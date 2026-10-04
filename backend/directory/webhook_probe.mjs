import {stripeSignature} from '../scheduling/stripe_provider.mjs';

// A short-lived delivery check with no database or payment-provider access.
// Sandbox events handled here can never enter membership reconciliation.
export function sandboxWebhookProbe(environment, now=Date.now){
 const secret=String(environment.KORLIX_DIRECTORY_STRIPE_SANDBOX_WEBHOOK_SECRET||'').trim();
 const probeId=String(environment.KORLIX_DIRECTORY_STRIPE_SANDBOX_PROBE_ID||'');
 const expires=Date.parse(environment.KORLIX_DIRECTORY_STRIPE_SANDBOX_PROBE_EXPIRES||'');
 const configured=/^whsec_[A-Za-z0-9]+$/.test(secret)&&/^[a-f0-9]{32}$/.test(probeId)
  &&secret!==String(environment.KORLIX_DIRECTORY_STRIPE_WEBHOOK_SECRET||'').trim()
  &&Number.isFinite(expires)&&expires>now()&&expires<=now()+2*60*60*1000;
 let receipt=null;
 const active=()=>configured&&now()<expires;
 return {
  status(){return {enabled:active(),verified:receipt!==null,...(receipt||{})};},
  receive(raw,signature){
   if(!active()||!stripeSignature(raw,signature,secret,now()))return null;
   let event;
   try{event=JSON.parse(raw.toString());}catch{return {status:400,body:{error:'Invalid sandbox event.'}};}
   if(event?.livemode!==false)return {status:400,body:{error:'Payment mode mismatch.'}};
   if(event.type==='customer.subscription.updated'
    &&event.data?.object?.metadata?.korlix_directory_delivery_probe===probeId){
    receipt={receivedAt:new Date(now()).toISOString(),eventType:event.type};
   }
   return {status:200,body:{received:true}};
  }
 };
}
