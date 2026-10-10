import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerAiVisibility} from '../ai_visibility/routes.mjs';
import {profileData,publicUrl,nameMatch,fingerprint,sampleAnswer,websiteReview,scanVisibility} from '../ai_visibility/ai.mjs';
let db,server,base,owner,other,usage,allowed,calls,providerFails,gate;
const profile=profileData({businessName:'Bright Pine',website:'brightpine.example.com',services:'office cleaning',market:'Columbus',facts:'We offer evening cleaning.'});
const result={business:{businessName:profile.businessName,website:profile.website},fingerprint:fingerprint(profile),method:'openai_web_samples_v1',sampleCount:3,nameMatches:1,siteCitations:1,summary:'Limited samples.',samples:[{question:'sample',answer:'answer'}],actions:[{id:'action-0',title:'Clarify services'}],drafts:[{type:'faq',body:'Draft'}]};
const rpc=async(action,id=null,data={},actor=owner)=>(await db.query('select public.korlix_visibility_v1($1,$2,$3,$4) r',[actor,action,id,data])).rows[0].r;
async function api(path='',body,method=body?'POST':'GET',actor=owner,status=200){const r=await fetch(base+path,{method,headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});const d=await r.json();assert.equal(r.status,status,JSON.stringify(d));assert.equal(r.headers.get('cache-control'),'no-store');return d;}
async function setup(){await api('/profile',profile,'PUT');}
async function start(extra={},status=202,actor=owner){return (await api('/runs',{request_key:randomUUID(),consent:true,...extra},'POST',actor,status)).run;}
async function done(id){for(let i=0;i<200;i++){const r=await api('/runs/'+id);if(r.run.state!=='running')return r.run;await new Promise(r=>setTimeout(r,5));}throw Error('Scan did not finish');}
async function credits(){return (await db.query('select credits_used from usage_counters where id=$1',[usage])).rows[0].credits_used;}
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table public.usage_counters(id uuid primary key,user_id uuid,credits_used integer default 0,standard_generations integer default 0,updated_at timestamptz default now());grant all on public.usage_counters to service_role;');
 const dir=new URL('../../supabase/migrations/',import.meta.url),files=await readdir(dir);await db.exec(await readFile(new URL(files.find(x=>x.endsWith('_ai_visibility.sql')),dir),'utf8'));
 const database={rpc:async(_name,p)=>{try{return {data:await rpc(p.p_action,p.p_id,p.p_data,p.p_actor)};}catch(error){if(process.env.VISIBILITY_DEBUG)console.error(error.message,error.code);return {error};}}};
 const app=express();app.use(express.json());registerAiVisibility(app,{database,requireUser:async q=>[owner,other].includes(q.headers.authorization)?{id:q.headers.authorization}:null,aiAccess:async()=>({allowed,usageId:usage,reason:'Upgrade required'}),logger:{warn(){}},scan:async input=>{calls++;await input.onPhase('Preparing report');if(gate)await gate;if(providerFails)throw Error('offline');return {...result,profileSnapshot:input.profile};}});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port+'/api/ai-visibility';
});
test.beforeEach(async()=>{await db.exec('reset role');owner=randomUUID();other=randomUUID();usage=randomUUID();for(const id of [owner,other])await db.query('insert into auth.users values($1)',[id]);await db.query('insert into usage_counters(id,user_id) values($1,$2)',[usage,owner]);await db.exec('set role service_role');allowed=true;calls=0;providerFails=false;gate=null;});
test.after(async()=>{await new Promise(r=>server.close(r));await db.close();});
test('profile save confirms persisted private setup and owner is never caller-controlled',async()=>{
 await api('',null,'GET','',401);await api('/profile',{...profile,user_id:other},'PUT');const own=await api();assert.deepEqual(own.profile.data,profile);assert.equal(own.profile.user_id,undefined);assert.equal((await api('',null,'GET',other)).profile,null);
});
test('job replay is once-only, credits are atomic, and list omits full report bodies',async()=>{
 await setup();const key=randomUUID();const j=await start({request_key:key});await done(j.id);await start({request_key:key},200);await rpc('run_finish',key,{result});assert.equal(calls,1);assert.equal(await credits(),3);
 const list=await api();assert.equal(list.runs[0].input,undefined);assert.equal(list.runs[0].usage_id,undefined);assert.equal(list.runs[0].result.samples,undefined);assert.equal((await api('/runs/'+key)).run.result.samples.length,1);
 await api('/runs/'+key,null,'GET',other,404);await api('/runs/'+key,{confirmed:true},'DELETE',other,404);
});
test('consent, setup, entitlement and failed generation never consume credits',async()=>{
 await start({consent:false},400);await start({},400);await setup();allowed=false;await start({},403);allowed=true;providerFails=true;assert.equal((await done((await start()).id)).state,'failed');assert.equal(await credits(),0);
});
test('concurrent starts are blocked and the saved profile snapshot survives edits',async()=>{
 await setup();let release;gate=new Promise(r=>release=r);const j=await start();await start({},409);await start({request_key:j.id},200);await api('/profile',{...profile,facts:'Changed later'},'PUT');
 await api('',{confirmed:true},'DELETE',owner,409);await api('/runs/'+j.id,{confirmed:true},'DELETE',owner,409);
 assert.equal((await api()).runs[0].state,'running');release();const r=await done(j.id);assert.equal(r.result.profileSnapshot.facts,profile.facts);assert.equal(calls,1);
});
test('interrupted scans are failed after twelve minutes without retry or charging',async()=>{
 await setup();const id=randomUUID();await rpc('run_begin',id,{usage_id:usage});await db.query("update korlix_visibility_runs set created_at=now()-interval '13 minutes' where id=$1",[id]);assert.equal((await api('/runs/'+id)).run.state,'failed');assert.equal(await credits(),0);assert.equal(calls,0);
});
test('progress is report-owned, bounded and never alters measured sample counts',async()=>{
 await setup();const id=(await start()).id;await done(id);const progress={completedActions:['action-0'],inquiries:4,bookings:1,notes:'Owner observations',nameMatches:3};const r=(await api('/runs/'+id,progress,'PATCH')).run;assert.equal(r.result.nameMatches,1);assert.equal(r.progress.inquiries,4);assert.equal(r.progress.nameMatches,undefined);
 await api('/runs/'+id,progress,'PATCH',other,404);await api('/runs/'+id,{...progress,completedActions:['fake']},'PATCH',owner,400);await api('/runs/'+id,{...progress,inquiries:-1},'PATCH',owner,400);
});
test('clear and removal require confirmation and affect only the owner; direct database access is denied',async()=>{
 await setup();await api('/profile',profile,'PUT',other);const id=(await start()).id;await done(id);await api('/runs/'+id,{},'DELETE',owner,400);await api('/runs/'+id,{confirmed:true},'DELETE');assert.equal((await api()).runs.length,0);await api('',{confirmed:true},'DELETE');assert.equal((await api()).profile,null);assert((await api('',null,'GET',other)).profile);
 await db.exec('reset role;set role authenticated');try{await assert.rejects(db.query('select * from korlix_visibility_profiles'),/permission denied/);await assert.rejects(rpc('list'),/permission denied/);}finally{await db.exec('reset role;set role service_role');}
 const rows=(await db.query("select relrowsecurity from pg_class where relname in ('korlix_visibility_profiles','korlix_visibility_runs')")).rows;assert.equal(rows.length,2);assert(rows.every(x=>x.relrowsecurity));
});
test('hourly start cap includes failed attempts',async()=>{await setup();providerFails=true;for(let i=0;i<6;i++)await done((await start()).id);await start({},429);assert.equal(calls,6);assert.equal(await credits(),0);});
test('public website validation and unbranded question requirements',()=>{
 assert.equal(profile.website,'https://brightpine.example.com/');for(const url of ['http://example.com','https://127.0.0.1','https://[::1]','https://user:secret@example.com','https://host.local','https://example.com:8443'])assert.throws(()=>publicUrl(url));
 assert.throws(()=>profileData({...profile,questions:['Bright Pine in Columbus?',...profile.questions.slice(1)]}),/unbranded/);assert.throws(()=>profileData({...profile,questions:[profile.questions[0],profile.questions[0],profile.questions[2]]}),/different/);assert.equal(nameMatch('CLEARWATER cleaners','clear'),false);assert.equal(nameMatch('Try BRIGHT  PINE today.','Bright Pine'),true);
 assert.notEqual(fingerprint(profile),fingerprint({...profile,questions:[...profile.questions.slice(0,2),'Different question']}));assert.equal(fingerprint(profile),fingerprint({...profile,facts:'New owner details'}));
});
function searchResponse(answer,urls,inline=urls){return {status:'completed',output_text:answer,output:[{type:'web_search_call',action:{type:'search',sources:urls.map(url=>({url}))}},{type:'message',content:[{type:'output_text',text:answer,annotations:inline.map(url=>({type:'url_citation',url,title:'Source'}))}]}]};}
test('sample requests exclude the target brand and distinguish cited from retrieved websites',async()=>{
 let req;const client={responses:{create:async r=>{req=r;return searchResponse('Consider Bright Pine and others.',['https://brightpine.example.com/','https://other.example.com/'],['https://other.example.com/']);}}};
 const r=await sampleAnswer({client,question:profile.questions[0],businessName:profile.businessName,website:profile.website});assert.equal(r.nameMatched,true);assert.equal(r.siteCited,false);assert(!JSON.stringify(req).includes('Bright Pine'));assert(!JSON.stringify(req).includes('brightpine.example.com'));assert.equal(req.store,false);assert.equal(req.model,'gpt-6-astra');assert.equal(req.reasoning.effort,'max');assert.equal(req.previous_response_id,undefined);
 const evil={responses:{create:async()=>searchResponse('Other options',['https://brightpine.example.com.evil.com/'])}};assert.equal((await sampleAnswer({client:evil,question:'Which cleaners?',businessName:profile.businessName,website:profile.website})).siteCited,false);
});
test('samples without actual retrieval fail instead of claiming zero visibility',async()=>{
 for(const response of [{status:'completed',output_text:'Nothing found',output:[]},searchResponse('Nothing found',[])])await assert.rejects(sampleAnswer({client:{responses:{create:async()=>response}},question:'Which cleaners?',businessName:profile.businessName,website:profile.website}),/web sources/);
});
const plan={summary:'Search-based summary',observations:[{topic:'Services',observation:'Cleaning is described.',sourceUrl:'https://brightpine.example.com/services'},{topic:'Invented',observation:'Unsupported',sourceUrl:'https://brightpine.example.com/not-retrieved'}],actions:[{title:'Clarify service area',why:'Help readers',how:'Add accurate areas.',priority:'high',sourceUrl:'https://evil.example.com/'}],drafts:['service_page','product_description','faq'].map(type=>({type,title:type,body:'[ADD VERIFIED DETAIL: service facts]',sourceUrls:['https://brightpine.example.com/services','https://evil.example.com/']}))};
test('website report retains only actually retrieved own-site links and preserves placeholders',async()=>{
 const client={responses:{create:async()=>searchResponse(JSON.stringify(plan),['https://brightpine.example.com/services'])}};const r=await websiteReview({client,profile,samples:[]});assert.equal(r.observations.length,1);assert.equal(r.actions[0].sourceUrl,'');assert.equal(r.websiteObserved,true);assert.deepEqual(r.drafts[0].sourceUrls,['https://brightpine.example.com/services']);assert.match(r.drafts[0].body,/DRAFT — REVIEW/);assert.match(r.drafts[0].body,/ADD VERIFIED DETAIL/);
 const noSources={responses:{create:async()=>searchResponse(JSON.stringify(plan),[])}};const empty=await websiteReview({client:noSources,profile,samples:[]});assert.equal(empty.websiteObserved,false);assert.equal(empty.observations.length,0);assert.match(empty.summary,/could not be assessed/);
});
test('scan aggregates observed samples itself and reports a fixed measurement method',async()=>{
 let n=0,phase='';const client={responses:{create:async r=>r.text?searchResponse(JSON.stringify(plan),['https://brightpine.example.com/services']):searchResponse(++n===1?'Bright Pine':'Other businesses',['https://other.example.com/'])}};
 const r=await scanVisibility({client,profile,onPhase:async p=>phase=p});assert.equal(r.sampleCount,3);assert.equal(r.nameMatches,1);assert.equal(r.siteCitations,0);assert.equal(r.fingerprint,fingerprint(profile));assert.equal(r.method,'openai_web_samples_v1');assert(phase.includes('website'));assert.match(r.limits,/not measure consumer ChatGPT/);
});
