import {createHash} from 'node:crypto';
import {fail,text,validDay} from './ai.mjs';
const endpoint='https://api.sam.gov/opportunities/v2/search';
const maxBytes=2*1024*1024;
export function samFilters(v={}){
 const query=text(v.query,160,'Search keywords',true),naics=text(v.naics,6,'NAICS code',true),state=text(v.state,2,'State code',true).toUpperCase();
 if(naics&&!/^\d{2,6}$/.test(naics))fail('Use a 2–6 digit NAICS code.');
 if(state&&!/^[A-Z]{2}$/.test(state))fail('Use a two-letter US state code.');
 if(!query&&!naics)fail('Enter search keywords or a NAICS code.');
 return {query,naics,state};
}
export function samNoticeId(value){if(typeof value!=='string'||!/^([a-f\d]{32}|[a-f\d-]{36})$/i.test(value))fail('Choose a valid SAM.gov notice.');return value.toLowerCase();}
const clip=(v,n)=>typeof v==='string'?v.trim().slice(0,n):'';
const day=v=>{try{return validDay(typeof v==='string'?v.slice(0,10):null);}catch{return null;}};
export function normalizeSam(row,now=new Date(),{allowClosed=false}={}){
 let noticeId;try{noticeId=samNoticeId(row.noticeId);}catch{return null;}
 const title=clip(row.title,200);if(!title)return null;
 const types={'Solicitation':'solicitation','Combined Synopsis/Solicitation':'solicitation','Sources Sought':'sources_sought','Presolicitation':'presolicitation'};
 const noticeType=types[row.type]||(allowClosed?'closed':null);if(!noticeType)return null;
 const deadline=day(row.responseDeadLine||row.reponseDeadLine),pop=row.placeOfPerformance||{};
 const location=[pop.city?.name,pop.state?.code,pop.country?.name].filter(x=>typeof x==='string').join(', ').slice(0,200);
 const active=String(row.active).toLowerCase()==='yes'&&noticeType!=='closed';
 const sourceUrl=`https://sam.gov/opp/${noticeId}/view`,agency=clip(row.fullParentPathName,200);
 const postedDate=clip(row.postedDate,40),solicitationNumber=clip(row.solicitationNumber,100),naics=clip(row.naicsCode,6);
 const revision=createHash('sha256').update(JSON.stringify({title,agency,deadline,active,postedDate,solicitationNumber,noticeType,naics,location,description:clip(row.description,2000),resources:Array.isArray(row.resourceLinks)?row.resourceLinks.filter(x=>typeof x==='string').slice(0,40).sort():[],modified:clip(row.modifiedDate||row.lastModifiedDate,50)})).digest('hex');
 const summary=`${noticeType==='closed'?'Notice no longer listed as an open opportunity':noticeType==='solicitation'?'Solicitation':noticeType==='sources_sought'?'Sources sought (not an open bid)':'Presolicitation (not an open bid)'}. ${solicitationNumber?'Notice '+solicitationNumber+'. ':''}Read the original notice and all attachments; full requirements are not included in this feed.`;
 return {noticeId,title,agency,location,sourceUrl,summary,deadline,noticeType,source:'sam_api',noticeText:'',discoveredAt:now.toISOString(),postedDate,solicitationNumber,naics,active,revision,matchReason:'Matches your explicit SAM.gov search filters; eligibility is not assessed.'};
}
async function boundedJSON(response){
 if(Number(response.headers?.get('content-length'))>maxBytes)fail('The official feed response is too large. Narrow your search.',502);
 let value='';let bytes=0;const chunks=[];
 if(response.body){for await(const chunk of response.body){bytes+=chunk.length;if(bytes>maxBytes){await response.body.cancel?.().catch(()=>{});fail('The official feed response is too large. Narrow your search.',502);}chunks.push(Buffer.from(chunk));}}
 else {value=await response.text();if(Buffer.byteLength(value)>maxBytes)fail('The official feed response is too large. Narrow your search.',502);}
 if(chunks.length)value=Buffer.concat(chunks).toString('utf8');
 try{return JSON.parse(value);}catch{fail('SAM.gov returned an unreadable response. Try again later.',502);}
}
export function createSamAdapter({environment=process.env,fetchImpl=fetch,now=()=>new Date()}={}){
 let cooldownUntil=0;
 const key=()=>String(environment.SAM_GOV_API_KEY||environment.SAM_API_KEY||'').trim();
 async function request(params){
  if(!key())fail('Direct SAM.gov search is not configured. Use official web search or saved deadline alerts.',503);
  if(now().getTime()<cooldownUntil)fail('SAM.gov reached its request limit. Direct checks will resume after its cooldown.',429);
  const url=new URL(endpoint);url.searchParams.set('api_key',key());for(const [k,v]of Object.entries(params))if(v!==''&&v!=null)url.searchParams.set(k,String(v));
  let response;try{response=await fetchImpl(url,{headers:{Accept:'application/json'},signal:AbortSignal.timeout(20000),redirect:'error'});}catch{fail('SAM.gov could not be reached. Try again later.',502);}
  if(response.status===429){const retry=response.headers?.get('retry-after')||'';const seconds=/^\d+$/.test(retry)?Number(retry):(Date.parse(retry)-now().getTime())/1000;cooldownUntil=now().getTime()+Math.min(86400,Math.max(30,Number.isFinite(seconds)&&seconds>0?seconds:3600))*1000;}
  if(!response.ok)fail(response.status===429?'SAM.gov reached its request limit. Try again later.':'SAM.gov direct search is temporarily unavailable. Use official web search.',response.status===429?429:502);
  return boundedJSON(response);
 }
 const dates=()=>{const end=now(),start=new Date(end);start.setUTCFullYear(start.getUTCFullYear()-1);start.setUTCDate(start.getUTCDate()+1);const f=d=>`${String(d.getUTCMonth()+1).padStart(2,'0')}/${String(d.getUTCDate()).padStart(2,'0')}/${d.getUTCFullYear()}`;return {postedFrom:f(start),postedTo:f(end)};};
 return {
  ready:()=>!!key(),
  async search(input){const filters=samFilters(input),opportunities=[],seen=new Set();let total=0;
   for(let page=0;page<2;page++){const data=await request({...dates(),title:filters.query,ncode:filters.naics,state:filters.state,limit:50,offset:page});const rows=Array.isArray(data.opportunitiesData)?data.opportunitiesData:[];total=Number(data.totalRecords)||rows.length;
    for(const row of rows){const x=normalizeSam(row,now());if(!x||!x.active||(x.deadline&&x.deadline<now().toISOString().slice(0,10))||seen.has(x.noticeId))continue;seen.add(x.noticeId);opportunities.push(x);}
    if(rows.length<50||total<=(page+1)*50)break;
   }
   return {opportunities,searchedAt:now().toISOString(),coverage:'SAM.gov public API: latest active federal notices, up to 100 feed records per search. Not all matching records may be included.',truncated:total>100,message:opportunities.length?'Read each official notice and amendments before bidding. No AI credit used.':'No active notices matched these filters. Try broader keywords or NAICS. No AI credit used.'};
  },
  async notice(id){id=samNoticeId(id);const data=await request({...dates(),noticeid:id,limit:1});const raw=(data.opportunitiesData||[]).find(x=>String(x.noticeId).toLowerCase()===id);return raw?normalizeSam(raw,now(),{allowClosed:true}):null;}
 };
}
