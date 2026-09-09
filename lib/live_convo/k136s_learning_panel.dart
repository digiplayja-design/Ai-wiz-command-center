// K136S-F2 — Nova Secure Spoken Learning: client-side controller + panel.
//
// Drives the K136S flow from the real live-convo events:
//   idle → (trigger phrase in USER speech) → triggered → mic muted → authRequired (typed-only vault
//   field) → grant → mic unmuted → capturing (user speech accumulates until an end phrase or the
//   Done button) → classifying (POST /k136s/preview) → previewReady (diff + classification + policy)
//   → confirmationRequired (POST /k136s/approve/request) → committing (POST /k136s/approve/confirm)
//   → verified | rejected | expired | cancelled.
//
// Invariants mirrored from K136S-B: the vault password is typed, never spoken, never logged, never
// retained; elevated changes accept a TYPED confirmation only; a stale grant (60 s) re-prompts the
// vault before an elevated confirm; every timeout and cancel unmutes the mic; nothing here talks to
// the realtime session except through the injected mute and context-refresh callbacks.
//
// Uses only packages the screen already imports (material, http). No new dependencies.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum K136sLearningState {
  idle,
  triggered,
  authRequired,
  authenticated,
  capturing,
  classifying,
  previewReady,
  confirmationRequired,
  committing,
  verified,
  cancelled,
  expired,
  rejected,
}

const Set<K136sLearningState> _terminal = <K136sLearningState>{
  K136sLearningState.verified,
  K136sLearningState.cancelled,
  K136sLearningState.expired,
  K136sLearningState.rejected,
};

enum _PendingAfterAuth { none, preview, approveRequest, confirmTyped }

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------

class K136sApiResult {
  const K136sApiResult(this.status, this.json);
  final int status;
  final Map<String, dynamic> json;
  bool get ok => status >= 200 && status < 300;
  String? get code => json['code']?.toString();
  String? get error => json['error']?.toString();
}

abstract class K136sLearningApiBase {
  Future<K136sApiResult> grant({required String agentId, required String vaultPassword});
  Future<K136sApiResult> preview({required String agentId, required String proposedText, required String grant});
  Future<K136sApiResult> approveRequest({
    required String sessionId,
    required String agentId,
    required String contentHash,
    required bool elevated,
    required String grant,
  });
  Future<K136sApiResult> approveConfirm({
    required String sessionId,
    required String agentId,
    required String contentHash,
    required String approvalToken,
    required String channel,
    required Map<String, dynamic> preview,
    required String grant,
  });
  void close() {}
}

