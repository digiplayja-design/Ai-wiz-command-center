'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createSupabaseStore, TABLES } = require('../k136s_learning/adapters/supabase_store.cjs');
const { hashToken } = require('../k136s_learning/services/approval_service.cjs');
const { fakeClient, fixture, T0, B, quiet } = require('./k136s_f4_durable_approval.test.cjs');
test('store: client required; async authority, sessions, reset, stats, pending exposed',()=>{
  assert.throws(()=>createSupabaseStore({}),/client/);
  const s=createSupabaseStore({client:fakeClient(),log:quiet});
  assert.equal(s.kind,'supabase');assert.equal(s.authority,'supabase_atomic');assert.ok(s.sessions&&s.audit&&s.approvalService);
  assert.deepEqual(s.stats(),{mirrored:0,failed:0});
});
test('store: database issue and conditional consume retain all bindings and hashed token only',async()=>{
  const f=fixture();const issued=await f.svc.issue({...B,elevated:true});assert.equal(issued.ok,true);
  const row=f.client.rows[0];assert.equal(row.token_hash,hashToken(issued.token));assert.equal(row.elevated,true);
  assert.equal(row.expires_at,new Date(T0+120000).toISOString());assert.equal(row.consumed_at,null);
  const c=await f.svc.consume({...B,token:issued.token});assert.equal(c.ok,true);assert.equal(c.sessionId,B.sessionId);
  assert.equal((await f.svc.consume({...B,token:issued.token})).code,'ALREADY_CONSUMED');
  assert.equal(JSON.stringify(f.client.writes).includes(issued.token),false);assert.equal(f.store.stats().failed,0);
});
test('store: audit columns/detail retained; no approval authority depends on audit cache',async()=>{
  const f=fixture();const id=f.store.audit.append({eventType:'WRITE',at:T0,...B,approvalId:'ap1',memoryKey:'k',memoryId:'m1',superseded:true});
  assert.equal(id,1);assert.equal(f.store.audit.list().length,1);await f.store.pending();
  const row=f.client.writes.find(w=>w.table===TABLES.audit).row;
  assert.equal(row.event_type,'WRITE');assert.equal(row.session_id,B.sessionId);assert.equal(row.approval_id,'ap1');
  assert.deepEqual(row.detail,{memoryId:'m1',superseded:true});
});
test('store: approval failure closes authorization; audit failure is counted and sanitized',async()=>{
  const f=fixture();f.client.control.fail='insert';
  assert.equal(f.store.audit.append({eventType:'ALERT',at:T0,error:'do-not-copy',password:'do-not-copy'}),1);
  assert.equal((await f.svc.issue(B)).code,'APPROVAL_STORE_UNAVAILABLE');await f.store.pending();
  assert.equal(f.client.rows.length,0);assert.equal(f.store.stats().failed,2);assert.equal(f.store.stats().mirrored,0);
  assert.equal(JSON.stringify(f.store.audit.list()).includes('do-not-copy'),false);
});
