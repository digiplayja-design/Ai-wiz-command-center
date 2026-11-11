import test from 'node:test';
import assert from 'node:assert/strict';
import {createBrainBilling} from '../brain_voice/billing/routes.mjs';
import {BillingError} from '../web_billing/core.mjs';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

function fixture(error) {
  const routes=new Map();
  const billing=createBrainBilling({autoStart:false,provider:{ready:()=>true},
    environment:{KORLIX_BRAIN_BILLING_ENABLED:'true'},requireUser:async()=>{throw error;}});
  billing.register({get:(path,fn)=>routes.set(path,fn),post:(path,fn)=>routes.set(path,fn)});
  const output={};const response={set(){return this;},status(status){output.status=status;return this;},json(body){output.body=body;return this;}};
  return {run:async()=>{await routes.get('/api/brain/billing/status')({query:{}},response);return output;}};
}

for(const status of [400,401,402,403,409,429]) {
  test(`Brain billing preserves actionable status ${status}`,async()=>{
    assert.deepEqual(await fixture(new BillingError('Actionable account message.',status)).run(),
      {status,body:{error:'Actionable account message.'}});
  });
}
test('Brain billing hides server internals and tolerates legacy statusCode errors',async()=>{
  assert.deepEqual(await fixture(Object.assign(new Error('Sign in again.'),{statusCode:401})).run(),
    {status:401,body:{error:'Sign in again.'}});
  const result=await fixture(new Error('database credential detail')).run();
  assert.equal(result.status,503);assert.doesNotMatch(result.body.error,/credential/);
});

test('the production voice error adapter handles both error contracts and hides unexpected server details',async()=>{
  const source=await readFile(new URL('../server.js',import.meta.url),'utf8');
  const start=source.indexOf('function korlixLiveConvoErrorStatusV1(');
  const end=source.indexOf('function korlixLiveConvoAgentRouteV1(',start);
  assert(start>0&&end>start);
  const context=vm.createContext({
    korlixLiveConvoAgentTextV1:(value,max)=>String(value||'').slice(0,max),
    getKorlixUserFacingError:error=>String(error.message).replace('secret-value','[hidden]'),
  });
  vm.runInContext(source.slice(start,end),context);
  for(const error of [new BillingError('Your Live minutes have run out.',402),
    Object.assign(new Error('End the previous session.'),{statusCode:409}),
    new BillingError('secret-value cannot be used.',403)]) {
    const output={};const res={status(s){output.status=s;return this;},json(value){output.body=value;return this;}};
    context.korlixLiveConvoAgentErrorV1(res,error,'Voice is temporarily unavailable.');
    assert.equal(output.status,error.statusCode??error.status);
    assert.doesNotMatch(output.body.error,/secret-value/);
  }
  for(const error of [new Error('database secret-value'),{status:503,message:'database secret-value'},
    {status:200,message:'secret-value'},{status:'429',message:'secret-value'}]) {
    const output={};const res={status(s){output.status=s;return this;},json(value){output.body=value;return this;}};
    context.korlixLiveConvoAgentErrorV1(res,error,'Voice is temporarily unavailable.');
    assert(output.status>=500);assert.equal(output.body.error,'Voice is temporarily unavailable.');
  }
  for(const code of ['live_convo_usage_report_failed','live_convo_reservation_failed','live_convo_session_error']) {
    const location=source.indexOf(`code: "${code}"`);
    assert(location>0);
    const body=source.slice(location-170,location+450);
    assert.match(body,/const status = korlixLiveConvoErrorStatusV1\(error\)/);
    assert.match(body,/res\.status\(status\)/);
    assert.match(body,/status < 500/);
    assert.doesNotMatch(body,/details: error/);
  }
});
