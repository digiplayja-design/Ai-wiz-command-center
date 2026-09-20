"use strict";

const crypto = require("node:crypto");
const {pcmLevel, createAudioLevelMeter} = require('./audio_level.cjs');

const {
  K135zZoomError,
} = require(
  "./zoom_token_vault.cjs",
);

function eventObject(body) {
  return (
    body?.payload?.object &&
    typeof body.payload.object ===
      "object"
  )
    ? body.payload.object
    : {};
}

function stableSessionKey(body) {
  const object =
    eventObject(body);

  const meetingUuid =
    String(
      object.uuid ||
        object.meeting_uuid ||
        "",
    ).trim();

  const meetingId =
    String(
      object.id ||
        object.meeting_id ||
        "",
    ).trim();

  const streamId =
    String(
      object.rtms_stream_id ||
        object.stream_id ||
        "",
    ).trim();

  const source = [
    meetingUuid,
    meetingId,
    streamId,
  ]
    .filter(Boolean)
    .join(":");

  if (!source) {
    throw new K135zZoomError(
      400,
      "ZOOM_RTMS_SESSION_IDENTITY_MISSING",
      "The RTMS event has no meeting or stream identity.",
    );
  }

  return crypto
    .createHash("sha256")
    .update(
      source,
      "utf8",
    )
    .digest("hex");
}

class ZoomRtmsSessionManager {
  constructor({
    repository,
    clock = () => Date.now(),
  }) {
    this.repository =
      repository;

    this.clock = clock;
  }

  async handleVerifiedEvent(
    body,
  ) {
    const event =
      String(
        body?.event || "",
      );

    if (
      ![
        "meeting.rtms_started",
        "meeting.rtms_stopped",
        "meeting.rtms_interrupted",
      ].includes(event)
    ) {
      return {
        handled: false,
      };
    }

    const object =
      eventObject(body);

    const sessionKey =
      stableSessionKey(body);

    const status =
      event.endsWith(
        "_started",
      )
        ? "started"
        : event.endsWith(
              "_stopped",
            )
          ? "stopped"
          : "interrupted";

    const record =
      await this.repository
        .upsertRtmsSession(
          sessionKey,
          {
            sessionKey,
            status,
            event,

            eventTs: Number(
              body?.event_ts ||
                this.clock(),
            ),

            meetingId:
              object.id != null
                ? String(
                    object.id,
                  )
                : null,

            meetingUuid:
              object.uuid
                ? String(
                    object.uuid,
                  )
                : null,

            streamId:
              object.rtms_stream_id
                ? String(
                    object.rtms_stream_id,
                  )
                : null,

            stopReason:
              object.stop_reason !=
              null
                ? Number(
                    object.stop_reason,
                  )
                : null,

            updatedAt:
              new Date(
                this.clock(),
              ).toISOString(),

            mediaConnected:
              false,

            transcriptCollected:
              false,

            audioInjected:
              false,
          },
        );

    return {
      handled: true,
      record,
    };
  }
}

// K135Z_GATE6D_COMMAND_BOUNDARY_BEGIN
// Internal service only: this is not an HTTP route or a live RTMS adapter.
// The injected adapter must resolve a server-owned context and atomically recheck
// authority, expected revision, command ordering and the terminal Stop fence.
// No adapter is installed by default. Webhook metadata cannot authorize capture.
const workspaceContract = require("../k135z_copilot_notes/contract.cjs");
const storageContract = require("./b5b_contract.cjs");

class WorkspaceBoundaryFailure extends Error {
  constructor(code) { super(code); this.code = code; }
}

class K135zWorkspaceCommandService {
  constructor({ authenticateRequest, resolveEnterprise, authorizeAgent, adapter = null,
    timeoutMs = workspaceContract.LIMITS.sessionTimeoutMs } = {}) {
    if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 ||
        timeoutMs > workspaceContract.LIMITS.sessionTimeoutMs) {
      throw new TypeError("K135Z_WORKSPACE_TIMEOUT_INVALID");
    }
    this.authenticateRequest = authenticateRequest;
    this.resolveEnterprise = resolveEnterprise;
    this.authorizeAgent = authorizeAgent;
    this.adapter = adapter;
    this.timeoutMs = timeoutMs;
  }

  async request(httpRequest, rawRequest, cancellation) {
    const C = workspaceContract;
    // An invalid request cannot receive a fabricated correlation envelope.
    let request;
    try { request = C.control(rawRequest, "request"); }
    catch (_) { throw new K135zZoomError(400, "K135Z_WORKSPACE_REQUEST_INVALID"); }
    const failed = (code, remoteOutcome) => C.control({ schemaVersion: 1,
      operation: request.operation, action: request.action, outcome: { kind: "failed",
        error: { code, message: "The requested operation could not be confirmed.",
          remoteOutcome, automaticRetry: false } } }, "reply");
    const deny = code => { throw new WorkspaceBoundaryFailure(code); };
    if (!cancellation || typeof cancellation.isCancelled !== "function" ||
        typeof cancellation.subscribe !== "function") {
      return failed("PROTOCOL_ERROR", "notRequested");
    }
    let finished = false, dispatched = false, stage = "authentication";
    let timer, unsubscribe, settle;
    const listeners = new Set();
    const result = new Promise(resolve => { settle = resolve; });
    const finish = reply => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      if (typeof unsubscribe === "function") { try { unsubscribe(); } catch (_) {} }
      for (const listener of listeners) { try { listener(); } catch (_) {} }
      listeners.clear();
      settle(reply);
    };
    const stop = code => finish(failed(code, dispatched ? "unknown" : "notRequested"));
    const current = () => {
      if (finished) return false;
      try {
        const cancelled = cancellation.isCancelled();
        if (typeof cancelled !== "boolean") { stop("PROTOCOL_ERROR"); return false; }
        if (cancelled) { stop("CANCELLED"); return false; }
      } catch (_) { stop("PROTOCOL_ERROR"); return false; }
      return true;
    };
    const token = Object.freeze({ isCancelled: () => !current(), subscribe(listener) {
      if (typeof listener !== "function") throw new TypeError("K135Z_CANCELLATION_LISTENER_INVALID");
      if (finished) { listener(); return () => {}; }
      listeners.add(listener);
      return () => { listeners.delete(listener); };
    } });
    if (!current()) return result;
    try {
      unsubscribe = cancellation.subscribe(() => { stop("CANCELLED"); });
      if (typeof unsubscribe !== "function") stop("PROTOCOL_ERROR");
      // A subscription may synchronously report cancellation before it returns.
      if (finished && typeof unsubscribe === "function") { try { unsubscribe(); } catch (_) {} }
    } catch (_) { stop("PROTOCOL_ERROR"); }
    if (!current()) return result;
    timer = setTimeout(() => stop("TIMEOUT"), this.timeoutMs);
    const run = async () => {
      try {
        if (typeof this.authenticateRequest !== "function" ||
            typeof this.resolveEnterprise !== "function" ||
            typeof this.authorizeAgent !== "function") deny("DENIED");
        const principal = await this.authenticateRequest(httpRequest);
        if (!current()) return;
        if (!principal) deny("DENIED");
        const bound = C.freeze(storageContract.identity(principal));
        const enterprise = await this.resolveEnterprise(principal, httpRequest);
        if (!current()) return;
        if (enterprise !== true) deny("DENIED");
        const owned = await this.authorizeAgent(bound, httpRequest);
        if (!current()) return;
        if (owned !== true) deny("DENIED");
        stage = "binding";
        for (const key of ["tenantId", "userId", "agentId"]) {
          if (request.expectedContext[key] !== bound[key]) deny("BINDING_MISMATCH");
        }
        const adapter = this.adapter;
        if (!adapter || typeof adapter.resolveContext !== "function" ||
            typeof adapter.requestAtomic !== "function") deny("UNAVAILABLE");
        const rawContext = await adapter.resolveContext({ principal: bound, cancellation: token });
        if (!current()) return;
        let context;
        try { context = C.context(rawContext); } catch (_) { deny("PROTOCOL_ERROR"); }
        if (!C.sameContext(context, request.expectedContext)) deny("BINDING_MISMATCH");
        // The adapter owns the atomic check. This earlier lookup never grants
        // authority or replaces an atomic revision/host/permission decision.
        stage = "dispatch";
        dispatched = true;
        const rawReply = await adapter.requestAtomic({ principal: bound, request, cancellation: token });
        if (!current()) return;
        stage = "reply";
        const reply = C.control(rawReply, "reply");
        if (reply.action !== request.action ||
            C.canonical(reply.operation) !== C.canonical(request.operation)) deny("PROTOCOL_ERROR");
        if (reply.outcome.kind === "acknowledged") {
          const snapshot = reply.outcome.snapshot;
          const expected = request.expectedContext;
          const adopted = request.action === "start" && expected.streamId === null &&
            snapshot.context.streamId !== null &&
            C.sameContext({ ...snapshot.context, streamId: null }, expected);
          if (!C.sameContext(snapshot.context, expected) && !adopted) deny("BINDING_MISMATCH");
          const revision = request.expectedSnapshotRevision;
          if (revision !== null && (request.action === "refresh"
              ? snapshot.revision < revision : snapshot.revision <= revision)) deny("PROTOCOL_ERROR");
          const states = { start: "listening", pause: "paused", stop: "stopped" };
          if (request.action !== "refresh" && snapshot.state !== states[request.action]) deny("PROTOCOL_ERROR");
          if (request.action === "start" && (!snapshot.hostAuthorized ||
              !snapshot.listeningAuthorized || snapshot.context.streamId === null)) deny("DENIED");
        }
        finish(reply);
      } catch (error) {
        if (!current()) return;
        const code = error instanceof WorkspaceBoundaryFailure ? error.code :
          stage === "authentication" ? "DENIED" : stage === "reply" ? "PROTOCOL_ERROR" : "UNAVAILABLE";
        finish(failed(code, dispatched ? "unknown" : "notRequested"));
      }
    };
    void run();
    return result;
  }
}
// K135Z_GATE6D_COMMAND_BOUNDARY_END

