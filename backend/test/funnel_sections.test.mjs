import test from 'node:test';
import assert from 'node:assert/strict';
import {document,publishReady,pageSections,defaultSections} from '../funnels/core.mjs';
import {renderPage} from '../funnels/render.mjs';
import {rehearseFunnel} from '../funnels/rehearsal.mjs';
const doc={brand:'Studio',headline:'Our offer',subheadline:'Talk to us.',cta:'Inquire',thank_you:'Thank you.',benefits:['Unique benefit marker'],faq:[{q:'Unique question marker?',a:'A useful answer.'}],layout:'consultation',accent:'cyan',privacy_url:'https://example.com/privacy',booking_url:'https://example.com/book',contact_email:'hi@example.com'};
const custom={kind:'text',id:'text-1',visible:true,heading:'Meet our team',body:'We help you plan.\nAsk us about your project.'};

test('Legacy pages retain their original section order and normalization does not introduce new fields',()=>{
 const normalized=document(doc);assert.equal(normalized.sections,undefined);
 assert.deepEqual(pageSections(undefined).map(s=>s.kind),['main_image','benefits','inquiry','faq']);
 const html=renderPage(normalized);
 assert(html.indexOf('data-section="benefits"')<html.indexOf('id="contact"'));
 assert(html.indexOf('id="contact"')<html.indexOf('data-section="faq"'));
 assert.equal((html.match(/id="contact"/g)||[]).length,1);
});
test('Section validation rejects duplicate, missing, hidden mandatory and unknown blocks without accepting custom markup or references',()=>{
 const defaults=defaultSections();
 for(const invalid of [null,{},[],defaults.slice(1),[...defaults,defaults[0]], [...defaults,{kind:'html',body:'<script/>'}],
   defaults.map(s=>s.kind==='inquiry'?{...s,visible:false}:s),defaults.map(s=>s.kind==='main_image'?{...s,visible:false}:s),
   defaults.map(s=>({...s,visible:'yes'})),[...defaults,custom,{...custom}], [...defaults,{...custom,id:'" onclick="evil'}],
   [...defaults,{...custom,visible:false}], [...defaults,{...custom,body:'a'.repeat(1001)}], [...defaults,{...custom,heading:'a'.repeat(121)}],
   [...defaults,{...custom,body:'bad\x00copy'}], [...defaults,...Array.from({length:5},(_,i)=>({...custom,id:'text-'+(i+1)}))]]) {
   assert.throws(()=>document({...doc,sections:invalid}));
 }
 const safe=document({...doc,sections:[...defaults,{...custom,url:'https://evil.invalid',image:{id:'foreign'},html:'<script/>'}]});
 assert.deepEqual(safe.sections.at(-1),custom);
});
test('Reordered and hidden sections render in the same saved order while preserving one form and escaped text',()=>{
 const malicious={...custom,heading:'<img src=x onerror=alert(1)>',body:'</p><script>alert(1)</script>\nNext line'};
 const sections=[{kind:'faq',visible:false},malicious,{kind:'inquiry'},{kind:'main_image'},{kind:'benefits',visible:false}];
 const d=document({...doc,sections}),html=renderPage(d,{action:'/f/example/lead#contact',token:'signed',mediaBase:'/f/example/media'});
 assert(!html.includes('Unique benefit marker'));assert(!html.includes('Unique question marker'));
 assert(!html.includes('<script>'));assert(!html.includes('<img src=x'));
 assert(html.includes('&lt;script&gt;'));assert(html.indexOf('data-section="text-1"')<html.indexOf('id="contact"'));
 assert.equal((html.match(/<form\b/g)||[]).length,1);assert(html.includes('href="#contact"'));
 assert.equal(d.benefits[0],doc.benefits[0]);assert.equal(d.faq[0].q,doc.faq[0].q);
 const preview=renderPage(d,{preview:true});assert.match(preview,/Submissions are disabled/);
 for(const button of preview.matchAll(/<button\b[^>]*>/g))assert.match(button[0],/disabled/);
});
test('Custom sections allow unfinished drafts, require complete copy for publication and retain line breaks',()=>{
 const d=document({...doc,sections:[...defaultSections(),{...custom,heading:'',body:''}]});
 assert.equal(d.sections.at(-1).heading,'');assert.throws(()=>publishReady(d),/Complete the heading/);
 assert.equal(publishReady({...doc,sections:[...defaultSections(),custom]}).sections.at(-1).body,custom.body);
 const snapshot={version:1,state:'draft',name:'Page',workflow:null};
 const result=rehearseFunnel(snapshot,{version:1,name:'Page',source:'draft',scenario:'valid',document:d});
 assert.equal(result.accepted_in_scenario,false);assert.deepEqual(result.tasks,[]);
});
test('A multilingual page over the existing document budget fails clearly before database storage',()=>{
 const large={...doc,subheadline:'詳'.repeat(600),thank_you:'詳'.repeat(600),benefits:Array(6).fill('詳'.repeat(180)),
 faq:Array.from({length:6},()=>({q:'詳'.repeat(180),a:'詳'.repeat(700)})),sections:[...defaultSections(),...Array.from({length:4},(_,i)=>({...custom,id:'text-'+(i+1),body:'詳'.repeat(1000)}))]};
 assert.throws(()=>document(large),/page is too long/);
 assert.equal(document({...doc,sections:[...defaultSections(),custom]}).sections.length,5);
});
test('Reordered guided journeys and receipts use the inquiry section once without altering consent or booking behavior',()=>{
 const d=publishReady({...doc,form_mode:'guided',sections:[{kind:'inquiry'},custom,{kind:'faq'},{kind:'benefits'},{kind:'main_image'}]});
 for(const step of ['contact','request','review']){
  const html=renderPage(d,{step,token:'signed',stepAction:'/f/example/step#contact',action:'/f/example/lead#contact',values:{name:'A',email:'a@example.com',message:'Hello'},reviewToken:'review'});
  assert.equal((html.match(/id="contact"/g)||[]).length,1);
  assert(html.indexOf('id="contact"')<html.indexOf('data-section="text-1"'));
  assert.match(html,/Inquiry progress/);
 }
 const receipt=renderPage(d,{success:true});assert.equal((receipt.match(/class="success"/g)||[]).length,1);
 assert(!receipt.includes('<form'));assert(receipt.includes('https://example.com/book'));assert(receipt.includes(custom.heading));
});
