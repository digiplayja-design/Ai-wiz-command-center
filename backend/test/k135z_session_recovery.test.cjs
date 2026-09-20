'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const U='11111111-1111-4111-8111-111111111111';
const literal=x=>"'"+JSON.stringify(x).replace(/'/g,"''")+"'::jsonb";
function register(sql){
 let serial=0;
 const rpc=async(op,payload,role='service_role')=>JSON.parse(await sql(
  "select public.k135z_workspace_commands_v1('"+op+"',"+literal(payload)+');',role));
 async function fixture({lease=120,age=120,terminal=false,state='listening',phase='dispatched'}={}){
  const agentId='recovery-'+(++serial),p={tenantId:U,userId:U,agentId};
  await sql("insert into public.korlix_live_convo_agent_profiles(user_id,agent_id) values('"+U+"','"+agentId+"');",'admin');
  const initial=await rpc('bind',{principal:p,meetingUuid:agentId,expectedBindingRevision:0});
  const ctx={...initial.record.snapshot.context,streamId:state==='ready'?null:'stream'};
  const snapshot={...initial.record.snapshot,context:ctx,state,revision:1,activeSeconds:9};
  const record={snapshot,version:6,uncertain:phase==='dispatched',pending:{phase,ticketVersion:5,
   request:{schemaVersion:1,action:'stop',expectedContext:ctx,expectedSnapshotRevision:1,
    operation:{requestId:agentId,localEpoch:0,operationNumber:1}}}};
  await sql("update k135z_workspace_private.bindings set record="+literal(record)+
   ",authority_until=clock_timestamp()-interval '"+lease+" seconds' where agent_id='"+agentId+"';"+
   "update k135z_workspace_private.bindings set record_touched_at=clock_timestamp()-interval '"+age+" seconds' where agent_id='"+agentId+"';",'admin');
  if(terminal)await sql("insert into k135z_b5b_private.stream_terminals values('"+agentId+"','stream','stopped',123);",'admin');
  return {p,record,ctx,read:()=>rpc('read',{principal:p}),raw:()=>sql("select record from k135z_workspace_private.bindings where agent_id='"+agentId+"';",'admin')};
 }
 test('recovery closes an expired abandoned generation without granting capture',async()=>{
  const f=await fixture({terminal:true}),r=await f.read();
  assert.equal(r.record.snapshot.state,'stopped');assert.equal(r.record.pending,null);assert.equal(r.record.uncertain,false);
  assert.equal(r.record.version,7);assert.equal(r.record.snapshot.revision,2);assert.equal(r.record.snapshot.activeSeconds,9);
  assert.deepEqual(r.record.snapshot.context,f.ctx);assert.equal(r.authorityRevision,1);
  assert.equal(r.authority.hostAuthorized,false);assert.equal(r.authority.listeningAuthorized,false);
  assert.deepEqual(await f.read(),r);
 });
 test('expired abandoned commands recover even when a process lost the final webhook',async()=>{
  for(const phase of ['prepared','dispatched']){
   const f=await fixture({phase});const r=await rpc('capture_lease',{principal:f.p});
   assert.equal(r.record.snapshot.state,'stopped');assert.equal(r.validForMs,0);
  }
 });
 test('fresh authority and recent operations are never recovered on age alone',async()=>{
  for(const options of [{lease:-30},{age:0},{lease:30}]){
   const f=await fixture(options);assert.deepEqual((await f.read()).record,f.record);
  }
 });
 test('terminal evidence cannot target a different stream or override a live lease',async()=>{
  const fresh=await fixture({lease:-30,terminal:true});assert.deepEqual((await fresh.read()).record,fresh.record);
  const f=await fixture({lease:10,age:0});
  await sql("insert into k135z_b5b_private.stream_terminals values('"+f.p.agentId+"','other-stream','stopped',123);",'admin');
  assert.deepEqual((await f.read()).record,f.record);
 });
 test('a recovered generation rejects delayed completion and can bind the next meeting',async()=>{
  const f=await fixture(),r=await f.read();
  const stale={bindingRevision:1,authorityRevision:0,record:f.record,
   authority:{context:f.ctx,viewerAuthorized:true,hostAuthorized:false,listeningAuthorized:false}};
  assert.equal((await rpc('compare_save',{principal:f.p,context:f.ctx,expected:stale,record:f.record})).status,'conflict');
  const next=await rpc('bind',{principal:f.p,meetingUuid:'new-meeting',expectedBindingRevision:1});
  assert.equal(next.bindingRevision,2);assert.equal(next.record.snapshot.state,'ready');
  assert.notEqual(next.record.snapshot.context.sessionId,r.record.snapshot.context.sessionId);
  assert.equal(next.authority.listeningAuthorized,false);
 });
 test('normal idle ready sessions do not expire through recovery',async()=>{
  const f=await fixture({state:'ready'}),record={...f.record,pending:null,uncertain:false};
  await sql("update k135z_workspace_private.bindings set record="+literal(record)+" where agent_id='"+f.p.agentId+"';"+
   "update k135z_workspace_private.bindings set record_touched_at=clock_timestamp()-interval '120 seconds' where agent_id='"+f.p.agentId+"';",'admin');
  assert.deepEqual((await f.read()).record,record);
 });
 test('recovery preserves ownership checks and is unavailable to public client roles',async()=>{
  const f=await fixture();
  for(const role of ['anon','authenticated'])await assert.rejects(()=>rpc('read',{principal:f.p},role),/permission denied/);
  await sql("update public.korlix_live_convo_agent_profiles set active=false where agent_id='"+f.p.agentId+"';",'admin');
  assert.equal((await f.read()).status,'denied');assert.deepEqual(JSON.parse(await f.raw()),f.record);
 });
}
module.exports={register};
