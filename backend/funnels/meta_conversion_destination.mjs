import {createHmac,timingSafeEqual} from 'node:crypto';
import {fail,uuid} from './core.mjs';
import {metaConfiguration,createMetaProvider,createMetaStore,tokenCipher,MetaAccessError} from './meta.mjs';
import {metaDestination,metaDestinationList,metaDestinationFields} from './meta_conversion_provider.mjs';
const keys=(v,expected)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).length===expected.length&&expected.every(k=>Object.hasOwn(v,k));
const hash=v=>typeof v==='string'&&/^[a-f0-9]{64}$/.test(v);
const ttl=5*60*1000;
const body=(scope,d,expires)=>JSON.stringify(['korlix-meta-conversion-destination-v1',scope.actor,scope.funnel,scope.campaign,scope.fingerprint,expires,...metaDestinationFields.map(k=>d[k])]);
export function metaDestinationProof(secret,scope,d,now){const expires=now+ttl;return `${expires}.${createHmac('sha256',secret).update(body(scope,d,expires)).digest('hex')}`;}
export function metaDestinationProofValid(secret,scope,d,proof,now){
 if(typeof proof!=='string'||!/^\d{13}\.[a-f0-9]{64}$/.test(proof))return false;
 const [stamp,sig]=proof.split('.'),expires=Number(stamp);if(expires<=now||expires>now+ttl)return false;
 return timingSafeEqual(Buffer.from(sig,'hex'),createHmac('sha256',secret).update(body(scope,d,expires)).digest());
}
export function registerMetaConversionDestination(app,{base,owner,database,environment,metaStore,metaProvider,now=Date.now}){
 const config=metaConfiguration(environment),configured=config.ready&&config.apiVersion==='v26.0'&&environment.KORLIX_META_CONVERSION_SETUP_ENABLED==='true',store=metaStore||createMetaStore(database),provider=metaProvider||createMetaProvider(config,{now});
 const path=base+'/:id/campaigns/:campaign_id/meta-conversion-destination';
 const context=q=>({campaign_id:uuid(q.params.campaign_id),configured,config_hash:config.hash});
 const command=async(actor,funnel,action,data)=>{
  if(!database)fail('Conversion destination storage is not configured.',503);
  const {data:out,error}=await database.rpc('korlix_funnel_meta_destination_v1',{p_actor:actor,p_action:action,p_funnel:funnel,p_data:data});
  if(error){const status={'42501':403,'P0002':404,'40001':409,'P0001':400,'23514':400,'22007':400,'22008':400}[error.code];fail(status?error.message:'Conversion destination storage is temporarily unavailable. Refresh before retrying.',status||503);}return out;
 };
 async function lookup(actor,funnel,data,fp){
  const before=await command(actor,funnel,'read',data),ctx=before.context;
  if(fp!==before.fingerprint)fail('The conversion destination or Meta account changed. Refresh it.',409);
  if(!configured||!before.lookup_ready)fail('Connect the active Meta account and save its Linked Meta campaign association first.',409);
  const access=async()=>{
   const c=await store.command(actor,'secret');
   if(c.config_hash!==config.hash||c.needs_reconnect||!Number.isFinite(Date.parse(c.expires_at))||Date.parse(c.expires_at)<=now()+60000||c.version!==ctx.connection_version||c.selected_account!==ctx.account?.id||!Array.isArray(c.accounts)||!c.accounts.some(a=>a.id===c.selected_account&&a.status===1))fail('Meta access changed. Refresh the destination setup.',409);return c;
  };
  const c=await access();let rows;
  try{
   const token=tokenCipher(config.key).open(c.sealed,`korlix-meta:${actor}:${c.binding_id}`);
   const a=await provider.account(token,c.selected_account);
   if(!a||!['id','name','currency','timezone','status'].every(k=>a[k]===ctx.account[k])||a.status!==1)fail('Meta account details changed. Refresh account access.',409);
   rows=metaDestinationList(await provider.conversionDestinations(token,a.id));
  }catch(e){if(e instanceof MetaAccessError)await store.command(actor,'invalid',{version:c.version}).catch(()=>{});throw e;}
  const after=await command(actor,funnel,'read',data),latest=await access();
  if(after.fingerprint!==before.fingerprint||!after.lookup_ready||latest.binding_id!==c.binding_id)fail('The campaign or Meta connection changed while loading data sources. Refresh it.',409);
  return {state:after,rows,checked_at:new Date(now()).toISOString()};
 }
 app.get(base+'/meta-conversion-destination/readiness',(_q,r)=>r.set('Cache-Control','no-store').json({configured,send_ready:false,provider_verified:false}));
 app.get(path,owner(async(q,r,u)=>{
  if(Object.keys(q.query).length)fail('Open destination setup without extra parameters.');r.json(await command(u,uuid(q.params.id),'read',context(q)));
 },{ratePrefix:'meta-destination-read:',max:30}));
 app.get(path+'/choices',owner(async(q,r,u)=>{
  if(!keys(q.query,['fingerprint'])||!hash(q.query.fingerprint))fail('Refresh the conversion destination before loading Meta data sources.');
  const funnel=uuid(q.params.id),data=context(q),d=await lookup(u,funnel,data,q.query.fingerprint),scope={actor:u,funnel,campaign:data.campaign_id,fingerprint:d.state.fingerprint};
  r.json({source:'meta_conversion_choices',funnel_id:funnel,campaign_id:data.campaign_id,fingerprint:d.state.fingerprint,checked_at:d.checked_at,expires_at:new Date(now()+ttl).toISOString(),choices:d.rows.map(destination=>({destination,proof:metaDestinationProof(config.secret,scope,destination,now())})),send_ready:false,provider_verified:false});
 },{ratePrefix:'meta-destination-provider:',max:10}));
 for(const action of ['save','clear'])app.post(path+'/'+action,owner(async(q,r,u)=>{
  const b=q.body,expected=['version','fingerprint','confirmed',...(action==='save'?['destination','proof']:[])];
  if(Object.keys(q.query).length||!keys(b,expected)||!Number.isSafeInteger(b.version)||b.version<0||b.version>2147483646||!hash(b.fingerprint)||b.confirmed!==true)fail('Refresh and confirm the conversion destination change.');
  const funnel=uuid(q.params.id),data=context(q),write={...data,version:b.version,fingerprint:b.fingerprint,confirmed:true};
  if(action==='save'){
   const before=await command(u,funnel,'read',data);
   if(before.version!==b.version||before.fingerprint!==b.fingerprint)fail('The conversion destination or Meta connection changed. Refresh it.',409);
   let destination;try{destination=metaDestination(b.destination);}catch{fail('Choose a listed Meta data source.');}
   const scope={actor:u,funnel,campaign:data.campaign_id,fingerprint:b.fingerprint};
   if(!configured||!metaDestinationProofValid(config.secret,scope,destination,b.proof,now()))fail('This conversion choice expired or could not be verified. Load Meta data sources again.',409);
   const d=await lookup(u,funnel,data,b.fingerprint);
   if(d.state.version!==b.version||!d.rows.some(row=>JSON.stringify(row)===JSON.stringify(destination))||!metaDestinationProofValid(config.secret,scope,destination,b.proof,now()))fail('Meta data source details changed or the choice expired. Load the data source list again.',409);
   Object.assign(write,{destination,checked_at:d.checked_at});
  }
  r.json(await command(u,funnel,action,write));
 },{ratePrefix:action==='save'?'meta-destination-provider:':'meta-destination-clear:',max:10}));
}