/// Thin HTTP client for the K136S routes mounted on the backend. Relays the screen's auth headers
/// (via `headersBuilder`) so the backend authenticates the caller; adds `x-k136s-grant` when set.
class K136sLearningApi extends K136sLearningApiBase {
  K136sLearningApi({
    required this.baseUrl,
    required this.headersBuilder,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final Map<String, dynamic> Function() headersBuilder;
  final Duration timeout;
  final http.Client _client;

  Uri _uri(String path) {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  Map<String, String> _headers({String? grant}) {
    final out = <String, String>{
      'content-type': 'application/json',
      'accept': 'application/json',
    };
    try {
      headersBuilder().forEach((String k, dynamic v) {
        if (v != null) out[k] = v.toString();
      });
    } catch (_) {
      // a failing headers builder just means no auth header; the backend will answer 401
    }
    if (grant != null && grant.isNotEmpty) out['x-k136s-grant'] = grant;
    return out;
  }

  Future<K136sApiResult> _post(String path, Map<String, dynamic> body, {String? grant}) async {
    try {
      final res = await _client
          .post(_uri(path), headers: _headers(grant: grant), body: jsonEncode(body))
          .timeout(timeout);
      Map<String, dynamic> parsed = <String, dynamic>{};
      if (res.body.isNotEmpty) {
        try {
          final dynamic d = jsonDecode(res.body);
          if (d is Map<String, dynamic>) parsed = d;
        } catch (_) {}
      }
      return K136sApiResult(res.statusCode, parsed);
    } on TimeoutException {
      return const K136sApiResult(0, <String, dynamic>{'error': 'timeout', 'code': 'TIMEOUT'});
    } catch (_) {
      return const K136sApiResult(0, <String, dynamic>{'error': 'network error', 'code': 'NETWORK'});
    }
  }

  @override
  Future<K136sApiResult> grant({required String agentId, required String vaultPassword}) =>
      _post('/k136s/grant', <String, dynamic>{'agentId': agentId, 'vaultPassword': vaultPassword});

  @override
  Future<K136sApiResult> preview({required String agentId, required String proposedText, required String grant}) =>
      _post('/k136s/preview', <String, dynamic>{'agentId': agentId, 'proposedText': proposedText}, grant: grant);

  @override
  Future<K136sApiResult> approveRequest({
    required String sessionId,
    required String agentId,
    required String contentHash,
    required bool elevated,
    required String grant,
  }) =>
      _post(
        '/k136s/approve/request',
        <String, dynamic>{'sessionId': sessionId, 'agentId': agentId, 'contentHash': contentHash, 'elevated': elevated},
        grant: grant,
      );

  @override
  Future<K136sApiResult> approveConfirm({
    required String sessionId,
    required String agentId,
    required String contentHash,
    required String approvalToken,
    required String channel,
    required Map<String, dynamic> preview,
    required String grant,
  }) =>
      _post(
        '/k136s/approve/confirm',
        <String, dynamic>{
          'sessionId': sessionId,
          'agentId': agentId,
          'contentHash': contentHash,
          'approvalToken': approvalToken,
          'channel': channel,
          'preview': preview,
        },
        grant: grant,
      );

  @override
  void close() => _client.close();
}

// ---------------------------------------------------------------------------
// Preview model
// ---------------------------------------------------------------------------

class K136sPreview {
  const K136sPreview({
    required this.normalizedText,
    required this.type,
    required this.category,
    required this.sensitivity,
    required this.expiresAt,
    required this.allowed,
    required this.elevated,
    required this.requiresQueue,
    required this.allowedChannels,
    required this.violations,
    required this.diffOps,
    required this.contentHash,
  });

  final String normalizedText;
  final String type;
  final String? category;
  final String sensitivity;
  final String? expiresAt;
  final bool allowed;
  final bool elevated;
  final bool requiresQueue;
  final List<String> allowedChannels;
  final List<String> violations;
  final List<Map<String, dynamic>> diffOps;
  final String contentHash;

  static K136sPreview? fromJson(Map<String, dynamic> j) {
    final text = j['normalizedText'];
    final hash = j['contentHash'];
    if (text is! String || hash is! String) return null;
    final cls = (j['classification'] is Map) ? Map<String, dynamic>.from(j['classification'] as Map) : <String, dynamic>{};
    final pol = (j['policy'] is Map) ? Map<String, dynamic>.from(j['policy'] as Map) : <String, dynamic>{};
    final diff = (j['diff'] is Map) ? Map<String, dynamic>.from(j['diff'] as Map) : <String, dynamic>{};
    final ops = <Map<String, dynamic>>[];
    if (diff['ops'] is List) {
      for (final dynamic o in diff['ops'] as List) {
        if (o is Map) ops.add(Map<String, dynamic>.from(o));
      }
    }
    final violations = <String>[];
    if (pol['violations'] is List) {
      for (final dynamic v in pol['violations'] as List) {
        if (v is Map && v['code'] != null) violations.add(v['code'].toString());
      }
    }
    final channels = <String>[];
    if (pol['allowedChannels'] is List) {
      for (final dynamic c in pol['allowedChannels'] as List) {
        channels.add(c.toString());
      }
    }
    return K136sPreview(
      normalizedText: text,
      type: (cls['type'] ?? 'MEMORY').toString(),
      category: cls['category']?.toString(),
      sensitivity: (cls['sensitivity'] ?? 'low').toString(),
      expiresAt: cls['expiresAt']?.toString(),
      allowed: pol['allowed'] == true,
      elevated: pol['elevated'] == true,
      requiresQueue: pol['requiresQueue'] == true,
      allowedChannels: channels,
      violations: violations,
      diffOps: ops,
      contentHash: hash,
    );
  }

  Map<String, dynamic> toConfirmPayload() => <String, dynamic>{
        'normalizedText': normalizedText,
        'type': type,
        'category': category,
        'sensitivity': sensitivity,
        'expiresAt': expiresAt,
      };
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

// K136S-F5: explicit microphone and refresh receipts; no success-by-returning-void.
class K136sRefreshReceipt {
  const K136sRefreshReceipt({required this.agentId, required this.liveSessionId,
    required this.contextRestored});
  final String agentId;
  final String liveSessionId;
  final bool contextRestored;
}

class K136sMicTrack {
  K136sMicTrack({required this.readEnabled, required this.writeEnabled,
    required this.nativeMute});
  final bool Function() readEnabled;
  final void Function(bool) writeEnabled;
  final Future<void> Function(bool) nativeMute;
}

/// Holds the exact stream/track lease. A late completion never unmutes a new stream.
class K136sMicrophoneGuard {
  K136sMicrophoneGuard({required this.identity, required this.tracks});
  final Object? Function() identity;
  final List<K136sMicTrack> Function() tracks;
  Object? _owner;
  List<K136sMicTrack> _held = <K136sMicTrack>[];
  List<bool> _before = <bool>[];
  bool get engaged => _owner != null;
  Future<bool> setMuted(bool muted) async {
    if (muted) {
      final owner = identity();
      if (owner == null) return false;
      if (_owner != null) {
        return identical(_owner, owner) && _held.isNotEmpty &&
          _held.every((t) => !t.readEnabled());
      }
      final held = tracks();
      if (held.isEmpty) return false;
      _owner = owner;
      _held = held;
      _before = held.map((t) => t.readEnabled()).toList();
      try {
        for (final t in held) { t.writeEnabled(false); }
        for (final t in held) { await t.nativeMute(true); }
        return identical(identity(), owner) && held.every((t) => !t.readEnabled());
      } catch (_) { return false; }
    }
    final owner = _owner;
    if (owner == null) return true;
    final held = _held;
    final before = _before;
    try {
      if (identical(identity(), owner)) {
        for (var i = 0; i < held.length; i++) {
          await held[i].nativeMute(!before[i]);
          if (!identical(identity(), owner)) break;
          held[i].writeEnabled(before[i]);
        }
        if (identical(identity(), owner)) {
          for (var i = 0; i < held.length; i++) {
            if (held[i].readEnabled() != before[i]) return false;
          }
        }
      }
      _owner = null; _held = <K136sMicTrack>[]; _before = <bool>[];
      return true;
    } catch (_) { return false; }
  }
}

class K136sLearningController extends ChangeNotifier {
  K136sLearningController({required this.api, required this._agentId,
    required this._setMuted, required this._refreshContext,
    this._liveSessionId = '', this._ready = false, this._principalScope = '',
    List<String>? triggerPhrases, List<String>? endPhrases, DateTime Function()? now})
    : _now = now ?? DateTime.now,
      triggerPhrases = triggerPhrases ?? const <String>['nova learn this','nova remember this','nova learning mode'],
      endPhrases = endPhrases ?? const <String>['thats all','that is all','end learning','nova done','nova thats it'];
  static const Duration authTimeout = Duration(minutes:2);
  static const Duration captureTimeout = Duration(minutes:3);
  static const Duration previewTimeout = Duration(minutes:10);
  static const Duration confirmationTimeout = Duration(seconds:120);
  static const Duration sessionTimeout = Duration(minutes:10);
  static const Duration grantFreshness = Duration(seconds:60);
  static const Duration grantSafety = Duration(seconds:5);
  static const int maxCaptureChars = 4000;
  final K136sLearningApiBase api;
  String _agentId, _liveSessionId, _principalScope;
  bool _ready;
  String get agentId => _agentId;
  String get liveSessionId => _liveSessionId;
  final List<String> triggerPhrases, endPhrases;
  final Future<bool> Function(bool) _setMuted;
  final Future<K136sRefreshReceipt?> Function() _refreshContext;
  final DateTime Function() _now;
  K136sLearningState _state = K136sLearningState.idle;
  String? sessionId, _grant, _approvalToken, lastError, lastCode, memoryKey, memoryId;
  DateTime? _grantAt, _approvalExpiresAt, _sessionStartedAt, _stateEnteredAt;
  int? passwordVersion;
  final StringBuffer _capture = StringBuffer();
  K136sPreview? preview;
  _PendingAfterAuth _pending = _PendingAfterAuth.none;
  bool busy = false, micMuted = false, contextRefreshed = false, _disposed = false;
  int _epoch = 0, _micJobs = 0;
  Future<void> _micTail = Future<void>.value();
  K136sLearningState get state => _state;
  bool get isTerminal => _terminal.contains(_state);
  bool get isActive => _state != K136sLearningState.idle && !isTerminal;
  bool get isVisible => _state != K136sLearningState.idle;
  bool get micBusy => _micJobs != 0;
  String get capturedText => _capture.toString().trim();
  bool get hasGrant => _grant != null && _grant!.isNotEmpty;
  bool get grantIsFresh => _grantAt != null && _now().difference(_grantAt!) < (grantFreshness-grantSafety);
  bool get pendingReauth => _pending != _PendingAfterAuth.none;
  bool get voiceConfirmAllowed => preview != null && !preview!.elevated && preview!.allowedChannels.contains('voice');
  bool _valid(int e) => !_disposed && _epoch == e;
  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r"[^\w\s']"),' ')
    .replaceAll("'",'').replaceAll(RegExp(r'\s+'),' ').trim();
  static String? _matchPhrase(String text,List<String> phrases) {
    final n = _norm(text);
    for (final p in phrases) { final np=_norm(p); if(np.isNotEmpty && n.contains(np)) return np; }
    return null;
  }
  bool recognizesTrigger(String text) => _matchPhrase(text,triggerPhrases) != null;
  void _notify() { if(!_disposed) notifyListeners(); }
  void _enter(K136sLearningState next) {
    _state=next; _stateEnteredAt=_now(); lastError=null; lastCode=null; _notify();
  }
  void _fail(String message,{String? code}) { lastError=message;lastCode=code;_notify(); }
  void setError(String message,{String? code}) => _fail(message,code:code);
  void _clearSecrets() { _grant=null;_grantAt=null;_approvalToken=null;_approvalExpiresAt=null;passwordVersion=null; }
  void bindContext({required String agentId,required String liveSessionId,required bool ready,required String principalScope}) {
    if(_disposed || (_agentId==agentId && _liveSessionId==liveSessionId && _ready==ready && _principalScope==principalScope)) return;
    invalidate();
    _agentId=agentId;_liveSessionId=liveSessionId;_ready=ready;_principalScope=principalScope;
  }
  void invalidate() {
    if(_disposed) return;
    final unknown=_state==K136sLearningState.committing;
    final visible=isVisible;
    _epoch++;busy=false;_clearSecrets();_pending=_PendingAfterAuth.none;
    _capture.clear();preview=null;sessionId=null;memoryKey=null;memoryId=null;contextRefreshed=false;
    _enter(visible ? K136sLearningState.cancelled : K136sLearningState.idle);
    if (visible) {
      _fail(unknown ? 'The session changed while saving. The result is unconfirmed; check Agent Hub before retrying.' :
        'Learning cancelled because the agent, sign-in, or live session changed.',code:unknown?'WRITE_OUTCOME_UNKNOWN':'CONTEXT_CHANGED');
    }
    unawaited(_mute(false));
  }
  Future<bool> _mute(bool muted) {
    final e=_epoch;_micJobs++;
    final operation=_micTail.then((_) async {
      if(muted && !_valid(e)) return false;
      bool ok;
      try { ok=await _setMuted(muted); } catch(_) { ok=false; }
      if(_valid(e) && ok) micMuted=muted;
      return ok && _valid(e);
    });
    _micTail=operation.then<void>((_) {},onError:(Object _,StackTrace _) {});
    return operation.whenComplete(() { _micJobs--;_notify(); });
  }
  Future<K136sApiResult?> _request(Future<K136sApiResult> Function() action) async {
    final e=_epoch;busy=true;_notify();
    K136sApiResult result;
    try { result=await action(); }
    catch(_) { result=const K136sApiResult(0,<String,dynamic>{'code':'NETWORK'}); }
    if(!_valid(e)) return null;
    busy=false;
    return result;
  }
  Future<void> _protectVault(_PendingAfterAuth pending,{bool reauth=false}) async {
    final e=_epoch;
    _pending=pending;_grant=null;_grantAt=null;busy=true;
    _enter(K136sLearningState.triggered);
    final protected=await _mute(true);
    if(!_valid(e)) return;
    busy=false;
    if(!protected) {
      _clearSecrets();_enter(K136sLearningState.rejected);
      _fail('Microphone protection could not be confirmed. No password field was opened.',code:'MIC_PROTECTION_FAILED');
      await _mute(false);return;
    }
    _enter(K136sLearningState.authRequired);
    if(reauth) _fail('Re-enter the BRAIN VAULT password to continue this exact change.',code:'REAUTH_REQUIRED');
  }
  void onUserTranscript(String text) {
    if(_disposed || busy || micBusy || !_ready || _liveSessionId.isEmpty || _agentId.isEmpty) return;
    final t=text.trim();if(t.isEmpty) return;
    switch(_state) {
      case K136sLearningState.idle:
        if(recognizesTrigger(t)) {
          _epoch++;
          final r=Random.secure();
          sessionId='k136s-${_now().millisecondsSinceEpoch}-${List<int>.generate(12,(_)=>r.nextInt(36)).map((v)=>v.toRadixString(36)).join()}';
          _sessionStartedAt=_now();_capture.clear();preview=null;memoryKey=null;memoryId=null;contextRefreshed=false;_clearSecrets();
          _enter(K136sLearningState.triggered);
          unawaited(_protectVault(_PendingAfterAuth.none));
        }
        return;
      case K136sLearningState.capturing:
        final end=_matchPhrase(t,endPhrases);var piece=t;
        if(end!=null) {
          final words=t.split(RegExp(r'\s+'));var cut=words.length;
          for(var i=0;i<words.length;i++) { if(_norm(words.sublist(i).join(' ')).startsWith(end)) {cut=i;break;} }
          piece=words.sublist(0,cut).join(' ');
        }
        if(piece.trim().isNotEmpty) {
          if(_capture.length+piece.length+1>maxCaptureChars) {
            _fail('Capture limit reached ($maxCaptureChars characters).',code:'CAPTURE_LIMIT');
          } else { if(_capture.isNotEmpty) _capture.write(' ');_capture.write(piece.trim());_notify(); }
        }
        if(end!=null) unawaited(endCapture());return;
      case K136sLearningState.confirmationRequired:
        final n=_norm(t);
        if(n=='cancel'||n=='nova cancel') { unawaited(cancel()); }
        else if(n=='confirm'||n=='nova confirm'||n=='yes confirm') { unawaited(confirm(channel:'voice')); }
        return;
      default:return;
    }
  }
  Future<void> submitVaultPassword(String password) async {
    if(_disposed||busy||micBusy||!micMuted||_state!=K136sLearningState.authRequired) return;
    if(password.isEmpty) {_fail('Enter the BRAIN VAULT password.',code:'PASSWORD_REQUIRED');return;}
    final e=_epoch;
    final r=await _request(()=>api.grant(agentId:agentId,vaultPassword:password));
    if(r==null) return;
    if(r.ok && r.json['grant'] is String && (r.json['grant'] as String).isNotEmpty) {
      _grant=r.json['grant'] as String;_grantAt=_now();
      final pv=r.json['passwordVersion'];passwordVersion=pv is int?pv:int.tryParse('$pv');
      _enter(K136sLearningState.authenticated);busy=true;
      final released=await _mute(false);if(!_valid(e)) return;busy=false;
      if(!released) {_clearSecrets();_enter(K136sLearningState.rejected);_fail('Microphone release failed. Learning stopped.',code:'MIC_RELEASE_FAILED');return;}
      final pending=_pending;_pending=_PendingAfterAuth.none;
      switch(pending) {
        case _PendingAfterAuth.preview:await _runPreview();return;
        case _PendingAfterAuth.approveRequest:_enter(K136sLearningState.previewReady);await requestConfirmation();return;
        case _PendingAfterAuth.confirmTyped:_enter(K136sLearningState.confirmationRequired);return;
        case _PendingAfterAuth.none:_enter(K136sLearningState.capturing);return;
      }
    }
    final message=r.status==401?'The BRAIN VAULT password is incorrect.':r.status==429?'The vault is temporarily locked.':
      r.status==409?'No BRAIN VAULT password is configured.':'Vault verification failed or is unavailable.';
    _fail(message,code:r.code??'VAULT_FAILED');
  }
  Future<void> endCapture() async {
    if(_disposed||busy||_state!=K136sLearningState.capturing) return;
    if(capturedText.isEmpty) {_fail('Nothing captured yet — say what Nova should learn.',code:'EMPTY_CAPTURE');return;}
    await _runPreview();
  }
  Future<void> _runPreview() async {
    if(!hasGrant) {await _needReauth(_PendingAfterAuth.preview);return;}
    _enter(K136sLearningState.classifying);
    final r=await _request(()=>api.preview(agentId:agentId,proposedText:capturedText,grant:_grant!));
    if(r==null) return;
    if(r.status==401) {await _needReauth(_PendingAfterAuth.preview);return;}
    if(!r.ok) {_enter(K136sLearningState.capturing);_fail('Preview failed.',code:r.code??'PREVIEW_FAILED');return;}
    final p=K136sPreview.fromJson(r.json);
    if(p==null) {_enter(K136sLearningState.capturing);_fail('Preview response was not understood.',code:'PREVIEW_MALFORMED');return;}
    preview=p;
    if(!p.allowed&&!p.requiresQueue) {
      _clearSecrets();_enter(K136sLearningState.rejected);
      _fail('This change cannot be learned.',code:p.violations.isNotEmpty?p.violations.first:'POLICY_DENIED');await _mute(false);return;
    }
    _enter(K136sLearningState.previewReady);
  }
  Future<void> requestConfirmation() async {
    if(_disposed||busy||_state!=K136sLearningState.previewReady||preview==null) return;
    if(preview!.requiresQueue) {_fail('This change needs manual review.',code:'REQUIRES_QUEUE');return;}
    if(!hasGrant) {await _needReauth(_PendingAfterAuth.approveRequest);return;}
    final r=await _request(()=>api.approveRequest(sessionId:sessionId!,agentId:agentId,contentHash:preview!.contentHash,elevated:preview!.elevated,grant:_grant!));
    if(r==null) return;
    if(r.status==401&&r.code!='UNAUTHENTICATED') {await _needReauth(_PendingAfterAuth.approveRequest);return;}
    if(!r.ok||r.json['approvalToken'] is! String||(r.json['approvalToken'] as String).isEmpty) {_fail('Could not request approval.',code:r.code??'APPROVAL_REQUEST_FAILED');return;}
    _approvalToken=r.json['approvalToken'] as String;
    final exp=r.json['expiresAt'];
    _approvalExpiresAt=exp is int?DateTime.fromMillisecondsSinceEpoch(exp):_now().add(confirmationTimeout);
    _enter(K136sLearningState.confirmationRequired);
  }
  Future<void> confirm({required String channel}) async {
    if(_disposed||busy||_state!=K136sLearningState.confirmationRequired||preview==null) return;
    if(channel!='typed'&&channel!='voice') return;
    if(preview!.elevated&&channel!='typed') {_fail('This change requires typed confirmation.',code:'ELEVATED_REQUIRES_TYPED');return;}
    if(channel=='voice'&&!voiceConfirmAllowed) {_fail('Voice confirmation is not allowed.',code:'CHANNEL_REQUIRED');return;}
    if((preview!.elevated&&!grantIsFresh)||!hasGrant) {await _needReauth(_PendingAfterAuth.confirmTyped);return;}
    if(_approvalToken==null||(_approvalExpiresAt!=null&&!_now().isBefore(_approvalExpiresAt!))) {
      _approvalToken=null;_enter(K136sLearningState.previewReady);_fail('Request a new approval.',code:'APPROVAL_MISSING');return;
    }
    _enter(K136sLearningState.committing);
    final r=await _request(()=>api.approveConfirm(sessionId:sessionId!,agentId:agentId,contentHash:preview!.contentHash,
      approvalToken:_approvalToken!,channel:channel,preview:preview!.toConfirmPayload(),grant:_grant!));
    if(r==null) return;
    if(r.ok&&r.json['state']=='VERIFIED') {
      memoryKey=r.json['memoryKey']?.toString();memoryId=r.json['memoryId']?.toString();
      _clearSecrets();_enter(K136sLearningState.verified);await _mute(false);return;
    }
    if(r.status==410) {_approvalToken=null;_enter(K136sLearningState.previewReady);_fail('The approval expired — request it again.',code:r.code??'EXPIRED');return;}
    if(r.status==401&&r.code!='UNAUTHENTICATED') {await _needReauth(_PendingAfterAuth.confirmTyped);return;}
    if(r.status==403&&r.code=='ELEVATED_REQUIRES_FRESH_VAULT') {await _needReauth(_PendingAfterAuth.confirmTyped);return;}
    if((r.status==401||r.status==403)&&r.json['approvalConsumed']!=true) {
      _enter(K136sLearningState.confirmationRequired);_fail('Confirmation refused.',code:r.code??'FORBIDDEN');return;
    }
    _clearSecrets();_enter(K136sLearningState.rejected);
    final unknown=r.status==0||r.status==503||r.ok;
    _fail(unknown?'The save result is unconfirmed. Check Agent Hub before retrying.':'The change was not verified. Review the result before retrying.',
      code:unknown?'WRITE_OUTCOME_UNKNOWN':r.code??'REJECTED');
    await _mute(false);
  }
  Future<void> _needReauth(_PendingAfterAuth pending) => _protectVault(pending,reauth:true);
  Future<void> cancel() async {
    if(_disposed||isTerminal||_state==K136sLearningState.idle) return;
    final unknown=_state==K136sLearningState.committing;
    _epoch++;busy=false;_clearSecrets();_pending=_PendingAfterAuth.none;
    _capture.clear();preview=null;_enter(K136sLearningState.cancelled);
    if(unknown) _fail('Cancellation cannot undo a submitted save. Its result is unconfirmed; check Agent Hub.',code:'WRITE_OUTCOME_UNKNOWN');
    await _mute(false);
  }
  Future<void> refreshNovaContext() async {
    if(_disposed||busy||_state!=K136sLearningState.verified||contextRefreshed) return;
    final e=_epoch;final oldSession=_liveSessionId;busy=true;_notify();
    try {
      final receipt=await _refreshContext();if(!_valid(e)) return;
      if(receipt==null||receipt.agentId!=agentId||receipt.liveSessionId.isEmpty||receipt.liveSessionId==oldSession||!receipt.contextRestored) {
        _fail('Context refresh was not confirmed. The verified memory remains saved.',code:'CONTEXT_REFRESH_FAILED');return;
      }
      _liveSessionId=receipt.liveSessionId;_ready=true;contextRefreshed=true;
    } catch(_) {if(_valid(e)) _fail('Context refresh failed. The verified memory remains saved.',code:'CONTEXT_REFRESH_FAILED');}
    finally {if(_valid(e)) {busy=false;_notify();}}
  }
  void reset() {
    if(_disposed||busy||micBusy) return;
    _epoch++;_clearSecrets();_capture.clear();preview=null;sessionId=null;_pending=_PendingAfterAuth.none;
    _sessionStartedAt=null;contextRefreshed=false;memoryId=null;memoryKey=null;_enter(K136sLearningState.idle);
  }
  void tick() {
    if(_disposed||!isActive||_stateEnteredAt==null) return;
    final t=_now();final inState=t.difference(_stateEnteredAt!);
    final inSession=_sessionStartedAt==null?Duration.zero:t.difference(_sessionStartedAt!);
    Duration? limit;
    switch(_state) {
      case K136sLearningState.authRequired:case K136sLearningState.triggered:limit=authTimeout;break;
      case K136sLearningState.capturing:case K136sLearningState.authenticated:limit=captureTimeout;break;
      case K136sLearningState.previewReady:case K136sLearningState.classifying:limit=previewTimeout;break;
      case K136sLearningState.confirmationRequired:case K136sLearningState.committing:limit=confirmationTimeout;break;
      default:limit=null;
    }
    if(inSession>=sessionTimeout||(limit!=null&&inState>=limit&&_state!=K136sLearningState.confirmationRequired)) {
      final unknown=_state==K136sLearningState.committing;
      _epoch++;busy=false;_clearSecrets();_pending=_PendingAfterAuth.none;_capture.clear();preview=null;
      _enter(K136sLearningState.expired);
      if(unknown) _fail('The save timed out; its result is unconfirmed. Check Agent Hub before retrying.',code:'WRITE_OUTCOME_UNKNOWN');
      unawaited(_mute(false));return;
    }
    if(_state==K136sLearningState.confirmationRequired&&_approvalExpiresAt!=null&&!t.isBefore(_approvalExpiresAt!)) {
      _epoch++;busy=false;_approvalToken=null;_enter(K136sLearningState.previewReady);_fail('The approval expired — request it again.',code:'EXPIRED');
    }
  }
  @override
  void dispose() {
    if(_disposed) return;
    _epoch++;_clearSecrets();_capture.clear();preview=null;
    unawaited(_mute(false));_disposed=true;
    try {api.close();} catch(_) {}
    super.dispose();
  }
}

/// Learning owns a voice turn only when already active, or when a free workflow
/// explicitly enters learning. Other confirmation workflows keep their normal behavior.
bool k136sRouteVoiceTurn(K136sLearningController? c,String text,{required bool otherWorkflowPending}) {
  if(c==null) return false;
  if(c.isActive) {c.onUserTranscript(text);return true;}
  if(otherWorkflowPending||c.state!=K136sLearningState.idle||!c.recognizesTrigger(text)) return false;
  c.onUserTranscript(text);return c.isActive;
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

/// Wraps the live-convo stage; shows the learning panel only while a session is active or just ended.
class K136sLearningOverlay extends StatelessWidget {
  const K136sLearningOverlay({super.key, required this.controller, required this.child});

  final K136sLearningController? controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null) return child;
    return AnimatedBuilder(
      animation: c,
      builder: (BuildContext context, Widget? _) {
        return Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            AbsorbPointer(absorbing:c.isActive || c.busy || c.micBusy, child:child),
            if (c.isVisible)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: SafeArea(child: K136sLearningPanel(key:ValueKey(c.sessionId), controller: c)),
              ),
          ],
        );
      },
    );
  }
}

