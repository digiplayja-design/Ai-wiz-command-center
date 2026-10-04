import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';
const code = await readFile(new URL('../web/korlix_social_push_sw.js', import.meta.url), 'utf8');
const owner = '11111111-1111-4111-8111-111111111111';
function worker() {
  const events = {}, shown = [], stored = new Map(), opened = [], focused = [], posted = [], closed = [];
  const db = { close() {}, transaction() {
    const tx = { objectStore() { return { get(key) { return run(() => stored.get(key)); }, put(value, key) { return run(() => { stored.set(key, value); return key; }); } }; } };
    function run(action) { const operation = {}; queueMicrotask(() => { operation.result = action(); operation.onsuccess?.(); tx.oncomplete?.(); }); return operation; }
    return tx;
  }};
  const indexedDB = {open() {const req = {}; queueMicrotask(() => { req.result = db; req.onsuccess(); }); return req;}};
  const self = { addEventListener: (key, cb) => { events[key] = cb; }, skipWaiting: async () => {}, location:{origin:'https://korlix.test'},
    registration:{scope:'https://korlix.test/app/social-push/',getNotifications:async()=>[{close(){closed.push(true);}}],showNotification:async(title,opts)=>shown.push({title,...opts})},
    clients:{matchAll:async()=>[{url:'https://korlix.test/app/',postMessage:data=>posted.push(data),focus:async()=>focused.push(true)}],openWindow:async url=>opened.push(url)}};
  vm.runInNewContext(code,{self,indexedDB,URL,Date,Promise});
  async function fire(kind, payload) { let done; events[kind]({...payload,waitUntil(promise){done=promise;}}); await done; }
  return {shown,stored,opened,focused,posted,closed,self,fire,async bind(value=owner){await fire('message',{data:{type:'bind',binding:value},ports:[{postMessage(){}}]});}};
}
const payload = (data={}) => ({kind:'call',binding:owner,eventId:'event',expiresAt:new Date(Date.now()+30000).toISOString(),...data});
test('push only shows current, unexpired account binding without leaking supplied content',async()=>{
  const w=worker(); await w.bind();
  await w.fire('push',{data:{json:()=>payload({title:'private name',body:'private message',url:'https://attacker.test'})}});
  assert.equal(w.shown.length,1); assert.equal(w.shown[0].title,'KORLIX Social');
  assert.ok(!JSON.stringify(w.shown).includes('private')); assert.ok(!JSON.stringify(w.shown).includes('attacker'));
  await w.fire('push',{data:{json:()=>payload({binding:'other-account'})}});
  await w.fire('push',{data:{json:()=>payload({expiresAt:'2000-01-01T00:00:00Z'})}});
  await w.fire('push',{data:{json:()=>{throw Error('invalid');}}});
  assert.equal(w.shown.length,1);
});
test('logout removes the binding and closes visible notifications',async()=>{
  const w=worker(); await w.bind(); await w.fire('message',{data:{type:'clear'},ports:[{postMessage(){}}]});
  await w.fire('push',{data:{json:()=>payload()}});
  assert.equal(w.shown.length,0); assert.equal(w.stored.get('binding'),''); assert.equal(w.closed.length,2);
});
test('warm click focuses app and sends a view request without reload or automatic answer',async()=>{
  const w=worker(); await w.bind();
  await w.fire('notificationclick',{notification:{data:{binding:owner},close(){}}});
  assert.equal(w.focused.length,1); assert.equal(w.opened.length,0);
  assert.deepEqual(JSON.parse(JSON.stringify(w.posted)),[{type:'korlix-social-open',binding:owner}]);
});
test('cold click uses a fixed same-origin Social entry point',async()=>{
  const w=worker(); await w.bind(); w.self.clients.matchAll=async()=>[];
  await w.fire('notificationclick',{notification:{data:{binding:owner,url:'https://attacker.test'},close(){}}});
  assert.deepEqual(w.opened,['https://korlix.test/app/?social=1']);
});
test('notification clicks from a previous account cannot open the current account',async()=>{
  const w=worker(); await w.bind();
  await w.fire('notificationclick',{notification:{data:{binding:'previous'},close(){}}});
  assert.equal(w.focused.length,0); assert.equal(w.opened.length,0);
});
