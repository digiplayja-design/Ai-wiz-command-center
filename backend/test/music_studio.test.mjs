import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerMusicStudio} from '../music/routes.mjs';
import {MusicError,settings,providerPayload,providerResult,entitlement,createProvider,downloadAudio,publicJob} from '../music/core.mjs';
let db,server,base,owner,other,creates,result,createError,active,providerReady,limit,createWait;const runtimes=[];
const idea=()=>settings({mode:'idea',idea:'A warm reggae song about a fresh start',style:'reggae, hopeful',title:'Fresh start'});
const rpc=async(actor,action,id=null,data={})=>(await db.query('select public.korlix_music_v2($1,$2,$3,$4) r',[actor,action,id,data])).rows[0].r;
const provider={ready:()=>providerReady,create:async()=>{creates++;if(createError)throw createError;if(createWait)await createWait;return randomUUID();},status:async()=>result};
const database={rpc:async(_name,p)=>{try{return {data:await rpc(p.p_actor,p.p_action,p.p_id,p.p_data)};}catch(error){if(process.env.MUSIC_DEBUG)console.error(error.message,error.where);return {error};}}};
function app(){const a=express();a.use(express.json());const runtime=registerMusicStudio(a,{database,requireUser:async q=>[owner,other].includes(q.headers.authorization)?{id:q.headers.authorization,email:'owner@example.test'}:null,provider,access:()=>({active,plan:active?{id:'fixture',monthlyGenerations:limit}:null,plans:[]}),fetchAudio:async()=>({bytes:Buffer.from('ID3fixture'),extension:'mp3',mime:'audio/mpeg'}),logger:{warn(){}}});runtimes.push(runtime);return a;}
async function api(path,body,method=body?'POST':'GET',actor=owner,expected=200,headers={}){
 const r=await fetch(base+path,{method,headers:{Authorization:actor,'Content-Type':'application/json',...headers},...(body?{body:JSON.stringify(body)}:{})});
 const d=await r.json();assert(Array.isArray(expected)?expected.includes(r.status):r.status===expected,JSON.stringify({status:r.status,expected,data:d}));if(path!='/webhook')assert.equal(r.headers.get('cache-control'),'no-store');return d;
}
const settle=async()=>{for(let i=0;i<100&&runtimes.some(r=>r.active.size);i++)await new Promise(r=>setTimeout(r,5));};
const start=async(extra={},expected=202)=>{const r=await api('/generate',{...idea(),request_key:randomUUID(),consent:true,...extra},'POST',owner,expected);await settle();if(r.job){r.job=publicJob(await rpc(owner,'get',r.job.id));r.addon=await api('/addon');}return r;};
const makeReady=async id=>rpc(owner,'result',id,providerResult({data:[{clip_id:'a',state:'succeeded',audio_url:'https://cdn1.suno.ai/song.mp3',title:'Saved music'}]}));
test.before(async()=>{db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);grant usage on schema public to anon,authenticated,service_role;');const dir=new URL('../../supabase/migrations/',import.meta.url);const file=(await readdir(dir)).find(f=>f.endsWith('_music_studio_library.sql'));await db.exec(await readFile(new URL(file,dir),'utf8'));server=app().listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port+'/api/music';});
test.beforeEach(async()=>{await db.exec('reset role');owner=randomUUID();other=randomUUID();for(const id of [owner,other])await db.query('insert into auth.users values($1)',[id]);await db.exec('set role service_role');creates=0;createError=null;createWait=null;active=true;providerReady=true;limit=75;result=providerResult({data:[{clip_id:'a',state:'running',audio_url:'https://cdn1.suno.ai/preview'}]});});
test.after(async()=>{server?.closeAllConnections();await new Promise(r=>server.close(r));await db.close();});
test('every private route verifies a real user and ignores spoofed identity headers',async()=>{
 for(const [path,method,body]of[['/addon','GET'],['/studio','GET'],['/jobs','GET'],['/generate','POST',{...idea(),request_key:randomUUID(),consent:true}],['/status/'+randomUUID(),'GET'],['/draft','PUT',{version:0,request_key:randomUUID(),data:idea()}],['/content/old','GET']])await api(path,body,method,'fake-token',401,{'x-korlix-user-email':'owner@example.test'});
 assert.equal(creates,0);assert.equal(entitlement({id:owner,email:'other@example.test'},{KORLIX_MUSIC_ADDON_ALLOWLIST:'owner@example.test'}).active,false);
 assert.equal(entitlement({id:owner,email:'Owner@Example.Test'},{KORLIX_MUSIC_ADDON_ALLOWLIST:'owner@example.test'}).active,true);
});
test('create reserves durably, acceptance uses one allowance, retries recover one job',async()=>{
 const key=randomUUID();const a=await start({request_key:key}),b=await start({request_key:key},200);
 assert.equal(a.job.id,key);assert.equal(b.job.id,key);assert.equal(creates,1);assert.equal(a.addon.usage.usedThisCycle,1);assert.equal(a.addon.usage.reservedThisCycle,0);assert.equal((await api('/studio')).jobs.length,1);
 await start({request_key:key,idea:'Changed idea'},409);assert.equal(creates,1);
});
test('concurrent duplicate requests make a single provider call',async()=>{
 const key=randomUUID();const rows=await Promise.all([start({request_key:key}),api('/generate',{...idea(),request_key:key,consent:true},'POST',owner,[200,202])]);
 assert(rows.every(r=>r.job.id===key));assert.equal(creates,1);
});
test('quota reservations prevent concurrent overuse and removal never restores used allowance',async()=>{
 limit=1;const a=await start();await start({},429);assert.equal(creates,1);await makeReady(a.job.id);await api('/jobs/'+a.job.id,{confirmed:true},'DELETE');assert.equal((await api('/jobs')).jobs.length,0);assert.equal((await api('/addon')).usage.usedThisCycle,1);await start({},429);
});
test('inactive and unconfigured generation do not submit or reserve; matching retries still recover',async()=>{
 const key=randomUUID();await start({request_key:key});active=false;await start({request_key:key},200);await start({},403);active=true;providerReady=false;await start({},503);assert.equal(creates,1);assert.equal((await rpc(owner,'usage')).allocated,1);
});
test('AI sharing is required before a provider request',async()=>{await start({consent:false},400);assert.equal(creates,0);assert.equal((await rpc(owner,'usage')).allocated,0);});
test('definite rejection releases a reservation; uncertain outcome stays held without resubmission',async()=>{
 createError=Object.assign(new MusicError('Rejected'),{definite:true});const a=await start();assert.equal(a.job.status,'failed');assert.equal(a.addon.usage.allocated,0);
 createError=Object.assign(new MusicError('Timeout'),{definite:false});const key=randomUUID(),b=await start({request_key:key});assert.equal(b.job.status,'uncertain');assert.equal(b.addon.usage.reservedThisCycle,1);await start({request_key:key},200);assert.equal(creates,2);await api('/jobs/'+b.job.id,{confirmed:true},'DELETE',owner,400);
});
test('restart-interrupted submission is marked uncertain and cannot be submitted again',async()=>{
 const key=randomUUID();await rpc(owner,'begin',key,{payload:idea(),limit:75});await db.query("update korlix_music_jobs set created_at=now()-interval '3 minutes' where id=$1",[key]);
 assert.equal((await api('/status/'+key)).job.status,'uncertain');await start({request_key:key},200);assert.equal(creates,0);assert.equal((await rpc(owner,'usage')).allocated,1);
});
test('library and status reject every foreign owner access',async()=>{
 const a=await start();assert.equal((await api('/jobs',undefined,'GET',other)).jobs.length,0);
 await api('/status/'+a.job.id,undefined,'GET',other,404);await api('/jobs/'+a.job.id+'/favorite',{favorite:true},'PUT',other,404);await api('/jobs/'+a.job.id,{confirmed:true},'DELETE',other,404);
 await api('/jobs/'+a.job.id+'/tracks/0/file',undefined,'GET',other,404);await api('/jobs?before='+a.job.id,undefined,'GET',other,404);
});
test('status waits for succeeded audio, rate limits polling, and preserves partial success',async()=>{
 const a=await start();let r=await api('/status/'+a.job.id);assert.equal(r.status,'processing');assert.equal(r.tracks[0].audioUrl,null);
 result=providerResult({code:200,data:[{clip_id:'a',state:'succeeded',audio_url:'https://cdn1.suno.ai/a.mp3'},{clip_id:'b',state:'running'}]});
 assert.equal((await api('/status/'+a.job.id)).status,'processing');await db.query("update korlix_music_jobs set polled_at=now()-interval '30 seconds' where id=$1",[a.job.id]);
 r=await api('/status/'+a.job.id);assert.equal(r.status,'processing');assert(r.tracks[0].audioUrl);
 result=providerResult({data:[{clip_id:'a',state:'succeeded',audio_url:'https://cdn1.suno.ai/a.mp3'},{clip_id:'b',state:'failed'}]});await db.query("update korlix_music_jobs set polled_at=now()-interval '30 seconds' where id=$1",[a.job.id]);
 assert.equal((await api('/status/'+a.job.id)).status,'partial');
});
test('favorites and search persist; paging is scoped and stable',async()=>{
 for(let i=0;i<34;i++){const id=randomUUID();await rpc(owner,'begin',id,{payload:{...idea(),title:i===33?'Needle song':'Song '+i},limit:100});await rpc(owner,'submission_error',id,{definite:true,error:'Fixture'});}
 const p=await api('/jobs');assert.equal(p.jobs.length,30);assert.equal(p.hasMore,true);
 const q=await api('/jobs?before='+p.nextBefore);assert.equal(q.jobs.length,4);assert(!q.jobs.some(j=>p.jobs.some(k=>k.id===j.id)));
 const found=await api('/jobs?query=needle');assert.equal(found.jobs.length,1);await api('/jobs/'+found.jobs[0].id+'/favorite',{favorite:true},'PUT');
 assert.equal((await api('/jobs?favorites=true')).jobs[0].id,found.jobs[0].id);
});
test('draft saves support optimistic versions, stable retries and owner isolation',async()=>{
 const key=randomUUID(),body={version:0,request_key:key,data:idea()};const a=await api('/draft',body,'PUT'),b=await api('/draft',body,'PUT');assert.equal(a.draft.version,1);assert.equal(b.draft.version,1);
 await api('/draft',{...body,data:{...idea(),idea:'Changed'}},'PUT',owner,409);
 await api('/draft',{...body,request_key:randomUUID()},'PUT',owner,409);
 assert.equal((await api('/draft',undefined,'GET',other)).draft.version,0);
 const c=await api('/draft',{version:1,request_key:randomUUID(),data:settings({mode:'lyrics',lyrics:'',style:''},{draft:true})},'PUT');assert.equal(c.draft.version,2);
});
test('library survives route recreation and usage does not depend on process maps',async()=>{
 const a=await start();const second=app().listen(0,'127.0.0.1');await new Promise(r=>second.once('listening',r));
 try{const r=await fetch('http://127.0.0.1:'+second.address().port+'/api/music/studio',{headers:{Authorization:owner}});const d=await r.json();assert.equal(d.jobs[0].id,a.job.id);assert.equal(d.addon.usage.usedThisCycle,1);}finally{second.closeAllConnections();await new Promise(r=>second.close(r));}
});
test('confirmed removal erases recipe and links but retains minimal usage receipt',async()=>{
 const a=await start();await api('/jobs/'+a.job.id,{confirmed:true},'DELETE',owner,400);await makeReady(a.job.id);await api('/jobs/'+a.job.id,{confirmed:false},'DELETE',owner,400);await api('/jobs/'+a.job.id,{confirmed:true},'DELETE');
 const j=(await db.query('select * from korlix_music_jobs where id=$1',[a.job.id])).rows[0];assert.equal(j.hidden,true);assert.deepEqual(j.payload,{});assert.deepEqual(j.tracks,[]);assert.equal(j.task_id,null);assert.equal(j.accepted,true);
});
test('untrusted callback cannot mark a job complete or overwrite audio',async()=>{
 const a=await start();await api('/webhook',{task_id:a.job.id,data:[{audio_url:'https://evil.test/audio'}]},'POST','',410);assert.equal((await rpc(owner,'get',a.job.id)).state,'submitted');
});
test('instrumental uses provider boolean and correct descriptions; lyrics and length are explicit',()=>{
 const p=providerPayload(settings({mode:'instrumental',idea:'Quiet piano',style:'ambient',voice:'f',lyrics:'Do not sing',duration:30}));assert.equal(p.make_instrumental,true);assert.equal(p.vocal_gender,undefined);assert.equal(p.prompt,undefined);assert.equal(p.duration,30);
 const c=providerPayload(settings({mode:'lyrics',lyrics:'[Verse]\nOriginal words',title:'Ours',style:'reggae',voice:'m'}));assert.equal(c.custom_mode,true);assert.equal(c.prompt,'[Verse]\nOriginal words');assert.equal(c.vocal_gender,'m');
 for(const v of [{mode:'idea',idea:'x'.repeat(400),style:'pop'},{mode:'lyrics',lyrics:'x'.repeat(5001)},{mode:'idea',idea:'Good',duration:361}])assert.throws(()=>settings(v));
});
test('provider responses expose playable HTTPS audio only after authoritative completion',()=>{
 assert.equal(providerResult({code:200,data:[{state:'running',audio_url:'https://cdn1.suno.ai/a'}]}).state,'processing');
 assert.equal(providerResult({data:[{state:'succeeded',audio_url:'javascript:alert(1)'}]}).state,'processing');
 assert.equal(providerResult({data:[{state:'succeeded',audio_url:'https://cdn1.suno.ai/a.mp3'}]}).state,'completed');
 assert.equal(providerResult({data:[{state:'failed'}]}).state,'failed');
});
test('provider client uses pinned existing integration, timeouts and non-retried creation',async()=>{
 const calls=[];const p=createProvider({env:{MUSICAPI_KEY:'fixture'},fetcher:async(url,options)=>{calls.push({url,options});return new Response(JSON.stringify({code:200,task_id:'task'}),{status:200});}});
 assert.equal(await p.create(idea()),'task');assert.equal(calls.length,1);assert.equal(JSON.parse(calls[0].options.body).mv,'sonic-v5');assert(calls[0].options.signal);
 const failed=createProvider({env:{MUSICAPI_KEY:'fixture'},fetcher:async()=>new Response('{"code":400}',{status:400})});await assert.rejects(()=>failed.create(idea()),e=>e.definite===true);
 const unknown=createProvider({env:{MUSICAPI_KEY:'fixture'},fetcher:async()=>{throw Error('timeout');}});await assert.rejects(()=>unknown.create(idea()),e=>e.definite===false);
});
test('audio downloads allow only verified CDN hosts, safe redirects and recognized bounded audio',async()=>{
 const bytes=Buffer.from('ID3fixture');const f=await downloadAudio('https://cdn1.suno.ai/song.mp3',async()=>new Response(bytes,{headers:{'content-type':'audio/mpeg'}}));assert.equal(f.extension,'mp3');
 await assert.rejects(()=>downloadAudio('http://127.0.0.1/a'),/Open audio/);
 await assert.rejects(()=>downloadAudio('https://cdn1.suno.ai/a',async()=>new Response('',{status:302,headers:{location:'https://localhost/private'}})),/Open audio/);
 await assert.rejects(()=>downloadAudio('https://cdn1.suno.ai/a',async()=>new Response('<html>error</html>')),/not recognized/);
 await assert.rejects(()=>downloadAudio('https://cdn1.suno.ai/a',async()=>new Response(bytes,{headers:{'content-length':String(65*1024*1024)}})),/large file/);
});
test('database RLS and grants deny direct client access, including trusted functions',async()=>{
 await db.exec('reset role');const rows=await db.query("select relrowsecurity from pg_class where relname in ('korlix_music_jobs','korlix_music_drafts')");assert.equal(rows.rows.length,2);assert(rows.rows.every(r=>r.relrowsecurity));
 await db.exec('set role authenticated');await assert.rejects(()=>rpc(owner,'list'),/permission denied/);await assert.rejects(()=>db.query('select * from korlix_music_jobs'),/permission denied/);
});


test('creation is acknowledged durably before the provider accepts, without blocking the interface',async()=>{
 let release;createWait=new Promise(r=>release=r);const key=randomUUID();
 try{const r=await api('/generate',{...idea(),request_key:key,consent:true},'POST',owner,202);assert.equal(r.job.status,'submitting');assert.equal(r.addon.usage.reservedThisCycle,1);assert.equal((await api('/jobs')).jobs[0].id,key);assert.equal(creates,1);}finally{release();await settle();}
 assert.equal((await rpc(owner,'get',key)).state,'submitted');assert.equal((await rpc(owner,'usage')).usedThisCycle,1);
});