class K136sLearningPanel extends StatefulWidget {
  const K136sLearningPanel({super.key, required this.controller});
  final K136sLearningController controller;

  @override
  State<K136sLearningPanel> createState() => _K136sLearningPanelState();
}

class _K136sLearningPanelState extends State<K136sLearningPanel> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _typedConfirm = TextEditingController();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => widget.controller.tick());
    widget.controller.addListener(_clearPrivateFields);
  }

  void _clearPrivateFields() {
    if(c.state != K136sLearningState.authRequired) _password.clear();
    if(c.state != K136sLearningState.confirmationRequired) _typedConfirm.clear();
  }

  @override
  void didUpdateWidget(covariant K136sLearningPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if(!identical(oldWidget.controller,widget.controller)) {
      oldWidget.controller.removeListener(_clearPrivateFields);
      widget.controller.addListener(_clearPrivateFields);
      _password.clear();_typedConfirm.clear();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.controller.removeListener(_clearPrivateFields);
    _password.dispose();
    _typedConfirm.dispose();
    super.dispose();
  }

  K136sLearningController get c => widget.controller;

  Future<void> _submitPassword() async {
    final pw = _password.text;
    _password.clear(); // never keep it in the field after submit
    await c.submitVaultPassword(pw);
  }

  Future<void> _typedConfirmSubmit() async {
    final typed = _typedConfirm.text.trim().toUpperCase();
    _typedConfirm.clear();
    if (typed != 'CONFIRM') {
      c.setError('Type CONFIRM to approve this change.', code: 'TYPED_CONFIRM_MISMATCH');
      return;
    }
    await c.confirm(channel: 'typed');
  }

  String _title() {
    if(c.lastCode == 'WRITE_OUTCOME_UNKNOWN') return 'Save result not confirmed';
    switch (c.state) {
      case K136sLearningState.triggered:
        return 'Nova learning — muting mic…';
      case K136sLearningState.authRequired:
        return 'BRAIN VAULT — type your password';
      case K136sLearningState.authenticated:
        return 'Unlocked';
      case K136sLearningState.capturing:
        return 'Listening — say what Nova should learn';
      case K136sLearningState.classifying:
        return 'Reviewing…';
      case K136sLearningState.previewReady:
        return 'Preview — check before approving';
      case K136sLearningState.confirmationRequired:
        return c.voiceConfirmAllowed ? 'Say "confirm" or type it' : 'Elevated change — type CONFIRM';
      case K136sLearningState.committing:
        return 'Saving…';
      case K136sLearningState.verified:
        return 'Nova learned this';
      case K136sLearningState.rejected:
        return 'Not verified';
      case K136sLearningState.expired:
        return 'Timed out';
      case K136sLearningState.cancelled:
        return 'Cancelled';
      case K136sLearningState.idle:
        return '';
    }
  }

  Widget _diff(BuildContext context) {
    final p = c.preview;
    if (p == null) return const SizedBox.shrink();
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    if (p.diffOps.isEmpty) return Text(p.normalizedText, style: base);
    final spans = <TextSpan>[];
    for (final op in p.diffOps) {
      final kind = op['op']?.toString() ?? 'equal';
      final text = '${op['text'] ?? ''} ';
      if (kind == 'insert') {
        spans.add(TextSpan(text: text, style: base.copyWith(backgroundColor: Colors.green.withValues(alpha: 0.25))));
      } else if (kind == 'delete') {
        spans.add(TextSpan(
          text: text,
          style: base.copyWith(decoration: TextDecoration.lineThrough, backgroundColor: Colors.red.withValues(alpha: 0.2)),
        ));
      } else {
        spans.add(TextSpan(text: text, style: base));
      }
    }
    return RichText(text: TextSpan(children: spans));
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    switch (c.state) {
      case K136sLearningState.triggered:
      case K136sLearningState.classifying:
      case K136sLearningState.committing:
      case K136sLearningState.authenticated:
        return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
      case K136sLearningState.authRequired:
        if(!c.micMuted || c.micBusy) return const Text('Waiting for microphone protection.');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('Your microphone is muted. Type the password — do not say it out loud.'),
            const SizedBox(height: 8),
            TextField(
              key: const Key('k136s_vault_password'),
              controller: _password,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              autofocus: true,
              enabled: !c.busy,
              decoration: const InputDecoration(labelText: 'BRAIN VAULT password', border: OutlineInputBorder()),
              onSubmitted: (_) => _submitPassword(),
            ),
            const SizedBox(height: 8),
            Row(children: <Widget>[
              FilledButton(key: const Key('k136s_unlock'), onPressed: c.busy ? null : _submitPassword, child: const Text('Unlock')),
              const SizedBox(width: 8),
              TextButton(onPressed: c.cancel, child: const Text('Cancel')),
            ]),
          ],
        );
      case K136sLearningState.capturing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(c.capturedText.isEmpty ? '…' : c.capturedText, key: const Key('k136s_captured')),
            const SizedBox(height: 8),
            Row(children: <Widget>[
              FilledButton(key: const Key('k136s_done'), onPressed: c.busy ? null : c.endCapture, child: const Text('Done')),
              const SizedBox(width: 8),
              TextButton(onPressed: c.cancel, child: const Text('Cancel')),
            ]),
          ],
        );
      case K136sLearningState.previewReady:
        final p = c.preview!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Wrap(spacing: 6, children: <Widget>[
              Chip(label: Text(p.type)),
              if (p.category != null) Chip(label: Text(p.category!)),
              Chip(label: Text('sensitivity: ${p.sensitivity}')),
              if (p.elevated) const Chip(label: Text('elevated — typed confirm')),
              if (p.expiresAt != null) Chip(label: Text('until ${p.expiresAt}')),
            ]),
            const SizedBox(height: 8),
            _diff(context),
            const SizedBox(height: 8),
            Row(children: <Widget>[
              FilledButton(key: const Key('k136s_request'), onPressed: c.busy ? null : c.requestConfirmation, child: const Text('Approve…')),
              const SizedBox(width: 8),
              TextButton(onPressed: c.cancel, child: const Text('Cancel')),
            ]),
          ],
        );
      case K136sLearningState.confirmationRequired:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(c.preview?.normalizedText ?? ''),
            const SizedBox(height: 8),
            TextField(
              key: const Key('k136s_typed_confirm'),
              controller: _typedConfirm,
              autocorrect: false,
              enableSuggestions: false,
              enabled: !c.busy,
              decoration: const InputDecoration(labelText: 'Type CONFIRM', border: OutlineInputBorder()),
              onSubmitted: (_) => _typedConfirmSubmit(),
            ),
            const SizedBox(height: 8),
            Row(children: <Widget>[
              FilledButton(key: const Key('k136s_confirm_typed'), onPressed: c.busy ? null : _typedConfirmSubmit, child: const Text('Confirm')),
              const SizedBox(width: 8),
              if (c.voiceConfirmAllowed) const Text('or say "confirm"'),
              const Spacer(),
              TextButton(onPressed: c.cancel, child: const Text('Cancel')),
            ]),
          ],
        );
      case K136sLearningState.verified:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(c.preview?.normalizedText ?? '', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Row(children: <Widget>[
              if (!c.contextRefreshed)
                FilledButton(key: const Key('k136s_refresh'), onPressed: c.busy ? null : c.refreshNovaContext, child: const Text('Refresh Nova now')),
              if (c.contextRefreshed) const Text('Nova\'s context refreshed'),
              const Spacer(),
              TextButton(key: const Key('k136s_close'), onPressed: c.reset, child: const Text('Close')),
            ]),
          ],
        );
      case K136sLearningState.rejected:
      case K136sLearningState.expired:
      case K136sLearningState.cancelled:
        return Row(children: <Widget>[
          const Spacer(),
          TextButton(key: const Key('k136s_close'), onPressed: c.reset, child: const Text('Close')),
        ]);
      case K136sLearningState.idle:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const Key('k136s_panel'),
      elevation: 10,
      borderRadius: BorderRadius.circular(14),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: ConstrainedBox(
          constraints:BoxConstraints(maxHeight:(MediaQuery.sizeOf(context).height * 0.65).clamp(120.0,600.0).toDouble()),
          child:SingleChildScrollView(child:Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(children: <Widget>[
              Icon(c.micMuted ? Icons.mic_off : Icons.school_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_title(), style: theme.textTheme.titleSmall)),
              if (c.isActive)
                IconButton(tooltip: 'Cancel', icon: const Icon(Icons.close, size: 18), onPressed: c.cancel),
            ]),
            if (c.lastError != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(c.lastError!, key: const Key('k136s_error'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 8),
            _body(context),
          ],
        )),
        ),
      ),
    );
  }
}
