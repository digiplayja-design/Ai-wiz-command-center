'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createSupabaseStore, TABLES } = require('../k136s_learning/adapters/supabase_store.cjs');
const { createApprovalService } = require('../k136s_learning/services/approval_service.cjs');
const { createApprovalRoutes, reconstructChange } = require('../k136s_learning/http/approval_routes.cjs');
const { createFakeMemoryWriter } = require('../k136s_learning/adapters/memory_writer.cjs');
const { mountK136S } = require('../k136s_learning/http/mount.cjs');
const quiet = { warn() {}, log() {} };
const T0 = 1800000000000;
const B = { sessionId: 'session', userId: 'user', accountId: 'account', agentId: 'agent', contentHash: 'hash' };
const copy = (x) => structuredClone(x);
// Query-shape fake; models one conditional update, NOT a substitute for a live DB test.
function fakeClient({ now = Date.now } = {}) {
  const rows = [], writes = [], queries = [];
  const control = { fail: null, throws: false, hold: null, corrupt: null, zero: false, multiple: false, dbClock: now };
  return { rows, writes, queries, control, from(table) {
    let op = 'select', payload, columns, cap = Infinity;
    const filters = [];
    const q = {
      insert(v) { op = 'insert'; payload = copy(v); return q; },
      update(v) { op = 'update'; payload = copy(v); return q; },
      select(v) { columns = v; return q; },
      eq(k,v) { filters.push(['eq',k,v]); return q; },
      is(k,v) { filters.push(['is',k,v]); return q; },
      gt(k,v) { filters.push(['gt',k,v]); return q; },
      limit(n) { cap = n; return q; }, abortSignal() { return q; },
      then(resolve,reject) { return (async () => {
        queries.push({ table, op, filters: copy(filters), columns });
        if (control.hold && op === control.hold.op && table === TABLES.approvals) await control.hold.promise;
        if (control.fail === op || control.fail === table) {
          if (control.throws) throw new Error('fixture-secret-do-not-log');
          return { data: null, error: { message: 'fixture-secret-do-not-log' } };
        }
        let data;
        if (table === TABLES.audit) { writes.push({ op,table,row:copy(payload) }); return { data: null,error:null }; }
        if (op === 'insert') {
          if (rows.some((r) => r.token_hash === payload.token_hash || r.id === payload.id)) return { data: null, error: { code: '23505' } };
          rows.push(copy(payload)); writes.push({ op,table,row:copy(payload) }); data = [copy(payload)];
        } else {
          const at = control.dbClock();
          const found = rows.filter((r) => filters.every(([kind,k,v]) => kind === 'gt' ? Date.parse(r[k]) > (v === 'now' ? at : Date.parse(v)) : r[k] === v)).slice(0,cap);
          if (op === 'update' && control.zero) data = [];
          else {
            if (op === 'update') for (const r of found) Object.assign(r, payload.consumed_at === 'now' ? { consumed_at: new Date(at).toISOString() } : payload);
            if (op === 'update') writes.push({ op,table,filters:copy(filters),row:copy(payload) });
            data = found.map(copy);
          }
        }
        if (control.corrupt && op === control.corrupt.op) data = control.corrupt.fn(data);
        if (control.multiple && op === 'update' && data.length) data.push(copy(data[0]));
        return { data, error:null };
      })().then(resolve,reject); },
    }; return q;
  } };
}
function fixture(options={}) {
  let t=T0; const now=()=>t;
  const client=fakeClient({now});
  const store=createSupabaseStore({client, now, log:quiet, ...options});
  return {client,store,svc:store.approvalService,now,tick:(n)=>{t+=n;}};
}
function routeFixture(f, overrides={}) {
  const preview={normalizedText:'Acme prefers morning calls.',type:'MEMORY',category:'preference',sensitivity:'low',expiresAt:null};
  const body={sessionId:B.sessionId,agentId:B.agentId,contentHash:reconstructChange(B.agentId,preview).change.contentHash};
  const writer=createFakeMemoryWriter({now:f.now});
  const routes=createApprovalRoutes({store:f.store,approvals:f.svc,writer,identity:()=>({userId:B.userId,accountId:B.accountId}),now:f.now,...overrides});
  const grantPayload={agentId:B.agentId,iat:f.now()};
  return {body,writer,routes,grantPayload,request:()=>routes.request({body,grantPayload}),
    confirm:(token)=>routes.confirm({body:{...body,preview,channel:'typed',approvalToken:token},grantPayload})};
}
module.exports={fakeClient,fixture,routeFixture,T0,B,quiet};
if (require.main === module) {
  test('F4: issue awaits committed insertion and stores no raw token', async()=>{
    const f=fixture(); let release; const promise=new Promise(r=>{release=r;}); f.client.control.hold={op:'insert',promise};
    let settled=false; const p=f.svc.issue(B).then(r=>{settled=true;return r;});
    await new Promise(r=>setImmediate(r)); assert.equal(settled,false); assert.equal(f.client.rows.length,0);
    release(); const r=await p; assert.equal(r.ok,true); assert.match(r.token,/^[A-Za-z0-9_-]{43}$/);
    assert.equal(JSON.stringify(f.client.writes).includes(r.token),false);
  });
  for(const thrown of [false,true]) test(`F4: insert failure returns no token (throw=${thrown})`, async()=>{
    const f=fixture();f.client.control.fail='insert';f.client.control.throws=thrown;
    const r=await f.svc.issue(B);assert.equal(r.ok,false);assert.equal(r.code,'APPROVAL_STORE_UNAVAILABLE');assert.equal(r.token,undefined);
  });
  test('F4: restart / second instance uses persisted approval and rejects replay', async()=>{
    const f=fixture(); const r=await f.svc.issue(B);
    const fresh=createSupabaseStore({client:f.client,now:f.now,log:quiet}).approvalService;
    assert.equal((await fresh.consume({...B,token:r.token})).ok,true);
    assert.equal((await f.svc.consume({...B,token:r.token})).code,'ALREADY_CONSUMED');
  });
  test('F4: 20 concurrent cross-instance consumes have exactly one winner',async()=>{
    const f=fixture();const r=await f.svc.issue(B);
    const results=await Promise.all(Array.from({length:20},()=>createSupabaseStore({client:f.client,now:f.now,log:quiet}).approvalService.consume({...B,token:r.token})));
    assert.equal(results.filter(x=>x.ok).length,1);assert.ok(results.filter(x=>!x.ok).every(x=>x.code==='ALREADY_CONSUMED'));
    const upd=f.client.queries.find(x=>x.op==='update');
    for(const col of ['token_hash','session_id','user_id','account_id','agent_id','content_hash']) assert.ok(upd.filters.some(x=>x[0]==='eq'&&x[1]===col));
    assert.ok(upd.filters.some(x=>x[0]==='is'&&x[1]==='consumed_at'&&x[2]===null));
    assert.ok(upd.filters.some(x=>x[0]==='gt'&&x[1]==='expires_at'&&x[2]==='now'));assert.ok(upd.columns.includes('consumed_at'));
  });
  for(const k of Object.keys(B)) test(`F4: ${k} mismatch cannot consume`,async()=>{
    const f=fixture();const r=await f.svc.issue(B);
    assert.equal((await f.svc.consume({...B,[k]:'wrong',token:r.token})).code,'BINDING_MISMATCH');
    assert.equal(f.client.rows[0].consumed_at,null);assert.equal((await f.svc.consume({...B,token:r.token})).ok,true);
  });
  test('F4: expiry equality and unknown token reject',async()=>{
    const f=fixture();const r=await f.svc.issue(B);f.tick(120000);
    assert.equal((await f.svc.consume({...B,token:r.token})).code,'EXPIRED');assert.equal(f.client.rows[0].consumed_at,null);
    assert.equal((await f.svc.consume({...B,token:'unknown'})).code,'NOT_FOUND');
  });
  test('F4: DB clock rejects expiration even when application clock is stale',async()=>{
    const f=fixture();const r=await f.svc.issue(B);f.client.control.dbClock=()=>T0+120001;
    assert.equal((await f.svc.consume({...B,token:r.token})).ok,false);assert.equal(f.client.rows[0].consumed_at,null);
  });
  for(const op of ['insert','update']) test(`F4: malformed ${op} response never authorizes`,async()=>{
    const f=fixture();let r;
    if(op==='update') r=await f.svc.issue(B);
    f.client.control.corrupt={op,fn:()=>null};
    const x=op==='insert'?await f.svc.issue(B):await f.svc.consume({...B,token:r.token});
    assert.equal(x.code,'APPROVAL_STORE_UNAVAILABLE');assert.equal(x.token,undefined);
  });
  test('F4: zero / multiple UPDATE rows cannot authorize',async()=>{
    const f=fixture();const r=await f.svc.issue(B);f.client.control.zero=true;
    assert.equal((await f.svc.consume({...B,token:r.token})).ok,false);
    f.client.control.zero=false;f.client.control.multiple=true;
    assert.equal((await f.svc.consume({...B,token:r.token})).ok,false);
  });
  test('F4: returned binding corruption is rejected',async()=>{
    const f=fixture();const r=await f.svc.issue(B);
    f.client.control.corrupt={op:'update',fn:rows=>rows.map(r=>({...r,session_id:'wrong'}))};
    assert.equal((await f.svc.consume({...B,token:r.token})).ok,false);
  });
  test('F4: synchronous B service cannot accidentally issue a token with async store',()=>{
    const f=fixture();const old=createApprovalService({store:f.store,now:f.now});
    assert.throws(()=>old.issue(B),/K136S_DURABLE_SERVICE_REQUIRED/);assert.equal(f.client.queries.length,0);
  });
  test('F4: timeout is bounded, no token; late insert never retroactively succeeds',async()=>{
    const f=fixture({timeoutMs:15});let release; const promise=new Promise(r=>{release=r;});f.client.control.hold={op:'insert',promise};
    const r=await f.svc.issue(B);assert.equal(r.code,'APPROVAL_STORE_UNAVAILABLE');assert.equal(r.token,undefined);
    release();await new Promise(r=>setImmediate(r));assert.equal(r.ok,false);
  });
  test('F4: HTTP issue DB failure is 503 without approvalToken',async()=>{
    const f=fixture();const h=routeFixture(f);f.client.control.fail='insert';
    const r=await h.request();assert.equal(r.status,503);assert.equal(r.json.approvalToken,undefined);
  });
  for(const thrown of [false,true]) test(`F4: HTTP consume DB failure makes zero memory writes (throw=${thrown})`,async()=>{
    const f=fixture();const h=routeFixture(f);const r=await h.request();f.client.control.fail='update';f.client.control.throws=thrown;
    const c=await h.confirm(r.json.approvalToken);assert.equal(c.status,503);assert.equal(h.writer._rows().length,0);
  });
  test('F4: held update cannot reach writer before DB response',async()=>{
    const f=fixture();const h=routeFixture(f);const r=await h.request();let release;const promise=new Promise(r=>{release=r;});
    f.client.control.hold={op:'update',promise};let settled=false;const p=h.confirm(r.json.approvalToken).then(r=>{settled=true;return r;});
    await new Promise(r=>setImmediate(r));assert.equal(settled,false);assert.equal(h.writer._rows().length,0);
    release();assert.equal((await p).json.state,'VERIFIED');assert.equal(h.writer._rows().length,1);
  });
  test('F4: concurrent HTTP confirms write exactly once',async()=>{
    const f=fixture();const h=routeFixture(f);const r=await h.request();
    const xs=await Promise.all(Array.from({length:12},()=>h.confirm(r.json.approvalToken)));
    assert.equal(xs.filter(x=>x.status===200).length,1);assert.equal(h.writer._rows().length,1);
    assert.equal(f.store.audit.list().filter(x=>x.eventType==='WRITE').length,1);
  });
  test('F4: failed writer never resurrects a consumed approval',async()=>{
    const f=fixture();let calls=0;const h=routeFixture(f,{writer:{readByKey:async()=>null,write:async()=>{calls++;throw Error('fixture');}}});
    const r=await h.request();assert.equal((await h.confirm(r.json.approvalToken)).status,502);
    assert.equal((await h.confirm(r.json.approvalToken)).status,409);assert.equal(calls,1);
  });
  test('F4: production memory/unset/typo configuration is disabled',()=>{
    for(const K136S_STORE of ['', 'memory','supabse']) {
      const handlers=[];const r=mountK136S({get:(p,h)=>handlers.push(h),post:(p,h)=>handlers.push(h)},
        {env:{K136S_STORE,NODE_ENV:'production',K136S_GRANT_KEY:'fixture-key-0123456789'},log:quiet,
          supabaseAdmin:fakeClient(),requireUser:async()=>({id:'u'}),korlixAgentSaveMemoryV1:async()=>{},korlixAgentListMemoriesV1:async()=>[]});
      assert.equal(r.configured,false);assert.equal(handlers.length,5);
    }
  });
  test('F4: DB errors containing sensitive data do not enter response or logs',async()=>{
    const lines=[];const f=fixture({log:{warn:(x)=>lines.push(x)}});f.client.control.fail='insert';
    const r=await f.svc.issue(B);assert.equal(JSON.stringify({r,lines}).includes('fixture-secret-do-not-log'),false);
  });
  test('F4: reset clears only local session/audit state, not durable approvals',async()=>{
    const f=fixture();const r=await f.svc.issue(B);f.store.reset();
    assert.equal((await f.svc.consume({...B,token:r.token})).ok,true);
  });
}
