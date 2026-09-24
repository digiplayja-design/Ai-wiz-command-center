import {randomUUID} from 'node:crypto';
import {fail,uuid} from './core.mjs';
import {metaConfiguration,createMetaStore,createMetaProvider,tokenCipher,MetaAccessError} from './meta.mjs';
import {metaPausedPlan,prepareMetaImage,metaCreationDigest,metaCreationResources,MetaPausedAccessError} from './meta_paused_provider.mjs';
const keys=(v,k)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).length===k.length&&k.every(x=>Object.hasOwn(v,x));
const sameAccount=(a,b)=>a&&b&&['id','name','currency','timezone','status'].every(k=>a[k]===b[k]);
const samePage=(a,b)=>a&&b&&['id','name','category'].every(k=>a[k]===b[k]);
export function registerMetaPausedCreate(app,{base,owner,database,environment,publicBase,metaStore,metaProvider,imageStore,now=Date.now}){
  const config=metaConfiguration(environment),enabled=config.ready&&config.apiVersion==='v26.0'&&environment.KORLIX_META_CREATE_PAUSED_ENABLED==='true';
  const store=metaStore||createMetaStore(database),provider=metaProvider||createMetaProvider(config,{now});
  const path=base+'/:id/campaigns/:campaign_id/meta-create';
  const context=q=>{
    let root;try{root=new URL(publicBase);}catch{fail('The campaign destination is not configured.',503);}
    if(root.protocol!=='https:'||root.username||root.password||root.search||root.hash)fail('The campaign destination is not configured.',503);
    return {campaign_id:uuid(q.params.campaign_id),configured:config.ready,config_hash:config.hash,public_base:root.href.replace(/\/$/,''),create_enabled:enabled};
  };
  const command=async(actor,funnel,action,data)=>{
    if(!database)fail('Meta creation storage is not configured.',503);
    const {data:out,error}=await database.rpc('korlix_funnel_meta_create_v1',{p_actor:actor,p_action:action,p_funnel:funnel,p_data:data});
    if(error){const status={'42501':403,'P0002':404,'40001':409,'23505':409,'P0001':400,'23514':400,'22007':400,'22008':400}[error.code];fail(status?error.message:'Meta creation storage is unavailable. Refresh the saved record before continuing.',status||503);}return out;
  };
  const publicResult=d=>{const {dispatch,proposal,...out}=d;return out;};
  const invalid=async(actor,identity,e)=>{if(e instanceof MetaAccessError||e instanceof MetaPausedAccessError)await store.command(actor,'invalid',{version:identity.connection_version}).catch(()=>{});};
  async function connection(actor,identity){
    const c=await store.command(actor,'secret');
    if(!config.ready||config.apiVersion!=='v26.0'||c.config_hash!==config.hash||c.needs_reconnect||!Number.isFinite(Date.parse(c.expires_at))||Date.parse(c.expires_at)<=now()+60000||c.version!==identity.connection_version||c.selected_account!==identity.account?.id||c.selected_page!==identity.page?.id||c.pages_access_denied||!Array.isArray(c.accounts)||!sameAccount(c.accounts.find(x=>x.id===c.selected_account),identity.account)||!Array.isArray(c.pages)||!samePage(c.pages.find(x=>x.id===c.selected_page),identity.page))fail('The Meta account or Page changed. Refresh access and review the creation details.',409);
    return c;
  }
  async function access(actor,identity){
    const c=await connection(actor,identity),token=tokenCipher(config.key).open(c.sealed,`korlix-meta:${actor}:${c.binding_id}`);
    try{
      const a=await provider.account(token,c.selected_account);if(!sameAccount(a,identity.account)||a.status!==1||a.currency!=='USD')fail('The saved Meta ad account changed or is unavailable. Refresh access and reviews.',409);
      const result=await provider.verifyCreationAccess(token,c.meta_user_id,identity.page);if(result?.verified!==true)fail('Meta advertising and Page permissions could not be verified.',409);
      await connection(actor,identity);return token;
    }catch(e){await invalid(actor,identity,e);throw e;}
  }
  app.get(path,owner(async(q,r,u)=>{
    if(Object.keys(q.query).length)fail('Open Meta creation details without extra parameters.');
    r.json(publicResult(await command(u,uuid(q.params.id),'read',context(q))));
  },{ratePrefix:'meta-creation-read:',max:30}));
  app.post(path+'/create',owner(async(q,r,u)=>{
    const started=now();
    if(Object.keys(q.query).length||!keys(q.body,['fingerprint','start_date','confirmed','budget_acknowledged'])||typeof q.body.fingerprint!=='string'||!/^[a-f0-9]{64}$/.test(q.body.fingerprint)||typeof q.body.start_date!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(q.body.start_date)||q.body.confirmed!==true||q.body.budget_acknowledged!==true)fail('Confirm the saved image upload, paused campaign, schedule and average daily budget.');
    const funnel=uuid(q.params.id),data=context(q),before=await command(u,funnel,'read',data);
    if(before.attempt)return r.json(publicResult(before));
    if(!enabled||!before.create_ready)fail('Paused Meta creation requires platform setup and complete current reviews.',409);
    const start=q.body.start_date,stamp=Date.parse(start+'T00:00:00Z');if(!Number.isFinite(stamp)||new Date(stamp).toISOString().slice(0,10)!==start||start<before.earliest_start||start>before.latest_start)fail('Choose tomorrow through the next 30 days in the account timezone.');
    if(q.body.fingerprint!==before.fingerprint)fail('The campaign or Meta context changed. Reload creation details.',409);
    const id=randomUUID(),prepared=await command(u,funnel,'prepare',{...data,...q.body,attempt_id:id});
    if(prepared.fingerprint!==before.fingerprint||!prepared.proposal)fail('The creation details changed. Reload before confirming.',409);
    const s=prepared.proposal,plan=metaPausedPlan(s),image=await prepareMetaImage(await imageStore.command(u,'get',s.creative.image_id),s);
    const requestHash=metaCreationDigest({plan,image_sha256:image.sha256}),token=await access(u,s.identity);
    try{if((await provider.validatePausedMeta(token,s,{},'campaign'))?.validated!==true)fail('Meta did not validate the paused campaign.',409);}catch(e){await invalid(u,s.identity,e);throw e;}
    await connection(u,s.identity);
    if(now()-started>75000)fail('Confirmation took too long. Reload before creating.',409);
    const claimed=await command(u,funnel,'claim',{...data,...q.body,attempt_id:id,request_hash:requestHash});
    if(claimed.dispatch!==true)return r.json(publicResult(claimed));
    if(claimed.attempt?.id!==id||metaCreationDigest({plan:metaPausedPlan(claimed.attempt.snapshot),image_sha256:image.sha256})!==requestHash)fail('Creation details changed during confirmation. Check the saved record.',409);
    const resources={};
    try{
      for(const stage of ['image_hash','campaign','ad_set','creative','ad']){
        if(now()-started>85000)fail('Creation took too long. Inspect its partial results in Meta.',409);
        // Every further write requires current local access. Historical receipts
        // can still be recorded if access changes while a provider call runs.
        await command(u,funnel,'read',data);await connection(u,s.identity);
        if(stage!=='image_hash'&&stage!=='campaign'&&(await provider.validatePausedMeta(token,s,resources,stage))?.validated!==true)fail('Meta did not validate the next paused resource.',409);
        await connection(u,s.identity);await command(u,funnel,'read',data);
        if(now()-started>85000)fail('Creation took too long. Inspect its partial results in Meta.',409);
        const value=await provider.createPausedMetaResource(token,s,resources,stage,stage==='image_hash'?image.bytes:undefined);
        resources[stage]=value;metaCreationResources(resources);
        await command(u,funnel,'progress',{...data,attempt_id:id,resource:stage,value});
      }
      await command(u,funnel,'finish',{...data,attempt_id:id,resources:metaCreationResources(resources,true)});
    }catch(e){
      await invalid(u,s.identity,e);const latest=await command(u,funnel,'read',data);
      return r.json({...publicResult(latest),notice:latest.attempt?.state==='created'?'Creation was recorded. Check Meta Ads Manager for current status.':'Creation is incomplete or uncertain. Some resources may already exist in Meta. Check the saved resource IDs in Meta Ads Manager. KORLIX will not repeat or continue this attempt; checking the result only reads Meta.'});
    }
    r.status(201).json(publicResult(await command(u,funnel,'read',data)));
  },{ratePrefix:'meta-creation-write:',max:5}));
  app.post(path+'/reconcile',owner(async(q,r,u)=>{
    if(Object.keys(q.query).length||!keys(q.body,['attempt_id']))fail('Choose the saved Meta creation attempt.');
    const id=uuid(q.body.attempt_id),funnel=uuid(q.params.id),data=context(q),before=await command(u,funnel,'read',data);
    if(before.attempt?.id!==id)fail('The creation record changed. Reload it.',409);
    if(before.attempt.state==='created')return r.json(publicResult(before));
    const s=before.attempt.snapshot,current=before.draft.identity;
    if(!sameAccount(s.identity.account,current.account)||!samePage(s.identity.page,current.page))fail('Select the saved Meta account and Page before checking this creation.',409);
    const token=await access(u,current);let found;
    try{found=await provider.findPausedMeta(token,s,metaCreationResources(before.attempt.resources));}catch(e){await invalid(u,current,e);throw e;}
    await connection(u,current);
    const currentRecord=await command(u,funnel,'read',data);if(currentRecord.attempt?.id!==id)fail('The creation record changed. Reload it.',409);
    if(found)await command(u,funnel,'finish',{...data,attempt_id:id,resources:metaCreationResources(found,true)});
    r.json({...publicResult(await command(u,funnel,'read',data)),...(found?{}:{notice:'No complete matching paused campaign was verified. This does not prove that creation failed. Check Meta Ads Manager for partial resources; automatic resending and continuation remain blocked.'})});
  },{ratePrefix:'meta-creation-check:',max:5}));
}
