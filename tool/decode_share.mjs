import fs from 'node:fs';

const htmlPath = process.argv[2];
if (!htmlPath) throw new Error('Usage: node tool/decode_share.mjs <share.html> [output.json]');
const html = fs.readFileSync(htmlPath, 'utf8');
const marker = 'window.__reactRouterContext.streamController.enqueue(';
const chunks = [];
let cursor = 0;
while ((cursor = html.indexOf(marker, cursor)) !== -1) {
  const start = cursor + marker.length;
  let i = start;
  let escaped = false;
  if (html[i] !== '"') { cursor = start; continue; }
  i++;
  for (; i < html.length; i++) {
    if (escaped) { escaped = false; continue; }
    if (html[i] === '\\') { escaped = true; continue; }
    if (html[i] === '"') break;
  }
  chunks.push(JSON.parse(html.slice(start, i + 1)));
  cursor = i + 1;
}
const flattened = JSON.parse(chunks[0]);
const mappingKeyIndex = flattened.indexOf('mapping');
const conversationIndex = flattened.findIndex((value) =>
  value && !Array.isArray(value) && typeof value === 'object' && Object.hasOwn(value, `_${mappingKeyIndex}`)
);
if (conversationIndex < 0) throw new Error('Conversation root not found');
const cache = new Map();
function hydrate(index) {
  if (index == null || index < 0) return null;
  if (cache.has(index)) return cache.get(index);
  const value = flattened[index];
  if (value == null || typeof value !== 'object') return value;
  if (Array.isArray(value)) {
    if (typeof value[0] === 'string') {
      if (value[0] === 'Date') return value[1];
      if (value[0] === 'P') return null;
    }
    const result = [];
    cache.set(index, result);
    for (const child of value) result.push(hydrate(child));
    return result;
  }
  const result = {};
  cache.set(index, result);
  for (const [rawKey, child] of Object.entries(value)) {
    const keyIndex = Number(rawKey.slice(1));
    result[hydrate(keyIndex)] = hydrate(child);
  }
  return result;
}
const data = hydrate(conversationIndex);

function locate(value, seen = new Set()) {
  if (!value || typeof value !== 'object' || seen.has(value)) return null;
  seen.add(value);
  if (value.mapping && typeof value.mapping === 'object' && value.title) return value;
  for (const child of Array.isArray(value) ? value : Object.values(value)) {
    const found = locate(child, seen);
    if (found) return found;
  }
  return null;
}
const conversation = data?.mapping ? data : locate(data);
if (!conversation) {
  function inspect(value, path = '$', seen = new Set()) {
    if (!value || typeof value !== 'object' || seen.has(value)) return;
    seen.add(value);
    const keys = Object.keys(value);
    if (keys.some((key) => ['mapping', 'title', 'serverResponse', 'conversation_id'].includes(key))) {
      process.stderr.write(`${path}: ${keys.slice(0, 30).join(',')}\n`);
    }
    for (const [key, child] of Object.entries(value)) inspect(child, `${path}.${key}`, seen);
  }
  inspect(data);
  throw new Error('Conversation object not found');
}
const output = JSON.stringify(conversation, null, 2);
if (process.argv[3]) fs.writeFileSync(process.argv[3], output);
else process.stdout.write(output);
