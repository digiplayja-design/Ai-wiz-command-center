import {stripeSignature} from '../scheduling/stripe_provider.mjs';
import {fail,PRICES,id} from './core.mjs';
export const DIRECTORY_STRIPE_API_VERSION='2026-09-30.endive';
const INTEGRATION_ID='korlix_directory_jnpvqxrw';
export function directoryBilling(env,{fetcher=fetch,now=Date.now}={}){
 const key=(env.KORLIX_DIRECTORY_STRIPE_SECRET_KEY||'').trim(),secret=(env.KORLIX_DIRECTORY_STRIPE_WEBHOOK_SECRET||'').trim();
 const live=/^(sk|rk)_live_/.test(key),configured=/^(sk|rk)_(test|live)_[A-Za-z0-9_]+$/.test(key)&&/^whsec_[A-Za-z0-9_]+$/.test(secret);
 const enabled=env.KORLIX_DIRECTORY_STRIPE_ENABLED==='true',ready=configured&&enabled;
 const portalConfiguration=(env.KORLIX_DIRECTORY_STRIPE_PORTAL_CONFIGURATION_ID||'').trim();
 let connectionCheck=null,connectionStatus='unchecked',connectionCheckedAt=0;
 async function api(path,{method='GET',body,idem}={}){
  if(!configured)fail('Verified membership payments are not yet available. Your free listing and application remain available.',503);
  let response;try{response=await fetcher('https://api.stripe.com/v1'+path,{method,headers:{Authorization:'Bearer '+key,'Stripe-Version':DIRECTORY_STRIPE_API_VERSION,...(body?{'Content-Type':'application/x-www-form-urlencoded'}:{}),...(idem?{'Idempotency-Key':idem}:{})},...(body?{body:new URLSearchParams(body).toString()}:{}),signal:AbortSignal.timeout(25000)});}catch{fail('Payment provider temporarily unavailable. Retry without starting a second purchase.',503);}
  const data=await response.json();if(!response.ok)fail('Payment provider could not complete this request. Please retry or contact support.',502);return data;
 }
 async function checkConnection(){
  if(!configured)return 'credentials_missing';
  if(!/^bpc_[A-Za-z0-9]+$/.test(portalConfiguration))return 'portal_configuration_missing';
  if(connectionCheck)return connectionCheck;
  if(connectionStatus!=='unchecked'&&now()-connectionCheckedAt<60000)return connectionStatus;
  connectionCheck=(async()=>{
   try{const p=await api('/billing_portal/configurations/'+portalConfiguration);connectionStatus=p.id===portalConfiguration&&p.livemode===live&&p.active===true?'verified':'configuration_mismatch';}
   catch{connectionStatus='unavailable';}
   connectionCheckedAt=now();return connectionStatus;
  })().finally(()=>{connectionCheck=null;});
  return connectionCheck;
 }
 function validSubscription(s){
  id(s.metadata?.korlix_directory);id(s.metadata?.generation);
  const lines=s.items?.data||[],price=lines[0]?.price,period=price?.recurring?.interval;
  if(s.livemode!==live||lines.length!==1||lines[0]?.quantity!==1||price?.currency!=='usd'||!Object.hasOwn(PRICES,period)||price?.unit_amount!==PRICES[period]||price?.recurring?.interval_count!==1)fail('Membership price or payment mode did not match.',409);
  const invoice=s.latest_invoice,paid=s.status==='active'&&invoice?.status==='paid'&&invoice?.amount_paid>=PRICES[period];
  const end=lines[0]?.current_period_end??s.current_period_end;
  if(paid&&!Number.isFinite(end))fail('Membership renewal date could not be verified.',409);
  // The customer portal can schedule flexible subscriptions with cancel_at
  // while leaving cancel_at_period_end false. Preserve paid access and report
  // renewal as canceled when that date is the end of this paid period.
  const renewalCanceled=s.cancel_at_period_end===true||(Number.isFinite(end)&&Number.isFinite(s.cancel_at)&&s.cancel_at>0&&s.cancel_at===end);
  return {livemode:live,business_id:s.metadata.korlix_directory,generation:s.metadata.generation,subscription_id:s.id,customer_id:typeof s.customer==='string'?s.customer:s.customer?.id,state:paid?'active':s.status==='active'?'unpaid':s.status,paid_until:paid?new Date(end*1000).toISOString():null,invoice_id:typeof invoice==='object'?invoice?.id:invoice,cancel_at_period_end:renewalCanceled};
 }
 return {ready,configured,enabled,live,checkConnection,apiVersion:DIRECTORY_STRIPE_API_VERSION,verify:(raw,signature)=>configured&&stripeSignature(raw,signature,secret),
  async checkout(business,m,email){
   if(!ready)fail('New membership checkout is paused. Free listings and existing membership management remain available.',503);
   if(!Object.hasOwn(PRICES,m.interval))fail('Choose monthly or yearly membership.');
   if(portalConfiguration&&await checkConnection()!=='verified')fail('Payment connection could not be verified. Please try again later.',503);
   if(m.checkout_url)return {id:m.checkout_id,url:m.checkout_url};
   const s=await api('/checkout/sessions',{method:'POST',idem:'directory-'+m.generation,body:{mode:'subscription',integration_identifier:INTEGRATION_ID,'subscription_data[billing_mode][type]':'flexible',client_reference_id:business,'metadata[korlix_directory]':business,'metadata[generation]':m.generation,'subscription_data[metadata][korlix_directory]':business,'subscription_data[metadata][generation]':m.generation,customer_email:email,'line_items[0][quantity]':'1','line_items[0][price_data][currency]':'usd','line_items[0][price_data][unit_amount]':String(PRICES[m.interval]),'line_items[0][price_data][recurring][interval]':m.interval,'line_items[0][price_data][product_data][name]':'KORLIX Verified Business Membership',expires_at:String(Math.floor(Date.parse(m.checkout_expires)/1000)),success_url:'https://www.korlixdeveloper.com/business-directory/?membership=return',cancel_url:'https://www.korlixdeveloper.com/business-directory/?membership=cancel','custom_text[submit][message]':'Recurring membership after verification approval. Cancel renewal in KORLIX My Businesses. Basic listing remains free. Verification is not a guarantee of service quality.'}});
   if(s.livemode!==live||s.client_reference_id!==business||s.metadata?.generation!==m.generation||s.mode!=='subscription'||!/^cs_/.test(s.id)||(s.url&&new URL(s.url).origin!=='https://checkout.stripe.com'))fail('Checkout verification failed.',502);return {id:s.id,url:s.url,status:s.status,subscription:s.subscription};
  },
  async session(m){const s=await api('/checkout/sessions/'+encodeURIComponent(m.checkout_id));if(s.client_reference_id!==m.business_id||s.metadata?.generation!==m.generation||s.livemode!==live)fail('Payment does not match this business.',409);return s;},
  async refresh(m){
   let sub=m.subscription_id;
   if(!sub&&m.checkout_id){const s=await api('/checkout/sessions/'+encodeURIComponent(m.checkout_id));if(s.client_reference_id!==m.business_id||s.metadata?.generation!==m.generation||s.livemode!==live)fail('Payment does not match this business.',409);sub=typeof s.subscription==='string'?s.subscription:s.subscription?.id;}
   if(!sub)return null;return this.subscription(sub);
  },
  async subscription(sub){if(!/^sub_[A-Za-z0-9]+$/.test(sub))fail('Invalid membership reference.');const observed_at=new Date().toISOString();return {...validSubscription(await api('/subscriptions/'+sub+'?expand[]=latest_invoice')),observed_at};},
  async cancel(sub){if(!/^sub_[A-Za-z0-9]+$/.test(sub))fail('Invalid membership reference.');await api('/subscriptions/'+sub,{method:'POST',body:{cancel_at_period_end:'true'}});return this.subscription(sub);},
  async portal(customer){if(!/^cus_[A-Za-z0-9]+$/.test(customer))fail('Payment account is not available.');const s=await api('/billing_portal/sessions',{method:'POST',body:{customer,return_url:'https://www.korlixdeveloper.com/app/',...(portalConfiguration?{configuration:portalConfiguration}:{})}});if(new URL(s.url).origin!=='https://billing.stripe.com')fail('Invalid payment management link.',502);return s.url;},
  async chargeCustomer(charge){if(!/^ch_[A-Za-z0-9]+$/.test(charge))fail('Invalid charge reference.');const c=await api('/charges/'+charge);if(c.livemode!==live)fail('Payment mode mismatch.',409);return typeof c.customer==='string'?c.customer:c.customer?.id;},
  validSubscription,
 };
}
