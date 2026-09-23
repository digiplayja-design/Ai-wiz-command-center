import {fail,uuid} from './core.mjs';
export const googleDraftUnits=value=>[...value].reduce((n,c)=>n+(c.codePointAt(0)>127?2:1),0);
export function googleCreativeAssets(v) {
  const keys=['headlines','descriptions','path1','path2'];
  if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).length!==4||keys.some(k=>!(k in v)))fail('Enter headlines, descriptions and both display paths.');
  const plain=(s,limit,path=false)=>typeof s==='string'&&s===s.trim()&&!/[\p{Cc}\p{Cf}\p{Cs}\u2028\u2029{}]/u.test(s)&&googleDraftUnits(s)<=limit&&(!path||!/[\s/\\?#]/u.test(s));
  for(const [k,max,limit] of [['headlines',15,30],['descriptions',4,90]]) {
    if(!Array.isArray(v[k])||v[k].length>max||v[k].some(s=>!plain(s,limit)||!s)||new Set(v[k].map(s=>s.toLowerCase())).size!==v[k].length)fail(`Use up to ${max} different ${k}, each within ${limit} draft characters.`);
  }
  if(!plain(v.path1,15,true)||!plain(v.path2,15,true)||(!v.path1&&v.path2))fail('Use display paths of up to 15 draft characters without spaces, slashes or URL punctuation. Add path 1 before path 2.');
  return v;
}
export function googleCreativeInput(body) {
  if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).length!==3||Object.keys(body).some(k=>!['version','fingerprint','assets'].includes(k))||!Number.isSafeInteger(body.version)||body.version<0||body.version>2147483647||typeof body.fingerprint!=='string'||!/^[a-f0-9]{64}$/.test(body.fingerprint))fail('Reload this search-ad draft before saving.');
  return{version:body.version,fingerprint:body.fingerprint,assets:googleCreativeAssets(body.assets)};
}
export function googleCreativeReviewInput(action,body) {
  const keys=action==='review'?['version','review_fingerprint','confirmed']:['version','confirmed'];
  if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).length!==keys.length||Object.keys(body).some(k=>!keys.includes(k))||!Number.isSafeInteger(body.version)||body.version<0||body.version>2147483647||body.confirmed!==true||(action==='review'&&(typeof body.review_fingerprint!=='string'||!/^[a-f0-9]{64}$/.test(body.review_fingerprint))))fail('Reload the saved draft and confirm this copy review.');
  return {version:body.version,confirmed:true,...(action==='review'?{review_fingerprint:body.review_fingerprint}:{})};
}
export function registerGoogleCreative(app,{base,owner,database,publicBase}) {
  const route=base+'/:id/campaigns/:campaign_id/google-creative';
  const run=action=>owner(async(q,r,u)=>{
    if(Object.keys(q.query).length)fail('Open the search-ad draft without extra parameters.');
    if(!database)fail('Search-ad draft storage is not configured.',503);
    let root;try{root=new URL(publicBase);}catch{fail('The campaign destination is not configured.',503);}
    if(root.protocol!=='https:'||root.username||root.password||root.search||root.hash)fail('The campaign destination is not configured.',503);
    const data={campaign_id:uuid(q.params.campaign_id),public_base:root.href.replace(/\/$/,''),...(action==='read'?{}:action==='save'?googleCreativeInput(q.body):googleCreativeReviewInput(action,q.body))};
    const {data:result,error}=await database.rpc('korlix_funnel_google_creative_v1',{p_actor:u,p_action:action,p_funnel:uuid(q.params.id),p_data:data});
    if(error){const status={'42501':403,'P0002':404,'40001':409,'54000':429,'23514':400,'P0001':400}[error.code];fail(status?error.message:'Search-ad draft storage is temporarily unavailable.',status||503);}
    r.json(result);
  },{ratePrefix:'google-creative:',max:30});
  app.get(route,run('read'));app.post(route+'/save',run('save'));
  app.post(route+'/review',run('review'));app.post(route+'/clear-review',run('clear_review'));
}
