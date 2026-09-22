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
export function document(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) fail('A page draft is required.');
  if (!['consultation', 'product', 'event'].includes(raw.layout)) fail('Choose a page template.');
  if (!['cyan', 'violet', 'gold'].includes(raw.accent)) fail('Choose a brand color.');
  const form_mode=raw.form_mode===undefined?'single':raw.form_mode;
  if(!['single','guided'].includes(form_mode))fail('Choose a single-page or guided inquiry form.');
  if (!Array.isArray(raw.benefits) || raw.benefits.length > 6 || !Array.isArray(raw.faq) || raw.faq.length > 6) fail('Use up to six benefits and FAQs.');
  return {brand:text(raw.brand,80,true),headline:text(raw.headline,160,true),subheadline:text(raw.subheadline,600,true),
    cta:text(raw.cta,60,true),thank_you:text(raw.thank_you,600,true),layout:raw.layout,accent:raw.accent,form_mode,
    benefits:raw.benefits.map(x=>text(x,180,true)),faq:raw.faq.map(x=>({q:text(x?.q,180,true),a:text(x?.a,700,true)})),
    privacy_url:httpsUrl(raw.privacy_url),booking_url:httpsUrl(raw.booking_url),
    contact_email:text(raw.contact_email ?? '',254),logo:imageReference(raw.logo),hero_image:imageReference(raw.hero_image)};
}
export function imageReference(raw) {
  if(raw===undefined||raw===null)return null;
  if(typeof raw!=='object'||Array.isArray(raw))fail('Choose a saved image.');
  return {id:uuid(raw.id).toLowerCase(),alt:text(raw.alt??'',180)};
}
export function publishReady(d) {
  d=document(d);
  if([d.logo,d.hero_image].some(x=>x&&!x.alt))fail('Add a description for each page image before publishing.');
  if (!d.privacy_url || !/^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$/.test(d.contact_email)) fail('Add your privacy-policy URL and a valid business contact email before publishing.');
  return d;
}
export function contactInput(p) {
  const email=text(p.email,254,true).toLowerCase();
  if (!/^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$/.test(email)) fail('Enter a valid email address.');
  return {name:text(p.name,160,true),email,phone:text(p.phone ?? '',60)};
}
export function leadInput(p) {
  const contact=contactInput(p);
  if (p.consent !== 'yes') fail('Confirm that this business may respond to your request.');
  const utm={}; for(const k of ['utm_source','utm_medium','utm_campaign','utm_content','utm_term']) utm[k]=text(p[k] ?? '',120);
  return {...contact,message:text(p.message ?? '',2000),utm};
}
export const esc = v => String(v ?? '').replace(/[&<>"']/g, c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
