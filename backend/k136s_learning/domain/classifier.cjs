'use strict';
// K136S - deterministic classifier. Rule order: PROHIBITED > TOOL_PERMISSION > PROFILE > TRAINING > MEMORY.
// Every decision is explainable (reasons[]) and testable; no model call is made here.
const { ENTRY_TYPES } = require('./state_machine.cjs');

const SENSITIVITY = Object.freeze({ LOW: 'low', MEDIUM: 'medium', HIGH: 'high' });
const RULES = Object.freeze({
  PROHIBITED: [
    /\bsystem prompt\b/i,
    /\bignore (all |any )?(previous|prior|earlier) instructions\b/i,
    /\b(disable|bypass|skip|turn off|remove) (the |all |your )?(security|safety|approval|approvals|vault|audit|audits|logging|guardrails?)\b/i,
    /\b(other|all|every) (tenants?|accounts?|users?|customers?|companies)('s?)? (data|memory|memories|information|files|records)\b/i,
    /\bcross[- ]tenant\b/i,
    /\b(password|passcode|pin|api key|secret key|secret|token|credentials?)\s+(is|are|equals|=|:)\s*\S/i,
    /\b(store|save|remember|keep) (my|the|this|their|our) (password|passcode|pin|api key|secret|token|credentials?)\b/i,
  ],
  TOOL_PERMISSION: [
    /\b(you (can|may|should) now|from now on you (can|may)|allow (nova|you|yourself)|nova (can|may) now|grant(ing)? (nova|you|yourself)|give (nova|you|yourself) (permission|access)|authorize (nova|you|yourself)|permission to)\b[^.]*\b(send|delete|schedule|email|join|access|zoom|calendar|pay|purchase|export|share|post|call|text|sms)\b/i,
    /\b(send|delete|schedule|join|access|share|post) [^.]*\b(on my behalf|without asking|without confirmation|automatically)\b/i,
  ],
  PROFILE: [
    /\byour (name|persona|personality|mission|role|voice|tone of voice|character) (is|will be|should be|becomes)\b/i,
    /\b(act as|you are now|from now on you are|call yourself|introduce yourself as|your new (name|persona|mission|role) is)\b/i,
  ],
  TRAINING: [
    /\b(always|never|whenever|every time|each time)\b/i,
    /\bwhen(ever)? (a|an|the|someone|somebody|any|our|clients?|customers?|users?|prospects?|callers?)\b/i,
    /\bif (a|an|the|someone|somebody|any|our|clients?|customers?|users?|prospects?)\b/i,
    /\b(escalate|escalation|policy|policies|rule|rules|workflow|procedure|process is|checklist|steps? (are|is)|make sure (to|you)|do not|don't|should|must|respond (with|by|in)|reply (with|in)|answer (with|in)|use (a|an|the)?\s?\w* tone|sign off|greet)\b/i,
  ],
});
const CATEGORY_RULES = Object.freeze({
  MEMORY: [
    ['contact', /\b(phone|mobile|cell|email address|address|contact|extension)\b/i],
    ['preference', /\b(prefers?|preferred|likes?|dislikes?|favou?rite|wants?|hates?)\b/i],
    ['account_knowledge', /\b(client|customer|account|contract|renewal|invoice|order|subscription|deal|project)\b/i],
    ['business_context', /\b(our|we|company|team|product|pricing|office|hours|location)\b/i],
  ],
  TRAINING: [
    ['escalation', /\bescalat/i],
    ['policy', /\b(policy|policies|never|must not|do not|don't|not allowed|forbidden)\b/i],
    ['workflow', /\b(workflow|step|steps|process|procedure|checklist|first|then|before|after)\b/i],
    ['style', /\b(tone|style|format|greet|greeting|sign off|respond|reply|answer|wording|voice)\b/i],
  ],
});
const SENSITIVE_PATTERNS = Object.freeze([
  /\b\d{3}[-.\s]?\d{3}[-.\s]?\d{4}\b/,            // phone
  /\b[\w.+-]+@[\w-]+\.[\w.-]+\b/,                    // email
  /\b\d{3}-\d{2}-\d{4}\b/,                           // ssn
  /\b(?:\d[ -]?){13,16}\b/,                          // card-like
  /\b(confidential|salary|salaries|medical|health|diagnosis|lawsuit|litigation|divorce|password|ssn|social security)\b/i,
]);
const WORD_NUMBERS = { a: 1, an: 1, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10, twelve: 12, fourteen: 14, thirty: 30 };
const DAYS = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
const MONTHS = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];

function firstMatch(rules, text) { for (const re of rules) if (re.test(text)) return re; return null; }
function endOfUtcDay(d) { const x = new Date(d); x.setUTCHours(23, 59, 59, 0); return x; }

// Returns an ISO timestamp or null. `now` is a ms epoch used for deterministic tests.
function parseExpiry(text, now = Date.now()) {
  const t = String(text).toLowerCase();
  const base = new Date(now);
  let m;
  if ((m = t.match(/\b(?:until|till|through|expires? (?:on|by))\s+(?:next\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b/))) {
    const target = DAYS.indexOf(m[1]); let delta = (target - base.getUTCDay() + 7) % 7; if (delta === 0) delta = 7;
    const d = new Date(now + delta * 86400000); return endOfUtcDay(d).toISOString();
  }
  if ((m = t.match(/\b(?:until|till|through|expires? (?:on|by))\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{1,2})(?:st|nd|rd|th)?\b/))) {
    const month = MONTHS.indexOf(m[1]); const day = Number(m[2]);
    let d = new Date(Date.UTC(base.getUTCFullYear(), month, day, 23, 59, 59)); if (d.getTime() < now) d = new Date(Date.UTC(base.getUTCFullYear() + 1, month, day, 23, 59, 59));
    return d.toISOString();
  }
  if ((m = t.match(/\bfor (?:the next |the coming )?(\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten|twelve|fourteen|thirty)\s+(day|week|month)s?\b/))) {
    const n = WORD_NUMBERS[m[1]] || Number(m[1]); const unit = m[2] === 'day' ? 1 : m[2] === 'week' ? 7 : 30;
    return endOfUtcDay(new Date(now + n * unit * 86400000)).toISOString();
  }
  if (/\b(for today|just for today|only today|today only)\b/.test(t)) return endOfUtcDay(base).toISOString();
  if (/\b(this week|for the week|until end of (the )?week)\b/.test(t)) { const delta = (7 - base.getUTCDay()) % 7; return endOfUtcDay(new Date(now + delta * 86400000)).toISOString(); }
  if (/\b(temporar(y|ily)|for now|short[- ]term)\b/.test(t)) return endOfUtcDay(new Date(now + 7 * 86400000)).toISOString();
  return null;
}

function sensitivityOf(text, type, category) {
  if (SENSITIVE_PATTERNS.some((re) => re.test(text))) return SENSITIVITY.HIGH;
  if (type === ENTRY_TYPES.PROFILE || type === ENTRY_TYPES.TOOL_PERMISSION) return SENSITIVITY.MEDIUM;
  if (category === 'account_knowledge' || category === 'business_context' || category === 'contact') return SENSITIVITY.MEDIUM;
  return SENSITIVITY.LOW;
}

function classify(text, opts = {}) {
  const now = Number.isFinite(opts.now) ? opts.now : Date.now();
  const src = String(text || '').trim();
  const reasons = [];
  let type = ENTRY_TYPES.MEMORY;
  let category = 'general';
  for (const t of ['PROHIBITED', 'TOOL_PERMISSION', 'PROFILE', 'TRAINING']) {
    const re = firstMatch(RULES[t], src);
    if (re) { type = ENTRY_TYPES[t]; reasons.push(`${t}:${re.source.slice(0, 40)}`); break; }
  }
  if (type === ENTRY_TYPES.MEMORY || type === ENTRY_TYPES.TRAINING) {
    for (const [name, re] of CATEGORY_RULES[type]) if (re.test(src)) { category = name; break; }
    if (category === 'general' && type === ENTRY_TYPES.TRAINING) category = 'behavior';
  } else if (type === ENTRY_TYPES.PROFILE) category = 'persona';
  else if (type === ENTRY_TYPES.TOOL_PERMISSION) category = 'permission';
  else category = 'prohibited';
  if (type === ENTRY_TYPES.MEMORY && reasons.length === 0) reasons.push('MEMORY:default');
  const sensitivity = sensitivityOf(src, type, category);
  const expiresAt = type === ENTRY_TYPES.MEMORY || type === ENTRY_TYPES.TRAINING ? parseExpiry(src, now) : null;
  return Object.freeze({ type, category, sensitivity, expiresAt, reasons: Object.freeze(reasons), overrides: Object.freeze([]) });
}

const OVERRIDABLE_TYPES = new Set([ENTRY_TYPES.MEMORY, ENTRY_TYPES.TRAINING, ENTRY_TYPES.PROFILE]);
const SLUG = /^[a-z][a-z0-9_]{1,39}$/;

// User correction of a classification. Fail closed: PROHIBITED is immutable, TOOL_PERMISSION cannot be downgraded.
function reclassify(classification, override = {}, opts = {}) {
  const now = Number.isFinite(opts.now) ? opts.now : Date.now();
  if (!classification || typeof classification !== 'object') return { ok: false, code: 'INVALID_CLASSIFICATION' };
  if (classification.type === ENTRY_TYPES.PROHIBITED) return { ok: false, code: 'PROHIBITED_IMMUTABLE' };
  const next = Object.assign({}, classification, { overrides: classification.overrides.slice() });
  if (override.type !== undefined) {
    if (classification.type === ENTRY_TYPES.TOOL_PERMISSION && override.type !== ENTRY_TYPES.TOOL_PERMISSION) return { ok: false, code: 'TOOL_PERMISSION_LOCKED' };
    if (!OVERRIDABLE_TYPES.has(override.type)) return { ok: false, code: 'TYPE_NOT_ALLOWED' };
    if (override.type !== classification.type) next.overrides.push({ field: 'type', from: classification.type, to: override.type, at: now });
    next.type = override.type;
    if (override.type === ENTRY_TYPES.PROFILE) next.category = 'persona';
  }
  if (override.category !== undefined) {
    if (typeof override.category !== 'string' || !SLUG.test(override.category)) return { ok: false, code: 'INVALID_CATEGORY' };
    if (override.category !== next.category) next.overrides.push({ field: 'category', from: next.category, to: override.category, at: now });
    next.category = override.category;
  }
  if (override.sensitivity !== undefined) {
    if (!Object.values(SENSITIVITY).includes(override.sensitivity)) return { ok: false, code: 'INVALID_SENSITIVITY' };
    if (override.sensitivity !== next.sensitivity) next.overrides.push({ field: 'sensitivity', from: next.sensitivity, to: override.sensitivity, at: now });
    next.sensitivity = override.sensitivity;
  }
  if (override.expiresAt !== undefined) {
    if (override.expiresAt !== null) {
      const ts = Date.parse(override.expiresAt);
      if (!Number.isFinite(ts) || ts <= now) return { ok: false, code: 'INVALID_EXPIRY' };
    }
    if (override.expiresAt !== next.expiresAt) next.overrides.push({ field: 'expiresAt', from: next.expiresAt, to: override.expiresAt, at: now });
    next.expiresAt = override.expiresAt === null ? null : new Date(Date.parse(override.expiresAt)).toISOString();
  }
  next.overrides = Object.freeze(next.overrides);
  return { ok: true, classification: Object.freeze(next) };
}

module.exports = { SENSITIVITY, classify, reclassify, parseExpiry };
