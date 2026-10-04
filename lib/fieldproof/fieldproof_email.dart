import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'fieldproof_client.dart';

const fieldProofEmailModes = <String, String>{
  'off': 'Off',
  'draft': 'Review drafts',
  'automatic': 'Automatic',
};

Map<String, dynamic> fpEmailMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> fpEmailRows(Object? value) => value is List
    ? value.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
    : [];
String fpEmailText(Object? value) => value?.toString() ?? '';

bool fieldProofEmailAddressValid(String value) =>
    value.length <= 254 &&
    RegExp(r'^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$').hasMatch(value);

List<String> fieldProofSupervisorEmails(String input) => input
    .split(RegExp(r'[,;\n]'))
    .map((v) => v.trim().toLowerCase())
    .where((v) => v.isNotEmpty)
    .toSet()
    .toList();

String? validateFieldProofEmailSettings(Map<String, dynamic> value) {
  for (final key in ['customer_mode', 'followup_mode', 'supervisor_mode']) {
    if (!fieldProofEmailModes.containsKey(value[key])) {
      return 'Choose a valid email mode.';
    }
  }
  final emails = value['supervisor_emails'];
  if (emails is! List ||
      emails.length > 5 ||
      emails.any((v) => v is! String || !fieldProofEmailAddressValid(v))) {
    return 'Enter up to five valid supervisor email addresses.';
  }
  if (value['supervisor_mode'] != 'off' && emails.isEmpty) {
    return 'Add at least one supervisor email address.';
  }
  final days = value['summary_days'];
  if (days is! List ||
      days.isEmpty ||
      days.any((v) => v is! int || v < 0 || v > 6)) {
    return 'Choose at least one summary day.';
  }
  if (!RegExp(
    r'^([01]\d|2[0-3]):[0-5]\d$',
  ).hasMatch(fpEmailText(value['summary_time']))) {
    return 'Enter summary time in 24-hour format, such as 17:00.';
  }
  final timezone = fpEmailText(value['timezone']);
  if (timezone.length > 80 ||
      !(timezone == 'UTC' ||
          RegExp(r'^[A-Za-z0-9_+-]+/[A-Za-z0-9_+\-/]+$').hasMatch(timezone))) {
    return 'Enter a time zone such as America/New_York or America/Jamaica.';
  }
  final cap = value['daily_limit'], followup = value['followup_days'];
  if (cap is! int || cap < 1 || cap > 100) return 'Daily limit must be 1–100.';
  if (followup is! int || followup < 1 || followup > 30) {
    return 'Choose a follow-up delay of 1–30 days.';
  }
  if (fpEmailText(value['business_name']).length > 120) {
    return 'Business name must be 120 characters or fewer.';
  }
  return null;
}

Map<String, dynamic> fieldProofEmailDefaults() => {
  'version': 0,
  'business_name': '',
  'customer_mode': 'off',
  'followup_mode': 'off',
  'followup_days': 3,
  'supervisor_mode': 'off',
  'supervisor_emails': <String>[],
  'timezone': 'America/New_York',
  'summary_time': '17:00',
  'summary_days': <int>[1, 2, 3, 4, 5],
  'include_photos': false,
  'daily_limit': 25,
  'paused': false,
};

String fieldProofEmailStatus(String state) =>
    const {
      'pending': 'Scheduled',
      'preparing': 'Preparing report',
      'draft': 'Draft · review required',
      'ready': 'Queued to send',
      'sending': 'Sending',
      'retry': 'Waiting to retry',
      'accepted': 'Accepted by email provider',
      'failed': 'Not sent',
      'unknown': 'Sending outcome unconfirmed',
      'cancelled': 'Cancelled',
    }[state] ??
    'Status unavailable';

