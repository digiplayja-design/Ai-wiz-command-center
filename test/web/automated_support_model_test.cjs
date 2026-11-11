const {test}=require('node:test');
const assert=require('node:assert/strict');
const M=require('../../website/nova-email/automated-support-model.js');

test('profile and case filtering never mixes support addresses',()=>{
  const profiles=M.profiles([{id:'a',displayName:'Business A',fromEmail:'help@a.example',mode:'automatic',ready:true},{id:'b',mode:'unrecognized',ready:'true'}]);
  assert.equal(profiles[0].mode,'automatic');assert.equal(profiles[1].mode,'paused');assert.equal(profiles[1].ready,false);
  const cases=[{id:'1',profileId:'a',details:'Voice connection failed',reporterEmail:'customer@example.test'},{id:'2',profileId:'b',details:'Voice connection failed'}];
  assert.deepEqual(M.cases(cases,'a','voice customer').map(c=>c.id),['1']);
  assert.deepEqual(M.cases(cases,'a','billing'),[]);
});
test('reply and mode changes send only intended fields, never editable identities',async()=>{
  const calls=[];const api=M.client(async(path,options)=>{calls.push({path,options});return{ok:true};},()=> 'owner');
  await api.reply('case/id','  Please share the feature name.  ');
  assert.equal(calls[0].path,'/api/automated-support/cases/case%2Fid/replies');
  assert.deepEqual(JSON.parse(calls[0].options.body),{text:'Please share the feature name.',confirmed:true});
  assert.throws(()=>api.mode({id:'a',ready:false},'automatic'),/Complete/);
  assert.equal(calls.length,1);
  await api.mode({id:'a',ready:true,fromEmail:'untrusted@example.test'},'automatic');
  assert.deepEqual(JSON.parse(calls[1].options.body),{mode:'automatic'});
});
test('resolved requires a recorded explanation and failed responses never become success',async()=>{
  const api=M.client(async()=>({ok:false}),()=> 'owner');
  assert.throws(()=>api.status('id','resolved',' '),/Describe/);
  assert.throws(()=>api.status('id','unknown'),/Choose/);
  await assert.rejects(api.status('id','resolved','Customer confirmed the fix.'),/could not be confirmed/);
});
test('late data from a changed account is rejected',async()=>{
  let current='owner-a',resolve;
  const api=M.client(()=>new Promise(r=>resolve=r),()=>current);
  const pending=api.detail('case-a');current='owner-b';resolve({ok:true,case:{id:'case-a',details:'private'}});
  await assert.rejects(pending,/workspace changed/);
  current='';await assert.rejects(api.profiles(),/Sign in/);
});
test('untrusted customer content is escaped for HTML rendering',()=>{
  assert.equal(M.escape('<img onerror="bad()">'), '&lt;img onerror=&quot;bad()&quot;&gt;');
  assert.equal(M.escape("A & O'Brien"),'A &amp; O&#39;Brien');
});
test('replies require a verified reporter and an open case',()=>{
  assert.equal(M.canReply({ready:true},{reporterVerified:true,state:'needs_review'}),true);
  assert.equal(M.canReply({ready:true},{reporterVerified:false,state:'new'}),false);
  assert.equal(M.canReply({ready:true},{reporterVerified:true,state:'resolved'}),false);
  assert.equal(M.canReply({ready:false},{reporterVerified:true,state:'new'}),false);
});
