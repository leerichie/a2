// The ONE canonical food catalogue store shared by every source: the
// server-side "global" additions/overrides layer that sits ABOVE whatever
// generic foods already ship inside the app (assets/parser/... in the a2
// repo). This module never touches that bundled data -- it is the delta
// layer that lets new foods, aliases, translations and portions reach every
// app install without an app-store release (see the app's
// CatalogueSyncService, which downloads from here).
//
// Every write path -- admin import, user "add this food" contribution --
// goes through the SAME functions here (mergeRow/contributeFood), so there
// is exactly one merge policy, one trust hierarchy, and one version/change
// log, never a second parallel food database.

import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import * as XLSX from 'xlsx';

const moduleRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const dataDir = process.env.DATA_DIR || join(moduleRoot, 'data');
const catalogueFile = join(dataDir, 'food-catalogue.json');
const catalogueMetaFile = join(dataDir, 'food-catalogue-meta.json');
const importBatchesFile = join(dataDir, 'food-import-batches.json');
const importProfilesFile = join(dataDir, 'food-import-profiles.json');

// Higher wins. Built-in/curated data (the app's own bundled dataset, never
// stored here, only referenced by trust rank when a row claims to BE that
// source) always outranks an admin import, which always outranks a single
// user's own contribution -- so a later, lower-trust write can never
// silently clobber better existing data.
export const TRUST_RANK = { builtin: 3, admin: 2, user: 1 };

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
export const loadImportBatches = () => readJson(importBatchesFile, []);
export const saveImportBatches = batches => writeJson(importBatchesFile, batches);
export const loadImportProfiles = () => readJson(importProfilesFile, []);
export const saveImportProfiles = profiles => writeJson(importProfilesFile, profiles);

const MAX_CHANGELOG = 5000;

// Bumps the catalogue version once and appends one change-log entry per
// touched food id, so /catalogue/changes?since=N can answer "what changed"
// without re-diffing the whole catalogue on every app sync.
export async function bumpVersion(touchedIds, action) {
  const meta = await loadMeta();
  meta.version += 1;
  const at = new Date().toISOString();
  for (const id of touchedIds) meta.changeLog.push({ version: meta.version, id, action, at });
  if (meta.changeLog.length > MAX_CHANGELOG) meta.changeLog = meta.changeLog.slice(-MAX_CHANGELOG);
  await saveMeta(meta);
  return meta.version;
}

