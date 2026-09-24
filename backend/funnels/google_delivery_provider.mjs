import {fail} from './core.mjs';
import {googleDestination} from './google_conversion_provider.mjs';
const object=v=>v&&typeof v==='object'&&!Array.isArray(v);
const account=v=>typeof v==='string'&&/^\d{10}$/.test(v);
export const googleRequestId=v=>typeof v==='string'&&v.length>0&&v.length<=512&&!/[\x00-\x20\x7f]/.test(v);
const invalid=()=>fail('Google delivery evidence could not be verified. Refresh the saved status; do not resend.',503);
export function googleDeliveryDestination(destination,root){
 const d=googleDestination(destination);if(!account(root))invalid();
 return {reference:'inquiry',operatingAccount:{accountType:'GOOGLE_ADS',accountId:d.conversion_customer_id},loginAccount:{accountType:'GOOGLE_ADS',accountId:root},productDestinationId:d.conversion_action_id};
}
export function googleDeliveryBody(a,now=Date.now()){
 const d=googleDestination(a.destination),r=a.receipt,t=Date.parse(r?.captured_at);
 if(!r||r.consent!=='granted'||r.policy_version!=='measurement_v1'||r.platform!=='google'||r.event_name!=='inquiry_submitted'||!['gclid','gbraid','wbraid'].includes(r.click_type)||typeof r.click_id!=='string'||!/^[A-Za-z0-9_-]{1,512}$/.test(r.click_id)||typeof r.event_id!=='string'||!/^[a-f0-9-]{36}$/.test(r.event_id)||!Number.isFinite(t)||t>now||t<now-Math.min(7,d.click_window_days)*86400000||(r.click_type!=='gclid'&&d.counting_type==='ONE_PER_CLICK'))fail('This inquiry is not eligible for this Google conversion action.',409);
 return {destinations:[googleDeliveryDestination(d,a.root_id)],events:[{transactionId:r.event_id,eventTimestamp:new Date(t).toISOString(),adIdentifiers:{[r.click_type]:r.click_id},consent:{adUserData:'CONSENT_GRANTED',adPersonalization:'CONSENT_DENIED'}}]};
}
export function googleDeliveryStatus(body,expected){
 if(!object(body)||body.error||!Array.isArray(body.requestStatusPerDestination)||body.requestStatusPerDestination.length!==1)invalid();
 const s=body.requestStatusPerDestination[0],d=s?.destination;
 if(!object(d)||d.reference!==expected.reference||d.productDestinationId!==expected.productDestinationId||d.linkedAccount||['operatingAccount','loginAccount'].some(k=>!object(d[k])||d[k].accountType!==expected[k].accountType||d[k].accountId!==expected[k].accountId))invalid();
 const states={PROCESSING:'processing',SUCCESS:'succeeded',FAILED:'rejected',PARTIAL_SUCCESS:'partial'};
 if(!states[s.requestStatus]||['audienceMembersIngestionStatus','audienceMembersRemovalStatus','removeAllAudienceMembersStatus'].some(k=>Object.hasOwn(s,k)))invalid();
 if(s.eventsIngestionStatus?.recordCount!==undefined&&s.eventsIngestionStatus.recordCount!=='1')invalid();
 if(s.requestStatus!=='PROCESSING'&&s.eventsIngestionStatus?.recordCount!=='1')invalid();
 const counts=(value,key)=>{
  if(value===undefined)return [];
  if(!object(value)||!Array.isArray(value[key])||value[key].length>100)invalid();
  return value[key].map(v=>{if(!object(v)||typeof v.reason!=='string'||!/^[A-Z][A-Z0-9_]{0,159}$/.test(v.reason)||!['0','1'].includes(v.recordCount))invalid();return {reason:v.reason,count:Number(v.recordCount)};});
 };
 const errors=counts(s.errorInfo,'errorCounts'),warnings=counts(s.warningInfo,'warningCounts');
 if(s.requestStatus==='SUCCESS'&&errors.some(e=>e.count>0))invalid();
 return {state:states[s.requestStatus],errors,warnings};
}
export function createGoogleDeliveryProvider({fetchImpl=fetch}={}){
 async function request(token,path,body){
  let response,value;
  try{
   response=await fetchImpl(new URL('https://datamanager.googleapis.com/v1/'+path),{method:body?'POST':'GET',headers:{Authorization:'Bearer '+token,...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{}),redirect:'error',signal:AbortSignal.timeout(10000)});
   const reader=response.body?.getReader();if(!reader)throw Error();const parts=[];let size=0;
   try{for(;;){const {value,done}=await reader.read();if(done)break;size+=value.byteLength;if(size>128*1024)throw Error();parts.push(Buffer.from(value));}}finally{await reader.cancel().catch(()=>{});}
   value=JSON.parse(Buffer.concat(parts).toString('utf8'));
  }catch{invalid();}
  if(!response.ok||!object(value)||value.error)invalid();return value;
 }
 return {
  async ingest(token,body){const r=await request(token,'events:ingest',body);if(!googleRequestId(r.requestId)||r.fieldWarnings!==undefined&&!Array.isArray(r.fieldWarnings))invalid();return {request_id:r.requestId,has_warnings:(r.fieldWarnings?.length??0)>0};},
  async status(token,id,destination){if(!googleRequestId(id))invalid();return googleDeliveryStatus(await request(token,'requestStatus:retrieve?'+new URLSearchParams({requestId:id})),destination);}
 };
}
