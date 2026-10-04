import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const source = await readFile(new URL('../server.js', import.meta.url), 'utf8');
const start = source.indexOf('app.post("/api/characters/select"');
const end = source.indexOf('// KORLIX_BRAIN_VAULT_CREDENTIALS_BUILD131_V2_BEGIN', start);
const normalizeStart = source.indexOf('function normalizeKorlixCharacterId(');
const normalizeEnd = source.indexOf('const characterPersonalityMap', normalizeStart);
const normalize = new Function(source.slice(normalizeStart, normalizeEnd) + ';return normalizeKorlixCharacterId')();

function route({tier = 'basic', active = true, comingSoon = false, missing = false, authenticated = true, failUpdate = false} = {}) {
  const writes = [];
  let callback, requested;
  const supabase = {from(table) {
    const q = {
      select() { return q; },
      eq(key, value) { if (table === 'characters') requested = value; else assert.equal(value, 'signed-in-user'); return q; },
      async maybeSingle() { return {data: missing ? null : {id: requested, is_active: active, is_coming_soon: comingSoon, tier_required: 'ultra'}}; },
      update(value) { writes.push({table, value}); return q; },
      async single() { return failUpdate ? {error: new Error('save failed')} : {data: {id: 'signed-in-user', tier, selected_character: writes.at(-1).value.selected_character}}; },
      async upsert(value, options) { writes.push({table, value}); assert.equal(options.onConflict, 'user_id,character_id'); return {error: null}; },
    };
    return q;
  }};
  new Function('app', 'supabaseAdmin', 'requireUser', 'getOrCreateProfile', 'normalizeKorlixCharacterId', 'getKorlixUserFacingError', source.slice(start, end))(
    {post(path, handler) { assert.equal(path, '/api/characters/select'); callback = handler; }}, supabase,
    async () => { if (!authenticated) throw Object.assign(new Error('Sign in required'), {statusCode: 401}); return {id: 'signed-in-user'}; },
    async () => ({tier}), normalize, error => error.message);
  return {writes, async select(id) { let status = 200, body; const res = {status(value) { status = value; return res; }, json(value) {body = value; return res;}};
    await callback({body: {character_id: id, user_id: 'someone-else'}}, res); return {status, body}; }};
}
for (const tier of ['basic', 'pro', 'ultra', 'enterprise']) {
  test(`${tier} can persist all five characters without an upgrade or tier change`, async () => {
    for (const id of ['jj', 'phil', 'chee_chai_chee', 'yuna', 'ji-a']) {
      const api = route({tier}); const {status, body} = await api.select(id);
      assert.equal(status, 200); assert.equal(body.success, true); assert.equal(body.profile.tier, tier);
      assert.equal(body.profile.selected_character, normalize(id));
      assert.deepEqual(api.writes[0].value, {selected_character: normalize(id)});
      assert.equal(api.writes[1].value.user_id, 'signed-in-user');
      assert.equal(body.upgradeRequired, undefined);
    }
  });
}
test('blank, unknown, inactive, coming-soon and unauthenticated requests cannot change a selection', async () => {
  for (const [options, id, expected] of [[{}, '', 400], [{missing:true}, 'unknown', 404], [{active:false}, 'yuna',403], [{comingSoon:true}, 'yuna',403], [{authenticated:false}, 'yuna',401]]) {
    const api = route(options); const result = await api.select(id);
    assert.equal(result.status, expected); assert.equal(api.writes.length, 0);
  }
});
test('a failed profile save returns failure rather than confirming the selection', async () => {
  const api = route({failUpdate:true}); assert.equal((await api.select('phil')).status,500);
  assert.equal(api.writes.length,1);
});
