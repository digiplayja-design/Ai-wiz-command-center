import { sequenceActions } from './sequences.mjs';
import { fail, text, uuid, version } from './core.mjs';
import { korlixAgentEmailNovaBinding, korlixAgentEmailDraftInput } from '../korlix_agent_email.mjs';
import { createKorlixAgentEmailSupabaseStore, createKorlixAgentEmailDraftService } from '../korlix_agent_email_routes.mjs';
import { createKorlixAgentEmailDeliveryService } from '../korlix_agent_email_delivery.mjs';

export function followupSettings(body={}) {
  if (![0,60,240,1440].includes(body.delay_minutes)) fail('Choose an available follow-up delay.');
  if (typeof body.enabled!=='boolean' || typeof body.email_enabled!=='boolean' || typeof body.call_enabled!=='boolean') fail('Choose the workflow and channel settings.');
  if (!body.email_enabled && !body.call_enabled) fail('Choose at least one follow-up channel.');
  const result={version:version(body.version),enabled:body.enabled,email_enabled:body.email_enabled,call_enabled:body.call_enabled,
    delay_minutes:body.delay_minutes,subject:text(body.subject,160,true),body:text(body.body,4000,true),confirmed:body.confirmed===true};
  for(const value of [result.subject,result.body]) for(const token of value.match(/\{\{.*?\}\}/g)||[]) {
    if(!['{{name}}','{{brand}}','{{funnel}}','{{booking_url}}'].includes(token)) fail('Use only the name, brand, funnel, and booking_url placeholders.');
  }
  return result;
}
export function createFollowupStore(database) {
  return {async command(actor,action,id,data={}) {
    if(!database) fail('Follow-up storage is not configured.',503);
    const r=await database.rpc('korlix_funnel_followup_v1',{p_actor:actor,p_action:action,p_id:id,p_data:data});
    if(r.error) {
      const status={'42501':403,'P0002':404,'40001':409,'P0001':400}[r.error.code];
      fail(status?r.error.message:'Follow-up storage is temporarily unavailable.',status||503);
    }
    return r.data;
  }, async sequence(actor,action,id,data={}) {
    if(!database) fail('Follow-up storage is not configured.',503);
    const r=await database.rpc('korlix_funnel_sequence_v1',{p_actor:actor,p_action:action,p_id:id,p_data:data});
    if(r.error) {
      const status={'42501':403,'P0002':404,'40001':409,'P0001':400}[r.error.code];
      fail(status?r.error.message:'Sequence storage is temporarily unavailable.',status||503);
    }
    return r.data;
  }, async due(owner) {
    if(!database) return [];
    const r=await database.rpc('korlix_funnel_scheduled_due_v1',{p_owner:owner});
    if(r.error) fail('Scheduled follow-ups are temporarily unavailable.',503);
    return r.data;
  }};
}
export function createFunnelFollowups({database,store,emailStore,drafts,delivery,loadAgentProfile,environment=process.env}={}) {
  const state=store||createFollowupStore(database);
  const binding=korlixAgentEmailNovaBinding(environment);
  const mailStore=emailStore||(database&&loadAgentProfile?createKorlixAgentEmailSupabaseStore(database):null);
  const draftService=drafts||(mailStore?createKorlixAgentEmailDraftService({store:mailStore,loadAgentProfile,environment,providerSendPathImplemented:true}):null);
  const mail=delivery||(mailStore?createKorlixAgentEmailDeliveryService({store:mailStore,loadAgentProfile,environment}):null);
  const cmd=(u,a,f,p)=>state.command(u,a,f,p);
  const identity=u=>({userId:u,agentId:binding.agentId});
  const bound=u=>binding.configured&&binding.ownerUid===u&&mail&&draftService;
  const publicTask=t=>{const {approval_nonce,...rest}=t;return rest;};
  const exact=(draft,task)=>{
    const normalized=korlixAgentEmailDraftInput({recipientId:draft.recipientId,subject:task.subject,textBody:task.body,idempotencyKey:'funnel-followup:'+task.id});
    if(draft.subject!==normalized.subject||draft.textBody!==normalized.textBody||draft.toEmail?.toLowerCase()!==task.to_email.toLowerCase()
      ||draft.messageKind!=='transactional'||draft.htmlBody||draft.idempotencyKey!==normalized.idempotencyKey) {
      fail('The NOVA email changed. Review it in NOVA Email Center before sending.',409);
    }
  };
  const schedulerEnabled=!['false','0','off','disabled'].includes(String(environment.KORLIX_FUNNEL_SCHEDULER_ENABLED??'true').toLowerCase());
  async function capabilities(u) {
    if(!bound(u)) return {email_ready:false,email_reason:'Connect this owner’s approved NOVA profile and Email Center to send follow-ups.',outbound_calling_enabled:false};
    try {
      const s=await mail.getDeliveryStatus(identity(u));
      return {scheduling_ready:schedulerEnabled&&s.canSend===true&&s.canAutopilot===true,scheduling_reason:!schedulerEnabled?'Scheduled follow-ups are paused on this server.':'Enable NOVA Email Autopilot to schedule approved replies. Existing sending limits and quiet hours apply.',email_ready:s.canSend===true,email_reason:s.canSend?null:'Enable sending in NOVA Email Center. Its existing permissions, daily limits, and quiet hours apply.',daily_usage:s.dailyUsage,outbound_calling_enabled:false};
    }catch{return {email_ready:false,email_reason:'NOVA Email Center is unavailable. Check the agent and email settings.',outbound_calling_enabled:false};}
  }
  async function send(u,f,body,{scheduled=false}={}) {
    const taskId=uuid(body.task_id), v=version(body.version);
    if(body.confirmed!==true) fail('Review the recipient and exact email before sending.');
    // Validate Enterprise ownership before looking up NOVA or mutating any recipient.
    await cmd(u,'get',f,{task_id:taskId});
    const cap=await capabilities(u);if(!cap.email_ready) fail(cap.email_reason,409);
    if(scheduled&&!cap.scheduling_ready) fail(cap.scheduling_reason,409);
    const task=await cmd(u,scheduled?'claim_scheduled':'claim',f,{task_id:taskId,version:v,confirmed:true,agent_id:binding.agentId});
    try {
      const current=await cmd(u,'get',f,{task_id:task.id});
      const contact=current.contact;
      let recipient=await mailStore.findRecipientByEmail(u,binding.agentId,task.to_email);
      if(recipient && (!recipient.active||!['transactional_only','marketing_opt_in'].includes(recipient.consent_status))) fail('This NOVA recipient is inactive or has opted out. Review Email Center.',409);
      if(!recipient) recipient=(await draftService.saveRecipient({...identity(u),body:{confirmed:true,email:task.to_email,displayName:contact.name,
        approvalSource:'user_confirmed',consentScope:'transactional',consentAt:contact.consent_at,sourceReference:'crm:'+contact.id}})).recipient;
      const {draft}=await draftService.createDraft({...identity(u),body:{recipientId:recipient.id,subject:task.subject,textBody:task.body,marketing:false,idempotencyKey:'funnel-followup:'+task.id}});
      await cmd(u,'attach',f,{task_id:task.id,message_id:draft.id,agent_id:binding.agentId});
      exact(draft,task);
      if(draft.status==='sent' && draft.providerMessageId) return {task:publicTask(await cmd(u,'finish',f,{task_id:task.id,state:'sent',note:'Accepted by the email provider. Delivery events are available in NOVA Email Center.'})),sent:true,replayed:true};
      // Approve the exact reviewed message using NOVA's existing approval service.
      const confirmationNonce=task.approval_nonce;
      const approved=await draftService.approveDraft({...identity(u),messageId:draft.id,body:{confirmed:true,confirmationNonce}});
      exact(approved.draft,task);
      await cmd(u,'check',f,{task_id:task.id}); // fresh rule, page, plan, contact, and suppression checks
      const result=await mail.sendApprovedDraft({...identity(u),messageId:draft.id,body:{confirmed:true,confirmationNonce},scheduled,beforeProvider:()=>cmd(u,'check',f,{task_id:task.id})});
      const sent=result.sent===true;
      return {task:publicTask(await cmd(u,'finish',f,{task_id:task.id,state:sent?'sent':'needs_review',note:sent?'Accepted by the email provider. This does not yet confirm delivery.':'Check delivery before trying again.'})),sent};
    }catch(error) {
      const note=error?.statusCode<500||error?.status<500?String(error.message).slice(0,700):'Sending could not be confirmed. Check delivery before trying again.';
      await cmd(u,'finish',f,{task_id:task.id,state:'needs_review',note}).catch(()=>{});
      // No blind retries: a timeout can occur after provider acceptance.
      fail(note,409);
    }
  }
  async function reconcile(u,f,taskId) {
    const {task}=await cmd(u,'get',f,{task_id:uuid(taskId)});
    if(!['needs_review','processing'].includes(task.state)) return {task:publicTask(task)};
    if(task.state==='processing') fail('A send is still in progress. Wait a few minutes, then refresh.',409);
    if(!bound(u)||task.agent_id&&task.agent_id!==binding.agentId) fail('Open the original NOVA Email Center to check this email.',409);
    const raw=await mailStore.findMessageByIdempotency(u,binding.agentId,'funnel-followup:'+task.id);
    let next='needs_review', note='Review this message in NOVA Email Center. No second email has been sent.';
    if(raw?.status==='sent'&&raw.provider_message_id) {next='sent';note='Accepted by the email provider. Check NOVA Email Center for delivery events.';}
    // Only return an untouched draft to review. A provider attempt, failure, edit,
    // or ambiguous result must be handled in the existing Email Center.
    else if(!raw || (['draft','approved'].includes(raw.status)&&!raw.provider_message_id&&!raw.sent_at&&!raw.last_attempt_at&&!raw.attempt_count)) {
      if(raw) {
        const {draft}=await draftService.getDraft({...identity(u),messageId:raw.id});exact(draft,task);
      }
      next='review';note='No provider attempt recorded. Review the email before trying again.';
    }
    return {task:publicTask(await cmd(u,'finish',f,{task_id:task.id,state:next,note})),sent:next==='sent'};
  }
  return {
    async get(u,f,query={}) {
      const offset=Number(query.offset||0);if(!Number.isInteger(offset)||offset<0||offset>100000) fail('Invalid page.');
      const data=await cmd(u,'state',f,{filter:query.filter||'open',offset});return {...data,...await capabilities(u)};
    },
    settings:(u,f,body)=>cmd(u,'settings',f,followupSettings(body)),
    enqueue:(u,f,body)=>cmd(u,'enqueue',f,{lead_id:uuid(body.lead_id)}),
    async edit(u,f,body) {return publicTask(await cmd(u,'edit',f,{task_id:uuid(body.task_id),version:version(body.version),subject:text(body.subject,200,true),body:text(body.body,6000,true)}));},
    async resolve(u,f,body) {if(!['done','dismissed'].includes(body.state))fail('Choose a valid outcome.');return publicTask(await cmd(u,'resolve',f,{task_id:uuid(body.task_id),version:version(body.version),state:body.state,note:text(body.note??'',1000)}));},
    async schedule(u,f,body) {
      const taskId=uuid(body.task_id),v=version(body.version);
      if(body.confirmed!==true) fail('Review and approve this exact scheduled email.');
      const date=typeof body.scheduled_for==='string'&&/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(body.scheduled_for)?new Date(body.scheduled_for):null;
      if(!date||!Number.isFinite(date.getTime())) fail('Choose a valid send date and time.');
      await cmd(u,'get',f,{task_id:taskId});
      const cap=await capabilities(u);if(!cap.scheduling_ready) fail(cap.scheduling_reason||cap.email_reason,409);
      return {task:publicTask(await cmd(u,'schedule',f,{task_id:taskId,version:v,confirmed:true,scheduled_for:date.toISOString(),agent_id:binding.agentId}))};
    },
    async cancelSchedule(u,f,body) {
      return {task:publicTask(await cmd(u,'cancel_schedule',f,{task_id:uuid(body.task_id),version:version(body.version)}))};
    },
    async runScheduled() {
      if(!schedulerEnabled||!bound(binding.ownerUid)||typeof state.due!=='function') return {checked:0,sent:0};
      const tasks=await state.due(binding.ownerUid);let sent=0;
      for(const task of tasks) {
        try {
          const result=await send(binding.ownerUid,task.funnel_id,{task_id:task.id,version:task.version,confirmed:true},{scheduled:true});
          if(result.sent)sent++;
        }catch {
          // Before a claim, return to review. After a claim, send() records uncertainty.
          // Version checks make this harmless when another worker already owns the task.
          await cmd(binding.ownerUid,'cancel_schedule',task.funnel_id,{task_id:task.id,version:task.version,
            note:'Scheduled sending was held. Check NOVA Email permissions and review this reply again.'}).catch(()=>{});
        }
      }
      return {checked:tasks.length,sent};
    },
    ...sequenceActions({state,capabilities,binding}),
    send,reconcile,
  };
}
