import {randomUUID,createHmac,timingSafeEqual} from 'node:crypto';
import {fail,uuid} from './core.mjs';
import {metaConfiguration,createMetaStore,createMetaProvider,tokenCipher,MetaAccessError} from './meta.mjs';
import {metaCreationDigest as digest,metaCreationResources,MetaPausedAccessError} from './meta_paused_provider.mjs';
const keys=(v,k)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).length===k.length&&k.every(x=>Object.hasOwn(v,x));
const sameAccount=(a,b)=>a&&b&&['id','name','currency','timezone','status'].every(k=>a[k]===b[k]);
const accessError=e=>e instanceof MetaAccessError||e instanceof MetaPausedAccessError;
export function registerMetaControls(app,{base,owner,database,environment,publicBase,metaStore,metaProvider,now=Date.now}){
 const config=metaConfiguration(environment),enabled=config.ready&&config.apiVersion==='v26.0'&&environment.KORLIX_META_CONTROLS_ENABLED==='true';
 const budgetEnabled=enabled&&environment.KORLIX_META_BUDGET_ENABLED==='true';
 const store=metaStore||createMetaStore(database),provider=metaProvider||createMetaProvider(config,{now}),path=base+'/:id/campaigns/:campaign_id/meta-controls';
 const context=q=>{
  let root;try{root=new URL(publicBase);}catch{fail('The campaign destination is not configured.',503);}
  if(root.protocol!=='https:'||root.username||root.password||root.search||root.hash)fail('The campaign destination is not configured.',503);
  return {campaign_id:uuid(q.params.campaign_id),configured:config.ready,config_hash:config.hash,public_base:root.href.replace(/\/$/,''),create_enabled:config.ready&&config.apiVersion==='v26.0'&&environment.KORLIX_META_CREATE_PAUSED_ENABLED==='true',controls_enabled:enabled,budget_enabled:budgetEnabled};
 };
 const command=async(actor,funnel,action,data)=>{
  if(!database)fail('Meta control storage is not configured.',503);
  const {data:out,error}=await database.rpc('korlix_funnel_meta_controls_v1',{p_actor:actor,p_action:action,p_funnel:funnel,p_data:data});
  if(error){const status={'42501':403,'P0002':404,'40001':409,'23505':409,'P0001':400,'23514':400}[error.code];fail(status?error.message:'Meta control storage is unavailable. Refresh the command record before continuing.',status||503);}return out;
 };
 const publicResult=d=>{const {dispatch,...out}=d;return out;};
 const invalid=async(actor,identity,e)=>{if(accessError(e))await store.command(actor,'invalid',{version:identity.connection_version}).catch(()=>{});};
 async function connection(actor,identity){
  const c=await store.command(actor,'secret');
  if(!config.ready||c.config_hash!==config.hash||c.needs_reconnect||!Number.isFinite(Date.parse(c.expires_at))||Date.parse(c.expires_at)<=now()+60000||c.version!==identity.connection_version||c.selected_account!==identity.account?.id||!Array.isArray(c.accounts)||!sameAccount(c.accounts.find(a=>a.id===c.selected_account),identity.account))fail('The Meta account changed. Refresh access and reload status.',409);
  return c;
 }
 async function token(actor,identity){
  const c=await connection(actor,identity),value=tokenCipher(config.key).open(c.sealed,`korlix-meta:${actor}:${c.binding_id}`);
  try{
   const a=await provider.account(value,c.selected_account);if(!sameAccount(a,identity.account)||a.status!==1||a.currency!=='USD')fail('The saved Meta account changed or is unavailable. Refresh its access.',409);
   if((await provider.verifyMetaControlAccess(value,c.meta_user_id))?.verified!==true)fail('Meta advertising management access could not be verified.',409);
   await connection(actor,identity);return {value,user:c.meta_user_id};
  }catch(e){await invalid(actor,identity,e);throw e;}
 }
 const mac=s=>createHmac('sha256',Buffer.from(config.key,'base64')).update('korlix-meta-controls-v1:'+s).digest('base64url');
 function proof(actor,funnel,d,observation){const body=Buffer.from(JSON.stringify({actor,funnel,campaign:d.campaign_id,fingerprint:d.fingerprint,observation:digest(observation),expires:now()+300000})).toString('base64url');return body+'.'+mac(body);}
 function decode(value,actor,funnel,d){
  if(typeof value!=='string'||value.length>3000||!/^[-_A-Za-z0-9]+\.[-_A-Za-z0-9]{43}$/.test(value))fail('Reload Meta status before confirming.',409);
  const [body,signature]=value.split('.');if(!timingSafeEqual(Buffer.from(signature),Buffer.from(mac(body))))fail('Reload Meta status before confirming.',409);
  let p;try{p=JSON.parse(Buffer.from(body,'base64url').toString());}catch{fail('Reload Meta status before confirming.',409);}
  if(p.actor!==actor||p.funnel!==funnel||p.campaign!==d.campaign_id||p.fingerprint!==d.fingerprint||!Number.isSafeInteger(p.expires)||p.expires<=now()||p.expires>now()+300000)fail('The confirmation expired or the campaign changed. Reload Meta status.',409);return p;
 }
 function identity(d){
  const saved=d.creation.attempt,current=d.creation.draft.identity;
  if(!enabled||saved?.state!=='created')fail('Meta controls require platform setup and a recorded KORLIX creation.',409);
  if(saved.snapshot.identity.account.id!==current.account?.id)fail('Select the saved Meta ad account before controlling this campaign.',409);
  const cents=d.managed_budget?.daily_cents??saved.snapshot.plan.daily_cents;
  if(!Number.isSafeInteger(cents)||cents<100||cents>1000000)fail('The saved Meta budget could not be verified.',503);
  return {identity:current,snapshot:{...saved.snapshot,plan:{...saved.snapshot.plan,daily_cents:cents,planned_total_cents:cents*saved.snapshot.plan.days},identity:{...current,page:saved.snapshot.identity.page}},resources:metaCreationResources(saved.resources,true)};
 }
 function graph(g,r){
  if(!g||digest(g.resources)!==digest(r)||!keys(g.statuses,['campaign','ad_set','ad'])||Object.values(g.statuses).some(v=>!['PAUSED','ACTIVE'].includes(v))||!keys(g.effective_statuses,['campaign','ad_set','ad'])||Object.values(g.effective_statuses).some(v=>!['PAUSED','ACTIVE','CAMPAIGN_PAUSED','ADSET_PAUSED','PENDING_REVIEW','IN_PROCESS','PREAPPROVED'].includes(v)))fail('Meta campaign details could not be verified.',409);
  return {resources:r,statuses:{...g.statuses},effective_statuses:{...g.effective_statuses}};
 }
 async function inspect(actor,d,auth,details,verifyPage=true){
  let status,g=null,reason=null;
  try{
   const s=await provider.createdMetaStatus(auth.value,details.snapshot,details.resources);
   if(s?.resource!==details.resources.campaign||!['ACTIVE','PAUSED','ARCHIVED','DELETED'].includes(s.status)||typeof s.name!=='string'||s.name.length>1000||typeof s.effective_status!=='string'||!/^[A-Z_]{1,40}$/.test(s.effective_status))fail('Meta returned inconsistent campaign status.',503);
   status={resource:s.resource,name:s.name,status:s.status,effective_status:s.effective_status};
   if(s.status==='PAUSED'&&d.activation_ready){
    try{
     if(verifyPage&&(await provider.verifyCreationAccess(auth.value,auth.user,details.identity.page))?.verified!==true)fail('Meta Page advertising access could not be verified.',409);
     g=graph(await provider.inspectCreatedMeta(auth.value,details.snapshot,details.resources),details.resources);
     if(g.statuses.campaign!=='PAUSED'||g.effective_statuses.campaign!==s.effective_status)fail('Meta campaign status changed. Reload it.',409);
    }catch(e){if(accessError(e))throw e;g=null;reason='Activation is unavailable: verify Page advertising permissions and resolve changed content, budget, targeting, schedule or reported ad issues in Meta Ads Manager.';}
   }
  }catch(e){await invalid(actor,details.identity,e);throw e;}
  const available=enabled&&d.checks.creation_recorded&&d.checks.no_uncertain_command&&d.checks.command_capacity;
  if(!d.activation_ready&&status.status==='PAUSED')reason='Activation requires current reviews matching the created campaign and Page, an open schedule and no uncertain command.';
  if(d.latest_command?.state==='unknown')reason='A command outcome is uncertain. Ads may be spending. Inspect and control this campaign directly in Meta Ads Manager. KORLIX will not send another command; a status observation cannot settle the earlier request.';
  return {status,graph:g,can_activate:available&&!!g&&d.activation_ready,can_pause:available&&status.status==='ACTIVE',reason};
 }
 app.get(path,owner(async(q,r,u)=>{
  if(Object.keys(q.query).length)fail('Open Meta controls without extra parameters.');
  r.json(publicResult(await command(u,uuid(q.params.id),'read',context(q))));
 },{ratePrefix:'meta-controls-read:',max:30}));
 app.post(path+'/inspect',owner(async(q,r,u)=>{
  if(Object.keys(q.query).length||!keys(q.body,[]))fail('Load Meta status without extra fields.');
  const funnel=uuid(q.params.id),data=context(q),before=await command(u,funnel,'read',data),details=identity(before),auth=await token(u,details.identity);
  const observation=await inspect(u,before,auth,details);await connection(u,details.identity);
  const after=await command(u,funnel,'read',data);if(after.fingerprint!==before.fingerprint)fail('The campaign changed while loading. Reload Meta status.',409);
  r.json({...publicResult(after),observation:{...observation,checked_at:new Date(now()).toISOString(),proof:observation.can_activate||observation.can_pause?proof(u,funnel,after,observation):null}});
 },{ratePrefix:'meta-controls-inspect:',max:10}));
 app.post(path+'/apply',owner(async(q,r,u)=>{
  const started=now();
  if(Object.keys(q.query).length||!keys(q.body,['proof','action','confirmed','spend_acknowledged'])||!['activate','pause'].includes(q.body.action)||q.body.confirmed!==true||q.body.spend_acknowledged!==(q.body.action==='activate'))fail('Confirm the selected Meta command and its spending impact.');
  const funnel=uuid(q.params.id),data=context(q),before=await command(u,funnel,'read',data),p=decode(q.body.proof,u,funnel,before),details=identity(before),auth=await token(u,details.identity),action=q.body.action;
  const observation=await inspect(u,before,auth,details);
  if(p.observation!==digest(observation)||!observation[action==='activate'?'can_activate':'can_pause'])fail('Meta status or eligibility changed. Reload before confirming.',409);
  const steps=action==='pause'?['campaign']:['ad','ad_set','campaign'].filter(k=>observation.graph.statuses[k]==='PAUSED');
  try{for(const stage of steps)if((await provider.validateMetaControl(auth.value,details.snapshot,details.resources,action,stage))?.validated!==true)fail('Meta did not validate the selected status command.',409);}catch(e){await invalid(u,details.identity,e);throw e;}
  if(digest(await inspect(u,before,auth,details,false))!==p.observation)fail('Meta details changed during validation. Reload status.',409);
  await connection(u,details.identity);
  if(p.expires<=now()||now()-started>75000)fail('Confirmation expired or took too long. Reload Meta status.',409);
  const id=randomUUID(),claimed=await command(u,funnel,'claim',{...data,fingerprint:before.fingerprint,action,confirmed:true,spend_acknowledged:q.body.spend_acknowledged,command_id:id,observed:observation});
  if(claimed.dispatch!==true||claimed.latest_command?.id!==id||digest(claimed.latest_command.steps)!==digest(steps))fail('The command claim could not be verified. Refresh its record.',409);
  const expected=observation.graph?{...observation.graph.statuses}:null;
  try{
   for(const stage of steps){
    if(now()-started>85000)fail('Command took too long. Inspect its partial results in Meta.',409);
    let local=await command(u,funnel,'read',data);await connection(u,details.identity);
    if(local.latest_command?.id!==id||local.latest_command.state!=='unknown')fail('The command record changed.',409);
    if(action==='activate'){
     for(const key of ['platform_enabled','creation_recorded','preparation_current','saved_content_current','identity_current','schedule_open'])if(local.checks[key]!==true)fail('Activation eligibility changed. Check Meta directly.',409);
     if(local.creation.fingerprint!==before.creation.fingerprint)fail('The saved preparation changed. Check Meta directly.',409);
     const g=graph(await provider.inspectCreatedMeta(auth.value,details.snapshot,details.resources),details.resources);
     if(digest(g.statuses)!==digest(expected))fail('Meta status changed between activation steps. Check Meta directly.',409);
    }else{
     const s=await provider.createdMetaStatus(auth.value,details.snapshot,details.resources);if(s?.resource!==details.resources.campaign||s.status!=='ACTIVE')fail('Meta campaign status changed before pause.',409);
    }
    // Repeat the local snapshot check after the final provider read.
    const again=await command(u,funnel,'read',data);await connection(u,details.identity);
    if(again.fingerprint!==local.fingerprint||now()-started>85000)fail('The campaign changed or the command took too long.',409);
    const result=await provider.applyMetaControlStage(auth.value,details.snapshot,details.resources,action,stage);
    const target=action==='activate'?'ACTIVE':'PAUSED';
    if(result?.confirmed!==true||result.stage!==stage||result.resource!==details.resources[stage]||result.status!==target)fail('Meta did not confirm the exact status change.',409);
    await command(u,funnel,'progress',{...data,command_id:id,stage,resource:result.resource,status:target});
    if(expected)expected[stage]=target;
   }
   await command(u,funnel,'finish',{...data,command_id:id});
  }catch(e){await invalid(u,details.identity,e);return r.json({...publicResult(await command(u,funnel,'read',data)),notice:'The command is incomplete or uncertain. Some statuses may have changed and ads may be spending. Check and control the campaign directly in Meta Ads Manager. KORLIX will not retry, resume or replace this command.'});}
  r.json({...publicResult(await command(u,funnel,'read',data)),notice:action==='activate'?'Meta accepted the requested activation steps. Delivery can incur charges within the saved schedule; Meta review and eligibility still apply. Reload status for a fresh observation.':'Meta accepted campaign pause. Earlier delivery and charges may still appear. Reload status for a fresh observation.'});
 },{ratePrefix:'meta-controls-write:',max:5}));

 const validBudget=v=>Number.isSafeInteger(v)&&v>=100&&v<=1000000;
 async function inspectBudget(actor,d,auth,details,cents,claimed=false){
  if(!budgetEnabled||d.budget_enabled!==true||!validBudget(cents)||cents===details.snapshot.plan.daily_cents||!claimed&&(!d.checks.no_uncertain_command||!d.checks.command_capacity))fail('Budget changes are unavailable, unchanged, or a command is uncertain.',409);
  const increase=cents>details.snapshot.plan.daily_cents;
  if(increase&&['platform_enabled','creation_recorded','preparation_current','saved_content_current','identity_current','schedule_open'].some(k=>d.checks[k]!==true))fail('A budget increase requires current reviews matching the saved campaign and an open schedule.',409);
  try{
   const b=await provider.inspectMetaBudget(auth.value,details.snapshot,details.resources);
   if(b?.status?.resource!==details.resources.campaign||b.status.name!==details.snapshot.provider_name+' Campaign'||!['PAUSED','ACTIVE'].includes(b.status.status)||typeof b.status.effective_status!=='string'||!/^[A-Z_]{1,40}$/.test(b.status.effective_status)||b.budget?.resource!==details.resources.ad_set||b.budget.daily_cents!==details.snapshot.plan.daily_cents||!['PAUSED','ACTIVE'].includes(b.budget.status)||typeof b.budget.effective_status!=='string'||!/^[A-Z_]{1,40}$/.test(b.budget.effective_status))fail('Meta budget details changed or could not be verified. Check Meta Ads Manager.',409);
   let g=null;
   if(increase){
    if((await provider.verifyCreationAccess(auth.value,auth.user,details.identity.page))?.verified!==true)fail('Meta Page advertising access could not be verified.',409);
    g=graph(await provider.inspectCreatedMeta(auth.value,details.snapshot,details.resources),details.resources);
    if(g.statuses.campaign!==b.status.status||g.effective_statuses.campaign!==b.status.effective_status||g.statuses.ad_set!==b.budget.status||g.effective_statuses.ad_set!==b.budget.effective_status)fail('Meta status changed during budget review.',409);
   }
   return {kind:'budget',status:{resource:b.status.resource,name:b.status.name,status:b.status.status,effective_status:b.status.effective_status},budget:{resource:b.budget.resource,daily_cents:b.budget.daily_cents,status:b.budget.status,effective_status:b.budget.effective_status},daily_cents:cents,increase,graph:g};
  }catch(e){await invalid(actor,details.identity,e);throw e;}
 }
 app.post(path+'/budget-preview',owner(async(q,r,u)=>{
  if(Object.keys(q.query).length||!keys(q.body,['daily_cents'])||!validBudget(q.body.daily_cents))fail('Enter an average daily budget from $1.00 to $10,000.00 USD.');
  const funnel=uuid(q.params.id),data=context(q),before=await command(u,funnel,'read',data),details=identity(before);
  if(!budgetEnabled)fail('Meta budget changes require platform activation.',409);
  const auth=await token(u,details.identity),observation=await inspectBudget(u,before,auth,details,q.body.daily_cents);
  await connection(u,details.identity);const after=await command(u,funnel,'read',data);
  if(after.fingerprint!==before.fingerprint)fail('The campaign changed while loading. Review the budget again.',409);
  r.json({...publicResult(after),budget_preview:{...observation,checked_at:new Date(now()).toISOString(),proof:proof(u,funnel,after,observation)}});
 },{ratePrefix:'meta-budget-preview:',max:10}));
 app.post(path+'/budget-apply',owner(async(q,r,u)=>{
  const started=now();
  if(Object.keys(q.query).length||!keys(q.body,['proof','daily_cents','confirmed','spend_acknowledged'])||!validBudget(q.body.daily_cents)||q.body.confirmed!==true||q.body.spend_acknowledged!==true)fail('Confirm the budget change and acknowledge its spending impact.');
  const funnel=uuid(q.params.id),data=context(q),before=await command(u,funnel,'read',data),p=decode(q.body.proof,u,funnel,before),details=identity(before);
  if(!budgetEnabled)fail('Meta budget changes require platform activation.',409);
  const auth=await token(u,details.identity),cents=q.body.daily_cents,observation=await inspectBudget(u,before,auth,details,cents);
  if(p.observation!==digest(observation))fail('The budget proposal changed. Review it again.',409);
  try{if((await provider.validateMetaBudget(auth.value,details.snapshot,details.resources,cents))?.validated!==true)fail('Meta did not validate the budget change.',409);}catch(e){await invalid(u,details.identity,e);throw e;}
  if(digest(await inspectBudget(u,before,auth,details,cents))!==p.observation)fail('Meta details changed during validation. Review the budget again.',409);
  await connection(u,details.identity);
  if(p.expires<=now()||now()-started>75000)fail('Budget confirmation expired or took too long. Review it again.',409);
  const id=randomUUID(),claimed=await command(u,funnel,'claim',{...data,fingerprint:before.fingerprint,action:'budget',daily_cents:cents,confirmed:true,spend_acknowledged:true,command_id:id,observed:observation});
  if(claimed.dispatch!==true||claimed.latest_command?.id!==id||claimed.latest_command.daily_cents!==cents||digest(claimed.latest_command.steps)!==digest(['budget']))fail('The budget claim could not be verified. Refresh its record.',409);
  try{
   if(now()-started>85000)fail('The budget claim took too long.',409);
   const local=await command(u,funnel,'read',data);await connection(u,details.identity);
   if(local.latest_command?.id!==id||local.latest_command.state!=='unknown'||local.creation.fingerprint!==before.creation.fingerprint||local.managed_budget.daily_cents!==before.managed_budget.daily_cents)fail('The campaign changed after the budget claim.',409);
   if(digest(await inspectBudget(u,local,auth,details,cents,true))!==p.observation)fail('Meta details changed after the budget claim.',409);
   const again=await command(u,funnel,'read',data);await connection(u,details.identity);
   if(again.fingerprint!==local.fingerprint||now()-started>85000)fail('The campaign changed or the budget command took too long.',409);
   const result=await provider.applyMetaBudget(auth.value,details.snapshot,details.resources,cents);
   if(result?.confirmed!==true||result.resource!==details.resources.ad_set||result.daily_cents!==cents)fail('Meta did not confirm the exact budget change.',409);
   await command(u,funnel,'progress',{...data,command_id:id,stage:'budget',resource:result.resource,daily_cents:cents});
   await command(u,funnel,'finish',{...data,command_id:id});
  }catch(e){await invalid(u,details.identity,e);return r.json({...publicResult(await command(u,funnel,'read',data)),notice:'The budget outcome is uncertain. Ads may be spending at the requested or another budget. Check and control this campaign directly in Meta Ads Manager. KORLIX will not retry or replace the command.'});}
  r.json({...publicResult(await command(u,funnel,'read',data)),notice:'Meta accepted the average daily budget change. Status and schedule were not changed. Earlier spending still counts and lowering a budget does not reverse charges. Check Meta Ads Manager for current delivery and billing.'});
 },{ratePrefix:'meta-budget-write:',max:5}));
}
