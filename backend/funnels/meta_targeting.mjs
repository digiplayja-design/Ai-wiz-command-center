import {fail,uuid} from './core.mjs';
import {metaConfiguration} from './meta.mjs';
import catalog from './meta_targeting_catalog.json' with {type:'json'};
export {catalog as metaTargetingCatalog};
export const metaAdCategories=['UNDECIDED','NONE','HOUSING','EMPLOYMENT','FINANCIAL_PRODUCTS_SERVICES','ISSUES_ELECTIONS_POLITICS','ONLINE_GAMBLING_AND_GAMING'];
export function metaTargetingAssets(v) {
  const keys=['countries','age_min','age_max','placements','categories'];
  if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).length!==5||keys.some(k=>!(k in v)))fail('Choose countries, ages, placement and ad categories.');
  const allowed=new Set(catalog.countries.map(x=>x.code));
  if(!Array.isArray(v.countries)||v.countries.length>20||v.countries.some(s=>typeof s!=='string'||!allowed.has(s))||new Set(v.countries).size!==v.countries.length)fail('Choose up to 20 different listed countries.');
  if(!Number.isInteger(v.age_min)||!Number.isInteger(v.age_max)||v.age_min<18||v.age_max>65||v.age_max<v.age_min)fail('Choose a draft age range from 18 through 65+.');
  if(!['undecided','automatic','facebook_feed'].includes(v.placements))fail('Choose a listed placement preference.');
  if(!Array.isArray(v.categories)||!v.categories.length||v.categories.length>5||v.categories.some(s=>!metaAdCategories.includes(s))||new Set(v.categories).size!==v.categories.length||v.categories.some(s=>['UNDECIDED','NONE'].includes(s))&&v.categories.length!==1)fail('Choose no special category, choose later, or the applicable special categories.');
  if(!v.categories.includes('NONE')&&(v.age_min!==18||v.age_max!==65))fail('Keep the broad 18–65+ draft range until special-category age eligibility is checked.');
  return v;
}
export function metaTargetingInput(body) {
  if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).length!==3||Object.keys(body).some(k=>!['version','fingerprint','assets'].includes(k))||!Number.isSafeInteger(body.version)||body.version<0||body.version>2147483647||typeof body.fingerprint!=='string'||!/^[a-f0-9]{64}$/.test(body.fingerprint))fail('Reload this targeting draft before saving.');
  return{version:body.version,fingerprint:body.fingerprint,assets:metaTargetingAssets(body.assets)};
}
export function metaTargetingReviewInput(action,body) {
  const keys=action==='review'?['version','review_fingerprint','confirmed']:['version','confirmed'];
  if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).length!==keys.length||Object.keys(body).some(k=>!keys.includes(k))||!Number.isSafeInteger(body.version)||body.version<0||body.version>2147483647||body.confirmed!==true||(action==='review'&&(typeof body.review_fingerprint!=='string'||!/^[a-f0-9]{64}$/.test(body.review_fingerprint))))fail('Reload the saved draft and confirm this targeting review.');
  return {version:body.version,confirmed:true,...(action==='review'?{review_fingerprint:body.review_fingerprint}:{})};
}
export function registerMetaTargeting(app,{base,owner,database,publicBase,environment}) {
  const config=metaConfiguration(environment);
  const route=base+'/:id/campaigns/:campaign_id/meta-targeting';
  const run=action=>owner(async(q,r,u)=>{
    if(Object.keys(q.query).length)fail('Open the targeting draft without extra parameters.');
    if(!database)fail('Targeting draft storage is not configured.',503);
    let root;try{root=new URL(publicBase);}catch{fail('The campaign destination is not configured.',503);}
    if(root.protocol!=='https:'||root.username||root.password||root.search||root.hash)fail('The campaign destination is not configured.',503);
    const data={campaign_id:uuid(q.params.campaign_id),public_base:root.href.replace(/\/$/,''),configured:config.ready,config_hash:config.hash,...(action==='read'?{}:action==='save'?metaTargetingInput(q.body):metaTargetingReviewInput(action,q.body))};
    const {data:result,error}=await database.rpc('korlix_funnel_meta_targeting_v1',{p_actor:u,p_action:action,p_funnel:uuid(q.params.id),p_data:data});
    if(error){const status={'42501':403,'P0002':404,'40001':409,'54000':429,'23514':400,'P0001':400}[error.code];fail(status?error.message:'Targeting draft storage is temporarily unavailable.',status||503);}
    r.json(result);
  },{ratePrefix:'meta-targeting:',max:30});
  app.get(route,run('read'));app.post(route+'/save',run('save'));
  app.post(route+'/review',run('review'));app.post(route+'/clear-review',run('clear_review'));
}