// K135Z_GATE6E_ATOMIC_ADAPTER_BEGIN
// Store contract: read resolves a server-owned binding. transact serializes one
// synchronous decision, rechecks current authority and durably commits its record
// before returning the exact decision. It must never replay the callback.
// No memory store, provider, session binding or live capture is installed here.
class K135zAtomicWorkspaceAdapter {
  constructor({store, transport} = {}) {
    if (!store || typeof store.read !== 'function' || typeof store.transact !== 'function' ||
        !transport || typeof transport.request !== 'function') {
      throw new TypeError('K135Z_ATOMIC_DEPENDENCIES_REQUIRED');
    }
    this.store = store;
    this.transport = transport;
  }
  static record(raw) {
    const C = workspaceContract;
    C.object(raw, ['snapshot', 'version', 'pending', 'uncertain']);
    const record = {snapshot:C.snapshot(raw.snapshot), version:C.uint(raw.version),
      pending:null, uncertain:C.bool(raw.uncertain)};
    if (raw.pending !== null) {
      C.object(raw.pending, ['request', 'ticketVersion', 'phase']);
      record.pending = {request:C.control(raw.pending.request, 'request'),
        ticketVersion:C.uint(raw.pending.ticketVersion),
        phase:C.oneOf(raw.pending.phase, ['prepared', 'dispatched'])};
      C.requireValue(record.pending.ticketVersion <= record.version &&
        C.sameContext(record.pending.request.expectedContext, record.snapshot.context) &&
        record.pending.request.expectedSnapshotRevision === record.snapshot.revision);
    }
    C.requireValue(!record.uncertain || record.pending?.phase === 'dispatched');
    C.checkSize(record, 2 * C.LIMITS.envelope + 1024, 'control');
    return C.freeze(record);
  }
  static failure(request, code, remoteOutcome = 'notRequested') {
    return workspaceContract.control({schemaVersion:1, operation:request.operation,
      action:request.action, outcome:{kind:'failed', error:{code,
        message:'The session command could not be confirmed.', remoteOutcome,
        automaticRetry:false}}}, 'reply');
  }
  static cancelled(token) {
    if (!token || typeof token.isCancelled !== 'function' ||
        typeof token.subscribe !== 'function') throw new WorkspaceBoundaryFailure('PROTOCOL_ERROR');
    const value = token.isCancelled();
    if (typeof value !== 'boolean') throw new WorkspaceBoundaryFailure('PROTOCOL_ERROR');
    return value;
  }
  static bound(input, principal, context) {
    const C = workspaceContract;
    C.object(input, ['record', 'authority']);
    const record = this.record(input.record), a = input.authority;
    C.object(a, ['context', 'viewerAuthorized', 'hostAuthorized', 'listeningAuthorized']);
    C.context(a.context);C.bool(a.viewerAuthorized);C.bool(a.hostAuthorized);C.bool(a.listeningAuthorized);
    for (const key of ['tenantId', 'userId', 'agentId']) {
      if (record.snapshot.context[key] !== principal[key]) throw new WorkspaceBoundaryFailure('BINDING_MISMATCH');
    }
    if (!C.sameContext(a.context, record.snapshot.context) ||
        (context && !C.sameContext(context, record.snapshot.context))) {
      throw new WorkspaceBoundaryFailure('BINDING_MISMATCH');
    }
    if (a.viewerAuthorized !== true) throw new WorkspaceBoundaryFailure('DENIED');
    return {record, authority:C.freeze(C.clone(a))};
  }
  async resolveContext({principal, cancellation}) {
    const A = K135zAtomicWorkspaceAdapter, p = storageContract.identity(principal);
    if (A.cancelled(cancellation)) throw new WorkspaceBoundaryFailure('CANCELLED');
    const input = await this.store.read({principal:p, cancellation});
    if (A.cancelled(cancellation)) throw new WorkspaceBoundaryFailure('CANCELLED');
    return A.bound(input, p).record.snapshot.context;
  }
  async requestAtomic({principal, request:rawRequest, cancellation}) {
    const A = K135zAtomicWorkspaceAdapter, C = workspaceContract;
    const request = C.control(rawRequest, 'request'), p = C.freeze(storageContract.identity(principal));
    let dispatched = false;
    const failure = (code, remote = dispatched ? 'unknown' : 'notRequested') => A.failure(request, code, remote);
    const settle = reply => {
      if (dispatched && typeof this.transport.settle === 'function') {
        try {
          const value = this.transport.settle({principal:p,request,reply});
          if (value && typeof value.then === 'function') void Promise.resolve(value).catch(()=>{});
          if (value !== true) return failure('UNAVAILABLE','unknown');
        } catch (_) { return failure('UNAVAILABLE','unknown'); }
      }
      return reply;
    };
    const change = (r, fields) => {
      C.requireValue(r.version < Number.MAX_SAFE_INTEGER);
      return A.record({...r, ...fields, version:r.version + 1});
    };
    const transaction = async decide => {
      let decision, calls = 0;
      const result = await this.store.transact({principal:p, context:request.expectedContext, cancellation}, input => {
        if (++calls !== 1) throw new WorkspaceBoundaryFailure('PROTOCOL_ERROR');
        decision = C.freeze(decide(A.bound(input, p, request.expectedContext)));
        return decision;
      });
      if (calls !== 1 || C.canonical(result) !== C.canonical(decision)) {
        throw new WorkspaceBoundaryFailure('PROTOCOL_ERROR');
      }
      return decision;
    };
    try {
      if (A.cancelled(cancellation)) return failure('CANCELLED');
      const reserved = await transaction(({record:r, authority:a}) => {
        const deny = code => ({record:r, reply:failure(code), ticket:null});
        if (A.cancelled(cancellation)) return deny('CANCELLED');
        if (r.pending || r.uncertain) return deny('CONFLICT');
        if (request.expectedSnapshotRevision !== null && request.expectedSnapshotRevision !== r.snapshot.revision) return deny('CONFLICT');
        if (request.action === 'refresh') {
          if (r.snapshot.hostAuthorized !== a.hostAuthorized ||
              r.snapshot.listeningAuthorized !== a.listeningAuthorized) return deny('DENIED');
          return {record:r, ticket:null, reply:C.control({schemaVersion:1, operation:request.operation,
            action:'refresh', outcome:{kind:'acknowledged', snapshot:r.snapshot}}, 'reply')};
        }
        if (r.snapshot.state === 'stopped' || r.snapshot.revision === Number.MAX_SAFE_INTEGER ||
            r.version > Number.MAX_SAFE_INTEGER - 3) return deny('CONFLICT');
        if (request.action === 'start' && (!['ready','paused'].includes(r.snapshot.state) ||
            !a.hostAuthorized || !a.listeningAuthorized)) return deny('DENIED');
        if (request.action === 'pause' && r.snapshot.state !== 'listening') return deny('CONFLICT');
        const ticket = {request, ticketVersion:r.version + 1, phase:'prepared'};
        return {record:change(r, {pending:ticket}), reply:null, ticket};
      });
      if (reserved.reply) return reserved.reply;
      const ticket = reserved.ticket;
      const owns = r => r.pending && r.pending.ticketVersion === ticket.ticketVersion &&
        C.canonical(r.pending.request) === C.canonical(request);
      const armed = await transaction(({record:r, authority:a}) => {
        if (!owns(r) || r.pending.phase !== 'prepared') throw new WorkspaceBoundaryFailure('CONFLICT');
        const code = A.cancelled(cancellation) ? 'CANCELLED' : request.action === 'start' &&
          (!a.hostAuthorized || !a.listeningAuthorized) ? 'DENIED' : null;
        if (code) return {record:change(r, {pending:null}), reply:failure(code)};
        return {record:change(r, {pending:{...r.pending, phase:'dispatched'}}), reply:null};
      });
      if (armed.reply) return armed.reply;
      dispatched = true;
      let reply;
      if (A.cancelled(cancellation)) reply = failure('CANCELLED');
      else {
        reply = await new Promise(resolve => {
          let done = false, unsubscribe;
          const finish = value => {
            if (done) return;
            done = true;
            if (typeof unsubscribe === 'function') { try { unsubscribe(); } catch (_) {} }
            resolve(value);
          };
          try {
            unsubscribe = cancellation.subscribe(() => finish(failure('CANCELLED')));
            if (typeof unsubscribe !== 'function') finish(failure('PROTOCOL_ERROR'));
            if (done) { if (typeof unsubscribe === 'function') unsubscribe(); return; }
            if (A.cancelled(cancellation)) { finish(failure('CANCELLED')); return; }
            Promise.resolve(this.transport.request({principal:p, request,
              snapshot:reserved.record.snapshot, cancellation})).then(value => {
                try { finish(C.control(value, 'reply')); }
                catch (_) { finish(failure('PROTOCOL_ERROR')); }
              }, () => finish(failure('UNAVAILABLE')));
          } catch (_) { finish(failure('UNAVAILABLE')); }
        });
      }
      const completed = await transaction(({record:r, authority:a}) => {
        if (!owns(r) || r.pending.phase !== 'dispatched') throw new WorkspaceBoundaryFailure('CONFLICT');
        let accepted = reply;
        if (A.cancelled(cancellation)) accepted = failure('CANCELLED');
        try {
          if (accepted.action !== request.action || C.canonical(accepted.operation) !== C.canonical(request.operation)) throw Error();
          if (accepted.outcome.kind === 'acknowledged') {
            const s = accepted.outcome.snapshot, old = r.snapshot;
            const adopted = request.action === 'start' && old.context.streamId === null &&
              s.context.streamId !== null && C.sameContext({...s.context, streamId:null}, old.context);
            if ((!C.sameContext(s.context, old.context) && !adopted) || s.revision !== old.revision + 1 ||
                s.activeSeconds < old.activeSeconds || s.state !== {start:'listening',pause:'paused',stop:'stopped'}[request.action] ||
                s.hostAuthorized !== a.hostAuthorized || s.listeningAuthorized !== a.listeningAuthorized ||
                (request.action === 'start' && (!a.hostAuthorized || !a.listeningAuthorized || s.context.streamId === null))) throw Error();
            return {record:change(r, {snapshot:s, pending:null, uncertain:false}), reply:accepted};
          }
        } catch (_) { accepted = failure('PROTOCOL_ERROR'); }
        const unknown = accepted.outcome.error.remoteOutcome === 'unknown';
        return {record:change(r, {pending:unknown ? r.pending : null, uncertain:unknown}), reply:accepted};
      });
      return settle(completed.reply);
    } catch (error) {
      return settle(failure(error instanceof WorkspaceBoundaryFailure ? error.code : 'UNAVAILABLE'));
    }
  }
}
// K135Z_GATE6E_ATOMIC_ADAPTER_END

