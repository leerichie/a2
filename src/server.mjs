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
const port = Number(process.env.PORT || 8787);
const initialAdminUser = process.env.INITIAL_ADMIN_USER || 'admin';
const initialAdminPassword = process.env.INITIAL_ADMIN_PASSWORD || '';
const scrypt = promisify(scryptCallback);
const sessions = new Map();

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
const readBody = async req => {
  let raw = '';
  for await (const chunk of req) {
    raw += chunk;
    if (raw.length > 1_000_000) throw new Error('Request too large');
  }
  return raw ? JSON.parse(raw) : {};
};
const load = async () => JSON.parse(await readFile(dataFile, 'utf8'));
const save = async data => {
  await mkdir(dirname(dataFile), {recursive: true});
  await writeFile(dataFile, JSON.stringify(data, null, 2));
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
const targetMatches = (target, userId, deviceId, groups) =>
  target.type === 'all' ||
  (target.type === 'user' && target.ids.includes(userId)) ||
  (target.type === 'device' && target.ids.includes(deviceId)) ||
  (target.type === 'group' && target.ids.some(id => groups.includes(id)));

async function research(topic) {
  if (!process.env.OPENAI_API_KEY) throw new Error('OPENAI_API_KEY is not configured');
  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: {'authorization': `Bearer ${process.env.OPENAI_API_KEY}`, 'content-type': 'application/json'},
    body: JSON.stringify({
      model: process.env.OPENAI_MODEL || 'gpt-5',
      store: false,
      tools: [{type: 'web_search'}],
      include: ['web_search_call.action.sources'],
      instructions: 'Research food and fitness information conservatively. Prefer primary health authorities and peer-reviewed sources. Never prescribe treatment. Return a short factual draft for human review with uncertainty clearly stated.',
      input: `Research this proposed a2 app content update: ${topic}\nReturn JSON with title, summary, category (diet|nutrition|calorie_reference|guidance), locale, evidence_note, and sources as an array of {title,url}.`,
      text: {format: {type: 'json_schema', name: 'content_draft', strict: true, schema: {
        type: 'object', additionalProperties: false,
        properties: {
          title: {type: 'string'}, summary: {type: 'string'},
          category: {type: 'string', enum: ['diet','nutrition','calorie_reference','guidance']},
          locale: {type: 'string'}, evidence_note: {type: 'string'},
          sources: {type: 'array', items: {type: 'object', additionalProperties: false, properties: {title: {type: 'string'}, url: {type: 'string'}}, required: ['title','url']}}
        }, required: ['title','summary','category','locale','evidence_note','sources']
      }}}
    })
  });
  if (!response.ok) throw new Error(`OpenAI request failed (${response.status})`);
  const result = await response.json();
  return JSON.parse(result.output_text);
}

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host}`);
    if (req.method === 'GET' && url.pathname === '/health') return json(res, 200, {ok: true});
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
    if (req.method === 'GET' && url.pathname === '/admin/api/me') return json(res, 200, {user: session});
    if (req.method === 'GET' && url.pathname === '/admin/api/users') {
      const users = await loadUsers();
      return json(res, 200, {users: users.map(publicUser)});
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
    if (req.method === 'GET' && url.pathname === '/admin/api/content') return json(res, 200, await load());
    if (req.method === 'POST' && url.pathname === '/admin/api/research') {
      const {topic} = await readBody(req);
      if (!topic?.trim()) return json(res, 400, {error: 'Topic is required'});
      const content = await research(topic.trim());
      const data = await load();
      const draft = {id: randomUUID(), createdAt: new Date().toISOString(), topic, content};
      data.drafts.unshift(draft);
      await save(data);
      return json(res, 201, draft);
    }
    if (req.method === 'POST' && url.pathname === '/admin/api/publish') {
      const {draftId, target = {type: 'all', ids: []}} = await readBody(req);
      if (!['all','user','device','group'].includes(target.type) || !Array.isArray(target.ids)) return json(res, 400, {error: 'Invalid target'});
      const data = await load();
      const draft = data.drafts.find(item => item.id === draftId);
      if (!draft) return json(res, 404, {error: 'Draft not found'});
      const release = {id: randomUUID(), version: Date.now(), status: 'published', publishedAt: new Date().toISOString(), target, content: draft.content};
      data.releases.unshift(release);
      await save(data);
      return json(res, 201, release);
    }
    if (req.method === 'POST' && url.pathname === '/admin/api/unpublish') {
      const {releaseId} = await readBody(req);
      const data = await load();
      const release = data.releases.find(item => item.id === releaseId);
      if (!release) return json(res, 404, {error: 'Release not found'});
      release.status = 'withdrawn';
      release.withdrawnAt = new Date().toISOString();
      await save(data);
      return json(res, 200, release);
    }
    if (req.method === 'GET' && (url.pathname === '/admin' || url.pathname === '/admin/')) {
      const body = await readFile(join(publicDir, 'index.html'));
      res.writeHead(200, {'content-type': 'text/html; charset=utf-8'}); return res.end(body);
    }
    const file = url.pathname.startsWith('/admin/') ? join(publicDir, url.pathname.slice(7)) : null;
    if (file && ['.js','.css'].includes(extname(file))) {
      const body = await readFile(file);
      res.writeHead(200, {'content-type': extname(file) === '.js' ? 'text/javascript' : 'text/css'}); return res.end(body);
    }
    json(res, 404, {error: 'Not found'});
  } catch (error) {
    json(res, 500, {error: error.message || 'Server error'});
  }
});
server.listen(port, '0.0.0.0', () => console.log(`a2 content server listening on ${port}`));
