import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {PDFDocument,StandardFonts} from 'pdf-lib';
import {registerContractRadar} from '../contract_radar/routes.mjs';
import {createSamAdapter,normalizeSam,samFilters} from '../contract_radar/sam.mjs';
import {noticeLink,GEOGRAPHIES} from '../contract_radar/sources.mjs';
import {extractRfpPdf,PDF_LIMIT} from '../contract_radar/pdf.mjs';
let db,server,base,owner,other,monitor,calls,ready,feedFails,aiCalls;
const noticeId='1234567890abcdef1234567890abcdef';
const nextDay=(n=1)=>new Date(Date.now()+n*86400000).toISOString().slice(0,10);
const raw=(extra={})=>({noticeId,title:'Office cleaning',type:'Solicitation',active:'Yes',fullParentPathName:'Fixture agency',responseDeadLine:nextDay(),postedDate:nextDay(-1),naicsCode:'561720',solicitationNumber:'FIXTURE',placeOfPerformance:{state:{code:'OH'}},...extra});
const notice=()=>normalizeSam(raw());
const rpc=async(name,actor,action,id=null,data={})=>(await db.query(`select public.${name}($1,$2,$3,$4) r`,[actor,action,id,data])).rows[0].r;
const call=(action,id=null,data={},actor=owner)=>rpc('korlix_radar_monitor_v1',actor,action,id,data);
async function api(path,body,method=body?'POST':'GET',actor=owner,status=200){const r=await fetch(base+path,{method,headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});const d=await r.json();assert.equal(r.status,status,JSON.stringify(d));assert.equal(r.headers.get('cache-control'),'no-store');return d;}
async function enable(actor=owner){const d=await api('/monitor',null,'GET',actor);return api('/monitor/settings',{...d.settings,enabled:true,timezone:'UTC',digest_time:'00:00'},'PUT',actor);}
async function save(actor=owner){return (await api('/direct-search/save',{request_key:randomUUID(),notice_id:noticeId},'POST',actor,201)).opportunity;}
async function digestAgain(actor=owner){await db.query('update korlix_radar_monitor_settings set last_run_day=null where user_id=$1',[actor]);}
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table public.usage_counters(id uuid primary key,user_id uuid references auth.users,credits_used int default 0,standard_generations int default 0,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant all on usage_counters to service_role;');
 const dir=new URL('../../supabase/migrations/',import.meta.url),names=await readdir(dir);for(const suffix of ['_contract_radar.sql','_contract_radar_monitoring.sql'])await db.exec(await readFile(new URL(names.find(n=>n.endsWith(suffix)),dir),'utf8'));
 const database={rpc:async(name,p)=>{try{return {data:await rpc(name,p.p_actor,p.p_action,p.p_id,p.p_data)};}catch(error){if(process.env.RADAR_DEBUG)console.error(error.message,error.code,error.where);return {error};}}};
 const sam={ready:()=>ready,search:async()=>{calls++;if(feedFails)throw Error('offline');return {opportunities:[notice()],searchedAt:new Date().toISOString(),message:'Fixture results',coverage:'Fixture'};},notice:async()=>{calls++;if(feedFails)throw Error('offline');return notice();}};
 const app=express();app.use(express.json());({monitor}=registerContractRadar(app,{database,requireUser:async q=>[owner,other].includes(q.headers.authorization)?{id:q.headers.authorization}:null,sam,aiAccess:async()=>{aiCalls++;return {allowed:false};},logger:{warn(){}}}));
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port+'/api/contract-radar';
});
test.beforeEach(async()=>{await db.exec('reset role');owner=randomUUID();other=randomUUID();for(const id of[owner,other])await db.query('insert into auth.users values($1)',[id]);await db.exec('set role service_role');calls=aiCalls=0;ready=true;feedFails=false;await db.exec('update korlix_radar_monitor_settings set enabled=false');});
test.after(async()=>{monitor.stop();await new Promise(r=>server.close(r));await db.close();});
test('monitor defaults off; direct search/PDF capabilities do not require or charge AI access',async()=>{
 await api('/monitor',null,'GET','',401);const d=await api('/monitor');assert.equal(d.settings.enabled,false);assert.equal(d.settings.version,0);assert.equal(d.capabilities.automatic_cost,0);
 await monitor.tick();assert.equal(calls,0);await api('/direct-search',{query:'cleaning'});await save();assert.equal(aiCalls,0);assert.equal((await db.query('select count(*) n from korlix_radar_jobs')).rows[0].n,0);
});
test('settings/searches/alerts are owner-isolated with stale version checks and direct-client denial',async()=>{
 await enable();const search=(await api('/monitor/searches',{request_key:randomUUID(),name:'Clean',query:'cleaning',enabled:true},'POST',owner,201)).search;
 assert.equal((await api('/monitor',null,'GET',other)).searches.length,0);await api('/monitor/searches/'+search.id,null,'DELETE',other,404);
 await api('/monitor/settings',{version:1,enabled:true,timezone:'UTC',digest_time:'00:00',deadline_days:[1]},'PUT',owner,409);
 await api('/monitor/settings',{version:2,enabled:true,timezone:'Nope/X',digest_time:'00:00',deadline_days:[1]},'PUT',owner,400);
 await db.exec('reset role;set role authenticated');try{await assert.rejects(call('state'),/permission denied/);await assert.rejects(db.query('select * from korlix_radar_alerts'),/permission denied/);}finally{await db.exec('reset role;set role service_role');}
 const rows=(await db.query("select relrowsecurity from pg_class where relname in('korlix_radar_monitor_settings','korlix_radar_searches','korlix_radar_alerts','korlix_radar_watches','korlix_radar_request_limits')")).rows;assert.equal(rows.length,5);assert(rows.every(r=>r.relrowsecurity));
});
test('daily digest and due reminders run without SAM connection, with dedup and read isolation',async()=>{
 await save();await enable();ready=false;await monitor.tick();let d=await api('/monitor');assert.equal(d.alerts.filter(a=>a.kind==='deadline').length,1);assert.equal(d.alerts.filter(a=>a.kind==='digest').length,1);assert.match(d.alerts.find(a=>a.kind==='digest').message,/not connected/);
 const alert=d.alerts[0];await api('/monitor/alerts/'+alert.id+'/read',{},'POST',other,404);await api('/monitor/alerts/'+alert.id+'/read',{});await monitor.tick();assert.equal((await api('/monitor')).alerts.length,2);
 await api('/monitor/alerts/read-all',{});assert((await api('/monitor')).alerts.every(a=>a.read_at));await api('/monitor/alerts',{confirmed:true},'DELETE');assert.equal((await api('/monitor')).alerts.length,0);
 await digestAgain();await monitor.tick();assert.equal((await api('/monitor')).alerts.length,0);assert.equal(aiCalls,0);
});
test('saved search daily result persists; feed failures retain prior results and do not claim success',async()=>{
 await api('/monitor/searches',{request_key:randomUUID(),name:'Clean',query:'cleaning',enabled:true},'POST',owner,201);await enable();await monitor.tick();let d=await api('/monitor');assert.equal(d.searches[0].result.opportunities.length,1);assert.equal(d.searches[0].last_error,null);
 await digestAgain();feedFails=true;await monitor.tick();d=await api('/monitor');assert.match(d.searches[0].last_error,/unavailable/);assert.equal(d.searches[0].result.opportunities.length,1);assert.match(d.settings.last_error,/unavailable/);assert.equal(aiCalls,0);
});
test('notice details change once and lease recovery never publishes stale owner settings',async()=>{
 const saved=await save();await enable();await monitor.tick();await db.query("update korlix_radar_watches set revision='old' where opportunity_id=$1",[saved.id]);await digestAgain();await monitor.tick();let d=await api('/monitor');assert.equal(d.alerts.filter(a=>a.kind==='amendment').length,1);
 await digestAgain();const claimed=await call('claim',null,{},null);assert(claimed.settings.lease_token);assert.equal(await call('claim',null,{},null),null);
 await db.query("update korlix_radar_monitor_settings set lease_until=now()-interval '1 second' where user_id=$1",[owner]);const next=await call('claim',null,{},null);assert.notEqual(next.settings.lease_token,claimed.settings.lease_token);
 assert.equal((await call('finish',null,{lease_token:claimed.settings.lease_token,version:claimed.settings.version,local_day:claimed.local_day})).stale,true);
 await api('/monitor/settings',{...(await api('/monitor')).settings,enabled:false},'PUT');assert.equal((await call('finish',null,{lease_token:next.settings.lease_token,version:next.settings.version,local_day:next.local_day})).stale,true);
});
test('search and direct-request caps are durable and global clear removes monitoring',async()=>{
 for(let i=0;i<5;i++)await api('/monitor/searches',{request_key:randomUUID(),name:'Search '+i,query:'cleaning '+i,enabled:true},'POST',owner,201);
 await api('/monitor/searches',{request_key:randomUUID(),name:'Six',query:'cleaning',enabled:true},'POST',owner,429);
 await db.query("insert into korlix_radar_request_limits(user_id,day,count) values($1,(now() at time zone 'UTC')::date,40)",[owner]);await api('/direct-search',{query:'cleaning'},'POST',owner,429);assert.equal(calls,0);
 await api('',{confirmed:true},'DELETE');assert.equal((await api('/monitor')).settings.enabled,false);assert.equal((await api('/monitor')).searches.length,0);
});
test('official adapter pins endpoint, redacts keys, bounds records, rejects redirects, and decodes split UTF8',async()=>{
 const requests=[];let redirect=false;const data=JSON.stringify({totalRecords:3,opportunitiesData:[raw({title:'Café cleaning'}),raw({noticeId:'a'.repeat(32),active:'No'}),raw({noticeId:'b'.repeat(32),type:'Award Notice'})]});
 const bytes=Buffer.from(data),split=bytes.indexOf(Buffer.from('é'))+1;
 const adapter=createSamAdapter({environment:{SAM_GOV_API_KEY:'fixture-secret'},fetchImpl:async(url,options)=>{requests.push({url:String(url),options});if(redirect)throw Error('redirect');return {ok:true,headers:new Headers(),body:(async function*(){yield bytes.subarray(0,split);yield bytes.subarray(split);})()};}});
 const r=await adapter.search({query:'cleaning',state:'oh'});assert.equal(r.opportunities.length,1);assert.equal(r.opportunities[0].title,'Café cleaning');assert(!JSON.stringify(r).includes('fixture-secret'));
 const u=new URL(requests[0].url);assert.equal(u.origin,'https://api.sam.gov');assert.equal(u.pathname,'/opportunities/v2/search');assert.equal(u.searchParams.get('state'),'OH');assert.equal(requests[0].options.redirect,'error');assert.equal(u.searchParams.get('offset'),'0');
 redirect=true;await assert.rejects(adapter.search({query:'cleaning'}),/could not be reached/);assert.throws(()=>samFilters({query:'x',naics:'12,34'}));await assert.rejects(adapter.notice('https://127.0.0.1'),/valid SAM/);
});
test('official source links allow vetted individual notices only and prevent lookalike hosts',()=>{
 for(const link of ['https://find-tender.service.gov.uk/Notice/012345-2026','https://canadabuys.canada.ca/en/tender-opportunities/tender-notice/abc-123','https://www.gojep.gov.jm/epps/cft/prepareViewCfTWS.do?resourceId=123','https://ogs.ny.gov/rfq-3048'])assert(noticeLink(link));
 for(const link of ['https://sam.gov.evil.test/opp/'+noticeId+'/view','https://www.gojep.gov.jm/epps/home.do','https://127.0.0.1/a','https://ogs.ny.gov/about','http://ogs.ny.gov/rfq-3048'])assert.equal(noticeLink(link),null);assert.equal(Object.keys(GEOGRAPHIES).length,4);
});
async function pdf(text='Insurance required. Submit a cleaning proposal by the official deadline.',pages=1){const doc=await PDFDocument.create();const font=await doc.embedFont(StandardFonts.Helvetica);for(let i=0;i<pages;i++){const page=doc.addPage();if(text)page.drawText(text,{font,size:12,x:40,y:700});}return Buffer.from(await doc.save());}
test('PDF text extraction is bounded, rejects scans and excessive pages without any AI calls',async()=>{
 const result=await extractRfpPdf(await pdf());assert.match(result.text,/Insurance required/);assert.equal(result.pageCount,1);assert.equal(result.truncated,false);
 await assert.rejects(extractRfpPdf(await pdf('',2)),/no usable text/);await assert.rejects(extractRfpPdf(await pdf('Sample long enough page text for extraction.',61)),/60 pages/);await assert.rejects(extractRfpPdf(Buffer.from('<html>bad')),/valid PDF/);await assert.rejects(extractRfpPdf(Buffer.alloc(PDF_LIMIT+1)),/5 MiB/);
});
test('authenticated multipart upload returns preview only and does not save or charge',async()=>{
 const form=new FormData();form.append('file',new Blob([await pdf()],{type:'application/pdf'}),'rfp.pdf');const r=await fetch(base+'/documents',{method:'POST',headers:{Authorization:owner},body:form});const d=await r.json();assert.equal(r.status,200,JSON.stringify(d));assert.match(d.text,/Insurance required/);assert.equal(d.filename,'rfp.pdf');assert.equal(aiCalls,0);assert.equal((await api('')).opportunities.length,0);
 const invalid=new FormData();invalid.append('file',new Blob(['%PDF-invalid'],{type:'application/pdf'}),'rfp.pdf');const bad=await fetch(base+'/documents',{method:'POST',headers:{Authorization:owner},body:invalid});assert.equal(bad.status,422);
});
test('SAM pagination is bounded and 429 cooldown is shared across manual and monitor callers',async()=>{
 let calls=0,clock=new Date('2026-10-04T12:00:00Z');const offsets=[];
 const adapter=createSamAdapter({environment:{SAM_API_KEY:'fixture'},now:()=>clock,fetchImpl:async(url)=>{calls++;offsets.push(new URL(url).searchParams.get('offset'));const rows=Array.from({length:50},(_,i)=>raw({noticeId:(calls*100+i).toString(16).padStart(32,'0'),responseDeadLine:'2099-01-01'}));return new Response(JSON.stringify({totalRecords:600,opportunitiesData:rows}),{headers:{'Content-Type':'application/json'}});}});
 const r=await adapter.search({naics:'561720'});assert.equal(calls,2);assert.deepEqual(offsets,['0','1']);assert.equal(r.opportunities.length,100);assert.equal(r.truncated,true);
 calls=0;const limited=createSamAdapter({environment:{SAM_API_KEY:'fixture'},now:()=>clock,fetchImpl:async()=>{calls++;return new Response('{}',{status:429,headers:{'Retry-After':'120'}});}});
 await assert.rejects(limited.search({query:'cleaning'}),/request limit/);await assert.rejects(limited.notice(noticeId),/cooldown/);assert.equal(calls,1);
 clock=new Date(clock.getTime()+121000);await assert.rejects(limited.notice(noticeId),/request limit/);assert.equal(calls,2);
});
test('completed/submitted opportunities do not generate deadline reminders and disabled searches never run',async()=>{
 const o=await save();await api('/opportunities/'+o.id,{stage:'submitted'},'PATCH');await api('/monitor/searches',{request_key:randomUUID(),name:'Disabled',query:'cleaning',enabled:false},'POST',owner,201);await enable();calls=0;await monitor.tick();const d=await api('/monitor');assert.equal(d.alerts.filter(a=>a.kind==='deadline').length,0);assert.equal(d.searches[0].last_checked_at,null);assert.equal(calls,1); // one saved notice check, no search
});
test('profile geography limits manual discovery and cannot be forged to fetch arbitrary sources',async()=>{
 await api('/profile',{businessName:'Fixture',services:'Cleaning',location:'Jamaica',geography:'jm'},'PUT');assert.equal((await api('')).profile.data.geography,'jm');
 await api('/profile',{businessName:'Fixture',services:'Cleaning',location:'Jamaica',geography:'http://localhost'},'PUT',owner,400);
});
test('automatic feed budget survives worker retries while saved deadline reminders still finish',async()=>{
 await save();await enable();await call('reserve_worker',null,{count:2});for(let i=0;i<9;i++)await call('reserve_worker',null,{count:2});await assert.rejects(call('reserve_worker',null,{count:1}),/daily limit/);
 calls=0;await monitor.tick();const d=await api('/monitor');assert.equal(calls,0);assert.equal(d.alerts.filter(a=>a.kind==='deadline').length,1);assert.match(d.settings.last_error,/unavailable/);
});