String fieldProofEmailIssueMessage(String code) => switch (code) {
  'daily_limit' =>
    'The daily email limit was reached. This email is waiting for the next available sending window.',
  'recipient_suppressed' || 'fieldproof_email_recipient_suppressed' =>
    'Email is stopped for this recipient because of an unsubscribe or delivery issue.',
  'recipient_changed' =>
    'The customer recipient changed, so this waiting email was cancelled.',
  'settings_changed' =>
    'The email setup changed, so this waiting email was cancelled.',
  'job_changed' || 'fieldproof_email_job_changed' =>
    'The job changed after this email was prepared. A fresh report is required.',
  'owner_cancelled' => 'You cancelled this email.',
  'expired' => 'This email expired before it could be sent.',
  'retry_window_closed' || 'fieldproof_email_retry_window_expired' =>
    'The safe retry window has closed. This email cannot be retried.',
  'send_interrupted' ||
  'fieldproof_email_receipt_uncertain' ||
  'fieldproof_email_transport_uncertain' =>
    'Sending could not be confirmed. This message will not be sent again automatically.',
  'fieldproof_email_rate_limited' =>
    'The email provider is temporarily limiting sends. A safe retry is scheduled.',
  'fieldproof_email_identity_unverified' =>
    'Verify your account email before sending.',
  'fieldproof_email_sender_changed' =>
    'Your account email changed after this message was prepared. A fresh report is required.',
  'fieldproof_email_attachment_integrity' ||
  'fieldproof_email_attachment_invalid' ||
  'fieldproof_email_attachment_unavailable' ||
  'fieldproof_email_report_invalid' =>
    'The prepared report could not be verified. Refresh to check its status.',
  'fieldproof_email_provider_rejected' =>
    'The email provider did not accept this message.',
  _ =>
    'This email needs attention. Refresh its status before taking another action.',
};

String fieldProofEmailReadinessMessage(String reason) => switch (reason) {
  'fieldproof_email_identity_unverified' =>
    'Verify your account email before enabling delivery. Replies will go to that verified address.',
  'fieldproof_email_identity_unavailable' =>
    'Account verification is temporarily unavailable. Refresh to check again.',
  'provider_key_unavailable' ||
  'sender_unavailable' ||
  'transport_unavailable' ||
  'fieldproof_email_public_url_unavailable' ||
  'fieldproof_email_provider_unavailable' =>
    'Email delivery is not available yet. Your setup can be saved; KORLIX needs to finish the email connection.',
  _ =>
    reason.contains(' ')
        ? reason
        : 'Email delivery is temporarily unavailable. Refresh to check again.',
};

String fieldProofEmailKind(String kind) =>
    const {
      'customer': 'Customer report',
      'closeout': 'Customer report',
      'customer_report': 'Customer report',
      'followup': 'Customer follow-up',
      'customer_followup': 'Customer follow-up',
      'summary': 'Supervisor summary',
      'supervisor_summary': 'Supervisor summary',
      'supervisor': 'Supervisor summary',
    }[kind] ??
    'FieldProof email';

/// A separate client keeps email route and response validation independent of
/// the evidence-job API. Identity is pinned; an in-flight response from an old
/// account can never populate the new account's screen.
class FieldProofEmailClient {
  FieldProofEmailClient({
    required this.backendBaseUrl,
    required this.headersBuilder,
    this.sessionChanges,
    http.Client? client,
  }) : _http = client ?? http.Client(),
       _ownsClient = client == null {
    _scope = _readScope(headersBuilder());
    sessionChanges?.addListener(_checkSession);
  }
  final String backendBaseUrl;
  final Map<String, String> Function() headersBuilder;
  final Listenable? sessionChanges;
  final http.Client _http;
  final bool _ownsClient;
  final Set<VoidCallback> _listeners = {};
  String? _scope;
  bool _closed = false, _changed = false;
  bool get sessionChanged => _closed || _changed;
  void addAccessDeniedListener(VoidCallback listener) =>
      _listeners.add(listener);
  void removeAccessDeniedListener(VoidCallback listener) =>
      _listeners.remove(listener);

  String? _readScope(Map<String, String> headers) {
    try {
      final bearer = headers.entries
          .firstWhere((e) => e.key.toLowerCase() == 'authorization')
          .value;
      final payload = jsonDecode(
        utf8.decode(
          base64Url.decode(
            base64Url.normalize(bearer.split(' ').last.split('.')[1]),
          ),
        ),
      );
      final values = [payload['iss'], payload['sub'], payload['session_id']];
      if (values.any((v) => v is! String || v.isEmpty)) return null;
      return jsonEncode(values);
    } catch (_) {
      return null;
    }
  }

  void _deny() {
    if (_changed || _closed) return;
    _changed = true;
    for (final listener in List<VoidCallback>.from(_listeners)) {
      listener();
    }
  }

  void _checkSession() {
    if (!_closed &&
        (_scope != null || sessionChanges != null) &&
        (_scope == null || _scope != _readScope(headersBuilder()))) {
      _deny();
    }
  }

