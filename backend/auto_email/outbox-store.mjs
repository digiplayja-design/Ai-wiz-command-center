import {fail} from './mailbox-security.mjs';
const errors={mailbox_busy:'Another email is using this mailbox. Please wait and review again.',workspace_paused:'Sending is paused in your KORLIX workspace.',mailbox_changed:'Your mailbox changed. Review the sender again.',draft_changed:'This draft changed. Review its latest version.',draft_not_eligible:'Only a fresh, unscheduled transactional draft can be sent here.',recipient_unavailable:'This recipient is no longer approved for this email.',daily_limit:'Your daily sending limit has been reached.'};
export function createOutboxStore(db){
 const scope=(q,c)=>q.eq('user_id',c.user_id).eq('agent_id',c.agent_id);
 async function result(q){if(!db)fail('Your outbox is temporarily unavailable.',503);const r=await q;if(r.error){const code=Object.keys(errors).find(k=>String(r.error.message||'').includes(k));fail(code?errors[code]:'Your outbox could not confirm this action. Refresh its status before retrying.',code?409:503,code||'outbox_storage_unavailable');}return r.data;}
 return{
  async context(c,id,provider){if(!db)fail('Your outbox is temporarily unavailable.',503);const [draft,mailbox,settings]=await Promise.all([result(scope(db.from('korlix_agent_email_messages').select('*'),c).eq('id',id).maybeSingle()),result(scope(db.from('korlix_auto_email_mailboxes').select('*'),c).eq('provider',provider).maybeSingle()),result(scope(db.from('korlix_agent_email_settings').select('*'),c).maybeSingle())]);const recipient=draft?await result(scope(db.from('korlix_agent_email_recipients').select('*'),c).eq('id',draft.recipient_id).maybeSingle()):null;return{draft,mailbox,settings,recipient};},
  async list(c){if(!db)fail('Your outbox is temporarily unavailable.',503);return result(scope(db.from('korlix_auto_email_outbox').select('*'),c).order('confirmed_at',{ascending:false}).limit(100));},
  async findByDraft(c,id){return result(scope(db.from('korlix_auto_email_outbox').select('*'),c).eq('draft_id',id).maybeSingle());},
  async get(c,id){return result(scope(db.from('korlix_auto_email_outbox').select('*'),c).eq('id',id).maybeSingle());},
  async claim(c,{id,draftId,provider,generation,snapshot,cap}){return result(db.rpc('korlix_auto_email_outbox_claim',{p_user:c.user_id,p_agent:c.agent_id,p_job:id,p_draft:draftId,p_provider:provider,p_generation:generation,p_snapshot:snapshot,p_daily_cap:cap}));},
  async mailbox(c,j){return result(scope(db.from('korlix_auto_email_mailboxes').select('*'),c).eq('id',j.mailbox_id).eq('generation',j.mailbox_generation).eq('status','connected').eq('dispatch_lease',j.id).gt('dispatch_lease_until',new Date().toISOString()).maybeSingle());},
  async credentials(c,j,secrets){return result(scope(db.from('korlix_auto_email_mailboxes').update({secrets}),c).eq('id',j.mailbox_id).eq('generation',j.mailbox_generation).eq('status','connected').eq('dispatch_lease',j.id).gt('dispatch_lease_until',new Date().toISOString()).select('id').maybeSingle());},
  async submit(c,id){return result(db.rpc('korlix_auto_email_outbox_submit',{p_user:c.user_id,p_agent:c.agent_id,p_job:id}));},
  async finish(c,id,status,code,providerId=null){return result(db.rpc('korlix_auto_email_outbox_finish',{p_user:c.user_id,p_agent:c.agent_id,p_job:id,p_status:status,p_code:code,p_provider_id:providerId}));},
  async cleanup(){if(!db)return;return result(db.rpc('korlix_auto_email_outbox_cleanup'));}
 };
}
