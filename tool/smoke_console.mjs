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

const login = await request('login', {method: 'POST', body: JSON.stringify({username, password})});
const me = await request('me', {}, login.token);
const created = await request('users', {method: 'POST', body: JSON.stringify({username: 'smoke_test_admin', password: 'temporary-test-5568'})}, login.token);
const users = await request('users', {}, login.token);
if (me.user.username !== username || !users.users.some(user => user.id === created.user.id)) throw new Error('Account verification failed');
await request(`users/${created.user.id}`, {method: 'DELETE'}, login.token);
await request('logout', {method: 'POST'}, login.token);
console.log('Console authentication and user-management smoke test passed.');