export function normalizeText(value) {
  return String(value ?? '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function tokenSet(value) {
  return new Set(normalizeText(value).split(' ').filter(Boolean));
}

// Cheap token-overlap similarity (Jaccard) -- good enough to SUGGEST a
// fuzzy match for a human to confirm, never to auto-apply one.
function similarity(a, b) {
  const ta = tokenSet(a);
  const tb = tokenSet(b);
  if (!ta.size || !tb.size) return 0;
  let shared = 0;
  for (const t of ta) if (tb.has(t)) shared += 1;
  return shared / new Set([...ta, ...tb]).size;
}

function allNames(record) {
  const names = [];
  for (const locale of Object.keys(record.names || {})) if (record.names[locale]) names.push(record.names[locale]);
  for (const locale of Object.keys(record.aliases || {})) for (const alias of record.aliases[locale] || []) names.push(alias);
  return names;
}

// Exact match first (canonical id, then trusted source+sourceId, then any
// normalized name/alias hit); a fuzzy candidate is returned separately and
// must never be treated as an automatic match -- see importPreview.
export function findMatch(record, catalogue) {
  if (record.canonicalId) {
    const byCanonical = catalogue.find(item => item.canonicalId === record.canonicalId);
    if (byCanonical) return { record: byCanonical, kind: 'canonicalId' };
  }
  if (record.source && record.sourceId) {
    const bySource = catalogue.find(item => item.source === record.source && item.sourceId === record.sourceId);
    if (bySource) return { record: bySource, kind: 'source' };
  }
  const incomingNames = allNames(record).map(normalizeText).filter(Boolean);
  for (const item of catalogue) {
    const existingNames = allNames(item).map(normalizeText);
    if (incomingNames.some(n => existingNames.includes(n))) return { record: item, kind: 'name' };
  }
  return null;
}

export function findFuzzyMatch(record, catalogue, threshold = 0.6) {
  const name = record.names?.en || record.names?.pl || '';
  if (!name) return null;
  let best = null;
  for (const item of catalogue) {
    for (const candidateName of allNames(item)) {
      const score = similarity(name, candidateName);
      if (score >= threshold && (!best || score > best.score)) best = { record: item, score };
    }
  }
  return best;
}

function mergeNamesAndAliases(existing, incoming) {
  const names = { ...existing.names };
  const aliases = { ...existing.aliases };
  for (const locale of Object.keys(incoming.names || {})) {
    if (!names[locale]) names[locale] = incoming.names[locale];
    else if (names[locale] !== incoming.names[locale]) {
      aliases[locale] = [...new Set([...(aliases[locale] || []), incoming.names[locale]])];
    }
  }
  for (const locale of Object.keys(incoming.aliases || {})) {
    aliases[locale] = [...new Set([...(aliases[locale] || []), ...(incoming.aliases[locale] || [])])];
  }
  return { names, aliases };
}

// The single merge policy every write path shares. Returns what actually
// happened so callers (import preview/confirm, user contribution) can
// report it honestly instead of pretending every write "succeeded" the way
// the caller hoped.
export function classifyRow(record, catalogue) {
  const exact = findMatch(record, catalogue);
  if (!record.names?.en && !record.names?.pl) return { action: 'invalid', reason: 'Missing a name' };
  if (record.kcalPer100g == null) return { action: 'invalid', reason: 'Missing calories' };
  if (!exact) {
    const fuzzy = findFuzzyMatch(record, catalogue);
    if (fuzzy) return { action: 'suggested-match', existing: fuzzy.record, score: fuzzy.score };
    return { action: 'new' };
  }
  const existing = exact.record;
  const existingRank = TRUST_RANK[existing.trust] ?? 0;
  const incomingRank = TRUST_RANK[record.trust] ?? 0;
  const nutritionChanged =
    existing.kcalPer100g !== record.kcalPer100g ||
    existing.proteinPer100g !== record.proteinPer100g ||
    existing.carbsPer100g !== record.carbsPer100g;
  if (!nutritionChanged) return { action: 'matched-nochange', existing, matchKind: exact.kind };
  if (incomingRank > existingRank) return { action: 'matched-update', existing, matchKind: exact.kind };
  if (incomingRank === existingRank) return { action: 'conflict', existing, matchKind: exact.kind };
  // Lower trust than what's already there: never silently overwrite, but
  // aliases/portions are still safe to merge onto the trusted record.
  return { action: 'matched-alias-only', existing, matchKind: exact.kind };
}

export function applyRow(record, catalogue, { decision } = {}) {
  const classification = classifyRow(record, catalogue);
  const effectiveAction = decision || classification.action;
  const now = new Date().toISOString();
  if (effectiveAction === 'invalid' || effectiveAction === 'skip') {
    return { action: 'skip', id: null, before: null };
  }
  if (effectiveAction === 'new' || (effectiveAction === 'create-separate')) {
    const created = {
      id: randomUUID(),
      canonicalId: record.canonicalId || null,
      category: record.category || null,
      names: record.names || {},
      aliases: record.aliases || {},
      kcalPer100g: record.kcalPer100g ?? null,
      proteinPer100g: record.proteinPer100g ?? null,
      carbsPer100g: record.carbsPer100g ?? null,
      fatPer100g: record.fatPer100g ?? null,
      fibrePer100g: record.fibrePer100g ?? null,
      servingAmount: record.servingAmount ?? null,
      servingUnit: record.servingUnit ?? null,
      portions: record.portions || [],
      source: record.source || 'unknown',
      sourceId: record.sourceId || null,
      trust: record.trust || 'user',
      createdBy: record.createdBy || null,
      createdAt: now,
      updatedAt: now,
    };
    catalogue.push(created);
    return { action: 'created', id: created.id, before: null };
  }
  const existing = classification.existing;
  if (!existing) return { action: 'skip', id: null, before: null };
  const before = JSON.parse(JSON.stringify(existing));
  if (effectiveAction === 'matched-nochange') return { action: 'nochange', id: existing.id, before: null };
  if (effectiveAction === 'matched-alias-only' || effectiveAction === 'merge') {
    Object.assign(existing, mergeNamesAndAliases(existing, record));
    existing.portions = [...(existing.portions || []), ...(record.portions || [])];
    existing.updatedAt = now;
    return { action: 'aliases-merged', id: existing.id, before };
  }
  if (effectiveAction === 'matched-update' || effectiveAction === 'use-imported') {
    Object.assign(existing, mergeNamesAndAliases(existing, record));
    existing.category = record.category || existing.category;
    existing.kcalPer100g = record.kcalPer100g ?? existing.kcalPer100g;
    existing.proteinPer100g = record.proteinPer100g ?? existing.proteinPer100g;
    existing.carbsPer100g = record.carbsPer100g ?? existing.carbsPer100g;
    existing.fatPer100g = record.fatPer100g ?? existing.fatPer100g;
    existing.fibrePer100g = record.fibrePer100g ?? existing.fibrePer100g;
    existing.portions = [...(existing.portions || []), ...(record.portions || [])];
    existing.source = record.source || existing.source;
    existing.sourceId = record.sourceId ?? existing.sourceId;
    existing.trust = record.trust && TRUST_RANK[record.trust] >= TRUST_RANK[existing.trust] ? record.trust : existing.trust;
    existing.updatedAt = now;
    return { action: 'updated', id: existing.id, before };
  }
  if (effectiveAction === 'keep' || effectiveAction === 'conflict') {
    return { action: 'kept', id: existing.id, before: null };
  }
  return { action: 'skip', id: null, before: null };
}

// ---- File parsing (CSV / XLSX / JSON) into raw {header: value} rows ----

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = '';
  let inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (inQuotes) {
      if (char === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; } else inQuotes = false;
      } else field += char;
    } else if (char === '"') inQuotes = true;
    else if (char === ',') { row.push(field); field = ''; }
    else if (char === '\n' || char === '\r') {
      if (char === '\r' && text[i + 1] === '\n') i++;
      row.push(field); field = '';
      if (row.some(v => v !== '')) rows.push(row);
      row = [];
    } else field += char;
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row); }
  if (!rows.length) return { headers: [], rows: [] };
  const [headers, ...body] = rows;
  return { headers, rows: body.map(cells => Object.fromEntries(headers.map((h, i) => [h, cells[i] ?? '']))) };
}

