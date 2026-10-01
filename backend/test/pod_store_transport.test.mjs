import test from 'node:test';
import assert from 'node:assert/strict';
import {createPodStore} from '../pod/store.mjs';

const privateData='SECRET private comment, user-id, request-id, token, URL and provider response';
function fixture(outcome,{start=100,end=12109,loggerThrows=false}={}) {
 const logs=[],calls=[];
 const store=createPodStore({database:{rpc:async(...args)=>{calls.push(args);if(outcome instanceof Error)throw outcome;return outcome;}},
  now:()=>calls.length ? end : start,logger:{warn:(...args)=>{logs.push(args);if(loggerThrows)throw Error(privateData);}}});
 return {store,logs,calls};
}
const contribution=store=>store.contribute('private-owner','private-episode',{requestId:'private-request',text:privateData});
const unavailable=error=>error.status===503&&error.code==='pod_storage_unavailable';

test('wrapped timeout logs only safe diagnostics and contribution keeps its unconfirmed-save wording',async()=>{
 const f=fixture({status:0,data:null,error:{code:'',message:'TimeoutError: '+privateData,details:privateData,hint:privateData}});
 await assert.rejects(contribution(f.store),error=>unavailable(error)&&error.message==='Your comment could not be confirmed as saved. Keep your text and retry.');
 assert.equal(f.calls.length,1);assert.deepEqual(f.logs,[['Pod storage unavailable',{action:'contribute',category:'timeout',elapsedMs:12009,code:null,httpStatus:null}]]);
 assert(!JSON.stringify(f.logs).includes(privateData));assert(!JSON.stringify(f.logs).includes('private-owner'));
});
test('thrown transport failure is classified without leaking cause, message, stack or input',async()=>{
 const error=new TypeError(privateData,{cause:{code:'ECONNRESET',message:privateData}}),f=fixture(error);
 await assert.rejects(contribution(f.store),unavailable);assert.equal(f.calls.length,1);
 assert.deepEqual(f.logs[0][1],{action:'contribute',category:'transport',elapsedMs:12009,code:null,httpStatus:null});assert(!JSON.stringify(f.logs).includes(privateData));
});
test('thrown timeout and timeout cause are classified with no automatic retry',async()=>{
 for(const error of [Object.assign(Error(privateData),{name:'TimeoutError'}),new TypeError(privateData,{cause:{code:'UND_ERR_CONNECT_TIMEOUT'}})]) {
  const f=fixture(error);await assert.rejects(f.store.get('private-owner','private-episode'),unavailable);
  assert.equal(f.logs[0][1].category,'timeout');assert.equal(f.calls.length,1);assert(!JSON.stringify(f.logs).includes(privateData));
 }
});
test('unknown database errors keep bounded SQL and HTTP codes without error text',async()=>{
 const f=fixture({status:500,data:null,error:{code:'42P01',message:privateData,details:privateData,hint:privateData}});
 await assert.rejects(f.store.get('private-owner','private-episode'),error=>unavailable(error)&&error.message==='Your pod could not be confirmed. Refresh before trying again.');
 assert.deepEqual(f.logs[0][1],{action:'get',category:'database',elapsedMs:12009,code:'42P01',httpStatus:500});assert.equal(f.calls.length,1);
});
test('unexpected diagnostic fields and action names cannot enter logs',async()=>{
 const f=fixture({status:privateData,data:null,error:{code:privateData,message:privateData,details:privateData,status:privateData}},{start:10,end:5});
 await assert.rejects(f.store.call('private-owner',privateData,'private-episode',{text:privateData}),unavailable);
 assert.deepEqual(f.logs[0][1],{action:'unknown',category:'transport',elapsedMs:0,code:null,httpStatus:null});assert(!JSON.stringify(f.logs).includes(privateData));
});
test('malformed RPC result and logger failure preserve a sanitized 503',async()=>{
 const f=fixture(null,{loggerThrows:true});await assert.rejects(contribution(f.store),unavailable);
 assert.deepEqual(f.logs[0][1],{action:'contribute',category:'database',elapsedMs:12009,code:null,httpStatus:null});assert.equal(f.calls.length,1);
});
test('known application conflicts and successful calls retain their existing contracts without transport warnings',async()=>{
 const conflict=fixture({error:{code:'40001',message:'Wait for the interrupted request to stop before resuming.'},status:400});
 await assert.rejects(conflict.store.control('private-owner','private-episode','resume'),e=>e.status===409&&e.code==='40001'&&e.message==='Wait for the interrupted request to stop before resuming.');assert.deepEqual(conflict.logs,[]);
 const success=fixture({data:{episode:{id:'private-episode',state:'paused'}},error:null,status:200});
 assert.deepEqual(await success.store.get('private-owner','private-episode'),{episode:{id:'private-episode',state:'paused'}});assert.deepEqual(success.logs,[]);assert.equal(success.calls.length,1);
});
