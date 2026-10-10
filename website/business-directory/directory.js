'use strict';
const API='https://chee-chai-chee-backend.onrender.com/api/directory';
const $=s=>document.querySelector(s),el=(tag,text,cls)=>{const n=document.createElement(tag);if(text!=null)n.textContent=text;if(cls)n.className=cls;return n;};
function showMembershipReturn(){
  const state=new URLSearchParams(location.search).get('membership'),banner=$('#membership-return');
  if(!banner)return;
  banner.hidden=!['return','cancel'].includes(state);
  if(banner.hidden)return;
  $('#membership-return-title').textContent=state==='cancel'?'Checkout closed':'Check your membership status';
  $('#membership-return-message').textContent=state==='cancel'
    ?'To check for a completed payment or resume checkout, open Business Directory → My Businesses in KORLIX and choose Refresh membership.'
    :'Welcome back from checkout. Open Business Directory → My Businesses in KORLIX and choose Refresh membership to confirm your payment and membership status.';
}
showMembershipReturn();
let page=0,rows=[],savedOnly=false,request=0,detailTicket=0,favorites=new Set();try{favorites=new Set(JSON.parse(localStorage.getItem('korlix_directory_favorites_v1')||'[]'));}catch{}
function remember(id){if(favorites.has(id))favorites.delete(id);else if(favorites.size<50)favorites.add(id);try{localStorage.setItem('korlix_directory_favorites_v1',JSON.stringify([...favorites]));}catch{}if(savedOnly)search();else render();}
async function api(path,body){const r=await fetch(API+path,body?{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}:{});const d=await r.json();if(!r.ok)throw Error(d.error||'Please try again.');return d;}
const photo=(b,id)=>`${API}/businesses/${encodeURIComponent(b.id)}/photos/${encodeURIComponent(id)}`;
const categoryLook = category => {
  if (/Food|Travel|Hospitality/.test(category)) return ['amber', 'cup'];
  if (/Beauty|Arts/.test(category)) return ['rose', 'spark'];
  if (/Health|Agriculture|Community/.test(category)) return ['green', 'leaf'];
  if (/Technology|Professional|Education/.test(category)) return ['violet', 'spark'];
  return ['cyan', 'shop'];
};
function icon(name) {
  const paths = {
    shop: 'M3 10h18M5 10v10h14V10M3 10l2-6h14l2 6M9 20v-6h6v6',
    cup: 'M4 8h12v6a6 6 0 0 1-12 0V8M16 9h2a3 3 0 0 1 0 6h-2M6 3v2M11 3v2M3 21h15',
    spark: 'm12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5L12 3Z',
    leaf: 'M20 4C8 2 2 9 6 16s16 2 14-12ZM4 21l11-11',
    pin: 'M20 10c0 6-8 11-8 11S4 16 4 10a8 8 0 1 1 16 0ZM15 10a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z',
    arrow: 'M5 12h14m-6-6 6 6-6 6',
    heart: 'M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z',
    check: 'M12 2 4 5v6c0 5 8 11 8 11s8-6 8-11V5l-8-3Zm-4 9 3 3 5-6',
  };
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  for (const [key,value] of Object.entries({viewBox:'0 0 24 24',fill:'none',stroke:'currentColor','stroke-width':'1.7','stroke-linecap':'round','stroke-linejoin':'round','aria-hidden':'true',class:'icon'})) svg.setAttribute(key,value);
  const path = document.createElementNS(svg.namespaceURI,'path'); path.setAttribute('d',paths[name] || paths.shop); svg.append(path); return svg;
}
function placeholder(b, cls) {
  const name = b.details.name || 'Business';
  const initials = name.trim().split(/\s+/).slice(0,2).map(word=>Array.from(word)[0]).join('').toUpperCase();
  const node = el('div', initials, cls+' placeholder'); node.setAttribute('aria-label',name); return node;
}
function cover(b, cls='cover') {
  const d=b.details;
  if (d.photos?.length) {
    const img=el('img',null,cls); img.src=photo(b,d.photos[0]); img.alt=d.name; img.loading='lazy'; img.referrerPolicy='no-referrer';
    img.onerror=()=>img.replaceWith(placeholder(b,cls)); return img;
  }
  return placeholder(b,cls);
}
function verified(b) {
  const n=el('button',null,'badge'); n.append(icon('check'),document.createTextNode('VERIFIED'));
  n.type='button'; n.setAttribute('aria-label','About this verified business'); n.title='KORLIX Verified Business';
  n.onclick=()=>alert(`KORLIX checked this owner's business email, phone and ownership evidence on ${new Date(b.verified_at).toLocaleDateString()}. The membership is active. Verification is not a guarantee of service quality.`); return n;
}
function shortcuts() {
  const container=$('#category-shortcuts'); if(!container)return;
  container.replaceChildren();
  for(const [category,label] of [['','All businesses'],['Food & Drink','Food & drink'],['Retail & Shopping','Shopping'],['Professional Services','Services'],['Health & Wellness','Wellness'],['Technology','Technology']]) {
    const button=el('button',null,'category-shortcut'); button.type='button';
    button.append(icon(categoryLook(category)[1]),document.createTextNode(label)); button.setAttribute('aria-pressed',String($('#category').value===category));
    button.onclick=()=>{$('#category').value=category;page=0;search();};container.append(button);
  }
}
function render() {
  const grid=$('#results');grid.replaceChildren();
  const list=savedOnly?rows.filter(b=>favorites.has(b.id)):rows;
  if(!list.length) {
    const empty=el('div',null,'empty');empty.append(icon(savedOnly?'heart':'shop'),el('h3',savedOnly?'Your favorites belong here.':'Your next discovery is out there.'),
      el('p',savedOnly?'No saved businesses on this results page. Explore the directory and save the ones you love.':'No businesses match yet. Try another location or category, or give your business its own place in the directory.'));
    const action=el('a',savedOnly?'Explore businesses ↗':'Add your business — free ↗','button');action.href=savedOnly?'/business-directory/':'/app/';empty.append(action);grid.append(empty);return;
  }
  for(const b of list) {
    const d=b.details,[tone,symbol]=categoryLook(d.category),card=el('article',null,'card tone-'+tone);
    const visual=el('div',null,'card-visual'),category=el('span',null,'cover-category');category.append(icon(symbol),document.createTextNode(d.category));visual.append(cover(b),category);card.append(visual);
    const body=el('div',null,'card-body'),title=el('div',null,'card-title');title.append(el('h3',d.name));if(b.verified)title.append(verified(b));body.append(title);
    const location=el('span',null,'location');location.append(icon('pin'),document.createTextNode([d.city,d.country].filter(Boolean).join(', ')||d.service_area||'Contact for location'));body.append(location);
    body.append(el('p',d.description.slice(0,150)+(d.description.length>150?'…':'')));
    const actions=el('div',null,'card-actions'),open=el('a','View Passport'),save=el('button',null,'quiet');
    open.append(icon('arrow'));open.href='passport.html?business='+encodeURIComponent(b.slug);
    save.type='button';save.append(icon('heart'),document.createTextNode(favorites.has(b.id)?'Saved':'Save'));save.setAttribute('aria-pressed',String(favorites.has(b.id)));save.setAttribute('aria-label',`${favorites.has(b.id)?'Unsave':'Save'} ${d.name}`);save.onclick=()=>remember(b.id);
    actions.append(open,save);body.append(actions);card.append(body);grid.append(card);
  }
}
async function search(){const ticket=++request;$('#status').textContent='Finding businesses…';const params=new URLSearchParams({q:$('#query').value,city:$('#city').value,category:$('#category').value,offset:String(page*25),...(savedOnly?{ids:[...favorites].join(',')||'00000000-0000-0000-0000-000000000000'}:{})});try{const d=await api('/businesses?'+params);if(ticket!==request)return;rows=d.businesses;if($('#category').options.length===1)for(const c of d.categories){const o=el('option',c);o.value=c;$('#category').append(o);}shortcuts();render();$('#status').textContent=`${rows.length} businesses on this page`;}catch(e){if(ticket===request)$('#status').textContent=e.message;}$('#previous').disabled=page===0;$('#next').disabled=rows.length<25;}
function track(b,kind){api(`/businesses/${b.id}/metrics`,{kind}).catch(()=>{});}
function link(label,url,b){const a=el('a',label,'button small');a.href=url;if(/^https?:/.test(url)){a.target='_blank';a.rel='noopener noreferrer';}a.onclick=()=>track(b,'contact');return a;}
async function show(slug){const ticket=++detailTicket;const dialog=$('#detail'),content=$('#detail-content');content.replaceChildren(el('p','Loading business…'));if(!dialog.open)dialog.showModal();try{const b=await api('/businesses/'+encodeURIComponent(slug)),d=b.details;if(ticket!==detailTicket||!dialog.open)return;dialog.className='tone-'+categoryLook(d.category)[0];const heading=el('div',null,'detail-heading');heading.append(el('p',d.category,'eyebrow'),el('h2',d.name),el('p',[d.city,d.country].filter(Boolean).join(', ')||d.service_area||'','location'));content.replaceChildren(cover(b,'detail-photo'),heading);document.title=d.name+' | KORLIX Business Directory';if(b.verified)content.append(verified(b));content.append(el('p',d.description,'detail-description'));const actions=el('div',null,'contact-actions');if(d.phone)actions.append(link('Call business','tel:'+d.phone.replace(/[^+\d]/g,''),b));if(d.email)actions.append(link('Email business','mailto:'+d.email,b));if(d.website)actions.append(link('Visit website ↗',d.website,b));if(d.social)actions.append(link('Social page ↗',d.social,b));if(d.address)actions.append(link('Directions ↗','https://www.google.com/maps/search/?api=1&query='+encodeURIComponent([d.address,d.city,d.country].filter(Boolean).join(', ')),b));content.append(actions);
const info=el('div',null,'details-grid');for(const [label,value]of [['Location',[d.address,d.city,d.country].filter(Boolean).join(', ')],['Service area',d.service_area],['Business hours',d.hours],['Specialties',d.specialties],['Languages',d.languages],['Accessibility',d.accessibility],['Contact',d.public_contact_name]])if(value){const block=el('div');block.append(el('strong',label),el('p',value,'detail-description'));info.append(block);}content.append(info);
if(d.offer?.text)content.append(el('p',`${d.offer.text} · Until ${d.offer.expires}`,'notice'));
if(d.photos?.length>1){const gallery=el('div',null,'gallery');for(const id of d.photos.slice(1)){const img=el('img');img.src=photo(b,id);img.alt=d.name+' company photo';img.loading='lazy';gallery.append(img);}content.append(gallery);}
const controls=el('div',null,'contact-actions detail-controls'),share=el('button','Copy listing link','quiet'),print=el('button','Print listing','quiet'),report=el('button','Report listing','quiet');share.onclick=async()=>{try{await navigator.clipboard.writeText(location.origin+'/business-directory/?business='+encodeURIComponent(b.slug));share.textContent='Link copied';}catch{prompt('Copy this listing link',location.href);}};print.onclick=()=>window.print();report.onclick=async()=>{const reason=prompt('What should KORLIX review? Describe incorrect information, a duplicate, spam or another concern (10–1,000 characters).');if(!reason)return;try{await api(`/businesses/${b.id}/report`,{reason});alert('Report submitted for review.');}catch(e){alert(e.message);}};controls.append(share,print,report);content.append(controls,el('p','Business information is provided by its owner. Confirm details with the business before making arrangements.','location'));track(b,'view');}catch(e){content.replaceChildren(el('p',e.message));}}
$('#search').onsubmit=e=>{e.preventDefault();page=0;search();};$('#previous').onclick=()=>{page=Math.max(0,page-1);search();};$('#next').onclick=()=>{page++;search();};$('#favorites').onclick=()=>{savedOnly=!savedOnly;$('#favorites').setAttribute('aria-pressed',String(savedOnly));$('#favorites').textContent=savedOnly?'Show all businesses':'♡ Saved businesses';page=0;search();};$('#close').onclick=()=>$('#detail').close();$('#detail').addEventListener('close',()=>{detailTicket++;history.replaceState({},'','/business-directory/');document.title='KORLIX Business Directory';});window.addEventListener('popstate',()=>{const slug=new URLSearchParams(location.search).get('business');if(slug)show(slug);else $('#detail').close();});search();const initial=new URLSearchParams(location.search);if(initial.get('business'))location.replace('passport.html?business='+encodeURIComponent(initial.get('business')));
