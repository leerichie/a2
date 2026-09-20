import { createServer } from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createPublicKey, createVerify, randomBytes, randomUUID, scrypt as scryptCallback, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import * as foodCatalogue from './food_catalogue.mjs';
import * as exerciseCatalogue from './exercise_catalogue.mjs';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const publicDir = join(root, 'public');
const dataFile = join(process.env.DATA_DIR || join(root, 'data'), 'content.json');
const usersFile = join(process.env.DATA_DIR || join(root, 'data'), 'users.json');
const appUsersFile = join(process.env.DATA_DIR || join(root, 'data'), 'app-users.json');
const healthDataFile = join(process.env.DATA_DIR || join(root, 'data'), 'health-data.json');
const settingsFile = join(process.env.DATA_DIR || join(root, 'data'), 'settings.json');
const sessionsFile = join(process.env.DATA_DIR || join(root, 'data'), 'sessions.json');
const activityLogFile = join(process.env.DATA_DIR || join(root, 'data'), 'activity-log.json');
const mediaDir = join(process.env.DATA_DIR || join(root, 'data'), 'media');
const MAX_MEDIA_BYTES = 6_000_000;
const MAX_ACTIVITY_ENTRIES = 500;
const port = Number(process.env.PORT || 8787);
const initialAdminUser = process.env.INITIAL_ADMIN_USER || 'admin';
const initialAdminPassword = process.env.INITIAL_ADMIN_PASSWORD || '';
const scrypt = promisify(scryptCallback);
const sessions = new Map();
const appSessions = new Map();

// Rate limiting -- config centralized here (env-overridable), not scattered
// as magic numbers through the route handlers. Windows are short and
// counters simply expire and reset; there is deliberately no permanent or
// long-duration lockout, since a per-email limit with no expiry would let
// anyone lock a stranger out of their own account just by repeatedly
// guessing their email with a wrong password.
const RATE_LIMIT_CONFIG = {
  loginPerIp: {
    windowMs: Number(process.env.RATE_LIMIT_LOGIN_IP_WINDOW_MS) || 15 * 60 * 1000,
    max: Number(process.env.RATE_LIMIT_LOGIN_IP_MAX) || 20,
  },
  loginPerEmail: {
    windowMs: Number(process.env.RATE_LIMIT_LOGIN_EMAIL_WINDOW_MS) || 15 * 60 * 1000,
    max: Number(process.env.RATE_LIMIT_LOGIN_EMAIL_MAX) || 8,
  },
  registerPerIp: {
    windowMs: Number(process.env.RATE_LIMIT_REGISTER_IP_WINDOW_MS) || 60 * 60 * 1000,
    max: Number(process.env.RATE_LIMIT_REGISTER_IP_MAX) || 6,
  },
};

// The a2_default Docker network's own gateway address -- confirmed
// empirically 2026-09-20 (see docker inspect a2_content / a disposable
// echo-server test) to be the ONLY address hairpin (loopback-originated)
// traffic can ever appear to come from at this container's socket layer.
// cloudflared runs with --network host on the same physical box and
// proxies to http://localhost:8094, so genuine Cloudflare Tunnel traffic
// is indistinguishable from any other loopback-originated connection at
// the TCP layer -- Docker's own port-publishing NAT rewrites it to this
// gateway address. No real external caller (Tailscale, LAN, or anyone on
// the public internet) can ever make their own connection originate from
// Docker's internal gateway, so this is a safe, non-spoofable trust
// boundary: only a request whose raw socket address is exactly this one
// gets its client IP taken from Cloudflare's CF-Connecting-IP header.
// Every other caller's own raw socket address is used instead, and any
// CF-Connecting-IP header they send is ignored outright.
const TRUSTED_PROXY_IP = process.env.TRUSTED_PROXY_IP || '172.22.0.1';

const realClientIp = req => {
  const socketIp = (req.socket.remoteAddress || '').replace(/^::ffff:/, '');
  if (socketIp === TRUSTED_PROXY_IP) {
    const cfIp = req.headers['cf-connecting-ip'];
    if (typeof cfIp === 'string' && cfIp.trim()) return cfIp.trim();
  }
  return socketIp;
};

// Simple in-memory sliding-window counters, one Map entry per bucket key
// (e.g. "login:ip:1.2.3.4" or "login:email:someone@example.com"). Not
// shared across processes or restarts -- fine for this single-instance
// deployment, and a restart resetting everyone's counters to zero is the
// safe direction to fail in, never a lockout that outlives the thing that
// caused it. Swept periodically (see setInterval below) so long-idle keys
// don't accumulate forever.
const rateLimitBuckets = new Map();
const checkRateLimit = (bucketKey, {windowMs, max}) => {
  const now = Date.now();
  const bucket = rateLimitBuckets.get(bucketKey);
  if (!bucket || bucket.resetAt <= now) {
    rateLimitBuckets.set(bucketKey, {count: 1, resetAt: now + windowMs});
    return {limited: false};
  }
  bucket.count += 1;
  if (bucket.count > max) {
    return {limited: true, retryAfterSeconds: Math.max(1, Math.ceil((bucket.resetAt - now) / 1000))};
  }
  return {limited: false};
};
setInterval(() => {
  const now = Date.now();
  for (const [key, bucket] of rateLimitBuckets) if (bucket.resetAt <= now) rateLimitBuckets.delete(key);
}, 10 * 60 * 1000).unref();
// Returns a response and sets Retry-After if any of the given [bucketKey,
// limitConfig] pairs is currently over its limit -- checks every pair
// (rather than stopping at the first) so, e.g., a login attempt always
// counts against both its IP and email buckets even if the IP one alone
// would already have blocked it.
const enforceRateLimit = (res, checks) => {
  let worst = null;
  for (const [bucketKey, limitConfig] of checks) {
    const result = checkRateLimit(bucketKey, limitConfig);
    if (result.limited && (!worst || result.retryAfterSeconds > worst.retryAfterSeconds)) worst = result;
  }
  if (!worst) return false;
  res.setHeader('retry-after', String(worst.retryAfterSeconds));
  json(res, 429, {error: 'Too many requests. Please try again later.'});
  return true;
};
const loadPersistedSessions = async () => {
  try {
    const raw = JSON.parse(await readFile(sessionsFile, 'utf8'));
    const now = Date.now();
    for (const [token, session] of raw.sessions || []) if (session.expiresAt > now) sessions.set(token, session);
    for (const [token, session] of raw.appSessions || []) if (session.expiresAt > now) appSessions.set(token, session);
  } catch (error) {
    if (error.code !== 'ENOENT') console.error('Failed to load sessions', error);
  }
};
const persistSessions = async () => {
  try {
    await mkdir(dirname(sessionsFile), {recursive: true});
    await writeFile(sessionsFile, JSON.stringify({sessions: [...sessions.entries()], appSessions: [...appSessions.entries()]}), {mode: 0o600});
  } catch (error) {
    console.error('Failed to persist sessions', error);
  }
};
await loadPersistedSessions();
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, async () => { await persistSessions(); process.exit(0); });
}

