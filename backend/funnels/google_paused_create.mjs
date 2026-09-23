import {randomUUID} from 'node:crypto';
import {fail,uuid} from './core.mjs';
import {googleAdsConfiguration,googleDigest,googleTokenCipher,createGoogleAdsProvider,GoogleAdsAccessError} from './google_ads_provider.mjs';
import {createGoogleAdsStore} from './google_ads.mjs';
import {googlePausedRequest,creationResources} from './google_paused_provider.mjs';

const keys=(v,expected)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).length===expected.length&&expected.every(k=>Object.hasOwn(v,k));
const hash=v=>typeof v==='string'&&/^[a-f0-9]{64}$/.test(v);
const sameAccount=(a,b)=>a&&b&&['id','name','currency','timezone','manager','status','test_account'].every(k=>a[k]===b[k]);
export function registerGooglePausedCreate(app,{base,owner,database,environment,publicBase,googleAdsStore,googleAdsProvider,now=Date.now}){
  const config=googleAdsConfiguration(environment),enabled=config.ready&&config.apiVersion==='v25'&&environment.KORLIX_GOOGLE_ADS_CREATE_PAUSED_ENABLED==='true';
  const store=googleAdsStore||createGoogleAdsStore(database),provider=googleAdsProvider||createGoogleAdsProvider(config,{now});
  const path=base+'/:id/campaigns/:campaign_id/google-create';
  const context=q=>{
    let root;try{root=new URL(publicBase);}catch{fail('The campaign destination is not configured.',503);}
    if(root.protocol!=='https:'||root.username||root.password||root.search||root.hash)fail('The campaign destination is not configured.',503);
    return {campaign_id:uuid(q.params.campaign_id),configured:config.ready,config_hash:config.hash,public_base:root.href.replace(/\/$/,''),create_enabled:enabled};
  };
  const command=async(actor,funnel,action,data)=>{
    if(!database)fail('Google creation storage is not configured.',503);
    const {data:out,error}=await database.rpc('korlix_funnel_google_create_v1',{p_actor:actor,p_action:action,p_funnel:funnel,p_data:data});
    if(error){const status={'42501':403,'P0002':404,'40001':409,'23505':409,'P0001':400,'23514':400,'22007':400,'22008':400}[error.code];fail(status?error.message:'Google creation storage is temporarily unavailable. Refresh the creation record before continuing.',status||503);}
    return out;
  };
  const publicResult=d=>{const {dispatch,...out}=d;return out;};
  const invalidAccess=async(actor,identity,error)=>{
    if(error instanceof GoogleAdsAccessError)await store.command(actor,'invalid',{version:identity.connection_version}).catch(()=>{});
  };
  async function connection(actor,identity){
    const c=await store.command(actor,'secret');
    if(!config.ready||c.config_hash!==config.hash||c.needs_reconnect||(c.refresh_expires_at!=null&&(!Number.isFinite(Date.parse(c.refresh_expires_at))||Date.parse(c.refresh_expires_at)<=now()+60000))||c.version!==identity.connection_version||c.root_id!==identity.root_id||c.login_customer_id!==identity.login_customer_id||c.selected_account!==identity.account?.id||!Array.isArray(c.roots)||!c.roots.includes(c.root_id)||!Array.isArray(c.accounts)||!sameAccount(c.accounts.find(a=>a.id===c.selected_account),identity.account))fail('The Google account changed. Refresh access and the creation details.',409);
    return c;
  }
  async function token(actor,identity){
    const c=await connection(actor,identity);
    try{
      const refresh=googleTokenCipher(config.key).open(c.sealed,`korlix-google-ads:refresh:${actor}:${c.binding_id}`),access=await provider.refresh(refresh);
      const roots=await provider.roots(access);if(!Array.isArray(roots)||!roots.includes(c.root_id))fail('Google access to the selected account was removed. Refresh account access.',409);
      const a=await provider.account(access,c.selected_account,c.login_customer_id);
      if(!sameAccount(a,identity.account)||a.status!=='ENABLED'||a.manager!==false||a.test_account!==false||a.currency!=='USD')fail('Google account details changed. Refresh the account and review the campaign again.',409);
      await connection(actor,identity);return access;
    }catch(e){
      if(e instanceof GoogleAdsAccessError)await store.command(actor,'invalid',{version:c.version}).catch(()=>{});
      throw e;
    }
  }
  app.get(path,owner(async(q,r,u)=>{
    if(Object.keys(q.query).length)fail('Open creation details without extra parameters.');
    r.json(publicResult(await command(u,uuid(q.params.id),'read',context(q))));
  },{ratePrefix:'google-creation-read:',max:30}));
  app.post(path+'/create',owner(async(q,r,u)=>{
    if(Object.keys(q.query).length||!keys(q.body,['fingerprint','start_date','confirmed','budget_acknowledged','no_eu_political_ads'])||!hash(q.body.fingerprint)||typeof q.body.start_date!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(q.body.start_date)||q.body.confirmed!==true||q.body.budget_acknowledged!==true||q.body.no_eu_political_ads!==true)fail('Review the creation details and confirm the start date, paused state, average budget and political-ad declaration.');
    const funnel=uuid(q.params.id),data=context(q),before=await command(u,funnel,'read',data);
    // Repeated requests only read the durable record, even after a timeout.
    if(before.attempt)return r.json(publicResult(before));
    if(!enabled||!before.create_ready)fail('Paused Google creation is not ready. Complete platform setup and current preparation reviews.',409);
    if(q.body.fingerprint!==before.fingerprint)fail('The campaign or account changed. Reload creation details.',409);
    const start=q.body.start_date,stamp=Date.parse(start+'T00:00:00Z');
    if(!Number.isFinite(stamp)||new Date(stamp).toISOString().slice(0,10)!==start||start<before.today||start>before.latest_start)fail('Choose a start date from today through the next 30 days in the account timezone.');
    const attempt=randomUUID(),snapshot={...before.draft,start_date:start,end_date:new Date(stamp+(before.draft.plan.days-1)*86400000).toISOString().slice(0,10),provider_name:'KORLIX '+attempt,no_eu_political_ads:true,budget_acknowledged:true};
    const requestHash=googleDigest(JSON.stringify(googlePausedRequest(snapshot))),access=await token(u,snapshot.identity);
    let validation;
    try{validation=await provider.validatePausedSearch(access,snapshot);}catch(e){await invalidAccess(u,snapshot.identity,e);throw e;}
    if(validation?.validated!==true)fail('Google did not validate this paused campaign. Refresh before continuing.',409);
    await connection(u,snapshot.identity);
    // SQL checks current entitlement, reviews, calendar and fingerprint again,
    // then atomically claims the only dispatch slot for this plan.
    const claimed=await command(u,funnel,'claim',{...data,...q.body,attempt_id:attempt,request_hash:requestHash});
    if(claimed.dispatch!==true)return r.json(publicResult(claimed));
    if(claimed.attempt?.id!==attempt||googleDigest(JSON.stringify(googlePausedRequest(claimed.attempt.snapshot)))!==requestHash)fail('Creation details changed during confirmation. Refresh the saved creation record.',409);
    try{
      const result=creationResources(await provider.createPausedSearch(access,claimed.attempt.snapshot),snapshot.identity.account.id);
      await command(u,funnel,'finish',{...data,attempt_id:attempt,resources:result});
    }catch(e){
      await invalidAccess(u,snapshot.identity,e);
      // A timeout, malformed response or failed local completion could follow a
      // successful Google commit. Never repeat the mutation or clear this slot.
      const latest=await command(u,funnel,'read',data);
      return r.json({...publicResult(latest),notice:'The creation outcome needs checking. Use Check creation result. KORLIX will not send this campaign again.'});
    }
    r.status(201).json(publicResult(await command(u,funnel,'read',data)));
  },{ratePrefix:'google-creation-write:',max:5}));
  app.post(path+'/reconcile',owner(async(q,r,u)=>{
    if(Object.keys(q.query).length||!keys(q.body,['attempt_id']))fail('Choose the saved creation attempt to check.');
    const attempt=uuid(q.body.attempt_id),funnel=uuid(q.params.id),data=context(q),before=await command(u,funnel,'read',data);
    if(before.attempt?.id!==attempt)fail('The creation record changed. Refresh it.',409);
    if(before.attempt.state==='created')return r.json(publicResult(before));
    const saved=before.attempt.snapshot,current=before.draft.identity;
    if(!sameAccount(saved.identity.account,current.account)||saved.identity.root_id!==current.root_id||saved.identity.login_customer_id!==current.login_customer_id)fail('Select the saved Google account and access manager before checking this creation.',409);
    const access=await token(u,current);let found;
    try{found=await provider.findPausedSearch(access,saved);}catch(e){await invalidAccess(u,current,e);throw e;}
    await connection(u,current);
    if(found){await command(u,funnel,'finish',{...data,attempt_id:attempt,resources:creationResources(found,saved.identity.account.id)});}
    const after=await command(u,funnel,'read',data);
    r.json({...publicResult(after),...(found?{}:{notice:'No matching complete paused campaign was found. This does not prove creation failed. Check Google Ads using the saved creation name; automatic resending remains blocked.'})});
  },{ratePrefix:'google-creation-check:',max:5}));
}
