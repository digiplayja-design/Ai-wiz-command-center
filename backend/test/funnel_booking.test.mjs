import test from 'node:test';
import assert from 'node:assert/strict';
import {document,publishReady,bookingRoutesReady,bookingOutcome,leadInput} from '../funnels/core.mjs';
import {renderPage} from '../funnels/render.mjs';
import {leadCsv} from '../funnels/inbox.mjs';
import {rehearseFunnel} from '../funnels/rehearsal.mjs';
const questions=[{id:'q-1',type:'choice',label:'Service',required:true,options:['Install','Advice']},{id:'q-2',type:'choice',label:'Property',required:false,options:['Home','Office'],show_when:{question_id:'q-1',equals:'Install'}}];
const route={id:'route-1',name:'Home visit',question_id:'q-2',equals:'Home',url:'https://example.com/home',button_label:'Book a home visit'};
const doc={brand:'Studio',headline:'Hello',subheadline:'Welcome',cta:'Send',thank_you:'We received your inquiry.',benefits:[],faq:[],layout:'consultation',accent:'cyan',privacy_url:'https://example.com/privacy',contact_email:'team@example.com',booking_url:'https://example.com/default',questions,booking_routes:[route]};
test('Booking definitions are bounded, normalized, and preserve incomplete drafts until publication',()=>{
 assert.equal(document({...doc,booking_routes:[{id:'route-1'}]}).booking_routes[0].url,'');
 assert.throws(()=>publishReady({...doc,booking_routes:[{id:'route-1'}]}),/Complete each booking/);
 assert.equal(bookingRoutesReady({...doc,booking_routes:[{...route,url:'https://example.com'}]})[0].url,'https://example.com/');
 for(const patch of [{id:'route-5'},{url:'javascript:alert(1)'},{url:'https://user:password@example.com'},{url:'http://example.com'},{name:'x'.repeat(81)},{button_label:'x'.repeat(61)},{question_id:'q-5'},{equals:'\x7f'}]) assert.throws(()=>document({...doc,booking_routes:[{...route,...patch}]}));
 assert.throws(()=>document({...doc,booking_routes:Array(5).fill(route)}));
 assert.throws(()=>document({...doc,booking_routes:[route,route]}));
 for(const patch of [{question_id:'q-3'},{equals:'Deleted'},{url:''},{name:''},{button_label:''}])assert.throws(()=>publishReady({...doc,booking_routes:[{...route,...patch}]}));
 assert.throws(()=>publishReady({...doc,booking_routes:[route,{...route,id:'route-2'}]}),/Use each/);
 assert.throws(()=>publishReady({...doc,questions:[questions[0],{...questions[1],type:'text',options:[]}]}));
});
test('Routing uses first active matching answer, fallback, and no-link receipts',()=>{
 const d=publishReady({...doc,booking_routes:[route,{id:'route-2',name:'Install team',question_id:'q-1',equals:'Install',url:'https://example.com/install',button_label:'Talk to installer'}]});
 const input=leadInput({name:'Visitor',email:'visitor@example.com',consent:'yes','answer_q-1':'Install','answer_q-2':'Home'},d);
 assert.equal(bookingOutcome(d,input.answers).route_id,'route-1');
 assert.equal(bookingOutcome({...d,booking_routes:[...d.booking_routes].reverse()},input.answers).route_id,'route-2');
 const hidden=[{id:'q-1',value:'Advice'},{id:'q-2',value:'Home'}];
 assert.equal(bookingOutcome(d,hidden).booking_url,doc.booking_url);
 assert.equal(bookingOutcome({...d,booking_url:''},hidden).booking_url,'');
});
test('Receipts render only saved escaped content and exported outcomes remain spreadsheet-safe',()=>{
 const outcome={route_id:'route-1',route_name:'=1+1',message:'Saved <thank you>',booking_url:'https://example.com/book?x=1&y=2',button_label:'Book <now>'};
 const html=renderPage({...doc,thank_you:'Current copy',booking_url:'https://example.com/changed'},{success:true,receipt:outcome});
 assert.match(html,/Saved &lt;thank you&gt;/);assert.match(html,/Book &lt;now&gt;/);assert.match(html,/book\?x=1&amp;y=2/);assert(!html.includes('https://example.com/changed'));assert(!html.includes('=1+1'));assert.match(html,/rel="noopener noreferrer"/);
 const csv=leadCsv([{outcome}]);assert.match(csv,/"Next step offered","Next-step URL","Next-step button"/);assert(csv.includes('"\'=1+1"'));assert(!leadCsv([{}]).includes('undefined'));
});
test('Rehearsal reports the first-choice outcome while follow-ups retain the default URL and no side effects',()=>{
 const d={...doc,booking_routes:[{...route,question_id:'q-1',equals:'Install'}]};
 const r=rehearseFunnel({version:1,state:'draft',workflow:{enabled:true,email_enabled:true,delay_minutes:0,subject:'Hello',body:'{{booking_url}}'}},{source:'draft',scenario:'valid',version:1,name:'Studio',document:d});
 assert.equal(r.receipt.route_id,'route-1');assert.equal(r.receipt.booking_url,route.url);assert.equal(r.tasks[0].body,doc.booking_url);assert.deepEqual(r.performed_actions,[]);assert.equal(r.delivery_tested,false);
});
