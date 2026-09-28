const assert = require('node:assert/strict');
const {test} = require('node:test');
const M = require('../../website/nova-email/email-workspace-model.js');
const now = Date.parse('2026-09-28T12:00:00Z');
const app = {
  connected:true, panelErrors:{},
  drafts:[
    {id:'a',subject:'Invoice follow-up',to_email:'accounts@example.test',status:'draft',text_body:'Please review the attached items.',created_at:'2026-09-28T11:00:00Z'},
    {id:'b',subject:'Invoice correction',status:'failed',createdAt:'2026-09-27T11:00:00Z'},
    {id:'c',subject:'Approved estimate',status:'approved'},
    {id:'d',subject:'Received',status:'delivered'},
  ],
  recipients:[{id:'r1',email:'active@example.test',consent_status:'transactional_only',active:true},{id:'r2',email:'blocked@example.test',consent_status:'suppressed',active:true}],
  rules:[{id:'q1',name:'Weekly follow-up',enabled:true,sendMode:'autopilot',preapproved:true,nextRunAt:'2026-09-29T12:00:00Z'},{id:'q2',name:'Paused rule',enabled:false},{id:'q3',name:'Needs approval',enabled:true,sendMode:'autopilot',preapproved:false}],
  events:[{id:'e1',type:'email.bounced',createdAt:'2026-09-28T11:00:00Z'},{id:'e2',type:'email.failed',createdAt:'2026-09-26T11:00:00Z'}],
};
test('partial multi-word search includes backend address and body fields', () => {
  const rows = M.records(app,'drafts');
  assert.deepEqual(M.select(rows,{query:'invo accounts rev'}).rows.map(r=>r.id),['a']);
  assert.equal(M.select(rows,{filter:'review'}).total,1);
  assert.equal(M.select(rows,{filter:'approved'}).rows[0].id,'c');
  assert.equal(M.select(rows,{filter:'issues'}).rows[0].id,'b');
});
test('restricted recipients are never described as eligible', () => {
  const rows = M.records(app,'recipients');
  assert.deepEqual(M.select(rows,{filter:'active'}).rows.map(r=>r.id),['r1']);
  assert.deepEqual(M.select(rows,{filter:'restricted'}).rows.map(r=>r.id),['r2']);
});
test('summaries distinguish review, draft failures, and recent delivery issues', () => {
  const s=M.summary(app,now);
  assert.equal(s.review,1); assert.equal(s.issues,1); assert.equal(s.rules,2); assert.equal(s.recentIssues,1); assert.equal(s.upcoming.id,'q1');
  assert.equal(M.select(M.records(app,'rules'),{filter:'issues'}).rows[0].id,'q3');
});
test('disconnected and failed panels never expose stale rows', () => {
  assert.equal(M.records({...app,connected:false},'drafts').length,0);
  assert.equal(M.records({...app,workspaceStale:true},'drafts').length,0);
  assert.equal(M.records({...app,panelErrors:{drafts:true}},'drafts').length,0);
  assert.equal(M.summary({...app,connected:false},now).upcoming,undefined);
});
test('pagination clamps stale pages after filtering and sorts reliably', () => {
  const rows=M.records(app,'drafts');
  assert.equal(M.select(rows,{page:90,pageSize:2}).page,1);
  assert.deepEqual(M.select(rows,{query:'correction',page:90,pageSize:2}).rows.map(r=>r.id),['b']);
  assert.equal(M.select(rows,{sort:'name'}).rows[0].id,'c');
});
test('untrusted subjects and rule bodies are escaped before HTML rendering', () => {
  assert.equal(M.escape('<img src=x onerror="alert(1)">'), '&lt;img src=x onerror=&quot;alert(1)&quot;&gt;');
  assert.equal(M.escape("O'Brien & Co"),'O&#39;Brien &amp; Co');
});
