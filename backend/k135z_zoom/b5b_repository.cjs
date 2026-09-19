'use strict';
// Injected RPC adapter. No client construction, environment access or connection on import.
const C = require('./b5b_contract.cjs');
const RPC = 'k135z_b5b_storage_v1';
function stateOutcome(r) {
  C.keys(r, ['outcome'], ['record']);
  if (r.outcome === 'ok') return C.stateRecord(r.record);
  const errors = {invalid:[400,'ZOOM_OAUTH_STATE_INVALID'], replayed:[409,'ZOOM_OAUTH_STATE_REPLAYED'], expired:[410,'ZOOM_OAUTH_STATE_EXPIRED']};
  const e = errors[r.outcome]; C.need(e, 'ZOOM_STORAGE_RESPONSE_INVALID',502); throw new C.K135zZoomError(...e);
}
function eventOutcome(r) {
  C.keys(r,['accepted','duplicate','deletedConnections']);
  C.need(typeof r.accepted === 'boolean' && r.duplicate === !r.accepted &&
    Number.isSafeInteger(r.deletedConnections) && r.deletedConnections >= 0, 'ZOOM_STORAGE_RESPONSE_INVALID',502); return r;
}
class SupabaseZoomRepository {
  constructor({client} = {}) { C.need(client && typeof client.rpc === 'function','ZOOM_STORAGE_CLIENT_REQUIRED',503); this.client=client; this.kind='supabase-b5b-v1'; }
  async rpc(operation, payload, signal) {
    let result;
    try { C.need(!signal?.aborted,'ZOOM_STORAGE_CANCELLED',503); const call=this.client.rpc(RPC,{operation,payload});
      result=await (signal && typeof call?.abortSignal==='function'?call.abortSignal(signal):call); }
    catch { throw new C.K135zZoomError(503,'ZOOM_STORAGE_UNAVAILABLE'); }
    C.need(result && !result.error && result.data !== undefined, 'ZOOM_STORAGE_UNAVAILABLE',503);
    return result.data; // Upstream errors/credentials are never forwarded.
  }
  async saveOAuthState(stateHash, record) {
    const r = await this.rpc('state_create',{stateHash:C.hash64(stateHash),record:C.stateRecord(record)});
    C.need(r === true,'ZOOM_STORAGE_RESPONSE_INVALID',502);
  }
  async consumeOAuthState(stateHash, nowMs=Date.now()) {
    return stateOutcome(await this.rpc('state_consume',{stateHash:C.hash64(stateHash),nowMs:C.time(nowMs)}));
  }
  async saveConnection(key, record) {
    const r=await this.rpc('connection_save',{key,record:C.connectionRecord(key,record)});
    C.need(r === true,'ZOOM_STORAGE_RESPONSE_INVALID',502);
  }
  async getConnection(key) {
    C.identityFromKey(key); const r=await this.rpc('connection_get',{key});
    return r === null ? null : C.connectionRecord(key,r);
  }
  async deleteConnection(key) {
    C.identityFromKey(key); const r=await this.rpc('connection_delete',{key});
    C.need(typeof r === 'boolean','ZOOM_STORAGE_RESPONSE_INVALID',502); return r;
  }
  async deleteConnectionsByZoomIdentity({zoomAccountId,zoomUserId}={}) {
    const r=await this.rpc('connection_deauthorize',{zoomAccountId:C.text(zoomAccountId),zoomUserId:C.text(zoomUserId)});
    C.need(Number.isSafeInteger(r)&&r>=0,'ZOOM_STORAGE_RESPONSE_INVALID',502); return r;
  }
  async getCaptureSource(query,{signal}={}) {
    const q=C.captureQuery(query),r=await this.rpc('capture_source',q,signal);
    if(r===null)return null;
    const v=C.captureSource(r);C.need(v.meetingUuid===q.meetingUuid && (q.streamId===null||v.streamId===q.streamId),'ZOOM_CAPTURE_BINDING_INVALID',502);
    return v;
  }
  async applyWebhookEvent(plan) { return eventOutcome(await this.rpc('event_apply',C.validatePlan(plan))); }
  async recordWebhookEvent(eventId, record) {
    C.keys(record,['event','eventTs','payloadHash']);
    return (await this.applyWebhookEvent({...record,eventId,mutation:{kind:'none'}})).accepted;
  }
  async upsertRtmsSession(key, record) { return C.sessionRecord(key,await this.rpc('session_upsert',{key,record:C.sessionRecord(key,record)})); }
  async getRtmsSession(key) { const r=await this.rpc('session_get',{key:C.hash64(key)}); return r===null ? null : C.sessionRecord(key,r); }
}
class MemoryZoomRepository {
  constructor() { this.kind='memory-offline-only'; this.oauthStates=new Map(); this.usedOAuthStates=new Set(); this.connections=new Map(); this.webhookEvents=new Map(); this.rtmsSessions=new Map(); this.rtmsTerminals=new Map(); this.rtmsSources=new Map(); }
  async saveOAuthState(h,r) { C.hash64(h); const v=C.stateRecord(r); C.need(!this.oauthStates.has(h)&&!this.usedOAuthStates.has(h),'ZOOM_STATE_EXISTS',409); this.oauthStates.set(h,v); }
  async consumeOAuthState(h,now=Date.now()) {
    C.hash64(h); C.time(now);
    if(this.usedOAuthStates.has(h)) return stateOutcome({outcome:'replayed'});
    const r=this.oauthStates.get(h); if(!r) return stateOutcome({outcome:'invalid'});
    this.oauthStates.delete(h); this.usedOAuthStates.add(h);
    return stateOutcome(now < r.createdAtMs || now >= r.expiresAtMs ? {outcome:'expired'} : {outcome:'ok',record:r});
  }
  async saveConnection(k,r) { this.connections.set(k,C.connectionRecord(k,r)); }
  async getConnection(k) { C.identityFromKey(k); const r=this.connections.get(k); return r ? C.connectionRecord(k,r) : null; }
  async deleteConnection(k) { C.identityFromKey(k); return this.connections.delete(k); }
  async deleteConnectionsByZoomIdentity(v) { C.text(v?.zoomAccountId); C.text(v?.zoomUserId); return this.deauthorize(v); }
  deauthorize(v) { let n=0; for(const [k,r] of this.connections) if(r.zoomAccountId===v.zoomAccountId && r.zoomUserId===v.zoomUserId) {this.connections.delete(k);n++;} return n; }
  terminal(m,eventTs) {
    const key=JSON.stringify([m.meetingUuid,m.streamId]),old=this.rtmsTerminals.get(key);
    const status=old?.status==='stopped'?'stopped':m.status;
    const value={...m,status,eventTs:Math.max(old?.eventTs??0,eventTs)};
    this.rtmsTerminals.set(key,value);
    for(const [k,r] of this.rtmsSessions) if(r.meetingUuid===m.meetingUuid && r.streamId===m.streamId)
      this.rtmsSessions.set(k,{...r,status:r.status==='stopped'?'stopped':status,eventTs:Math.max(r.eventTs,value.eventTs)});
  }
  session(k,r) {
    const terminal=this.rtmsTerminals.get(JSON.stringify([r.meetingUuid,r.streamId]));
    if(terminal) r={...r,status:r.status==='stopped'?'stopped':terminal.status,eventTs:Math.max(r.eventTs,terminal.eventTs)};
    const old=this.rtmsSessions.get(k);
    if(!old || (old.status!=='stopped' && r.eventTs>=old.eventTs)) this.rtmsSessions.set(k,structuredClone(r));
    return structuredClone(this.rtmsSessions.get(k));
  }
  async upsertRtmsSession(k,r) {
    // Standalone legacy B5A manager is metadata-only; persistence requires the strict v1 session shape.
    if(Object.hasOwn(r,'zoomAccountId')) {const value=C.sessionRecord(k,r);this.rtmsSources.delete(k);return this.session(k,value);}
    C.hash64(k); C.need(r.mediaConnected===false&&r.transcriptCollected===false&&r.audioInjected===false,'ZOOM_MEDIA_DISABLED');
    return this.session(k,r);
  }
  async getRtmsSession(k) { C.hash64(k); return structuredClone(this.rtmsSessions.get(k)??null); }
  async recordWebhookEvent(eventId,r) { C.keys(r,['event','eventTs','payloadHash']); return (await this.applyWebhookEvent({...r,eventId,mutation:{kind:'none'}})).accepted; }
  async getCaptureSource(query) {
    const q=C.captureQuery(query),c=this.connections.get(q.key);if(!c)return null;
    if(!c.scope.split(/ +/).includes('meeting:read:meeting_transcripts'))return null;
    const matches=[];
    for(const [key,s] of this.rtmsSessions) {
      const source=this.rtmsSources.get(key);
      if(s.status==='started' && s.meetingUuid===q.meetingUuid && (q.streamId===null||s.streamId===q.streamId) &&
        s.zoomAccountId===c.zoomAccountId && source && source.eventTs===s.eventTs && s.eventTs>=c.connectedAtMs &&
        source.value.originalHost===true && source.value.operatorId===c.zoomUserId)
        matches.push(C.captureSource({meetingUuid:s.meetingUuid,streamId:s.streamId,serverUrls:source.value.serverUrls}));
    }
    return matches.length===1?matches[0]:null;
  }
  async applyWebhookEvent(input) {
    const p=C.validatePlan(input), old=this.webhookEvents.get(p.eventId);
    if(old) { C.need(old.payloadHash===p.payloadHash,'ZOOM_EVENT_ID_CONFLICT',409); return {accepted:false,duplicate:true,deletedConnections:0}; }
    // Validation completes before any effect. This synchronous section is indivisible in this offline fake.
    let deletedConnections=0;
    if(p.mutation.kind==='terminal') this.terminal(p.mutation,p.eventTs);
    if(p.mutation.kind==='session') {
      const m=p.mutation,s=this.session(m.key,m.record);
      if(s.status==='started' && s.eventTs===p.eventTs) {
        if(m.source)this.rtmsSources.set(m.key,{eventTs:p.eventTs,value:structuredClone(m.source)});
        else this.rtmsSources.delete(m.key);
      }
    }
    if(p.mutation.kind==='deauthorize') deletedConnections=this.deauthorize(p.mutation);
    this.webhookEvents.set(p.eventId,{payloadHash:p.payloadHash,event:p.event,eventTs:p.eventTs});
    return {accepted:true,duplicate:false,deletedConnections};
  }
}
module.exports={RPC,SupabaseZoomRepository,MemoryZoomRepository};
