import {fail,uuid} from './core.mjs';
import {googleRadiiValid} from './google_radius.mjs';
import catalog from './google_targeting_catalog.json' with {type:'json'};
export {catalog as googleTargetingCatalog};
export function googleTargetingAssets(v) {
  const keys=['countries','excluded_countries','content_languages','location_mode','bidding'];
  if(!v||typeof v!=='object'||Array.isArray(v)||keys.some(k=>!Object.hasOwn(v,k))||Object.keys(v).some(k=>!keys.includes(k)&&k!=='proximities'))fail('Choose countries or radius areas, content languages, reach and a bidding preference.');
  if(!['undecided','presence','presence_or_interest'].includes(v.location_mode)||!['undecided','maximize_clicks','maximize_conversions'].includes(v.bidding))fail('Choose a listed location reach and bidding preference.');
  for(const k of keys.slice(0,3)) {
    const a=v[k],allowed=new Set(catalog[k==='content_languages'?'languages':'countries'].map(x=>x.code));
    if(!Array.isArray(a)||a.length>(k==='content_languages'?10:20)||a.some(s=>typeof s!=='string'||!allowed.has(s))||new Set(a).size!==a.length)fail('Choose different listed countries or content languages within the draft limits.');
  }
  if(v.countries.some(s=>v.excluded_countries.includes(s)))fail('A country cannot be both targeted and excluded.');
  if(Object.hasOwn(v,'proximities')&&(!googleRadiiValid(v.proximities)||v.countries.length))fail('Choose up to 10 valid radius areas, with no whole-country targets.');
  return v;
}
export function googleTargetingInput(body) {
  if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).length!==3||Object.keys(body).some(k=>!['version','fingerprint','assets'].includes(k))||!Number.isSafeInteger(body.version)||body.version<0||body.version>2147483647||typeof body.fingerprint!=='string'||!/^[a-f0-9]{64}$/.test(body.fingerprint))fail('Reload this targeting draft before saving.');
  return{version:body.version,fingerprint:body.fingerprint,assets:googleTargetingAssets(body.assets)};
}
export function googleTargetingReviewInput(action,body) {
  const keys=action==='review'?['version','review_fingerprint','confirmed']:['version','confirmed'];
  if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).length!==keys.length||Object.keys(body).some(k=>!keys.includes(k))||!Number.isSafeInteger(body.version)||body.version<0||body.version>2147483647||body.confirmed!==true||(action==='review'&&(typeof body.review_fingerprint!=='string'||!/^[a-f0-9]{64}$/.test(body.review_fingerprint))))fail('Reload the saved draft and confirm this targeting review.');
  return {version:body.version,confirmed:true,...(action==='review'?{review_fingerprint:body.review_fingerprint}:{})};
}
export function registerGoogleTargeting(app,{base,owner,database,publicBase}) {
  const route=base+'/:id/campaigns/:campaign_id/google-targeting';
  const run=action=>owner(async(q,r,u)=>{
    if(Object.keys(q.query).length)fail('Open the targeting draft without extra parameters.');
    if(!database)fail('Targeting draft storage is not configured.',503);
    let root;try{root=new URL(publicBase);}catch{fail('The campaign destination is not configured.',503);}
    if(root.protocol!=='https:'||root.username||root.password||root.search||root.hash)fail('The campaign destination is not configured.',503);
    const data={campaign_id:uuid(q.params.campaign_id),public_base:root.href.replace(/\/$/,''),...(action==='read'?{}:action==='save'?googleTargetingInput(q.body):googleTargetingReviewInput(action,q.body))};
    const {data:result,error}=await database.rpc('korlix_funnel_google_targeting_v1',{p_actor:u,p_action:action,p_funnel:uuid(q.params.id),p_data:data});
    if(error){const status={'42501':403,'P0002':404,'40001':409,'54000':429,'23514':400,'P0001':400}[error.code];fail(status?error.message:'Targeting draft storage is temporarily unavailable.',status||503);}
    r.json(result);
  },{ratePrefix:'google-targeting:',max:30});
  app.get(route,run('read'));app.post(route+'/save',run('save'));
  app.post(route+'/review',run('review'));app.post(route+'/clear-review',run('clear_review'));
}