function parseXlsx(buffer) {
  const workbook = XLSX.read(buffer, { type: 'buffer' });
  const sheet = workbook.Sheets[workbook.SheetNames[0]];
  const json = XLSX.utils.sheet_to_json(sheet, { defval: '' });
  const headers = json.length ? Object.keys(json[0]) : [];
  return { headers, rows: json };
}

function parseJsonFile(text) {
  const data = JSON.parse(text);
  const list = Array.isArray(data) ? data : Array.isArray(data.foods) ? data.foods : [];
  const headers = list.length ? Object.keys(list[0]) : [];
  return { headers, rows: list };
}

export function parseUploadedFile(buffer, format) {
  if (format === 'xlsx') return parseXlsx(buffer);
  const text = buffer.toString('utf8');
  if (format === 'json') return parseJsonFile(text);
  return parseCsv(text);
}

// Best-effort header -> field guesses so most datasets need little/no
// manual remapping, while still letting the admin console override any of
// these choices before previewing.
const FIELD_GUESSES = {
  canonicalId: ['canonical_id', 'canonicalid', 'id', 'food_id', 'code'],
  nameEn: ['name', 'english_name', 'name_en', 'description', 'food_name', 'canonical'],
  namePl: ['name_pl', 'polish_name', 'nazwa'],
  aliasesEn: ['aliases', 'aliases_en', 'synonyms', 'also_known_as'],
  aliasesPl: ['aliases_pl', 'synonimy'],
  category: ['category', 'food_category', 'group'],
  kcal: ['kcal', 'calories', 'energy_kcal', 'energy'],
  protein: ['protein', 'protein_g'],
  carbs: ['carbs', 'carbohydrate', 'carbohydrates', 'carb_g'],
  fat: ['fat', 'fat_g', 'total_fat'],
  fibre: ['fibre', 'fiber', 'fibre_g'],
  basis: ['basis', 'nutrition_basis', 'per'],
  servingAmount: ['serving_amount', 'serving_size', 'portion_amount'],
  servingUnit: ['serving_unit', 'portion_unit'],
  householdPortions: ['household_portions', 'portions'],
  source: ['source', 'dataset'],
  sourceId: ['source_id', 'external_id', 'fdc_id', 'ndb_no'],
};

