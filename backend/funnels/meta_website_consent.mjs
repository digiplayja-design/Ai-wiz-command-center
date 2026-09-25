import {createHash} from 'node:crypto';
import {fail,uuid} from './core.mjs';
export const metaWebsitePolicy='meta_measurement_v2';
export const metaWebsiteDisclosure=brand=>`Optional: I allow ${brand} to store and share with Meta the advertising click identifier from this link, the time of this inquiry, my browser information (user agent), and this page's address without query parameters, to measure advertising results. My name, email, phone, message and IP address are not included. I can send my inquiry without agreeing.`;
export const metaBrowserAgent=value=>typeof value==='string'&&value.length>0&&value.length<=1024&&value.trim()===value&&!/[^\x20-\x7e]/.test(value)?value:null;
export function createMetaWebsiteConsent(database,publicBase,enabled){
 let origin=null;
 try{const u=new URL(publicBase);if(u.protocol==='https:'&&!u.username&&!u.password&&!u.search&&!u.hash&&u.pathname==='/'&&u.hostname.length<=253&&/^[a-z0-9.-]+$/.test(u.hostname)&&u.hostname.includes('.')&&!u.hostname.endsWith('.localhost')&&u.hostname!=='localhost'&&!/^[\d.]+$/.test(u.hostname)&&!u.port)origin=u.origin;}catch{}
 const configured=enabled===true&&origin!==null;
 const config={configured,public_origin:origin,config_hash:createHash('sha256').update(metaWebsitePolicy+'\0'+(origin??'')).digest('hex')};
 const command=async(actor,action,funnel,data={})=>{
  if(!database)fail('Meta website consent storage is not configured.',503);
  const {data:out,error}=await database.rpc('korlix_meta_measurement_v2',{p_actor:actor,p_action:action,p_funnel:funnel,p_data:{...data,...config}});
  if(error){const status={'42501':403,'P0002':404,'40001':409,'54000':429,'P0001':400,'23514':400}[error.code];fail(status?error.message:'Meta website consent is temporarily unavailable.',status||503);}return out;
 };
 return {configured,config,command,
  resolve:(f,code)=>configured?command(null,'resolve',f.id,{slug:f.slug,code}):null,
  capture(f,input,code,context,choice,headers={}){
   // Read browser metadata only for this affirmative consent version and a
   // supported click. No Host/Referer/body URL, cookies, IP or contact fields.
   const allowed=configured&&choice==='granted'&&context.click;
   const agent=allowed?metaBrowserAgent(headers['user-agent']):null;
   return command(null,'capture',f.id,{...input,code,settings_revision:context.revision,policy_version:metaWebsitePolicy,measurement_consent:choice,
    observed_at:new Date(context.observed).toISOString(),
    ...(allowed?{click_id:context.click.id}:{}),
    ...(agent?{client_user_agent:agent,event_source_url:`${origin}/f/${f.slug}`}:{})});
  }
 };
}
export function registerMetaWebsiteConsent(app,{base,owner,consent}){
 const path=base+'/:id/campaigns/:campaign_id/meta-website-consent';
 app.get(base+'/meta-website-consent/readiness',(_q,r)=>r.set('Cache-Control','no-store').json({configured:consent.configured,send_ready:false,provider_verified:false}));
 app.get(path,owner(async(q,r,u)=>{
  if(Object.keys(q.query).some(k=>k!=='days')||q.query.days!==undefined&&!['7','30','90'].includes(q.query.days))fail('Choose 7, 30 or 90 reporting days.');
  r.json(await consent.command(u,'read',uuid(q.params.id),{campaign_id:uuid(q.params.campaign_id),days:Number(q.query.days??30)}));
 },{ratePrefix:'meta-website-consent-read:',max:30}));
 app.post(path+'/settings',owner(async(q,r,u)=>{
  const b=q.body,keys=['enabled','expected_revision','days','confirmed'];
  if(Object.keys(q.query).length||!b||typeof b!=='object'||Array.isArray(b)||Object.keys(b).length!==keys.length||!keys.every(k=>Object.hasOwn(b,k))||typeof b.enabled!=='boolean'||b.confirmed!==true||![7,30,90].includes(b.days))fail('Refresh and confirm the Meta website consent setting.');
  if(b.expected_revision!==null)uuid(b.expected_revision);
  r.json(await consent.command(u,'settings',uuid(q.params.id),{campaign_id:uuid(q.params.campaign_id),...b}));
 },{ratePrefix:'meta-website-consent-settings:',max:5}));
}
