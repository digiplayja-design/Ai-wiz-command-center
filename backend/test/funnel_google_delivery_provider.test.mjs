import test from 'node:test';
import assert from 'node:assert/strict';
import {googleDeliveryBody,googleDeliveryDestination,googleDeliveryStatus,createGoogleDeliveryProvider} from '../funnels/google_delivery_provider.mjs';
const destination={conversion_customer_id:'8888888888',conversion_action_id:'9223372036854775807',resource_name:'customers/8888888888/conversionActions/9223372036854775807',name:'Inquiry',status:'ENABLED',type:'UPLOAD_CLICKS',category:'SUBMIT_LEAD_FORM',counting_type:'MANY_PER_CLICK',primary_for_goal:false,click_window_days:30,attribution_model:'GOOGLE_ADS_LAST_CLICK',default_value:0,default_currency:'USD',always_use_default_value:false};
const fixture=()=>({destination,root_id:'9999999999',receipt:{event_id:'00000000-0000-4000-8000-000000000002',captured_at:'2026-09-24T12:00:00Z',click_type:'gclid',click_id:'private-click',consent:'granted',policy_version:'measurement_v1',platform:'google',event_name:'inquiry_submitted',email:'never-send@example.com'}});
const now=Date.parse('2026-09-24T13:00:00Z'),dest=googleDeliveryDestination(destination,'9999999999');
const response=(state='SUCCESS')=>({requestStatusPerDestination:[{destination:dest,requestStatus:state,eventsIngestionStatus:{recordCount:'1'}}]});
test('K192 payload includes only consented click, time and stable event identity for action owner',()=>{
 for(const type of ['gclid','gbraid','wbraid']){const a=fixture();a.receipt.click_type=type;const body=googleDeliveryBody(a,now);assert.deepEqual(Object.keys(body),['destinations','events']);assert.deepEqual(Object.keys(body.events[0]),['transactionId','eventTimestamp','adIdentifiers','consent']);assert.deepEqual(body.events[0].adIdentifiers,{[type]:'private-click'});assert.deepEqual(body.events[0].consent,{adUserData:'CONSENT_GRANTED',adPersonalization:'CONSENT_DENIED'});assert(!JSON.stringify(body).includes('never-send'));assert.equal(body.destinations[0].operatingAccount.accountId,'8888888888');}
 for(const change of [{consent:'declined'},{platform:'meta'},{click_type:'fbclid'},{click_id:'bad\n'},{captured_at:'2026-09-10T12:00:00Z'},{captured_at:'2026-09-25T12:00:00Z'}]){const a=fixture();Object.assign(a.receipt,change);assert.throws(()=>googleDeliveryBody(a,now));}
 const a=fixture();a.destination={...destination,counting_type:'ONE_PER_CLICK'};a.receipt.click_type='wbraid';assert.throws(()=>googleDeliveryBody(a,now));
});
test('K192 ingest uses fixed HTTPS, one request, bounded response, sanitized receipt',async()=>{
 const calls=[],p=createGoogleDeliveryProvider({fetchImpl:async(url,options)=>{calls.push({url,options});return new Response(JSON.stringify({requestId:'provider-id',fieldWarnings:[{message:'private echo'}]}));}});
 assert.deepEqual(await p.ingest('private-token',googleDeliveryBody(fixture(),now)),{request_id:'provider-id',has_warnings:true});assert.equal(calls.length,1);assert.equal(calls[0].url.href,'https://datamanager.googleapis.com/v1/events:ingest');assert.equal(calls[0].options.redirect,'error');assert.equal(calls[0].options.method,'POST');assert(calls[0].options.signal);assert.equal(calls[0].options.headers['developer-token'],undefined);
 for(const res of [new Response('{'),new Response(JSON.stringify({error:{message:'private-click'}}),{status:400}),new Response(JSON.stringify({requestId:'x\n'})),new Response('x'.repeat(128*1024+1))]){
  let count=0;const provider=createGoogleDeliveryProvider({fetchImpl:async()=>{count++;return res;}});await assert.rejects(provider.ingest('token',{}),e=>!e.message.includes('private-click'));assert.equal(count,1);
 }
});
test('K192 diagnostics verify one destination and one event; processing never means attributed',()=>{
 for(const [input,state]of [['PROCESSING','processing'],['SUCCESS','succeeded'],['FAILED','rejected'],['PARTIAL_SUCCESS','partial']])assert.equal(googleDeliveryStatus(response(input),dest).state,state);
 for(const mutate of [r=>r.requestStatusPerDestination.push(r.requestStatusPerDestination[0]),r=>r.requestStatusPerDestination[0].destination={...dest,productDestinationId:'1'},r=>r.requestStatusPerDestination[0].eventsIngestionStatus.recordCount='2',r=>r.requestStatusPerDestination[0].requestStatus='NEW_ENUM',r=>r.requestStatusPerDestination[0].errorInfo={errorCounts:[{reason:'PRIVATE text',recordCount:'1'}]},r=>r.requestStatusPerDestination[0].errorInfo={errorCounts:[{reason:'PROCESSING_ERROR_REASON_INVALID_GCLID',recordCount:'1'}]}]){const r=structuredClone(response());mutate(r);assert.throws(()=>googleDeliveryStatus(r,dest));}
});
test('K192 status transport only retrieves saved request and never ingests or forwards errors',async()=>{
 let call;const p=createGoogleDeliveryProvider({fetchImpl:async(url,options)=>{call={url,options};return new Response(JSON.stringify(response()));}});assert.equal((await p.status('token','a/b?c',dest)).state,'succeeded');assert.equal(call.url.origin,'https://datamanager.googleapis.com');assert.equal(call.url.pathname,'/v1/requestStatus:retrieve');assert.equal(call.url.searchParams.get('requestId'),'a/b?c');assert.equal(call.options.method,'GET');assert.equal(call.options.body,undefined);
});
