import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerContractRadar} from '../contract_radar/routes.mjs';
import {discoverContracts,reviewContract,officialLink,profileData,importData} from '../contract_radar/ai.mjs';
let db,server,base,owner,other,usage,calls,allowed,providerFails,gate,emptySearch;
const profile={businessName:'Fixture Services',services:'Office cleaning',location:'Ohio',capacity:'Five staff',certifications:'Insurance held',naics:'561720'};
const sourceUrl='https://sam.gov/opp/1234567890abcdef1234567890abcdef/view';
const found={title:'Office cleaning solicitation',agency:'Fixture agency',location:'Ohio',sourceUrl,noticeType:'solicitation',deadline:'2099-10-01',summary:'Provide weekly cleaning. Insurance required.',matchReason:'Cleaning in your service area.',noticeText:'',source:'official_search',discoveredAt:'2026-09-27T00:00:00Z'};
const imported={title:'A private RFP',agency:'Fixture buyer',sourceUrl:'https://example.com/rfp',location:'Ohio',noticeText:'Provide weekly cleaning. Insurance required.',deadline:'2099-10-01'};
const reviewResult={summary:'Check insurance evidence.',fit:'needs_review',reasons:['Services align'],requirements:[{requirement:'Insurance',evidence:'Insurance required.',profileEvidence:'Insurance held',status:'provided'}],risks:[],questions:['What is the square footage?'],nextSteps:['Read amendments'],draft:'DRAFT — VERIFY BEFORE SUBMISSION\n[NEEDS YOUR INPUT: pricing]'};
const rpc=async(action,id=null,data={},actor=owner)=>(await db.query('select public.korlix_radar_v1($1,$2,$3,$4) r',[actor,action,id,data])).rows[0].r;
async function api(path='',body,method=body?'POST':'GET',actor=owner,status=200){const r=await fetch(base+path,{method,headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});const d=await r.json();assert.equal(r.status,status,JSON.stringify(d));assert.equal(r.headers.get('cache-control'),'no-store');return d;}
async function setup(){await api('/profile',profile,'PUT');}
async function save(actor=owner,extra={}){return (await api('/opportunities',{request_key:randomUUID(),...imported,...extra},'POST',actor,201)).opportunity;}
async function start(extra={},status=202){return (await api('/jobs',{request_key:randomUUID(),kind:'discover',query:'',consent:true,...extra},'POST',owner,status)).job;}
async function done(id){for(let i=0;i<200;i++){const r=await api('/jobs/'+id);if(r.job.state!=='running')return r.job;await new Promise(r=>setTimeout(r,5));}throw Error('Job did not finish');}
async function credits(){return (await db.query('select credits_used from usage_counters where id=$1',[usage])).rows[0].credits_used;}
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table public.usage_counters(id uuid primary key,user_id uuid references auth.users,credits_used int default 0,standard_generations int default 0,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant all on usage_counters to service_role;');
 const dir=new URL('../../supabase/migrations/',import.meta.url);const name=(await readdir(dir)).find(n=>n.endsWith('_contract_radar.sql'));await db.exec(await readFile(new URL(name,dir),'utf8'));const upgrade=(await readdir(dir)).find(n=>n.endsWith('_contract_radar_monitoring.sql'));await db.exec(await readFile(new URL(upgrade,dir),'utf8'));
 const database={rpc:async(_name,p)=>{try{return {data:await rpc(p.p_action,p.p_id,p.p_data,p.p_actor)};}catch(error){if(process.env.RADAR_DEBUG)console.error(error.message,error.code,error.where);return {error};}}};
 const app=express();app.use(express.json());registerContractRadar(app,{database,requireUser:async q=>[owner,other].includes(q.headers.authorization)?{id:q.headers.authorization}:null,
  aiAccess:async()=>({allowed,usageId:usage,reason:'Upgrade required'}),logger:{warn(){}},
  discover:async()=>{calls++;if(gate)await gate;if(providerFails)throw Error('offline');return {opportunities:emptySearch?[]:[found],searchedAt:'2026-09-27T00:00:00Z'};},
  review:async(input)=>{calls++;if(gate)await gate;if(providerFails)throw Error('offline');return {...reviewResult,profileUpdatedAt:input.profileUpdatedAt,reviewedProfile:input.profile};},
 });server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port+'/api/contract-radar';
});
test.beforeEach(async()=>{await db.exec('reset role');owner=randomUUID();other=randomUUID();usage=randomUUID();for(const id of [owner,other])await db.query('insert into auth.users values($1)',[id]);await db.query('insert into usage_counters(id,user_id) values($1,$2)',[usage,owner]);await db.exec('set role service_role');calls=0;allowed=true;providerFails=emptySearch=false;gate=null;});
test.after(async()=>{await new Promise(r=>server.close(r));await db.close();});
test('private profiles and opportunities only expose the authenticated account',async()=>{
 await api('',null,'GET','',401);await setup();const o=await save();const own=await api();assert.deepEqual(own.profile.data,profile);assert.equal(own.profile.user_id,undefined);assert.equal(own.opportunities[0].id,o.id);
 const foreign=await api('',null,'GET',other);assert.equal(foreign.profile,null);assert.deepEqual(foreign.opportunities,[]);
 await api('/opportunities/'+o.id,{notes:'attack'},'PATCH',other,404);await api('/opportunities/'+o.id,{confirmed:true},'DELETE',other,404);
});
test('input validation rejects bad URLs, dates, oversized text and forged discovery labels',async()=>{
 assert.throws(()=>importData({...imported,sourceUrl:'javascript:alert(1)'}));assert.throws(()=>importData({...imported,deadline:'2026-02-30'}));assert.throws(()=>profileData({...profile,services:'x'.repeat(2401)}));
 const o=await save(owner,{source:'official_search',matchReason:'guaranteed'});assert.equal(o.data.source,'import');assert.equal(o.data.matchReason,undefined);
 await api('/opportunities',{request_key:randomUUID(),...imported,noticeText:''},'POST',owner,400);
});
test('discovery results save from owned jobs and deduplicate without replacing private notes',async()=>{
 await setup();const j=await start();await done(j.id);
 const saveBody={request_key:randomUUID(),job_id:j.id,index:0};const o=(await api('/opportunities',saveBody,'POST',owner,201)).opportunity;
 assert.equal(o.data.source,'official_search');await api('/opportunities/'+o.id,{notes:'Private note',stage:'preparing'},'PATCH');
 const again=(await api('/opportunities',{...saveBody,request_key:randomUUID()},'POST',owner,201)).opportunity;assert.equal(again.id,o.id);assert.equal(again.notes,'Private note');
 await api('/opportunities',saveBody,'POST',other,404);await api('/opportunities',{...saveBody,index:9},'POST',owner,400);
});
test('replayed jobs charge once and changed inputs do not reuse a request key',async()=>{
 await setup();const key=randomUUID();const j=await start({request_key:key});const d=await done(j.id);assert.equal(d.state,'completed');assert.equal(d.charged,1);assert.equal(await credits(),1);
 await start({request_key:key},200);await start({request_key:key,query:'changed'},409);await rpc('job_finish',key,{result:d.result});assert.equal(calls,1);assert.equal(await credits(),1);assert.equal(d.usage_id,undefined);assert.equal(d.input,undefined);
});
test('parallel requests cannot start a second job and recoverable polling keeps the first',async()=>{
 await setup();let release;gate=new Promise(r=>release=r);const j=await start();await start({},409);await start({request_key:j.id},200);
 assert.equal((await api()).jobs[0].id,j.id);release();assert.equal((await done(j.id)).state,'completed');assert.equal(calls,1);
});
test('missing consent, missing profile, denied access, empty searches and provider failures do not charge',async()=>{
 await start({consent:false},400);await start({},400);await setup();allowed=false;await start({},403);allowed=true;providerFails=true;
 assert.equal((await done((await start()).id)).state,'failed');providerFails=false;emptySearch=true;const d=await done((await start()).id);assert.equal(d.charged,0);assert.equal(await credits(),0);
});
test('reviews require owned records and snapshot the profile used for the result',async()=>{
 await setup();const foreign=await save(other);await start({kind:'review',opportunity_id:foreign.id},404);
 const o=await save();let release;gate=new Promise(r=>release=r);const j=await start({kind:'review',opportunity_id:o.id});
 await api('/profile',{...profile,capacity:'New capacity'},'PUT');await api('/opportunities/'+o.id,{noticeText:'Changed'},'PATCH',owner,409);await api('/opportunities/'+o.id,{confirmed:true},'DELETE',owner,409);
 release();await done(j.id);const saved=(await api()).opportunities[0];assert.equal(saved.review.reviewedProfile.capacity,'Five staff');assert.equal(await credits(),1);
 await api('/opportunities/'+o.id,{noticeText:'Updated complete notice'},'PATCH');assert.deepEqual((await api()).opportunities[0].review,{});
});
test('pipeline updates never submit anything; deletion needs confirmation and removes associated reviews',async()=>{
 await setup();const o=await save();await done((await start({kind:'review',opportunity_id:o.id})).id);
 await api('/opportunities/'+o.id,{stage:'submitted'},'PATCH');assert.equal(calls,1);await api('/opportunities/'+o.id,{},'DELETE',owner,400);
 await api('/opportunities/'+o.id,{confirmed:true},'DELETE');assert.deepEqual((await api()).jobs,[]);assert.deepEqual((await api()).opportunities,[]);
});
test('interrupted jobs become failed without retry or credit usage',async()=>{
 await setup();const id=randomUUID();await rpc('job_begin',id,{kind:'discover',query:'',signature:'fixture',usage_id:usage});
 await db.query("update korlix_radar_jobs set created_at=now()-interval '9 minutes' where id=$1",[id]);const j=(await api('/jobs/'+id)).job;assert.equal(j.state,'failed');assert.equal(await credits(),0);assert.equal(calls,0);
});
test('clear removes only the actor records; revoked grants block direct clients',async()=>{
 await setup();await save();await save(other);await api('',{confirmed:true},'DELETE');assert.equal((await api()).profile,null);assert.equal((await api('',null,'GET',other)).opportunities.length,1);
 await db.exec('reset role;set role authenticated');try{await assert.rejects(db.query('select * from korlix_radar_profiles'),/permission denied/);await assert.rejects(rpc('list'),/permission denied/);}finally{await db.exec('reset role;set role service_role');}
 const r=(await db.query("select relrowsecurity from pg_class where relname in ('korlix_radar_profiles','korlix_radar_opportunities','korlix_radar_jobs')")).rows;assert.equal(r.length,3);assert(r.every(x=>x.relrowsecurity));
});
test('search accepts only retrieved official notice URLs, removes duplicates, expired notices and awards',async()=>{
 const bad='https://sam.gov/opp/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/view';const second='https://sam.gov/opp/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/view';
 const rows=[{...found},{...found},{...found,sourceUrl:bad},{...found,sourceUrl:second,deadline:'2025-01-01'},{...found,sourceUrl:'https://evil.test/opp'},{...found,noticeType:'award'}];let request;
 const client={responses:{create:async(b)=>{request=b;return {status:'completed',output_text:JSON.stringify({opportunities:rows}),output:[{type:'web_search_call',action:{type:'search',sources:[{url:sourceUrl},{url:second}]}}]};}}};
 const r=await discoverContracts({client,profile,now:new Date('2026-09-27T12:00:00Z')});assert.equal(r.opportunities.length,1);assert.equal(r.opportunities[0].source,'official_search');assert.equal(request.model,'gpt-6-astra');assert.equal(request.reasoning.effort,'max');assert.equal(request.store,false);assert.deepEqual(request.tools[0].filters.allowed_domains,['sam.gov','a856-cityrecord.nyc.gov','ogs.ny.gov']);
 assert(!request.input.includes('Fixture Services'));assert(!request.input.includes('Insurance held'));assert(!request.input.includes('Five staff'));
 assert.equal(officialLink(sourceUrl.replace('/opp/','/workspace/contract/opp/')+'?utm_source=test'),sourceUrl);assert.equal(officialLink('https://sam.gov.evil.com/opp/123/view'),null);
});
test('search without real web execution fails rather than supplying ungrounded results',async()=>{
 const client={responses:{create:async()=>({status:'completed',output_text:JSON.stringify({opportunities:[found]})})}};
 await assert.rejects(discoverContracts({client,profile}),/Live source search/);
});
test('review downgrades invented evidence and keeps uncertain credentials unverified',async()=>{
 let request;const client={responses:{create:async(b)=>{request=b;return {status:'completed',output_text:JSON.stringify({...reviewResult,requirements:[...reviewResult.requirements,{requirement:'Made-up bond',evidence:'Bonding required',profileEvidence:'Certified',status:'provided'}]})};}}};
 const r=await reviewContract({client,profile,profileUpdatedAt:'2026-09-27',opportunity:{...imported,summary:'Summary'}});
 assert.equal(r.requirements[0].status,'provided');assert.equal(r.requirements[1].status,'verify');assert.equal(r.requirements[1].evidence,'');assert.equal(r.requirements[1].profileEvidence,'');assert.match(r.draft,/DRAFT/);assert.equal(r.limitedToSummary,false);assert.equal(request.tools,undefined);assert.equal(request.store,false);
});
