import {readFile} from 'node:fs/promises';
import {GoogleAuth} from 'google-auth-library';
import {fail} from '../../web_billing/core.mjs';
import {BRAIN_BUNDLE,BRAIN_APPLE_ID,productFor,appleFacts,googleFacts} from './catalog.mjs';

export function brainProviders(env=process.env,{googleAuth}={}) {
  let credentials;try{credentials=JSON.parse(env.KORLIX_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON||'null');}catch{}
  const google=googleAuth||(credentials?.type==='service_account'?new GoogleAuth({credentials,scopes:['https://www.googleapis.com/auth/androidpublisher']}):null);
  const appleKey=env.KORLIX_APPLE_PRIVATE_KEY_BASE64?Buffer.from(env.KORLIX_APPLE_PRIVATE_KEY_BASE64,'base64').toString('utf8'):String(env.KORLIX_APPLE_PRIVATE_KEY||'').replace(/\\n/g,'\n');
  const configured={apple:!!(appleKey&&env.KORLIX_APPLE_ISSUER_ID&&env.KORLIX_APPLE_KEY_ID),google:!!google};
  let appleConfiguration;
  async function appleClients(){
    if(!configured.apple)fail('App Store verification is not configured.',503);
    return appleConfiguration ||= (async()=>{
      const lib=await import('@apple/app-store-server-library');
      const certs=await Promise.all(['AppleIncRootCertificate.cer','AppleRootCA-G2.cer','AppleRootCA-G3.cer'].map(n=>readFile(new URL('../../apple_root_certs/'+n,import.meta.url))));
      return [lib.Environment.PRODUCTION,lib.Environment.SANDBOX].map(environment=>({
        verifier:new lib.SignedDataVerifier(certs,true,environment,BRAIN_BUNDLE,environment===lib.Environment.PRODUCTION?BRAIN_APPLE_ID:undefined),
        client:new lib.AppStoreServerAPIClient(appleKey,env.KORLIX_APPLE_KEY_ID,env.KORLIX_APPLE_ISSUER_ID,BRAIN_BUNDLE,environment),
      }));
    })().catch(e=>{appleConfiguration=null;throw e;});
  }
  const googleRoot=`https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${BRAIN_BUNDLE}`;
  async function request(path,method='GET',data) {
    if(!google)fail('Google Play verification is not configured.',503);
    try{return(await google.request({url:googleRoot+path,method,data,timeout:20000,retry:false})).data;}
    catch{fail('The store could not verify this purchase. Please restore again later.',503);}
  }
  return {
    ready(provider){return configured[provider]&&env.KORLIX_BRAIN_BILLING_ENABLED==='true'&&env[`KORLIX_BRAIN_${provider.toUpperCase()}_PRODUCTS_READY`]==='true';},
    async verify(provider,{userId,productId,purchaseId,purchaseToken}) {
      const item=productFor(provider,productId);
      const observedAt=Date.now();
      if(provider==='google') {
        if(typeof purchaseToken!=='string'||purchaseToken.length<10||purchaseToken.length>4096||/\s/.test(purchaseToken))fail('Restore a valid Google Play purchase.',400);
        const token=encodeURIComponent(purchaseToken);
        const value=await request(item.kind==='subscription'?`/purchases/subscriptionsv2/tokens/${token}`:`/purchases/productsv2/tokens/${token}`);
        return googleFacts(value,userId,purchaseToken,productId,env,observedAt);
      }
      if(!/^\d{5,40}$/.test(String(purchaseId||'')))fail('Restore a valid App Store purchase.',400);
      for(const {client,verifier}of await appleClients()){
        let decoded;
        try{
          if(item.kind==='consumable')decoded=await verifier.verifyAndDecodeTransaction((await client.getTransactionInfo(String(purchaseId))).signedTransactionInfo);
          else {
            const statuses=await client.getAllSubscriptionStatuses(String(purchaseId));
            const values=[];
            for(const group of statuses.data||[])for(const transaction of group.lastTransactions||[]){
              const value=await verifier.verifyAndDecodeTransaction(transaction.signedTransactionInfo);
              if(value.productId===productId)values.push(value);
            }
            decoded=values.sort((a,b)=>Number(b.purchaseDate)-Number(a.purchaseDate))[0];
          }
        }catch{continue;}
        if(decoded){if(decoded.productId!==productId)fail('This purchase does not match the selected product.',409);return appleFacts(decoded,userId,env,observedAt);}
      }
      fail('App Store verification is unavailable. No minutes were added. Please restore again later.',503);
    },
    async finish(facts){
      if(facts.provider!=='google'||!facts.active)return;
      const product=encodeURIComponent(facts.product_id),token=encodeURIComponent(facts.provider_token);
      if(facts.kind==='consumable'){
        // A retry after successful consumption is safe: verify it is already consumed.
        const value=await request(`/purchases/productsv2/tokens/${token}`);
        if(value.productLineItem?.[0]?.productOfferDetails?.consumptionState==='CONSUMPTION_STATE_CONSUMED')return;
        await request(`/purchases/products/${product}/tokens/${token}:consume`,'POST',{});
      }else {
        const value=await request(`/purchases/subscriptionsv2/tokens/${token}`);
        if(value.acknowledgementState==='ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED')return;
        await request(`/purchases/subscriptions/${product}/tokens/${token}:acknowledge`,'POST',{});
      }
    },
    async appleNotification(payload){
      if(typeof payload!=='string'||payload.length>100000)fail('Invalid store notification.',400);
      for(const {verifier}of await appleClients())try{
        const n=await verifier.verifyAndDecodeNotification(payload);
        if(n.data?.signedTransactionInfo)return await verifier.verifyAndDecodeTransaction(n.data.signedTransactionInfo);
      }catch{}
      fail('Store notification could not be verified.',400);
    },
  };
}
