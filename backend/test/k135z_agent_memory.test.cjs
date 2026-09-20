'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync(require.resolve('../server.js'),'utf8');
const user='11111111-1111-4111-8111-111111111111',agentId='custom_nova_test';
const principal={tenantId:user,userId:user,agentId};
async function fixture(){
 const agents=await import('../korlix_live_convo_agents.js');
 const profile={user_id:user,agent_id:agentId,name:'NOVA',active:true,memory_enabled:true,
  deleted_at:null,configuration:{isCustom:true,mission:'Help with Aurora.',trainingInstructions:'Use clear, practical answers.'}};
 const memories=Array.from({length:34},(_,i)=>({user_id:user,agent_id:agentId,id:String(i),
  content:`Approved project fact ${i}.`,kind:'fact',importance:3,active:true,enabled:true,
  forgotten_at:null,deleted_at:null,expires_at:null}));
 memories.push(...[
  {...memories[0],user_id:'22222222-2222-4222-8222-222222222222',content:'OTHER_ACCOUNT_SECRET'},
  {...memories[0],agent_id:'custom_other',content:'OTHER_AGENT_SECRET'},
  {...memories[0],active:false,content:'INACTIVE_SECRET'},
  {...memories[0],enabled:false,content:'DISABLED_SECRET'},
  {...memories[0],forgotten_at:'2020-01-01',content:'FORGOTTEN_SECRET'},
  {...memories[0],deleted_at:'2020-01-01',content:'DELETED_SECRET'},
  {...memories[0],expires_at:'2020-01-01',content:'EXPIRED_SECRET'},
 ]);
 const reads=[];
 const client={from(table){
  const filters=[];let maximum=250;
  const rows=()=>{reads.push({table,filters:[...filters]});return (table.endsWith('_profiles')?[profile]:memories)
   .filter(row=>filters.every(([k,v])=>row[k]===v)).slice(0,maximum);};
  const q={select(){return q;},eq(k,v){filters.push([k,v]);return q;},is(k,v){filters.push([k,v]);return q;},
   order(){return q;},limit(n){maximum=n;return q;},async maybeSingle(){return {data:rows()[0]||null,error:null};},
   then(resolve,reject){return Promise.resolve({data:rows(),error:null}).then(resolve,reject);}};
  return q;
 }};
 const start=source.indexOf('async function korlixLiveConvoBuildAgentRuntimeV1(');
 const end=source.indexOf('\nfunction korlixLiveConvoAgentInstructionsV1',start);
 const build=vm.runInNewContext(source.slice(start,end)+'\nkorlixLiveConvoBuildAgentRuntimeV1;',{
  ...agents,korlixLiveConvoAgentPersistenceClientV1:()=>client,
  korlixLiveConvoAgentTextV1:(v,n)=>String(v??'').trim().slice(0,n),
  korlixLiveConvoAgentModelProofV1:()=>({}),
 });
 let options;
 vm.runInNewContext(source.slice(source.indexOf('const k135zRegistered ='),source.indexOf('k135zServerRuntime.attach')),
  {process:{env:{}},app:{},supabaseAdmin:client,requireUser:()=>{},korlixAgentLoadProfileV1:agents.korlixAgentLoadProfileV1,
   k135zServerRuntime:{options:{}},korlixLiveConvoBuildAgentRuntimeV1:build,createK135zGate5Wiring:()=>({}),
   registerK135zZoomRoutes:(_app,o)=>{options=o;return {};}});
 return {profile,memories,reads,build,load:()=>options.workspaceAgentRuntime({principal})};
}
test('production wiring uses the shared Agent Hub loader and includes all 34 saved records',async()=>{
 const f=await fixture(),r=await f.load();
 assert.equal(r.agent.id,agentId);assert.equal(r.memoryCount,34);
 assert.match(r.instructions,/Use clear, practical answers/);assert.match(r.instructions,/Approved project fact 33/);
 assert(!r.instructions.includes('_SECRET'));
 for(const read of f.reads){assert(read.filters.some(([k,v])=>k==='user_id'&&v===user));
  assert(read.filters.some(([k,v])=>k==='agent_id'&&v===agentId));}
});
test('LIVE CONVO keeps its existing default memory budget',async()=>{
 const f=await fixture(),r=await f.build({user:{id:user},agentId,characterName:'Nova',language:'English'});
 assert.equal(r.memoryCount,24);
});
test('Agent Hub edits, forget and memory off are reflected on the next reply',async()=>{
 const f=await fixture();await f.load();f.profile.configuration.trainingInstructions='Updated training';
 f.memories[0].content='Launch moved to June.';f.memories[1].forgotten_at='2026-01-01';
 let r=await f.load();assert.equal(r.memoryCount,33);assert.match(r.instructions,/Launch moved to June/);
 assert.match(r.instructions,/Updated training/);assert(!r.instructions.includes('Approved project fact 1.'));
 f.profile.memory_enabled=false;r=await f.load();assert.equal(r.memoryCount,0);
 assert(!r.instructions.includes('Launch moved to June'));assert.match(r.instructions,/memory is disabled/);
});
test('missing or inactive owned agent never falls back to General Korlix',async()=>{
 for(const change of [f=>f.profile.active=false,f=>f.profile.deleted_at='2026-01-01',
  f=>f.profile.user_id='22222222-2222-4222-8222-222222222222']){
  const f=await fixture();change(f);await assert.rejects(f.load());
 }
});
