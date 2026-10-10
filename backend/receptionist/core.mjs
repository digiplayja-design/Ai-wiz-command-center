import {createHmac,timingSafeEqual} from 'node:crypto';

export class ReceptionistError extends Error {
  constructor(message,status=400,code='RECEPTIONIST_REQUEST_FAILED'){super(message);this.status=status;this.code=code;}
}
export function fail(message,status=400,code){throw new ReceptionistError(message,status,code);}
export function text(value,max=500,required=false){
  if(value!=null&&typeof value!=='string')fail('Enter text for this field.');
  const v=(value||'').trim();if(v.length>max||(required&&!v))fail(`Check the required fields (maximum ${max} characters).`);return v;
}
export function uuid(value){const v=text(value,40,true);if(!/^[a-f\d]{8}-[a-f\d]{4}-[a-f\d]{4}-[a-f\d]{4}-[a-f\d]{12}$/i.test(v))fail('Choose a valid business or call.');return v;}
export const VOICES=[{id:'coral',name:'Coral · warm'},{id:'ash',name:'Ash · calm'},{id:'sage',name:'Sage · clear'},{id:'verse',name:'Verse · expressive'}];
export function settings(body={}){
  if(!body||typeof body!=='object'||Array.isArray(body))fail('Review your receptionist settings.');
  if(!Number.isInteger(body.version)||body.version<0)fail('Refresh your receptionist settings.',409);
  const result={version:body.version,enabled:body.enabled===true,booking_enabled:body.booking_enabled===true,
    greeting:text(body.greeting,400),knowledge:text(body.knowledge,8000),voice:text(body.voice||'coral',40),
    language:text(body.language||'English',80,true),monthly_minutes:Number(body.monthly_minutes),max_call_minutes:Number(body.max_call_minutes),
    processing_consent:body.processing_consent===true,event_ids:[]};
  if(!VOICES.some(v=>v.id===result.voice))fail('Choose an available receptionist voice.');
  if(!Number.isInteger(result.monthly_minutes)||result.monthly_minutes<1||result.monthly_minutes>1200)fail('Set a monthly phone limit from 1 to 1,200 minutes.');
  if(!Number.isInteger(result.max_call_minutes)||result.max_call_minutes<1||result.max_call_minutes>10)fail('Set a call limit from 1 to 10 minutes.');
  if(!Array.isArray(body.event_ids||[])||(body.event_ids||[]).length>12)fail('Choose up to 12 appointment types.');
  result.event_ids=[...new Set((body.event_ids||[]).map(uuid))];
  if(result.booking_enabled&&!result.event_ids.length)fail('Choose an appointment type before enabling phone bookings.');
  if(result.enabled&&!result.processing_consent)fail('Review and accept AI call processing before enabling your receptionist.');
  return result;
}
export function equalSecret(a,b){const x=Buffer.from(a||''),y=Buffer.from(b||'');return x.length>0&&x.length===y.length&&timingSafeEqual(x,y);}
export function sessionSecret(secret,id){return createHmac('sha256',secret).update('korlix-receptionist-v1:'+id).digest('hex');}
export function messages(value){
  if(!Array.isArray(value)||value.length>150)fail('This conversation is too long. Please start a new call.');
  let total=0;
  return value.filter(m=>m&&['user','assistant'].includes(m.role)).slice(-24).map(m=>{
    const content=text(m.content,4000,true);total+=content.length;if(total>24000)fail('This conversation is too long.');
    return {role:m.role,content};
  });
}
export function publicKnowledge(business){
  const d=business.published||{};
  return Object.fromEntries(['name','category','tagline','description','services','specialties','hours','phone','email','address','city','country','service_area','languages','accessibility','website'].map(k=>[k,String(d[k]||'').slice(0,2400)]));
}
export function confirmedBooking(message){return /^\s*(?:yes[,!\s]+)?(?:please\s+)?confirm (?:the |my )?booking[.!\s]*$/i.test(message||'');}
export function safeError(error){return error instanceof ReceptionistError?error.message:'The receptionist could not complete this request. Please retry.';}