export function guessColumnMapping(headers) {
  const normalizedHeaders = headers.map(h => ({ raw: h, norm: normalizeText(h).replace(/ /g, '_') }));
  const mapping = {};
  for (const [field, candidates] of Object.entries(FIELD_GUESSES)) {
    const found = normalizedHeaders.find(h => candidates.includes(h.norm));
    if (found) mapping[field] = found.raw;
  }
  return mapping;
}

function toNumber(value) {
  if (value === '' || value == null) return null;
  const n = Number(String(value).replace(',', '.'));
  return Number.isFinite(n) ? n : null;
}

function round1(value) {
  return value == null ? null : Math.round(value * 10) / 10;
}

// The catalogue always stores nutrition per-100g/100ml (matching the app's
// own NutritionCatalogue schema exactly, so no conversion is needed at
// parse time) -- a dataset or a user reporting "per serving" numbers is
// normalized here, once, using its own serving amount, rather than
// carrying two parallel bases through the rest of the pipeline.
function normalizeToPer100(values, basis, servingAmount) {
  if (basis !== 'perServing') return values;
  if (!servingAmount || servingAmount <= 0) return { kcal: null, protein: null, carbs: null, fat: null, fibre: null };
  const scale = 100 / servingAmount;
  return {
    kcal: round1(values.kcal == null ? null : values.kcal * scale),
    protein: round1(values.protein == null ? null : values.protein * scale),
    carbs: round1(values.carbs == null ? null : values.carbs * scale),
    fat: round1(values.fat == null ? null : values.fat * scale),
    fibre: round1(values.fibre == null ? null : values.fibre * scale),
  };
}

// Converts one raw {header: value} row into the shared record shape used
// by classifyRow/applyRow, using the given column mapping.
export function mapRow(raw, mapping, { trust, source, defaultBasis = 'per100g' } = {}) {
  const get = field => (mapping[field] ? raw[mapping[field]] : undefined);
  const nameEn = get('nameEn');
  const namePl = get('namePl');
  const aliasesEn = String(get('aliasesEn') || '').split(/[|;]/).map(s => s.trim()).filter(Boolean);
  const aliasesPl = String(get('aliasesPl') || '').split(/[|;]/).map(s => s.trim()).filter(Boolean);
  const householdPortions = String(get('householdPortions') || '')
    .split(/[|;]/)
    .map(entry => entry.trim())
    .filter(Boolean)
    .map(entry => {
      const [unit, grams] = entry.split(':').map(s => s.trim());
      return unit && grams ? { unit, grams: toNumber(grams) } : null;
    })
    .filter(Boolean);
  const basis = get('basis') || defaultBasis;
  const servingAmount = toNumber(get('servingAmount'));
  const per100 = normalizeToPer100(
    { kcal: toNumber(get('kcal')), protein: toNumber(get('protein')), carbs: toNumber(get('carbs')), fat: toNumber(get('fat')), fibre: toNumber(get('fibre')) },
    basis,
    servingAmount,
  );
  return {
    canonicalId: get('canonicalId') ? normalizeText(get('canonicalId')).replace(/ /g, '_') : null,
    category: get('category') || null,
    names: { ...(nameEn ? { en: String(nameEn).trim() } : {}), ...(namePl ? { pl: String(namePl).trim() } : {}) },
    aliases: { ...(aliasesEn.length ? { en: aliasesEn } : {}), ...(aliasesPl.length ? { pl: aliasesPl } : {}) },
    kcalPer100g: per100.kcal,
    proteinPer100g: per100.protein,
    carbsPer100g: per100.carbs,
    fatPer100g: per100.fat,
    fibrePer100g: per100.fibre,
    servingAmount,
    servingUnit: get('servingUnit') || null,
    portions: householdPortions,
    source: get('source') || source || 'import',
    sourceId: get('sourceId') || null,
    trust: trust || 'admin',
  };
}

