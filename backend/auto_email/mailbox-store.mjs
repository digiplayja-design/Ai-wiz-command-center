import {fail} from './mailbox-security.mjs';
export function createMailboxStore(database){
 const ready=()=>{if(!database)fail('Mailbox storage is temporarily unavailable.',503);};
 async function result(query){const r=await query;if(r.error)fail('Mailbox storage is temporarily unavailable. Please retry.',503,'mailbox_storage_unavailable');return r.data;}
 const scoped=(q,c)=>q.eq('user_id',c.user_id).eq('agent_id',c.agent_id);
 return {
  async list(c){ready();return result(scoped(database.from('korlix_auto_email_mailboxes').select('provider,status,identity,connected_at,updated_at'),c));},
  async begin(flow){ready();return result(database.rpc('korlix_auto_email_mailbox_begin',{p_flow:flow}));},
  async claim(provider,stateHash,browserHash,now){ready();return result(database.from('korlix_auto_email_mailbox_flows').update({status:'exchanging',state_hash:null}).eq('provider',provider).eq('state_hash',stateHash).eq('browser_hash',browserHash).eq('status','pending').gt('expires_at',new Date(now).toISOString()).select('*').maybeSingle());},
  async complete(flow,values,now){return result(database.from('korlix_auto_email_mailbox_flows').update(values).eq('id',flow.id).eq('status','exchanging').gt('expires_at',new Date(now).toISOString()).select('id').maybeSingle());},
  async getFlow(c,id){ready();return result(scoped(database.from('korlix_auto_email_mailbox_flows').select('*'),c).eq('device_hash',c.device_hash).eq('id',id).maybeSingle());},
  async confirm(c,id,secrets){ready();return result(database.rpc('korlix_auto_email_mailbox_confirm',{p_user:c.user_id,p_agent:c.agent_id,p_device:c.device_hash,p_flow:id,p_secrets:secrets}));},
  async disconnect(c,provider){ready();return result(database.rpc('korlix_auto_email_mailbox_disconnect',{p_user:c.user_id,p_agent:c.agent_id,p_provider:provider}));},
  async cancel(c,id){ready();return result(scoped(database.from('korlix_auto_email_mailbox_flows').update({status:'cancelled',secrets:null,identity:null,state_hash:null,browser_hash:null}),c).eq('device_hash',c.device_hash).eq('id',id).in('status',['pending','exchanging','review']).select('id').maybeSingle());},
  async cleanup(){ready();return result(database.rpc('korlix_auto_email_mailbox_cleanup'));},
 };
}
