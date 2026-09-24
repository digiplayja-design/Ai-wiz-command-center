import {fail,uuid} from './core.mjs';
import {googleTokenCipher,googleDigest,createGoogleAdsProvider} from './google_ads_provider.mjs';
import {googleDestination,googleDestinationList} from './google_conversion_provider.mjs';
import {googleUploadConfiguration,createGoogleUploadProvider} from './google_upload_provider.mjs';
import {createGoogleDeliveryProvider,googleDeliveryBody,googleDeliveryDestination,googleRequestId} from './google_delivery_provider.mjs';
const exact=(v,keys)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).length===keys.length&&keys.every(k=>Object.hasOwn(v,k));
export function registerGoogleConversionDelivery(app,{base,owner,database,environment,googleAdsProvider,googleUploadProvider,googleDeliveryProvider,now=Date.now}){
 const config=googleUploadConfiguration(environment),enabled=config.ready&&environment.KORLIX_GOOGLE_DELIVERY_ENABLED==='true';
 const ads=googleAdsProvider||createGoogleAdsProvider(config.ads,{now}),oauth=googleUploadProvider||createGoogleUploadProvider(config,{now}),provider=googleDeliveryProvider||createGoogleDeliveryProvider();
 const data=q=>({campaign_id:uuid(q.params.campaign_id),ads_configured:config.ads.ready&&config.ads.apiVersion==='v25',ads_config_hash:config.ads.hash,configured:config.ready,config_hash:config.hash,delivery_configured:enabled});
 const command=async(u,action,f,d)=>{
  if(!database)fail('Google delivery storage is not configured.',503);
  const {data:out,error}=await database.rpc('korlix_google_delivery_v1',{p_actor:u,p_action:action,p_funnel:f,p_data:d});
  if(error){const status={'42501':403,'P0002':404,'40001':409,'54000':429,'P0001':400,'23514':400,'23505':409}[error.code];fail(status?error.message:'Delivery storage is temporarily unavailable. Refresh the saved status; do not resend.',status||503);}return out;
 };
 const noQuery=q=>{if(Object.keys(q.query).length)fail('Open Google delivery without extra parameters.');};
 const confirm=b=>{if(b.confirmed!==true||typeof b.fingerprint!=='string'||!/^[a-f0-9]{64}$/.test(b.fingerprint))fail('Refresh and confirm this Google delivery action.');};
 const gate=()=>{if(!enabled)fail('Google conversion delivery is awaiting KORLIX platform setup.',503);};
 const token=(u,a)=>oauth.refresh(googleTokenCipher(config.key).open(a.sealed,`korlix-google-upload:refresh:${u}:${a.binding_id}`));
 const path=base+'/:id/campaigns/:campaign_id/google-delivery';
 app.get(base+'/google-delivery/readiness',(_q,r)=>r.set('Cache-Control','no-store').json({configured:enabled,automatic_delivery:false,provider_verified:false}));
 app.get(path,owner(async(q,r,u)=>{noQuery(q);r.json(await command(u,'read',uuid(q.params.id),data(q)));},{ratePrefix:'google-delivery-read:',max:30}));
 app.post(path+'/settings',owner(async(q,r,u)=>{
  noQuery(q);const b=q.body;if(!exact(b,['enabled','fingerprint','confirmed'])||typeof b.enabled!=='boolean')fail('Choose whether to prepare future Google inquiries.');confirm(b);
  const f=uuid(q.params.id),d=data(q);await command(u,'read',f,d);if(b.enabled)gate();await command(u,'settings',f,{...d,...b});r.json(await command(u,'read',f,d));
 },{ratePrefix:'google-delivery-write:',max:10}));
 app.post(path+'/send',owner(async(q,r,u)=>{
  noQuery(q);const b=q.body;if(!exact(b,['event_id','fingerprint','confirmed']))fail('Select one inquiry and confirm sending it.');confirm(b);uuid(b.event_id);
  const f=uuid(q.params.id),d=data(q);await command(u,'read',f,d);gate();const a=await command(u,'claim',f,{...d,...b});
  let dispatched=false;
  try{
   const body=googleDeliveryBody(a,now()),access=await token(u,a),roots=await ads.roots(access);
   if(!Array.isArray(roots)||!roots.includes(a.root_id))fail('Google account access changed before delivery.',409);
   const account=await ads.account(access,a.account.id,a.login_customer_id);
   if(!account||!['id','name','currency','timezone','manager','status','test_account'].every(k=>account[k]===a.account[k])||account.status!=='ENABLED'||account.manager!==false||account.test_account!==false)fail('The selected Google account changed before delivery.',409);
   const selected=googleDestination(a.destination),choices=googleDestinationList(await ads.conversionDestinations(access,account,a.login_customer_id));
   if(!choices.some(x=>JSON.stringify(x)===JSON.stringify(selected)))fail('The Google conversion action changed before delivery.',409);
   // Commit identity and hash before the single HTTP write. A lost response can
   // never cause this event to be claimed or dispatched again.
   await command(u,'dispatch',f,{...d,id:a.id,request_hash:googleDigest(JSON.stringify(body))});dispatched=true;
   const result=await provider.ingest(access,body);
   if(!exact(result,['request_id','has_warnings'])||!googleRequestId(result.request_id)||typeof result.has_warnings!=='boolean')fail('Google returned an unreadable receipt. Refresh the saved status; do not resend.',503);
   await command(u,'received',f,{...d,id:a.id,...result});
  }catch(e){if(!dispatched)try{await command(u,'blocked',f,{...d,id:a.id});}catch{}throw e;}
  r.json(await command(u,'read',f,d));
 },{ratePrefix:'google-delivery-write:',max:10}));
 app.post(path+'/check',owner(async(q,r,u)=>{
  noQuery(q);const b=q.body;if(!exact(b,['event_id']))fail('Select one Google delivery to check.');uuid(b.event_id);
  const f=uuid(q.params.id),d=data(q);await command(u,'read',f,d);gate();const a=await command(u,'poll',f,{...d,...b}),access=await token(u,a);
  const status=await provider.status(access,a.request_id,googleDeliveryDestination(a.destination,a.root_id));
  if(!exact(status,['state','errors','warnings']))fail('Google returned unreadable processing evidence.',503);
  await command(u,'status',f,{...d,id:a.id,poll_id:a.poll_id,...status});r.json(await command(u,'read',f,d));
 },{ratePrefix:'google-delivery-check:',max:10}));
}
