import test from 'node:test';
import assert from 'node:assert/strict';
import {document,publishReady,leadInput,inquiryQuestions,inquiryAnswers} from '../funnels/core.mjs';
import {renderPage} from '../funnels/render.mjs';
import {leadCsv} from '../funnels/inbox.mjs';
import {rehearseFunnel} from '../funnels/rehearsal.mjs';
const doc={brand:'Studio',headline:'Talk with us',subheadline:'Your next step',cta:'Inquire',thank_you:'Thanks',layout:'product',accent:'cyan',benefits:[],faq:[],privacy_url:'https://example.com/privacy',contact_email:'team@example.com'};
const qs=[{id:'q-1',type:'text',label:'What are your goals?',required:true,options:[]},{id:'q-2',type:'choice',label:'When?',required:false,options:['Now','Later']}];
const input={name:'Visitor',email:'visitor@example.com',consent:'yes','answer_q-1':'A useful answer','answer_q-2':'Later'};
test('Question drafts, publication requirements and bounded definitions reject malformed inputs',()=>{
 assert.equal(document(doc).questions,undefined);
 for(const raw of [null,{},Array(5).fill(qs[0]),[qs[0],qs[0]],[{...qs[0],id:['q-1']}],[{...qs[0],type:'html'}],[{...qs[0],required:'yes'}],[{...qs[0],label:'a'.repeat(121)}],[{...qs[1],options:Array(9).fill('x')}],[{...qs[1],options:['a'.repeat(81),'b']}]])assert.throws(()=>inquiryQuestions(raw));
 for(const q of [{...qs[0],label:''},{...qs[1],options:['One']},{...qs[1],options:['Same',' Same ']},{...qs[1],options:['','B']}]) {
  assert.equal(document({...doc,questions:[q]}).questions.length,1);
  assert.throws(()=>publishReady({...doc,questions:[q]}),/Complete each question/);
 }
 assert.deepEqual(publishReady({...doc,questions:qs}).questions,qs);
 assert.equal(inquiryQuestions([{...qs[0],html:'<script/>'}])[0].html,undefined);
});
test('Answer validation binds fields to the published definition and respects optional answers',()=>{
 assert.deepEqual(inquiryAnswers(input,{questions:qs}),[{id:'q-1',value:'A useful answer'},{id:'q-2',value:'Later'}]);
 for(const patch of [{'answer_q-1':''},{'answer_q-1':['duplicate']},{'answer_q-1':'a'.repeat(501)},{'answer_q-2':'Unlisted'},{'answer_q-3':'Unknown'}])assert.throws(()=>leadInput({...input,...patch},{questions:qs}));
 assert.equal(leadInput({...input,'answer_q-2':''},{questions:qs}).answers[1].value,'');
 assert.throws(()=>leadInput(input,doc),/form changed/);
});
test('Escaped rendering, disabled previews, CSV and rehearsal include questions without live actions',()=>{
 const d=publishReady({...doc,questions:[{...qs[0],label:'<script>Question</script>'},qs[1]]});
 const html=renderPage(d,{values:{...input,'answer_q-1':'</textarea><script>alert(1)</script>'},preview:true});
 assert(!html.includes('<script>'));assert(html.includes('&lt;script&gt;'));assert.match(html,/<textarea name="answer_q-1" maxlength="500" required>/);assert.match(html,/<option value="Later" selected>/);assert.match(html,/<button type="submit" disabled>/);
 const csv=leadCsv([{answers:[{label:'=SUM(A1)',value:'"quoted"\nline'}]}]);assert(csv.includes('Question answers'));assert(csv.includes('"\'=SUM(A1): ""quoted""\nline"'));
 const result=rehearseFunnel({version:1,state:'draft',workflow:null},{version:1,name:'Page',source:'draft',scenario:'valid',document:d});
 assert.equal(result.accepted_in_scenario,true);assert.equal(result.sample['answer_q-1'],'Sample response');assert.equal(result.sample['answer_q-2'],'Now');assert.deepEqual(result.performed_actions,[]);
});
