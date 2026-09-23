import test from 'node:test';
import assert from 'node:assert/strict';
import {createMetaProvider} from '../funnels/meta.mjs';
import {MetaPageAccessError} from '../funnels/meta_pages.mjs';
const cfg={apiVersion:'v26.0',secret:'mock-secret-no-real-credential'};
const permission={data:[{permission:'pages_show_list',status:'granted'}]};
const page={id:'12345678901234567890',name:'Page identity',category:'Education'};
const json=(data,status=200)=>new Response(JSON.stringify(data),{status});
function provider(responses,calls=[]) {return createMetaProvider(cfg,{fetchImpl:async(url,options)=>{calls.push({url,options});const r=responses.shift();return r instanceof Response?r:json(r);}});}
test('Page adapter reads explicit identity fields, checks permission, and keeps paging on the fixed host',async()=>{
 const calls=[],p=provider([permission,{data:[{...page,access_token:'must-not-escape',extra:'ignored'}],paging:{next:'https://evil.example/token',cursors:{after:'opaque'}}},{data:[]}],calls);
 assert.deepEqual(await p.pages('fixture-user-token'),[page]);assert.equal(calls.length,3);
 assert.equal(calls[0].url.pathname,'/v26.0/me/permissions');assert.equal(calls[1].url.pathname,'/v26.0/me/accounts');assert.equal(calls[1].url.searchParams.get('fields'),'id,name,category');assert.equal(calls[2].url.searchParams.get('after'),'opaque');
 for(const {url,options} of calls){assert.equal(url.hostname,'graph.facebook.com');assert.equal(options.redirect,'error');assert.equal(options.headers.Authorization,'Bearer fixture-user-token');assert(url.searchParams.get('appsecret_proof'));assert(!url.searchParams.has('access_token'));}
});
test('Missing Page scope stops discovery and provider permission errors are redacted',async()=>{
 for(const data of [[],[{permission:'ads_read',status:'granted'}],[{permission:'pages_show_list',status:'declined'}]]){const calls=[];await assert.rejects(provider([{data}],calls).pages('t'),MetaPageAccessError);assert.equal(calls.length,1);}
 for(const code of [10,200,283])await assert.rejects(provider([permission,json({error:{code,message:'sensitive-token'}},403)]).pages('t'),e=>e instanceof MetaPageAccessError&&!e.message.includes('sensitive'));
 await assert.rejects(provider([json({error:{code:190,message:'private-token'}},401)]).pages('t'),e=>e.message.includes('Reconnect')&&!e.message.includes('private-token'));
});
test('Page adapter rejects duplicate IDs, bad metadata, oversized rows and malformed permissions',async()=>{
 for(const data of [[page,page],[{...page,id:12}],[{...page,name:''}],[{...page,name:'a'.repeat(201)}],[{...page,category:{}}],Array(101).fill(page),{}])await assert.rejects(provider([permission,{data}]).pages('t'));
 for(const r of [{data:[{permission:'pages_show_list',status:'unknown'}]},{data:[] ,paging:{next:'unexpected'}},{data:Array(101).fill(permission.data[0])}])await assert.rejects(provider([r]).pages('t'));
 assert.deepEqual(await provider([permission,{data:[]}]).pages('t'),[]);
});
test('Page adapter accepts 500 complete rows and refuses excess pages or cursor cycles',async()=>{
 const pages=Array.from({length:5},(_,i)=>({data:Array.from({length:100},(_,j)=>({...page,id:String(i*100+j+1)})),...(i<4?{paging:{next:'ignored',cursors:{after:String(i+1)}}}:{})}));
 assert.equal((await provider([permission,...pages]).pages('t')).length,500);
 await assert.rejects(provider([permission,...pages.map((p,i)=>({...p,paging:{next:'ignored',cursors:{after:String(i+1)}}}))]).pages('t'),/More than 500/);
 for(const after of ['', 'a'.repeat(4001)])await assert.rejects(provider([permission,{data:[],paging:{next:'ignored',cursors:{after}}}]).pages('t'),/pagination/);
 await assert.rejects(provider([permission,...Array(2).fill({data:[],paging:{next:'ignored',cursors:{after:'same'}}})]).pages('t'),/pagination/);
});
test('Page adapter bounds streamed bytes and rejects unreadable provider responses',async()=>{
 for(const response of [new Response('x'.repeat(1024*1024+1)),new Response('invalid'),json(null),json([]),json({error:{code:2,message:'raw-private-error'}},503)])await assert.rejects(provider([response]).pages('t'),e=>!e.message.includes('raw-private-error'));
 const p=createMetaProvider(cfg,{fetchImpl:async()=>{throw Error('secret-network-data');}});await assert.rejects(p.pages('t'),e=>!e.message.includes('secret-network-data'));
});

test('Page refresh and selection share a ten-request owner limit in real middleware',async()=>{
 const [{default:express},{registerFunnels},{randomUUID},{tokenCipher,metaConfiguration}]=await Promise.all([import('express'),import('../funnels/routes.mjs'),import('node:crypto'),import('../funnels/meta.mjs')]);
 const env={KORLIX_META_ENABLED:'true',KORLIX_META_APP_ID:'1234567',KORLIX_META_APP_SECRET:'mock-app-secret-no-real-credential',KORLIX_META_LOGIN_CONFIG_ID:'7654321',KORLIX_META_TOKEN_KEY:Buffer.alloc(32,7).toString('base64'),KORLIX_META_REDIRECT_URI:'https://example.com/api/funnels/meta/callback'};
 const owner=randomUUID(),binding=randomUUID(),config=metaConfiguration(env);let reads=0;
 let c={version:1,binding_id:binding,config_hash:config.hash,expires_at:new Date(Date.now()+86400000).toISOString(),needs_reconnect:false,accounts:[{id:'act_123'}],selected_account:'act_123',sealed:tokenCipher(config.key).seal('fake-token',`korlix-meta:${owner}:${binding}`)};
 const store={command:async(_u,action,data)=>{if(action==='secret')return c;if(action==='status')return{connection:{version:c.version,pages:c.pages||[]}};if(action==='pages'){c={...c,pages:data.pages,version:c.version+1};return{};}throw Error('unexpected action');}};
 const app=express();app.use(express.json());registerFunnels(app,{requireUser:async q=>q.headers.authorization?{id:owner}:null,metaStore:store,metaProvider:{pages:async()=>{reads++;return[page];}},environment:env,autoStartScheduler:false});
 const server=app.listen(0);await new Promise(r=>server.once('listening',r));const base='http://127.0.0.1:'+server.address().port+'/api/funnels/meta';
 try{
  for(const path of ['/pages','/select-page','/clear-page'])assert.equal((await fetch(base+path,{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})).status,401);
  for(let i=0;i<11;i++){
   const select=i%2===1;const r=await fetch(base+(select?'/select-page':'/pages'),{method:'POST',headers:{'Content-Type':'application/json',Authorization:owner},body:JSON.stringify({version:c.version,account_id:'act_123',...(select?{page_id:page.id}:{})})});
   assert.equal(r.status,i<10?200:429);assert.equal(r.headers.get('cache-control'),'no-store');
  }
  assert.equal(reads,10);
 }finally{server.closeAllConnections();await new Promise(r=>server.close(r));}
});
