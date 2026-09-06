'use strict';
// K136S - normalization of spoken text, canonical content hash, and a word-level diff for the preview.
const crypto = require('node:crypto');

const WAKE = /^(?:hey|ok|okay|hi)?\s*nova[,:!.]?\s+/i;
const FILLERS = /\b(?:um+|uh+|erm+|hmm+|like,)\s*/gi;
const LEAD = /^(?:please|so|well|alright|right),?\s+/i;

function normalize(text) {
  let t = String(text || '').replace(/\s+/g, ' ').trim();
  t = t.replace(WAKE, '').replace(LEAD, '').replace(FILLERS, '').replace(/\s+/g, ' ').trim();
  for (let prev = null; prev !== t; ) { // peel any lead-ins/punctuation the wake or filler strip exposed, until stable
    prev = t;
    t = t.replace(/^[\s,;:.!?-]+/, '').replace(LEAD, '').replace(FILLERS, '').replace(/\s+/g, ' ').trim();
  }
  t = t.replace(/\s+([,.;:!?])/g, '$1').replace(/([,.;:!?])(?=[^\s])/g, '$1 ').replace(/\s+/g, ' ').trim();
  if (!t) return '';
  t = t.charAt(0).toUpperCase() + t.slice(1);
  if (!/[.!?]$/.test(t)) t += '.';
  return t;
}

function canonical(fields) {
  const keys = ['agentId', 'text', 'type', 'category', 'sensitivity', 'expiresAt'];
  const out = {};
  for (const k of keys) out[k] = fields[k] === undefined || fields[k] === null ? null : String(fields[k]);
  return JSON.stringify(out);
}
function contentHash(fields) {
  for (const k of ['agentId', 'text', 'type']) if (!fields || typeof fields[k] !== 'string' || !fields[k]) throw new TypeError(`contentHash: ${k} required`);
  return crypto.createHash('sha256').update(canonical(fields), 'utf8').digest('hex');
}

function tokenize(text) { return String(text || '').split(/\s+/).filter(Boolean); }
function diffWords(oldText, newText) {
  const a = tokenize(oldText), b = tokenize(newText);
  const n = a.length, m = b.length;
  const lcs = Array.from({ length: n + 1 }, () => new Uint16Array(m + 1));
  for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--) lcs[i][j] = a[i] === b[j] ? lcs[i + 1][j + 1] + 1 : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
  const ops = [];
  let i = 0, j = 0;
  const push = (op, text) => { const last = ops[ops.length - 1]; if (last && last.op === op) last.text += ' ' + text; else ops.push({ op, text }); };
  while (i < n && j < m) {
    if (a[i] === b[j]) { push('equal', a[i]); i++; j++; }
    else if (lcs[i + 1][j] >= lcs[i][j + 1]) { push('delete', a[i]); i++; }
    else { push('insert', b[j]); j++; }
  }
  while (i < n) push('delete', a[i++]);
  while (j < m) push('insert', b[j++]);
  const changed = ops.some((o) => o.op !== 'equal');
  return Object.freeze({ changed, ops: Object.freeze(ops.map((o) => Object.freeze(o))) });
}

module.exports = { normalize, canonical, contentHash, diffWords };
