import {RadarError,fail,text,uuid} from './ai.mjs';
import {createSamAdapter,samFilters,samNoticeId} from './sam.mjs';
import {GEOGRAPHIES} from './sources.mjs';
import {extractRfpPdf,PDF_LIMIT} from './pdf.mjs';
import multer from 'multer';
const base='/api/contract-radar';
export const monitorDefaults=Object.freeze({enabled:false,timezone:'America/New_York',digest_time:'09:00',deadline_days:[7,3,1],version:0});
function settingsInput(v={}){
 if(typeof v.enabled!=='boolean'||!Number.isInteger(v.version)||v.version<0)fail('Refresh monitoring settings and try again.');
 const timezone=text(v.timezone,100,'Time zone');try{new Intl.DateTimeFormat('en',{timeZone:timezone}).format();}catch{fail('Choose a valid time zone.');}
 if(typeof v.digest_time!=='string'||!/^([01]\d|2[0-3]):[0-5]\d$/.test(v.digest_time))fail('Choose a valid digest time.');
 if(!Array.isArray(v.deadline_days)||v.deadline_days.length>5||v.deadline_days.some(x=>![0,1,3,7,14,30].includes(x)))fail('Choose up to five supported deadline reminders.');
 return {version:v.version,enabled:v.enabled,timezone,digest_time:v.digest_time,deadline_days:[...new Set(v.deadline_days)].sort((a,b)=>b-a)};
}
const publicOpportunity=o=>({id:o.id,data:o.data,stage:o.stage,notes:o.notes,review:o.review,createdAt:o.created_at,updatedAt:o.updated_at});
export function createRadarMonitor({database,requireUser,environment=process.env,sam=createSamAdapter({environment}),extractPdf=extractRfpPdf,autoStart=false,logger=console}={}){
 let stopped=false,running=false,timer;const uploading=new Set(),searching=new Set();
 const call=async(actor,action,id=null,data={})=>{const r=await database.rpc('korlix_radar_monitor_v1',{p_actor:actor,p_action:action,p_id:id,p_data:data});if(r.error){const status={P0002:404,'40001':409,'54000':429,P0001:400,'42501':403}[r.error.code];if(status)fail(r.error.message,status);fail('Contract Radar monitoring is temporarily unavailable. Refresh and retry.',503);}return r.data;};
 const rootCapabilities=()=>({directSamReady:sam.ready(),monitoringReady:!!database,pdfImport:true,geographies:Object.entries(GEOGRAPHIES).map(([code,x])=>({code,label:x.label,coverage:x.coverage}))});
 const capabilities=()=>({direct_sam_ready:sam.ready(),monitor_ready:!!database,automatic_cost:0,coverage:'Daily in-app deadline reminders for saved opportunities. SAM.gov matching and notice-detail checks require the server SAM.gov connection. Other regions use on-demand official web search.',sources:Object.entries(GEOGRAPHIES).map(([code,x])=>({code,...x})),limits:{saved_searches:5,notice_checks_per_day:10,direct_actions_per_day:40,automatic_feed_requests_per_utc_day:20,pdf_bytes:PDF_LIMIT,pdf_pages:60,pdf_characters:18000},readiness:sam.ready()?'Direct SAM.gov feed configured. Its request limits and availability still apply.':'Direct SAM.gov is not connected. Saved deadline reminders still work; official web search remains available.'});
 const state=async actor=>{const d=await call(actor,'state');return {...d,settings:d.settings?{...d.settings,digest_time:d.settings.digest_time.slice(0,5)}:{...monitorDefaults},capabilities:capabilities()};};
 const route=fn=>async(q,r)=>{r.set('Cache-Control','no-store');try{const user=await requireUser(q);if(!user?.id)fail('Sign in to use Contract Radar.',401);if(!database)fail('Contract Radar is temporarily unavailable.',503);await fn(q,r,user);}catch(e){const status=e instanceof RadarError?e.status:e.status===422?422:e.statusCode===401?401:503;r.status(status).json({error:e instanceof RadarError||status===422?e.message:status===401?'Sign in again to use Contract Radar.':'Contract Radar is temporarily unavailable. Refresh and retry.'});}};
 const reserve=async owner=>{if(!sam.ready())fail('Direct SAM.gov is not configured. Use official web search or saved deadline alerts.',503);await call(owner,'reserve_request');};
 const upload=multer({storage:multer.memoryStorage(),limits:{fileSize:PDF_LIMIT,files:1,fields:0,parts:2},fileFilter:(_q,file,cb)=>cb(null,file.mimetype==='application/pdf'||file.mimetype==='application/octet-stream')}).single('file');
 function register(app){
  app.get(base+'/monitor',route(async(_q,r,u)=>r.json(await state(u.id))));
  app.put(base+'/monitor/settings',route(async(q,r,u)=>{await call(u.id,'save_settings',null,settingsInput(q.body));r.json(await state(u.id));}));
  app.post(base+'/monitor/searches',route(async(q,r,u)=>{if(q.body?.enabled!==true&&q.body?.enabled!==false)fail('Choose whether this search is enabled.');const search=await call(u.id,'search_save',uuid(q.body?.request_key),{...samFilters(q.body),name:text(q.body?.name,80,'Saved search name'),enabled:q.body.enabled});r.status(201).json({search});}));
  app.delete(base+'/monitor/searches/:id',route(async(q,r,u)=>{await call(u.id,'search_delete',uuid(q.params.id));r.json({deleted:true});}));
  app.post(base+'/monitor/alerts/read-all',route(async(_q,r,u)=>{await call(u.id,'read_all');r.json({updated:true});}));
  app.post(base+'/monitor/alerts/:id/read',route(async(q,r,u)=>r.json({alert:await call(u.id,'read',uuid(q.params.id))})));
  app.delete(base+'/monitor/alerts',route(async(q,r,u)=>{if(q.body?.confirmed!==true)fail('Confirm before clearing alert history.');await call(u.id,'clear_alerts');r.json({deleted:true});}));
  app.post(base+'/direct-search',route(async(q,r,u)=>{
   const filters=samFilters(q.body);if(searching.has(u.id)||searching.size>=3)fail('A direct search is already running. Try again shortly.',429);
   searching.add(u.id);try{await reserve(u.id);r.json(await sam.search(filters));}finally{searching.delete(u.id);}
  }));
  app.post(base+'/direct-search/save',route(async(q,r,u)=>{
   const id=uuid(q.body?.request_key),noticeId=samNoticeId(q.body?.notice_id);
   if(searching.has(u.id)||searching.size>=3)fail('A direct search is already running. Try again shortly.',429);
   searching.add(u.id);try{await reserve(u.id);const data=await sam.notice(noticeId);
    if(!data||!data.active||(data.deadline&&data.deadline<new Date().toISOString().slice(0,10)))fail('This notice is no longer active. Check SAM.gov for updates.',409);
    const saved=await database.rpc('korlix_radar_v1',{p_actor:u.id,p_action:'opportunity_save',p_id:id,p_data:{source_key:data.sourceUrl,data}});
    if(saved.error)fail('This opportunity could not be saved. Refresh and retry.',saved.error.code==='54000'?429:503);r.status(201).json({opportunity:publicOpportunity(saved.data)});
   }finally{searching.delete(u.id);}
  }));
  app.post(base+'/documents',route(async(q,r,u)=>{
   if(uploading.has(u.id)||uploading.size>=2)fail('A PDF is already being read. Try again shortly.',429);uploading.add(u.id);
   try{
    await new Promise((resolve,reject)=>{const timeout=setTimeout(()=>{q.destroy();reject(new RadarError('PDF upload timed out. Try again with a smaller file.',408));},60000);
     upload(q,r,e=>{clearTimeout(timeout);e?reject(new RadarError(e.code==='LIMIT_FILE_SIZE'?'Upload a PDF smaller than 5 MiB.':'Upload one PDF file with no other fields.',e.code==='LIMIT_FILE_SIZE'?413:400)):resolve();});
    });
    if(!q.file)fail('Choose one PDF file.',400);
    const result=await extractPdf(q.file.buffer);r.json({text:result.text,pageCount:result.pageCount,truncated:result.truncated,warnings:result.warnings,filename:String(q.file.originalname).replace(/[\x00-\x1f\\/]/g,'').slice(0,160)});
   }finally{if(q.file)q.file.buffer=null;uploading.delete(u.id);}
  }));
 }
 async function tick(){
  if(stopped||running||!database)return;running=true;
  try{for(let account=0;account<3&&!stopped;account++){
   const claim=await call(null,'claim');if(!claim)break;
   const s=claim.settings,data={lease_token:s.lease_token,version:s.version,local_day:claim.local_day,searches:[],watches:[],digest:{searches:[],notice_checks:0,feed_available:sam.ready()}};
   try{
    let matchCount=0,errors=0;const deadline=Date.now()+8*60*1000;
    for(const search of claim.searches||[]){
     if(!sam.ready()||stopped||Date.now()>deadline){data.searches.push({id:search.id,error:'SAM.gov is not connected. Saved search will run after connection.',result:search.result||{}});continue;}
     try{await call(s.user_id,'reserve_worker',null,{count:2});const result=await sam.search(search);data.searches.push({id:search.id,result});matchCount+=result.opportunities.length;data.digest.searches.push({id:search.id,name:search.name,count:result.opportunities.length,truncated:!!result.truncated});}
     catch{errors++;data.searches.push({id:search.id,error:'SAM.gov search was unavailable. It will be checked at the next digest.',result:search.result||{}});}
    }
    if(sam.ready())for(const opportunity of (claim.opportunities||[]).filter(o=>/^https:\/\/sam\.gov\/opp\/([a-f\d]{32}|[a-f\d-]{36})\/view$/i.test(o.data.sourceUrl||'')).slice(0,10)){
     if(stopped||Date.now()>deadline){errors++;break;}
     try{await call(s.user_id,'reserve_worker',null,{count:1});const id=opportunity.data.sourceUrl.split('/')[4],snapshot=await sam.notice(id);if(snapshot){data.watches.push({id:opportunity.id,snapshot});data.digest.notice_checks++;}else errors++;}catch{errors++;}
    }
    data.message=`${matchCount} matching federal notices across ${data.digest.searches.length} saved searches. Saved opportunity deadlines were checked. ${sam.ready()?`${data.digest.notice_checks} SAM.gov notices checked for detail changes.`:'SAM.gov is not connected; automatic matches and notice changes were not checked.'} ${errors?'Some feed checks failed or notices were unavailable. Earlier snapshots were retained; read each official notice for the latest information.':''} No AI credits used.`;
    data.error=errors?'Some SAM.gov checks were unavailable. Earlier snapshots were retained; confirm deadlines on the official notice.':null;
    await call(s.user_id,'finish',null,data);
   }catch{try{await call(s.user_id,'failed',null,data);}catch{logger.warn('Contract Radar monitor could not save recovery state');}}
  }}catch{logger.warn('Contract Radar monitoring temporarily unavailable');}finally{running=false;}
 }
 if(autoStart&&database){timer=setInterval(()=>void tick(),60000);timer.unref?.();}
 return {register,tick,rootCapabilities,capabilities,state,clear:actor=>call(actor,'clear'),stop(){stopped=true;clearInterval(timer);}};
}