const loadActivityLog = async () => {
  try { return JSON.parse(await readFile(activityLogFile, 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return []; throw error; }
};
const logActivity = async (session, message) => {
  try {
    const entries = await loadActivityLog();
    entries.unshift({
      id: randomUUID(),
      at: new Date().toISOString(),
      by: session ? session.username : 'system',
      message,
    });
    await mkdir(dirname(activityLogFile), {recursive: true});
    await writeFile(
      activityLogFile,
      JSON.stringify(entries.slice(0, MAX_ACTIVITY_ENTRIES), null, 2),
      {mode: 0o600},
    );
  } catch (error) {
    console.error('Failed to record activity', error);
  }
};

const json = (res, status, body) => {
  res.writeHead(status, {'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store'});
  res.end(JSON.stringify(body));
};
const localWebOrigin = origin => /^https?:\/\/(?:localhost|127\.0\.0\.1)(?::\d+)?$/.test(origin || '');
const allowLocalWebApp = (req, res) => {
  const origin = req.headers.origin;
  if (!localWebOrigin(origin)) return false;
  res.setHeader('access-control-allow-origin', origin);
  res.setHeader('vary', 'Origin');
  res.setHeader('access-control-allow-methods', 'GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS');
  res.setHeader('access-control-allow-headers', 'Authorization, Content-Type');
  res.setHeader('access-control-allow-private-network', 'true');
  return true;
};
const sessionFor = req => {
  const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  const session = sessions.get(token);
  if (!session || session.expiresAt < Date.now()) {
    if (token) sessions.delete(token);
    return null;
  }
  return {...session, token};
};
const readBody = async (req, maxBytes = 1_000_000) => {
  let raw = '';
  for await (const chunk of req) {
    raw += chunk;
    if (raw.length > maxBytes) throw new Error('Request too large');
  }
  return raw ? JSON.parse(raw) : {};
};
const load = async () => {
  try { return JSON.parse(await readFile(dataFile, 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return {drafts: [], releases: []}; throw error; }
};
const hashPassword = async (password, salt = randomBytes(16).toString('hex')) => {
  const hash = await scrypt(password, salt, 64);
  return `${salt}:${Buffer.from(hash).toString('hex')}`;
};
const verifyPassword = async (password, stored) => {
  const [salt, expectedHex] = String(stored || '').split(':');
  if (!salt || !expectedHex) return false;
  const actual = Buffer.from(await scrypt(password, salt, 64));
  const expected = Buffer.from(expectedHex, 'hex');
  return actual.length === expected.length && timingSafeEqual(actual, expected);
};
// Verifies a Firebase Auth ID token WITHOUT the firebase-admin SDK -- this
// server has no service account key (and doesn't need one just to verify
// tokens), so it does what firebase-admin itself does under the hood:
// fetch Google's public signing keys, check the RS256 signature, and
// validate the standard claims by hand. This keeps the "no framework,
// minimal dependencies" shape of the rest of this file rather than
// pulling in the full, heavy admin SDK for one narrow job.
const FIREBASE_PROJECT_ID = 'a2-platform';
let googlePublicKeysCache = {keys: null, expiresAt: 0};
const getGooglePublicKeys = async () => {
  if (googlePublicKeysCache.keys && googlePublicKeysCache.expiresAt > Date.now()) {
    return googlePublicKeysCache.keys;
  }
  const response = await fetch('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com');
  if (!response.ok) throw new Error('Failed to fetch Google public keys');
  const {keys} = await response.json();
  googlePublicKeysCache = {keys, expiresAt: Date.now() + 60 * 60 * 1000};
  return keys;
};
const base64UrlDecode = input => Buffer.from(input.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
async function verifyFirebaseIdToken(idToken) {
  const parts = String(idToken || '').split('.');
  if (parts.length !== 3) throw new Error('Malformed token');
  const header = JSON.parse(base64UrlDecode(parts[0]).toString('utf8'));
  const payload = JSON.parse(base64UrlDecode(parts[1]).toString('utf8'));
  if (header.alg !== 'RS256') throw new Error('Unexpected signing algorithm');
  const keys = await getGooglePublicKeys();
  const jwk = keys.find(key => key.kid === header.kid);
  if (!jwk) throw new Error('Unknown signing key');
  const publicKey = createPublicKey({key: jwk, format: 'jwk'});
  const signedData = `${parts[0]}.${parts[1]}`;
  const valid = createVerify('RSA-SHA256').update(signedData).verify(publicKey, base64UrlDecode(parts[2]));
  if (!valid) throw new Error('Invalid signature');
  const now = Math.floor(Date.now() / 1000);
  if (typeof payload.exp !== 'number' || payload.exp < now) throw new Error('Token expired');
  if (typeof payload.iat !== 'number' || payload.iat > now + 60) throw new Error('Token issued in the future');
  if (payload.aud !== FIREBASE_PROJECT_ID) throw new Error('Wrong audience');
  if (payload.iss !== `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`) throw new Error('Wrong issuer');
  if (!payload.sub) throw new Error('Missing subject');
  return {uid: payload.sub, email: payload.email, emailVerified: payload.email_verified === true, name: payload.name};
}

const saveUsers = async users => {
  await mkdir(dirname(usersFile), {recursive: true});
  await writeFile(usersFile, JSON.stringify({users}, null, 2), {mode: 0o600});
};
const loadUsers = async () => {
  try {
    return JSON.parse(await readFile(usersFile, 'utf8')).users || [];
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    if (!initialAdminPassword) throw new Error('INITIAL_ADMIN_PASSWORD is not configured');
    const users = [{id: randomUUID(), username: initialAdminUser, role: 'admin', passwordHash: await hashPassword(initialAdminPassword), createdAt: new Date().toISOString()}];
    await saveUsers(users);
    return users;
  }
};
const publicUser = user => ({id: user.id, username: user.username, role: user.role, createdAt: user.createdAt});
const validUsername = value => /^[A-Za-z0-9_.-]{3,32}$/.test(value || '');
const validPassword = value => typeof value === 'string' && value.length >= 8 && value.length <= 128;
const validEmail = value => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value || '');
const loadAppUsers = async () => {
  try { return JSON.parse(await readFile(appUsersFile, 'utf8')).users || []; }
  catch (error) { if (error.code === 'ENOENT') return []; throw error; }
};
const saveAppUsers = async users => {
  await mkdir(dirname(appUsersFile), {recursive: true});
  await writeFile(appUsersFile, JSON.stringify({users}, null, 2), {mode: 0o600});
};
// The A² shell's module registry -- the platform-wide list of modules
// that could exist, independent of which ones any given user is entitled
// to. `globalEnabled: false` hides a module from EVERY user regardless of
// their own per-user access, for staged rollouts (e.g. enabling something
// for admin/test accounts only via moduleAccess while it's still globally
// off for everyone else -- see defaultModuleAccess). Adding a future
// module (HorseVibe, CrewPilot, ...) is meant to be exactly one new entry
// here plus a per-user default in defaultModuleAccess, never a code
// change to the entitlements route itself.
const MODULE_REGISTRY = [
  {
    id: 'health',
    name: 'A² Health',
    description: 'Food, exercise, weight and photo tracking',
    icon: 'health',
    route: 'health',
    globalEnabled: true,
    minAppVersion: null,
  },
];
// Existing accounts predate the moduleAccess field entirely -- this is the
// fallback used everywhere a user record might not have one yet, so every
// current Health user keeps working through the shell migration with no
// admin action required. New modules default to false: being entitled to
// Health says nothing about being entitled to something added later.
const defaultModuleAccess = () => ({health: true});

const publicAppUser = user => ({id: user.id, email: user.email, name: user.name, role: user.role || 'user', blocked: user.blocked === true, privateSync: user.privateSync === true, aiEnabled: user.aiEnabled === true, entrySyncEnabled: user.entrySyncEnabled === true, linkedUserIds: user.linkedUserIds || [], googleLinked: user.googleLinked === true, createdAt: user.createdAt, membership: user.membership || 'basic', moduleAccess: {...defaultModuleAccess(), ...(user.moduleAccess || {})}});
const syncInvitesFile = join(process.env.DATA_DIR || join(root, 'data'), 'sync-invites.json');
const loadSyncInvites = async () => {
  try { return JSON.parse(await readFile(syncInvitesFile, 'utf8')).invites || []; }
  catch (error) { if (error.code === 'ENOENT') return []; throw error; }
};
const saveSyncInvites = async invites => {
  await mkdir(dirname(syncInvitesFile), {recursive: true});
  await writeFile(syncInvitesFile, JSON.stringify({invites}, null, 2), {mode: 0o600});
};
// A pending invite is only ever shown to its two participants, so it's safe
// to resolve their name/email for display here.
const publicInvite = (invite, users) => {
  const from = users.find(item => item.id === invite.fromUserId);
  const to = users.find(item => item.id === invite.toUserId);
  return {
    id: invite.id,
    fromUserId: invite.fromUserId,
    fromName: from?.name || '',
    fromEmail: from?.email || '',
    toUserId: invite.toUserId,
    toName: to?.name || '',
    toEmail: to?.email || '',
    createdAt: invite.createdAt,
  };
};
const loadServerSettings = async () => {
  try { return JSON.parse(await readFile(settingsFile, 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return {}; throw error; }
};
const saveServerSettings = async settings => {
  await mkdir(dirname(settingsFile), {recursive: true});
  await writeFile(settingsFile, JSON.stringify(settings, null, 2), {mode: 0o600});
};
const getOpenAiCredentials = async () => {
  const settings = await loadServerSettings();
  return {
    apiKey: settings.openaiApiKey || process.env.OPENAI_API_KEY || '',
    model: settings.openaiModel || process.env.OPENAI_MODEL || 'gpt-4o-mini',
  };
};
const decodeHealthPayload = record => {
  const payload = record?.payload || {};
  const settings = payload.settings || {};
  const parse = value => {
    if (typeof value !== 'string') return value ?? null;
    try { return JSON.parse(value); } catch { return null; }
  };
  return {
    updatedAt: record?.updatedAt || null,
    bodyProfile: parse(settings.bodyProfile),
    activeDietPlan: parse(settings.activeDietPlan),
    dailyTarget: settings.dailyTarget ?? null,
    dailyTargetCustom: settings.dailyTargetCustom === true,
    savedDietPlans: (settings.savedDietPlans || []).map(parse).filter(Boolean),
    dailyEntries: payload.dailyEntries || {},
    dailyWater: payload.dailyWater || {},
    waterTargetMl: settings.waterTargetMl ?? null,
    history: payload.history || {records: []},
  };
};
const loadHealthData = async () => {
  try { return JSON.parse(await readFile(healthDataFile, 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return {users: {}}; throw error; }
};
const saveHealthData = async data => {
  await mkdir(dirname(healthDataFile), {recursive: true});
  await writeFile(healthDataFile, JSON.stringify(data, null, 2), {mode: 0o600});
};
const appSessionFor = req => {
  const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  const session = appSessions.get(token);
  if (!session || session.expiresAt < Date.now()) { if (token) appSessions.delete(token); return null; }
  return {...session, token};
};
const targetMatches = (target, userId, deviceId, groups) =>
  target.type === 'all' ||
  (target.type === 'user' && target.ids.includes(userId)) ||
  (target.type === 'device' && target.ids.includes(deviceId)) ||
  (target.type === 'group' && target.ids.some(id => groups.includes(id)));

const NUTRITION_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    name: {type: 'string'},
    calories: {type: 'number'},
    protein: {type: 'number'},
    carbs: {type: 'number'},
    servingGrams: {type: 'number'},
  },
  required: ['name', 'calories', 'protein', 'carbs', 'servingGrams'],
};

// For 'recipe' mode: the text describes a BATCH (a recipe yielding several
// portions, a jug of several drinks, a workout made of several rounds) --
// this asks the model to do the batch-total-then-divide math itself and
// return one portion's worth, plus how many of those portions the text
// says were actually consumed, so the app can offer an editable "how many
// did you have?" step instead of guessing.
const RECIPE_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    name: {type: 'string'},
    totalPortions: {type: 'number'},
    consumedPortions: {type: 'number'},
    caloriesPerPortion: {type: 'number'},
    proteinPerPortion: {type: 'number'},
    carbsPerPortion: {type: 'number'},
    fatPerPortion: {type: 'number'},
    servingGramsPerPortion: {type: 'number'},
  },
  required: ['name', 'totalPortions', 'consumedPortions', 'caloriesPerPortion', 'proteinPerPortion', 'carbsPerPortion', 'fatPerPortion', 'servingGramsPerPortion'],
};

// `output_text` is a convenience property the official OpenAI SDK computes
// client-side -- it is NOT a field the Responses API actually returns over
// the wire, so a raw fetch() (as used here, with no SDK) never has it. The
// real answer lives in the `message`-type entry of the `output` array (a
// reasoning model's output can contain a `reasoning` entry too, so this
// can't just take output[0]). Confirmed live 2026-09-18: every call was
// silently failing on `JSON.parse(undefined)` since this was first built.
function extractOutputText(result) {
  const message = (result.output || []).find(item => item.type === 'message');
  return message?.content?.find(part => part.type === 'output_text')?.text;
}

const RECIPE_INSTRUCTIONS = {
  exercise: 'The user describes a workout made of repeated rounds/sets/circuits (e.g. "5 rounds of burpees and squats, 40s each with 20s rest"). Work out totalPortions: the number of rounds/sets described. Work out consumedPortions: how many of those the user actually completed -- equal to totalPortions unless the text explicitly says they did fewer (e.g. "only managed 3 of the 5"). caloriesPerPortion is the realistic calories burned for ONE round of the described work, given typical effort. Be conservative and realistic, never invent false precision. proteinPerPortion, carbsPerPortion, fatPerPortion and servingGramsPerPortion are always 0 for exercise.',
  food: 'The user describes a recipe or batch that yields multiple portions/servings (e.g. a recipe making 6 waffles, a jug of 4 cocktails), and may say how many of those portions they personally ate or drank. First work out the TOTAL nutrition of the entire batch from the listed ingredients/recipe, then divide by the number of portions the batch/recipe makes to get accurate per-portion figures -- do not just estimate one portion directly, do the batch-then-divide arithmetic. totalPortions is how many portions/servings/items the batch or recipe makes (e.g. 6 for "6 waffles", 4 for "4 cocktails"). consumedPortions is how many of those the text says were actually eaten/drunk (default to 1 if not stated). Give a short natural name for ONE portion (e.g. "Twaróg waffle"), not a description of the whole batch. Never invent false precision, but do the division carefully. servingGramsPerPortion is the realistic weight in grams of ONE portion.',
};

async function aiDescribe(kind, text, mode = 'single') {
  const {apiKey, model} = await getOpenAiCredentials();
  if (!apiKey) throw new Error('AI is not configured on this server');
  const recipeMode = mode === 'recipe';
  const schema = recipeMode ? RECIPE_SCHEMA : NUTRITION_SCHEMA;
  const instructions = recipeMode
    ? RECIPE_INSTRUCTIONS[kind === 'exercise' ? 'exercise' : 'food']
    : kind === 'exercise'
    ? 'Estimate calories burned for a described exercise session, given its duration. Be conservative and realistic, never invent false precision. Protein and carbs are always 0 for exercise. Set servingGrams to 0 for exercise.'
    : 'Estimate total nutrition for the described food or drink. It may list several distinct items (e.g. a fast-food order or a multi-part meal) — recognise each one, including named branded/restaurant items, and return the SUM of calories, protein and carbs across all of them, not just one. Account for any stated quantities (e.g. "2x", "large"). Assume typical realistic portion sizes when a quantity is vague; never invent false precision, but also never underestimate a clearly multi-item meal. Also return servingGrams: the total realistic weight in grams of the portion your calorie/protein/carb figures describe (summed across every item if there are several), so those figures can be recorded on a per-100g basis later.';
  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: {'authorization': `Bearer ${apiKey}`, 'content-type': 'application/json'},
    body: JSON.stringify({
      model,
      store: false,
      instructions,
      input: text,
      text: {format: {type: 'json_schema', name: recipeMode ? 'recipe_estimate' : 'nutrition_estimate', strict: true, schema}},
    }),
  });
  if (!response.ok) throw new Error(`AI request failed (${response.status})`);
  const result = await response.json();
  const outputText = extractOutputText(result);
  if (!outputText) {
    console.error('[aiDescribe] no message output:', JSON.stringify(result).slice(0, 2000));
    throw new Error('AI did not return an answer');
  }
  return JSON.parse(outputText);
}

async function aiVision(kind, imageBase64, mimeType) {
  const {apiKey, model} = await getOpenAiCredentials();
  if (!apiKey) throw new Error('AI is not configured on this server');
  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: {'authorization': `Bearer ${apiKey}`, 'content-type': 'application/json'},
    body: JSON.stringify({
      model,
      store: false,
      instructions: kind === 'label_photo'
        ? 'Read the nutrition facts label shown in the photo and extract calories, protein and carbohydrates for one serving. If a value is unreadable, estimate conservatively rather than inventing false precision. Also read or estimate servingGrams: the weight in grams of the one serving the label describes.'
        : 'Identify the food or drink shown in the photo and estimate its nutrition for the visible portion. Never invent false precision. Also return servingGrams: the realistic weight in grams of the visible portion your figures describe.',
      input: [{
        role: 'user',
        content: [
          {type: 'input_text', text: kind === 'label_photo' ? 'Read this nutrition label.' : 'What food or drink is this, and roughly how much does it contain?'},
          {type: 'input_image', image_url: `data:${mimeType};base64,${imageBase64}`},
        ],
      }],
      text: {format: {type: 'json_schema', name: 'nutrition_estimate', strict: true, schema: NUTRITION_SCHEMA}},
    }),
  });
  if (!response.ok) throw new Error(`AI vision request failed (${response.status})`);
  const result = await response.json();
  const outputText = extractOutputText(result);
  if (!outputText) {
    console.error('[aiVision] no message output:', JSON.stringify(result).slice(0, 2000));
    throw new Error('AI did not return an answer');
  }
  return JSON.parse(outputText);
}

