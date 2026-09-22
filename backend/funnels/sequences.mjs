import { fail, text, uuid, version } from './core.mjs';

function sendTime(raw) {
  if(typeof raw!=='string'||!/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(raw)) fail('Choose a valid send date and time.');
  const date=new Date(raw);
  if(!Number.isFinite(date.getTime())) fail('Choose a valid send date and time.');
  return date.toISOString();
}
export function sequenceActions({state,capabilities,binding}) {
  const command=(u,a,f,p)=>state.sequence(u,a,f,p);
  async function ready(u) {
    const cap=await capabilities(u);
    if(!cap.scheduling_ready) fail(cap.scheduling_reason||cap.email_reason||'Connect NOVA Email Autopilot first.',409);
  }
  function steps(body,resume=false) {
    if(!Array.isArray(body.steps)||body.steps.length<(resume?1:2)||body.steps.length>5) fail('Choose two to five sequence steps.');
    if(body.steps.some(s=>!s||typeof s!=='object'||Array.isArray(s))) fail('Provide valid sequence steps.');
    return body.steps.map(s=>resume?{task_id:uuid(s.task_id),version:version(s.version),scheduled_for:sendTime(s.scheduled_for)}:
      {subject:text(s.subject,200,true),body:text(s.body,6000,true),scheduled_for:sendTime(s.scheduled_for)});
  }
  const target=b=>({sequence_id:uuid(b.sequence_id),version:version(b.version),confirmed:b.confirmed===true});
  return {
    sequenceDetail:(u,f,id)=>command(u,'get',f,{sequence_id:uuid(id)}),
    async createSequence(u,f,body) {
      const id=uuid(body.task_id),v=version(body.version);
      if(body.confirmed!==true)fail('Review every message and time before approving this sequence.');
      const payload={task_id:id,version:v,name:text(body.name,100,true),steps:steps(body),confirmed:true,agent_id:binding.agentId};
      await state.command(u,'get',f,{task_id:id}); // ownership before any agent lookup
      await ready(u);
      return command(u,'create',f,payload);
    },
    async resumeSequence(u,f,body) {
      const payload={...target(body),steps:steps(body,true),agent_id:binding.agentId};
      if(!payload.confirmed)fail('Review every remaining message and time before resuming.');
      await command(u,'get',f,{sequence_id:payload.sequence_id});
      await ready(u);
      return command(u,'resume',f,payload);
    },
    pauseSequence:(u,f,b)=>command(u,'pause',f,target(b)),
    cancelSequence:(u,f,b)=>command(u,'cancel',f,target(b)),
    replySequence:(u,f,b)=>command(u,'replied',f,target(b)),
  };
}
