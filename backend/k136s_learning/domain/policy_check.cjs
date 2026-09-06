'use strict';
// K136S - policy check. Runs on every preview (and again after every edit). Fail closed.
const { ENTRY_TYPES } = require('./state_machine.cjs');
const { SENSITIVITY } = require('./classifier.cjs');

const LIMITS = Object.freeze({ MIN_CHARS: 3, MAX_CHARS: 2000 });
const SECRET_LIKE = Object.freeze([
  /eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/,
  /\bsk-[A-Za-z0-9_-]{12,}/, /\b(sk|pk|rk)_(live|test)_[A-Za-z0-9]{8,}/, /\bAKIA[A-Z0-9]{12,}/, /\bgh[pousr]_[A-Za-z0-9]{16,}/,
  /[A-Za-z0-9+/=_-]{40,}/,
  /\b(password|passcode|pin|api key|secret|token)\b[^.]{0,20}\b(is|=|:)\s*\S{4,}/i,
]);
const PLATFORM_CONTROL = /\b(disable|remove|skip|bypass|turn off|ignore|override)\b[^.]*\b(system prompt|safety|guardrails?|approval|approvals|confirmation|audit|audits|vault|logging|security)\b|\b(system prompt|safety|guardrails?|approval|approvals|confirmation|audit|audits|vault|logging|security)\b[^.]*\b(disabled|removed|skipped|bypassed|turned off|ignored|overridden|off)\b/i;
const SILENT_LEARNING = /\b(learn|remember|train|memori[sz]e|update your (memory|training))\b[^.]*\b(automatically|silently|on your own|without (asking|approval|confirmation|telling me)|from (every|all|each) (meeting|email|call|conversation|document|web ?page)s?)\b/i;
const CROSS_TENANT = /\b(other|all|every|another) (tenants?|accounts?|customers?|companies|workspaces?|users?)\b/i;
const DESTRUCTIVE = /\b(delete|wipe|erase|forget|clear|reset) (all|everything|every|the whole|your entire|entire)\b/i;

function check(input) {
  const cls = (input && input.classification) || {};
  const text = String((input && input.finalText) || '');
  const violations = [];
  let elevated = false;
  let requiresQueue = false;
  const add = (code, detail) => violations.push({ code, detail });

  if (cls.type === ENTRY_TYPES.PROHIBITED) add('PROHIBITED_TYPE', 'classified as prohibited');
  if (text.trim().length < LIMITS.MIN_CHARS) add('TOO_SHORT', `minimum ${LIMITS.MIN_CHARS} characters`);
  if (text.length > LIMITS.MAX_CHARS) add('TOO_LONG', `maximum ${LIMITS.MAX_CHARS} characters`);
  if (SECRET_LIKE.some((re) => re.test(text))) add('SECRET_LIKE_CONTENT', 'text contains a credential-like value');
  if (PLATFORM_CONTROL.test(text)) add('PLATFORM_CONTROL', 'text targets platform prompt or security controls');
  if (SILENT_LEARNING.test(text)) add('SILENT_LEARNING', 'text requests unattended learning');
  if (CROSS_TENANT.test(text)) add('CROSS_TENANT', 'text references other tenants or accounts');

  if (cls.type === ENTRY_TYPES.TOOL_PERMISSION) { elevated = true; requiresQueue = true; }
  if (cls.type === ENTRY_TYPES.PROFILE) elevated = true;
  if (cls.sensitivity === SENSITIVITY.HIGH) elevated = true;
  if (DESTRUCTIVE.test(text)) { elevated = true; requiresQueue = true; }

  const allowed = violations.length === 0 && !requiresQueue;
  const allowedChannels = violations.length > 0 ? [] : requiresQueue ? ['queue'] : elevated ? ['typed'] : ['voice', 'typed'];
  return Object.freeze({ allowed, elevated, requiresQueue, allowedChannels: Object.freeze(allowedChannels), violations: Object.freeze(violations) });
}

module.exports = { check, LIMITS };
