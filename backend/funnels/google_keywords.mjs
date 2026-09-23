import {fail,uuid} from './core.mjs';
export const googleKeywordGroups=['exact','phrase','broad','negative_exact','negative_phrase','negative_broad'];
export function googleKeywordsAssets(v) {
  if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).length!==6||googleKeywordGroups.some(k=>!(k in v)))fail('Enter the six keyword match-type lists.');
  let positive=0,negative=0;
  for(const k of googleKeywordGroups) {
    const a=v[k];
    if(!Array.isArray(a)||a.length>50||a.some(s=>typeof s!=='string'||!s||s!==s.trim()||[...s].length>80||s.split(' ').length>10||s.includes('  ')||/[\p{Cc}\p{Cf}\p{Cs}\u2028\u2029!@%^=;<>?,{}\[\]"\\+*/:|()#$]/u.test(s)||/[^\S ]/u.test(s))||new Set(a.map(s=>s.toLowerCase())).size!==a.length)fail('Use different plain keywords within each match type, at most 80 characters and 10 words each. Do not add match-type brackets, quotes or operators.');
    if(k.startsWith('negative_'))negative+=a.length;else positive+=a.length;
  }
  if(positive>50||negative>50)fail('Use up to 50 positive keywords and 50 negative keywords per draft.');
  return v;
}
export function googleKeywordsInput(body) {
  if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).length!==3||Object.keys(body).some(k=>!['version','fingerprint','assets'].includes(k))||!Number.isSafeInteger(body.version)||body.version<0||body.version>2147483647||typeof body.fingerprint!=='string'||!/^[a-f0-9]{64}$/.test(body.fingerprint))fail('Reload this keyword draft before saving.');
  return{version:body.version,fingerprint:body.fingerprint,assets:googleKeywordsAssets(body.assets)};
}
export function registerGoogleKeywords(app,{base,owner,database,publicBase}) {
  const route=base+'/:id/campaigns/:campaign_id/google-keywords';
  const run=action=>owner(async(q,r,u)=>{
    if(Object.keys(q.query).length)fail('Open the keyword draft without extra parameters.');
    if(!database)fail('Keyword draft storage is not configured.',503);
    let root;try{root=new URL(publicBase);}catch{fail('The campaign destination is not configured.',503);}
    if(root.protocol!=='https:'||root.username||root.password||root.search||root.hash)fail('The campaign destination is not configured.',503);
    const data={campaign_id:uuid(q.params.campaign_id),public_base:root.href.replace(/\/$/,''),...(action==='read'?{}:googleKeywordsInput(q.body))};
    const {data:result,error}=await database.rpc('korlix_funnel_google_keywords_v1',{p_actor:u,p_action:action,p_funnel:uuid(q.params.id),p_data:data});
    if(error){const status={'42501':403,'P0002':404,'40001':409,'54000':429,'23514':400,'P0001':400}[error.code];fail(status?error.message:'Keyword draft storage is temporarily unavailable.',status||503);}
    r.json(result);
  },{ratePrefix:'google-keywords:',max:30});
  app.get(route,run('read'));app.post(route+'/save',run('save'));
}
