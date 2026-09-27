'use strict';
const {createHash} = require('node:crypto');
const C = require('../k135z_copilot_notes/contract.cjs');
const {identity} = require('./b5b_contract.cjs');
const {K135zZoomError} = require('./b5b_contract.cjs');
const TABLE = 'k135z_meeting_recordings';
const BUCKET = 'korlix-meeting-recordings';
const unavailable = () => new K135zZoomError(503,'K135Z_RECORDING_STORAGE_UNAVAILABLE');
const columns = 'id,tenant_id,user_id,agent_id,context,status,created_at,updated_at,duration_ms,byte_size,object_path,end_reason,process_id';
function owner(principal) {
  const p = identity(principal);
  return {tenant_id:p.tenantId,user_id:p.userId,agent_id:p.agentId};
}
function objectPath(principal,id) {
  const prefix = createHash('sha256').update(C.canonical(identity(principal))).digest('hex');
  return `${prefix}/${id}.mp3`;
}
function createRecordingStore(client) {
  function scope(query,principal) {
    for (const [key,value] of Object.entries(owner(principal))) query = query.eq(key,value);
    return query;
  }
  async function result(query) {
    const r = await query;
    if (r.error) throw unavailable();
    return r.data;
  }
  const store = {
    async list(principal) {
      return await result(scope(client.from(TABLE).select(columns),principal)
        .order('created_at',{ascending:false}).limit(21));
    },
    async get(principal,id) {
      return await result(scope(client.from(TABLE).select(columns).eq('id',id),principal).maybeSingle());
    },
    async reserve(principal,{id,context,processId,now}) {
      if ((await store.list(principal)).length >= 20)
        throw new K135zZoomError(429,'K135Z_RECORDING_LIBRARY_FULL');
      const row = {id,...owner(principal),context,status:'recording',process_id:processId,
        object_path:objectPath(principal,id),created_at:now,updated_at:now,
        duration_ms:0,byte_size:0,end_reason:null};
      const r = await client.from(TABLE).insert(row).select(columns).single();
      if (r.error) {
        if (r.error.code === '23505') throw new K135zZoomError(409,'K135Z_RECORDING_CONFLICT');
        throw unavailable();
      }
      return r.data;
    },
    async update(principal,id,patch,{processId,updatedAt,statuses}={}) {
      let q = scope(client.from(TABLE).update(patch).eq('id',id),principal);
      if (processId) q=q.eq('process_id',processId);
      if (updatedAt) q=q.eq('updated_at',updatedAt);
      if (statuses) q=q.in('status',statuses);
      return await result(q.select(columns).maybeSingle());
    },
    async upload(path,bytes) {
      const r=await client.storage.from(BUCKET).upload(path,bytes,
        {contentType:'audio/mpeg',cacheControl:'0',upsert:false});
      if (r.error) throw unavailable();
    },
    async link(path,download=false) {
      const r=await client.storage.from(BUCKET).createSignedUrl(path,3600,
        download ? {download:'Nova-meeting-recording.mp3'} : {});
      if (r.error || typeof r.data?.signedUrl !== 'string') throw unavailable();
      const url=new URL(r.data.signedUrl);
      if(url.protocol!=='https:' || url.origin!==new URL(client.supabaseUrl).origin || url.username || url.password)
        throw unavailable();
      return r.data.signedUrl;
    },
    async remove(principal,row) {
      const marked=await store.update(principal,row.id,{status:'deleting'},
        {statuses:['ready','failed','deleting']});
      if (!marked) throw new K135zZoomError(409,'K135Z_RECORDING_CONFLICT');
      const r=await client.storage.from(BUCKET).remove([objectPath(principal,row.id)]);
      if (r.error) throw unavailable();
      await result(scope(client.from(TABLE).delete().eq('id',row.id).eq('status','deleting'),principal));
    },
  };
  return store;
}
module.exports = {createRecordingStore,objectPath,TABLE,BUCKET};
