import {stripeSignature} from '../scheduling/stripe_provider.mjs';
import {fail,PRICES,id} from './core.mjs';
export function directoryBilling(env,{fetcher=fetch}={}){
 const key=env.KORLIX_DIRECTORY_STRIPE_SECRET_KEY||'',secret=env.KORLIX_DIRECTORY_STRIPE_WEBHOOK_SECRET||'';
 const live=/^(sk|rk)_live_/.test(key),ready=!!key&&!!secret;
 async function api(path,{method='GET',body,idem}={}){
  if(!ready)fail('Verified membership payments are not yet available. Your free listing and application remain available.',503);
  let response;try{response=await fetcher('https://api.stripe.com/v1'+path,{method,headers:{Authorization:'Bearer '+key,'Stripe-Version':'2025-09-30.clover',...(body?{'Content-Type':'application/x-www-form-urlencoded'}:{}),...(idem?{'Idempotency-Key':idem}:{})},...(body?{body:new URLSearchParams(body).toString()}:{}),signal:AbortSignal.timeout(25000)});}catch{fail('Payment provider temporarily unavailable. Retry without starting a second purchase.',503);}
  const data=await response.json();if(!response.ok)fail('Payment provider could not complete this request. Please retry or contact support.',502);return data;
 }
 function validSubscription(s){
  id(s.metadata?.korlix_directory);id(s.metadata?.generation);
  const lines=s.items?.data||[],price=lines[0]?.price,period=price?.recurring?.interval;
  if(s.livemode!==live||lines.length!==1||lines[0]?.quantity!==1||price?.currency!=='usd'||!Object.hasOwn(PRICES,period)||price?.unit_amount!==PRICES[period]||price?.recurring?.interval_count!==1)fail('Membership price or payment mode did not match.',409);
  const invoice=s.latest_invoice,paid=s.status==='active'&&invoice?.status==='paid'&&invoice?.amount_paid>=PRICES[period];
  const end=lines[0]?.current_period_end??s.current_period_end;
  if(paid&&!Number.isFinite(end))fail('Membership renewal date could not be verified.',409);
  return {livemode:live,business_id:s.metadata.korlix_directory,generation:s.metadata.generation,subscription_id:s.id,customer_id:typeof s.customer==='string'?s.customer:s.customer?.id,state:paid?'active':s.status==='active'?'unpaid':s.status,paid_until:paid?new Date(end*1000).toISOString():null,invoice_id:typeof invoice==='object'?invoice?.id:invoice,cancel_at_period_end:s.cancel_at_period_end===true};
 }
 return {ready,live,verify:(raw,signature)=>ready&&stripeSignature(raw,signature,secret),
  async checkout(business,m,email){
   if(m.checkout_url)return {id:m.checkout_id,url:m.checkout_url};
   const s=await api('/checkout/sessions',{method:'POST',idem:'directory-'+m.generation,body:{mode:'subscription',client_reference_id:business,'metadata[korlix_directory]':business,'metadata[generation]':m.generation,'subscription_data[metadata][korlix_directory]':business,'subscription_data[metadata][generation]':m.generation,customer_email:email,'line_items[0][quantity]':'1','line_items[0][price_data][currency]':'usd','line_items[0][price_data][unit_amount]':String(PRICES[m.interval]),'line_items[0][price_data][recurring][interval]':m.interval,'line_items[0][price_data][product_data][name]':'KORLIX Verified Business Membership',expires_at:String(Math.floor(Date.parse(m.checkout_expires)/1000)),success_url:'https://www.korlixdeveloper.com/business-directory/?membership=return',cancel_url:'https://www.korlixdeveloper.com/business-directory/?membership=cancel','custom_text[submit][message]':'Recurring membership after verification approval. Cancel renewal in KORLIX My Businesses. Basic listing remains free. Verification is not a guarantee of service quality.'}});
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
  async portal(customer){if(!/^cus_[A-Za-z0-9]+$/.test(customer))fail('Payment account is not available.');const s=await api('/billing_portal/sessions',{method:'POST',body:{customer,return_url:'https://www.korlixdeveloper.com/app/'}});if(new URL(s.url).origin!=='https://billing.stripe.com')fail('Invalid payment management link.',502);return s.url;},
  async chargeCustomer(charge){if(!/^ch_[A-Za-z0-9]+$/.test(charge))fail('Invalid charge reference.');const c=await api('/charges/'+charge);if(c.livemode!==live)fail('Payment mode mismatch.',409);return typeof c.customer==='string'?c.customer:c.customer?.id;},
  validSubscription,
 };
}