// K135Z_GATE6F_RPC_STORE_BEGIN
// Backend-only RPC client; the database function is not installed by this patch.
// compare_save MUST lock the binding, recheck current authority and both fences,
// compare the full expected record/authority, then commit before returning ok.
// Conflicts never replay the synchronous callback. No in-memory fallback.
class K135zSupabaseWorkspaceStore {
  constructor({client, timeoutMs=5000}={}) {
    if (!client || typeof client.rpc !== 'function' || !Number.isSafeInteger(timeoutMs) ||
        timeoutMs < 1 || timeoutMs > 15000) throw new TypeError('K135Z_COMMAND_STORE_REQUIRED');
    this.client=client;this.timeoutMs=timeoutMs;
  }
  async rpc(operation,payload,signal) {
    const abort=new AbortController();let timer,listener;
    if(signal?.aborted)throw new WorkspaceBoundaryFailure('CANCELLED');
    try {
      const cancelled=new Promise((_,reject)=>{listener=()=>{abort.abort();reject(new WorkspaceBoundaryFailure('CANCELLED'));};
        signal?.addEventListener('abort',listener,{once:true});});
      const result=await Promise.race([cancelled,
        Promise.resolve().then(()=>{
          if(signal?.aborted)throw new WorkspaceBoundaryFailure('CANCELLED');
          const call=this.client.rpc('k135z_workspace_commands_v1',{operation,payload});
          return call && typeof call.abortSignal==='function' ? call.abortSignal(abort.signal) : call;
        }),
        new Promise((_,reject)=>{timer=setTimeout(()=>{
          abort.abort();reject(new WorkspaceBoundaryFailure('TIMEOUT'));
        },this.timeoutMs);})
      ]);
      if(signal?.aborted)throw new WorkspaceBoundaryFailure('CANCELLED');
      if (!result || result.error || !Object.hasOwn(result,'data')) throw Error();
      return result.data;
    } catch (error) {
      throw new WorkspaceBoundaryFailure(signal?.aborted ? 'CANCELLED' : abort.signal.aborted ? 'TIMEOUT' : 'UNAVAILABLE');
    } finally {clearTimeout(timer);signal?.removeEventListener('abort',listener);}
  }
  decode(raw,principal,context) {
    const C=workspaceContract;
    try {
      C.checkSize(raw,3*C.LIMITS.envelope,'control');
      if (raw && raw.status!=='ok') {
        C.object(raw,['status']);
        C.oneOf(raw.status,['conflict','denied','not_found']);
        const code={conflict:'CONFLICT',denied:'DENIED',not_found:'BINDING_MISMATCH'}[raw.status];
        if (!code) throw Error();
        throw new WorkspaceBoundaryFailure(code);
      }
      C.object(raw,['status','bindingRevision','authorityRevision','record','authority']);
      C.requireValue(raw.status==='ok');C.uint(raw.bindingRevision);C.uint(raw.authorityRevision);
      const bound=K135zAtomicWorkspaceAdapter.bound({record:raw.record,authority:raw.authority},principal,context);
      return C.freeze({bindingRevision:raw.bindingRevision,authorityRevision:raw.authorityRevision,...bound});
    } catch (error) {
      if (error instanceof WorkspaceBoundaryFailure) throw error;
      throw new WorkspaceBoundaryFailure('PROTOCOL_ERROR');
    }
  }
  async read({principal,cancellation}) {
    const A=K135zAtomicWorkspaceAdapter,p=storageContract.identity(principal);
    if (A.cancelled(cancellation)) throw new WorkspaceBoundaryFailure('CANCELLED');
    const input=this.decode(await this.rpc('read',{principal:p}),p);
    if (A.cancelled(cancellation)) throw new WorkspaceBoundaryFailure('CANCELLED');
    return workspaceContract.freeze({record:input.record,authority:input.authority});
  }
  decodeLease(raw,p,context) {
    const C=workspaceContract;
    if(raw?.status!=='ok')return this.decode(raw,p,context);
    try {
      C.checkSize(raw,3*C.LIMITS.envelope,'control');
      C.object(raw,['status','bindingRevision','authorityRevision','record','authority','validForMs']);
      C.uint(raw.validForMs);C.requireValue(raw.validForMs<=60000);
      const {validForMs,...row}=raw,value=this.decode(row,p,context);
      C.requireValue(value.bindingRevision===value.record.snapshot.context.generation && value.bindingRevision>0);
      return C.freeze({...value,validForMs});
    }catch(error){if(error instanceof WorkspaceBoundaryFailure)throw error;throw new WorkspaceBoundaryFailure('PROTOCOL_ERROR');}
  }
  async readCaptureLease({principal,context,signal}) {
    const p=storageContract.identity(principal);
    return this.decodeLease(await this.rpc('capture_lease',{principal:p},signal),p,context);
  }
  async bindWorkspace({principal,meetingUuid,expectedBindingRevision,signal}) {
    const C=workspaceContract,p=storageContract.identity(principal);
    C.text(meetingUuid);C.uint(expectedBindingRevision);
    const row=this.decode(await this.rpc('bind',{principal:p,meetingUuid,expectedBindingRevision},signal),p);
    if(row.bindingRevision!==expectedBindingRevision+1 || row.record.snapshot.context.generation!==row.bindingRevision ||
      row.record.pending!==null || row.record.uncertain || row.record.snapshot.context.meetingUuid!==meetingUuid ||
      row.record.snapshot.state!=='ready' || row.authority.hostAuthorized || row.authority.listeningAuthorized)
      throw new WorkspaceBoundaryFailure('PROTOCOL_ERROR');
    return C.freeze({...row,validForMs:0});
  }
  async changeConsent({principal,request,signal}) {
    const C=workspaceContract,p=storageContract.identity(principal),r=C.clone(request);
    C.object(r,['action','context','bindingRevision','authorityRevision'],r.action==='consent'?['listeningConsent']:[]);
    C.oneOf(r.action,['consent','renew','revoke']);C.context(r.context);
    C.uint(r.bindingRevision);C.uint(r.authorityRevision);
    C.requireValue(r.action!=='consent'||r.listeningConsent===true);
    for(const key of ['tenantId','userId','agentId'])
      if(r.context[key]!==p[key])throw new WorkspaceBoundaryFailure('BINDING_MISMATCH');
    const {action,...body}=r,row=this.decodeLease(await this.rpc(action,{principal:p,...body},signal),p,r.context);
    const revision=r.authorityRevision+(action==='renew'?0:1);
    if(row.bindingRevision!==r.bindingRevision || row.authorityRevision!==revision ||
      action==='revoke'&&(row.validForMs!==0 || row.authority.hostAuthorized || row.authority.listeningAuthorized))
      throw new WorkspaceBoundaryFailure('PROTOCOL_ERROR');
    return row;
  }
  async transact({principal,context,cancellation},decide) {
    const C=workspaceContract,A=K135zAtomicWorkspaceAdapter;
    const p=C.freeze(storageContract.identity(principal)),ctx=C.context(context);
    A.cancelled(cancellation); // Cleanup decisions must still run after cancellation.
    if (typeof decide!=='function') throw new WorkspaceBoundaryFailure('PROTOCOL_ERROR');
    const before=this.decode(await this.rpc('read',{principal:p}),p,ctx);
    let decision,record;
    try {
      decision=decide(C.freeze({record:before.record,authority:before.authority}));
      if (decision && typeof decision.then==='function') {
        void Promise.resolve(decision).catch(()=>{});throw Error();
      }
      C.object(decision,['record'],['reply','ticket']);
      C.checkSize(decision,4*C.LIMITS.envelope,'control');
      record=A.record(decision.record);
      const unchanged=C.canonical(record)===C.canonical(before.record);
      C.requireValue(unchanged || (before.record.version<Number.MAX_SAFE_INTEGER &&
        record.version===before.record.version+1));
      const old=before.record.snapshot,now=record.snapshot;
      const adoption=old.context.streamId===null && now.context.streamId!==null &&
        C.sameContext({...now.context,streamId:null},old.context) &&
        before.record.pending?.phase==='dispatched' &&
        before.record.pending.request.action==='start' && record.pending===null &&
        !record.uncertain && now.state==='listening' && now.revision===old.revision+1;
      C.requireValue(C.sameContext(old.context,now.context) || adoption);
      // A stopped generation cannot be reopened through the storage boundary.
      C.requireValue(old.state!=='stopped' || C.canonical(now)===C.canonical(old));
      decision=C.freeze(C.clone(decision));
    } catch (error) {
      if (error instanceof WorkspaceBoundaryFailure) throw error;
      throw new WorkspaceBoundaryFailure('PROTOCOL_ERROR');
    }
    // Even a read-only decision uses compare_save to validate its authority fence.
    const after=this.decode(await this.rpc('compare_save',{principal:p,context:ctx,
      expected:before,record}),p,record.snapshot.context);
    const expectedAuthority={...before.authority,context:record.snapshot.context};
    if (after.bindingRevision!==before.bindingRevision ||
        after.authorityRevision!==before.authorityRevision ||
        C.canonical(after.record)!==C.canonical(record) ||
        C.canonical(after.authority)!==C.canonical(expectedAuthority)) {
      throw new WorkspaceBoundaryFailure('PROTOCOL_ERROR');
    }
    return decision;
  }
}
// K135Z_GATE6F_RPC_STORE_END

