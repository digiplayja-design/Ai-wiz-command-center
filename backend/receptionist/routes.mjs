import {randomUUID} from 'node:crypto';
import {adminIds} from '../directory/core.mjs';
import {directoryPassport} from '../directory/passport.mjs';
import {ReceptionistError,fail,text,uuid,settings,messages,publicKnowledge,equalSecret,sessionSecret,VOICES,safeError} from './core.mjs';
import {receptionistProvider} from './provider.mjs';
import {receptionistBooking} from './booking.mjs';
import {SchedulingError} from '../scheduling/core.mjs';

export function registerReceptionist(app,{database,requireUser,scheduling,generate,voiceAccess,previewAccess,previewCharge,environment=process.env,fetcher=fetch,now=Date.now,autoStart=true,store}={}){
  const admins=adminIds(environment),provider=receptionistProvider(environment,fetcher),passport=directoryPassport(database,environment);
  const limits=new Map(),prefix='/api/directory/owner/:business/receptionist';
  const admin=u=>admins.has(u?.id?.toLowerCase());
  function rate(key,max=40){const time=now();let b=limits.get(key);if(!b||time-b.time>60000)b={time,n:0};b.n++;limits.set(key,b);if(limits.size>5000)for(const[k,v]of limits)if(time-v.time>60000)limits.delete(k);if(b.n>max)fail('Please wait before trying again.',429);}
  async function command(user,action,id=null,p={}){
    if(store)return store.command(user?.id,admin(user),action,id,p);
    if(!database)fail('Receptionist storage is temporarily unavailable.',503);
    const {data,error}=await database.rpc('korlix_receptionist_command',{p_actor:user?.id||null,p_admin:admin(user),p_action:action,p_id:id,p});
    if(error){const match=/REC(\d{3}): (.+)/.exec(error.message||'');if(match)fail(match[2],Number(match[1]),Number(match[1])===402?'RECEPTIONIST_ENTERPRISE_REQUIRED':undefined);
      if(['23505','40001'].includes(error.code))fail('This request changed or is already being handled. Refresh and try again.',409);
      if(['P0001','P0002','42501','54000'].includes(error.code))fail('That appointment is no longer available. Please check the booking details again.',409);
      fail('Receptionist storage could not complete this request. Please retry.',503);}
    return data;
  }
  const booking=receptionistBooking({database,scheduling,command,now});
  const errorResponse=(r,e)=>r.status(e instanceof ReceptionistError?e.status:503).json({error:safeError(e),code:e.code||'RECEPTIONIST_UNAVAILABLE',...(e.status===402?{requiredTier:'enterprise',upgradeRequired:true}:{})});
  const owner=fn=>async(q,r)=>{
    r.set('Cache-Control','no-store');
    try{let user;try{user=await requireUser(q);}catch{fail('Sign in to manage your receptionist.',401);}
      if(!user?.id||user.is_anonymous)fail('Sign in with a permanent account.',401);rate('owner:'+user.id);
      await fn(q,r,user,uuid(q.params.business));
    }catch(e){errorResponse(r,e);}
  };
  async function snapshot(business){
    const {data,error}=await database.from('korlix_directory_businesses').select('id,owner_id,published,state').eq('id',business).maybeSingle();
    if(error||!data)fail('Business not found.',404);return data;
  }
  app.get('/api/receptionist/health',(_q,r)=>r.json({version:1,requiredTier:'enterprise',model:'gpt-6-astra',effort:'max',aiReady:!!generate,phoneAuthenticationReady:provider.ready,phoneConnectionReady:provider.connectionReady,bookingReady:!!scheduling,recordings:false,preview:true}));
  app.get(prefix,owner(async(q,r,u,id)=>{
    const data=await command(u,'get',id);
    r.json({...data,events:await passport.events(u.id),voices:VOICES,aiReady:!!generate,
      phoneReady:provider.ready,phoneConnectionReady:provider.connectionReady,isAdmin:admin(u),
      usageDescription:'Calls use your existing voice allowance. Your monthly phone limit can be lower. Phone service requires a connected line.',
      setupStatus:!data.published?'publish_passport':!data.line?'connect_phone':!provider.ready?'platform_setup':data.settings.enabled===true?'ready':'paused'});
  }));
  app.post(prefix,owner(async(q,r,u,id)=>r.json(await command(u,'save',id,settings(q.body)))));
  app.post(prefix+'/pause',owner(async(q,r,u,id)=>r.json(await command(u,'pause',id))));
  app.post(prefix+'/calls/:call/handled',owner(async(q,r,u,id)=>r.json(await command(u,'handled',id,{call_id:uuid(q.params.call)}))));
  app.get(prefix+'/lines',owner(async(q,r,u,id)=>{
    if(!admin(u))fail('Contact KORLIX support to connect your business line.',403);
    await command(u,'get',id);r.json({lines:await provider.lines()});
  }));
  app.post(prefix+'/line',owner(async(q,r,u,id)=>{
    if(!admin(u))fail('Platform phone setup is required.',403);
    if(q.body?.confirmed!==true)fail('Confirm the selected phone connection.');await command(u,'get',id);
    r.json(await provider.connect(uuid(q.body.phone_id),data=>command(u,'bind_line',id,data)));
  }));
  async function turn({call,conversation,preview=false,lease}){
    if(!generate)fail('AI answers are temporarily unavailable.',503);
    const config=call.snapshot.settings;
    const eventList=config.booking_enabled?await booking.events(call.owner_id,config.event_ids):[];
    const context={business:publicKnowledge({published:call.snapshot.business}),approvedAnswers:config.knowledge||'',language:config.language||'English',
      now:new Date(now()).toISOString(),events:eventList.map(({id,title,description,duration_minutes,timezone,questions})=>({id,title,description,duration_minutes,timezone,questions})),
      pending:call.pending?{title:call.pending.event_title,starts_at:call.pending.data.starts_at,timezone:call.pending.timezone,readback:call.pending.readback}:null,
      booked:call.booking?{title:call.booking.event_title,starts_at:call.booking.starts_at}:null,preview};
    const {plan,usage}=await generate({context,messages:conversation,signal:AbortSignal.timeout(115000)});
    let output;
    try {
    if(['find_slots','prepare_booking','confirm_booking'].includes(plan.action)){
      if(!config.booking_enabled)output={reply:'I can take your appointment request for the business to follow up. Phone booking is not enabled.'};
      else output=await booking.apply({plan,call,lease,eventList,lastUser:conversation.at(-1)?.content,preview});
    }else if(plan.action==='take_message'){
      const note={name:text(plan.guest_name,120,true),email:text(plan.guest_email,254),phone:text(plan.callback_number,40),message:text(plan.message,2000,true)};
      if(!note.phone&&!note.email)fail('Please provide a callback number or email address.');
      if(note.email&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(note.email))fail('Please confirm the email address.');
      if(note.phone&&!/^[+\d() .x-]{5,40}$/i.test(note.phone))fail('Please confirm the callback number.');
      if(!preview)await command(null,'note',call.id,{lease,note});
      output={reply:preview?'Preview only: your caller’s message would appear in the private call inbox. No message was saved.':'I have saved your message for the business. They can follow up using the contact details you provided.'};
    }else output={reply:text(plan.reply,1800,true)};
    } catch(error) {
      // A completed AI turn still consumes its allowance when a slot changes
      // or a caller supplies incomplete details. No failed action is presented
      // as successful, and raw provider/database payloads never become speech.
      output={reply:error instanceof ReceptionistError||error instanceof SchedulingError
        ? error.message : 'I could not confirm that action. Please try again or contact the business directly.'};
    }
    return {...output,usage};
  }
  app.post(prefix+'/preview',owner(async(q,r,u,id)=>{
    rate('preview:'+u.id,8);
    if(q.body?.processing_consent!==true)fail('Accept AI processing before starting a preview.');
    const config=await command(u,'get',id),business=await snapshot(id);
    if(!business.published)fail('Publish your Business Passport to preview its approved answers.',409);
    if(previewAccess){const access=await previewAccess(u);if(!access.allowed)fail(access.reason||'Your AI allowance has been reached.',access.status||429);}
    const conversation=messages(q.body?.messages);
    if(!conversation.length||conversation.at(-1).role!=='user')fail('Enter a customer question.');
    const output=await turn({call:{owner_id:business.owner_id,snapshot:{business:business.published,settings:config.settings}},conversation,preview:true});
    if(previewCharge)await previewCharge(u);
    r.json({reply:output.reply,preview:true,slots:output.slots||[]});
  }));
  const providerAuth=q=>{
    if(!provider.ready)fail('Phone setup is incomplete.',503);
    if(!equalSecret(String(q.headers['x-vapi-secret']||''),provider.secret))fail('Phone authentication required.',401);
  };
  app.post('/api/receptionist/provider/events',async(q,r)=>{
    r.set('Cache-Control','no-store');
    try{
      providerAuth(q);const m=q.body?.message||{},callId=uuid(m.call?.id),phoneId=text(m.call?.phoneNumberId||m.phoneNumber?.id,100,true);
      rate('provider:'+phoneId,100);
      if(m.type==='assistant-request'){
        if(!generate||!voiceAccess)fail('The business receptionist is temporarily unavailable.',503);
        const line=await command(null,'line_lookup',null,{provider_id:phoneId});
        const business=await snapshot(line.business_id),access=await voiceAccess({id:business.owner_id});
        if(!access.allowed)fail('This business has reached its voice allowance. Please contact the business directly.',429);
        const call=await command(null,'start',callId,{provider_id:phoneId,caller_number:text(m.call?.customer?.number||m.customer?.number,40),limits:access.limits,remaining_seconds:access.remainingSeconds});
        if(call.state!=='active')fail('This call has already ended.',409);
        return r.json({assistant:provider.assistant(call)});
      }
      const call=await command(null,'call_get',callId);
      if(call.provider_phone_id!==phoneId)fail('Call identity does not match.',403);
      if(m.type==='end-of-call-report'||(m.type==='status-update'&&m.status==='ended')){
        const seconds=Math.max(0,Math.min(call.max_seconds,Math.ceil((now()-Date.parse(call.started_at))/1000)));
        await command(null,'end',callId,{seconds,reason:text(m.endedReason||'completed',120)});
      }
      r.json({received:true});
    }catch(e){
      // Vapi speaks assistant-request errors. An unavailable receptionist never
      // falls back to a different business or to the platform owner's agent.
      if(q.body?.message?.type==='assistant-request'&&e.status!==401)return r.json({error:safeError(e)});
      errorResponse(r,e);
    }
  });
  app.post('/api/receptionist/model/chat/completions',async(q,r)=>{
    let call,lease,heartbeat;
    r.set('Cache-Control','no-store');
    try{
      const id=uuid(q.body?.call?.id);
      if(!provider.ready||!equalSecret(String(q.headers['x-korlix-call-key']||''),sessionSecret(provider.secret,id)))fail('Call authentication required.',401);
      rate('model:'+id,25);const conversation=messages(q.body?.messages);
      if(!conversation.length||conversation.at(-1).role!=='user')fail('A caller question is required.');
      lease=randomUUID();call=await command(null,'claim',id,{lease});
      const stream=q.body.stream!==false,completionId='chatcmpl-'+randomUUID(),created=Math.floor(now()/1000);
      const chunk=(content,finish=null)=>({id:completionId,object:'chat.completion.chunk',created,model:'gpt-6-astra',choices:[{index:0,delta:content===null?{}:{content},finish_reason:finish}]});
      if(stream){r.set({'Content-Type':'text/event-stream','Connection':'keep-alive','X-Accel-Buffering':'no'});r.flushHeaders();r.write(': connected\n\n');heartbeat=setInterval(()=>{if(!r.destroyed)r.write(': processing\n\n');},8000);}
      const output=await turn({call,conversation,lease});
      const finished=await command(null,'finish',id,{lease,reply:output.reply,...output.usage});lease=null;
      if(finished?.deliver===false)output.reply='This receptionist is no longer available for this call. Please contact the business directly.';
      if(r.destroyed)return;
      if(stream){r.write('data: '+JSON.stringify(chunk(output.reply))+'\n\n');r.write('data: '+JSON.stringify(chunk(null,'stop'))+'\n\n');r.end('data: [DONE]\n\n');}
      else r.json({id:completionId,object:'chat.completion',created,model:'gpt-6-astra',choices:[{index:0,message:{role:'assistant',content:output.reply},finish_reason:'stop'}]});
    }catch(e){
      if(lease&&call)await command(null,'release',call.id,{lease}).catch(()=>{});
      if(r.destroyed)return;
      if(r.headersSent){r.write('data: '+JSON.stringify({id:'chatcmpl-unavailable',object:'chat.completion.chunk',model:'gpt-6-astra',choices:[{index:0,delta:{content:e instanceof ReceptionistError?safeError(e):'I could not confirm that just now. Please try again or contact the business directly.'},finish_reason:null}]})+'\n\n');r.end('data: [DONE]\n\n');}
      else errorResponse(r,e);
    }finally{clearInterval(heartbeat);}
  });
  async function cleanup(){try{await command(null,'cleanup');}catch{console.warn('[Receptionist] Usage reconciliation will retry.');}}
  const timer=autoStart?setInterval(cleanup,60000):null;timer?.unref();
  return {stop:()=>clearInterval(timer),cleanup,turn};
}
