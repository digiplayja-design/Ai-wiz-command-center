import test from 'node:test';
import assert from 'node:assert/strict';
import {createVideoAccess} from '../security/video_access.mjs';

const alice={id:'11111111-1111-4111-8111-111111111111'};
const bob={id:'22222222-2222-4222-8222-222222222222'};
const reservationId='33333333-3333-4333-8333-333333333333';
function fixture({rows=[],rpcResult={ok:true,reservation_id:reservationId},error=null}={}) {
  const calls=[];
  return {calls,access:createVideoAccess({database:{
    async rpc(name,args) { calls.push({name,args}); return {data:rpcResult,error}; },
    from(table) {
      const filters={};
      const query={select(){return query;},eq(key,value){filters[key]=value;return query;},
        async maybeSingle(){calls.push({table,filters});return {data:rows.find(row=>Object.entries(filters).every(([key,value])=>row[key]===value))??null,error};}};
      return query;
    },
  }})};
}
test('anonymous video access never reaches database or reservation',async()=>{
  const {access,calls}=fixture();
  for (const action of [()=>access.reserve({kind:'text_to_video',provider:'openai'}),()=>access.requireOwnedJob({jobId:'video_bob',provider:'openai'}),()=>access.summary({})]) {
    await assert.rejects(action,{statusCode:401});
  }
  assert.equal(calls.length,0);
});
test('cross-account and cross-provider jobs are invisible',async()=>{
  const row={id:reservationId,user_id:bob.id,provider_job_id:'video_bob',provider:'openai',kind:'text_to_video',status:'submitted'};
  const {access,calls}=fixture({rows:[row]});
  await assert.rejects(()=>access.requireOwnedJob({user:alice,jobId:'video_bob',provider:'openai'}),{statusCode:404});
  await assert.rejects(()=>access.requireOwnedJob({user:bob,jobId:'video_bob',provider:'kling'}),{statusCode:404});
  assert.equal((await access.requireOwnedJob({user:bob,jobId:'video_bob',provider:'openai'})).id,reservationId);
  assert.equal(calls[0].filters.user_id,alice.id);
});
test('unknown historical videos fail closed instead of querying paid provider',async()=>{
  const {access}=fixture();
  await assert.rejects(()=>access.requireOwnedJob({user:alice,jobId:'unrecorded_legacy_job',provider:'openai'}),{statusCode:404});
});
test('invalid provider paths never reach database',async()=>{
  const {access,calls}=fixture();
  for(const jobId of ['../other','video/../../../files','%2e%2e', '', 'x'.repeat(201)]) {
    await assert.rejects(()=>access.requireOwnedJob({user:alice,jobId,provider:'openai'}),{statusCode:404});
  }
  assert.equal(calls.length,0);
});
test('quota reservation sends verified identity only and ignores user metadata tier',async()=>{
  const {access,calls}=fixture();
  const result=await access.reserve({user:{...alice,user_metadata:{tier:'enterprise'}},provider:'openai',kind:'text_to_video'});
  assert.equal(result.id,reservationId);
  assert.deepEqual(calls,[{name:'korlix_video_reserve',args:{p_user_id:alice.id,p_kind:'text_to_video',p_provider:'openai'}}]);
});
test('empty allowance blocks before a reservation can be returned',async()=>{
  const {access}=fixture({rpcResult:{ok:false}});
  await assert.rejects(()=>access.reserve({user:alice,provider:'openai',kind:'image_to_video'}),{statusCode:429});
  await assert.rejects(()=>access.reserve({user:alice,provider:'openai',kind:'text_to_video'}),{statusCode:402});
});
test('missing migration or lookup failure cannot grant access',async()=>{
  const {access}=fixture({error:{message:'missing table'}});
  await assert.rejects(()=>access.reserve({user:alice,provider:'openai',kind:'text_to_video'}),{statusCode:503});
  await assert.rejects(()=>access.requireOwnedJob({user:alice,jobId:'video_bob',provider:'openai'}),{statusCode:503});
  await assert.rejects(()=>createVideoAccess({database:null}).summary({user:alice}),{statusCode:503});
});
test('a different user cannot attach their result to another reservation',async()=>{
  const {access,calls}=fixture();
  await assert.rejects(()=>access.attach({user:bob,reservation:{id:reservationId,userId:alice.id},jobId:'video_bob'}),{statusCode:404});
  assert.equal(calls.length,0);
});
test('unsubmitted reservations do not authorize download',async()=>{
  const {access}=fixture({rows:[{user_id:alice.id,provider:'openai',provider_job_id:'video_a',status:'reserved'}]});
  await assert.rejects(()=>access.requireOwnedJob({user:alice,jobId:'video_a',provider:'openai'}),{statusCode:404});
});
