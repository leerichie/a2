import { createServer } from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes, randomUUID, scrypt as scryptCallback, timingSafeEqual } from 'node:crypto';
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
const publicAppUser = user => ({id: user.id, email: user.email, name: user.name, role: user.role || 'user', blocked: user.blocked === true, privateSync: user.privateSync === true, aiEnabled: user.aiEnabled === true, entrySyncEnabled: user.entrySyncEnabled === true, linkedUserIds: user.linkedUserIds || [], googleLinked: user.googleLinked === true, createdAt: user.createdAt});
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

async function aiDescribe(kind, text) {
  const {apiKey, model} = await getOpenAiCredentials();
  if (!apiKey) throw new Error('AI is not configured on this server');
  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: {'authorization': `Bearer ${apiKey}`, 'content-type': 'application/json'},
    body: JSON.stringify({
      model,
      store: false,
      instructions: kind === 'exercise'
        ? 'Estimate calories burned for a described exercise session, given its duration. Be conservative and realistic, never invent false precision. Protein and carbs are always 0 for exercise. Set servingGrams to 0 for exercise.'
        : 'Estimate total nutrition for the described food or drink. It may list several distinct items (e.g. a fast-food order or a multi-part meal) — recognise each one, including named branded/restaurant items, and return the SUM of calories, protein and carbs across all of them, not just one. Account for any stated quantities (e.g. "2x", "large"). Assume typical realistic portion sizes when a quantity is vague; never invent false precision, but also never underestimate a clearly multi-item meal. Also return servingGrams: the total realistic weight in grams of the portion your calorie/protein/carb figures describe (summed across every item if there are several), so those figures can be recorded on a per-100g basis later.',
      input: text,
      text: {format: {type: 'json_schema', name: 'nutrition_estimate', strict: true, schema: NUTRITION_SCHEMA}},
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
      const {email, password} = await readBody(req);
      const users = await loadAppUsers();
      const user = users.find(item => item.email === String(email || '').trim().toLowerCase());
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
    if (url.pathname.startsWith('/api/v1/auth/')) {
      const appSession = appSessionFor(req);
      if (!appSession) return json(res, 401, {error: 'Unauthorized'});
      if (req.method === 'GET' && url.pathname === '/api/v1/auth/me') {
        const user = (await loadAppUsers()).find(item => item.id === appSession.userId);
        return user ? json(res, 200, {user: publicAppUser(user)}) : json(res, 401, {error: 'Account no longer exists'});
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
        const {kind, text} = await readBody(req);
        if (!['food', 'drink', 'exercise'].includes(kind) || !text?.trim()) {
          return json(res, 400, {error: 'A kind and description are required'});
        }
        try {
          return json(res, 200, await aiDescribe(kind, text.trim()));
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
    json(res, 500, {error: error.message || 'Server error'});
  }
});
server.listen(port, '0.0.0.0', () => console.log(`a2 content server listening on ${port}`));
