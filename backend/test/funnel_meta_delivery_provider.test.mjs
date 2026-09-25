import test from 'node:test';
import assert from 'node:assert/strict';
import {createMetaDeliveryProvider,metaDeliveryBody,metaDeliveryReceipt,metaDeliveryToken} from '../funnels/meta_delivery_provider.mjs';
const clock=Date.parse('2026-09-25T00:00:00Z'),token='private-system-token-fixture';
const config={id:'1234567',secret:'private-app-secret',apiVersion:'v26.0'};
const destination={pixel_id:'987654321',name:'Website inquiries'};
const receipt={state:'prepared',consent:'granted',policy_version:'meta_measurement_v2',event_name:'Lead',action_source:'website',event_id:'00000000-0000-4000-8000-000000000003',captured_at:'2026-09-24T23:59:00.987Z',observed_at:'2026-09-24T23:58:00.123Z',click_id:'CaseSensitive_FB-Click',client_user_agent:'Fixture browser',event_source_url:'https://example.com/f/services'};
const debug=()=>({data:{is_valid:true,type:'SYSTEM_USER',app_id:config.id,user_id:'77777',scopes:['ads_management'],expires_at:0,data_access_expires_at:0}});
const response=(value,status=200)=>new Response(JSON.stringify(value),{status,headers:{'Content-Type':'application/json'}});
test('K195 provider builds exactly one bounded Lead with original click time and stable identity',()=>{
 const body=metaDeliveryBody({...receipt,email:'excluded',client_ip_address:'excluded',fbp:'excluded'},clock);
 assert.deepEqual(body,{data:[{event_name:'Lead',event_time:1790294340,event_id:receipt.event_id,action_source:'website',event_source_url:receipt.event_source_url,user_data:{client_user_agent:receipt.client_user_agent,fbc:'fb.1.1790294280123.CaseSensitive_FB-Click'}}]});
 assert.equal(metaDeliveryToken(token),true);for(const value of ['',null,'short','token with spaces','x'.repeat(12001)])assert.equal(metaDeliveryToken(value),false);
});
test('K195 provider refuses legacy consent, incomplete evidence, forged URLs and invalid timing',()=>{
 const patches=[{policy_version:'measurement_v1'},{consent:'declined'},{state:'missing_browser'},{event_name:'Purchase'},{action_source:'physical_store'},{event_id:'bad'},{click_id:'contains.dot'},{click_id:'x'.repeat(513)},{client_user_agent:''},{client_user_agent:'has\nnewline'},{client_user_agent:'x'.repeat(1025)},{event_source_url:'https://example.com/f/services?email=leak'},{event_source_url:'http://example.com/f/services'},{event_source_url:'https://user:password@example.com/f/services'},{observed_at:'2026-09-25T00:01:00Z'},{observed_at:'2026-09-24T22:00:00Z'},{captured_at:'2026-09-17T00:00:00Z'},{captured_at:'2026-09-25T00:01:00Z'},{captured_at:'infinity'}];
 for(const patch of patches)assert.throws(()=>metaDeliveryBody({...receipt,...patch},clock),/eligible/);
});
test('K195 system-user preflight verifies app, scopes, source and zero/finite expiry without writing',async()=>{
 const calls=[];const p=createMetaDeliveryProvider(config,{now:()=>clock,fetchImpl:async(url,options)=>{calls.push({url,options});return response(url.pathname.endsWith('/debug_token')?debug():{id:destination.pixel_id,name:destination.name});}});
 assert.deepEqual(await p.authorize(token,destination),{system_user_id:'77777',expires_at:null});assert.equal(calls.length,2);
 assert(calls.every(c=>c.options.method==='GET'&&c.options.redirect==='error'&&c.options.signal));
 assert.equal(calls[0].options.headers.Authorization,'Bearer '+config.id+'|'+config.secret);assert.equal(calls[0].url.searchParams.get('input_token'),token);
 assert.equal(calls[1].options.headers.Authorization,'Bearer '+token);assert.equal(calls[1].url.searchParams.get('fields'),'id,name');
 const exp=Math.floor(clock/1000)+3600;
 const finite=createMetaDeliveryProvider(config,{now:()=>clock,fetchImpl:async(url)=>response(url.pathname.endsWith('/debug_token')?{data:{...debug().data,expires_at:exp,data_access_expires_at:exp+3600}}:{id:destination.pixel_id,name:destination.name})});
 assert.equal((await finite.authorize(token,destination)).expires_at,new Date(exp*1000).toISOString());
});
for(const [name,patch] of Object.entries({
 'USER read token':{type:'USER'},'different app':{app_id:'22222'},'revoked token':{is_valid:false},'read scope only':{scopes:['ads_read']},
 'missing scope list':{scopes:null},'unknown expiry':{expires_at:undefined},'expired access':{expires_at:1},'expired data access':{data_access_expires_at:1},'invalid system user':{user_id:'act_123'},
})){
 test('K195 rejects '+name+' before reading data source',async()=>{
  let calls=0;const p=createMetaDeliveryProvider(config,{now:()=>clock,fetchImpl:async()=>{calls++;return response({data:{...debug().data,...patch}});}});
  await assert.rejects(p.authorize(token,destination));assert.equal(calls,1);
 });
}
test('K195 changed data source identity cannot authorize a token',async()=>{
 for(const pixel of [{id:'123',name:destination.name},{id:destination.pixel_id,name:'Renamed'}]){
  const p=createMetaDeliveryProvider(config,{now:()=>clock,fetchImpl:async(url)=>response(url.pathname.endsWith('/debug_token')?debug():pixel)});
  await assert.rejects(p.authorize(token,destination),/data source changed/);
 }
});
test('K195 only one POST uses the system token, exact endpoint and app secret proof',async()=>{
 const calls=[];const p=createMetaDeliveryProvider(config,{now:()=>clock,fetchImpl:async(url,options)=>{calls.push({url,options});return response({events_received:1,messages:['Private provider content'],fbtrace_id:'trace_123'});}});
 assert.deepEqual(await p.send(token,destination,metaDeliveryBody(receipt,clock)),{trace_id:'trace_123',has_warnings:true});assert.equal(calls.length,1);
 const c=calls[0];assert.equal(c.url.href,'https://graph.facebook.com/v26.0/987654321/events');assert.equal(c.options.method,'POST');assert.equal(c.options.headers.Authorization,'Bearer '+token);assert.equal(c.options.redirect,'error');
 const body=JSON.parse(c.options.body);assert.deepEqual(body.data,metaDeliveryBody(receipt,clock).data);assert.match(body.appsecret_proof,/^[a-f0-9]{64}$/);assert(!c.options.body.includes(token));
});
test('K195 response parsing requires one receipt and drops provider message content',()=>{
 assert.deepEqual(metaDeliveryReceipt({events_received:1,messages:[],fbtrace_id:'trace'}),{trace_id:'trace',has_warnings:false});
 for(const patch of [{events_received:0},{events_received:2},{events_received:'1'},{messages:null},{messages:Array(101).fill('x')},{fbtrace_id:'raw\ntext'},{error:{message:'secret'}}])assert.throws(()=>metaDeliveryReceipt({events_received:1,messages:[],fbtrace_id:'trace',...patch}),/do not resend/);
});
test('K195 malformed, oversized, HTTP and network failures never retry or expose provider details',async()=>{
 for(const fetchImpl of [async()=>{throw Error('private transport token');},async()=>new Response('not json'),async()=>new Response('x'.repeat(131073)),async()=>response({error:{message:'secret'}},403),async()=>response({events_received:0,messages:[],fbtrace_id:'trace'})]){
  let calls=0;const p=createMetaDeliveryProvider(config,{fetchImpl:async(...a)=>{calls++;return fetchImpl(...a);}});
  await assert.rejects(p.send(token,destination,metaDeliveryBody(receipt,clock)),e=>{assert(!e.message.includes('secret'));assert.match(e.message,/do not resend/);return true;});assert.equal(calls,1);
 }
});
test('K195 unsupported API version never starts a request',async()=>{
 let calls=0;const p=createMetaDeliveryProvider({...config,apiVersion:'v999.0'},{fetchImpl:async()=>{calls++;throw Error();}});
 await assert.rejects(p.authorize(token,destination),/supported API/);assert.equal(calls,0);
});
