'use strict';
const C = require('../k135z_copilot_notes/contract.cjs');
const B = require('./b5b_contract.cjs');
const {K135zZoomError} = require('./zoom_token_vault.cjs');
const START_SCOPE = 'meeting:update:participant_rtms_app_status';
const fail = (code, status = 409) => { throw new K135zZoomError(status, code); };

// Starts only the explicitly selected, owned, live meeting. A REST acknowledgement
// never grants capture: the existing signed-webhook and consent checks still do.
function createZoomRtmsStarter({store, repository, oauthService, transport, clientId,
  fetchImpl = globalThis.fetch, waitMs = 5000} = {}) {
  const pending = new Set();
  const check = signal => { if (signal?.aborted) fail('ZOOM_RTMS_CANCELLED', 499); };
  async function http(path, accessToken, signal, body) {
    check(signal);
    const abort = new AbortController();
    const cancel = () => abort.abort();
    signal?.addEventListener('abort', cancel, {once:true});
    const timer = setTimeout(cancel, 6000);
    let reader;
    try {
      const url = 'https://api.zoom.us/v2/' + path;
      const response = await fetchImpl(url, {method:body ? 'PATCH' : 'GET',
        redirect:'error', signal:abort.signal,
        headers:{authorization:'Bearer ' + accessToken, accept:'application/json',
          ...(body ? {'content-type':'application/json'} : {})},
        ...(body ? {body:JSON.stringify(body)} : {})});
      check(signal);
      if (response.redirected || (response.url && response.url !== url)) fail('ZOOM_RTMS_RESPONSE_INVALID', 502);
      if (body && response.status === 204) return;
      let value = {};
      if (/^application\/json(?:\s*;|$)/i.test(response.headers?.get('content-type') || '')) {
        reader = response.body.getReader();
        const chunks = []; let bytes = 0;
        while (true) {
          const next = await reader.read(); check(signal);
          if (next.done) break;
          bytes += next.value.byteLength;
          if (bytes > 262144) fail('ZOOM_RTMS_RESPONSE_INVALID', 502);
          chunks.push(Buffer.from(next.value));
        }
        value = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      }
      if (response.status >= 200 && response.status < 300) return value;
      // Only allowlisted codes are exposed; never return Zoom bodies or tokens.
      if (value?.code === 2310) fail('ZOOM_RTMS_ACCOUNT_REJECTED', 403);
      if (value?.code === 2308) fail('ZOOM_RTMS_HOST_REJECTED', 403);
      if (value?.code === 4711 || response.status === 401) fail('ZOOM_RTMS_REAUTHORIZE', 403);
      if (response.status === 404 || value?.code === 3001) fail('ZOOM_RTMS_MEETING_NOT_LIVE');
      if (response.status === 429) fail('ZOOM_RTMS_RATE_LIMITED', 429);
      fail('ZOOM_RTMS_START_REJECTED', 502);
    } catch (error) {
      check(signal);
      if (error instanceof K135zZoomError) throw error;
      fail(abort.signal.aborted ? 'ZOOM_RTMS_TIMEOUT' : 'ZOOM_RTMS_REQUEST_FAILED', 502);
    } finally {
      clearTimeout(timer); abort.abort();
      signal?.removeEventListener('abort', cancel);
      if (reader) void reader.cancel().catch(() => {});
    }
  }
  return async function ensureStarted({principal, request, signal}) {
    const p = B.identity(principal), key = B.identityKey(p), r = request;
    C.object(r, ['action','context','bindingRevision','authorityRevision','listeningConsent']);
    C.context(r.context);
    if (r.action !== 'consent' || r.listeningConsent !== true) fail('ZOOM_RTMS_CONSENT_REQUIRED', 403);
    if (!['tenantId','userId','agentId'].every(k => r.context[k] === p[k])) fail('ZOOM_RTMS_BINDING_CHANGED');
    if (pending.has(key)) fail('ZOOM_RTMS_START_PENDING');
    if (pending.size >= 64) fail('ZOOM_RTMS_BUSY', 503);
    pending.add(key);
    const source = () => repository.getCaptureSource({key, meetingUuid:r.context.meetingUuid,
      streamId:r.context.streamId}, {signal});
    async function current() {
      check(signal);
      const row = await store.readCaptureLease({principal:p, context:r.context, signal});
      check(signal);
      if (!C.sameContext(row.record.snapshot.context, r.context) || row.bindingRevision !== r.bindingRevision ||
          row.authorityRevision !== r.authorityRevision || row.record.pending !== null || row.record.uncertain ||
          !['ready','paused'].includes(row.record.snapshot.state) || row.authority.viewerAuthorized !== true)
        fail('ZOOM_RTMS_BINDING_CHANGED');
      return row;
    }
    try {
      await current();
      if (await source()) { check(signal); return; }
      const original = await repository.getConnection(key); check(signal);
      if (!original) fail('ZOOM_RTMS_REAUTHORIZE', 403);
      if (!original.scope.split(/\s+/).includes(START_SCOPE)) fail('ZOOM_RTMS_SCOPE_REQUIRED', 403);
      if (!original.scope.split(/\s+/).includes('meeting:read:meeting_audio') ||
          !original.scope.split(/\s+/).includes('meeting:read:meeting_transcript'))
        fail('ZOOM_RTMS_MEDIA_SCOPE_REQUIRED', 403);
      const auth = await oauthService.getAuthorizedAccess(p); check(signal);
      const meetings = await transport.listUpcomingMeetings({accessToken:auth.accessToken, apiUrl:auth.apiUrl, userId:'me'});
      check(signal);
      const matches = meetings.meetings.filter(m => m.uuid === r.context.meetingUuid && m.is_host === true);
      if (matches.length !== 1 || !/^[1-9]\d{0,14}$/.test(String(matches[0].id))) fail('ZOOM_RTMS_RESELECT_MEETING');
      const id = String(matches[0].id);
      const meeting = await http('meetings/' + id, auth.accessToken, signal);
      if (meeting.uuid !== r.context.meetingUuid) fail('ZOOM_RTMS_RESELECT_MEETING');
      if (meeting.host_id !== original.zoomUserId) fail('ZOOM_RTMS_HOST_REJECTED', 403);
      if (meeting.status !== 'started') fail('ZOOM_RTMS_MEETING_NOT_LIVE');
      await current();
      const latest = await repository.getConnection(key); check(signal);
      if (!latest || latest.connectedAtMs !== original.connectedAtMs || latest.zoomUserId !== original.zoomUserId ||
          latest.zoomAccountId !== original.zoomAccountId || !latest.scope.split(/\s+/).includes(START_SCOPE))
        fail('ZOOM_RTMS_REAUTHORIZE', 403);
      if (await source()) { check(signal); return; }
      check(signal);
      await http('live_meetings/' + id + '/rtms_app/status', auth.accessToken, signal,
        {action:'start', settings:{client_id:clientId}});
      // The bounded wait only reads verified metadata. It never retries Start or
      // connects audio. Disconnecting/backgrounding cancels all further work.
      const deadline = Date.now() + waitMs;
      do {
        await current();
        if (await source()) { check(signal); return; }
        if (Date.now() >= deadline) break;
        await new Promise(resolve => {
          const done = () => { clearTimeout(timer); signal?.removeEventListener('abort', done); resolve(); };
          const timer = setTimeout(done, 250);
          signal?.addEventListener('abort', done, {once:true});
          if (signal?.aborted) done();
        });
      } while (!signal?.aborted);
      check(signal); fail('ZOOM_RTMS_WEBHOOK_PENDING');
    } finally { pending.delete(key); }
  };
}
module.exports = {createZoomRtmsStarter, START_SCOPE};
