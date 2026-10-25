import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {messengerAuthAlias} from '../security/messenger_auth_alias.mjs';
import {createKorlixSignupHandler} from '../korlix_signup_eligibility.mjs';

test('Messenger aliases known account routes before handling and preserves original scope', async t => {
  const app = express(); app.use(express.json()); app.use(messengerAuthAlias);
  app.post('/api/auth/signin', (req,res) => res.json({url:req.url, original:req.originalUrl, app:req.headers['x-korlix-app'], body:req.body}));
  const server = app.listen(0,'127.0.0.1');
  await new Promise(resolve=>server.once('listening',resolve));
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  const root=`http://127.0.0.1:${server.address().port}`;
  const response=await fetch(root+'/api/messenger/auth/signin',{method:'POST',headers:{'content-type':'application/json','x-korlix-app':'korlix_ai'},body:JSON.stringify({client_app:'korlix_ai',email:'fixture@example.test'})});
  assert.equal(response.status,200);
  const value=await response.json();
  assert.equal(value.app,'korlix_messenger'); assert.equal(value.body.client_app,'korlix_messenger');
  assert.equal(value.url,'/api/auth/signin'); assert.equal(value.original,'/api/messenger/auth/signin');
  for (const path of ['/api/messenger/generate','/api/messenger/auth/signin/extra']) {
    assert.equal((await fetch(root+path,{method:'POST'})).status,404);
  }
  assert.equal((await fetch(root+'/api/messenger/auth/signin')).status,404);
});

test('Messenger duplicate signup offers shared-account sign-in and does not register another login', async () => {
  let registrations=0;
  const handler=createKorlixSignupHandler({
    supabaseAuth:{auth:{signUp:async()=>({data:{user:{identities:[]},session:null}})}},
    getRequestDeviceInfo:()=>({clientApp:'korlix_messenger'}),getOrCreateProfile:async()=>({}),
    registerDeviceSession:async()=>{registrations++;},getUserFacingError:error=>error.message,
  });
  const response={statusCode:200,status(value){this.statusCode=value;return this;},json(value){this.body=value;return this;}};
  await handler({body:{email:'fixture@example.test',password:'fixture-password',client_app:'korlix_messenger',
    signup_eligibility:{age_band:'18_plus',terms_accepted:true,privacy_acknowledged:true,policy_version:'2026-10-06'}}},response);
  assert.equal(response.statusCode,409); assert.equal(response.body.code,'KORLIX_ACCOUNT_EXISTS');
  assert.equal(registrations,0);
});
