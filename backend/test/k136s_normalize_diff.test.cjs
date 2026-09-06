'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { normalize, contentHash, canonical, diffWords } = require('../k136s_learning/domain/normalize_diff.cjs');

test('normalize strips wake word, fillers and lead-ins and fixes punctuation', () => {
  assert.equal(normalize('  Hey Nova,   um, always   escalate  billing '), 'Always escalate billing.');
  assert.equal(normalize('nova: remember that Acme prefers mornings'), 'Remember that Acme prefers mornings.');
  assert.equal(normalize('Please, so well, note the renewal date.'), 'Note the renewal date.');
  assert.equal(normalize('already fine.'), 'Already fine.');
  assert.equal(normalize('   '), '');
  assert.equal(normalize('spaces , before punctuation .'), 'Spaces, before punctuation.');
});

test('contentHash is stable, order-independent over fields and sensitive to every field', () => {
  const base = { agentId: 'a1', text: 'Always escalate.', type: 'TRAINING', category: 'escalation', sensitivity: 'low', expiresAt: null };
  const h = contentHash(base);
  assert.match(h, /^[0-9a-f]{64}$/);
  assert.equal(contentHash({ text: 'Always escalate.', type: 'TRAINING', agentId: 'a1', sensitivity: 'low', category: 'escalation', expiresAt: null }), h);
  assert.notEqual(contentHash(Object.assign({}, base, { text: 'Always escalate!' })), h);
  assert.notEqual(contentHash(Object.assign({}, base, { agentId: 'a2' })), h);
  assert.notEqual(contentHash(Object.assign({}, base, { category: 'policy' })), h);
  assert.notEqual(contentHash(Object.assign({}, base, { expiresAt: '2026-10-01T00:00:00Z' })), h);
  assert.equal(canonical(base), '{"agentId":"a1","text":"Always escalate.","type":"TRAINING","category":"escalation","sensitivity":"low","expiresAt":null}');
  assert.throws(() => contentHash({ agentId: 'a1', text: '', type: 'MEMORY' }), /text required/);
});

test('diffWords marks equal, insert and delete spans and reports whether anything changed', () => {
  const d = diffWords('Always escalate billing disputes to Maria', 'Always escalate billing disputes to Maria within one hour');
  assert.equal(d.changed, true);
  assert.deepEqual(d.ops, [{ op: 'equal', text: 'Always escalate billing disputes to Maria' }, { op: 'insert', text: 'within one hour' }]);
  const d2 = diffWords('route calls to Sam', 'route calls to Alex');
  assert.deepEqual(d2.ops, [{ op: 'equal', text: 'route calls to' }, { op: 'delete', text: 'Sam' }, { op: 'insert', text: 'Alex' }]);
  const same = diffWords('no change here', 'no change here');
  assert.equal(same.changed, false);
  assert.deepEqual(diffWords('', 'brand new fact').ops, [{ op: 'insert', text: 'brand new fact' }]);
});
