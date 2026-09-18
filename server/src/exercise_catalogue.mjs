// The server-side "global" additions layer for exercise activities,
// mirroring food_catalogue.mjs's role for food: the app's own bundled
// activity_catalogue.json (assets/parser/shared/) never changes here, this
// is the delta layer that lets a brand-new activity AI identifies (see the
// app's ExerciseCatalogueSyncService) reach every install without an
// app-store release. There is no bulk admin-import pipeline for exercise
// (unlike food) -- activities only ever arrive one at a time, from a real
// AI-derived MET for a specific session, via contributeActivity below.

import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';

const moduleRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const dataDir = process.env.DATA_DIR || join(moduleRoot, 'data');
const catalogueFile = join(dataDir, 'exercise-catalogue.json');
const catalogueMetaFile = join(dataDir, 'exercise-catalogue-meta.json');

const readJson = async (file, fallback) => {
  try {
    return JSON.parse(await readFile(file, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return fallback;
    throw error;
  }
};
const writeJson = async (file, data) => {
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, JSON.stringify(data, null, 2), { mode: 0o600 });
};

export const loadCatalogue = () => readJson(catalogueFile, []);
export const saveCatalogue = records => writeJson(catalogueFile, records);
export const loadMeta = () => readJson(catalogueMetaFile, { version: 0, changeLog: [] });
export const saveMeta = meta => writeJson(catalogueMetaFile, meta);

const MAX_CHANGELOG = 5000;

// Same bump-once-log-per-touched-id scheme as food_catalogue.mjs, so
// /exercise-catalogue/changes?since=N can answer "what changed" cheaply.
export async function bumpVersion(touchedIds, action) {
  const meta = await loadMeta();
  meta.version += 1;
  const at = new Date().toISOString();
  for (const id of touchedIds) meta.changeLog.push({ version: meta.version, id, action, at });
  if (meta.changeLog.length > MAX_CHANGELOG) meta.changeLog = meta.changeLog.slice(-MAX_CHANGELOG);
  await saveMeta(meta);
  return meta.version;
}

function normalizeText(value) {
  return String(value ?? '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function findMatch(name, locale, catalogue) {
  const normalized = normalizeText(name);
  if (!normalized) return null;
  return catalogue.find(item => {
    if (normalizeText(item.names?.[locale] || '') === normalized) return true;
    return Object.values(item.aliases || {}).some(list => list.some(alias => normalizeText(alias) === normalized));
  }) || null;
}

// The one write path a contributed activity goes through -- an AI-derived
// MET for something local truly didn't recognize. Never overwrites an
// existing activity's MET from a single sample (one AI session's estimate
// is not trusted over what may already be a curated or earlier-contributed
// value); a name that already matches just gets its new spelling merged in
// as an alias for future matching, the same "first contribution stands"
// rule food contributions use.
export async function contributeActivity(input) {
  const catalogue = await loadCatalogue();
  const name = String(input.name || '').trim();
  const locale = input.locale || 'en';
  const met = Number(input.met);
  if (!name) return { status: 'invalid', reason: 'An activity name is required' };
  if (!Number.isFinite(met) || met <= 0 || met > 25) {
    return { status: 'invalid', reason: 'A realistic MET value is required' };
  }
  const existing = findMatch(name, locale, catalogue);
  if (existing) {
    const normalized = normalizeText(name);
    const alreadyKnown =
      normalizeText(existing.names?.[locale] || '') === normalized ||
      (existing.aliases?.[locale] || []).some(alias => normalizeText(alias) === normalized);
    if (alreadyKnown) return { status: 'exists', record: existing };
    existing.aliases = existing.aliases || {};
    existing.aliases[locale] = [...new Set([...(existing.aliases[locale] || []), name])];
    existing.updatedAt = new Date().toISOString();
    await saveCatalogue(catalogue);
    await bumpVersion([existing.id], 'alias-merge');
    return { status: 'exists-different', record: existing };
  }
  const now = new Date().toISOString();
  const record = {
    id: randomUUID(),
    category: input.category || 'other',
    names: { [locale]: name },
    aliases: {},
    met: Math.round(met * 10) / 10,
    source: 'user',
    createdBy: input.createdBy || null,
    createdAt: now,
    updatedAt: now,
  };
  catalogue.push(record);
  await saveCatalogue(catalogue);
  const version = await bumpVersion([record.id], 'add');
  return { status: 'created', record, version };
}

export async function getChangesSince(sinceVersion) {
  const meta = await loadMeta();
  const relevant = meta.changeLog.filter(entry => entry.version > sinceVersion);
  const catalogue = await loadCatalogue();
  const byId = new Map(catalogue.map(item => [item.id, item]));
  const touchedIds = [...new Set(relevant.map(entry => entry.id))];
  const removedIds = [...new Set(relevant.filter(e => e.action === 'remove' && !byId.has(e.id)).map(e => e.id))];
  const activities = touchedIds.filter(id => byId.has(id)).map(id => byId.get(id));
  return { version: meta.version, activities, removed: removedIds };
}
