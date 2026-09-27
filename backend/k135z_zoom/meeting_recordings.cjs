'use strict';
const {randomUUID} = require('node:crypto');
const C = require('../k135z_copilot_notes/contract.cjs');
const {identity,K135zZoomError} = require('./b5b_contract.cjs');
const {createRecordingEncoder} = require('./recording_encoder.cjs');
const {objectPath} = require('./recording_store.cjs');
const fail = (status,code) => { throw new K135zZoomError(status,'K135Z_RECORDING_'+code); };
const key = p => C.canonical(identity(p));
const activeStates = ['recording','saving'];
function validateRecordingRequest(body) {
  C.oneOf(body.action,['list','start','stop','play','download','delete','voice-start','voice-chunk']);
  C.object(body,body.action==='list'?['action']:body.action==='start'
    ? ['action','id','context','consent'] : body.action==='voice-start'
    ? ['action','id','context','playbackId'] : body.action==='voice-chunk'
    ? ['action','id','context','playbackId','sequence','pcm'] : ['action','id']);
  if (body.action!=='list') C.requireValue(typeof body.id==='string' && /^[a-f0-9]{32}$/.test(body.id));
  if (body.action==='start') { C.context(body.context); C.requireValue(body.consent===true); }
  if (body.action.startsWith('voice-')) {
    C.context(body.context);
    C.requireValue(typeof body.playbackId==='string'&&/^[a-f0-9]{32}$/.test(body.playbackId));
    if(body.action==='voice-chunk') {
      C.uint(body.sequence);C.requireValue(body.sequence>0&&body.sequence<=180);
      C.requireValue(typeof body.pcm==='string'&&body.pcm.length<=21336&&
        /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(body.pcm));
      const pcm=Buffer.from(body.pcm,'base64');
      C.requireValue(pcm.length>0&&pcm.length<=16000&&pcm.length%2===0&&pcm.toString('base64')===body.pcm);
    }
  }
}
function summary(row) {
  return {id:row.id,status:row.status,createdAt:row.created_at,
    durationMs:row.duration_ms,byteSize:row.byte_size,endReason:row.end_reason,
    meetingUuid:row.context.meetingUuid};
}
function createMeetingRecordings({store,encoderFactory=createRecordingEncoder,
  now=Date.now,maxDurationMs=3600000,heartbeatMs=15000,maxConcurrent=4}={}) {
  if (!store || maxDurationMs<1 || maxDurationMs>3600000 || heartbeatMs<1 || maxConcurrent<1)
    throw new TypeError('K135Z_RECORDING_CONFIGURATION_INVALID');
  const entries=new Map(), processId=randomUUID();
  const stamp=()=>new Date(now()).toISOString();
  let closed=false;
  async function persist(e,patch) {
    const row=await store.update(e.principal,e.id,{...patch,updated_at:stamp()},
      {processId,statuses:activeStates});
    if (!row) fail(409,'CONFLICT');
    return row;
  }
  function stopEntry(e,reason='stopped') {
    if (e.finishing) return e.finishing;
    e.active=false; e.stopped=true;
    clearTimeout(e.timer); clearInterval(e.heartbeat);
    if (e.row) e.row={...e.row,status:'saving',end_reason:reason,
      duration_ms:Math.floor(Math.max(e.inputBytes,e.voiceEnd)/32)};
    // Finalization belongs to the recording, not to the lifetime of an HTTP
    // Stop request. A lost response must not restart or discard the recording.
    e.finishing=(async()=>{
      try {
        await e.heartbeatTask;
        if (!e.encoder || (!e.inputBytes&&!e.voiceEnd)) fail(409,'NO_AUDIO');
        await persist(e,{status:'saving',end_reason:reason,duration_ms:e.row.duration_ms});
        const bytes=await e.encoder.finish(); e.encoder=null;
        await store.upload(objectPath(e.principal,e.id),bytes);
        e.row=await persist(e,{status:'ready',byte_size:bytes.length,
          duration_ms:e.row.duration_ms,end_reason:reason});
      } catch (_) {
        try { await e.encoder?.abort(); } catch {}
        e.encoder=null;
        if (e.row) {
          e.row={...e.row,status:'failed',end_reason:e.inputBytes||e.voiceEnd?'save_failed':'no_audio'};
          try { await persist(e,{status:'failed',end_reason:e.row.end_reason,
            duration_ms:e.row.duration_ms}); } catch {}
        }
      } finally {
        if (entries.get(key(e.principal))===e) entries.delete(key(e.principal));
      }
    })();
    return e.finishing;
  }
  async function list(principal) {
    const rows=await store.list(principal), e=entries.get(key(principal));
    const out=[];
    for (let row of rows) {
      if (e?.id===row.id && e.row) row={...e.row,duration_ms:Math.floor(Math.max(e.inputBytes,e.voiceEnd)/32)};
      else if (activeStates.includes(row.status) && now()-Date.parse(row.updated_at)>90000) {
        // Compare-and-set prevents declaring another instance's fresh heartbeat
        // failed during rolling deploys. Interrupted files are never called ready.
        row=await store.update(principal,row.id,{status:'failed',end_reason:'interrupted',updated_at:stamp()},
          {updatedAt:row.updated_at,statuses:activeStates}) || row;
      }
      out.push(summary(row));
    }
    return out;
  }
  async function start(principal,body,verify,check) {
    const k=key(principal), existing=entries.get(k);
    if (closed) fail(503,'UNAVAILABLE');
    if (existing) {
      if (existing.id===body.id && existing.row && C.sameContext(existing.context,body.context))
        return summary(existing.row);
      fail(409,'CONFLICT');
    }
    if (entries.size>=maxConcurrent) fail(429,'BUSY');
    const e={principal:identity(principal),id:body.id,context:C.clone(body.context),
      row:null,encoder:null,active:false,stopped:false,inputBytes:0,heartbeatBusy:false,
      voices:new Map(),voiceBytes:0,voiceEnd:0};
    e.startDone=new Promise(resolve=>{e.started=resolve;});
    entries.set(k,e);
    try {
      await verify(); check();
      const previous=await store.get(principal,body.id); check();
      if (previous) {
        if (!C.sameContext(previous.context,body.context)) fail(409,'CONFLICT');
        return summary(previous);
      }
      // Reconcile interrupted sessions before a new reservation.
      await list(principal); check();
      e.row=await store.reserve(principal,{id:body.id,context:e.context,processId,now:stamp()});
      check();
      e.encoder=await encoderFactory({onFailure:()=>{
        e.stopped=true;
        if (e.active) void stopEntry(e,'encoder_failed');
      }});
      await verify(); check();
      if (e.stopped || closed) fail(409,'INTERRUPTED');
      e.active=true;
      e.timer=setTimeout(()=>void stopEntry(e,'duration_limit'),maxDurationMs);
      e.heartbeat=setInterval(()=>{
        if (!e.active || e.heartbeatBusy) return;
        e.heartbeatBusy=true;
        e.heartbeatTask=(async()=>{
          try {
            const row=await persist(e,{status:'recording',duration_ms:Math.floor(Math.max(e.inputBytes,e.voiceEnd)/32)});
            if(e.active)e.row=row;
          } catch { queueMicrotask(()=>void stopEntry(e,'storage_interrupted')); }
          finally { e.heartbeatBusy=false; }
        })();
      },heartbeatMs);
      e.timer.unref?.(); e.heartbeat.unref?.();
      return summary(e.row);
    } catch (error) {
      e.stopped=true;
      try { await e.encoder?.abort(); } catch {}
      e.encoder=null;
      if(e.row)try { await persist(e,{status:'failed',end_reason:'start_failed'}); } catch {}
      throw error;
    } finally {
      e.started();
      if (!e.active && !e.finishing && entries.get(k)===e) entries.delete(k);
    }
  }
  return {
    async run({principal,body,verify,check=()=>{}}) {
      validateRecordingRequest(body); identity(principal); check();
      if (body.action==='list') return {recordings:await list(principal)};
      if (body.action==='start') return {recording:await start(principal,body,verify,check)};
      const e=entries.get(key(principal));
      if(body.action.startsWith('voice-')) {
        if(!e?.active||e.id!==body.id||!C.sameContext(e.context,body.context))fail(409,'VOICE_SESSION_CHANGED');
        await verify();check();
        if(!e.active||entries.get(key(principal))!==e)fail(409,'VOICE_SESSION_CHANGED');
        let voice=e.voices.get(body.playbackId);
        if(body.action==='voice-start') {
          if(!voice) {
            if(e.voices.size>=512)fail(429,'VOICE_LIMIT');
            voice={offset:e.inputBytes,bytes:0,sequence:0,startedAt:now()};e.voices.set(body.playbackId,voice);
          }
          return {accepted:true};
        }
        if(!voice)fail(409,'VOICE_SESSION_CHANGED');
        // Serialized browser packets may retry an acknowledged sequence, but
        // may never fill a gap or append the same samples twice.
        if(body.sequence<=voice.sequence)return {accepted:true};
        if(body.sequence!==voice.sequence+1)fail(409,'VOICE_SEQUENCE');
        const pcm=Buffer.from(body.pcm,'base64'),offset=voice.offset+voice.bytes;
        if(voice.bytes+pcm.length>45*32000||e.voiceBytes+pcm.length>maxDurationMs*32||
            offset+pcm.length>maxDurationMs*32||voice.bytes+pcm.length>(Math.max(0,now()-voice.startedAt)+2000)*32)fail(429,'VOICE_LIMIT');
        if(e.encoder.writeVoice?.(pcm,offset)!==true)fail(503,'VOICE_UNAVAILABLE');
        voice.sequence=body.sequence;voice.bytes+=pcm.length;e.voiceBytes+=pcm.length;
        e.voiceEnd=Math.max(e.voiceEnd,offset+pcm.length);
        return {accepted:true};
      }
      let row=e?.id===body.id ? e.row : await store.get(principal,body.id); check();
      if (!row) fail(404,'NOT_FOUND');
      if (body.action==='stop') {
        if (e?.id===body.id) { void stopEntry(e); row=e.row; }
        else if (activeStates.includes(row.status)) fail(409,'NOT_LOCAL');
        return {recording:summary(row)};
      }
      if (body.action==='delete') {
        if (activeStates.includes(row.status)) fail(409,'STILL_ACTIVE');
        await store.remove(principal,row); return {deleted:true};
      }
      if (row.status!=='ready') fail(409,'NOT_READY');
      const path=objectPath(principal,row.id);
      const url=await store.link(path,body.action==='download'); check();
      const downloadUrl=body.action==='play'?await store.link(path,true):url; check();
      return {recording:summary(row),url,downloadUrl,expiresIn:3600};
    },
    accept(context,buffer) {
      let e;
      try {
        e=entries.get(key(context));
        if (!e?.active || !C.sameContext(e.context,context)) return;
        if (!Buffer.isBuffer(buffer) || !buffer.length || buffer.length%2 || buffer.length>65536) {
          void stopEntry(e,'invalid_audio'); return;
        }
        const remaining=Math.floor(maxDurationMs*32/2)*2-e.inputBytes;
        if (remaining<=0) { void stopEntry(e,'duration_limit'); return; }
        const packet=buffer.length>remaining?buffer.subarray(0,remaining):buffer;
        if (e.encoder.write(packet)) {
          e.inputBytes+=packet.length;
          if(e.inputBytes>=maxDurationMs*32)void stopEntry(e,'duration_limit');
        }
        else void stopEntry(e,'encoder_failed');
      } catch { if (e?.active) void stopEntry(e,'encoder_failed'); }
    },
    streamClosed(context) {
      try {
        const e=entries.get(key(context));
        if (e && C.sameContext(e.context,context)) {
          e.stopped=true;
          if(e.active)void stopEntry(e,'capture_ended');
        }
      } catch {}
    },
    close() {
      closed=true;
      return Promise.all([...entries.values()].map(async e=>{
        e.stopped=true;
        await e.startDone;
        if(e.active||e.finishing)await stopEntry(e,'service_stopped');
      }));
    },
  };
}
module.exports={createMeetingRecordings,validateRecordingRequest,summary};
