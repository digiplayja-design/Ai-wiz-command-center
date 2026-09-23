import {fail,uuid} from './core.mjs';
import {googleAdsConfiguration} from './google_ads_provider.mjs';
export function createGooglePreparationStore(database) {
  return {async command(actor,action,funnel,data={}) {
    if(!database)fail('Google Ads setup storage is not configured.',503);
    const {data:result,error}=await database.rpc('korlix_funnel_google_preparation_v1',{p_actor:actor,p_action:action,p_funnel:funnel,p_data:data});
    if(error){const status={'42501':403,'P0002':404,'40001':409,'54000':429,'P0001':400,'23514':400}[error.code];fail(status?error.message:'Google Ads setup storage is temporarily unavailable.',status||503);}
    return result;
  }};
}
export function googlePreparationInput(action,body={}) {
  const keys=action==='review'?['version','fingerprint','confirmed']:['version','confirmed'];
  if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).some(k=>!keys.includes(k))||!Number.isSafeInteger(body.version)||body.version<0||body.version>2147483647||body.confirmed!==true||(action==='review'&&(typeof body.fingerprint!=='string'||! /^[a-f0-9]{64}$/.test(body.fingerprint))))fail('Refresh the Google Ads setup and confirm the displayed review.');
  return {version:body.version,confirmed:true,...(action==='review'?{fingerprint:body.fingerprint}:{})};
}
export function registerGooglePreparation(app,{base,owner,database,googlePreparationStore,environment,publicBase}) {
  const store=googlePreparationStore||createGooglePreparationStore(database),config=googleAdsConfiguration(environment);
  const root=()=>{let u;try{u=new URL(publicBase);}catch{fail('The campaign destination is not configured.',503);}if(u.protocol!=='https:'||u.username||u.password||u.search||u.hash)fail('The campaign destination is not configured.',503);return u.href.replace(/\/$/,'');};
  const route=base+'/:id/campaigns/:campaign_id/google-setup';
  const run=action=>owner(async(q,r,u)=>{
    if(Object.keys(q.query).length)fail('Refresh this campaign’s Google Ads setup without extra parameters.');
    const data={campaign_id:uuid(q.params.campaign_id),configured:config.ready,config_hash:config.hash,public_base:root(),...(action==='read'?{}:googlePreparationInput(action,q.body))};
    r.json(await store.command(u,action,uuid(q.params.id),data));
  },{ratePrefix:'google-setup:',max:30});
  app.get(route,run('read'));
  app.post(route+'/review',run('review'));
  app.post(route+'/clear',run('clear'));
}