const server = createServer(async (req, res) => {
  const localWebAllowed = allowLocalWebApp(req, res);
  if (req.method === 'OPTIONS') {
    res.writeHead(localWebAllowed ? 204 : 403, {'cache-control': 'no-store'});
    return res.end();
  }
  try {
    const url = new URL(req.url, `http://${req.headers.host}`);
    if (req.method === 'GET' && url.pathname === '/health') return json(res, 200, {ok: true});
    if (req.method === 'POST' && url.pathname === '/api/v1/auth/register') {
      const clientIp = realClientIp(req);
      if (enforceRateLimit(res, [[`register:ip:${clientIp}`, RATE_LIMIT_CONFIG.registerPerIp]])) return;
      const {email, password, name = ''} = await readBody(req);
      const normalEmail = String(email || '').trim().toLowerCase();
      if (!validEmail(normalEmail)) return json(res, 400, {error: 'Enter a valid email address'});
      if (!validPassword(password)) return json(res, 400, {error: 'Password must be at least 8 characters'});
      const users = await loadAppUsers();
      if (users.some(item => item.email === normalEmail)) return json(res, 409, {error: 'An account already exists for this email'});
      const user = {id: randomUUID(), email: normalEmail, name: String(name).trim().slice(0, 60), role: 'user', blocked: false, privateSync: false, aiEnabled: false, passwordHash: await hashPassword(password), createdAt: new Date().toISOString()};
      users.push(user); await saveAppUsers(users);
      const token = randomBytes(32).toString('hex');
      appSessions.set(token, {userId: user.id, expiresAt: Date.now() + 30 * 24 * 60 * 60 * 1000});
      return json(res, 201, {token, user: publicAppUser(user)});
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/auth/login') {
      const clientIp = realClientIp(req);
      if (enforceRateLimit(res, [[`login:ip:${clientIp}`, RATE_LIMIT_CONFIG.loginPerIp]])) return;
      const {email, password} = await readBody(req);
      const normalEmail = String(email || '').trim().toLowerCase();
      if (normalEmail && enforceRateLimit(res, [[`login:email:${normalEmail}`, RATE_LIMIT_CONFIG.loginPerEmail]])) return;
      const users = await loadAppUsers();
      const user = users.find(item => item.email === normalEmail);
      if (!user || !(await verifyPassword(password, user.passwordHash))) return json(res, 401, {error: 'Incorrect email or password'});
      if (user.blocked === true) return json(res, 403, {error: 'This account has been blocked'});
      const token = randomBytes(32).toString('hex');
      appSessions.set(token, {userId: user.id, expiresAt: Date.now() + 30 * 24 * 60 * 60 * 1000});
      return json(res, 200, {token, user: publicAppUser(user)});
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/auth/google') {
      const googleClientId = process.env.GOOGLE_CLIENT_ID || '';
      if (!googleClientId) return json(res, 501, {error: 'Google sign-in is not configured on this server'});
      const {idToken} = await readBody(req);
      if (!idToken) return json(res, 400, {error: 'Missing Google ID token'});
      let payload;
      try {
        const verifyResponse = await fetch(
          `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`,
        );
        if (!verifyResponse.ok) return json(res, 401, {error: 'Could not verify Google sign-in'});
        payload = await verifyResponse.json();
      } catch (error) {
        return json(res, 502, {error: 'Could not reach Google to verify sign-in'});
      }
      // The token must have been issued FOR this app's own client ID, not
      // just any Google sign-in anywhere -- otherwise a token minted for a
      // different app would also be accepted here.
      if (payload.aud !== googleClientId) return json(res, 401, {error: 'Google sign-in token was not issued for this app'});
      if (payload.email_verified !== 'true' && payload.email_verified !== true) {
        return json(res, 401, {error: 'Google account email is not verified'});
      }
      const normalEmail = String(payload.email || '').trim().toLowerCase();
      if (!validEmail(normalEmail)) return json(res, 401, {error: 'Google account has no usable email'});
      const users = await loadAppUsers();
      let user = users.find(item => item.email === normalEmail);
      if (!user) {
        user = {
          id: randomUUID(), email: normalEmail, name: String(payload.name || '').trim().slice(0, 60),
          role: 'user', blocked: false, privateSync: false, aiEnabled: false,
          // A Google-linked account signs in via Google only -- this hash
          // never matches any password, so /auth/login can't be used for it.
          passwordHash: await hashPassword(randomBytes(32).toString('hex')),
          googleLinked: true, createdAt: new Date().toISOString(),
        };
        users.push(user);
      } else if (user.blocked === true) {
        return json(res, 403, {error: 'This account has been blocked'});
      } else {
        user.googleLinked = true;
      }
      await saveAppUsers(users);
      const token = randomBytes(32).toString('hex');
      appSessions.set(token, {userId: user.id, expiresAt: Date.now() + 30 * 24 * 60 * 60 * 1000});
      return json(res, 200, {token, user: publicAppUser(user)});
    }
    // The shared A² identity bridge: Firebase Auth (Apple/Google/email,
    // whichever provider the user actually used) only ever proves who
    // someone is -- this endpoint is what turns that into an A² account
    // and this server's own session token, which is the only thing every
    // other route (sync, AI, entitlements) ever checks. An existing
    // account is matched and linked by email, never overwritten; a new
    // one is created exactly like a direct email/password registration
    // would, just with no usable password of its own (mirrors how the
    // Google-only branch above already does this).
    if (req.method === 'POST' && url.pathname === '/api/v1/auth/firebase') {
      const clientIp = realClientIp(req);
      if (enforceRateLimit(res, [[`firebase-auth:ip:${clientIp}`, RATE_LIMIT_CONFIG.loginPerIp]])) return;
      const {idToken} = await readBody(req);
      if (!idToken) return json(res, 400, {error: 'A Firebase ID token is required'});
      let decoded;
      try {
        decoded = await verifyFirebaseIdToken(idToken);
      } catch (error) {
        return json(res, 401, {error: 'Invalid or expired sign-in token'});
      }
      const normalEmail = String(decoded.email || '').trim().toLowerCase();
      if (!validEmail(normalEmail)) return json(res, 400, {error: 'This sign-in method did not provide a usable email address'});
      const users = await loadAppUsers();
      let user = users.find(item => item.email === normalEmail);
      const isNewUser = !user;
      if (!user) {
        user = {
          id: randomUUID(), email: normalEmail, name: String(decoded.name || '').trim().slice(0, 60),
          role: 'user', blocked: false, privateSync: false, aiEnabled: false, entrySyncEnabled: false, linkedUserIds: [],
          passwordHash: await hashPassword(randomBytes(32).toString('hex')),
          firebaseUid: decoded.uid, createdAt: new Date().toISOString(),
        };
        users.push(user);
      } else if (user.blocked === true) {
        return json(res, 403, {error: 'This account has been blocked'});
      } else {
        user.firebaseUid = decoded.uid;
      }
      await saveAppUsers(users);
      const token = randomBytes(32).toString('hex');
      appSessions.set(token, {userId: user.id, expiresAt: Date.now() + 30 * 24 * 60 * 60 * 1000});
      await logActivity({username: user.name || user.email}, `${user.email} signed in via Firebase${isNewUser ? ' (new account)' : ''}`);
      return json(res, isNewUser ? 201 : 200, {token, user: publicAppUser(user)});
    }
    if (url.pathname.startsWith('/api/v1/auth/')) {
      const appSession = appSessionFor(req);
      if (!appSession) return json(res, 401, {error: 'Unauthorized'});
      if (req.method === 'GET' && url.pathname === '/api/v1/auth/me') {
        const user = (await loadAppUsers()).find(item => item.id === appSession.userId);
        return user ? json(res, 200, {user: publicAppUser(user)}) : json(res, 401, {error: 'Account no longer exists'});
      }
      // The A² shell's dashboard renders exactly what this returns and
      // nothing else -- a module absent from this list must not appear as
      // a locked/greyed-out card, it must not appear at all. A module only
      // shows when it's globally enabled AND this specific account has it
      // switched on; membership level never implies module access on its
      // own (see MODULE_REGISTRY/defaultModuleAccess above).
      if (req.method === 'GET' && url.pathname === '/api/v1/auth/entitlements') {
        const user = (await loadAppUsers()).find(item => item.id === appSession.userId);
        if (!user) return json(res, 401, {error: 'Account no longer exists'});
        if (user.blocked === true) return json(res, 403, {error: 'This account has been blocked'});
        const moduleAccess = {...defaultModuleAccess(), ...(user.moduleAccess || {})};
        const modules = MODULE_REGISTRY
          .filter(module => module.globalEnabled && moduleAccess[module.id] === true)
          .map(module => ({id: module.id, name: module.name, description: module.description, icon: module.icon, route: module.route}));
        return json(res, 200, {membership: user.membership || 'basic', aiEnabled: user.aiEnabled === true, modules});
      }
      if (req.method === 'POST' && url.pathname === '/api/v1/auth/logout') {
        appSessions.delete(appSession.token); return json(res, 200, {ok: true});
      }
      if (req.method === 'POST' && url.pathname === '/api/v1/auth/password') {
        const {currentPassword, newPassword} = await readBody(req);
        if (!validPassword(newPassword)) return json(res, 400, {error: 'New password must be at least 8 characters'});
        const users = await loadAppUsers();
        const user = users.find(item => item.id === appSession.userId);
        if (!user) return json(res, 401, {error: 'Account no longer exists'});
        if (!(await verifyPassword(currentPassword, user.passwordHash))) {
          return json(res, 401, {error: 'Current password is incorrect'});
        }
        user.passwordHash = await hashPassword(newPassword);
        await saveAppUsers(users);
        return json(res, 200, {ok: true});
      }
      if (req.method === 'PATCH' && url.pathname === '/api/v1/auth/link') {
        const {entrySyncEnabled} = await readBody(req);
        const users = await loadAppUsers();
        const user = users.find(item => item.id === appSession.userId);
        if (!user) return json(res, 401, {error: 'Account no longer exists'});
        if (typeof entrySyncEnabled === 'boolean') user.entrySyncEnabled = entrySyncEnabled;
        await saveAppUsers(users);
        return json(res, 200, {user: publicAppUser(user)});
      }
      // Only people you've mutually confirmed a sync invite with — never a
      // directory of every registered account's email address.
      if (req.method === 'GET' && url.pathname === '/api/v1/auth/link/partners') {
        const users = await loadAppUsers();
        const user = users.find(item => item.id === appSession.userId);
        if (!user) return json(res, 401, {error: 'Account no longer exists'});
        const partners = (user.linkedUserIds || [])
          .map(id => users.find(item => item.id === id && item.blocked !== true))
          .filter(Boolean)
          .map(item => ({id: item.id, name: item.name, email: item.email}));
        return json(res, 200, {partners});
      }
      if (req.method === 'GET' && url.pathname === '/api/v1/auth/link/invites') {
        const users = await loadAppUsers();
        const invites = await loadSyncInvites();
        const incoming = invites.filter(item => item.toUserId === appSession.userId).map(item => publicInvite(item, users));
        const outgoing = invites.filter(item => item.fromUserId === appSession.userId).map(item => publicInvite(item, users));
        return json(res, 200, {incoming, outgoing});
      }
      if (req.method === 'POST' && url.pathname === '/api/v1/auth/link/invites') {
        const {email} = await readBody(req);
        const normalEmail = String(email || '').trim().toLowerCase();
        if (!validEmail(normalEmail)) return json(res, 400, {error: 'Enter a valid email address'});
        const users = await loadAppUsers();
        const me = users.find(item => item.id === appSession.userId);
        if (!me) return json(res, 401, {error: 'Account no longer exists'});
        if (normalEmail === me.email) return json(res, 400, {error: 'You can’t invite yourself'});
        const target = users.find(item => item.email === normalEmail && item.blocked !== true);
        if (!target) return json(res, 404, {error: 'No account found for this email'});
        if ((me.linkedUserIds || []).includes(target.id)) return json(res, 400, {error: 'You’re already linked with this person'});
        const invites = await loadSyncInvites();
        if (invites.some(item => item.fromUserId === me.id && item.toUserId === target.id)) {
          return json(res, 400, {error: 'Invite already sent — waiting for them to confirm'});
        }
        // They already invited me — confirming mutually right away instead of
        // leaving two redundant one-way invites pending.
        const reverse = invites.find(item => item.fromUserId === target.id && item.toUserId === me.id);
        if (reverse) {
          me.linkedUserIds = [...new Set([...(me.linkedUserIds || []), target.id])];
          target.linkedUserIds = [...new Set([...(target.linkedUserIds || []), me.id])];
          await saveAppUsers(users);
          await saveSyncInvites(invites.filter(item => item.id !== reverse.id));
          return json(res, 200, {linked: true});
        }
        const invite = {id: randomUUID(), fromUserId: me.id, toUserId: target.id, createdAt: new Date().toISOString()};
        invites.push(invite);
        await saveSyncInvites(invites);
        return json(res, 201, {invite: publicInvite(invite, users)});
      }
      if (req.method === 'POST' && /^\/api\/v1\/auth\/link\/invites\/[^/]+\/(accept|decline)$/.test(url.pathname)) {
        const parts = url.pathname.split('/');
        const id = parts[6];
        const accept = parts[7] === 'accept';
        const invites = await loadSyncInvites();
        const invite = invites.find(item => item.id === id);
        if (!invite || invite.toUserId !== appSession.userId) return json(res, 404, {error: 'Invite not found'});
        if (accept) {
          const users = await loadAppUsers();
          const me = users.find(item => item.id === invite.toUserId);
          const from = users.find(item => item.id === invite.fromUserId);
          if (!me || !from) return json(res, 404, {error: 'Account no longer exists'});
          me.linkedUserIds = [...new Set([...(me.linkedUserIds || []), from.id])];
          from.linkedUserIds = [...new Set([...(from.linkedUserIds || []), me.id])];
          await saveAppUsers(users);
        }
        await saveSyncInvites(invites.filter(item => item.id !== id));
        return json(res, 200, {ok: true});
      }
      if (req.method === 'DELETE' && /^\/api\/v1\/auth\/link\/invites\/[^/]+$/.test(url.pathname)) {
        const id = url.pathname.split('/')[6];
        const invites = await loadSyncInvites();
        const invite = invites.find(item => item.id === id);
        if (!invite || invite.fromUserId !== appSession.userId) return json(res, 404, {error: 'Invite not found'});
        await saveSyncInvites(invites.filter(item => item.id !== id));
        return json(res, 200, {ok: true});
      }
      if (req.method === 'DELETE' && /^\/api\/v1\/auth\/link\/[^/]+$/.test(url.pathname)) {
        const targetId = url.pathname.split('/')[5];
        const users = await loadAppUsers();
        const me = users.find(item => item.id === appSession.userId);
        if (!me) return json(res, 401, {error: 'Account no longer exists'});
        me.linkedUserIds = (me.linkedUserIds || []).filter(id => id !== targetId);
        const target = users.find(item => item.id === targetId);
        if (target) target.linkedUserIds = (target.linkedUserIds || []).filter(id => id !== me.id);
        await saveAppUsers(users);
        return json(res, 200, {user: publicAppUser(me)});
      }
      if (req.method === 'DELETE' && url.pathname === '/api/v1/auth/account') {
        const users = await loadAppUsers();
        await saveAppUsers(users.filter(item => item.id !== appSession.userId));
        for (const [token, item] of appSessions) if (item.userId === appSession.userId) appSessions.delete(token);
        return json(res, 200, {ok: true});
      }
      if (url.pathname === '/api/v1/auth/sync') {
        const users = await loadAppUsers();
        const user = users.find(item => item.id === appSession.userId);
        if (!user || user.blocked === true) return json(res, 403, {error: 'Account access is blocked'});
        if (user.privateSync !== true) return json(res, 403, {error: 'Private sync is not enabled for this account'});
        if (req.method === 'GET') {
          const data = await loadHealthData();
          return json(res, 200, {data: data.users[appSession.userId] || null});
        }
        if (req.method === 'PUT') {
          const body = await readBody(req);
          const data = await loadHealthData();
          // A device's upload always sends its whole local payload, which can't
          // yet know about an entry another user just shared into this account
          // server-side (see /api/v1/entries/share) — keep any such entry this
          // upload doesn't already have, per day, instead of dropping it.
          const existingDaily = data.users[appSession.userId]?.payload?.dailyEntries || {};
          const incomingDaily = body.payload?.dailyEntries || {};
          const deletedDaily = Array.isArray(body.payload?.deletedDailyEntries) ? body.payload.deletedDailyEntries : [];
          const wasDeleted = (key, item) => deletedDaily.some(deletion => {
            if (deletion?.dateKey !== key || !deletion.entry) return false;
            const removed = deletion.entry;
            if (item.sharedEntryId && removed.sharedEntryId) return item.sharedEntryId === removed.sharedEntryId;
            return ['name', 'time', 'calories', 'protein', 'carbs', 'sharedFrom']
              .every(field => (item[field] ?? null) === (removed[field] ?? null));
          });
          const mergedDaily = {...incomingDaily};
          for (const [key, existingList] of Object.entries(existingDaily)) {
            const incomingList = incomingDaily[key] || [];
            const incomingSerialized = new Set(incomingList.map(item => JSON.stringify(item)));
            const missingShared = (existingList || []).filter(item => item?.sharedFrom && !incomingSerialized.has(JSON.stringify(item)) && !wasDeleted(key, item));
            if (missingShared.length) mergedDaily[key] = [...incomingList, ...missingShared];
          }
          const mergedPayload = {...(body.payload || {}), dailyEntries: mergedDaily};
          data.users[appSession.userId] = {payload: mergedPayload, updatedAt: new Date().toISOString()};
          await saveHealthData(data);
          return json(res, 200, {ok: true, updatedAt: data.users[appSession.userId].updatedAt});
        }
      }
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/entries/share') {
      const appSession = appSessionFor(req);
      if (!appSession) return json(res, 401, {error: 'Unauthorized'});
      const users = await loadAppUsers();
      const user = users.find(item => item.id === appSession.userId);
      if (!user || user.blocked === true) return json(res, 403, {error: 'Account access is blocked'});
      if (user.entrySyncEnabled !== true) return json(res, 400, {error: 'Entry sync is turned off in Settings'});
      const targetIds = (user.linkedUserIds || []).filter(id => users.some(item => item.id === id && item.blocked !== true));
      if (!targetIds.length) return json(res, 400, {error: 'No one is linked to sync entries with yet'});
      const {date, entry} = await readBody(req);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date || '') || !entry || typeof entry !== 'object') {
        return json(res, 400, {error: 'A date and entry are required'});
      }
      const data = await loadHealthData();
      const key = `daily_entries_${date}`;
      // `photoPaths` is a filesystem path local to the sender's own device --
      // it means nothing on the recipient's device and must never be
      // propagated (see photoMediaIds / /api/v1/media, which is how a synced
      // photo actually travels). Stripped here too as defense-in-depth, in
      // case an older client still sends it.
      const {photoPaths: _senderLocalPhotoPaths, ...entryWithoutLocalPaths} = entry;
      const sharedEntry = {...entryWithoutLocalPaths, sharedFrom: user.name || user.email, sharedEntryId: randomUUID()};
      for (const targetId of targetIds) {
        const existing = data.users[targetId]?.payload || {};
        const dailyEntries = {...(existing.dailyEntries || {})};
        dailyEntries[key] = [...(dailyEntries[key] || []), sharedEntry];
        data.users[targetId] = {payload: {...existing, dailyEntries}, updatedAt: new Date().toISOString()};
      }
      await saveHealthData(data);
      const targetNames = targetIds.map(id => { const t = users.find(item => item.id === id); return t?.name || t?.email || id; });
      await logActivity({username: user.name || user.email}, `${user.name || user.email} shared "${entry.name || 'an entry'}" with ${targetNames.join(', ')}`);
      return json(res, 200, {shared: targetIds});
    }
    // Backend-held photo storage for anything that crosses a device boundary
    // (a synced/shared entry's attached photo, or a standalone day photo).
    // The diary JSON itself only ever carries the returned id
    // (photoMediaIds) -- never base64/bytes -- so payloads stay small; the
    // actual bytes live here, fetched once per device and cached locally.
    if (req.method === 'POST' && url.pathname === '/api/v1/media') {
      const appSession = appSessionFor(req);
      if (!appSession) return json(res, 401, {error: 'Unauthorized'});
      const {mimeType, dataBase64} = await readBody(req, 8_000_000);
      const extForMime = {'image/jpeg': 'jpg', 'image/jpg': 'jpg', 'image/png': 'png', 'image/webp': 'webp'};
      const ext = extForMime[mimeType];
      if (!ext || !dataBase64 || typeof dataBase64 !== 'string') {
        return json(res, 400, {error: 'A supported image and its data are required'});
      }
      const buffer = Buffer.from(dataBase64, 'base64');
      if (buffer.length === 0 || buffer.length > MAX_MEDIA_BYTES) {
        return json(res, 413, {error: 'Photo is too large'});
      }
      const id = randomUUID();
      await mkdir(mediaDir, {recursive: true});
      await writeFile(join(mediaDir, `${id}.${ext}`), buffer, {mode: 0o600});
      await writeFile(
        join(mediaDir, `${id}.meta.json`),
        JSON.stringify({mimeType, ownerId: appSession.userId, createdAt: new Date().toISOString()}),
        {mode: 0o600},
      );
      return json(res, 200, {id});
    }
    const mediaMatch = req.method === 'GET' ? url.pathname.match(/^\/api\/v1\/media\/([A-Za-z0-9-]+)$/) : null;
    if (mediaMatch) {
      const appSession = appSessionFor(req);
      if (!appSession) return json(res, 401, {error: 'Unauthorized'});
      try {
        const meta = JSON.parse(await readFile(join(mediaDir, `${mediaMatch[1]}.meta.json`), 'utf8'));
        const ext = {'image/jpeg': 'jpg', 'image/jpg': 'jpg', 'image/png': 'png', 'image/webp': 'webp'}[meta.mimeType] || 'jpg';
        const buffer = await readFile(join(mediaDir, `${mediaMatch[1]}.${ext}`));
        res.writeHead(200, {
          'content-type': meta.mimeType,
          'cache-control': 'private, max-age=31536000, immutable',
          'content-length': buffer.length,
        });
        return res.end(buffer);
      } catch (error) {
        if (error.code === 'ENOENT') return json(res, 404, {error: 'Photo not found'});
        throw error;
      }
    }
    // The global food catalogue -- built-in app data stays bundled in the
    // app itself; this is the delta layer (admin imports + user
    // contributions) every app instance can pull without an app-store
    // release. Version/changes are unauthenticated (shared reference data,
    // not personal); contributing requires a signed-in app account so
    // additions carry real provenance.
    if (req.method === 'GET' && url.pathname === '/api/v1/catalogue/version') {
      const meta = await foodCatalogue.loadMeta();
      return json(res, 200, {version: meta.version});
    }
    if (req.method === 'GET' && url.pathname === '/api/v1/catalogue/changes') {
      const since = Number(url.searchParams.get('since') || '0');
      const result = await foodCatalogue.getChangesSince(Number.isFinite(since) ? since : 0);
      return json(res, 200, result);
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/catalogue/contribute') {
      const appSession = appSessionFor(req);
      if (!appSession) return json(res, 401, {error: 'Unauthorized'});
      const users = await loadAppUsers();
      const user = users.find(item => item.id === appSession.userId);
      if (!user || user.blocked === true) return json(res, 403, {error: 'Account access is blocked'});
      const body = await readBody(req);
      if (!String(body.name || '').trim()) return json(res, 400, {error: 'A food name is required'});
      if (body.kcal == null || body.kcal === '') return json(res, 400, {error: 'Calories are required'});
      const result = await foodCatalogue.contributeFood({
        name: body.name,
        locale: body.locale,
        category: body.category,
        kcal: body.kcal,
        protein: body.protein,
        carbs: body.carbs,
        fat: body.fat,
        fibre: body.fibre,
        basis: body.basis,
        servingAmount: body.servingAmount,
        servingUnit: body.servingUnit,
        createdBy: user.id,
      });
      if (result.status === 'invalid') return json(res, 400, {error: result.reason});
      if (result.status === 'created') {
        await logActivity({username: user.name || user.email}, `${user.name || user.email} contributed "${body.name}" to the global food catalogue`);
      }
      return json(res, 200, result);
    }
    // The global exercise-activity catalogue -- same delta-layer role as
    // the food catalogue above, but activities only ever arrive one at a
    // time (an AI-derived MET for something local didn't recognize), never
    // via bulk admin import.
    if (req.method === 'GET' && url.pathname === '/api/v1/exercise-catalogue/version') {
      const meta = await exerciseCatalogue.loadMeta();
      return json(res, 200, {version: meta.version});
    }
    if (req.method === 'GET' && url.pathname === '/api/v1/exercise-catalogue/changes') {
      const since = Number(url.searchParams.get('since') || '0');
      const result = await exerciseCatalogue.getChangesSince(Number.isFinite(since) ? since : 0);
      return json(res, 200, result);
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/exercise-catalogue/contribute') {
      const appSession = appSessionFor(req);
      if (!appSession) return json(res, 401, {error: 'Unauthorized'});
      const users = await loadAppUsers();
      const user = users.find(item => item.id === appSession.userId);
      if (!user || user.blocked === true) return json(res, 403, {error: 'Account access is blocked'});
      const body = await readBody(req);
      if (!String(body.name || '').trim()) return json(res, 400, {error: 'An activity name is required'});
      if (body.met == null || body.met === '') return json(res, 400, {error: 'A MET value is required'});
      const result = await exerciseCatalogue.contributeActivity({
        name: body.name,
        locale: body.locale,
        category: body.category,
        met: body.met,
        createdBy: user.id,
      });
      if (result.status === 'invalid') return json(res, 400, {error: result.reason});
      if (result.status === 'created') {
        await logActivity({username: user.name || user.email}, `${user.name || user.email} contributed "${body.name}" to the global exercise catalogue`);
      }
      return json(res, 200, result);
    }
    if (url.pathname.startsWith('/api/v1/ai/')) {
      const appSession = appSessionFor(req);
      if (!appSession) return json(res, 401, {error: 'Unauthorized'});
      const aiUser = (await loadAppUsers()).find(item => item.id === appSession.userId);
      if (!aiUser || aiUser.blocked === true) return json(res, 403, {error: 'Account access is blocked'});
      if (aiUser.aiEnabled !== true) return json(res, 403, {error: 'AI features are not enabled for this account'});
      const {apiKey} = await getOpenAiCredentials();
      if (!apiKey) return json(res, 503, {error: 'AI is not configured on this server'});
      if (req.method === 'POST' && url.pathname === '/api/v1/ai/describe') {
        const {kind, text, mode} = await readBody(req);
        if (!['food', 'drink', 'exercise'].includes(kind) || !text?.trim()) {
          return json(res, 400, {error: 'A kind and description are required'});
        }
        if (mode !== undefined && mode !== 'single' && mode !== 'recipe') {
          return json(res, 400, {error: 'Invalid mode'});
        }
        try {
          return json(res, 200, await aiDescribe(kind, text.trim(), mode || 'single'));
        } catch (error) {
          return json(res, 502, {error: error.message || 'AI request failed'});
        }
      }
      if (req.method === 'POST' && url.pathname === '/api/v1/ai/vision') {
        const {kind, imageBase64, mimeType} = await readBody(req, 6_000_000);
        if (!['meal_photo', 'label_photo'].includes(kind) || !imageBase64) {
          return json(res, 400, {error: 'A photo is required'});
        }
        try {
          return json(res, 200, await aiVision(kind, imageBase64, mimeType || 'image/jpeg'));
        } catch (error) {
          return json(res, 502, {error: error.message || 'AI request failed'});
        }
      }
    }
    if (req.method === 'GET' && url.pathname === '/api/v1/content') {
      const userId = url.searchParams.get('userId') || '';
      const deviceId = url.searchParams.get('deviceId') || '';
      const groups = (url.searchParams.get('groups') || '').split(',').filter(Boolean);
      const data = await load();
      const releases = data.releases.filter(item => item.status === 'published' && targetMatches(item.target, userId, deviceId, groups));
      return json(res, 200, {schemaVersion: 1, checkedAt: new Date().toISOString(), releases});
    }
    if (req.method === 'POST' && url.pathname === '/admin/api/login') {
      const {username, password} = await readBody(req);
      const users = await loadUsers();
      const user = users.find(item => item.username.toLowerCase() === String(username || '').toLowerCase());
      if (!user || !(await verifyPassword(password, user.passwordHash))) return json(res, 401, {error: 'Incorrect username or password'});
      const token = randomBytes(32).toString('hex');
      const newSession = {userId: user.id, username: user.username, role: user.role, expiresAt: Date.now() + 12 * 60 * 60 * 1000};
      sessions.set(token, newSession);
      await logActivity(newSession, `${user.username} signed in to the console`);
      return json(res, 200, {token, user: publicUser(user)});
    }
    const session = url.pathname.startsWith('/admin/api/') ? sessionFor(req) : null;
    if (url.pathname.startsWith('/admin/api/') && !session) return json(res, 401, {error: 'Unauthorized'});
    if (session && session.role !== 'admin' && req.method !== 'GET' && url.pathname !== '/admin/api/logout') {
      return json(res, 403, {error: 'Your account has view-only access'});
    }
    if (req.method === 'POST' && url.pathname === '/admin/api/logout') {
      sessions.delete(session.token);
      return json(res, 200, {ok: true});
    }
    if (req.method === 'GET' && url.pathname === '/admin/api/me') {
      return json(res, 200, {
        user: {
          id: session.userId,
          username: session.username,
          role: session.role,
        },
      });
    }
    if (req.method === 'GET' && url.pathname === '/admin/api/activity') {
      return json(res, 200, {entries: await loadActivityLog()});
    }
    if (req.method === 'GET' && url.pathname === '/admin/api/users') {
      const users = await loadUsers();
      return json(res, 200, {users: users.map(publicUser)});
    }
    if (req.method === 'GET' && url.pathname === '/admin/api/app-users') {
      return json(res, 200, {users: (await loadAppUsers()).map(publicAppUser)});
    }
    if (req.method === 'GET' && url.pathname === '/admin/api/modules') {
      return json(res, 200, {modules: MODULE_REGISTRY});
    }
    if (req.method === 'POST' && url.pathname === '/admin/api/app-users') {
      const {email, password, name = ''} = await readBody(req);
      const normalEmail = String(email || '').trim().toLowerCase();
      if (!validEmail(normalEmail)) return json(res, 400, {error: 'Enter a valid email address'});
      if (!validPassword(password)) return json(res, 400, {error: 'Password must be at least 8 characters'});
      const users = await loadAppUsers();
      if (users.some(item => item.email === normalEmail)) return json(res, 409, {error: 'An app account already exists for this email'});
      const user = {id: randomUUID(), email: normalEmail, name: String(name).trim().slice(0, 60), role: 'user', blocked: false, privateSync: false, aiEnabled: false, entrySyncEnabled: false, linkedUserIds: [], passwordHash: await hashPassword(password), createdAt: new Date().toISOString()};
      users.push(user); await saveAppUsers(users);
      await logActivity(session, `${session.username} added app user ${normalEmail} from the console`);
      return json(res, 201, {user: publicAppUser(user)});
    }
    const appUserMatch = url.pathname.match(/^\/admin\/api\/app-users\/([^/]+)$/);
    if (appUserMatch && req.method === 'PATCH') {
      const changes = await readBody(req);
      const users = await loadAppUsers();
      const user = users.find(item => item.id === appUserMatch[1]);
      if (!user) return json(res, 404, {error: 'App user not found'});
      if (typeof changes.name === 'string') user.name = changes.name.trim().slice(0, 60);
      if (typeof changes.blocked === 'boolean') user.blocked = changes.blocked;
      if (typeof changes.privateSync === 'boolean') user.privateSync = changes.privateSync;
      if (typeof changes.aiEnabled === 'boolean') user.aiEnabled = changes.aiEnabled;
      if (changes.moduleAccess && typeof changes.moduleAccess === 'object') {
        const nextAccess = {...defaultModuleAccess(), ...(user.moduleAccess || {})};
        for (const [moduleId, enabled] of Object.entries(changes.moduleAccess)) {
          if (typeof enabled !== 'boolean' || !MODULE_REGISTRY.some(module => module.id === moduleId)) {
            return json(res, 400, {error: `Unknown module or invalid value: ${moduleId}`});
          }
          nextAccess[moduleId] = enabled;
        }
        user.moduleAccess = nextAccess;
      }
      if (typeof changes.membership === 'string') {
        if (!['basic', 'platinum'].includes(changes.membership)) return json(res, 400, {error: 'Invalid membership level'});
        user.membership = changes.membership;
      }
      if (typeof changes.role === 'string') {
        if (!['user', 'admin'].includes(changes.role)) return json(res, 400, {error: 'Role must be "user" or "admin"'});
        user.role = changes.role;
      }
      if (typeof changes.password === 'string') {
        if (!validPassword(changes.password)) return json(res, 400, {error: 'Password must be at least 8 characters'});
        user.passwordHash = await hashPassword(changes.password);
      }
      await saveAppUsers(users);
      if (user.blocked || typeof changes.password === 'string') {
        for (const [token, item] of appSessions) if (item.userId === user.id) appSessions.delete(token);
        await persistSessions();
      }
      const changeNotes = [];
      if (typeof changes.name === 'string') changeNotes.push(`renamed the app account to ${user.name || user.email} for`);
      if (typeof changes.blocked === 'boolean') changeNotes.push(changes.blocked ? 'blocked' : 'unblocked');
      if (typeof changes.privateSync === 'boolean') changeNotes.push(`turned private sync ${changes.privateSync ? 'on' : 'off'} for`);
      if (typeof changes.aiEnabled === 'boolean') changeNotes.push(`turned AI ${changes.aiEnabled ? 'on' : 'off'} for`);
      if (changes.moduleAccess && typeof changes.moduleAccess === 'object') {
        for (const [moduleId, enabled] of Object.entries(changes.moduleAccess)) {
          changeNotes.push(`turned the ${moduleId} module ${enabled ? 'on' : 'off'} for`);
        }
      }
      if (typeof changes.membership === 'string') changeNotes.push(`set the membership level to ${changes.membership} for`);
      if (typeof changes.role === 'string') changeNotes.push(changes.role === 'admin' ? 'granted the app-admin role to' : 'removed the app-admin role from');
      if (typeof changes.password === 'string') changeNotes.push('reset the password for');
      if (changeNotes.length) await logActivity(session, `${session.username} ${changeNotes.join(', ')} ${user.email}`);
      return json(res, 200, {user: publicAppUser(user)});
    }
    if (appUserMatch && req.method === 'DELETE') {
      const users = await loadAppUsers();
      const deletedUser = users.find(item => item.id === appUserMatch[1]);
      if (!deletedUser) return json(res, 404, {error: 'App user not found'});
      await saveAppUsers(users.filter(item => item.id !== appUserMatch[1]));
      for (const [token, item] of appSessions) if (item.userId === appUserMatch[1]) appSessions.delete(token);
      const data = await loadHealthData();
      delete data.users[appUserMatch[1]];
      await saveHealthData(data);
      await logActivity(session, `${session.username} deleted app user ${deletedUser.email} and all their synced data`);
      return json(res, 200, {ok: true});
    }
    const appUserHealthMatch = url.pathname.match(/^\/admin\/api\/app-users\/([^/]+)\/health$/);
    if (appUserHealthMatch && req.method === 'GET') {
      const data = await loadHealthData();
      const record = data.users[appUserHealthMatch[1]] || null;
      return json(res, 200, {data: record ? decodeHealthPayload(record) : null});
    }
    if (appUserHealthMatch && req.method === 'PATCH') {
      const changes = await readBody(req, 4_000_000);
      const data = await loadHealthData();
      const id = appUserHealthMatch[1];
      const existing = data.users[id]?.payload || {};
      const settings = {...(existing.settings || {})};
      if (changes.bodyProfile) settings.bodyProfile = JSON.stringify(changes.bodyProfile);
      if (changes.activeDietPlan) settings.activeDietPlan = JSON.stringify(changes.activeDietPlan);
      if (typeof changes.dailyTarget === 'number') {
        settings.dailyTarget = changes.dailyTarget;
        settings.dailyTargetCustom = true;
      }
      if (typeof changes.waterTargetMl === 'number') settings.waterTargetMl = changes.waterTargetMl;
      if (Array.isArray(changes.savedDietPlans)) {
        settings.savedDietPlans = changes.savedDietPlans.map(plan => JSON.stringify(plan));
      }
      const updated = {...existing, settings};
      if (changes.dailyEntries && typeof changes.dailyEntries === 'object') {
        updated.dailyEntries = changes.dailyEntries;
      }
      if (changes.dailyWater && typeof changes.dailyWater === 'object') {
        updated.dailyWater = changes.dailyWater;
      }
      if (changes.history && typeof changes.history === 'object') {
        updated.history = changes.history;
      }
      data.users[id] = {payload: updated, updatedAt: new Date().toISOString()};
      await saveHealthData(data);
      const editedParts = [];
      if (changes.bodyProfile || changes.activeDietPlan || typeof changes.dailyTarget === 'number' || typeof changes.waterTargetMl === 'number' || changes.savedDietPlans) editedParts.push('settings');
      if (changes.dailyEntries) editedParts.push('daily entries');
      if (changes.dailyWater) editedParts.push('daily water');
      if (changes.history) editedParts.push('history');
      const targetUser = (await loadAppUsers()).find(item => item.id === id);
      await logActivity(session, `${session.username} edited ${editedParts.join(', ') || 'data'} for ${targetUser?.email || id}`);
      return json(res, 200, {data: decodeHealthPayload(data.users[id])});
    }
    if (req.method === 'GET' && url.pathname === '/admin/api/settings') {
      const settings = await loadServerSettings();
      return json(res, 200, {
        hasApiKey: Boolean(settings.openaiApiKey || process.env.OPENAI_API_KEY),
        openaiModel: settings.openaiModel || process.env.OPENAI_MODEL || 'gpt-4o-mini',
      });
    }
    if (req.method === 'PATCH' && url.pathname === '/admin/api/settings') {
      const changes = await readBody(req);
      const settings = await loadServerSettings();
      if (typeof changes.openaiApiKey === 'string' && changes.openaiApiKey.trim()) {
        settings.openaiApiKey = changes.openaiApiKey.trim();
      }
      if (typeof changes.openaiModel === 'string' && changes.openaiModel.trim()) {
        settings.openaiModel = changes.openaiModel.trim();
      }
      await saveServerSettings(settings);
      const settingsNotes = [];
      if (typeof changes.openaiApiKey === 'string' && changes.openaiApiKey.trim()) settingsNotes.push('the OpenAI API key');
      if (typeof changes.openaiModel === 'string' && changes.openaiModel.trim()) settingsNotes.push('the AI model');
      if (settingsNotes.length) await logActivity(session, `${session.username} updated ${settingsNotes.join(' and ')}`);
      return json(res, 200, {
        hasApiKey: Boolean(settings.openaiApiKey || process.env.OPENAI_API_KEY),
        openaiModel: settings.openaiModel || process.env.OPENAI_MODEL || 'gpt-4o-mini',
      });
    }
    if (req.method === 'POST' && url.pathname === '/admin/api/users') {
      const {username, password, role = 'admin'} = await readBody(req);
      if (!validUsername(username)) return json(res, 400, {error: 'Username must be 3–32 letters, numbers, dots, dashes or underscores'});
      if (!validPassword(password)) return json(res, 400, {error: 'Password must be at least 8 characters'});
      if (!['admin', 'viewer'].includes(role)) return json(res, 400, {error: 'Role must be "admin" or "viewer"'});
      const users = await loadUsers();
      if (users.some(item => item.username.toLowerCase() === username.toLowerCase())) return json(res, 409, {error: 'Username already exists'});
      const user = {id: randomUUID(), username, role, passwordHash: await hashPassword(password), createdAt: new Date().toISOString()};
      users.push(user); await saveUsers(users);
      await logActivity(session, `${session.username} added console user ${username} (${role === 'admin' ? 'administrator' : 'view-only'})`);
      return json(res, 201, {user: publicUser(user)});
    }
    const userMatch = url.pathname.match(/^\/admin\/api\/users\/([^/]+)$/);
    if (userMatch && req.method === 'PATCH') {
      const {username, password, currentPassword, role} = await readBody(req);
      const users = await loadUsers();
      const user = users.find(item => item.id === userMatch[1]);
      if (!user) return json(res, 404, {error: 'User not found'});
      const editingSelf = user.id === session.userId;
      const oldUsername = user.username;
      if (editingSelf && (username !== undefined || password)) {
        if (!(await verifyPassword(currentPassword, user.passwordHash))) return json(res, 403, {error: 'Current password is incorrect'});
      }
      if (username !== undefined) {
        if (!validUsername(username)) return json(res, 400, {error: 'Username must be 3–32 valid characters'});
        if (users.some(item => item.id !== user.id && item.username.toLowerCase() === username.toLowerCase())) return json(res, 409, {error: 'Username already exists'});
        user.username = username;
      }
      if (password) {
        if (!validPassword(password)) return json(res, 400, {error: 'Password must be at least 8 characters'});
        user.passwordHash = await hashPassword(password);
      }
      if (typeof role === 'string') {
        if (!['admin', 'viewer'].includes(role)) return json(res, 400, {error: 'Role must be "admin" or "viewer"'});
        if (editingSelf && role !== 'admin') return json(res, 400, {error: 'You cannot remove your own admin access'});
        if (role !== 'admin' && users.filter(item => item.role === 'admin' && item.id !== user.id).length === 0) {
          return json(res, 400, {error: 'At least one console account must stay an administrator'});
        }
        user.role = role;
      }
      await saveUsers(users);
      for (const [token, item] of sessions) if (item.userId === user.id && token !== session.token) sessions.delete(token);
      const changeNotes = [];
      if (username !== undefined) changeNotes.push(editingSelf ? 'renamed their account' : `renamed console user ${oldUsername} to ${user.username}`);
      if (password) changeNotes.push(editingSelf ? 'changed their password' : `reset the password for console user ${user.username}`);
      if (typeof role === 'string') changeNotes.push(`set ${user.username}'s console role to ${role === 'admin' ? 'administrator' : 'view-only'}`);
      if (editingSelf) session.username = user.username;
      if (changeNotes.length) await logActivity(session, `${session.username} ${changeNotes.join(', ')}`);
      return json(res, 200, {user: publicUser(user)});
    }
    if (userMatch && req.method === 'DELETE') {
      if (userMatch[1] === session.userId) return json(res, 400, {error: 'You cannot delete your own account'});
      const users = await loadUsers();
      const removedUser = users.find(item => item.id === userMatch[1]);
      if (!removedUser) return json(res, 404, {error: 'User not found'});
      await saveUsers(users.filter(item => item.id !== userMatch[1]));
      for (const [token, item] of sessions) if (item.userId === userMatch[1]) sessions.delete(token);
      await logActivity(session, `${session.username} removed console user ${removedUser.username}`);
      return json(res, 200, {ok: true});
    }
    // ---- Admin food-catalogue import/export (item 12) ----
    // Every write here goes through food_catalogue.mjs's shared merge
    // policy (classifyRow/applyRow) -- the SAME functions the app's user
    // "add this food" contribution endpoint uses -- so there is one trust
    // hierarchy and one version/change-log, not a second system.
    if (req.method === 'GET' && url.pathname === '/admin/api/catalogue') {
      const catalogue = await foodCatalogue.loadCatalogue();
      const query = foodCatalogue.normalizeText(url.searchParams.get('query') || '');
      const trustFilter = url.searchParams.get('trust');
      const page = Math.max(1, Number(url.searchParams.get('page') || '1'));
      const pageSize = 50;
      let filtered = catalogue;
      if (trustFilter) filtered = filtered.filter(item => item.trust === trustFilter);
      if (query) {
        filtered = filtered.filter(item => {
          const names = [item.names?.en, item.names?.pl, ...(item.aliases?.en || []), ...(item.aliases?.pl || [])].filter(Boolean);
          return names.some(name => foodCatalogue.normalizeText(name).includes(query));
        });
      }
      const meta = await foodCatalogue.loadMeta();
      return json(res, 200, {
        version: meta.version,
        total: filtered.length,
        page,
        pageSize,
        foods: filtered.slice((page - 1) * pageSize, page * pageSize),
      });
    }
    if (req.method === 'GET' && url.pathname === '/admin/api/catalogue/export') {
      const format = url.searchParams.get('format') || 'csv';
      const catalogue = await foodCatalogue.loadCatalogue();
      const {contentType, body} = foodCatalogue.exportCatalogueRows(catalogue, format);
      res.writeHead(200, {
        'content-type': contentType,
        'content-disposition': `attachment; filename="a2-food-catalogue.${format}"`,
        'cache-control': 'no-store',
      });
      return res.end(body);
    }
    if (req.method === 'GET' && url.pathname === '/admin/api/catalogue/import-profiles') {
      return json(res, 200, {profiles: await foodCatalogue.loadImportProfiles()});
    }
    if (req.method === 'POST' && url.pathname === '/admin/api/catalogue/import-profiles') {
      const {name, mapping, source, trust, defaultBasis} = await readBody(req);
      if (!String(name || '').trim()) return json(res, 400, {error: 'A profile name is required'});
      const profiles = await foodCatalogue.loadImportProfiles();
      const existingIndex = profiles.findIndex(p => p.name === name);
      const profile = {name: String(name).trim(), mapping: mapping || {}, source: source || '', trust: trust || 'admin', defaultBasis: defaultBasis || 'per100g'};
      if (existingIndex >= 0) profiles[existingIndex] = profile; else profiles.push(profile);
      await foodCatalogue.saveImportProfiles(profiles);
      await logActivity(session, `${session.username} saved import profile "${profile.name}"`);
      return json(res, 200, {profiles});
    }
    if (req.method === 'GET' && url.pathname === '/admin/api/catalogue/imports') {
      const batches = await foodCatalogue.loadImportBatches();
      // Snapshots (`before`) can be large -- the list view never needs them.
      return json(res, 200, {batches: batches.map(({before, ...rest}) => rest).reverse()});
    }
    if (req.method === 'POST' && url.pathname === '/admin/api/catalogue/import/preview') {
      const {format, filename, contentBase64, mapping: explicitMapping, source, trust, defaultBasis} = await readBody(req, 30_000_000);
      if (!['csv', 'xlsx', 'json'].includes(format)) return json(res, 400, {error: 'format must be csv, xlsx or json'});
      if (!contentBase64) return json(res, 400, {error: 'No file content received'});
      let parsed;
      try {
        const buffer = Buffer.from(contentBase64, 'base64');
        parsed = foodCatalogue.parseUploadedFile(buffer, format);
      } catch (error) {
        return json(res, 400, {error: `Could not read this file: ${error.message}`});
      }
      if (!parsed.rows.length) return json(res, 400, {error: 'No rows found in this file'});
      const mapping = explicitMapping && Object.keys(explicitMapping).length
        ? explicitMapping
        : foodCatalogue.guessColumnMapping(parsed.headers);
      const mappedRows = parsed.rows.map(raw => foodCatalogue.mapRow(raw, mapping, {trust: trust || 'admin', source: source || filename, defaultBasis}));
      const catalogue = await foodCatalogue.loadCatalogue();
      const {summary, rows} = foodCatalogue.classifyImportRows(mappedRows, catalogue);
      const previewId = foodCatalogue.storePreview({mappedRows, source: source || filename, filename});
      // Full detail for a bounded sample keeps the response reasonable for
      // datasets with thousands of rows; the counts above already cover all
      // of them, and the conflict/suggested/invalid rows most worth a
      // human's attention are prioritised into that sample first.
      const priority = ['conflict', 'suggested-match', 'invalid', 'matched-update', 'duplicate-in-file', 'matched-alias-only', 'matched-nochange', 'new'];
      const sample = [...rows].sort((a, b) => priority.indexOf(a.action) - priority.indexOf(b.action)).slice(0, 300);
      return json(res, 200, {
        previewId,
        detectedColumns: parsed.headers,
        mapping,
        summary,
        sampleRows: sample,
      });
    }
    if (req.method === 'POST' && url.pathname === '/admin/api/catalogue/import/confirm') {
      const {previewId, decisions = {}, defaultConflictAction = 'skip'} = await readBody(req);
      const preview = foodCatalogue.getPreview(previewId);
      if (!preview) return json(res, 404, {error: 'This preview has expired -- please re-upload and preview again'});
      const catalogue = await foodCatalogue.loadCatalogue();
      const touchedIds = [];
      const beforeById = {};
      const createdIds = [];
      const counts = {created: 0, updated: 0, aliasesMerged: 0, kept: 0, skipped: 0, noChange: 0};
      preview.mappedRows.forEach((record, index) => {
        const classification = foodCatalogue.classifyRow(record, catalogue);
        let decision = decisions[index] || decisions[String(index)];
        if (!decision) {
          decision = classification.action === 'conflict' || classification.action === 'suggested-match'
            ? defaultConflictAction
            : classification.action;
        }
        const result = foodCatalogue.applyRow(record, catalogue, {decision});
        if (result.id) {
          touchedIds.push(result.id);
          if (result.before && !(result.id in beforeById)) beforeById[result.id] = result.before;
          if (!result.before && result.action === 'created' && !createdIds.includes(result.id)) {
            beforeById[result.id] = null;
            createdIds.push(result.id);
          }
        }
        if (result.action === 'created') counts.created += 1;
        else if (result.action === 'updated') counts.updated += 1;
        else if (result.action === 'aliases-merged') counts.aliasesMerged += 1;
        else if (result.action === 'kept') counts.kept += 1;
        else if (result.action === 'nochange') counts.noChange += 1;
        else counts.skipped += 1;
      });
      await foodCatalogue.saveCatalogue(catalogue);
      const version = await foodCatalogue.bumpVersion(touchedIds);
      const batch = {
        id: randomUUID(),
        importedAt: new Date().toISOString(),
        importedBy: session.username,
        source: preview.source,
        filename: preview.filename,
        version,
        counts,
        touchedIds: [...new Set(touchedIds)],
        before: beforeById,
      };
      const batches = await foodCatalogue.loadImportBatches();
      batches.push(batch);
      await foodCatalogue.saveImportBatches(batches);
      foodCatalogue.deletePreview(previewId);
      await logActivity(session, `${session.username} imported "${preview.filename}" -- ${counts.created} added, ${counts.updated} updated, ${counts.aliasesMerged} alias merges`);
      const {before, ...batchSummary} = batch;
      return json(res, 200, {batch: batchSummary});
    }
    const rollbackMatch = url.pathname.match(/^\/admin\/api\/catalogue\/imports\/([^/]+)\/rollback$/);
    if (rollbackMatch && req.method === 'POST') {
      const batches = await foodCatalogue.loadImportBatches();
      const batch = batches.find(item => item.id === rollbackMatch[1]);
      if (!batch) return json(res, 404, {error: 'Import batch not found'});
      if (batch.rolledBackAt) return json(res, 400, {error: 'This import was already rolled back'});
      const catalogue = await foodCatalogue.loadCatalogue();
      const remaining = [];
      const restoredIds = [];
      for (const item of catalogue) {
        if (!(item.id in batch.before)) { remaining.push(item); continue; }
        const snapshot = batch.before[item.id];
        if (snapshot === null) { restoredIds.push(item.id); continue; } // was created by this batch -- remove it
        remaining.push(snapshot); // restore its pre-import state
        restoredIds.push(item.id);
      }
      await foodCatalogue.saveCatalogue(remaining);
      await foodCatalogue.bumpVersion(restoredIds, 'rollback');
      batch.rolledBackAt = new Date().toISOString();
      await foodCatalogue.saveImportBatches(batches);
      await logActivity(session, `${session.username} rolled back the "${batch.filename}" import`);
      return json(res, 200, {ok: true});
    }
    if (['GET', 'HEAD'].includes(req.method) && (url.pathname === '/' || url.pathname === '/admin')) {
      res.writeHead(302, {location: '/admin/', 'cache-control': 'no-store'});
      return res.end();
    }
    if (req.method === 'GET' && url.pathname === '/admin/') {
      const [page, styles, script] = await Promise.all([
        readFile(join(publicDir, 'index.html'), 'utf8'),
        readFile(join(publicDir, 'style.css'), 'utf8'),
        readFile(join(publicDir, 'app.js'), 'utf8'),
      ]);
      const body = page
        .replace(/<link rel="stylesheet"[^>]*>/, `<style>${styles}</style>`)
        .replace(/<script src="[^"]+"><\/script>/, `<script>${script}</script>`);
      res.writeHead(200, {'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store'}); return res.end(body);
    }
    const file = url.pathname.startsWith('/admin/') ? join(publicDir, url.pathname.slice(7)) : null;
    if (file && ['.js','.css'].includes(extname(file))) {
      const body = await readFile(file);
      res.writeHead(200, {'content-type': extname(file) === '.js' ? 'text/javascript' : 'text/css', 'cache-control': 'no-store'}); return res.end(body);
    }
    json(res, 404, {error: 'Not found'});
  } catch (error) {
    // Full detail stays server-side only -- an unexpected exception's
    // message could leak internal paths/state to a public, unauthenticated
    // caller now that this server is reachable over the open internet.
    console.error('[server] unhandled request error:', error);
    json(res, 500, {error: 'Server error'});
  }
});
server.listen(port, '0.0.0.0', () => console.log(`a2 content server listening on ${port}`));