  void _guard() {
    _checkSession();
    if (sessionChanged) {
      throw const FieldProofException(
        'Sign in again and reopen FieldProof email.',
        401,
      );
    }
  }

  Future<http.Response> _send(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    _guard();
    final request =
        http.Request(
            method,
            Uri.parse(
              '${backendBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/fieldproof/email$path',
            ),
          )
          ..headers.addAll({
            ...headersBuilder(),
            'Content-Type': 'application/json',
            'Cache-Control': 'no-store',
          });
    _guard();
    if (body != null) request.body = jsonEncode(body);
    try {
      final response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 65));
      _guard();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401) _deny();
        String? error;
        try {
          final decoded = fpEmailMap(jsonDecode(response.body));
          error =
              decoded['message']?.toString() ?? decoded['error']?.toString();
        } catch (_) {}
        throw FieldProofException(
          error ??
              'Email settings could not be updated. Refresh and try again.',
          response.statusCode,
        );
      }
      return response;
    } on TimeoutException {
      _guard();
      throw const FieldProofException(
        'This request is taking longer than expected. Refresh to check its status before trying again.',
      );
    } on http.ClientException {
      _guard();
      throw const FieldProofException(
        'Check your connection, then refresh FieldProof email.',
      );
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final response = await _send(method, path, body);
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException();
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw const FieldProofException(
        'FieldProof returned an unreadable response. Refresh before retrying.',
      );
    }
  }

  Map<String, dynamic> _state(
    Map<String, dynamic> result, {
    bool job = false,
    int? afterVersion,
  }) {
    final settings = result[job ? 'job_settings' : 'settings'];
    if (settings is! Map ||
        settings['version'] is! int ||
        (afterVersion != null && settings['version'] <= afterVersion) ||
        result['deliveries'] is! List ||
        (!job && result['capabilities'] is! Map)) {
      throw const FieldProofException(
        'The saved email settings were not confirmed. Refresh before retrying.',
      );
    }
    return result;
  }

  Future<Map<String, dynamic>> load() async =>
      _state(await _request('GET', ''));
  Future<Map<String, dynamic>> saveSettings(
    int version,
    Map<String, dynamic> settings,
  ) async => _state(
    await _request('PUT', '/settings', {
      'version': version,
      'settings': settings,
      'confirmed': true,
    }),
    afterVersion: version,
  );
  Future<Map<String, dynamic>> job(String id) async => _state(
    await _request('GET', '/jobs/${Uri.encodeComponent(id)}'),
    job: true,
  );
  Future<Map<String, dynamic>> saveJob(
    String id,
    int version,
    Map<String, dynamic> settings,
  ) async => _state(
    await _request('PUT', '/jobs/${Uri.encodeComponent(id)}', {
      'version': version,
      'job_settings': settings,
      'confirmed': true,
    }),
    job: true,
    afterVersion: version,
  );
  Future<Map<String, dynamic>> delivery(String id) async {
    final result = await _request(
      'GET',
      '/deliveries/${Uri.encodeComponent(id)}',
    );
    final delivery = fpEmailMap(result['delivery']);
    if (delivery['id'] != id || delivery['version'] is! int) {
      throw const FieldProofException(
        'The email preview was not confirmed. Refresh and try again.',
      );
    }
    return delivery;
  }

  Future<void> action(String id, String action, int version) async {
    if (!{'approve', 'cancel', 'retry'}.contains(action)) {
      throw ArgumentError.value(action);
    }
    await _request('POST', '/deliveries/${Uri.encodeComponent(id)}/$action', {
      'version': version,
      'confirmed': true,
    });
  }

  Future<void> prepare(String jobId, String requestKey) async {
    await _request('POST', '/jobs/${Uri.encodeComponent(jobId)}/prepare', {
      'request_key': requestKey,
      'confirmed': true,
    });
  }

  Future<Uint8List> report(String id) async {
    final response = await _send(
      'GET',
      '/deliveries/${Uri.encodeComponent(id)}/report',
    );
    final bytes = response.bodyBytes;
    if (bytes.length < 5 ||
        bytes.length > 5 * 1024 * 1024 ||
        ascii.decode(bytes.take(5).toList(), allowInvalid: true) != '%PDF-') {
      throw const FieldProofException(
        'The prepared PDF is unavailable. Refresh and try again.',
      );
    }
    return bytes;
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    sessionChanges?.removeListener(_checkSession);
    _listeners.clear();
    if (_ownsClient) _http.close();
  }
}
