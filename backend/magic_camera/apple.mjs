import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {appleTransactionAccess,assertAppleSandboxAccess} from '../web_billing/apple_security.mjs';
import {fail,UUID} from './core.mjs';
export const MAGIC_BUNDLE='com.korlixdeveloper.magiccamera';
export const APPLE_PRODUCTS=['magic_camera_starter','magic_camera_plus'];
export function appleFacts(decoded,userId,environment=process.env){
 if(decoded?.bundleId!==MAGIC_BUNDLE||!APPLE_PRODUCTS.includes(decoded.productId)||!/^\d{5,40}$/.test(String(decoded.originalTransactionId||'')))fail('This purchase does not belong to Magic Camera.',409);
 if(String(decoded.appAccountToken||'').toLowerCase()!==userId.toLowerCase())fail('This purchase belongs to a different Korlix account.',409);
 const {active,status}=appleTransactionAccess(decoded);
 const transaction={environment:decoded.environment,status,expiresAt:new Date(Number(decoded.expiresDate)).toISOString(),revokedAt:decoded.revocationDate?new Date(Number(decoded.revocationDate)).toISOString():null};
 assertAppleSandboxAccess({userId,transaction,environment});
 return {token_hash:createHash('sha256').update('magic:apple:'+decoded.originalTransactionId).digest('hex'),purchase_token:String(decoded.originalTransactionId),product_id:decoded.productId,state:status,active,expires_at:transaction.expiresAt,test_purchase:decoded.environment==='Sandbox',account_id:userId};
}
export function appleProvider(environment=process.env){
 const appId=Number(environment.KORLIX_MAGIC_APPLE_APP_ID),key=environment.KORLIX_APPLE_PRIVATE_KEY_BASE64?Buffer.from(environment.KORLIX_APPLE_PRIVATE_KEY_BASE64,'base64').toString('utf8'):String(environment.KORLIX_APPLE_PRIVATE_KEY||'').replace(/\\n/g,'\n');
 const ready=environment.KORLIX_MAGIC_APPLE_BILLING_ENABLED==='true'&&Number.isSafeInteger(appId)&&appId>0&&!!key&&!!environment.KORLIX_APPLE_ISSUER_ID&&!!environment.KORLIX_APPLE_KEY_ID;
 let configuration;
 async function configurations(){
  if(!ready)fail('App Store purchases are being set up. Please try again later.',503);
  if(!configuration)configuration=(async()=>{
   const lib=await import('@apple/app-store-server-library');
   const certs=await Promise.all(['AppleIncRootCertificate.cer','AppleRootCA-G2.cer','AppleRootCA-G3.cer'].map(n=>readFile(new URL('../apple_root_certs/'+n,import.meta.url))));
   return [lib.Environment.PRODUCTION,lib.Environment.SANDBOX].map(env=>({
    verifier:new lib.SignedDataVerifier(certs,true,env,MAGIC_BUNDLE,env===lib.Environment.PRODUCTION?appId:undefined),
    client:new lib.AppStoreServerAPIClient(key,environment.KORLIX_APPLE_KEY_ID,environment.KORLIX_APPLE_ISSUER_ID,MAGIC_BUNDLE,env),
   }));
  })().catch(e=>{configuration=null;throw e;});
  return configuration;
 }
 return {ready,
  async current(transactionId){
   if(!/^\d{5,40}$/.test(String(transactionId||'')))fail('Restore a valid App Store purchase.',400);
   for(const c of await configurations()){
    try{
     const status=await c.client.getAllSubscriptionStatuses(String(transactionId));
     const transactions=[];
     for(const group of status.data||[])for(const item of group.lastTransactions||[]){
      if(!item.signedTransactionInfo)continue;
      const decoded=await c.verifier.verifyAndDecodeTransaction(item.signedTransactionInfo);
      if(APPLE_PRODUCTS.includes(decoded.productId))transactions.push(decoded);
     }
     if(transactions.length)return transactions;
    }catch{ /* Try only the other verified store environment. */ }
   }
   fail('App Store verification is unavailable. No upgrade was applied. Please restore again later.',503);
  },
  async notification(signedPayload){
   if(typeof signedPayload!=='string'||signedPayload.length>100000)fail('Invalid notification.');
   for(const c of await configurations())try{const n=await c.verifier.verifyAndDecodeNotification(signedPayload);if(n.data?.signedTransactionInfo)return c.verifier.verifyAndDecodeTransaction(n.data.signedTransactionInfo);}catch{}
   fail('Notification could not be verified.',400);
  },
 };
}
export function registerMagicApple(app,{database,requireUser,provider=appleProvider(),environment=process.env,autoStart=true}={}){
 const base='/api/magic-camera/billing/apple',rates=new Map();
 const call=async(actor,action,p={})=>{if(!database)fail('Subscription storage is unavailable.',503);const r=await database.rpc('korlix_magic_apple_command',{p_actor:actor,p_action:action,p});if(r.error){const m=/BILL(\d{3}): (.+)/.exec(r.error.message||'');fail(m?m[2]:'Subscription storage is unavailable.',m?Number(m[1]):503);}return r.data;};
 async function sync(userId,id){let active=false;for(const decoded of await provider.current(id)){const facts=appleFacts(decoded,userId,environment);const result=await call(userId,'apply',facts);active=active||result.active;}return active;}
 const wrap=fn=>async(q,r)=>{r.set('Cache-Control','no-store');try{const user=await requireUser(q);if(!UUID.test(user?.id||'')||!user.email_confirmed_at)fail('Verify your Korlix email first.',403);const prior=rates.get(user.id),now=Date.now();if(prior&&prior.until>now){if(++prior.n>15)fail('Please wait a minute before checking again.',429);}else rates.set(user.id,{n:1,until:now+60000});if(rates.size>10000)for(const[k,v]of rates)if(v.until<now)rates.delete(k);await fn(q,r,user);}catch(e){r.status(e.statusCode||503).json({error:e.statusCode?e.message:'App Store verification is unavailable. Please retry.'});}};
 app.get(base+'/status',wrap(async(q,r,u)=>{
  let result=await call(u.id,'snapshot'),warning=null;
  if(q.query.refresh==='1'&&provider.ready){for(const p of result.purchases)try{await sync(u.id,p.purchase_token);}catch{warning='The App Store could not be refreshed. Please retry before changing plans.';}result=await call(u.id,'snapshot');}
  r.json({plan:result.plan,tier:result.plan.name,billingEnabled:provider.ready,canPurchase:provider.ready&&result.plan.name==='free',entitlement:result.entitlement,refreshWarning:warning});
 }));
 app.post(base+'/prepare',wrap(async(q,r,u)=>{
  if(!provider.ready)fail('App Store purchases are being set up.',503);if(!APPLE_PRODUCTS.includes(q.body?.productId))fail('Choose a Magic Camera plan.');
  const result=await call(u.id,'snapshot');if(result.plan.name!=='free')fail('Magic Camera is already included. Manage your current subscription instead.',409);
  r.json({canPurchase:true,accountId:u.id});
 }));
 app.post(base+'/verify',wrap(async(q,r,u)=>{
  if(!APPLE_PRODUCTS.includes(q.body?.productId))fail('Choose a Magic Camera plan.');
  const active=await sync(u.id,q.body?.purchaseId);
  const result=await call(u.id,'snapshot');r.json({verified:true,active,tier:result.plan.name,completePurchase:true});
 }));
 app.post(base+'/notifications',async(q,r)=>{
  try{const signed=await provider.notification(q.body?.signedPayload);if(!UUID.test(signed.appAccountToken||''))fail('Notification account not found.',409);await sync(signed.appAccountToken,signed.originalTransactionId);r.json({accepted:true});}catch(e){r.status(e.statusCode||503).json({error:'Notification could not be applied.'});}
 });
 let syncing=false;
 async function tick(){if(syncing||!provider.ready||!database)return;syncing=true;try{for(const row of await call(null,'due'))await sync(row.user_id,row.purchase_token).catch(()=>{});}catch{}finally{syncing=false;}}
 const timer=autoStart?setInterval(()=>void tick(),600000):null;timer?.unref();return {stop:()=>clearInterval(timer)};
}
