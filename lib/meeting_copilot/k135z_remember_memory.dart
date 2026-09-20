import 'dart:math';
import 'package:flutter/foundation.dart';
import '../live_convo/k136s_learning_panel.dart';

/// Meeting captions propose text only. Saving uses NOVA's existing vault-backed,
/// single-use approval and read-back verification API, with an owner button tap.
class K135zRememberMemory extends ChangeNotifier {
  K135zRememberMemory({required this.api, required this.agentId,
    required this.currentBinding, DateTime Function()? now}) : _now = now ?? DateTime.now;
  final K136sLearningApiBase api;
  final String agentId;
  final String? Function() currentBinding;
  final DateTime Function() _now;
  String phase = 'idle', text = '', agentName = '', message = '';
  String? _binding, _grant, _session;
  DateTime? _expires, _opened;
  K136sPreview? preview;
  bool busy = false, _dead = false, _submitted = false;
  int _epoch = 0;
  bool get visible => phase != 'idle';
  String? get requestId => _session;
  bool get active => busy || phase == 'editing' || phase == 'preview';
  bool get needsUnlock => _grant == null || _expires == null || !_now().isBefore(_expires!);
  bool _valid(int epoch) => !_dead && epoch == _epoch &&
      _binding != null && _binding == currentBinding();
  void _notify() { if (!_dead) notifyListeners(); }
  void _lock() { _grant = null; _expires = null; }

  void propose(String draft, String name) {
    if (_dead || active || currentBinding() == null || draft.length > 1600) return;
    _epoch++; _binding = currentBinding(); _opened = _now(); _lock();
    _session = 'k135z-memory-${List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    text = draft; agentName = name; preview = null; _submitted = false;
    phase = 'editing'; message = 'Review the exact fact to save to $agentName.';
    _notify();
  }

  void edit(String value) {
    if (_dead || busy || !active || value.length > 2000) return;
    text = value; preview = null; phase = 'editing';
    message = 'Review the exact fact to save to $agentName.'; _notify();
  }

  void checkContext() {
    if (_dead || !active) return;
    if (_binding != currentBinding() || (_opened != null &&
        _now().difference(_opened!) >= const Duration(minutes: 10))) cancel();
  }

  Future<K136sApiResult?> _call(int e, Future<K136sApiResult> Function() call) async {
    if (!_valid(e)) { checkContext(); return null; }
    K136sApiResult r;
    try { r = await call(); } catch (_) { r = const K136sApiResult(0, {'code':'NETWORK'}); }
    if (!_valid(e)) { checkContext(); return null; }
    return r;
  }

  Future<void> prepare(String password) async {
    if (_dead || busy || !active || !_valid(_epoch)) return;
    if (text.trim().length < 3 || text.length > 2000) {
      message = 'Enter the fact you want Nova to remember (3–2,000 characters).'; _notify(); return;
    }
    final e = _epoch; busy = true; preview = null; phase = 'editing';
    message = 'Checking your memory request…'; _notify();
    try {
      if (needsUnlock) {
        if (password.isEmpty) { message = 'Type your Brain Vault password to review this memory.'; return; }
        final start = _now();
        final r = await _call(e, () => api.grant(agentId:agentId, vaultPassword:password));
        if (r == null) return;
        if (!r.ok || r.json['grant'] is! String || (r.json['grant'] as String).isEmpty || r.json['agentId'] != agentId) {
          message = r.status == 401 ? 'Brain Vault password was not accepted.' :
            r.status == 429 ? 'Brain Vault is temporarily locked. Try again later.' :
            r.status == 409 ? 'Set your Brain Vault password in Agent Hub first.' :
            'Could not unlock Brain Vault. Nothing was saved.';
          _lock(); return;
        }
        _grant = r.json['grant'];
        // Existing grant TTL is 60 seconds. Keep a margin; the server verifies expiry.
        _expires = start.add(const Duration(seconds: 50));
      }
      final r = await _call(e, () => api.preview(agentId:agentId, proposedText:text.trim(), grant:_grant!));
      if (r == null) return;
      if (r.status == 401) { _lock(); message = 'Unlock Brain Vault again to continue.'; return; }
      K136sPreview? p;
      try { p = r.ok ? K136sPreview.fromJson(r.json) : null; } catch (_) { p = null; }
      if (p == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(p.contentHash) ||
          p.normalizedText.trim().isEmpty || p.normalizedText.length > 2000) {
        message = 'Could not prepare this memory. Nothing was saved.'; return;
      }
      if (!p.allowed || p.requiresQueue || !p.allowedChannels.contains('typed')) {
        _lock(); phase = 'rejected';
        message = 'This request needs review in Agent Hub. Nothing was saved.'; return;
      }
      preview = p; phase = 'preview';
      message = 'Check the preview, then tap Confirm save.';
    } finally { if (_valid(e)) { busy = false; _notify(); } }
  }

  Future<void> save() async {
    if (_dead || busy || phase != 'preview' || preview == null || !_valid(_epoch)) return;
    if (needsUnlock) { _lock(); phase = 'editing'; message = 'Unlock Brain Vault again, then review and confirm.'; _notify(); return; }
    final e = _epoch, p = preview!;
    busy = true; _submitted = false; message = 'Saving to $agentName’s memory…'; _notify();
    try {
      final approval = await _call(e, () => api.approveRequest(sessionId:_session!, agentId:agentId,
        contentHash:p.contentHash, elevated:p.elevated, grant:_grant!));
      if (approval == null) return;
      final token = approval.json['approvalToken'];
      if (!approval.ok || token is! String || token.isEmpty || needsUnlock) {
        if (approval.status == 401 || needsUnlock) {
          _lock(); phase = 'editing'; message = 'Unlock Brain Vault again, then review and confirm.';
        } else { message = 'Approval could not be prepared. Nothing was saved; try Confirm save again.'; }
        return;
      }
      _submitted = true;
      final result = await _call(e, () => api.approveConfirm(sessionId:_session!, agentId:agentId,
        contentHash:p.contentHash, approvalToken:token, channel:'typed',
        preview:p.toConfirmPayload(), grant:_grant!));
      if (result == null) return;
      _lock();
      if (result.ok && result.json['state'] == 'VERIFIED' && result.json['contentHash'] == p.contentHash &&
          result.json['memoryId'] is String && (result.json['memoryId'] as String).isNotEmpty &&
          result.json['memoryKey'] is String && (result.json['memoryKey'] as String).startsWith('k136s:')) {
        phase = 'saved'; message = 'Saved and verified in $agentName’s memory. Nova reloads saved memory with her next reply.';
      } else {
        phase = 'unconfirmed'; message = 'The save was not verified. Check Agent Hub before trying again.';
      }
    } finally { if (_valid(e)) { busy = false; _notify(); } }
  }

  void cancel() {
    if (_dead) return;
    final uncertain = busy && _submitted;
    _epoch++; busy = false; _lock(); preview = null; text = ''; _binding = null; _session = null;
    phase = uncertain ? 'unconfirmed' : 'idle';
    message = uncertain ? 'A save was already submitted. Check Agent Hub to see whether it completed.' : '';
    _notify();
  }

  @override
  void dispose() { cancel(); _dead = true; api.close(); super.dispose(); }
}
