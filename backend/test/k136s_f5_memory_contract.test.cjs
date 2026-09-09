'use strict';
// K136S-F5 regressions use the REAL helper and an in-memory query substitute. No service credentials.
const test = require('node:test');
const assert = require('node:assert/strict');
const { pathToFileURL } = require('node:url');
const path = require('node:path');
const { buildWriter, mountK136S } = require('../k136s_learning/http/mount.cjs');
const { contentHash } = require('../k136s_learning/domain/normalize_diff.cjs');
const { toBackendSaveBody, deriveMemoryKey } = require('../k136s_learning/adapters/memory_writer.cjs');
const INTERNAL = Symbol.for('korlix.k136s.memory-contract.v1');
const TABLE = 'korlix_live_convo_agent_memories';
const clone = x => structuredClone(x);
const load = () => import(pathToFileURL(path.resolve(__dirname, '../korlix_live_convo_agents.js')).href);
function database() {
  const tables = new Map(); const calls = []; let sequence = 0;
  const db = { tables, calls, corrupt: null, fail: false, from(table) {
    if (!tables.has(table)) tables.set(table, []);
    let filters = [], mode = 'select', payload, maximum = Infinity;
    const q = {
      select() { return q; }, eq(k,v) { filters.push(r => r[k] === v); calls.push([table,'eq',k,v]); return q; },
      is(k,v) { filters.push(r => (r[k] ?? null) === v); return q; },
      order() { return q; }, limit(n) { maximum=n; return q; },
      insert(v) { mode='insert';payload=v;return q; }, update(v) { mode='update';payload=v;return q; },
      maybeSingle() { return execute(true); }, single() { return execute(true); },
      then(a,b) { return execute(false).then(a,b); }
    };
    async function execute(single) {
      if (db.fail) return { data:null, error:{ message:'fixture unavailable' } };
      let rows = tables.get(table), result = rows.filter(r => filters.every(f => f(r)));
      if (mode === 'insert') {
        result = (Array.isArray(payload) ? payload : [payload]).map(v => ({ id:`f5-${++sequence}`, created_at:new Date().toISOString(), updated_at:new Date().toISOString(), ...clone(v) }));
        rows.push(...result);
      } else if (mode === 'update') for (const row of result) Object.assign(row, clone(payload));
      if (mode !== 'select' && table === TABLE && db.corrupt) for (const row of result) db.corrupt(row);
      result = result.slice(0,maximum).map(clone);
      if (single && result.length>1) return {data:null,error:{message:'multiple records'}};
      return { data:single ? result[0] ?? null : result, error:null };
    }
    return q;
  }};
  return db;
}
function change(text='Acme prefers morning calls.', expiresAt=null) {
  const c={normalizedText:text,type:'MEMORY',category:'preference',sensitivity:'low',expiresAt};
  c.contentHash=contentHash({agentId:'general',text,...c});return c;
}
async function fixture() {
  const api=await load(), db=database();
  const writer=buildWriter({supabaseAdmin:db, saveMemory:api.korlixAgentSaveMemoryV1, listMemories:api.korlixAgentListMemoriesV1});
  const c=change(), memoryKey=deriveMemoryKey({agentId:'general',...c});
  const args={userId:'user-one',agentId:'general',change:c,memoryKey,sessionId:'learning-one',approvalId:'approved-one'};
  return {api,db,writer,args};
}
test('F5 real helper preserves metadata and expires_at; exact-key read and runtime recall agree',async()=>{
  const {api,db,writer,args}=await fixture();args.change=change('Acme prefers morning calls.','2099-01-01T00:00:00.000Z');
  args.memoryKey=deriveMemoryKey({agentId:'general',...args.change});
  const saved=await writer.write(args), row=db.tables.get(TABLE)[0];
  assert.equal(row.expires_at,args.change.expiresAt);
  assert.equal(row.metadata.k136s.contentHash,args.change.contentHash);
  assert.equal(row.metadata.k136s.approvalId,args.approvalId);
  assert.equal(row.metadata.k136s.sessionId,args.sessionId);
  assert.equal((await writer.readByKey(args)).id,saved.id);
  assert.equal((await writer.readByKey(args)).contentHash,args.change.contentHash);
  row.expires_at='2099-01-01T00:00:00+00:00';
  assert.equal((await writer.readByKey(args)).contentHash,args.change.contentHash, 'Postgres timestamp representation');
  const recalled=await api.korlixAgentLoadRuntimeMemoriesV1({client:db,userId:args.userId,agentId:args.agentId});
  assert.equal(recalled.length,1);assert.equal(recalled[0].content,args.change.normalizedText);
});
test('F5 exact lookup is user + agent + key scoped and is not a limited public list scan',async()=>{
  const {db,writer,args}=await fixture();await writer.write(args);
  const original=db.tables.get(TABLE)[0];
  for(let n=0;n<300;n++)db.tables.get(TABLE).unshift({...clone(original),id:'noise-'+n,memory_key:'other-'+n});
  assert.equal((await writer.readByKey(args)).id,original.id);
  for(const alter of [{userId:'other-user'},{agentId:'my_assistant'},{memoryKey:'k136s:missing:key'}])
    assert.equal(await writer.readByKey({...args,...alter}),null);
  assert.ok(db.calls.some(c=>c[1]==='eq'&&c[2]==='memory_key'&&c[3]===args.memoryKey));
});
test('F5 regular helper behavior and public projections do not expose private provenance',async()=>{
  const {api,db}=await fixture();
  const b={confirmed:true,content:'A normal note.',metadata:{k136s:{contentHash:'untrusted'}},k136sInternal:true};
  const v=await api.korlixAgentSaveMemoryV1({client:db,userId:'user-one',agentId:'general',body:b});
  assert.equal(v.content,'A normal note.');assert.equal('metadata' in v,false);assert.equal('memoryKey' in v,false);
  assert.equal('k136s' in db.tables.get(TABLE)[0].metadata,false);
  const list=await api.korlixAgentListMemoriesV1({client:db,userId:'user-one',agentId:'general',memoryKey:'not-an-internal-lookup'});
  assert.equal(list.length,1);assert.deepEqual(Object.keys(list[0]).sort(),Object.keys(v).sort());
});
test('F5 internal writes still require confirmation, valid hash, existing agent and enabled memory',async()=>{
  const {api,db,writer,args}=await fixture();
  const b=toBackendSaveBody({...args,confirmationField:'confirmed'});
  for(const altered of [{...b,confirmed:false},{...b,content:'Changed text.'},{...b,expires_at:'not a date'},
      {...b,metadata:{k136s:{...b.metadata.k136s,contentHash:'0'.repeat(64)}}}]) {
    await assert.rejects(api.korlixAgentSaveMemoryV1({client:db,userId:args.userId,agentId:args.agentId,body:altered,[INTERNAL]:true}));
  }
  await assert.rejects(writer.write({...args,agentId:'missing_agent'}));
  db.tables.set('korlix_live_convo_agent_profiles',[{user_id:args.userId,agent_id:'general',memory_enabled:false,configuration:{memoryEnabled:false}}]);
  await assert.rejects(writer.write(args),e=>e.code==='agent_memory_disabled');
  assert.equal((db.tables.get(TABLE)||[]).length,0);
});
test('F5 persisted corruption is not repaired in memory or presented as verified',async()=>{
  for(const corrupt of [r=>delete r.metadata.k136s, r=>r.metadata.k136s.contentHash='0'.repeat(64),
      r=>r.content='Corrupted text.',r=>r.expires_at='2098-01-01T00:00:00.000Z']){
    const {db,writer,args}=await fixture();db.corrupt=corrupt;await writer.write(args);
    const back=await writer.readByKey(args);
    assert.ok(!back||back.contentHash!==args.change.contentHash||back.content!==args.change.normalizedText);
  }
});
test('F5 expired, forgotten and deleted records cannot become recalled memories',async()=>{
  const {api,db,writer,args}=await fixture();await writer.write(args);
  const row=db.tables.get(TABLE)[0];
  for(const flag of [{expires_at:'2000-01-01T00:00:00.000Z'},{forgotten_at:'2000-01-01T00:00:00.000Z'},{deleted_at:'2000-01-01T00:00:00.000Z'}]) {
    Object.assign(row,{expires_at:null,forgotten_at:null,deleted_at:null},flag);
    const read=await writer.readByKey(args);assert.ok(!read||!read.active||read.forgottenAt||read.deletedAt);
    assert.equal((await api.korlixAgentLoadRuntimeMemoriesV1({client:db,userId:args.userId,agentId:args.agentId})).length,0);
  }
});
test('F5 reapproved same key updates once and preserves supplied supersession provenance',async()=>{
  const {db,writer,args}=await fixture();await writer.write(args);const before=await writer.readByKey(args);
  args.change=change('Acme prefers afternoon calls.');args.approvalId='approved-two';
  await writer.write({...args,previous:{contentHash:before.contentHash,content:before.content,at:before.updatedAt}});
  assert.equal(db.tables.get(TABLE).length,1);
  const row=db.tables.get(TABLE)[0];assert.equal(row.metadata.k136s.superseded.previousContent,before.content);
  assert.equal((await writer.readByKey(args)).contentHash,args.change.contentHash);
});
test('F5 database errors propagate rather than fabricate a saved/read record',async()=>{
  const {db,writer,args}=await fixture();db.fail=true;
  await assert.rejects(writer.write(args));await assert.rejects(writer.readByKey(args));
});
test('F5 actual mounted flow with real helper verifies stored content; replay cannot write twice',async()=>{
  const {api,db}=await fixture(), routes=new Map(), key='fixture-only-learning-key-0123456789';
  const m=mountK136S({get:(p,h)=>routes.set('GET '+p,h),post:(p,h)=>routes.set('POST '+p,h)}, {
    supabaseAdmin:db,requireUser:async()=>({id:'user-one'}),
    korlixAgentSaveMemoryV1:api.korlixAgentSaveMemoryV1,korlixAgentListMemoriesV1:api.korlixAgentListMemoriesV1,
    env:{K136S_GRANT_KEY:key},log:{log(){},warn(){}},
    vaultVerifier:async()=>({status:200,body:{success:true,verified:true}})
  });assert.equal(m.ok,true);
  async function call(p,body,headers={}){let out;const res={set(){},status(s){this.s=s;return this;},json(j){out={status:this.s,json:j};}};
    await routes.get('POST '+p)({method:'POST',url:p,headers,body},res);return out;}
  const g=await call('/k136s/grant',{agentId:'general',vaultPassword:'fixture-only'});assert.equal(g.status,200);
  const headers={'x-k136s-grant':g.json.grant};
  const p=await call('/k136s/preview',{agentId:'general',proposedText:'Acme prefers morning calls.'},headers);assert.equal(p.status,200);
  const binding={agentId:'general',sessionId:'session-f5',contentHash:p.json.contentHash};
  const a=await call('/k136s/approve/request',binding,headers);assert.equal(a.status,200);
  const body={...binding,approvalToken:a.json.approvalToken,channel:'typed',preview:{normalizedText:p.json.normalizedText,...p.json.classification}};
  const c=await call('/k136s/approve/confirm',body,headers);assert.equal(c.status,200,JSON.stringify(c));assert.equal(c.json.state,'VERIFIED');
  assert.equal((await call('/k136s/approve/confirm',body,headers)).status,409);
  assert.equal(db.tables.get(TABLE).length,1);
});
