export class DirectoryError extends Error { constructor(message,status=400){super(message);this.status=status;} }
export const fail=(message,status=400)=>{throw new DirectoryError(message,status);};
export const id=v=>{if(typeof v!=='string'||!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(v))fail('Choose a valid business or file.');return v;};
export const text=(v,max=200,required=false)=>{if(v!=null&&typeof v!=='string')fail('Use text for this field.');const s=(v||'').trim();if(s.length>max||(required&&!s))fail(`Complete the required fields; maximum ${max} characters.`);return s;};
export const CATEGORIES=['Food & Drink','Retail & Shopping','Home & Property','Construction & Trades','Health & Wellness','Beauty & Personal Care','Professional Services','Technology','Automotive','Transport & Delivery','Education','Arts & Entertainment','Travel & Hospitality','Agriculture','Community & Nonprofit','Other'];
export const PRICES={month:499,year:4900};
export function url(v){const s=text(v,500);if(!s)return '';let u;try{u=new URL(s);}catch{fail('Use a complete https:// website address.');}if(!['https:','http:'].includes(u.protocol)||u.username||u.password)fail('Use a public http or https website address.');return u.href;}
export function details(p={}){
 if(!p||typeof p!=='object'||Array.isArray(p))fail('Enter business details.');
 const d={};for(const [k,max] of Object.entries({name:150,category:80,specialties:300,phone:40,email:254,address:250,city:100,country:100,service_area:250,description:2000,hours:500,languages:200,accessibility:300,public_contact_name:100})){d[k]=text(p[k],max,['name','category','description'].includes(k));}
 if(!CATEGORIES.includes(d.category))fail('Choose a business category.');
 if(d.email&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(d.email))fail('Enter a valid public contact email.');
 if(d.phone&&!/^[+\d() .x-]{5,40}$/i.test(d.phone))fail('Enter a valid contact phone number.');
 if(!d.phone&&!d.email)fail('Add a business phone or contact email.');
 if(!d.city&&!d.service_area)fail('Add a city or service area.');
 d.website=url(p.website);d.social=url(p.social);
 if(!Array.isArray(p.photos??[])||(p.photos??[]).length>12)fail('Choose up to 12 photos.');d.photos=[...new Set((p.photos??[]).map(id))];
 d.offer=null;if(p.offer?.text){const expires=text(p.offer.expires,10,true);if(!/^\d{4}-\d{2}-\d{2}$/.test(expires)||!Number.isFinite(Date.parse(expires)))fail('Use an offer expiry date in YYYY-MM-DD format.');d.offer={text:text(p.offer.text,400,true),expires};}
 return d;
}
export function adminIds(env){return new Set(String(env.KORLIX_DIRECTORY_ADMIN_USER_IDS||env.KORLIX_VAPI_NOVA_OWNER_UID||'').match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/ig)?.map(s=>s.toLowerCase())||[]);}
export function publicCard(card){if(!card)return null;return card;}
export function slug(name){return name.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'').slice(0,65)||'business';}
export function storeFor(db){return {async command(actor,admin,action,business,p={}){const {data,error}=await db.rpc('korlix_directory_command',{p_actor:actor||null,p_admin:admin===true,p_action:action,p_id:business||null,p});if(error){const m=/DIR(\d{3}): (.+)/.exec(error.message||'');if(m)fail(m[2],Number(m[1]));if(['23514','22P02','22007','23505'].includes(error.code))fail('Check your details and refresh before retrying.',409);fail('Directory storage is temporarily unavailable.',503);}return data;}};}
