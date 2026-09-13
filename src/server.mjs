import { createServer } from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes, randomUUID, scrypt as scryptCallback, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const publicDir = join(root, 'public');
const dataFile = join(process.env.DATA_DIR || join(root, 'data'), 'content.json');
const usersFile = join(process.env.DATA_DIR || join(root, 'data'), 'users.json');
const appUsersFile = join(process.env.DATA_DIR || join(root, 'data'), 'app-users.json');
const healthDataFile = join(process.env.DATA_DIR || join(root, 'data'), 'health-data.json');
const settingsFile = join(process.env.DATA_DIR || join(root, 'data'), 'settings.json');
const sessionsFile = join(process.env.DATA_DIR || join(root, 'data'), 'sessions.json');
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

const json = (res, status, body) => {
  res.writeHead(status, {'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store'});
  res.end(JSON.stringify(body));
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
const publicAppUser = user => ({id: user.id, email: user.email, name: user.name, role: user.role || 'user', blocked: user.blocked === true, privateSync: user.privateSync === true, aiEnabled: user.aiEnabled === true, createdAt: user.createdAt});
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
    model: settings.openaiModel || process.env.OPENAI_MODEL || 'gpt-5',
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
    savedDietPlans: (settings.savedDietPlans || []).map(parse).filter(Boolean),
    dailyEntries: payload.dailyEntries || {},
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
  },
  required: ['name', 'calories', 'protein', 'carbs'],
};

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
        ? 'Estimate calories burned for a described exercise session, given its duration. Be conservative and realistic, never invent false precision. Protein and carbs are always 0 for exercise.'
        : 'Estimate nutrition for a described food or drink item, assuming typical portion sizes when quantities are vague. Never invent false precision.',
      input: text,
      text: {format: {type: 'json_schema', name: 'nutrition_estimate', strict: true, schema: NUTRITION_SCHEMA}},
    }),
  });
  if (!response.ok) throw new Error(`AI request failed (${response.status})`);
  const result = await response.json();
  return JSON.parse(result.output_text);
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
        ? 'Read the nutrition facts label shown in the photo and extract calories, protein and carbohydrates for one serving. If a value is unreadable, estimate conservatively rather than inventing false precision.'
        : 'Identify the food or drink shown in the photo and estimate its nutrition for the visible portion. Never invent false precision.',
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
  return JSON.parse(result.output_text);
}