// K135Z_GATE6I_RTMS_STREAM_BEGIN
// Internal SDK driver. The server must supply a verified binding, signed Zoom
// endpoint and a synchronous check of its current authority lease. No HTTP
// request may supply these dependencies. Nothing connects during construction.
function createK135zRtmsStream({sdk,context,serverUrls,signature,authorize,onTranscript,onAudioLevel,
  onClosed=()=>{},leaseMs=15000,joinTimeoutMs=10000,
  clock=()=>require('node:perf_hooks').performance.now()}={}) {
  const C=workspaceContract,ctx=C.context(context);
  const error=code=>Object.assign(new Error('K135Z_RTMS_'+code),{code});
  const need=(ok,code='INVALID_INPUT')=>{if(!ok)throw error(code);};
  need(ctx.streamId!==null && typeof sdk?.Client==='function' && sdk.RTMS_SDK_OK===0);
  need(typeof authorize==='function' && typeof onTranscript==='function' && typeof onClosed==='function' && typeof clock==='function');
  const validLease=n=>Number.isSafeInteger(n)&&n>=1&&n<=60000;
  need(validLease(leaseMs) && Number.isSafeInteger(joinTimeoutMs)&&joinTimeoutMs>=1&&joinTimeoutMs<=15000);
  need(typeof signature==='string' && /^[a-f0-9]{64}$/.test(signature));
  need(typeof serverUrls==='string' && serverUrls.length>0 && serverUrls.length<=4096);
  const urls=serverUrls.split(',');need(urls.length<=4);
  for(const value of urls){
    let u;try{u=new URL(value);}catch{throw error('INVALID_ENDPOINT');}
    need(value===value.trim() && u.protocol==='wss:' && !u.username && !u.password && !u.hash &&
      (!u.port||u.port==='443') && /^(?:[a-z0-9-]+\.)+zoom\.us$/i.test(u.hostname),'INVALID_ENDPOINT');
  }
  let phase='idle',client=null,deadline=0,leaseTimer,joinTimer,checkTimer,abortSignal,abortHandler;
  let resolveJoin,rejectJoin,settled=false,closed=null,joinReturned=false,pendingReason;
  const now=()=>{const n=clock();need(typeof n==='number'&&Number.isFinite(n)&&n>=0,'CLOCK_INVALID');return n;};
  const authorized=()=>{try{return authorize(ctx)===true;}catch{return false;}};
  const permitted=()=>{try{return authorized()&&now()<deadline;}catch{return false;}};
  function consume(value){if(value&&typeof value.then==='function')Promise.resolve(value).catch(()=>{});}
  function end(code){
    if(closed)return closed;
    closed=Object.freeze({code,released:false});phase='closed';clearTimeout(leaseTimer);clearTimeout(joinTimer);clearInterval(checkTimer);
    if(abortSignal&&abortHandler)abortSignal.removeEventListener('abort',abortHandler);
    let released=true;try{if(client)released=client.leave()===true;}catch{released=false;}
    closed=Object.freeze({code,released});
    if(!settled&&rejectJoin){settled=true;rejectJoin(error(code));}
    try{consume(onClosed(closed));}catch{}
    return closed;
  }
  function scheduleLease(){
    clearTimeout(leaseTimer);
    leaseTimer=setTimeout(()=>{
      if(phase==='closed')return;
      if(!permitted())end('AUTHORIZATION_EXPIRED');else scheduleLease();
    },Math.max(1,deadline-now()));
  }
  function confirm(reason){
    if(phase!=='connecting')return;
    if(!joinReturned){pendingReason=reason;return;}
    if(reason!==sdk.RTMS_SDK_OK){end('JOIN_FAILED');return;}
    if(!permitted()){end('DENIED');return;}
    phase='connected';clearTimeout(joinTimer);settled=true;
    resolveJoin(Object.freeze({context:ctx,state:'connected'}));
  }
  function transcript(buffer,size,timestamp,metadata){
    if(phase!=='connected')return;
    if(!permitted()){end('DENIED');return;}
    let packet;
    try{
      need(Buffer.isBuffer(buffer)&&Number.isSafeInteger(size)&&size>0&&size===buffer.length&&size<=C.LIMITS.text);
      const text=new TextDecoder('utf-8',{fatal:true}).decode(buffer);C.nonblank(text);
      need(metadata&&typeof metadata==='object');
      packet={context:ctx,text,providerTimestamp:C.uint(timestamp),userId:C.uint(metadata.userId),
        userName:C.text(metadata.userName),startTs:C.uint(metadata.startTs),endTs:C.uint(metadata.endTs)};
      need(Buffer.byteLength(packet.userName,'utf8')<=256&&packet.endTs>=packet.startTs);
      C.checkSize(packet,C.LIMITS.envelope);C.freeze(packet);
    }catch{end('INVALID_TRANSCRIPT');return;}
    try{const accepted=onTranscript(packet);if(accepted!==true){consume(accepted);end('BACKPRESSURE');}}
    catch{end('TRANSCRIPT_HANDLER_FAILED');}
  }
  function connect({signal}={}){
    if(phase!=='idle')return Promise.reject(error('ALREADY_USED'));
    if(signal!==undefined)need(signal&&typeof signal.aborted==='boolean'&&typeof signal.addEventListener==='function'&&typeof signal.removeEventListener==='function');
    phase='connecting';
    const promise=new Promise((resolve,reject)=>{resolveJoin=resolve;rejectJoin=reject;});
    try{
      deadline=now()+leaseMs;
      if(!authorized()){end('DENIED');return promise;}
      if(signal?.aborted){end('CANCELLED');return promise;}
      abortSignal=signal;abortHandler=()=>end('CANCELLED');signal?.addEventListener('abort',abortHandler,{once:true});
      if(signal?.aborted||phase==='closed'){end('CANCELLED');return promise;}
      need(typeof sdk.configureLogger==='function','SDK_INVALID');sdk.configureLogger({enabled:false});
      client=new sdk.Client();
      if(typeof onAudioLevel==='function') {
        need(typeof client.setAudioParams==='function' && typeof client.onAudioData==='function','AUDIO_SDK_INVALID');
        need(client.setAudioParams({contentType:2,codec:1,sampleRate:1,channel:1,
          dataOpt:1,duration:20,frameSize:320})===true,'AUDIO_CONFIGURATION_FAILED');
        need(client.onAudioData((buffer,size)=>{
          if(phase!=='connected')return;
          if(!permitted()){end('DENIED');return;}
          const level=pcmLevel(buffer,size);
          if(level)try{onAudioLevel(level);}catch{end('AUDIO_HANDLER_FAILED');}
        })===true,'AUDIO_CALLBACK_FAILED');
      }
      for(const [name,callback] of [['onJoinConfirm',confirm],['onTranscriptData',transcript],['onLeave',()=>end('REMOTE_CLOSED')]]){
        need(typeof client[name]==='function'&&client[name](callback)===true,'CALLBACK_REGISTRATION_FAILED');
      }
      need(phase==='connecting'&&permitted(),'DENIED');
      scheduleLease();checkTimer=setInterval(()=>{if(!permitted())end('DENIED');},250);
      joinTimer=setTimeout(()=>end('JOIN_TIMEOUT'),joinTimeoutMs);
      const started=client.join({meeting_uuid:ctx.meetingUuid,rtms_stream_id:ctx.streamId,
        server_urls:serverUrls,signature,is_verify_cert:1,timeout:joinTimeoutMs,pollInterval:10});
      joinReturned=true;
      if(phase==='closed'){try{client.leave();}catch{}return promise;}
      if(started!==true)end('JOIN_FAILED');else if(pendingReason!==undefined)confirm(pendingReason);
    }catch{end('SDK_ERROR');}
    return promise;
  }
  return Object.freeze({connect,
    close:()=>end('STOPPED'),
    status:()=>Object.freeze({phase,closed}),
    renew(ms=leaseMs){
      need(validLease(ms));
      if(!['connecting','connected'].includes(phase)||!permitted()){if(phase!=='idle')end('DENIED');return false;}
      deadline=now()+ms;scheduleLease();return true;
    }
  });
}
// K135Z_GATE6I_RTMS_STREAM_END

