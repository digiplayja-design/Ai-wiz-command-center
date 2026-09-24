import test from 'node:test';
import assert from 'node:assert/strict';
import {createMetaProvider,MetaAccessError} from '../funnels/meta.mjs';
import {MetaConversionAccessError,metaDestinationList} from '../funnels/meta_conversion_provider.mjs';
const cfg={apiVersion:'v26.0',secret:'fixture-secret-not-a-credential'};
const row={id:'12345678901234567890',name:'Website data source'};
const json=(data,status=200)=>new Response(JSON.stringify(data),{status});
function provider(responses,calls=[]){return createMetaProvider(cfg,{fetchImpl:async(url,options)=>{calls.push({url,options});const r=responses.shift();return r instanceof Response?r:json(r);}});}
test('K193 data source reader uses account membership, narrow fields and fixed-host cursor pagination',async()=>{
 const calls=[],p=provider([{data:[{...row,code:'private-pixel-snippet',access_token:'private-token'}],paging:{next:'https://evil.example/events',cursors:{after:'opaque'}}},{data:[]}],calls);
 assert.deepEqual(await p.conversionDestinations('fixture-token','act_123'),[{pixel_id:row.id,name:row.name}]);assert.equal(calls.length,2);
 for(const {url,options} of calls){assert.equal(url.hostname,'graph.facebook.com');assert.equal(url.pathname,'/v26.0/act_123/adspixels');assert.equal(url.searchParams.get('fields'),'id,name');assert.equal(url.searchParams.get('limit'),'100');assert(!url.searchParams.has('access_token'));assert(url.searchParams.get('appsecret_proof'));assert.equal(options.headers.Authorization,'Bearer fixture-token');assert.equal(options.redirect,'error');assert(options.signal);assert(!options.method||options.method==='GET');assert.equal(options.body,undefined);}
 assert.equal(calls[1].url.searchParams.get('after'),'opaque');
});
test('K193 permission failures are redacted and distinct from expired account authorization',async()=>{
 for(const code of [10,200,283])await assert.rejects(provider([json({error:{code,message:'private-token'}},403)]).conversionDestinations('t','act_123'),e=>e instanceof MetaConversionAccessError&&!(e instanceof MetaAccessError)&&!e.message.includes('private-token'));
 await assert.rejects(provider([json({error:{code:190,message:'private-token'}},401)]).conversionDestinations('t','act_123'),MetaAccessError);
});
test('K193 malformed metadata and duplicate identities fail closed, while empty discovery is valid',async()=>{
 for(const data of [[row,row],[{...row,id:123}],[{...row,name:''}],[{...row,name:' x'}],[{...row,name:'bad\n'}],[{...row,name:'a'.repeat(1001)}],Array(101).fill(row),{},[null]])await assert.rejects(provider([{data}]).conversionDestinations('t','act_123'));
 assert.deepEqual(await provider([{data:[]}]).conversionDestinations('t','act_123'),[]);
 for(const d of [{pixel_id:'123',name:'Name',extra:true},{pixel_id:'bad',name:'Name'},null])assert.throws(()=>metaDestinationList([d]));
 const calls=[];await assert.rejects(provider([],calls).conversionDestinations('t','123/events'));assert.equal(calls.length,0);
});
test('K193 accepts at most 500 complete choices and rejects incomplete pages and cursor loops',async()=>{
 const pages=Array.from({length:5},(_,i)=>({data:Array.from({length:100},(_,j)=>({...row,id:String(i*100+j+1)})),...(i<4?{paging:{next:'ignored',cursors:{after:String(i+1)}}}:{})}));
 assert.equal((await provider(pages.slice()).conversionDestinations('t','act_123')).length,500);
 await assert.rejects(provider(pages.map((p,i)=>({...p,paging:{next:'ignored',cursors:{after:String(i+1)}}}))).conversionDestinations('t','act_123'),/More than 500/);
 for(const paging of [[],{next:true},{next:''},{next:'ignored'}, {next:'ignored',cursors:{after:''}},{next:'ignored',cursors:{after:'a'.repeat(4001)}}])await assert.rejects(provider([{data:[row],paging}]).conversionDestinations('t','act_123'));
 await assert.rejects(provider([{data:[row],paging:{next:'ignored',cursors:{after:'same'}}},{data:[{...row,id:'2'}],paging:{next:'ignored',cursors:{after:'same'}}}]).conversionDestinations('t','act_123'));
});
test('K193 bounds provider response bytes, does not retry and never echoes raw provider failures',async()=>{
 for(const response of [new Response('x'.repeat(1024*1024+1)),new Response('invalid'),json(null),json([]),json({error:{code:2,message:'raw-private-error'}},503)]){
  const calls=[];await assert.rejects(provider([response],calls).conversionDestinations('t','act_123'),e=>!e.message.includes('raw-private-error'));assert.equal(calls.length,1);
 }
 let calls=0;const p=createMetaProvider(cfg,{fetchImpl:async()=>{calls++;throw Error('private-network-data');}});await assert.rejects(p.conversionDestinations('t','act_123'),e=>!e.message.includes('private-network-data'));assert.equal(calls,1);
});
