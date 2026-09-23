import {fail,uuid} from './core.mjs';
import {radiusAreasValid} from './radius.mjs';
import {metaConfiguration,createMetaStore,createMetaProvider,tokenCipher,MetaAccessError} from './meta.mjs';
import {metaLocationsValid,metaLocationSearchInput,metaLocationIdentity,metaLocationProof,metaLocationProofValid,sameMetaLocation} from './meta_locations.mjs';
import catalog from './meta_targeting_catalog.json' with {type:'json'};
export {catalog as metaTargetingCatalog};
export const metaAdCategories=['UNDECIDED','NONE','HOUSING','EMPLOYMENT','FINANCIAL_PRODUCTS_SERVICES','ISSUES_ELECTIONS_POLITICS','ONLINE_GAMBLING_AND_GAMING'];
export const metaRadiiValid=v=>radiusAreasValid(v,80000);
export function metaTargetingAssets(v) {
  const keys=['countries','age_min','age_max','placements','categories'];
  if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).some(k=>![...keys,'custom_locations','geo_locations'].includes(k))||keys.some(k=>!Object.hasOwn(v,k)))fail('Choose countries, ages, placement and ad categories.');
  const allowed=new Set(catalog.countries.map(x=>x.code));
  if(!Array.isArray(v.countries)||v.countries.length>20||v.countries.some(s=>typeof s!=='string'||!allowed.has(s))||new Set(v.countries).size!==v.countries.length)fail('Choose up to 20 different listed countries.');
  if(Object.hasOwn(v,'custom_locations')&&(!metaRadiiValid(v.custom_locations)||v.countries.length))fail('Choose countries or up to 10 distinct radius areas from 1 to 80 km.');
  if(Object.hasOwn(v,'geo_locations')&&(!metaLocationsValid(v.geo_locations)||v.countries.length||Object.hasOwn(v,'custom_locations')))fail('Choose countries, radius areas or up to 20 distinct Meta cities and regions.');
  if(!Number.isInteger(v.age_min)||!Number.isInteger(v.age_max)||v.age_min<18||v.age_max>65||v.age_max<v.age_min)fail('Choose a draft age range from 18 through 65+.');
  if(!['undecided','automatic','facebook_feed'].includes(v.placements))fail('Choose a listed placement preference.');
  if(!Array.isArray(v.categories)||!v.categories.length||v.categories.length>5||v.categories.some(s=>!metaAdCategories.includes(s))||new Set(v.categories).size!==v.categories.length||v.categories.some(s=>['UNDECIDED','NONE'].includes(s))&&v.categories.length!==1)fail('Choose no special category, choose later, or the applicable special categories.');
  if(!v.categories.includes('NONE')&&(v.age_min!==18||v.age_max!==65))fail('Keep the broad 18–65+ draft range until special-category age eligibility is checked.');
  return v;
}
export function metaTargetingInput(body) {
  if(!body||typeof body!=='object'||Array.isArray(body)||![3,4].includes(Object.keys(body).length)||Object.keys(body).some(k=>!['version','fingerprint','assets','location_proofs'].includes(k))||!Number.isSafeInteger(body.version)||body.version<0||body.version>2147483647||typeof body.fingerprint!=='string'||!/^[a-f0-9]{64}$/.test(body.fingerprint))fail('Reload this targeting draft before saving.');
  const assets=metaTargetingAssets(body.assets),proofs=body.location_proofs;
  if(proofs!==undefined&&(!proofs||typeof proofs!=='object'||Array.isArray(proofs)||!Object.hasOwn(assets,'geo_locations')||Object.keys(proofs).length>20||Object.entries(proofs).some(([k,v])=>!assets.geo_locations.some(x=>metaLocationIdentity(x)===k)||typeof v!=='string'||!/^\d{13}\.[a-f0-9]{64}$/.test(v))))fail('Search again to verify new Meta locations.');
  return{version:body.version,fingerprint:body.fingerprint,assets,...(proofs===undefined?{}:{location_proofs:proofs})};
}
export function metaTargetingReviewInput(action,body) {
  const keys=action==='review'?['version','review_fingerprint','confirmed']:['version','confirmed'];
  if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).length!==keys.length||Object.keys(body).some(k=>!keys.includes(k))||!Number.isSafeInteger(body.version)||body.version<0||body.version>2147483647||body.confirmed!==true||(action==='review'&&(typeof body.review_fingerprint!=='string'||!/^[a-f0-9]{64}$/.test(body.review_fingerprint))))fail('Reload the saved draft and confirm this targeting review.');
  return {version:body.version,confirmed:true,...(action==='review'?{review_fingerprint:body.review_fingerprint}:{})};
}
export function registerMetaTargeting(app,{base,owner,database,publicBase,environment,metaStore,metaProvider,now=Date.now}) {
  const config=metaConfiguration(environment),store=metaStore||createMetaStore(database),provider=metaProvider||createMetaProvider(config,{now});
  const route=base+'/:id/campaigns/:campaign_id/meta-targeting';
  const context=q=>{
    if(!database)fail('Targeting draft storage is not configured.',503);
    let root;try{root=new URL(publicBase);}catch{fail('The campaign destination is not configured.',503);}
    if(root.protocol!=='https:'||root.username||root.password||root.search||root.hash)fail('The campaign destination is not configured.',503);
    return{campaign_id:uuid(q.params.campaign_id),public_base:root.href.replace(/\/$/,''),configured:config.ready,config_hash:config.hash};
  };
  const command=async(u,funnel,action,data)=>{
    const {data:result,error}=await database.rpc('korlix_funnel_meta_targeting_v1',{p_actor:u,p_action:action,p_funnel:funnel,p_data:data});
    if(error){const status={'42501':403,'P0002':404,'40001':409,'54000':429,'23514':400,'P0001':400}[error.code];fail(status?error.message:'Targeting draft storage is temporarily unavailable.',status||503);}
    return result;
  };
  const scope=(u,funnel,data)=>({actor:u,funnel,campaign:data.campaign_id,fingerprint:data.fingerprint});
  const run=action=>owner(async(q,r,u)=>{
    if(Object.keys(q.query).length)fail('Open the targeting draft without extra parameters.');
    const funnel=uuid(q.params.id),data={...context(q),...(action==='read'?{}:action==='save'?metaTargetingInput(q.body):metaTargetingReviewInput(action,q.body))};
    if(action==='save'&&Object.hasOwn(data.assets,'geo_locations')){
      const saved=await command(u,funnel,'read',context(q));
      if(saved.version!==data.version||saved.fingerprint!==data.fingerprint)fail('The targeting draft or Meta context changed. Reload before saving.',409);
      for(const row of data.assets.geo_locations){
        if((saved.assets.geo_locations||[]).some(x=>sameMetaLocation(x,row)))continue;
        if(!config.ready||saved.location_lookup_ready!==true||!metaLocationProofValid(config.secret,scope(u,funnel,data),row,data.location_proofs?.[metaLocationIdentity(row)],now()))fail('A new Meta location could not be verified or its search expired. Remove it and search again.',400);
      }
    }
    delete data.location_proofs; // Receipts are transient, never stored in drafts or reviews.
    r.json(await command(u,funnel,action,data));
  },{ratePrefix:'meta-targeting:',max:30});
  app.get(route,run('read'));app.post(route+'/save',run('save'));
  app.post(route+'/review',run('review'));app.post(route+'/clear-review',run('clear_review'));
  app.get(route+'/locations',owner(async(q,r,u)=>{
    const input=metaLocationSearchInput(q.query),funnel=uuid(q.params.id),data=context(q);
    const before=await command(u,funnel,'read',data);
    if(input.fingerprint!==before.fingerprint)fail('The campaign or Meta connection changed. Reload this draft before searching.',409);
    if(!before.editable)fail('Reopen this campaign before searching locations.',409);
    if(!config.ready||before.location_lookup_ready!==true)fail('Meta location search needs platform setup and a connected, selected active ad account.',409);
    const access=async()=>{
      const c=await store.command(u,'secret');
      const meta=before.creative.setup.current_snapshot.meta;
      if(c.config_hash!==config.hash||c.needs_reconnect||!Number.isFinite(Date.parse(c.expires_at))||Date.parse(c.expires_at)<=now()+60000||c.version!==meta.connection_version||c.selected_account!==meta.account?.id||!c.accounts.some(a=>a.id===c.selected_account&&a.status===1))fail('The Meta connection changed. Reload this draft before searching.',409);
      return c;
    };
    const c=await access(),token=tokenCipher(config.key).open(c.sealed,`korlix-meta:${u}:${c.binding_id}`);
    let result;
    try{result=await provider.locations(token,input);}catch(e){if(e instanceof MetaAccessError)await store.command(u,'invalid',{version:c.version});throw e;}
    const after=await command(u,funnel,'read',data);
    if(after.fingerprint!==before.fingerprint||after.version!==before.version||!after.editable||!after.location_lookup_ready)fail('The draft or Meta connection changed while searching. Reload and try again.',409);
    const latest=await access();
    if(latest.binding_id!==c.binding_id)fail('The draft or Meta connection changed while searching. Reload and try again.',409);
    // Validate injected provider adapters too; never sign arbitrary adapter output.
    if(!result||!Array.isArray(result.locations)||result.locations.length>30||typeof result.more!=='boolean'||!result.locations.every(x=>metaLocationsValid([x])&&x.country===input.country&&(input.kind==='all'||x.type===input.kind))||new Set(result.locations.map(metaLocationIdentity)).size!==result.locations.length)fail('Meta returned inconsistent location results.',503);
    const proofScope=scope(u,funnel,{...data,fingerprint:before.fingerprint});
    r.json({source:'meta_location_search',query:input.q,country:input.country,kind:input.kind,fingerprint:before.fingerprint,more:result.more,locations:result.locations.map(row=>({...row,proof:metaLocationProof(config.secret,proofScope,row,now())}))});
  },{ratePrefix:'meta-targeting:',max:30}));
}