// ---- In-memory pending-preview sessions (short-lived, admin-only) ----

const pendingPreviews = new Map();
const PREVIEW_TTL_MS = 60 * 60 * 1000;

setInterval(() => {
  const now = Date.now();
  for (const [id, session] of pendingPreviews) if (now - session.createdAt > PREVIEW_TTL_MS) pendingPreviews.delete(id);
}, 10 * 60 * 1000).unref?.();

export function storePreview(session) {
  const id = randomUUID();
  pendingPreviews.set(id, { ...session, createdAt: Date.now() });
  return id;
}
export function getPreview(id) {
  return pendingPreviews.get(id) || null;
}
export function deletePreview(id) {
  pendingPreviews.delete(id);
}

export function buildPreview(mappedRows) {
  const summary = { total: mappedRows.length, new: 0, matchedUpdate: 0, matchedNoChange: 0, aliasOnly: 0, conflicts: 0, suggested: 0, invalid: 0 };
  const rows = [];
  const seenKeys = new Set();
  const workingCatalogueRef = { list: null }; // set by caller before use
  return { summary, rows, seenKeys, workingCatalogueRef };
}

export function classifyImportRows(mappedRows, catalogue) {
  const summary = { total: mappedRows.length, new: 0, matchedUpdate: 0, matchedNoChange: 0, aliasOnly: 0, conflicts: 0, suggested: 0, invalid: 0, duplicateInFile: 0 };
  const rows = [];
  const seenInFile = new Set();
  mappedRows.forEach((record, index) => {
    const dedupeKey = normalizeText(record.names?.en || record.names?.pl || `${index}`);
    const isDuplicateInFile = seenInFile.has(dedupeKey);
    seenInFile.add(dedupeKey);
    const classification = classifyRow(record, catalogue);
    const row = { index, record, ...classification };
    if (isDuplicateInFile && classification.action === 'new') {
      row.action = 'duplicate-in-file';
      summary.duplicateInFile += 1;
    } else {
      switch (classification.action) {
        case 'new': summary.new += 1; break;
        case 'matched-update': summary.matchedUpdate += 1; break;
        case 'matched-nochange': summary.matchedNoChange += 1; break;
        case 'matched-alias-only': summary.aliasOnly += 1; break;
        case 'conflict': summary.conflicts += 1; break;
        case 'suggested-match': summary.suggested += 1; break;
        case 'invalid': summary.invalid += 1; break;
      }
    }
    rows.push(row);
  });
  return { summary, rows };
}

