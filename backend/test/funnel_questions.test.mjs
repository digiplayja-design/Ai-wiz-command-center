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

const branchQuestions=[
 {id:'q-1',type:'choice',label:'Service',required:true,options:['Install','Advice']},
 {id:'q-2',type:'choice',label:'Property',required:true,options:['Home','Office'],show_when:{question_id:'q-1',equals:'Install'}},
 {id:'q-3',type:'text',label:'Rooms',required:true,options:[],show_when:{question_id:'q-2',equals:'Home'}},
 {id:'q-4',type:'text',label:'Topic',required:false,options:[],show_when:{question_id:'q-1',equals:'Advice'}},
];
test('Conditional publication rejects cycles, forward, removed, non-choice and stale-choice dependencies while saving drafts',()=>{
 assert.deepEqual(publishReady({...doc,questions:branchQuestions}).questions,branchQuestions);
 for(const rule of [{question_id:'q-2',equals:'Home'},{question_id:'q-4',equals:'x'},{question_id:'q-1',equals:'Removed'},{question_id:'q-1',equals:''}]) {
  const questions=structuredClone(branchQuestions);questions[1].show_when=rule;
  assert.equal(document({...doc,questions}).questions.length,4);
  assert.throws(()=>publishReady({...doc,questions}),/condition/);
 }
 for(const rule of [[],false,'text',{question_id:['q-1'],equals:'Install'},{question_id:'q-9',equals:'Install'},{question_id:'q-1',equals:['Install']}])assert.throws(()=>inquiryQuestions([{...branchQuestions[1],show_when:rule}]));
 const moved=[branchQuestions[1],branchQuestions[0],...branchQuestions.slice(2)];assert.throws(()=>publishReady({...doc,questions:moved}),/condition/);
});
test('Chained branching enforces visible required answers and drops stale hidden data',()=>{
 const d={questions:branchQuestions},base={'answer_q-1':'Install','answer_q-2':'Home','answer_q-3':'Three','answer_q-4':'Old topic'};
 assert.deepEqual(inquiryAnswers(base,d),[{id:'q-1',value:'Install'},{id:'q-2',value:'Home'},{id:'q-3',value:'Three'}]);
 assert.throws(()=>inquiryAnswers({...base,'answer_q-3':''},d));
 assert.deepEqual(inquiryAnswers({...base,'answer_q-1':'Advice','answer_q-2':['forged'],'answer_q-3':'x'.repeat(600)},d),[{id:'q-1',value:'Advice'},{id:'q-4',value:'Old topic'}]);
 assert.deepEqual(inquiryAnswers({...base,'answer_q-2':'Office'},d),[{id:'q-1',value:'Install'},{id:'q-2',value:'Office'}]);
 assert.throws(()=>inquiryAnswers({...base,'answer_q-9':'unknown'},d),/form changed/);
});
test('Conditional HTML escapes rule values, hides inactive fields, and binds the fixed enhancement to CSP',async()=>{
 const {createHash}=await import('node:crypto'),{questionScript}=await import('../funnels/question_visibility.mjs'),{publicHeaders}=await import('../funnels/render.mjs');
 const d=publishReady({...doc,questions:branchQuestions});
 const html=renderPage(d,{action:'/f/page/lead',stepAction:'/f/page/step',values:{'answer_q-1':'Advice','answer_q-2':'Home','answer_q-3':'Hidden secret'}});
 assert.match(html,/data-question-id="q-2"[^>]* hidden/);assert.match(html,/name="answer_q-3" maxlength="500" disabled><\/textarea>/);assert(!html.includes('Hidden secret'));
 assert.match(html,/value="refresh_questions"[^>]*formnovalidate/);assert(html.includes('<script>'+questionScript+'</script>'));
 assert(publicHeaders['Content-Security-Policy'].includes("script-src 'sha256-"+createHash('sha256').update(questionScript).digest('base64')+"'"));
 const qs=structuredClone(branchQuestions);qs[0].options[0]='</script>" &';qs[1].show_when.equals=qs[0].options[0];
 const escaped=renderPage(publishReady({...doc,questions:qs}));assert.match(escaped,/data-show-value="&lt;\/script&gt;&quot; &amp;"/);
 const review=renderPage({...d,form_mode:'guided'},{step:'review',values:{'answer_q-1':'Advice','answer_q-4':'Topic'}});assert(!review.includes('<dt>Rooms</dt>'));assert(!review.includes('name="answer_q-2"'));assert(review.includes('<dt>Topic</dt>'));
});
test('Browser enhancement clears hidden descendants, toggles native required validation, and leaves fallback usable until initialized',async()=>{
 const {enhanceQuestions}=await import('../funnels/question_visibility.mjs');
 const groups=branchQuestions.map(q=>({dataset:{questionId:q.id,required:String(q.required),...(q.show_when?{showQuestion:q.show_when.question_id,showValue:q.show_when.equals}:{})},hidden:false,field:{tagName:q.type==='choice'?'SELECT':'TEXTAREA',value:({'q-1':'Install','q-2':'Home','q-3':'Secret','q-4':'Old'})[q.id]},querySelector(){return this.field;}}));
 const fallback={hidden:false};let refresh;
 const form={querySelectorAll:()=>groups,querySelector:()=>fallback,addEventListener:(_name,fn)=>{refresh=fn;}};
 enhanceQuestions({querySelectorAll:()=>[form]});assert(fallback.hidden);assert.equal(groups[3].field.value,'');assert(groups[2].field.required);
 groups[0].field.value='Advice';refresh();assert(groups[1].hidden);assert(groups[1].field.disabled);assert.equal(groups[1].field.value,'');assert.equal(groups[2].field.value,'');assert(!groups[2].field.required);assert(!groups[3].hidden);
 groups[0].field.value='Install';refresh();assert(!groups[1].hidden);assert(groups[2].hidden);assert(groups[1].field.required);
});
