export class FunnelError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}
export const fail = (m, s) => { throw new FunnelError(m, s); };
export function text(v, max, required = false) {
  if (typeof v !== 'string' || v.length > max || /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(v)) fail('Check the length and format of your text.');
  v = v.trim(); if (required && !v) fail('Complete the required fields.'); return v;
}
export function uuid(v) { if (typeof v !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v)) fail('Invalid record.'); return v; }
export function version(v) { if (!Number.isSafeInteger(v) || v < 1) fail('Refresh this funnel before saving.'); return v; }
export function slug(v) { if (typeof v !== 'string' || !/^[a-z0-9][a-z0-9-]{2,59}$/.test(v)) fail('Use 3–60 lowercase letters, numbers, or hyphens for the address.'); return v; }
export function httpsUrl(v) {
  v = text(v ?? '', 1000); if (!v) return '';
  let u; try { u = new URL(v); } catch { fail('Enter a complete HTTPS address.'); }
  if (u.protocol !== 'https:' || u.username || u.password || !u.hostname.includes('.') || /^(localhost|127\.|0\.|169\.254\.)/.test(u.hostname)) fail('Enter a public HTTPS address.');
  return u.href;
}
export const defaultSections=()=>['main_image','benefits','inquiry','faq'].map(kind=>({kind,visible:true}));
const questionText=(v,max,required=false)=>{
  const value=text(v,max,required);
  if(value.includes('\x7f'))fail('Check the length and format of your question or answer.');
  return value;
};
export function inquiryQuestions(raw=[]) {
  if(!Array.isArray(raw)||raw.length>4)fail('Use up to four inquiry questions.');
  const ids=new Set();
  return raw.map(q=>{
    if(!q||typeof q!=='object'||Array.isArray(q)||typeof q.id!=='string'||!/^q-[1-4]$/.test(q.id)||ids.has(q.id)||!['text','choice'].includes(q.type)||typeof q.required!=='boolean')fail('Choose a valid inquiry question.');
    ids.add(q.id);
    const options=q.type==='choice'?q.options:[];
    if(!Array.isArray(options)||options.length>8)fail('Use up to eight choices per question.');
    let show_when;
    if(q.show_when!==undefined&&q.show_when!==null){
      const rule=q.show_when;
      if(typeof rule!=='object'||Array.isArray(rule)||typeof rule.question_id!=='string'||!/^q-[1-4]$/.test(rule.question_id))fail('Choose a valid question condition.');
      show_when={question_id:rule.question_id,equals:questionText(rule.equals??'',80)};
    }
    return{id:q.id,type:q.type,label:questionText(q.label??'',120),required:q.required,options:options.map(o=>questionText(o,80)),...(show_when?{show_when}:{})};
  });
}
export function questionsReady(raw) {
  const questions=inquiryQuestions(raw);
  if(questions.some(q=>!q.label||(q.type==='choice'&&(q.options.length<2||q.options.some(o=>!o)||new Set(q.options).size!==q.options.length))))fail('Complete each question and give multiple-choice questions two to eight distinct choices before publishing.');
  for(const [i,q] of questions.entries())if(q.show_when){
    const source=questions.slice(0,i).find(p=>p.id===q.show_when.question_id);
    if(!source||source.type!=='choice'||!q.show_when.equals||!source.options.includes(q.show_when.equals))fail('Check each question condition: choose an earlier multiple-choice question and one of its current choices.');
  }
  return questions;
}
// Earlier-only dependencies make chains deterministic and prevent cycles.
export function visibleQuestions(raw,values={}) {
  const shown=[];
  for(const q of inquiryQuestions(raw)){
    const rule=q.show_when,source=rule&&shown.find(p=>p.id===rule.question_id);
    if(!rule||(source?.type==='choice'&&rule.equals&&source.options.includes(rule.equals)&&typeof values['answer_'+source.id]==='string'&&values['answer_'+source.id].trim()===rule.equals))shown.push(q);
  }
  return shown;
}
export function inquiryAnswers(p,d={}) {
  const questions=questionsReady(d.questions);
  if(Object.keys(p).some(k=>k.startsWith('answer_')&&!questions.some(q=>k==='answer_'+q.id)))fail('This form changed. Reload before answering.');
  // Stale answers for a now-hidden branch are intentionally discarded.
  return visibleQuestions(questions,p).map(q=>{
    const value=questionText(p['answer_'+q.id]??'',q.type==='choice'?80:500,q.required);
    if(q.type==='choice'&&value&&!q.options.includes(value))fail('Choose one of the listed answers.');
    return{id:q.id,value};
  });
}
export function bookingRoutes(raw=[]) {
  if(!Array.isArray(raw)||raw.length>4)fail('Use up to four booking routes.');
  const ids=new Set();
  return raw.map(r=>{
    if(!r||typeof r!=='object'||Array.isArray(r)||typeof r.id!=='string'||!/^route-[1-4]$/.test(r.id)||ids.has(r.id))fail('Choose a valid booking route.');
    ids.add(r.id);
    const question_id=text(r.question_id??'',10);
    if(question_id&&!/^q-[1-4]$/.test(question_id))fail('Choose an inquiry question for this route.');
    return{id:r.id,name:text(r.name??'',80),question_id,equals:questionText(r.equals??'',80),url:httpsUrl(r.url),button_label:text(r.button_label??'',60)};
  });
}
export function bookingRoutesReady(d) {
  const routes=bookingRoutes(d.booking_routes),questions=questionsReady(d.questions),seen=new Set();
  for(const r of routes){
    const q=questions.find(q=>q.id===r.question_id),key=JSON.stringify([r.question_id,r.equals]);
    if(!r.name||!r.url||!r.button_label||!q||q.type!=='choice'||!r.equals||!q.options.includes(r.equals)||seen.has(key))fail('Complete each booking route with a name, current multiple-choice answer, HTTPS link and button text. Use each answer condition once.');
    seen.add(key);
  }
  return routes;
}
export function bookingOutcome(d,answers=[]) {
  const active=new Set(visibleQuestions(d.questions,Object.fromEntries(answers.map(a=>['answer_'+a.id,a.value]))).map(q=>q.id));
  const route=bookingRoutesReady(d).find(r=>active.has(r.question_id)&&answers.some(a=>a.id===r.question_id&&a.value.trim()===r.equals));
  return{route_id:route?.id??'default',route_name:route?.name??'Default next step',message:d.thank_you,
    booking_url:route?.url??d.booking_url??'',button_label:route?.button_label??'Continue →'};
}
export function pageSections(raw) {
  if(raw===undefined)return defaultSections();
  if(!Array.isArray(raw)||raw.length<4||raw.length>8)fail('Use the four standard sections and up to four text sections.');
  const seen=new Set();
  const sections=raw.map(s=>{
    if(!s||typeof s!=='object'||Array.isArray(s))fail('Choose a valid page section.');
    const visible=s.visible===undefined?true:s.visible;
    if(typeof visible!=='boolean')fail('Choose whether the section is visible.');
    if(s.kind==='text'){
      if(typeof s.id!=='string'||!/^text-[1-4]$/.test(s.id)||seen.has(s.id)||!visible)fail('Use up to four distinct text sections.');
      seen.add(s.id);return{kind:'text',id:s.id,visible:true,heading:text(s.heading??'',120),body:text(s.body??'',1000)};
    }
    if(!['main_image','benefits','inquiry','faq'].includes(s.kind)||seen.has(s.kind))fail('Keep one of each standard page section.');
    if(['inquiry','main_image'].includes(s.kind)&&!visible)fail('Keep the inquiry form and image position enabled. Remove an unwanted image in Page images.');
    seen.add(s.kind);return{kind:s.kind,visible};
  });
  if(['main_image','benefits','inquiry','faq'].some(kind=>!seen.has(kind)))fail('Keep the inquiry form and all standard section positions.');
  return sections;
}
export function document(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) fail('A page draft is required.');
  if (!['consultation', 'product', 'event'].includes(raw.layout)) fail('Choose a page template.');
  if (!['cyan', 'violet', 'gold'].includes(raw.accent)) fail('Choose a brand color.');
  const form_mode=raw.form_mode===undefined?'single':raw.form_mode;
  if(!['single','guided'].includes(form_mode))fail('Choose a single-page or guided inquiry form.');
  if (!Array.isArray(raw.benefits) || raw.benefits.length > 6 || !Array.isArray(raw.faq) || raw.faq.length > 6) fail('Use up to six benefits and FAQs.');
  const result={brand:text(raw.brand,80,true),headline:text(raw.headline,160,true),subheadline:text(raw.subheadline,600,true),
    cta:text(raw.cta,60,true),thank_you:text(raw.thank_you,600,true),layout:raw.layout,accent:raw.accent,form_mode,
    benefits:raw.benefits.map(x=>text(x,180,true)),faq:raw.faq.map(x=>({q:text(x?.q,180,true),a:text(x?.a,700,true)})),
    privacy_url:httpsUrl(raw.privacy_url),booking_url:httpsUrl(raw.booking_url),
    contact_email:text(raw.contact_email ?? '',254),logo:imageReference(raw.logo),hero_image:imageReference(raw.hero_image),
    ...(raw.sections===undefined?{}:{sections:pageSections(raw.sections)}),
    ...(raw.questions===undefined?{}:{questions:inquiryQuestions(raw.questions)}),
    ...(raw.booking_routes===undefined?{}:{booking_routes:bookingRoutes(raw.booking_routes)})};
  // Leave headroom for PostgreSQL's jsonb whitespace below its existing 18 KB
  // page limit. Legacy documents retain their existing validation behavior.
  if((raw.sections!==undefined||raw.questions!==undefined||raw.booking_routes!==undefined)&&Buffer.byteLength(JSON.stringify(result),'utf8')>17200)fail('This page is too long. Shorten some copy or remove a text section before saving.');
  return result;
}
export function imageReference(raw) {
  if(raw===undefined||raw===null)return null;
  if(typeof raw!=='object'||Array.isArray(raw))fail('Choose a saved image.');
  return {id:uuid(raw.id).toLowerCase(),alt:text(raw.alt??'',180)};
}
export function publishReady(d) {
  d=document(d);
  questionsReady(d.questions);
  bookingRoutesReady(d);
  if(pageSections(d.sections).some(s=>s.kind==='text'&&(!s.heading||!s.body)))fail('Complete the heading and copy in each text section before publishing.');
  if([d.logo,d.hero_image].some(x=>x&&!x.alt))fail('Add a description for each page image before publishing.');
  if (!d.privacy_url || !/^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$/.test(d.contact_email)) fail('Add your privacy-policy URL and a valid business contact email before publishing.');
  return d;
}
export function contactInput(p) {
  const email=text(p.email,254,true).toLowerCase();
  if (!/^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$/.test(email)) fail('Enter a valid email address.');
  return {name:text(p.name,160,true),email,phone:text(p.phone ?? '',60)};
}
export function leadInput(p,d={}) {
  const contact=contactInput(p);
  if (p.consent !== 'yes') fail('Confirm that this business may respond to your request.');
  const utm={}; for(const k of ['utm_source','utm_medium','utm_campaign','utm_content','utm_term']) utm[k]=text(p[k] ?? '',120);
  const answers=inquiryAnswers(p,d);
  return {...contact,message:text(p.message ?? '',2000),utm,...(d.questions===undefined?{}:{answers})};
}
export const esc = v => String(v ?? '').replace(/[&<>"']/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
