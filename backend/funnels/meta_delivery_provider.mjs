import {createHmac} from 'node:crypto';
import {fail} from './core.mjs';
import {metaBrowserAgent} from './meta_website_consent.mjs';
import {metaDestination} from './meta_conversion_provider.mjs';
const object=v=>v&&typeof v==='object'&&!Array.isArray(v);
export const metaDeliveryToken=v=>typeof v==='string'&&v.length>=20&&v.length<=12000&&/^[A-Za-z0-9._|-]+$/.test(v);
const invalid=()=>fail('Meta delivery could not be verified. Refresh the saved status; do not resend.',503);
export function metaDeliveryBody(receipt,now=Date.now()){
 const r=receipt,t=Date.parse(r?.captured_at),observed=Date.parse(r?.observed_at);
 if(!r||r.state!=='prepared'||r.consent!=='granted'||r.policy_version!=='meta_measurement_v2'||r.event_name!=='Lead'||r.action_source!=='website'||
  typeof r.event_id!=='string'||!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(r.event_id)||
  !Number.isFinite(t)||t>now||t<now-7*86400000||!Number.isFinite(observed)||observed>now||observed<t-3600000||observed>t+300000||
  typeof r.click_id!=='string'||!/^[A-Za-z0-9_-]{1,512}$/.test(r.click_id)||!metaBrowserAgent(r.client_user_agent)||
  typeof r.event_source_url!=='string'||r.event_source_url.length>2048||!/^https:\/\/[a-z0-9.-]+\/f\/[a-z0-9-]+$/.test(r.event_source_url))fail('This inquiry has no eligible Meta website consent receipt.',409);
 return {data:[{event_name:'Lead',event_time:Math.floor(t/1000),event_id:r.event_id,action_source:'website',event_source_url:r.event_source_url,
  user_data:{client_user_agent:r.client_user_agent,fbc:'fb.1.'+observed+'.'+r.click_id}}]};
}
export function metaDeliveryReceipt(value){
 if(!object(value)||value.error||value.events_received!==1||!Array.isArray(value.messages)||value.messages.length>100||
  typeof value.fbtrace_id!=='string'||!/^[A-Za-z0-9_-]{1,200}$/.test(value.fbtrace_id))invalid();
 // Never persist or return provider message text; it can contain submitted data.
 return {trace_id:value.fbtrace_id,has_warnings:value.messages.length>0};
}
export function createMetaDeliveryProvider(config,{fetchImpl=fetch,now=Date.now}={}){
 async function request(path,token,params={},write=false){
  if(config.apiVersion!=='v26.0')fail('Meta conversion delivery requires the supported API version.',409);
  const url=new URL('https://graph.facebook.com/v26.0/'+path);
  const proof=createHmac('sha256',config.secret).update(token).digest('hex');
  const body={...params,appsecret_proof:proof};
  if(!write)for(const [k,v] of Object.entries(body))url.searchParams.set(k,String(v));
  let response,value;
  try{
   response=await fetchImpl(url,{method:write?'POST':'GET',headers:{Authorization:'Bearer '+token,...(write?{'Content-Type':'application/json'}:{})},...(write?{body:JSON.stringify(body)}:{}),redirect:'error',signal:AbortSignal.timeout(10000)});
   const reader=response.body?.getReader();if(!reader)throw Error();let size=0;const parts=[];
   try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>128*1024)throw Error();parts.push(Buffer.from(value));}}finally{await reader.cancel().catch(()=>{});}
   value=JSON.parse(Buffer.concat(parts).toString('utf8'));
  }catch{invalid();}
  if(!response.ok||!object(value)||value.error)invalid();return value;
 }
 return {
  async authorize(token,destination){
   if(!metaDeliveryToken(token))fail('Enter a valid Meta system-user access token.',400);
   const selected=metaDestination(destination),debug=await request('debug_token',config.id+'|'+config.secret,{input_token:token}),d=debug.data;
   if(!d||d.is_valid!==true||d.type!=='SYSTEM_USER'||String(d.app_id)!==config.id||typeof d.user_id!=='string'||!/^\d{1,40}$/.test(d.user_id)||
    !Array.isArray(d.scopes)||!d.scopes.includes('ads_management'))fail('Use a system-user token for the configured KORLIX Meta app with ads_management and access to this data source.',409);
   const times=[d.expires_at,d.data_access_expires_at];
   if(times.some(n=>!Number.isSafeInteger(n)||n<0||n!==0&&n*1000<=now()+60000))fail('Meta conversion access is expired. Replace its system-user token.',409);
   const pixel=await request(selected.pixel_id,token,{fields:'id,name'});
   if(pixel.id!==selected.pixel_id||pixel.name!==selected.name)fail('The Meta data source changed. Refresh its selection before authorizing delivery.',409);
   const expiry=times.filter(n=>n>0);
   // Scope + exact readable asset identity are preflight evidence only.
   // Actual event-write acceptance is established solely by /events.
   return {system_user_id:d.user_id,expires_at:expiry.length?new Date(Math.min(...expiry)*1000).toISOString():null};
  },
  async send(token,destination,body){
   const d=metaDestination(destination);
   if(!metaDeliveryToken(token)||!object(body)||Object.keys(body).length!==1||!Array.isArray(body.data)||body.data.length!==1)invalid();
   return metaDeliveryReceipt(await request(d.pixel_id+'/events',token,body,true));
  }
 };
}
