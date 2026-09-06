'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { findDuplicates, findContradictions, subjectKey, trigramSimilarity } = require('../k136s_learning/domain/similarity.cjs');

const E = (id, agentId, normalizedText, extra = {}) => Object.assign({ id, agentId, normalizedText }, extra);
const existing = [
  E('m1', 'a1', 'Always escalate billing disputes to Maria.', { type: 'TRAINING', category: 'escalation', contentHash: 'h-maria' }),
  E('m2', 'a1', 'Acme prefers morning calls.', { type: 'MEMORY', category: 'preference' }),
  E('m3', 'a2', 'Always escalate billing disputes to Maria.', { type: 'TRAINING', category: 'escalation' }),
];

test('duplicate by identical content hash', () => {
  const d = findDuplicates({ agentId: 'a1', type: 'TRAINING', normalizedText: 'whatever', contentHash: 'h-maria' }, existing);
  assert.equal(d.length, 1); assert.equal(d[0].id, 'm1'); assert.equal(d[0].similarity, 1); assert.equal(d[0].reason, 'hash');
});

test('duplicate by high trigram similarity within the same agent and type', () => {
  const d = findDuplicates({ agentId: 'a1', type: 'TRAINING', normalizedText: 'Always escalate billing disputes to Maria!' }, existing);
  assert.equal(d.length, 1); assert.equal(d[0].id, 'm1'); assert.ok(d[0].similarity >= 0.85);
  assert.equal(findDuplicates({ agentId: 'a1', type: 'TRAINING', normalizedText: 'Completely unrelated instruction about coffee.' }, existing).length, 0);
});

test('scope isolation: a different agent is never a duplicate', () => {
  assert.equal(findDuplicates({ agentId: 'a9', type: 'TRAINING', normalizedText: 'Always escalate billing disputes to Maria.' }, existing).length, 0);
});

test('contradiction: same subject, different value or a negation flip, below the duplicate threshold', () => {
  const c = findContradictions({ agentId: 'a1', category: 'escalation', normalizedText: 'Always escalate billing disputes to Sam.' }, existing);
  assert.equal(c.length, 1); assert.equal(c[0].id, 'm1'); assert.equal(c[0].reason, 'different_value'); assert.ok(c[0].similarity < 0.85);
  const neg = findContradictions({ agentId: 'a1', category: 'preference', normalizedText: 'Acme does not prefer morning calls.' }, existing);
  assert.equal(neg.length, 1); assert.equal(neg[0].id, 'm2'); assert.equal(neg[0].reason, 'negation');
});

test('a near-identical instruction is a duplicate, not a contradiction', () => {
  assert.equal(findContradictions({ agentId: 'a1', category: 'escalation', normalizedText: 'Always escalate billing disputes to Maria.' }, existing).length, 0);
});

test('subjectKey supports an explicit key and otherwise picks salient words', () => {
  assert.equal(subjectKey('key: billing escalation. Always send to Maria.'), 'billing escalation');
  assert.equal(subjectKey('Always escalate billing disputes to Maria.'), 'escalate billing dispute'); // light stemming collapses the plural
  assert.ok(trigramSimilarity('route calls to Sam', 'route calls to Sam') === 1);
});
