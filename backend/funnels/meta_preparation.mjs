import {fail,uuid} from './core.mjs';
import {metaConfiguration} from './meta.mjs';
export function createMetaPreparationStore(database) {
  return {async command(actor,action,funnel,data={}) {
    if(!database)fail('Meta setup storage is not configured.',503);
    const {data:result,error}=await database.rpc('korlix_funnel_meta_preparation_v1',{p_actor:actor,p_action:action,p_funnel:funnel,p_data:data});
    if(error){const status={'42501':403,'P0002':404,'40001':409,'54000':429,'P0001':400,'23514':400}[error.code];fail(status?error.message:'Meta setup storage is temporarily unavailable.',status||503);}
    return result;
  }};
}
export function metaPreparationInput(action,body={}) {
  const keys=action==='review'?['version','fingerprint','confirmed']:['version','confirmed'];
  if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).some(k=>!keys.includes(k))||!Number.isSafeInteger(body.version)||body.version<0||body.version>2147483647||body.confirmed!==true||(action==='review'&&(typeof body.fingerprint!=='string'||! /^[a-f0-9]{64}$/.test(body.fingerprint))))fail('Refresh the Meta setup and confirm the displayed review.');
  return {version:body.version,confirmed:true,...(action==='review'?{fingerprint:body.fingerprint}:{})};
}
export function registerMetaPreparation(app,{base,owner,database,metaPreparationStore,environment,publicBase}) {
  const store=metaPreparationStore||createMetaPreparationStore(database),config=metaConfiguration(environment);
  const root=()=>{let u;try{u=new URL(publicBase);}catch{fail('The campaign destination is not configured.',503);}if(u.protocol!=='https:'||u.username||u.password||u.search||u.hash)fail('The campaign destination is not configured.',503);return u.href.replace(/\/$/,'');};
  const route=base+'/:id/campaigns/:campaign_id/meta-setup';
  const run=action=>owner(async(q,r,u)=>{
    if(Object.keys(q.query).length)fail('Refresh this campaign’s Meta setup without extra parameters.');
    const data={campaign_id:uuid(q.params.campaign_id),configured:config.ready,config_hash:config.hash,public_base:root(),...(action==='read'?{}:metaPreparationInput(action,q.body))};
    r.json(await store.command(u,action,uuid(q.params.id),data));
  },{ratePrefix:'meta-setup:',max:30});
  app.get(route,run('read'));
  app.post(route+'/review',run('review'));
  app.post(route+'/clear',run('clear'));
}
