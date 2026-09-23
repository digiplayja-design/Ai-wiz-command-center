import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {createMetaProvider,MetaAccessError} from '../funnels/meta.mjs';
import {readMetaLocations,metaLocationProof,metaLocationProofValid} from '../funnels/meta_locations.mjs';
const input={q:'Columbus',country:'US',kind:'city',fingerprint:'a'.repeat(64)};
const raw={key:'424242',name:'Columbus',country_code:'US',type:'city',region:'Ohio'};
const config={apiVersion:'v26.0',secret:'fixture-secret-only'};
test('Meta search uses fixed Graph route, bounded first page, bearer auth and appsecret proof',async()=>{
 let calls=0;const p=createMetaProvider(config,{fetchImpl:async(url,options)=>{
 calls++;assert.equal(url.origin,'https://graph.facebook.com');assert.equal(url.pathname,'/v26.0/search');assert.equal(url.searchParams.get('type'),'adgeolocation');assert.equal(url.searchParams.get('country_code'),'US');assert.equal(url.searchParams.get('location_types'),'["city"]');assert.equal(url.searchParams.get('q'),'Columbus');assert.equal(url.searchParams.get('limit'),'31');assert.equal(url.searchParams.get('appsecret_proof'),createHmac('sha256',config.secret).update('fake-token').digest('hex'));assert(!url.href.includes('fake-token'));assert.equal(options.headers.Authorization,'Bearer fake-token');assert.equal(options.redirect,'error');assert(options.signal);return new Response(JSON.stringify({data:[raw],paging:{next:'https://untrusted.example/?access_token=private'}}));}});
 const r=await p.locations('fake-token',input);assert.equal(calls,1);assert.deepEqual(r,{locations:[{key:raw.key,name:raw.name,country:'US',type:'city',region:'Ohio'}],more:true});assert(!JSON.stringify(r).includes('private'));
});
test('Meta location provider rejects oversized, malformed, cross-country and duplicate responses',async()=>{
 const cases=[{data:null},{data:Array.from({length:32},()=>raw)},{data:[raw,raw]},{data:[{...raw,country_code:'CA'}]},{data:[{...raw,type:'zip'}]},{data:[{...raw,name:'<City>'}]},{data:[{...raw,key:123}]},{data:[{...raw,region:5}]},{data:[raw],paging:{next:4}}];
 for(const value of cases)await assert.rejects(readMetaLocations(async()=>value,'token',input),e=>e.status===503);
 const provider=createMetaProvider(config,{fetchImpl:async()=>new Response(' '.repeat(1024*1024+1))});await assert.rejects(provider.locations('token',input),e=>e.status===503);
});
test('Meta location results keep separate city/region keys and report more without pagination',async()=>{
 const rows=Array.from({length:31},(_,i)=>({...raw,key:String(i)}));const r=await readMetaLocations(async()=>({data:rows}),'token',input);assert.equal(r.locations.length,30);assert.equal(r.more,true);
 const both=await readMetaLocations(async()=>({data:[raw,{...raw,type:'region',region:null}]}),'token',{...input,kind:'all'});assert.equal(both.locations.length,2);assert.equal(both.locations[1].region,'');
});
test('Meta location access errors are redacted and do not use Page-permission errors',async()=>{
 for(const code of [10,190,200]){const p=createMetaProvider(config,{fetchImpl:async()=>new Response(JSON.stringify({error:{code,message:'private-secret-debug'}}),{status:400})});await assert.rejects(p.locations('token',input),e=>e instanceof MetaAccessError&&!e.message.includes('private-secret'));}
});
test('Location receipts bind all displayed fields, owner, campaign and fingerprint and expire',()=>{
 const row={key:'42',name:'Columbus',country:'US',type:'city',region:'Ohio'},scope={actor:'owner',funnel:'funnel',campaign:'campaign',fingerprint:'a'.repeat(64)},now=Date.now(),proof=metaLocationProof('secret',scope,row,now);
 assert(metaLocationProofValid('secret',scope,row,proof,now));assert(!metaLocationProofValid('secret',scope,row,proof,now+30*60000));assert(!metaLocationProofValid('secret',scope,row,proof,now-1));assert(!metaLocationProofValid('different',scope,row,proof,now));
 for(const k of Object.keys(scope))assert(!metaLocationProofValid('secret',{...scope,[k]:'changed'},row,proof,now));
 for(const k of Object.keys(row))assert(!metaLocationProofValid('secret',scope,{...row,[k]:'changed'},proof,now));
});
