import {fail,uuid} from './core.mjs';
const code=v=>typeof v==='string'&&/^[a-f0-9]{64}$/.test(v);
export function createCampaignAttribution(database){
 const command=async(actor,action,funnel,data)=>{
  if(!database)fail('Campaign attribution is not configured.',503);
  const {data:out,error}=await database.rpc('korlix_funnel_attribution_v1',{p_actor:actor,p_action:action,p_funnel:funnel,p_data:data});
  if(error){const status={'42501':403,'P0002':404,'40001':409,'54000':429,'P0001':400}[error.code];fail(status?error.message:'Campaign attribution is temporarily unavailable.',status||503);}
  return out;
 };
 return {command,
  async resolve(f,value){if(!code(value))return null;const r=await command(null,'resolve',f.id,{slug:f.slug,code:value});if(r!==null&&(!r||r.code!==value))fail('Campaign attribution could not be verified.',503);return r?.code??null;},
  async capture(f,input,value){if(!code(value))fail('Reload this campaign page before submitting.');return command(null,'capture',f.id,{...input,code:value});}
 };
}
export function registerCampaignAttribution(app,{base,owner,attribution,publicBase}){
 const path=base+'/:id/campaigns/:campaign_id/attribution';
 const days=v=>{if(![7,30,90].includes(v))fail('Choose 7, 30 or 90 reporting days.');return v;};
 const present=d=>{
  let root;try{root=new URL(publicBase);}catch{fail('The campaign destination is not configured.',503);}
  if(root.protocol!=='https:'||root.username||root.password||root.search||root.hash)fail('The campaign destination is not configured.',503);
  let link=null;
  if(d.link){
   if(!code(d.link.code))fail('Campaign attribution could not be verified.',503);
   const u=new URL(`${publicBase}/f/${d.slug}`);u.search=new URLSearchParams({utm_source:d.platform==='meta'?'facebook':d.platform==='google'?'google':'other',utm_medium:'paid',utm_campaign:'k143_'+d.campaign_id.replaceAll('-',''),kl:d.link.code}).toString();
   link={url:u.href,created_at:d.link.created_at};
  }
  return {...d,link};
 };
 app.get(path,owner(async(q,r,u)=>{
  if(Object.keys(q.query).some(k=>k!=='days')||q.query.days!==undefined&&!['7','30','90'].includes(q.query.days))fail('Choose 7, 30 or 90 reporting days.');
  r.json(present(await attribution.command(u,'read',uuid(q.params.id),{campaign_id:uuid(q.params.campaign_id),days:days(Number(q.query.days??30))})));
 },{ratePrefix:'campaign-attribution-read:',max:30}));
 app.post(path+'/link',owner(async(q,r,u)=>{
  if(Object.keys(q.query).length||!q.body||Object.keys(q.body).length!==1||!Object.hasOwn(q.body,'days'))fail('Choose the attribution reporting window.');
  r.json(present(await attribution.command(u,'create_link',uuid(q.params.id),{campaign_id:uuid(q.params.campaign_id),days:days(q.body.days)})));
 },{ratePrefix:'campaign-attribution-link:',max:5}));
}
