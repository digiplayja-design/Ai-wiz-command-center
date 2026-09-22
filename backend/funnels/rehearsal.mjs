import {FunnelError, fail, text, uuid, version, publishReady, leadInput, inquiryQuestions, visibleQuestions, bookingOutcome} from './core.mjs';

const sampleFor = scenario => ({
  name:'Taylor Morgan', email:scenario==='invalid_email'?'not-an-email':'taylor@example.com',
  phone:'', message:'I would like to learn more about your services.',
  consent:scenario==='missing_consent'?'no':'yes', utm_source:'rehearsal',
});
const check = (id,title,fn) => {
  try {fn();return {id,title,status:'pass'};}
  catch(e) {if(!(e instanceof FunnelError))throw e;return {id,title,status:'blocked',detail:e.message};}
};
// Match the existing database interpolation order and Postgres character limits.
export function rehearsalText(template,lead,doc,name,max) {
  let value=template;
  for(const [token,replacement] of [
    ['booking_url',doc.booking_url],['funnel',name],['brand',doc.brand],['name',lead.name],
  ]) value=value.split('{{'+token+'}}').join(replacement??'');
  return [...value].slice(0,max).join('');
}

export function rehearseFunnel(snapshot,body={}) {
  if(!body||typeof body!=='object'||Array.isArray(body))fail('Choose a rehearsal scenario.');
  if(!['draft','published'].includes(body.source))fail('Choose the editor draft or published page.');
  if(!['valid','missing_consent','invalid_email'].includes(body.scenario))fail('Choose an available sample inquiry.');
  if(version(body.version)!==snapshot.version)fail('This funnel changed. Reload saved, review your edits, and run again.',409);
  const draft=body.source==='draft';
  let doc=draft?body.document:snapshot.published;
  const name=draft?text(body.name,100,true):snapshot.name;
  const sample=sampleFor(body.scenario);
  const checks=[
    check('page','Page content and required details',()=>{doc=publishReady(doc);}),
    check('inquiry','Sample inquiry validation',()=>{for(const q of inquiryQuestions(doc?.questions))sample['answer_'+q.id]=q.type==='choice'?(q.options[0]??''):'Sample response';leadInput(sample,doc??{});}),
  ];
  if(checks[0].status==='pass'&&inquiryQuestions(doc.questions).some(q=>q.show_when))checks.push({id:'branches',title:'Conditional questions',status:'scenario',detail:`The sample selects the first choice at each visible question: ${visibleQuestions(doc.questions,sample).length} of ${inquiryQuestions(doc.questions).length} questions apply. Use the page preview to explore other answers. This does not exercise every branch.`});
  if(checks[0].status==='pass')checks.push({id:'journey',title:'Visitor journey',status:'scenario',
    detail:doc.form_mode==='guided'?
      'Guided: contact details, request and consent, then review and send. Only the final submission creates an inquiry. This rehearsal does not exercise browser navigation.':
      'Single-page inquiry form. This rehearsal models final submission; it does not exercise browser navigation.'});
  const publishedAvailable=snapshot.state==='published'&&snapshot.published!=null;
  const available=draft||publishedAvailable;
  checks.unshift({id:'availability',title:draft?'Draft publication scenario':'Current page availability',
    status:draft?'scenario':publishedAvailable?'pass':'blocked',
    detail:draft?'Shows what would happen if you published the current editor draft. Unsaved changes are included.':
      publishedAvailable?'Uses the published page, even when the editor has newer changes.':'This page is not currently published and accepting inquiries.'});
  const accepted=available&&checks.every(c=>c.status!=='blocked');
  const s=snapshot.workflow;
  const tasks=[];
  if(accepted&&s?.enabled) {
    for(const channel of [s.email_enabled?'email':null,s.call_enabled?'call_review':null].filter(Boolean)) {
      tasks.push({channel,delay_minutes:s.delay_minutes,state:'review',
        subject:channel==='email'?rehearsalText(s.subject,sample,doc,name,200):'',
        body:channel==='email'?rehearsalText(s.body,sample,doc,name,6000):'',
      });
    }
  }
  return {
    kind:'simulation',source:body.source,scenario:body.scenario,saved_version:snapshot.version,
    workflow_version:s?.version??null,page_state:snapshot.state,published_version:snapshot.published_version,
    checks,sample,accepted_in_scenario:accepted,tasks,
    workflow_enabled:s?.enabled===true,workflow_configured:s!=null,
    workflow_note:!accepted?'No follow-up tasks would be queued for this blocked scenario.':
      !s?.enabled?'Saved follow-ups are off. An inquiry would appear in Leads and CRM without automatic review tasks.':
      `${tasks.length} review task${tasks.length===1?'':'s'} would become due ${s.delay_minutes===0?'immediately':`after ${s.delay_minutes} minutes`}. This is task timing, not a send time.`,
    receipt:accepted?bookingOutcome(doc,leadInput(sample,doc).answers??[]):null,
    performed_actions:[],delivery_tested:false,
    limits:'Simulation only. No inquiry, contact, task, email, call or ad is created. Live form cookies, rate limits, existing contact permissions, provider readiness and delivery still need separate verification. New inquiries are not automatically enrolled in a sequence. Booking links offer a next step, not a confirmed appointment. Follow-up templates still use the default booking link.',
  };
}

export function createRehearsalStore(database) {
  return async(actor,id)=>{
    if(!database)fail('Rehearsal is not available on this server yet.',503);
    const {data,error}=await database.rpc('korlix_funnel_rehearsal_v1',{p_actor:actor,p_id:id});
    if(error) {
      if(error.code==='42501')fail('Funnel Studio requires Enterprise.',403);
      if(error.code==='P0002')fail('Funnel not found.',404);
      fail('Rehearsal is temporarily unavailable. Please try again later.',503);
    }
    if(!data?.id)fail('Rehearsal could not load this funnel.',503);
    return data;
  };
}
export function registerRehearsal(app,{base,owner,database,rehearsalStore}) {
  const snapshot=rehearsalStore??createRehearsalStore(database);
  app.post(base+'/:id/rehearsal',owner(async(q,r,u)=>{
    const data=await snapshot(u,uuid(q.params.id));
    r.json(rehearseFunnel(data,q.body));
  }));
}