// K135Z_GATE6J_RTMS_TRANSPORT_BEGIN
// Server-only dependency: resolveGrant must verify the owned provider binding
// and current permission lease. Never build grants from browser flags or an
// unsigned webhook. This factory does not install routes or grant permissions.
// validForMs is measured from BEFORE the resolver call; network time consumes it.
function createK135zRtmsCommandTransport({sdk,resolveGrant,onTranscript,
  clock=()=>require('node:perf_hooks').performance.now(),grantTimeoutMs=2000,
  maxSessions=64,audioLevels=false}={}) {
  const C=workspaceContract,A=K135zAtomicWorkspaceAdapter;
  const need=(ok,code='PROTOCOL_ERROR')=>{if(!ok)throw new WorkspaceBoundaryFailure(code);};
  need(typeof sdk?.Client==='function' && sdk.RTMS_SDK_OK===0 &&
    typeof resolveGrant==='function' && typeof onTranscript==='function' && typeof clock==='function');
  need(Number.isSafeInteger(grantTimeoutMs)&&grantTimeoutMs>=1&&grantTimeoutMs<=5000);
  need(Number.isSafeInteger(maxSessions)&&maxSessions>=1&&maxSessions<=256);
  const entries=new Map();let disposed=false,lastClock=-1;
  const now=()=>{const n=clock();need(Number.isFinite(n)&&n>=0&&n>=lastClock);lastClock=n;return n;};
  const key=p=>C.canonical(p);
  const sameBase=(a,b)=>C.sameContext({...a,streamId:null},{...b,streamId:null});
  const matches=(e,r)=>e.pending&&C.canonical(e.pending.request)===C.canonical(r);
  function account(e){
    if(e.started!==null){try{e.elapsed+=Math.max(0,Math.min(now(),e.deadline)-e.started);}catch{}
      e.started=null;}
  }
  function release(e){
    e.deliver=false;account(e);clearTimeout(e.refresh);e.refresh=null;
    e.meter?.clear();
    if(e.stream){const result=e.stream.close();e.released=e.released&&result.released;}
    return e.released;
  }
  function end(e){release(e);e.abort?.abort();}
  const permitted=e=>{
    try{return !disposed&&!e.abort.signal.aborted&&e.grant.hostAuthorized&&
      e.grant.listeningAuthorized&&now()<e.deadline;}catch{return false;}
  };
  async function grant(p,ctx,signal,action='start'){
    const started=now(),abort=new AbortController();let timer,listener;
    try{
      const cancelled=new Promise((_,reject)=>{
        listener=()=>{abort.abort();reject(new WorkspaceBoundaryFailure('CANCELLED'));};
        if(signal.aborted)listener();else signal.addEventListener('abort',listener,{once:true});
      });
      const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>{
        abort.abort();reject(new WorkspaceBoundaryFailure('TIMEOUT'));
      },grantTimeoutMs);});
      const raw=await Promise.race([cancelled,timeout,Promise.resolve().then(()=>{
        need(!abort.signal.aborted,'CANCELLED');return resolveGrant({principal:p,context:ctx,signal:abort.signal,action});
      })]);
      C.checkSize(raw,16384,'control');
      C.object(raw,['context','bindingRevision','authorityRevision','viewerAuthorized','hostAuthorized',
        'listeningAuthorized','validForMs','serverUrls','signature']);
      const g=C.freeze(C.clone(raw));C.context(g.context);C.uint(g.bindingRevision);C.uint(g.authorityRevision);
      C.bool(g.viewerAuthorized);C.bool(g.hostAuthorized);C.bool(g.listeningAuthorized);C.uint(g.validForMs);
      need(g.validForMs<=60000&&g.bindingRevision>0&&g.viewerAuthorized,'DENIED');
      need(g.bindingRevision===g.context.generation,'BINDING_MISMATCH');
      need(sameBase(g.context,ctx)&&(ctx.streamId===null||g.context.streamId===ctx.streamId),'BINDING_MISMATCH');
      need(g.serverUrls===null||typeof g.serverUrls==='string');need(g.signature===null||typeof g.signature==='string');
      need(!signal.aborted,'CANCELLED');
      return {value:g,deadline:started+Math.min(g.validForMs,5000)};
    }finally{clearTimeout(timer);if(listener)signal.removeEventListener('abort',listener);}
  }
  function schedule(e){
    clearTimeout(e.refresh);
    const stream=e.stream,abort=e.abort;
    const current=()=>e.stream===stream&&e.abort===abort&&stream.status().phase==='connected';
    e.refresh=setTimeout(async()=>{
      try{
        if(!current())return;
        if(!permitted(e))return end(e);
        const next=await grant(e.principal,e.context,abort.signal),g=next.value;
        if(!current())return;
        need(permitted(e)&&g.hostAuthorized&&g.listeningAuthorized&&now()<next.deadline,'DENIED');
        need(g.bindingRevision===e.grant.bindingRevision&&g.authorityRevision===e.grant.authorityRevision&&
          C.sameContext(g.context,e.context)&&g.serverUrls===e.grant.serverUrls&&g.signature===e.grant.signature,'CONFLICT');
        e.grant=g;e.deadline=next.deadline;
        need(e.stream.renew(Math.max(1,Math.floor(e.deadline-now()))),'DENIED');schedule(e);
      }catch{if(current())end(e);}
    },Math.max(1,Math.min(1000,Math.floor((e.deadline-now())/2))));
  }
  async function request({principal,request:raw,snapshot:rawSnapshot,cancellation}){
    const p=C.freeze(storageContract.identity(principal)),r=C.control(raw,'request'),s=C.snapshot(rawSnapshot),k=key(p);
    let e,token,unsubscribe,changed=false;
    const fail=code=>A.failure(r,code,changed?'unknown':'notRequested');
    try{
      need(!disposed,'UNAVAILABLE');need(!A.cancelled(cancellation),'CANCELLED');
      need(r.action!=='refresh'&&C.sameContext(r.expectedContext,s.context)&&r.expectedSnapshotRevision===s.revision,'CONFLICT');
      need(['tenantId','userId','agentId'].every(x=>p[x]===s.context[x]),'BINDING_MISMATCH');
      need(s.revision<Number.MAX_SAFE_INTEGER&&s.state!=='stopped','CONFLICT');
      need(r.action!=='start'||['ready','paused'].includes(s.state),'CONFLICT');
      need(r.action!=='pause'||s.state==='listening','CONFLICT');
      e=entries.get(k);
      // The locked store may have closed an abandoned generation. Retire its
      // local handle before accepting the newly bound, explicitly started one.
      if(e && s.context.generation>e.context.generation && s.state==='ready' && s.context.streamId===null){
        end(e);need(e.released,'UNAVAILABLE');entries.delete(k);e=null;
      }
      if(!e){
        // After a process restart, a listening/paused snapshot is not proof that
        // this process owns the native handle. Trusted recovery is required.
        if(s.state!=='ready'||s.context.streamId!==null)return A.failure(r,'UNAVAILABLE','unknown');
        need(entries.size<maxSessions,'UNAVAILABLE');
        e={principal:p,context:s.context,snapshot:s,pending:null,stream:null,released:true,
          deliver:false,started:null,elapsed:s.activeSeconds*1000,deadline:0,refresh:null,
          meter:createAudioLevelMeter({clock:now})};
        need(Number.isSafeInteger(e.elapsed));entries.set(k,e);
      }
      need(!e.pending&&C.canonical(e.snapshot)===C.canonical(s),'CONFLICT');
      need(e.released,'UNAVAILABLE');
      token={request:r,reply:null};e.pending=token;
      changed=r.action!=='start'&&!!e.stream;e.abort?.abort();e.abort=new AbortController();
      unsubscribe=cancellation.subscribe(()=>{changed=changed||!!e.stream;end(e);});
      need(typeof unsubscribe==='function');need(!A.cancelled(cancellation),'CANCELLED');
      // Pause/Stop stop local delivery immediately, before a permission lookup.
      if(r.action!=='start'){changed=!!e.stream;need(release(e),'UNAVAILABLE');}
      const resolved=await grant(p,s.context,e.abort.signal,r.action),g=resolved.value;
      need(e.pending===token&&!e.abort.signal.aborted,'CANCELLED');
      if(e.grant)need(g.bindingRevision===e.grant.bindingRevision,'BINDING_MISMATCH');
      if(r.action==='start'){
        need(g.context.streamId!==null&&g.hostAuthorized&&g.listeningAuthorized&&now()<resolved.deadline,'DENIED');
        e.context=g.context;e.grant=g;e.deadline=resolved.deadline;e.deliver=false;
        e.stream=createK135zRtmsStream({sdk,context:e.context,serverUrls:g.serverUrls,signature:g.signature,
          leaseMs:Math.max(1,Math.floor(e.deadline-now())),authorize:()=>permitted(e),
          onTranscript:packet=>e.deliver?onTranscript(packet):true,
          ...(audioLevels?{onAudioLevel:level=>{
            if(e.deliver&&!e.pending&&permitted(e))e.meter.accept(level);
          }}:{}),
          onClosed:result=>{e.deliver=false;account(e);clearTimeout(e.refresh);e.released=e.released&&result.released;}});
        changed=true;await e.stream.connect({signal:e.abort.signal});
        need(e.pending===token&&permitted(e)&&e.stream.status().phase==='connected','DENIED');schedule(e);
      }
      need(!A.cancelled(cancellation)&&e.pending===token,'CANCELLED');
      const snapshot=C.snapshot({...s,context:r.action==='start'?e.context:s.context,revision:s.revision+1,
        state:{start:'listening',pause:'paused',stop:'stopped'}[r.action],
        activeSeconds:Math.max(s.activeSeconds,Math.floor(e.elapsed/1000)),
        hostAuthorized:g.hostAuthorized,listeningAuthorized:g.listeningAuthorized});
      token.reply=C.control({schemaVersion:1,operation:r.operation,action:r.action,
        outcome:{kind:'acknowledged',snapshot}},'reply');return token.reply;
    }catch(error){
      if(e&&token&&e.pending===token)end(e);
      return fail(error instanceof WorkspaceBoundaryFailure?error.code:'UNAVAILABLE');
    }finally{if(typeof unsubscribe==='function')try{unsubscribe();}catch{}}
  }
  // Called synchronously by the atomic adapter after durable completion, or on
  // every failure after dispatch. Until this point transcripts are discarded.
  function settle({principal,request:raw,reply:rawReply}){
    const r=C.control(raw,'request'),reply=C.control(rawReply,'reply');
    const k=key(storageContract.identity(principal)),e=entries.get(k);
    if(!e||!matches(e,r))return reply.outcome.kind==='failed';
    try{
      if(reply.outcome.kind!=='acknowledged'){end(e);e.pending=null;return true;}
      need(e.pending.reply&&C.canonical(reply)===C.canonical(e.pending.reply));
      if(r.action==='start'){
        need(permitted(e)&&e.stream.status().phase==='connected','DENIED');
        e.started=now();e.deliver=true;
      }else need(e.released,'UNAVAILABLE');
      e.snapshot=reply.outcome.snapshot;e.context=e.snapshot.context;e.pending=null;
      if(r.action==='stop'){end(e);entries.delete(k);}return true;
    }catch{end(e);e.pending=null;return false;}
  }
  function captureActive({principal,context}) {
    try {
      const e=entries.get(key(storageContract.identity(principal)));
      C.context(context);
      return !!(e && e.deliver && !e.pending && C.sameContext(e.context,context) &&
        permitted(e) && e.stream?.status().phase==='connected');
    } catch {return false;}
  }
  function audioLevel({principal,context}) {
    const active=captureActive({principal,context});
    const e=entries.get(key(storageContract.identity(principal)));
    return {schemaVersion:1,context,active,available:audioLevels,
      ...(active&&e?e.meter.snapshot(true):{received:false,packets:0,ageMs:null,level:0,peak:0})};
  }
  return Object.freeze({request,settle,captureActive,audioLevel,close(){disposed=true;for(const e of entries.values())end(e);
    return [...entries.values()].every(e=>e.released);}});
}
// K135Z_GATE6J_RTMS_TRANSPORT_END

