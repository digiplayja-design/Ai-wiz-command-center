import {fail,uuid} from './core.mjs';
import {metaConfiguration} from './meta.mjs';

export const metaCreativeCtas=['LEARN_MORE','CONTACT_US','SIGN_UP','SHOP_NOW','GET_QUOTE'];
export function metaCreativeAssets(v) {
  const limits={primary_text:1000,headline:100,description:200,image_alt:180};
  const keys=[...Object.keys(limits),'cta','image_id'];
  if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).length!==keys.length||keys.some(k=>!(k in v)))fail('Enter the Meta ad text, button and image selection.');
  for(const [k,max] of Object.entries(limits)) {
    const s=v[k];
    if(typeof s!=='string'||s!==s.trim()||[...s].length>max||/[\u0000-\u001f\u007f-\u009f\u00ad\u061c\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff\ud800-\udfff]/u.test(s))fail(`Check ${k.replaceAll('_',' ')}. Use plain text within ${max} characters.`);
  }
  if(!metaCreativeCtas.includes(v.cta)||!(v.image_id===null||typeof v.image_id==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(v.image_id))||(v.image_id===null&&v.image_alt!==''))fail('Choose a draft button and a saved image, or remove the image description.');
  return v;
}
export function metaCreativeInput(body) {
  if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).length!==3||Object.keys(body).some(k=>!['version','fingerprint','assets'].includes(k))||!Number.isSafeInteger(body.version)||body.version<0||body.version>2147483647||typeof body.fingerprint!=='string'||!/^[a-f0-9]{64}$/.test(body.fingerprint))fail('Reload this Meta ad draft before saving.');
  return{version:body.version,fingerprint:body.fingerprint,assets:metaCreativeAssets(body.assets)};
}
export function registerMetaCreative(app,{base,owner,database,publicBase,environment}) {
  const config=metaConfiguration(environment),route=base+'/:id/campaigns/:campaign_id/meta-creative';
  const run=action=>owner(async(q,r,u)=>{
    if(Object.keys(q.query).length)fail('Open the Meta ad draft without extra parameters.');
    if(!database)fail('Meta ad draft storage is not configured.',503);
    let root;try{root=new URL(publicBase);}catch{fail('The campaign destination is not configured.',503);}
    if(root.protocol!=='https:'||root.username||root.password||root.search||root.hash)fail('The campaign destination is not configured.',503);
    const data={campaign_id:uuid(q.params.campaign_id),public_base:root.href.replace(/\/$/,''),configured:config.ready,config_hash:config.hash,...(action==='read'?{}:metaCreativeInput(q.body))};
    const {data:result,error}=await database.rpc('korlix_funnel_meta_creative_v1',{p_actor:u,p_action:action,p_funnel:uuid(q.params.id),p_data:data});
    if(error){const status={'42501':403,'P0002':404,'40001':409,'54000':429,'23514':400,'P0001':400}[error.code];fail(status?error.message:'Meta ad draft storage is temporarily unavailable.',status||503);}
    r.json(result);
  },{ratePrefix:'meta-creative:',max:30});
  app.get(route,run('read'));app.post(route+'/save',run('save'));
}
