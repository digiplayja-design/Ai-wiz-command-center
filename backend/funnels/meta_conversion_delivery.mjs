import {randomUUID,createHash} from 'node:crypto';
import {fail,uuid} from './core.mjs';
import {metaConfiguration,createMetaProvider,createMetaStore,tokenCipher,MetaAccessError} from './meta.mjs';
import {metaDestinationList} from './meta_conversion_provider.mjs';
import {createMetaDeliveryProvider,metaDeliveryBody,metaDeliveryToken} from './meta_delivery_provider.mjs';
const exact=(v,keys)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).length===keys.length&&keys.every(k=>Object.hasOwn(v,k));
export function registerMetaConversionDelivery(app,{base,owner,database,environment,consent,metaStore,metaProvider,metaDeliveryProvider,now=Date.now}){
 const config=metaConfiguration(environment),configured=config.ready&&config.apiVersion==='v26.0'&&environment.KORLIX_META_CONVERSION_SETUP_ENABLED==='true';
 const enabled=configured&&environment.KORLIX_META_DELIVERY_ENABLED==='true';
 const store=metaStore||createMetaStore(database),ads=metaProvider||createMetaProvider(config,{now}),provider=metaDeliveryProvider||createMetaDeliveryProvider(config,{now});
 const data=q=>({campaign_id:uuid(q.params.campaign_id),configured,config_hash:config.hash,measurement_configured:consent.configured,measurement_config_hash:consent.config.config_hash,public_origin:consent.config.public_origin,delivery_configured:enabled});
 const command=async(u,action,f,d)=>{
  if(!database)fail('Meta delivery storage is not configured.',503);
  const {data:out,error}=await database.rpc('korlix_meta_delivery_v1',{p_actor:u,p_action:action,p_funnel:f,p_data:d});
  if(error){const status={'42501':403,'P0002':404,'40001':409,'54000':429,'P0001':400,'23514':400,'23505':409}[error.code];fail(status?error.message:'Meta delivery storage is temporarily unavailable. Refresh the saved status; do not resend.',status||503);}return out;
 };
 const noQuery=q=>{if(Object.keys(q.query).length)fail('Open Meta delivery without extra parameters.');};
 const confirm=b=>{if(b.confirmed!==true||typeof b.fingerprint!=='string'||!/^[a-f0-9]{64}$/.test(b.fingerprint))fail('Refresh and confirm this Meta delivery action.');};
 const gate=()=>{if(!enabled)fail('Meta conversion delivery is awaiting KORLIX platform setup.',503);};
 const binding=(u,c,id)=>'korlix-meta-delivery:'+u+':'+c+':'+id;
 const token=(u,c,a)=>tokenCipher(config.key).open(a.sealed,binding(u,c,a.binding_id));
 function grant(value){
  if(!exact(value,['system_user_id','expires_at'])||typeof value.system_user_id!=='string'||!/^\d{1,40}$/.test(value.system_user_id)||
   value.expires_at!==null&&(typeof value.expires_at!=='string'||!Number.isFinite(Date.parse(value.expires_at))||Date.parse(value.expires_at)<=now()+60000))fail('Meta conversion authorization could not be verified.',503);
  return value;
 }
 async function check(u,c,a){
  const access=token(u,c,a),verified=grant(await provider.authorize(access,a.destination));
  if(verified.system_user_id!==a.system_user_id)fail('Meta conversion authorization changed. Replace its token.',409);
  const m=await store.command(u,'secret');
  if(m.config_hash!==config.hash||m.needs_reconnect||!Number.isFinite(Date.parse(m.expires_at))||Date.parse(m.expires_at)<=now()+60000||m.selected_account!==a.account.id)fail('Reconnect the selected Meta advertising account.',409);
  try{
   const readToken=tokenCipher(config.key).open(m.sealed,'korlix-meta:'+u+':'+m.binding_id);
   const account=await ads.account(readToken,a.account.id);
   if(!account||account.status!==1||!['id','name','currency','timezone','status'].every(k=>account[k]===a.account[k]))fail('The selected Meta account changed. Refresh account access.',409);
   const choices=metaDestinationList(await ads.conversionDestinations(readToken,account.id));
   if(!choices.some(d=>d.pixel_id===a.destination.pixel_id&&d.name===a.destination.name))fail('The Meta data source is no longer available to the selected account.',409);
  }catch(e){if(e instanceof MetaAccessError)await store.command(u,'invalid',{version:m.version}).catch(()=>{});throw e;}
  return access;
 }
 const path=base+'/:id/campaigns/:campaign_id/meta-delivery';
 app.get(base+'/meta-delivery/readiness',(_q,r)=>r.set('Cache-Control','no-store').json({configured:enabled,automatic_delivery:false,provider_verified:false}));
 app.get(path,owner(async(q,r,u)=>{noQuery(q);r.json(await command(u,'read',uuid(q.params.id),data(q)));},{ratePrefix:'meta-delivery-read:',max:30}));
 for(const action of ['authorize','disconnect'])app.post(path+'/'+action,owner(async(q,r,u)=>{
  noQuery(q);const b=q.body;if(!exact(b,['fingerprint','confirmed',...(action==='authorize'?['access_token']:[])]))fail('Refresh and confirm Meta conversion authorization.');confirm(b);
  const f=uuid(q.params.id),d=data(q),before=await command(u,'read',f,d);
  if(before.fingerprint!==b.fingerprint)fail('Meta delivery setup changed. Refresh before continuing.',409);
  if(action==='disconnect')await command(u,'disconnect',f,{...d,fingerprint:b.fingerprint,confirmed:true});
  else {
   gate();if(!before.can_authorize||!metaDeliveryToken(b.access_token))fail('Choose a current Meta data source and enter its system-user token.',409);
   const verified=grant(await provider.authorize(b.access_token,before.destination)),id=randomUUID();
   const sealed=tokenCipher(config.key).seal(b.access_token,binding(u,d.campaign_id,id));
   await command(u,'authorize',f,{...d,fingerprint:b.fingerprint,confirmed:true,binding_id:id,sealed,...verified});
  }
  r.json(await command(u,'read',f,d));
 },{ratePrefix:'meta-delivery-access:',max:5}));
 app.post(path+'/settings',owner(async(q,r,u)=>{
  noQuery(q);const b=q.body;if(!exact(b,['enabled','fingerprint','confirmed'])||typeof b.enabled!=='boolean')fail('Choose whether to prepare future Meta inquiries.');confirm(b);
  const f=uuid(q.params.id),d=data(q);await command(u,'read',f,d);
  if(b.enabled){gate();const a=await command(u,'credentials',f,{...d,fingerprint:b.fingerprint});await check(u,d.campaign_id,a);}
  await command(u,'settings',f,{...d,...b});r.json(await command(u,'read',f,d));
 },{ratePrefix:'meta-delivery-write:',max:10}));
 app.post(path+'/send',owner(async(q,r,u)=>{
  noQuery(q);const b=q.body;if(!exact(b,['event_id','fingerprint','confirmed']))fail('Select one Meta inquiry and confirm sending it.');confirm(b);uuid(b.event_id);
  const f=uuid(q.params.id),d=data(q);await command(u,'read',f,d);gate();const a=await command(u,'claim',f,{...d,...b});
  let dispatched=false;
  try{
   metaDeliveryBody(a.receipt,now());
   const access=await check(u,d.campaign_id,a),body=metaDeliveryBody(a.receipt,now());
   // Committed before the only /events POST. Uncertain attempts are never retried.
   await command(u,'dispatch',f,{...d,id:a.id,request_hash:createHash('sha256').update(JSON.stringify(body)).digest('hex')});dispatched=true;
   const receipt=await provider.send(access,a.destination,body);
   if(!exact(receipt,['trace_id','has_warnings'])||typeof receipt.trace_id!=='string'||!/^[A-Za-z0-9_-]{1,200}$/.test(receipt.trace_id)||typeof receipt.has_warnings!=='boolean')fail('Meta returned an unreadable receipt. Refresh the saved status; do not resend.',503);
   await command(u,'received',f,{...d,id:a.id,...receipt});
  }catch(e){if(!dispatched)try{await command(u,'blocked',f,{...d,id:a.id});}catch{}throw e;}
  r.json(await command(u,'read',f,d));
 },{ratePrefix:'meta-delivery-write:',max:10}));
}