// Server-only bridge. Webhook ownership and database permission are independent.
// Reading a lease never issues or renews consent. Pause/Stop require no Zoom lookup.
function createK135zRtmsGrantResolver({store,repository,clientId,clientSecret,timeoutMs=1500}={}) {
  const C=workspaceContract,S=storageContract;
  const need=(ok,code='DENIED')=>{if(!ok)throw new WorkspaceBoundaryFailure(code);};
  need(typeof store?.readCaptureLease==='function' && typeof repository?.getCaptureSource==='function','UNAVAILABLE');
  S.text(clientId,256);S.text(clientSecret,1024);need(!clientId.includes(','),'PROTOCOL_ERROR');
  need(Number.isSafeInteger(timeoutMs)&&timeoutMs>=1&&timeoutMs<=5000,'PROTOCOL_ERROR');
  return async function resolveGrant({principal,context,signal,action='start'}) {
    const p=C.freeze(S.identity(principal)),ctx=C.context(context),abort=new AbortController();let timer,listener;
    C.oneOf(action,['start','pause','stop']);
    need(['tenantId','userId','agentId'].every(k=>p[k]===ctx[k]),'BINDING_MISMATCH');
    need(signal && typeof signal.addEventListener==='function' && typeof signal.removeEventListener==='function','PROTOCOL_ERROR');
    const check=()=>need(!abort.signal.aborted,'CANCELLED');
    try {
      const cancelled=new Promise((_,reject)=>{listener=()=>{abort.abort();reject(new WorkspaceBoundaryFailure('CANCELLED'));};
        if(signal.aborted)listener();else signal.addEventListener('abort',listener,{once:true});});
      const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>{abort.abort();reject(new WorkspaceBoundaryFailure('TIMEOUT'));},timeoutMs);});
      const work=async()=>{
        check();const first=await store.readCaptureLease({principal:p,context:ctx,signal:abort.signal});check();
        const make=(lease,bound,urls=null,signature=null)=>C.freeze({context:bound,bindingRevision:lease.bindingRevision,
          authorityRevision:lease.authorityRevision,viewerAuthorized:lease.authority.viewerAuthorized,
          hostAuthorized:lease.authority.hostAuthorized,listeningAuthorized:lease.authority.listeningAuthorized,
          validForMs:Math.min(first.validForMs,lease.validForMs,5000),serverUrls:urls,signature});
        if(action!=='start')return make(first,ctx);
        need(first.authority.viewerAuthorized && first.authority.hostAuthorized && first.authority.listeningAuthorized && first.validForMs>0);
        need(!first.record.uncertain && first.record.snapshot.state!=='stopped','CONFLICT');
        const source=await repository.getCaptureSource({key:S.identityKey(p),meetingUuid:ctx.meetingUuid,streamId:ctx.streamId},{signal:abort.signal});check();
        need(source!==null);const v=S.captureSource(source);
        need(v.meetingUuid===ctx.meetingUuid && (ctx.streamId===null||v.streamId===ctx.streamId),'BINDING_MISMATCH');
        const last=await store.readCaptureLease({principal:p,context:ctx,signal:abort.signal});check();
        need(first.bindingRevision===last.bindingRevision && first.authorityRevision===last.authorityRevision &&
          C.canonical(first.record)===C.canonical(last.record),'CONFLICT');
        need(last.authority.viewerAuthorized && last.authority.hostAuthorized && last.authority.listeningAuthorized && last.validForMs>0);
        const bound=C.context({...ctx,streamId:v.streamId});
        const signature=require('node:crypto').createHmac('sha256',clientSecret).update([clientId,bound.meetingUuid,bound.streamId].join(',')).digest('hex');
        return make(last,bound,v.serverUrls,signature);
      };
      return await Promise.race([cancelled,timeout,Promise.resolve().then(work)]);
    }catch(error){if(error instanceof WorkspaceBoundaryFailure)throw error;throw new WorkspaceBoundaryFailure('UNAVAILABLE');}
    finally{clearTimeout(timer);if(listener)signal.removeEventListener('abort',listener);}
  };
}

module.exports = {
  createK135zRtmsGrantResolver,
  createK135zRtmsCommandTransport,
  createK135zRtmsStream,
  K135zSupabaseWorkspaceStore,
  K135zAtomicWorkspaceAdapter,
  K135zWorkspaceCommandService,
  ZoomRtmsSessionManager,
  eventObject,
  stableSessionKey,
};
