const $ = id => document.getElementById(id);
let data = {drafts: [], releases: []};
let adminPassword = sessionStorage.getItem('a2-admin-password') || '';

const api = async (path, options = {}) => {
  const response = await fetch(`/admin/api/${path}`, {
    ...options,
    headers: {
      'authorization': `Bearer ${adminPassword}`,
      'content-type': 'application/json',
      ...(options.headers || {}),
    },
  });
  const body = await response.json();
  if (!response.ok) throw new Error(body.error || `Request failed (${response.status})`);
  return body;
};
const escapeHtml = value => String(value ?? '').replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));

async function load() {
  data = await api('content');
  $('login').hidden = true;
  $('console').hidden = false;
  $('status').textContent = 'Connected';
  $('draft-count').textContent = data.drafts.length;
  $('release-count').textContent = data.releases.filter(item => item.status === 'published').length;
  render();
}
function render() {
  $('drafts').innerHTML = data.drafts.length ? data.drafts.map(d => `<div class="item"><span class="pill">${escapeHtml(d.content.category)}</span><h3>${escapeHtml(d.content.title)}</h3><p>${escapeHtml(d.content.summary)}</p><p><strong>Evidence:</strong> ${escapeHtml(d.content.evidence_note)}</p><p>${d.content.sources.map(s => `<a target="_blank" rel="noopener" href="${escapeHtml(s.url)}">${escapeHtml(s.title)}</a>`).join(' · ')}</p><div class="row"><select id="type-${d.id}"><option value="all">Everyone</option><option value="group">Group</option><option value="user">User</option><option value="device">Device</option></select><input id="ids-${d.id}" placeholder="IDs, comma separated"><button onclick="publishDraft('${d.id}')">Approve & publish</button></div></div>`).join('') : 'No drafts yet.';
  $('releases').innerHTML = data.releases.length ? data.releases.map(r => `<div class="item"><div class="row"><span class="pill">${escapeHtml(r.status)}</span><small>${escapeHtml(r.target.type)}: ${escapeHtml(r.target.ids.join(', ') || 'all')}</small></div><h3>${escapeHtml(r.content.title)}</h3><p>Version ${r.version} · ${new Date(r.publishedAt).toLocaleString()}</p>${r.status === 'published' ? `<button class="danger" onclick="withdraw('${r.id}')">Withdraw</button>` : ''}</div>`).join('') : 'Nothing published yet.';
}
window.publishDraft = async id => {
  const type = $(`type-${id}`).value;
  const ids = $(`ids-${id}`).value.split(',').map(x => x.trim()).filter(Boolean);
  if (type !== 'all' && !ids.length) return alert('Enter at least one target ID.');
  await api('publish', {method:'POST', body:JSON.stringify({draftId:id,target:{type,ids}})});
  await load();
};
window.withdraw = async id => {
  if (confirm('Withdraw this release from future device updates?')) {
    await api('unpublish', {method:'POST', body:JSON.stringify({releaseId:id})});
    await load();
  }
};
$('login-form').onsubmit = async event => {
  event.preventDefault();
  adminPassword = $('token').value;
  $('login-error').textContent = '';
  try {
    await load();
    sessionStorage.setItem('a2-admin-password', adminPassword);
    $('token').value = '';
  } catch (error) {
    adminPassword = '';
    $('login-error').textContent = error.message === 'Unauthorized' ? 'That admin password is not correct.' : error.message;
  }
};
$('logout').onclick = () => {
  adminPassword = '';
  sessionStorage.removeItem('a2-admin-password');
  $('console').hidden = true;
  $('login').hidden = false;
};
$('research').onclick = async () => {
  const topic = $('topic').value.trim(); if (!topic) return;
  $('research').disabled = true; $('research').textContent = 'Researching…';
  try { await api('research', {method:'POST', body:JSON.stringify({topic})}); $('topic').value=''; await load(); }
  catch(error) { alert(error.message); } finally { $('research').disabled=false; $('research').textContent='Create review draft'; }
};
if (adminPassword) load().catch(() => sessionStorage.removeItem('a2-admin-password'));