const server = createServer(async (req, res) => {
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
          data.users[appSession.userId] = {payload: body.payload || {}, updatedAt: new Date().toISOString()};
          await saveHealthData(data);
          return json(res, 200, {ok: true, updatedAt: data.users[appSession.userId].updatedAt});
        }
      }
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
      sessions.set(token, {userId: user.id, username: user.username, role: user.role, expiresAt: Date.now() + 12 * 60 * 60 * 1000});
      return json(res, 200, {token, user: publicUser(user)});
    }
    const session = url.pathname.startsWith('/admin/api/') ? sessionFor(req) : null;
    if (url.pathname.startsWith('/admin/api/') && !session) return json(res, 401, {error: 'Unauthorized'});
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
    if (req.method === 'GET' && url.pathname === '/admin/api/users') {
      const users = await loadUsers();
      return json(res, 200, {users: users.map(publicUser)});
    }
    if (req.method === 'GET' && url.pathname === '/admin/api/app-users') {
      return json(res, 200, {users: (await loadAppUsers()).map(publicAppUser)});
    }
    const appUserMatch = url.pathname.match(/^\/admin\/api\/app-users\/([^/]+)$/);
    if (appUserMatch && req.method === 'PATCH') {
      const changes = await readBody(req);
      const users = await loadAppUsers();
      const user = users.find(item => item.id === appUserMatch[1]);
      if (!user) return json(res, 404, {error: 'App user not found'});
      if (typeof changes.blocked === 'boolean') user.blocked = changes.blocked;
      if (typeof changes.privateSync === 'boolean') user.privateSync = changes.privateSync;
      if (typeof changes.aiEnabled === 'boolean') user.aiEnabled = changes.aiEnabled;
      if (typeof changes.password === 'string') {
        if (!validPassword(changes.password)) return json(res, 400, {error: 'Password must be at least 8 characters'});
        user.passwordHash = await hashPassword(changes.password);
      }
      await saveAppUsers(users);
      if (user.blocked || typeof changes.password === 'string') {
        for (const [token, item] of appSessions) if (item.userId === user.id) appSessions.delete(token);
        await persistSessions();
      }
      return json(res, 200, {user: publicAppUser(user)});
    }
    if (appUserMatch && req.method === 'DELETE') {
      const users = await loadAppUsers();
      if (!users.some(item => item.id === appUserMatch[1])) return json(res, 404, {error: 'App user not found'});
      await saveAppUsers(users.filter(item => item.id !== appUserMatch[1]));
      for (const [token, item] of appSessions) if (item.userId === appUserMatch[1]) appSessions.delete(token);
      const data = await loadHealthData();
      delete data.users[appUserMatch[1]];
      await saveHealthData(data);
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
      if (typeof changes.dailyTarget === 'number') settings.dailyTarget = changes.dailyTarget;
      if (Array.isArray(changes.savedDietPlans)) {
        settings.savedDietPlans = changes.savedDietPlans.map(plan => JSON.stringify(plan));
      }
      const updated = {...existing, settings};
      if (changes.dailyEntries && typeof changes.dailyEntries === 'object') {
        updated.dailyEntries = changes.dailyEntries;
      }
      if (changes.history && typeof changes.history === 'object') {
        updated.history = changes.history;
      }
      data.users[id] = {payload: updated, updatedAt: new Date().toISOString()};
      await saveHealthData(data);
      return json(res, 200, {data: decodeHealthPayload(data.users[id])});
    }
    if (req.method === 'GET' && url.pathname === '/admin/api/settings') {
      const settings = await loadServerSettings();
      return json(res, 200, {
        hasApiKey: Boolean(settings.openaiApiKey || process.env.OPENAI_API_KEY),
        openaiModel: settings.openaiModel || process.env.OPENAI_MODEL || 'gpt-5',
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
      return json(res, 200, {
        hasApiKey: Boolean(settings.openaiApiKey || process.env.OPENAI_API_KEY),
        openaiModel: settings.openaiModel || process.env.OPENAI_MODEL || 'gpt-5',
      });
    }
    if (req.method === 'POST' && url.pathname === '/admin/api/users') {
      const {username, password, role = 'admin'} = await readBody(req);
      if (!validUsername(username)) return json(res, 400, {error: 'Username must be 3–32 letters, numbers, dots, dashes or underscores'});
      if (!validPassword(password)) return json(res, 400, {error: 'Password must be at least 8 characters'});
      if (role !== 'admin') return json(res, 400, {error: 'Only admin accounts are currently supported'});
      const users = await loadUsers();
      if (users.some(item => item.username.toLowerCase() === username.toLowerCase())) return json(res, 409, {error: 'Username already exists'});
      const user = {id: randomUUID(), username, role, passwordHash: await hashPassword(password), createdAt: new Date().toISOString()};
      users.push(user); await saveUsers(users);
      return json(res, 201, {user: publicUser(user)});
    }
    const userMatch = url.pathname.match(/^\/admin\/api\/users\/([^/]+)$/);
    if (userMatch && req.method === 'PATCH') {
      const {username, password, currentPassword} = await readBody(req);
      const users = await loadUsers();
      const user = users.find(item => item.id === userMatch[1]);
      if (!user) return json(res, 404, {error: 'User not found'});
      if (user.id === session.userId && !(await verifyPassword(currentPassword, user.passwordHash))) return json(res, 403, {error: 'Current password is incorrect'});
      if (username !== undefined) {
        if (!validUsername(username)) return json(res, 400, {error: 'Username must be 3–32 valid characters'});
        if (users.some(item => item.id !== user.id && item.username.toLowerCase() === username.toLowerCase())) return json(res, 409, {error: 'Username already exists'});
        user.username = username;
      }
      if (password) {
        if (!validPassword(password)) return json(res, 400, {error: 'Password must be at least 8 characters'});
        user.passwordHash = await hashPassword(password);
      }
      await saveUsers(users);
      for (const [token, item] of sessions) if (item.userId === user.id && token !== session.token) sessions.delete(token);
      session.username = user.username;
      return json(res, 200, {user: publicUser(user)});
    }
    if (userMatch && req.method === 'DELETE') {
      if (userMatch[1] === session.userId) return json(res, 400, {error: 'You cannot delete your own account'});
      const users = await loadUsers();
      if (!users.some(item => item.id === userMatch[1])) return json(res, 404, {error: 'User not found'});
      await saveUsers(users.filter(item => item.id !== userMatch[1]));
      for (const [token, item] of sessions) if (item.userId === userMatch[1]) sessions.delete(token);
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
