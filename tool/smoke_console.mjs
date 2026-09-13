const base = process.argv[2];
const username = process.argv[3];
const password = process.argv[4];
if (!base || !username || !password) throw new Error('Usage: node tool/smoke_console.mjs URL USER PASSWORD');

const request = async (path, options = {}, token = '') => {
  const response = await fetch(`${base}/admin/api/${path}`, {
    ...options,
    headers: {'content-type': 'application/json', ...(token ? {authorization: `Bearer ${token}`} : {})},
  });
  const body = await response.json();
  if (!response.ok) throw new Error(`${path}: ${body.error}`);
  return body;
};
const appRequest = async (path, options = {}, token = '') => {
  const response = await fetch(`${base}/api/v1/auth/${path}`, {
    ...options,
    headers: {'content-type': 'application/json', ...(token ? {authorization: `Bearer ${token}`} : {})},
  });
  const body = await response.json();
  if (!response.ok) throw new Error(`app ${path}: ${body.error}`);
  return body;
};

const login = await request('login', {method: 'POST', body: JSON.stringify({username, password})});
const me = await request('me', {}, login.token);
const created = await request('users', {method: 'POST', body: JSON.stringify({username: 'smoke_test_admin', password: 'temporary-test-5568'})}, login.token);
const users = await request('users', {}, login.token);
if (me.user.username !== username || !users.users.some(user => user.id === created.user.id)) throw new Error('Account verification failed');
await request(`users/${created.user.id}`, {method: 'DELETE'}, login.token);
const email = `smoke-${Date.now()}@example.test`;
const appAccount = await appRequest('register', {method: 'POST', body: JSON.stringify({email, password: 'temporary-test-5568', name: 'Smoke Test'})});
const appMe = await appRequest('me', {}, appAccount.token);
if (appMe.user.email !== email) throw new Error('App account verification failed');
await request(`app-users/${appAccount.user.id}`, {method: 'PATCH', body: JSON.stringify({privateSync: true})}, login.token);
await appRequest('sync', {method: 'PUT', body: JSON.stringify({payload: {dailyEntries: {test: []}}})}, appAccount.token);
const synced = await appRequest('sync', {}, appAccount.token);
if (!synced.data?.payload?.dailyEntries?.test) throw new Error('Private sync verification failed');
await request(`app-users/${appAccount.user.id}`, {method: 'PATCH', body: JSON.stringify({blocked: true})}, login.token);
const blockedLogin = await fetch(`${base}/api/v1/auth/login`, {method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({email, password: 'temporary-test-5568'})});
if (blockedLogin.status !== 403) throw new Error('Blocked account could still sign in');
await request(`app-users/${appAccount.user.id}`, {method: 'DELETE'}, login.token);
await request('logout', {method: 'POST'}, login.token);
console.log('Console and app account smoke tests passed.');
