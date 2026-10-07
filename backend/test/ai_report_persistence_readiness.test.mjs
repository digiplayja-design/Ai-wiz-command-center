import test from 'node:test';
import assert from 'node:assert/strict';
import {inspectSupportAggregates,validateTarget} from '../ops/support_readiness.mjs';

test('readiness inventory requests head counts only and exports no rows or diagnostics',async()=>{
  const calls=[];
  const database={from(table){return {select(columns,options){calls.push({table,columns,options});return this;},
    eq(){return this;},neq(){return this;},in(){return this;},lte(){return this;},
    async abortSignal(){return {count:3,data:[{email:'private@example.invalid',details:'customer text'}],error:null};}};}};
  const result=await inspectSupportAggregates(database,{now:new Date('2026-10-07T22:00:00Z')});
  assert.equal(calls.length,15);
  for(const call of calls) assert.deepEqual(call.options,{count:'exact',head:true});
  assert.equal(result.assignedModerators.count,3);assert.equal(result.mutationsPerformed,false);
  assert.equal(result.queues.length,4);assert(!JSON.stringify(result).includes('private@example'));assert(!JSON.stringify(result).includes('customer text'));
});

test('readiness errors remain unverified rather than reporting a falsely empty queue',async()=>{
  const result=await inspectSupportAggregates({from(){throw new Error('secret credential');}});
  assert.equal(result.queues[0].open.verified,false);assert.equal(result.assignedModerators.verified,false);
  assert(!('count' in result.queues[0].open));assert(!JSON.stringify(result).includes('secret'));
});

test('live inspection rejects mismatched or credential-bearing endpoints before sending keys',()=>{
  const project='uxtjzjbwtppjvnsoiijv';
  const env={SUPABASE_URL:`https://${project}.supabase.co`,SUPABASE_SERVICE_ROLE_KEY:'synthetic-only'};
  assert.equal(validateTarget(env,project),env.SUPABASE_URL);
  for(const url of ['https://example.com',`http://${project}.supabase.co`,`https://user@${project}.supabase.co`,
    `https://${project}.supabase.co?token=secret`,`https://${project}.supabase.co/other`]) {
    assert.throws(()=>validateTarget({...env,SUPABASE_URL:url},project));
  }
  assert.throws(()=>validateTarget(env,'differentprojectaaaa'));
  assert.throws(()=>validateTarget({...env,SUPABASE_SERVICE_ROLE_KEY:''},project));
});
