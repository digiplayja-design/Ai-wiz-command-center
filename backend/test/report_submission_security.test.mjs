import test from 'node:test';
import assert from 'node:assert/strict';
import {createReportSubmissionGuard} from '../security/report_submission.mjs';

const actor={id:'trusted-user',email:'verified@example.invalid'};
const req=body=>({body,headers:{}});
test('anonymous reports fail before any report is constructed',()=>{
  let ids=0;const guard=createReportSubmissionGuard({idFactory:()=>{ids++;return 'test';}});
  assert.throws(()=>guard({req:req({})}),{statusCode:401});assert.equal(ids,0);
});
test('report identity and reference are server-generated, unknown/raw fields are discarded',()=>{
  const guard=createReportSubmissionGuard({idFactory:()=> 'server-id'});
  const report=guard({user:actor,req:{body:{id:'forged',userId:'victim',user_id:'victim',userEmail:'victim@example.invalid',email:'victim@example.invalid',raw:{token:'secret'},unknown:'secret',reason:'A\r\nB',details:'Needs review'},headers:{'x-korlix-user-email':'victim@example.invalid','x-forwarded-for':'forged-ip'},ip:'synthetic-ip'}});
  assert.equal(report.userId,actor.id);assert.equal(report.userEmail,actor.email);
  assert.equal(report.id,'korlix_report_server-id');assert.equal(report.reason,'A  B');assert.equal(report.ip,'synthetic-ip');
  assert.equal(report.raw,undefined);assert.equal(report.unknown,undefined);assert(!JSON.stringify(report).includes('victim'));assert(!JSON.stringify(report).includes('secret'));
});
test('32 KiB cap counts UTF-8 bytes and unknown input fields before they can be logged',()=>{
  const guard=createReportSubmissionGuard();
  for(const body of [{details:'x'.repeat(32769)},{details:'🌪'.repeat(10000)},{ignored:'x'.repeat(32769)}]) {
    assert.throws(()=>guard({user:actor,req:req(body)}),{statusCode:413});
  }
  assert.equal(guard({user:actor,req:req({details:'x'.repeat(1000)})}).details.length,1000);
});
test('five reports per ten minutes, independently per verified user',()=>{
  let time=1000000;const guard=createReportSubmissionGuard({now:()=>time});
  for(let i=0;i<5;i++) guard({user:actor,req:req({userId:'rotating-'+i})});
  assert.throws(()=>guard({user:actor,req:req({userId:'other'})}),{statusCode:429,retryAfter:600});
  assert.equal(guard({user:{...actor,id:'another-user'},req:req({})}).userId,'another-user');
  time+=600000;assert.equal(guard({user:actor,req:req({})}).userId,actor.id);
});
test('bounded limiter cannot be bypassed by evicting active users',()=>{
  let time=1000000;const guard=createReportSubmissionGuard({now:()=>time,maxTrackedUsers:1,maxPerWindow:1});
  guard({user:actor,req:req({})});
  assert.throws(()=>guard({user:{...actor,id:'another-user'},req:req({})}),{statusCode:503});
  assert.throws(()=>guard({user:actor,req:req({})}),{statusCode:429});
  time+=600000;assert.equal(guard({user:{...actor,id:'another-user'},req:req({})}).userId,'another-user');
});
test('invalid or oversized submissions do not consume a legitimate user allowance',()=>{
  const guard=createReportSubmissionGuard({maxPerWindow:1});
  assert.throws(()=>guard({user:actor,req:req([])}),{statusCode:400});
  assert.throws(()=>guard({user:actor,req:req({details:'x'.repeat(40000)})}),{statusCode:413});
  assert.equal(guard({user:actor,req:req({})}).userId,actor.id);
});