export function exportCatalogueRows(catalogue, format) {
  const flat = catalogue.map(item => ({
    canonical_id: item.canonicalId || '',
    name_en: item.names?.en || '',
    name_pl: item.names?.pl || '',
    aliases_en: (item.aliases?.en || []).join('|'),
    aliases_pl: (item.aliases?.pl || []).join('|'),
    category: item.category || '',
    kcal: item.kcalPer100g ?? '',
    protein: item.proteinPer100g ?? '',
    carbs: item.carbsPer100g ?? '',
    fat: item.fatPer100g ?? '',
    fibre: item.fibrePer100g ?? '',
    serving_amount: item.servingAmount ?? '',
    serving_unit: item.servingUnit || '',
    household_portions: (item.portions || []).map(p => `${p.unit}:${p.grams}`).join('|'),
    source: item.source || '',
    source_id: item.sourceId || '',
    trust: item.trust || '',
    created_at: item.createdAt || '',
    updated_at: item.updatedAt || '',
  }));
  if (format === 'json') return { contentType: 'application/json', body: JSON.stringify(flat, null, 2) };
  if (format === 'xlsx') {
    const sheet = XLSX.utils.json_to_sheet(flat);
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, sheet, 'Foods');
    return { contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', body: XLSX.write(workbook, { type: 'buffer', bookType: 'xlsx' }) };
  }
  const headers = flat.length ? Object.keys(flat[0]) : [];
  const csvField = value => {
    const s = String(value ?? '');
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const csv = [headers.join(','), ...flat.map(row => headers.map(h => csvField(row[h])).join(','))].join('\r\n');
  return { contentType: 'text/csv', body: csv };
}

// ---- Public API used by both the admin import flow and app contributions ----

export async function contributeFood(input) {
  const catalogue = await loadCatalogue();
  // A user reports "this many calories for this portion" -- normalized to
  // per-100g/ml immediately, same as an admin-imported per-serving row, so
  // the stored catalogue only ever has one basis.
  const servingAmount = toNumber(input.servingAmount);
  const isPerServing = input.basis !== 'per100g' && input.basis !== 'per100ml';
  const per100 = normalizeToPer100(
    { kcal: toNumber(input.kcal), protein: toNumber(input.protein), carbs: toNumber(input.carbs), fat: toNumber(input.fat), fibre: toNumber(input.fibre) },
    isPerServing ? 'perServing' : 'per100g',
    servingAmount,
  );
  const record = {
    canonicalId: null,
    category: input.category || null,
    names: { [input.locale || 'en']: input.name.trim() },
    aliases: {},
    kcalPer100g: isPerServing ? per100.kcal : toNumber(input.kcal),
    proteinPer100g: isPerServing ? per100.protein : toNumber(input.protein),
    carbsPer100g: isPerServing ? per100.carbs : toNumber(input.carbs),
    fatPer100g: isPerServing ? per100.fat : toNumber(input.fat),
    fibrePer100g: isPerServing ? per100.fibre : toNumber(input.fibre),
    servingAmount,
    servingUnit: input.servingUnit || null,
    portions: servingAmount ? [{ unit: input.servingUnit || 'portion', grams: servingAmount }] : [],
    source: 'user',
    sourceId: null,
    trust: 'user',
    createdBy: input.createdBy || null,
  };
  const classification = classifyRow(record, catalogue);
  if (classification.action === 'invalid') return { status: 'invalid', reason: classification.reason };
  if (classification.action === 'matched-nochange') {
    return { status: 'exists', record: classification.existing };
  }
  if (classification.action === 'matched-update' || classification.action === 'conflict' || classification.action === 'matched-alias-only') {
    // A user contribution NEVER overwrites or out-ranks existing data --
    // trusted/admin data always wins, and even another user's earlier entry
    // is left alone (first contribution stands) to avoid one person's typo
    // clobbering another's good-faith entry. We still merge in any new
    // alias/spelling for future matching.
    const result = applyRow(record, catalogue, { decision: 'matched-alias-only' });
    if (result.id) {
      await saveCatalogue(catalogue);
      await bumpVersion([result.id], 'alias-merge');
    }
    return { status: 'exists-different', record: classification.existing };
  }
  const result = applyRow(record, catalogue, { decision: 'new' });
  await saveCatalogue(catalogue);
  const version = await bumpVersion([result.id], 'add');
  return { status: 'created', record: catalogue.find(item => item.id === result.id), version };
}

export async function getChangesSince(sinceVersion) {
  const meta = await loadMeta();
  const relevant = meta.changeLog.filter(entry => entry.version > sinceVersion);
  const catalogue = await loadCatalogue();
  const byId = new Map(catalogue.map(item => [item.id, item]));
  const touchedIds = [...new Set(relevant.map(entry => entry.id))];
  const removedIds = [...new Set(relevant.filter(e => e.action === 'remove' && !byId.has(e.id)).map(e => e.id))];
  const foods = touchedIds.filter(id => byId.has(id)).map(id => byId.get(id));
  return { version: meta.version, foods, removed: removedIds };
}
