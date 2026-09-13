import fs from 'node:fs';

const conversation = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const nodes = conversation.mapping;
const path = [];
let id = conversation.current_node;
while (id && nodes[id]) {
  if (nodes[id].message) path.push(nodes[id].message);
  id = nodes[id].parent;
}
path.reverse();
const output = path.map((message) => {
  const parts = (message.content?.parts ?? []).map((part) => {
    if (typeof part === 'string') return part;
    if (part?.content_type === 'image_asset_pointer') return `[IMAGE ${part.asset_pointer} ${part.width ?? '?'}x${part.height ?? '?'}]`;
    return `[${part?.content_type ?? 'ATTACHMENT'}]`;
  }).join('\n');
  return `\n--- ${new Date(message.create_time * 1000).toISOString()} ${message.author.role.toUpperCase()} ${message.id} ---\n${parts}`;
}).join('\n');
fs.writeFileSync(process.argv[3], output);
