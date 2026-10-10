'use strict';
const API='https://chee-chai-chee-backend.onrender.com/api/directory';
const root=document.querySelector('#passport');
const el=(tag,value,cls)=>{const n=document.createElement(tag);if(value!=null)n.textContent=value;if(cls)n.className=cls;return n;};
const panel=(title,cls='')=>{const n=el('section',null,'panel '+cls);n.append(el('h2',title));return n;};
const photo=(b,id)=>`${API}/businesses/${encodeURIComponent(b.id)}/photos/${encodeURIComponent(id)}`;
const passportLink=b=>location.origin+'/business-directory/passport.html?business='+encodeURIComponent(b.slug);
async function request(path,body){const r=await fetch(API+path,body?{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}:{});const data=await r.json();if(!r.ok)throw Error(data.error||'This Business Passport is unavailable.');return data;}
function track(b,kind){request(`/businesses/${encodeURIComponent(b.id)}/metrics`,{kind}).catch(()=>{});}
function download(bytes,name,type){const url=URL.createObjectURL(new Blob([bytes],{type})),a=el('a');a.href=url;a.download=name;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),30000);}
function external(value){try{const u=new URL(value);return ['https:','http:'].includes(u.protocol)&&!u.username&&!u.password?u.href:null;}catch{return null;}}
function action(label,address,b,primary=false){const a=el('a',null,'passport-action'+(primary?' primary':''));a.append(el('span',label),el('span','↗'));a.href=address;if(/^https?:/.test(address)){a.target='_blank';a.rel='noopener noreferrer';}a.onclick=()=>track(b,'contact');return a;}
function saveContact(b){const d=b.details,escape=v=>String(v||'').replace(/\\/g,'\\\\').replace(/\r\n|\r|\n/g,'\\n').replace(/,/g,'\\,').replace(/;/g,'\\;');
  const lines=['BEGIN:VCARD','VERSION:3.0','FN:'+escape(d.name),'ORG:'+escape(d.name)];
  if(d.phone)lines.push('TEL;TYPE=WORK:'+d.phone.replace(/[^+\d]/g,''));if(d.email)lines.push('EMAIL;TYPE=WORK:'+escape(d.email));
  lines.push('URL:'+passportLink(b),'NOTE:'+escape(d.tagline||d.description),'END:VCARD');download(lines.join('\r\n')+'\r\n','business-contact.vcf','text/vcard;charset=utf-8');
}
function sharePanel(b,mobile=false){
  const box=panel('Keep this connection',mobile?'share-panel mobile-share':'share-panel'),status=el('div','','share-status');status.setAttribute('role','status');
  const qr=el('div',null,'qr-box'),img=el('img');img.src=`${API}/businesses/${encodeURIComponent(b.slug)}/passport-qr`;img.alt='QR code for '+b.details.name;img.width=104;img.height=104;
  img.onerror=()=>{img.hidden=true;status.textContent='QR unavailable. You can still copy the Passport link.';};qr.append(img,el('p','Scan to open this business’s services, contact details and booking page.'));box.append(qr);
  const row=el('div',null,'share-row');
  for(const [label,fn]of[
    ['Share',async()=>{if(navigator.share){try{await navigator.share({title:b.details.name+' · Business Passport',url:passportLink(b)});}catch(e){if(e.name!=='AbortError')throw e;}}else{await navigator.clipboard.writeText(passportLink(b));status.textContent='Passport link copied.';}}],
    ['Copy link',async()=>{await navigator.clipboard.writeText(passportLink(b));status.textContent='Passport link copied.';}],
    ['Save contact',async()=>saveContact(b)],
    ['Save QR',async()=>{const r=await fetch(img.src);if(!r.ok)throw Error('The QR code could not be downloaded.');download(await r.arrayBuffer(),'business-passport-qr.png','image/png');status.textContent='QR code downloaded.';}],
    ['Print',async()=>window.print()],
  ]){const button=el('button',label,'share-btn');button.type='button';button.onclick=async()=>{try{await fn();}catch(e){status.textContent=e.message||'Sharing is unavailable. Copy the page address from your browser.';}};row.append(button);}
  box.append(row,status);return box;
}
function render(b){
  const d=b.details;if(!d||!d.name)throw Error('This Business Passport is unavailable.');
  document.title=d.name+' · Business Passport · KORLIX';document.querySelector('meta[name="description"]').content=(d.tagline||d.description||'').slice(0,160);
  const canonical=el('link');canonical.rel='canonical';canonical.href=passportLink(b);document.head.append(canonical);
  const hero=el('section',null,'passport-hero');
  const placeholder=()=>el('div',null,'hero-cover placeholder');
  if(d.photos?.length){const cover=el('img',null,'hero-cover');cover.src=photo(b,d.photos[0]);cover.alt=d.name+' business photo';cover.fetchPriority='high';cover.onerror=()=>cover.replaceWith(placeholder());hero.append(cover);}else hero.append(placeholder());
  const identity=el('div',null,'identity'),top=el('div',null,'identity-top');
  top.append(el('div',d.name.split(/\s+/).slice(0,2).map(s=>Array.from(s)[0]).join('').toUpperCase(),'monogram'));
  if(b.verified){const badge=el('button','✓ VERIFIED BUSINESS','verified-pill');badge.onclick=()=>alert('KORLIX checked the owner’s business email, phone and ownership evidence. The membership is active. Verification is not a guarantee of service quality, licensing or insurance.');top.append(badge);}
  identity.append(top,el('p',d.category||'BUSINESS PASSPORT','passport-label'),el('h1',d.name));
  if(d.tagline)identity.append(el('p',d.tagline,'tagline'));
  const chips=el('div',null,'chips');for(const value of [[d.city,d.country].filter(Boolean).join(', ')||d.service_area,d.languages].filter(Boolean))chips.append(el('span',value,'chip'));identity.append(chips);hero.append(identity);
  const grid=el('div',null,'passport-grid'),main=el('div',null,'passport-main'),aside=el('aside',null,'aside');
  const about=panel('Meet '+d.name);about.append(el('p',d.description,'preline'));main.append(about);
  const services=String(d.services||d.specialties||'').split(/\n/).map(s=>s.trim()).filter(Boolean).slice(0,12);
  if(services.length){const box=panel('What we can help with'),list=el('div',null,'services-list');for(const service of services){const parts=service.split('|');const row=el('div',null,'service');row.append(el('span',parts.shift().trim()));if(parts.length)row.append(el('strong',parts.join('|').trim()));list.append(row);}box.append(list);main.append(box);}
  if(d.photos?.length){const box=panel('A closer look'),gallery=el('div',null,'work-gallery');d.photos.forEach((id,index)=>{const img=el('img');img.src=photo(b,id);img.alt=`${d.name} · work photo ${index+1}`;img.loading='lazy';img.onerror=()=>img.hidden=true;gallery.append(img);});box.append(gallery);main.append(box);}
  if(d.offer?.text){const box=panel('From the business','offer');box.append(el('p',d.offer.text),el('p','Available until '+d.offer.expires));main.append(box);}
  const info=panel('Good to know'),list=el('dl',null,'info-list');
  for(const [label,value]of[['Opening hours',d.hours],['Service area',d.service_area],['Location',[d.address,d.city,d.country].filter(Boolean).join(', ')],['Languages',d.languages],['Accessibility',d.accessibility],['Public contact',d.public_contact_name]])if(value){const item=el('div');item.append(el('dt',label),el('dd',value));list.append(item);}
  if(list.childElementCount){info.append(list);main.append(info);}main.append(sharePanel(b,true));
  const contact=panel('Let’s connect.','contact-panel');contact.append(el('p','Ask a question, discuss your next project or choose a time to meet.'));
  const actions=el('div',null,'contact-actions');
  if(b.booking&&external(b.booking.url)){actions.append(action('Book an appointment',b.booking.url,b,true));contact.append(el('p',b.booking.title+' · '+b.booking.durationMinutes+' min','booking-note'));}
  if(d.phone)actions.append(action('Call business','tel:'+d.phone.replace(/[^+\d]/g,''),b));
  if(d.email)actions.append(action('Email business','mailto:'+d.email,b));
  if(external(d.website))actions.append(action('Visit website',external(d.website),b));
  if(external(d.social))actions.append(action('Social page',external(d.social),b));
  if(d.address)actions.append(action('Get directions','https://www.google.com/maps/search/?api=1&query='+encodeURIComponent([d.address,d.city,d.country].filter(Boolean).join(', ')),b));
  contact.append(actions);aside.append(contact,sharePanel(b));
  const fine=el('div',null,'fine');fine.append(el('p','Business information is supplied by its owner. Confirm prices and arrangements directly with the business.'));
  const report=el('button','Report this Passport','report');report.onclick=async()=>{const reason=prompt('What should KORLIX review? Describe inaccurate information or another concern (10–1,000 characters).');if(!reason)return;try{await request(`/businesses/${encodeURIComponent(b.id)}/report`,{reason});alert('Your report was submitted for review.');}catch(e){alert(e.message);}};fine.append(report);aside.append(fine);
  grid.append(main,aside);root.replaceChildren(hero,grid);track(b,'view');
}
(async()=>{try{const slug=new URLSearchParams(location.search).get('business');if(!slug||!/^[a-z0-9-]{1,120}$/.test(slug))throw Error('Choose a business from the KORLIX Directory.');render(await request('/businesses/'+encodeURIComponent(slug)));}catch(e){const box=el('section',null,'panel unavailable');box.append(el('p','BUSINESS PASSPORT','passport-label'),el('h1','Let’s find your business.'),el('p',e.message));const a=el('a','Explore the directory');a.href='/business-directory/';box.append(a);root.replaceChildren(box);}})();
