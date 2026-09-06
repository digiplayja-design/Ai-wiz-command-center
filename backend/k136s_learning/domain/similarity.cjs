'use strict';
// K136S - deterministic duplicate / contradiction detection. No model call; an optional LLM opinion (later phases) never decides alone.
const DUPLICATE_THRESHOLD = 0.85;
const STOPWORDS = new Set(['the', 'a', 'an', 'our', 'my', 'your', 'their', 'that', 'this', 'these', 'those', 'is', 'are', 'was', 'were', 'be', 'to', 'of', 'for', 'with', 'on', 'in', 'at', 'and', 'or', 'it', 'as', 'by', 'from', 'about', 'please', 'nova', 'do', 'does', 'not', 'never', 'always', 'should', 'must', 'can']);
const LEAD_VERBS = /^(?:(?:please\s+)?(?:remember|note|know|keep in mind)\s+(?:that\s+)?|always\s+|never\s+|from now on,?\s+|make sure (?:to|that)\s+|whenever?\s+|when\s+)/i;
const NEGATION = /\b(never|not|don't|do not|doesn't|does not|no longer|stop|avoid|without|isn't|is not|aren't|are not)\b/i;

function clean(text) { return String(text || '').toLowerCase().replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim(); }
function trigrams(text) {
  const t = `  ${clean(text)}  `;
  const set = new Set();
  for (let i = 0; i + 3 <= t.length; i++) set.add(t.slice(i, i + 3));
  return set;
}
function trigramSimilarity(a, b) {
  const A = trigrams(a), B = trigrams(b);
  if (A.size === 0 && B.size === 0) return 1;
  let inter = 0;
  for (const g of A) if (B.has(g)) inter++;
  return inter / (A.size + B.size - inter);
}
function stem(w) {
  if (w.length <= 4) return w;
  if (w.endsWith('ies')) return w.slice(0, -3) + 'y';
  if (w.endsWith('sses') || w.endsWith('shes') || w.endsWith('ches') || w.endsWith('xes')) return w.slice(0, -2);
  if (w.endsWith('ing') && w.length > 8) return w.slice(0, -3); // keep short -ing nouns like 'billing', collapse 'scheduling'
  if (w.endsWith('ed') && w.length > 5) return w.slice(0, -2);
  if (w.endsWith('s') && !w.endsWith('ss')) return w.slice(0, -1);
  return w;
}
function subjectKey(text) {
  const raw = String(text || '').trim();
  const explicit = raw.match(/^key:\s*([^\n]+?)(?:[.:;]|$)/i);
  if (explicit) return clean(explicit[1]).split(' ').filter(Boolean).map(stem).slice(0, 5).join(' ');
  const body = clean(raw.replace(LEAD_VERBS, ''));
  const words = body.split(' ').filter((w) => w && !STOPWORDS.has(w)).map(stem);
  return words.slice(0, 3).join(' ');
}
function sameScope(a, b) { return a.agentId === b.agentId && (a.type === undefined || b.type === undefined || a.type === b.type); }

function findDuplicates(candidate, existing, threshold = DUPLICATE_THRESHOLD) {
  const out = [];
  for (const e of existing || []) {
    if (!sameScope(candidate, e)) continue;
    if (candidate.contentHash && e.contentHash && candidate.contentHash === e.contentHash) { out.push({ id: e.id, similarity: 1, reason: 'hash' }); continue; }
    const sim = trigramSimilarity(candidate.normalizedText, e.normalizedText);
    if (sim >= threshold) out.push({ id: e.id, similarity: Number(sim.toFixed(3)), reason: 'trigram' });
  }
  return Object.freeze(out.sort((x, y) => y.similarity - x.similarity));
}
function findContradictions(candidate, existing, threshold = DUPLICATE_THRESHOLD) {
  const key = subjectKey(candidate.normalizedText);
  const out = [];
  if (!key) return Object.freeze(out);
  for (const e of existing || []) {
    if (e.agentId !== candidate.agentId) continue;
    if (candidate.category && e.category && candidate.category !== e.category) continue;
    if (subjectKey(e.normalizedText) !== key) continue;
    const sim = trigramSimilarity(candidate.normalizedText, e.normalizedText);
    if (sim >= threshold) continue; // a duplicate, not a contradiction
    const negFlip = NEGATION.test(candidate.normalizedText) !== NEGATION.test(e.normalizedText);
    out.push({ id: e.id, subjectKey: key, similarity: Number(sim.toFixed(3)), reason: negFlip ? 'negation' : 'different_value' });
  }
  return Object.freeze(out);
}

module.exports = { DUPLICATE_THRESHOLD, trigramSimilarity, subjectKey, findDuplicates, findContradictions };
