import {randomUUID,randomBytes} from 'node:crypto';
import {hash,booking,date,zone} from '../scheduling/core.mjs';
import {fail,text,confirmedBooking} from './core.mjs';

export const timeLabel=(at,timezone)=>new Intl.DateTimeFormat('en-US',{dateStyle:'full',timeStyle:'short',timeZone:timezone}).format(new Date(at))+` (${timezone})`;
export function receptionistBooking({database,scheduling,command,now=Date.now}){
  async function events(owner,ids){
    if(!ids?.length)return [];
    const {data,error}=await database.from('korlix_schedule_events')
      .select('id,slug,title,description,duration_minutes,questions,price_cents,currency')
      .eq('owner_id',owner).eq('state','published').eq('price_cents',0).in('id',ids);
    if(error)fail('Appointment types could not be loaded.',503);
    const {data:profile,error:profileError}=await database.from('korlix_schedule_profiles').select('timezone').eq('owner_id',owner).maybeSingle();
    if(profileError)fail('The appointment timezone could not be checked.',503);
    return (data||[]).map(e=>({...e,timezone:profile?.timezone||'UTC'}));
  }
  async function context(event){
    const data={token_hash:hash(randomBytes(32).toString('hex')),browser_hash:hash(randomBytes(32).toString('hex'))};
    await scheduling.publicCall('context',event.slug,data);return data;
  }
  async function apply({plan,call,lease,eventList,lastUser,preview=false}){
    const event=eventList.find(e=>e.id===plan.event_id);
    if(plan.action==='find_slots'){
      if(!event)fail('Choose an available appointment type.',409);
      const data={...await context(event),date:date(plan.date)};
      await scheduling.connected.checkAvailability(null,event.slug,data);
      const result=await scheduling.publicCall('slots',event.slug,data);
      const slots=(result.slots||[]).slice(0,5);
      return {reply:slots.length?`For ${event.title}, the next available times are: ${slots.map(s=>timeLabel(s.starts_at,event.timezone)).join('; ')}. Which time works for you?`:'There are no available appointments in that date range. Would you like to check another date?',slots,eventId:event.id};
    }
    if(plan.action==='prepare_booking'){
      if(!event)fail('Choose an available appointment type.',409);
      if(!plan.guest_name||!plan.guest_email||!plan.starts_at)fail('Please provide the guest name, email and chosen appointment time.');
      const requestId=randomUUID(),manage=randomBytes(32).toString('hex');
      const data={...booking({request_id:requestId,manage_token:manage,starts_at:plan.starts_at,guest_name:plan.guest_name,
        guest_email:plan.guest_email,guest_timezone:zone(plan.guest_timezone||event.timezone),answers:Object.fromEntries((plan.answers||[]).map(a=>[text(a.id,31,true),text(a.value,1000)])),confirmed:true}),
        ...await context(event),payments_ready:false,sealed_manage_token:scheduling.notifications.seal(manage,requestId)};
      await scheduling.connected.checkAvailability(null,event.slug,data);
      const localDay=new Intl.DateTimeFormat('en-CA',{timeZone:event.timezone,year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(data.starts_at));
      const available=await scheduling.publicCall('slots',event.slug,{...data,date:localDay});
      if(!(available.slots||[]).some(s=>Date.parse(s.starts_at)===Date.parse(data.starts_at)))fail('That time is no longer available. Please choose another appointment.',409);
      for(const q of event.questions||[])if(q.required&&!data.answers[q.id])fail(`Please answer: ${q.label}`);
      const readback=`Please confirm: ${event.title}, ${timeLabel(data.starts_at,event.timezone)}, for ${data.guest_name}, email ${data.guest_email}. Say "confirm booking" to reserve this appointment.`;
      if(!preview)await command(null,'pending',call.id,{lease,pending:{data,slug:event.slug,event_id:event.id,event_title:event.title,timezone:event.timezone,readback,expires_at:new Date(now()+180000).toISOString()}});
      return {reply:preview?'Preview only. '+readback:readback,pending:preview?null:{title:event.title,starts_at:data.starts_at}};
    }
    if(plan.action==='confirm_booking'){
      if(preview)return {reply:'Preview only: a real caller would confirm the appointment here. No booking has been created.'};
      if(call.booking)return {reply:`Your ${call.booking.event_title} appointment is already booked for ${timeLabel(call.booking.starts_at,call.booking.timezone)}.`};
      if(!confirmedBooking(lastUser)||!call.pending||call.last_response!==call.pending.readback)return {reply:'Please confirm the appointment details by saying "confirm booking", or tell me what you would like to change.'};
      const pending=call.pending;
      if(!eventList.some(e=>e.id===pending.event_id))fail('That appointment type is no longer available.',409);
      await scheduling.connected.checkAvailability(null,pending.slug,pending.data);
      const booked=await command(null,'confirm',call.id,{lease,confirmed:true});
      if(booked.state!=='confirmed')fail('The appointment could not be confirmed. Please contact the business.',409);
      return {reply:`Your ${booked.event_title} appointment is confirmed for ${timeLabel(booked.starts_at,booked.timezone)}. The business has your booking.`,booking:booked};
    }
    fail('This booking action is unavailable.');
  }
  return {events,apply};
}
