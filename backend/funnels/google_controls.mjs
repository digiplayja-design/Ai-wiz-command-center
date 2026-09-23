import {randomUUID,createHmac,timingSafeEqual} from 'node:crypto';
import {fail,uuid} from './core.mjs';
import {googleAdsConfiguration,googleDigest,googleTokenCipher,createGoogleAdsProvider,GoogleAdsAccessError} from './google_ads_provider.mjs';
import {createGoogleAdsStore} from './google_ads.mjs';
import {creationResources} from './google_paused_provider.mjs';
const keys=(v,k)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).length===k.length&&k.every(x=>Object.hasOwn(v,x));
const sameAccount=(a,b)=>a&&b&&['id','name','currency','timezone','manager','status','test_account'].every(k=>a[k]===b[k]);
const stable=v=>Array.isArray(v)?'['+v.map(stable).join(',')+']':v&&typeof v==='object'?'{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+stable(v[k])).join(',')+'}':JSON.stringify(v);
const digest=v=>googleDigest(stable(v));
export function registerGoogleControls(app,{base,owner,database,environment,publicBase,googleAdsStore,googleAdsProvider,now=Date.now}){
  const config=googleAdsConfiguration(environment),enabled=config.ready&&config.apiVersion==='v25'&&environment.KORLIX_GOOGLE_ADS_CONTROLS_ENABLED==='true';
  const store=googleAdsStore||createGoogleAdsStore(database),provider=googleAdsProvider||createGoogleAdsProvider(config,{now});
  const path=base+'/:id/campaigns/:campaign_id/google-controls';
  const context=q=>{
    let root;try{root=new URL(publicBase);}catch{fail('The campaign destination is not configured.',503);}
    if(root.protocol!=='https:'||root.username||root.password||root.search||root.hash)fail('The campaign destination is not configured.',503);
    return {campaign_id:uuid(q.params.campaign_id),configured:config.ready,config_hash:config.hash,public_base:root.href.replace(/\/$/,''),create_enabled:config.ready&&config.apiVersion==='v25'&&environment.KORLIX_GOOGLE_ADS_CREATE_PAUSED_ENABLED==='true',controls_enabled:enabled};
  };
  const command=async(actor,funnel,action,data)=>{
    if(!database)fail('Google control storage is not configured.',503);
    const {data:out,error}=await database.rpc('korlix_funnel_google_controls_v1',{p_actor:actor,p_action:action,p_funnel:funnel,p_data:data});
    if(error){const status={'42501':403,'P0002':404,'40001':409,'23505':409,'P0001':400,'23514':400}[error.code];fail(status?error.message:'Google control storage is unavailable. Check the saved command record before continuing.',status||503);}return out;
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

  const mac=s=>createHmac('sha256',Buffer.from(config.key,'base64')).update('korlix-google-controls-v1:'+s).digest('base64url');
  function proof(actor,funnel,d,observation){
    const body=Buffer.from(JSON.stringify({actor,funnel,campaign:d.campaign_id,fingerprint:d.fingerprint,observation:digest(observation),expires:now()+300000})).toString('base64url');return body+'.'+mac(body);
  }
  function decode(value,actor,funnel,d){
    if(typeof value!=='string'||value.length>3000||!/^[-_A-Za-z0-9]+\.[-_A-Za-z0-9]{43}$/.test(value))fail('Reload Google status before confirming.',409);
    const [body,signature]=value.split('.'),expected=mac(body);
    if(!timingSafeEqual(Buffer.from(signature),Buffer.from(expected)))fail('Reload Google status before confirming.',409);
    let p;try{p=JSON.parse(Buffer.from(body,'base64url').toString());}catch{fail('Reload Google status before confirming.',409);}
    if(p.actor!==actor||p.funnel!==funnel||p.campaign!==d.campaign_id||p.fingerprint!==d.fingerprint||!Number.isSafeInteger(p.expires)||p.expires<=now()||p.expires>now()+300000)fail('The status confirmation expired or the campaign changed. Reload Google status.',409);
    return p;
  }
  function identity(d){
    const saved=d.creation.attempt,current=d.creation.draft.identity;
    if(!enabled||saved?.state!=='created')fail('Google controls require platform setup and a recorded KORLIX creation.',409);
    const prior=saved.snapshot.identity;
    if(prior.account.id!==current.account?.id||prior.root_id!==current.root_id||prior.login_customer_id!==current.login_customer_id)fail('Select the saved Google account and access manager before controlling this campaign.',409);
    return {snapshot:{...saved.snapshot,identity:current},resources:creationResources(saved.resources,current.account.id)};
  }
  async function inspect(actor,d,access,details){
    const {snapshot:s,resources}=details;
    let status,graph=null,reason=null;
    try{
      status=await provider.createdSearchStatus(access,s,resources);
      if(status?.resource!==resources.campaign||!['ENABLED','PAUSED','REMOVED'].includes(status.status)||typeof status.name!=='string'||status.name.length>1000)fail('Google returned inconsistent campaign status.',503);
      status={resource:status.resource,name:status.name,status:status.status};
      if(status.status==='PAUSED'&&d.activation_ready){
        try{
          graph=await provider.inspectCreatedSearch(access,s,resources);
          if(!graph||digest(graph.resources)!==digest(resources)||graph.policy!=='APPROVED'||graph.statuses?.campaign!=='PAUSED'||!['PAUSED','ENABLED'].includes(graph.statuses?.ad_group)||!['PAUSED','ENABLED'].includes(graph.statuses?.ad))fail('Google campaign structure could not be verified.',409);
          graph={resources:creationResources(graph.resources,s.identity.account.id),statuses:{campaign:graph.statuses.campaign,ad_group:graph.statuses.ad_group,ad:graph.statuses.ad},policy:'APPROVED'};
        }catch(e){if(e instanceof GoogleAdsAccessError)throw e;graph=null;reason='Activation is unavailable: Google must approve the ad, and the saved campaign structure, budget, dates, copy, keywords and targeting must match. Check Google Ads for changes.';}
      }
    }catch(e){await invalidAccess(actor,s.identity,e);throw e;}
    const available=enabled&&d.checks.creation_recorded&&d.checks.no_uncertain_command&&d.checks.command_capacity;
    if(!d.activation_ready&&status.status==='PAUSED')reason='Activation requires current preparation matching the created campaign, an open schedule and no uncertain command.';
    if(d.latest_command?.state==='unknown')reason='A command outcome is uncertain. Ads may be spending. Inspect and control this campaign directly in Google Ads. KORLIX will not send another command; a status observation cannot settle the earlier request.';
    return {status,graph,can_activate:available&&!!graph&&d.activation_ready,can_pause:available&&status.status==='ENABLED',reason};
  }
  app.get(path,owner(async(q,r,u)=>{
    if(Object.keys(q.query).length)fail('Open campaign controls without extra parameters.');
    r.json(publicResult(await command(u,uuid(q.params.id),'read',context(q))));
  },{ratePrefix:'google-controls-read:',max:30}));
  app.post(path+'/inspect',owner(async(q,r,u)=>{
    if(Object.keys(q.query).length||!keys(q.body,[]))fail('Load Google status without extra fields.');
    const funnel=uuid(q.params.id),data=context(q),before=await command(u,funnel,'read',data),details=identity(before),access=await token(u,details.snapshot.identity);
    const observation=await inspect(u,before,access,details);await connection(u,details.snapshot.identity);
    const after=await command(u,funnel,'read',data);if(after.fingerprint!==before.fingerprint)fail('The campaign changed while loading. Reload Google status.',409);
    r.json({...publicResult(after),observation:{...observation,checked_at:new Date(now()).toISOString(),proof:observation.can_activate||observation.can_pause?proof(u,funnel,after,observation):null}});
  },{ratePrefix:'google-controls-inspect:',max:10}));
  app.post(path+'/apply',owner(async(q,r,u)=>{
    const started=now();
    if(Object.keys(q.query).length||!keys(q.body,['proof','action','confirmed','spend_acknowledged'])||!['activate','pause'].includes(q.body.action)||q.body.confirmed!==true||q.body.spend_acknowledged!==(q.body.action==='activate'))fail('Confirm the selected campaign control and its spending impact.');
    const funnel=uuid(q.params.id),data=context(q),before=await command(u,funnel,'read',data),p=decode(q.body.proof,u,funnel,before),details=identity(before),access=await token(u,details.snapshot.identity);
    const observation=await inspect(u,before,access,details),action=q.body.action;
    if(p.observation!==digest(observation)||!observation[action==='activate'?'can_activate':'can_pause'])fail('Google status or eligibility changed. Reload before confirming.',409);
    try{const v=await provider.validateSearchControl(access,details.snapshot,details.resources,action);if(v?.validated!==true)fail('Google did not validate this control.',409);}catch(e){await invalidAccess(u,details.snapshot.identity,e);throw e;}
    // Re-read provider state after validation; Google has no cross-system CAS.
    const rechecked=await inspect(u,before,access,details);
    if(digest(rechecked)!==p.observation)fail('Google details changed during validation. Reload status.',409);
    await connection(u,details.snapshot.identity);
    if(p.expires<=now()||now()-started>75000)fail('The status confirmation expired or took too long. Reload Google status.',409);
    const id=randomUUID(),claimed=await command(u,funnel,'claim',{...data,fingerprint:before.fingerprint,action,confirmed:true,spend_acknowledged:q.body.spend_acknowledged,command_id:id,observed:observation});
    if(claimed.dispatch!==true||claimed.latest_command?.id!==id)fail('The command could not be claimed. Reload its record.',409);
    try{
      if(now()-started>85000)fail('The command claim took too long. Check its saved record.',409);
      const result=await provider.applySearchControl(access,details.snapshot,details.resources,action);
      if(result?.confirmed!==true||result.action!==action)fail('Google did not confirm this control.',409);
      await command(u,funnel,'finish',{...data,command_id:id});
    }catch(e){await invalidAccess(u,details.snapshot.identity,e);return r.json({...publicResult(await command(u,funnel,'read',data)),notice:'The command outcome is uncertain. Ads may be spending. Check and control the campaign directly in Google Ads. KORLIX will not repeat or replace this command.'});}
    r.json({...publicResult(await command(u,funnel,'read',data)),notice:action==='activate'?'Google accepted activation. Delivery may begin within the saved schedule and incur charges. Reload Google status to see a fresh observation.':'Google accepted campaign pause. Earlier delivery and charges may still appear. Reload Google status to see a fresh observation.'});
  },{ratePrefix:'google-controls-write:',max:5}));
}
