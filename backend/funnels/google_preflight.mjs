import {fail,uuid} from './core.mjs';
import {googleAdsConfiguration} from './google_ads_provider.mjs';
export function registerGooglePreflight(app,{base,owner,database,environment,publicBase}) {
  const config=googleAdsConfiguration(environment);
  app.get(base+'/:id/campaigns/:campaign_id/google-preflight',owner(async(q,r,u)=>{
    if(Object.keys(q.query).length)fail('Refresh the preparation checklist without extra parameters.');
    if(!database)fail('Preparation checklist storage is not configured.',503);
    let root;try{root=new URL(publicBase);}catch{fail('The campaign destination is not configured.',503);}
    if(root.protocol!=='https:'||root.username||root.password||root.search||root.hash)fail('The campaign destination is not configured.',503);
    const {data,error}=await database.rpc('korlix_funnel_google_preflight_v1',{p_actor:u,p_action:'read',p_funnel:uuid(q.params.id),p_data:{campaign_id:uuid(q.params.campaign_id),configured:config.ready,config_hash:config.hash,public_base:root.href.replace(/\/$/,'')}});
    if(error){const status={'42501':403,'P0002':404,'P0001':400}[error.code];fail(status?error.message:'Preparation checklist storage is temporarily unavailable.',status||503);}
    r.json(data);
  },{ratePrefix:'google-preflight:',max:30}));
}
