import {createCipheriv,createDecipheriv,createHash,randomBytes} from 'node:crypto';
import {fail,uuid} from './core.mjs';
export const measurementDisclosure=(brand,platform)=>`Optional: I allow ${brand} to store the advertising click identifier from this link and share it, with the time of this inquiry, with ${platform==='google'?'Google':'Meta'} to measure advertising results. My name, email, phone and message are not included. I can send my inquiry without agreeing.`;
export function measurementCandidate(query,platform){
 const keys=platform==='google'?['gclid','gbraid','wbraid']:['fbclid'];
 const present=keys.filter(k=>Object.hasOwn(query,k));
 if(present.length!==1)return null;
 const kind=present[0],value=query[kind];
 return typeof value==='string'&&/^[A-Za-z0-9_-]{1,512}$/.test(value)?{type:kind,id:value}:null;
}
export const measurementChoice=body=>{
 if(body.measurement_consent!==undefined&&body.measurement_consent!=='yes')fail('Choose the optional measurement setting again.');
 return body.measurement_consent==='yes'?'granted':'declined';
};
export function createConversionIntake(database,secret,now){
 const key=createHash('sha256').update('korlix-measurement-envelope-v1\0').update(secret).digest();
 const command=async(actor,action,funnel,data)=>{
  if(!database)fail('Conversion intake is not configured.',503);
  const {data:out,error}=await database.rpc('korlix_funnel_measurement_v1',{p_actor:actor,p_action:action,p_funnel:funnel,p_data:data});
  if(error){const status={'42501':403,'P0002':404,'40001':409,'54000':429,'P0001':400}[error.code];fail(status?error.message:'Conversion intake is temporarily unavailable.',status||503);}
  return out;
 };
 const open=(value,token)=>{
  if(value===undefined||value==='')return null;
  if(typeof value!=='string'||value.length>1800||!/^[A-Za-z0-9_-]+$/.test(value))fail('Reload the measurement choice before submitting.');
  try{
   const b=Buffer.from(value,'base64url'),cipher=createDecipheriv('aes-256-gcm',key,b.subarray(0,12));cipher.setAAD(Buffer.from(token));cipher.setAuthTag(b.subarray(12,28));
   const d=JSON.parse(Buffer.concat([cipher.update(b.subarray(28)),cipher.final()]).toString());
   if(d.policy_version!=='measurement_v1'||!['google','meta'].includes(d.platform)||!Number.isSafeInteger(d.observed)||now()-d.observed<0||now()-d.observed>1800000)throw Error();
   uuid(d.revision);return {...d,token:value};
  }catch{fail('Reload the measurement choice before submitting.');}
 };
 return {command,open,
  async resolve(f,code,query,token){
   if(!code)return null;
   const d=await command(null,'resolve',f.id,{slug:f.slug,code});if(!d)return null;
   if(!['meta','google'].includes(d.platform)||d.policy_version!=='measurement_v1')fail('Conversion intake could not be verified.',503);uuid(d.revision);
   const context={...d,click:measurementCandidate(query,d.platform),observed:now()};
   const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key,iv);cipher.setAAD(Buffer.from(token));
   const encrypted=Buffer.concat([cipher.update(JSON.stringify(context)),cipher.final()]);
   return {...context,token:Buffer.concat([iv,cipher.getAuthTag(),encrypted]).toString('base64url')};
  },
  capture(f,input,code,context,choice){return command(null,'capture',f.id,{...input,code,settings_revision:context.revision,platform:context.platform,policy_version:context.policy_version,measurement_consent:choice,
   ...(choice==='granted'&&context.click?{click_type:context.click.type,click_id:context.click.id,observed_at:new Date(context.observed).toISOString()}:{})});}
 };
}
export function registerConversionIntake(app,{base,owner,intake}){
 const path=base+'/:id/campaigns/:campaign_id/measurement';
 const days=v=>{if(![7,30,90].includes(v))fail('Choose 7, 30 or 90 reporting days.');return v;};
 app.get(path,owner(async(q,r,u)=>{
  if(Object.keys(q.query).some(k=>k!=='days')||q.query.days!==undefined&&!['7','30','90'].includes(q.query.days))fail('Choose 7, 30 or 90 reporting days.');
  r.json(await intake.command(u,'read',uuid(q.params.id),{campaign_id:uuid(q.params.campaign_id),days:days(Number(q.query.days??30))}));
 },{ratePrefix:'conversion-intake-read:',max:30}));
 app.post(path+'/settings',owner(async(q,r,u)=>{
  const b=q.body;
  if(Object.keys(q.query).length||!b||Object.keys(b).length!==3||typeof b.enabled!=='boolean'||!Object.hasOwn(b,'expected_revision')||!Object.hasOwn(b,'days'))fail('Choose the measurement setting and reporting window.');
  if(b.expected_revision!==null)uuid(b.expected_revision);
  r.json(await intake.command(u,'settings',uuid(q.params.id),{campaign_id:uuid(q.params.campaign_id),days:days(b.days),enabled:b.enabled,expected_revision:b.expected_revision}));
 },{ratePrefix:'conversion-intake-settings:',max:5}));
}
