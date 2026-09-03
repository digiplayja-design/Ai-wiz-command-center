import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'korlix_live_convo_agent.dart';
import 'korlix_live_convo_agent_client.dart';

// KORLIX_AGENT_EMAIL_UI_BUILD133_BEGIN

class KorlixAgentEmailRoute {
  const KorlixAgentEmailRoute(this.method, this.template);

  final String method;
  final String template;
}

class KorlixAgentEmailApiContract {
  const KorlixAgentEmailApiContract._();

  static const String statusTemplate =
      "/api/live-convo/agents/:agentId/email/status";

  static const String settingsTemplate =
      "/api/live-convo/agents/:agentId/email/settings";

  static const String recipientsTemplate =
      "/api/live-convo/agents/:agentId/email/recipients";

  static const String recipientTemplate =
      "/api/live-convo/agents/:agentId/email/recipients/:recipientId";

  static const String draftsTemplate =
      "/api/live-convo/agents/:agentId/email/drafts";

  static const String draftTemplate =
      "/api/live-convo/agents/:agentId/email/drafts/:messageId";

  static const String approveDraftTemplate =
      "/api/live-convo/agents/:agentId/email/drafts/:messageId/approve";

  static const String deliveryStatusTemplate =
      "/api/live-convo/agents/:agentId/email/delivery/status";

  static const String sendDraftTemplate =
      "/api/live-convo/agents/:agentId/email/drafts/:messageId/send";

  static const String eventsTemplate =
      "/api/live-convo/agents/:agentId/email/events";

  static const String rulesTemplate =
      "/api/live-convo/agents/:agentId/email/rules";

  static const String ruleTemplate =
      "/api/live-convo/agents/:agentId/email/rules/:ruleId";

  static const String resendWebhookTemplate = "/api/agent-email/resend/webhook";

  static const String autopilotRunTemplate =
      "/api/internal/agent-email/autopilot/run";

  static const bool requiresSharedApprovalNonce = true;

  static const bool approvalNonceReturnedByServer = false;

  static const bool clientCanCallResendWebhook = false;

  static const bool clientCanRunAutopilot = false;

  static const List<KorlixAgentEmailRoute> authenticatedClientRoutes =
      <KorlixAgentEmailRoute>[
        KorlixAgentEmailRoute('GET', statusTemplate),
        KorlixAgentEmailRoute('GET', settingsTemplate),
        KorlixAgentEmailRoute('PUT', settingsTemplate),
        KorlixAgentEmailRoute('GET', recipientsTemplate),
        KorlixAgentEmailRoute('POST', recipientsTemplate),
        KorlixAgentEmailRoute('PATCH', recipientTemplate),
        KorlixAgentEmailRoute('GET', draftsTemplate),
        KorlixAgentEmailRoute('POST', draftsTemplate),
        KorlixAgentEmailRoute('GET', draftTemplate),
        KorlixAgentEmailRoute('PATCH', draftTemplate),
        KorlixAgentEmailRoute('POST', approveDraftTemplate),
        KorlixAgentEmailRoute('GET', deliveryStatusTemplate),
        KorlixAgentEmailRoute('POST', sendDraftTemplate),
        KorlixAgentEmailRoute('GET', eventsTemplate),
        KorlixAgentEmailRoute('GET', rulesTemplate),
        KorlixAgentEmailRoute('POST', rulesTemplate),
        KorlixAgentEmailRoute('PATCH', ruleTemplate),
      ];

  static const List<KorlixAgentEmailRoute> serverOnlyRoutes =
      <KorlixAgentEmailRoute>[
        KorlixAgentEmailRoute('POST', resendWebhookTemplate),
        KorlixAgentEmailRoute('POST', autopilotRunTemplate),
      ];

  static String resolve(
    String template, {
    required String agentId,
    String? recipientId,
    String? messageId,
    String? ruleId,
  }) {
    String encode(String value, String label) {
      final clean = value.trim();

      if (clean.isEmpty) {
        throw ArgumentError('$label is required.');
      }

      return Uri.encodeComponent(clean);
    }

    var path = template;

    final replacements = <String, String>{
      ':agentId': encode(agentId, 'Agent ID'),
      '{agentId}': encode(agentId, 'Agent ID'),
      '<agentId>': encode(agentId, 'Agent ID'),
    };

    if (recipientId != null) {
      final value = encode(recipientId, 'Recipient ID');

      replacements
        ..[':recipientId'] = value
        ..['{recipientId}'] = value
        ..['<recipientId>'] = value;
    }

    if (messageId != null) {
      final value = encode(messageId, 'Message ID');

      replacements
        ..[':messageId'] = value
        ..['{messageId}'] = value
        ..['<messageId>'] = value;
    }

    if (ruleId != null) {
      final value = encode(ruleId, 'Rule ID');

      replacements
        ..[':ruleId'] = value
        ..['{ruleId}'] = value
        ..['<ruleId>'] = value;
    }

    for (final entry in replacements.entries) {
      path = path.replaceAll(entry.key, entry.value);
    }

    final unresolved = RegExp(
      r'(?::|\{|\<)(agentId|recipientId|messageId|ruleId)',
    );

    if (unresolved.hasMatch(path)) {
      throw ArgumentError(
        'The Agent Email route still contains an unresolved ID.',
      );
    }

    if (!path.startsWith('/')) {
      throw ArgumentError('Agent Email routes must be backend-relative paths.');
    }

    return path;
  }
}

class KorlixAgentEmailAccess {
  const KorlixAgentEmailAccess._();

  static bool canOpen(KorlixLiveConvoAgent agent) {
    final tools = agent.toolIds
        .map((tool) => tool.trim().toLowerCase())
        .toSet();

    return agent.isCustom && tools.contains('agent_email');
  }
}

Future<void> showKorlixLiveConvoAgentEmailSheet({
  required BuildContext context,
  required KorlixLiveConvoAgentClient client,
  required KorlixLiveConvoAgent agent,
}) async {
  if (!KorlixAgentEmailAccess.canOpen(agent)) {
    throw const KorlixLiveConvoAgentClientException(
      'Agent Email is not authorized for this Agent.',
      code: 'agent_email_not_authorized',
    );
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xD902070C),
    builder: (sheetContext) {
      return KorlixLiveConvoAgentEmailSheet(client: client, agent: agent);
    },
  );
}

Map<String, dynamic> _emailMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  if (value is Map<Object?, Object?>) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  return <String, dynamic>{};
}

Object? _emailFirst(Map<String, dynamic> source, Iterable<String> keys) {
  for (final key in keys) {
    if (source.containsKey(key) && source[key] != null) {
      return source[key];
    }
  }

  return null;
}

String _emailText(
  Map<String, dynamic> source,
  Iterable<String> keys, {
  String fallback = '',
}) {
  final value = _emailFirst(source, keys);

  final text = value?.toString().trim() ?? '';

  return text.isEmpty ? fallback : text;
}

bool _emailBool(
  Map<String, dynamic> source,
  Iterable<String> keys, {
  bool fallback = false,
}) {
  final value = _emailFirst(source, keys);

  if (value is bool) {
    return value;
  }

  if (value is num) {
    return value != 0;
  }

  final normalized = value?.toString().trim().toLowerCase();

  if (<String>{'true', 'yes', '1', 'on', 'enabled'}.contains(normalized)) {
    return true;
  }

  if (<String>{'false', 'no', '0', 'off', 'disabled'}.contains(normalized)) {
    return false;
  }

  return fallback;
}

int _emailInt(
  Map<String, dynamic> source,
  Iterable<String> keys, {
  int fallback = 0,
}) {
  final value = _emailFirst(source, keys);

  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.round();
  }

  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

Map<String, dynamic> _emailPayload(
  Map<String, dynamic> response,
  Iterable<String> keys,
) {
  for (final key in keys) {
    final nested = _emailMap(response[key]);

    if (nested.isNotEmpty) {
      return nested;
    }
  }

  final data = _emailMap(response['data']);

  if (data.isNotEmpty) {
    return data;
  }

  return response;
}

List<Map<String, dynamic>> _emailItems(
  Map<String, dynamic> response,
  Iterable<String> keys,
) {
  List<Map<String, dynamic>> convert(Object? value) {
    if (value is! Iterable<Object?>) {
      return <Map<String, dynamic>>[];
    }

    return value
        .map(_emailMap)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  for (final key in keys) {
    final direct = convert(response[key]);

    if (direct.isNotEmpty) {
      return direct;
    }

    final nested = _emailMap(response[key]);

    for (final nestedKey in <String>['items', 'results', 'data', ...keys]) {
      final items = convert(nested[nestedKey]);

      if (items.isNotEmpty) {
        return items;
      }
    }
  }

  for (final key in const <String>['items', 'results', 'data']) {
    final items = convert(response[key]);

    if (items.isNotEmpty) {
      return items;
    }
  }

  return <Map<String, dynamic>>[];
}

String _emailId(Map<String, dynamic> source, Iterable<String> keys) {
  return _emailText(source, keys);
}

Color _emailAccent(String value) {
  final clean = value.trim().replaceFirst('#', '').toUpperCase();

  if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(clean)) {
    return const Color(0xFF21D4F4);
  }

  return Color(int.parse('FF$clean', radix: 16));
}

String _emailDate(Object? value) {
  final raw = value?.toString().trim() ?? '';

  if (raw.isEmpty) {
    return '';
  }

  final parsed = DateTime.tryParse(raw);

  if (parsed == null) {
    return raw;
  }

  final local = parsed.toLocal();

  final hour = local.hour == 0
      ? 12
      : local.hour > 12
      ? local.hour - 12
      : local.hour;

  final minute = local.minute.toString().padLeft(2, '0');

  final period = local.hour >= 12 ? 'PM' : 'AM';

  return '${local.month}/${local.day}/${local.year} '
      '$hour:$minute $period';
}

class _KorlixAgentEmailApi {
  const _KorlixAgentEmailApi(this.client);

  final KorlixLiveConvoAgentClient client;

  String get _baseUrl {
    final clean = client.backendBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');

    if (clean.isEmpty) {
      throw const KorlixLiveConvoAgentClientException(
        'The Korlix backend address is unavailable.',
        code: 'backend_address_unavailable',
      );
    }

    return clean;
  }

  Map<String, String> _headers({required bool hasBody}) {
    final headers = Map<String, String>.from(client.headersBuilder());

    headers.removeWhere(
      (name, _) => name.trim().toLowerCase() == 'content-type',
    );

    headers['Accept'] = 'application/json';

    if (hasBody) {
      headers['Content-Type'] = 'application/json; charset=utf-8';
    }

    return headers;
  }

  Future<Map<String, dynamic>> request({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');

    final normalized = method.trim().toUpperCase();

    final headers = _headers(hasBody: body != null);

    final encodedBody = body == null ? null : jsonEncode(body);

    late final http.Response response;

    if (normalized == 'GET') {
      response = await http.get(uri, headers: headers).timeout(client.timeout);
    } else if (normalized == 'POST') {
      response = await http
          .post(uri, headers: headers, body: encodedBody)
          .timeout(client.timeout);
    } else if (normalized == 'PUT') {
      response = await http
          .put(uri, headers: headers, body: encodedBody)
          .timeout(client.timeout);
    } else if (normalized == 'PATCH') {
      response = await http
          .patch(uri, headers: headers, body: encodedBody)
          .timeout(client.timeout);
    } else {
      throw ArgumentError('Unsupported Agent Email method: $normalized');
    }

    Object? decoded;

    if (response.body.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = null;
      }
    }

    final responseMap = _emailMap(decoded);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = responseMap['error'];

      var message = _emailText(responseMap, const <String>[
        'message',
        'detail',
        'details',
      ]);

      if (message.isEmpty && error is Map) {
        message = _emailText(_emailMap(error), const <String>[
          'message',
          'error',
          'detail',
        ]);
      }

      if (message.isEmpty && error is String) {
        message = error.trim();
      }

      if (message.isEmpty) {
        message =
            'Agent Email request failed with HTTP '
            '${response.statusCode}.';
      }

      throw KorlixLiveConvoAgentClientException(
        message,
        code: _emailText(responseMap, const <String>[
          'code',
        ], fallback: 'agent_email_request_failed'),
      );
    }

    if (responseMap.isNotEmpty) {
      return responseMap;
    }

    if (decoded is Iterable<Object?>) {
      return <String, dynamic>{'items': decoded.toList(growable: false)};
    }

    return <String, dynamic>{};
  }
}

class KorlixLiveConvoAgentEmailSheet extends StatefulWidget {
  const KorlixLiveConvoAgentEmailSheet({
    super.key,
    required this.client,
    required this.agent,
  });

  final KorlixLiveConvoAgentClient client;
  final KorlixLiveConvoAgent agent;

  @override
  State<KorlixLiveConvoAgentEmailSheet> createState() {
    return _KorlixLiveConvoAgentEmailSheetState();
  }
}

class _KorlixLiveConvoAgentEmailSheetState
    extends State<KorlixLiveConvoAgentEmailSheet> {
  late final _KorlixAgentEmailApi _api;

  Map<String, dynamic> _status = <String, dynamic>{};

  Map<String, dynamic> _settings = <String, dynamic>{};

  Map<String, dynamic> _deliveryStatus = <String, dynamic>{};

  List<Map<String, dynamic>> _recipients = <Map<String, dynamic>>[];

  List<Map<String, dynamic>> _drafts = <Map<String, dynamic>>[];

  List<Map<String, dynamic>> _events = <Map<String, dynamic>>[];

  List<Map<String, dynamic>> _rules = <Map<String, dynamic>>[];

  final Map<String, String> _heldNonces = <String, String>{};

  bool _loading = true;
  bool _busy = false;
  int _section = 0;
  String? _error;
  DateTime? _loadedAt;

  Color get _accent => _emailAccent(widget.agent.accentHex);

  String get _agentId => widget.agent.id.trim();

  Map<String, dynamic> get _combinedStatus {
    return <String, dynamic>{..._status, ..._settings, ..._deliveryStatus};
  }

  bool get _canSend {
    final combined = _combinedStatus;

    if (combined.containsKey('canSend') || combined.containsKey('can_send')) {
      return _emailBool(combined, const <String>['canSend', 'can_send']);
    }

    final enabled = _emailBool(combined, const <String>[
      'enabled',
      'settingsEnabled',
      'settings_enabled',
      'emailEnabled',
      'email_enabled',
    ]);

    final paused = _emailBool(combined, const <String>[
      'paused',
      'settingsPaused',
      'settings_paused',
      'emergencyPaused',
      'emergency_paused',
    ], fallback: true);

    return enabled && !paused;
  }

  @override
  void initState() {
    super.initState();

    _api = _KorlixAgentEmailApi(widget.client);

    unawaited(_loadAll());
  }

  String _route(
    String template, {
    String? recipientId,
    String? messageId,
    String? ruleId,
  }) {
    return KorlixAgentEmailApiContract.resolve(
      template,
      agentId: _agentId,
      recipientId: recipientId,
      messageId: messageId,
      ruleId: ruleId,
    );
  }

  String _cleanError(Object error) {
    return error
        .toString()
        .replaceFirst('KorlixLiveConvoAgentClientException: ', '')
        .replaceFirst('Exception: ', '')
        .trim();
  }

  Future<Map<String, dynamic>> _safeGet(String template) async {
    try {
      return await _api.request(method: 'GET', path: _route(template));
    } catch (error) {
      return <String, dynamic>{'_loadError': _cleanError(error)};
    }
  }

  Future<void> _loadAll({bool showLoader = true}) async {
    if (!mounted) {
      return;
    }

    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final results = await Future.wait(<Future<Map<String, dynamic>>>[
      _safeGet(KorlixAgentEmailApiContract.statusTemplate),
      _safeGet(KorlixAgentEmailApiContract.settingsTemplate),
      _safeGet(KorlixAgentEmailApiContract.recipientsTemplate),
      _safeGet(KorlixAgentEmailApiContract.draftsTemplate),
      _safeGet(KorlixAgentEmailApiContract.deliveryStatusTemplate),
      _safeGet(KorlixAgentEmailApiContract.eventsTemplate),
      _safeGet(KorlixAgentEmailApiContract.rulesTemplate),
    ]);

    if (!mounted) {
      return;
    }

    final errors = results
        .map((result) => _emailText(result, const <String>['_loadError']))
        .where((message) => message.isNotEmpty)
        .toList(growable: false);

    setState(() {
      _status = _emailPayload(results[0], const <String>[
        'status',
        'emailStatus',
        'email_status',
      ]);

      _settings = _emailPayload(results[1], const <String>['settings']);

      _recipients = _emailItems(results[2], const <String>['recipients']);

      _drafts = _emailItems(results[3], const <String>['drafts', 'messages']);

      _deliveryStatus = _emailPayload(results[4], const <String>[
        'deliveryStatus',
        'delivery_status',
        'status',
      ]);

      _events = _emailItems(results[5], const <String>['events', 'deliveries']);

      _rules = _emailItems(results[6], const <String>['rules', 'automations']);

      _loadedAt = DateTime.now();
      _loading = false;

      _error = errors.isEmpty
          ? null
          : 'Some Agent Email information '
                'could not be loaded:\n'
                '${errors.take(3).join('\n')}';
    });
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error
              ? const Color(0xFF8D3344)
              : const Color(0xFF145A6D),
          duration: const Duration(seconds: 5),
        ),
      );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool dangerous = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF071722),
          title: Text(
            title,
            style: const TextStyle(
              color: Color(0xFFE4EBEE),
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(color: Color(0xFFB9CDD4), height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: dangerous ? const Color(0xFF9C3D4D) : _accent,
                foregroundColor: dangerous
                    ? Colors.white
                    : const Color(0xFF03110E),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<void> _runMutation({
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await action();

      if (!mounted) {
        return;
      }

      _showMessage(successMessage);

      await _loadAll(showLoader: false);
    } catch (error) {
      if (!mounted) {
        return;
      }

      final message = _cleanError(error);

      setState(() {
        _error = message;
      });

      _showMessage(message, error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Color(0xFFA9C6CF)),
      hintStyle: const TextStyle(color: Color(0xFF718B95)),
      filled: true,
      fillColor: const Color(0xFF06141D),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF315866)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _accent, width: 1.6),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  String _newNonce() {
    final random = math.Random.secure();

    final bytes = List<int>.generate(
      32,
      (_) => random.nextInt(256),
      growable: false,
    );

    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<void> _editSettings() async {
    final combined = _combinedStatus;

    const allowedModes = <String>[
      'draft_only',
      'approval_required',
      'autopilot',
    ];

    var mode = _emailText(combined, const <String>[
      'mode',
      'operatingMode',
      'operating_mode',
    ], fallback: 'draft_only');

    if (!allowedModes.contains(mode)) {
      mode = 'draft_only';
    }

    var enabled = _emailBool(combined, const <String>[
      'enabled',
      'settingsEnabled',
      'settings_enabled',
    ]);

    var paused = _emailBool(combined, const <String>[
      'paused',
      'settingsPaused',
      'settings_paused',
      'emergencyPaused',
      'emergency_paused',
    ], fallback: true);

    var marketingEnabled = _emailBool(combined, const <String>[
      'marketingEnabled',
      'marketing_enabled',
    ]);

    final capController = TextEditingController(
      text: _emailInt(combined, const <String>[
        'dailySendCap',
        'daily_send_cap',
      ], fallback: 25).toString(),
    );

    final timezoneController = TextEditingController(
      text: _emailText(combined, const <String>[
        'timezone',
      ], fallback: 'America/New_York'),
    );

    final startController = TextEditingController(
      text: _emailText(combined, const <String>[
        'sendWindowStart',
        'send_window_start',
      ], fallback: '09:00'),
    );

    final endController = TextEditingController(
      text: _emailText(combined, const <String>[
        'sendWindowEnd',
        'send_window_end',
      ], fallback: '17:00'),
    );

    final fromNameController = TextEditingController(
      text: _emailText(combined, const <String>[
        'fromName',
        'from_name',
      ], fallback: widget.agent.name),
    );

    final fromEmailController = TextEditingController(
      text: _emailText(combined, const <String>['fromEmail', 'from_email']),
    );

    final replyToController = TextEditingController(
      text: _emailText(combined, const <String>[
        'replyToEmail',
        'reply_to_email',
      ]),
    );

    final addressController = TextEditingController(
      text: _emailText(combined, const <String>[
        'physicalAddress',
        'physical_address',
      ]),
    );

    String? formError;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF071722),
              title: Text(
                '${widget.agent.name} Email Settings',
                style: const TextStyle(
                  color: Color(0xFFE4EBEE),
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: mode,
                        dropdownColor: const Color(0xFF071722),
                        style: const TextStyle(color: Color(0xFFE4EBEE)),
                        decoration: _decoration('Operating mode'),
                        items: const [
                          DropdownMenuItem(
                            value: 'draft_only',
                            child: Text('Draft Only'),
                          ),
                          DropdownMenuItem(
                            value: 'approval_required',
                            child: Text('Approval Required'),
                          ),
                          DropdownMenuItem(
                            value: 'autopilot',
                            child: Text('Autopilot — Preapproved Rules'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setDialogState(() {
                            mode = value;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: enabled,
                        activeColor: _accent,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Enable Agent Email',
                          style: TextStyle(
                            color: Color(0xFFE4EBEE),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            enabled = value;
                          });
                        },
                      ),
                      SwitchListTile(
                        value: paused,
                        activeColor: const Color(0xFFF28B82),
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Emergency Pause',
                          style: TextStyle(
                            color: Color(0xFFE4EBEE),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: const Text(
                          'When enabled, no Agent Email may be sent.',
                          style: TextStyle(color: Color(0xFFA9C6CF)),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            paused = value;
                          });
                        },
                      ),
                      SwitchListTile(
                        value: marketingEnabled,
                        activeColor: _accent,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Approved Marketing Email',
                          style: TextStyle(
                            color: Color(0xFFE4EBEE),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: const Text(
                          'Consent, unsubscribe, and physical-address rules still apply.',
                          style: TextStyle(color: Color(0xFFA9C6CF)),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            marketingEnabled = value;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: capController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Color(0xFFE4EBEE)),
                        decoration: _decoration('Daily send cap'),
                      ),
                      const SizedBox(height: 11),
                      TextField(
                        controller: timezoneController,
                        style: const TextStyle(color: Color(0xFFE4EBEE)),
                        decoration: _decoration(
                          'Timezone',
                          hint: 'America/New_York',
                        ),
                      ),
                      const SizedBox(height: 11),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: startController,
                              style: const TextStyle(color: Color(0xFFE4EBEE)),
                              decoration: _decoration('Start', hint: '09:00'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: endController,
                              style: const TextStyle(color: Color(0xFFE4EBEE)),
                              decoration: _decoration('End', hint: '17:00'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 11),
                      TextField(
                        controller: fromNameController,
                        style: const TextStyle(color: Color(0xFFE4EBEE)),
                        decoration: _decoration('From name'),
                      ),
                      const SizedBox(height: 11),
                      TextField(
                        controller: fromEmailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Color(0xFFE4EBEE)),
                        decoration: _decoration('From email — optional'),
                      ),
                      const SizedBox(height: 11),
                      TextField(
                        controller: replyToController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Color(0xFFE4EBEE)),
                        decoration: _decoration('Reply-to email — optional'),
                      ),
                      const SizedBox(height: 11),
                      TextField(
                        controller: addressController,
                        minLines: 2,
                        maxLines: 3,
                        style: const TextStyle(color: Color(0xFFE4EBEE)),
                        decoration: _decoration('Physical mailing address'),
                      ),
                      if (formError != null) ...[
                        const SizedBox(height: 11),
                        Text(
                          formError!,
                          style: const TextStyle(
                            color: Color(0xFFFF8A80),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: const Color(0xFF03110E),
                  ),
                  onPressed: () {
                    final cap = int.tryParse(capController.text.trim());

                    if (cap == null || cap < 1 || cap > 500) {
                      setDialogState(() {
                        formError = 'Daily send cap must be between 1 and 500.';
                      });
                      return;
                    }

                    if (timezoneController.text.trim().isEmpty ||
                        startController.text.trim().isEmpty ||
                        endController.text.trim().isEmpty) {
                      setDialogState(() {
                        formError = 'Timezone and send window are required.';
                      });
                      return;
                    }

                    if (marketingEnabled &&
                        addressController.text.trim().isEmpty) {
                      setDialogState(() {
                        formError =
                            'Marketing email requires a physical mailing address.';
                      });
                      return;
                    }

                    Navigator.of(dialogContext).pop(<String, dynamic>{
                      'confirmed': true,
                      'mode': mode,
                      'operatingMode': mode,
                      'enabled': enabled,
                      'paused': paused,
                      'emergencyPaused': paused,
                      'dailySendCap': cap,
                      'timezone': timezoneController.text.trim(),
                      'sendWindowStart': startController.text.trim(),
                      'sendWindowEnd': endController.text.trim(),
                      'marketingEnabled': marketingEnabled,
                      if (fromNameController.text.trim().isNotEmpty)
                        'fromName': fromNameController.text.trim(),
                      if (fromEmailController.text.trim().isNotEmpty)
                        'fromEmail': fromEmailController.text.trim(),
                      if (replyToController.text.trim().isNotEmpty)
                        'replyToEmail': replyToController.text.trim(),
                      if (addressController.text.trim().isNotEmpty)
                        'physicalAddress': addressController.text.trim(),
                    });
                  },
                  child: const Text('Review & Save'),
                ),
              ],
            );
          },
        );
      },
    );

    capController.dispose();
    timezoneController.dispose();
    startController.dispose();
    endController.dispose();
    fromNameController.dispose();
    fromEmailController.dispose();
    replyToController.dispose();
    addressController.dispose();

    if (!mounted || result == null) {
      return;
    }

    final confirmed = await _confirm(
      title: 'Save Agent Email settings?',
      message:
          'These settings apply only to '
          '${widget.agent.name}. Autopilot remains restricted '
          'to preapproved rules and approved recipients.',
      confirmLabel: 'Save Settings',
    );

    if (!confirmed) {
      return;
    }

    await _runMutation(
      action: () async {
        await _api.request(
          method: 'PUT',
          path: _route(KorlixAgentEmailApiContract.settingsTemplate),
          body: result,
        );
      },
      successMessage: '${widget.agent.name} Email settings were saved.',
    );
  }

  Future<void> _addRecipient() async {
    final emailController = TextEditingController();

    final nameController = TextEditingController();

    var consentScope = 'transactional';
    String? formError;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF071722),
              title: const Text(
                'Add Approved Recipient',
                style: TextStyle(
                  color: Color(0xFFE4EBEE),
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Only add an address manually entered or expressly confirmed by the user.',
                      style: TextStyle(color: Color(0xFFA9C6CF), height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Color(0xFFE4EBEE)),
                      decoration: _decoration('Recipient email'),
                    ),
                    const SizedBox(height: 11),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Color(0xFFE4EBEE)),
                      decoration: _decoration('Display name — optional'),
                    ),
                    const SizedBox(height: 11),
                    DropdownButtonFormField<String>(
                      value: consentScope,
                      dropdownColor: const Color(0xFF071722),
                      style: const TextStyle(color: Color(0xFFE4EBEE)),
                      decoration: _decoration('Consent scope'),
                      items: const [
                        DropdownMenuItem(
                          value: 'transactional',
                          child: Text('Transactional Only'),
                        ),
                        DropdownMenuItem(
                          value: 'marketing',
                          child: Text('Marketing — Express Consent'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }

                        setDialogState(() {
                          consentScope = value;
                        });
                      },
                    ),
                    if (formError != null) ...[
                      const SizedBox(height: 11),
                      Text(
                        formError!,
                        style: const TextStyle(
                          color: Color(0xFFFF8A80),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: const Color(0xFF03110E),
                  ),
                  onPressed: () {
                    final email = emailController.text.trim().toLowerCase();

                    final valid = RegExp(
                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                    ).hasMatch(email);

                    if (!valid) {
                      setDialogState(() {
                        formError = 'Enter a valid email address.';
                      });
                      return;
                    }

                    Navigator.of(dialogContext).pop(<String, dynamic>{
                      'confirmed': true,
                      'email': email,
                      'displayName': nameController.text.trim(),
                      'approvalSource': 'manual_user_entry',
                      'consentScope': consentScope,
                      'consentAt': DateTime.now().toUtc().toIso8601String(),
                    });
                  },
                  child: const Text('Add Recipient'),
                ),
              ],
            );
          },
        );
      },
    );

    emailController.dispose();
    nameController.dispose();

    if (!mounted || result == null) {
      return;
    }

    final confirmed = await _confirm(
      title: 'Confirm recipient?',
      message:
          '${result['email']}\n\n'
          'KORLIX will record that this address was manually '
          'approved for ${result['consentScope']} email.',
      confirmLabel: 'Confirm Recipient',
    );

    if (!confirmed) {
      return;
    }

    await _runMutation(
      action: () async {
        await _api.request(
          method: 'POST',
          path: _route(KorlixAgentEmailApiContract.recipientsTemplate),
          body: result,
        );
      },
      successMessage: 'Approved recipient added.',
    );
  }

  Future<void> _setRecipientStatus(
    Map<String, dynamic> recipient,
    String status,
  ) async {
    final recipientId = _emailId(recipient, const <String>[
      'id',
      'recipientId',
      'recipient_id',
    ]);

    if (recipientId.isEmpty) {
      _showMessage('This recipient has no usable recipient ID.', error: true);
      return;
    }

    final email = _emailText(recipient, const <String>[
      'email',
    ], fallback: 'this recipient');

    final label = status == 'unsubscribed' ? 'Unsubscribe' : 'Suppress';

    final confirmed = await _confirm(
      title: '$label $email?',
      message: status == 'unsubscribed'
          ? 'This recipient will no longer receive marketing email.'
          : 'This recipient will be blocked from future Agent Email sends.',
      confirmLabel: label,
      dangerous: true,
    );

    if (!confirmed) {
      return;
    }

    await _runMutation(
      action: () async {
        await _api.request(
          method: 'PATCH',
          path: _route(
            KorlixAgentEmailApiContract.recipientTemplate,
            recipientId: recipientId,
          ),
          body: <String, dynamic>{
            'confirmed': true,
            'status': status,
            'consentAt': _emailText(recipient, const <String>[
              'consentAt',
              'consent_at',
            ], fallback: DateTime.now().toUtc().toIso8601String()),
            'suppressionReason': status == 'unsubscribed'
                ? 'recipient_unsubscribed'
                : 'user_requested_suppression',
          },
        );
      },
      successMessage:
          '$email was ${status == 'unsubscribed' ? 'unsubscribed' : 'suppressed'}.',
    );
  }

  List<Map<String, dynamic>> get _availableRecipients {
    return _recipients
        .where((recipient) {
          final id = _emailId(recipient, const <String>[
            'id',
            'recipientId',
            'recipient_id',
          ]);

          final status = _emailText(recipient, const <String>[
            'status',
          ]).toLowerCase();

          return id.isNotEmpty &&
              status != 'suppressed' &&
              status != 'unsubscribed';
        })
        .toList(growable: false);
  }

  Future<void> _createDraft() async {
    final recipients = _availableRecipients;

    if (recipients.isEmpty) {
      _showMessage(
        'Add an approved recipient before creating a draft.',
        error: true,
      );
      return;
    }

    var recipientId = _emailId(recipients.first, const <String>[
      'id',
      'recipientId',
      'recipient_id',
    ]);

    var marketing = false;
    String? formError;

    final subjectController = TextEditingController();

    final bodyController = TextEditingController();

    final unsubscribeController = TextEditingController();

    final addressController = TextEditingController(
      text: _emailText(_settings, const <String>[
        'physicalAddress',
        'physical_address',
      ]),
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF071722),
              title: Text(
                'Create ${widget.agent.name} Email Draft',
                style: const TextStyle(
                  color: Color(0xFFE4EBEE),
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: recipientId,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF071722),
                        style: const TextStyle(color: Color(0xFFE4EBEE)),
                        decoration: _decoration('Approved recipient'),
                        items: recipients
                            .map((recipient) {
                              final id = _emailId(recipient, const <String>[
                                'id',
                                'recipientId',
                                'recipient_id',
                              ]);

                              final email = _emailText(
                                recipient,
                                const <String>['email'],
                                fallback: id,
                              );

                              return DropdownMenuItem<String>(
                                value: id,
                                child: Text(
                                  email,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            })
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setDialogState(() {
                            recipientId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 11),
                      TextField(
                        controller: subjectController,
                        style: const TextStyle(color: Color(0xFFE4EBEE)),
                        decoration: _decoration('Subject'),
                      ),
                      const SizedBox(height: 11),
                      TextField(
                        controller: bodyController,
                        minLines: 7,
                        maxLines: 12,
                        style: const TextStyle(color: Color(0xFFE4EBEE)),
                        decoration: _decoration('Email message'),
                      ),
                      const SizedBox(height: 5),
                      SwitchListTile(
                        value: marketing,
                        activeColor: _accent,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Marketing Email',
                          style: TextStyle(
                            color: Color(0xFFE4EBEE),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: const Text(
                          'Requires express consent, unsubscribe URL, and physical address.',
                          style: TextStyle(color: Color(0xFFA9C6CF)),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            marketing = value;
                          });
                        },
                      ),
                      if (marketing) ...[
                        TextField(
                          controller: unsubscribeController,
                          keyboardType: TextInputType.url,
                          style: const TextStyle(color: Color(0xFFE4EBEE)),
                          decoration: _decoration('Unsubscribe URL'),
                        ),
                        const SizedBox(height: 11),
                        TextField(
                          controller: addressController,
                          minLines: 2,
                          maxLines: 3,
                          style: const TextStyle(color: Color(0xFFE4EBEE)),
                          decoration: _decoration('Physical mailing address'),
                        ),
                      ],
                      if (formError != null) ...[
                        const SizedBox(height: 11),
                        Text(
                          formError!,
                          style: const TextStyle(
                            color: Color(0xFFFF8A80),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: const Color(0xFF03110E),
                  ),
                  onPressed: () {
                    final subject = subjectController.text.trim();

                    final message = bodyController.text.trim();

                    if (subject.isEmpty || message.isEmpty) {
                      setDialogState(() {
                        formError = 'Subject and message are required.';
                      });
                      return;
                    }

                    if (marketing &&
                        (unsubscribeController.text.trim().isEmpty ||
                            addressController.text.trim().isEmpty)) {
                      setDialogState(() {
                        formError =
                            'Marketing drafts require an unsubscribe URL and physical address.';
                      });
                      return;
                    }

                    Navigator.of(dialogContext).pop(<String, dynamic>{
                      'recipientId': recipientId,
                      'subject': subject,
                      'textBody': message,
                      'idempotencyKey':
                          'draft-${widget.agent.id}-'
                          '${DateTime.now().microsecondsSinceEpoch}',
                      'marketing': marketing,
                      if (marketing)
                        'unsubscribeUrl': unsubscribeController.text.trim(),
                      if (marketing)
                        'physicalAddress': addressController.text.trim(),
                    });
                  },
                  child: const Text('Create Draft'),
                ),
              ],
            );
          },
        );
      },
    );

    subjectController.dispose();
    bodyController.dispose();
    unsubscribeController.dispose();
    addressController.dispose();

    if (!mounted || result == null) {
      return;
    }

    await _runMutation(
      action: () async {
        await _api.request(
          method: 'POST',
          path: _route(KorlixAgentEmailApiContract.draftsTemplate),
          body: result,
        );
      },
      successMessage:
          '${widget.agent.name} created an email draft. Nothing was sent.',
    );
  }

  Future<void> _approveDraft(
    Map<String, dynamic> draft, {
    required bool sendAfterApproval,
  }) async {
    final messageId = _emailId(draft, const <String>[
      'id',
      'messageId',
      'message_id',
    ]);

    if (messageId.isEmpty) {
      _showMessage('This draft has no usable message ID.', error: true);
      return;
    }

    final subject = _emailText(draft, const <String>[
      'subject',
    ], fallback: 'Untitled email');

    final approved = await _confirm(
      title: 'Approve this draft?',
      message:
          'Subject: $subject\n\n'
          'Approval does not send the email. Editing after '
          'approval resets the authorization.',
      confirmLabel: 'Approve Draft',
    );

    if (!approved || _busy) {
      return;
    }

    final nonce = _newNonce();

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // KORLIX_AGENT_EMAIL_NONCE_BOUNDARY_V1
      await _api.request(
        method: 'POST',
        path: _route(
          KorlixAgentEmailApiContract.approveDraftTemplate,
          messageId: messageId,
        ),
        body: <String, dynamic>{'confirmed': true, 'confirmationNonce': nonce},
      );

      _heldNonces[messageId] = nonce;

      var sent = false;

      if (sendAfterApproval && mounted) {
        final sendConfirmed = await _confirm(
          title: 'Send approved email now?',
          message:
              'KORLIX will send the approved email to its '
              'selected recipient. This cannot be undone.',
          confirmLabel: 'Send Email',
        );

        if (sendConfirmed) {
          await _api.request(
            method: 'POST',
            path: _route(
              KorlixAgentEmailApiContract.sendDraftTemplate,
              messageId: messageId,
            ),
            body: <String, dynamic>{
              'confirmed': true,
              'confirmationNonce': nonce,
            },
          );

          _heldNonces.remove(messageId);

          sent = true;
        }
      }

      if (!mounted) {
        return;
      }

      _showMessage(
        sent
            ? 'The approved email was sent.'
            : 'The draft was approved. Its one-time authorization '
                  'is held only in this open screen.',
      );

      await _loadAll(showLoader: false);
    } catch (error) {
      if (!mounted) {
        return;
      }

      final message = _cleanError(error);

      setState(() {
        _error = message;
      });

      _showMessage(message, error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _sendHeldDraft(Map<String, dynamic> draft) async {
    final messageId = _emailId(draft, const <String>[
      'id',
      'messageId',
      'message_id',
    ]);

    final nonce = _heldNonces[messageId];

    if (messageId.isEmpty || nonce == null || nonce.isEmpty) {
      _showMessage(
        'Re-approve this draft in the current screen before sending.',
        error: true,
      );
      return;
    }

    final confirmed = await _confirm(
      title: 'Send approved email?',
      message: 'This one-time approval will be consumed by the send request.',
      confirmLabel: 'Send Email',
    );

    if (!confirmed) {
      return;
    }

    await _runMutation(
      action: () async {
        await _api.request(
          method: 'POST',
          path: _route(
            KorlixAgentEmailApiContract.sendDraftTemplate,
            messageId: messageId,
          ),
          body: <String, dynamic>{
            'confirmed': true,
            'confirmationNonce': nonce,
          },
        );

        _heldNonces.remove(messageId);
      },
      successMessage: 'The approved email was sent.',
    );
  }

  Future<void> _createRule() async {
    final recipients = _availableRecipients;

    if (recipients.isEmpty) {
      _showMessage(
        'Add an approved recipient before creating a rule.',
        error: true,
      );
      return;
    }

    var recipientId = _emailId(recipients.first, const <String>[
      'id',
      'recipientId',
      'recipient_id',
    ]);

    var sendMode = 'draft_only';
    var enabled = true;
    String? formError;

    final nameController = TextEditingController();

    final triggerController = TextEditingController();

    final subjectController = TextEditingController();

    final bodyController = TextEditingController();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF071722),
              title: const Text(
                'Create Agent Email Rule',
                style: TextStyle(
                  color: Color(0xFFE4EBEE),
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'This interface can create rules, but it cannot '
                        'run the server-only Autopilot trigger.',
                        style: TextStyle(color: Color(0xFFA9C6CF), height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: nameController,
                        style: const TextStyle(color: Color(0xFFE4EBEE)),
                        decoration: _decoration('Rule name'),
                      ),
                      const SizedBox(height: 11),
                      TextField(
                        controller: triggerController,
                        style: const TextStyle(color: Color(0xFFE4EBEE)),
                        decoration: _decoration(
                          'Approved trigger key',
                          hint: 'customer_follow_up_due',
                        ),
                      ),
                      const SizedBox(height: 11),
                      DropdownButtonFormField<String>(
                        value: recipientId,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF071722),
                        style: const TextStyle(color: Color(0xFFE4EBEE)),
                        decoration: _decoration('Approved recipient'),
                        items: recipients
                            .map((recipient) {
                              final id = _emailId(recipient, const <String>[
                                'id',
                                'recipientId',
                                'recipient_id',
                              ]);

                              final email = _emailText(
                                recipient,
                                const <String>['email'],
                                fallback: id,
                              );

                              return DropdownMenuItem<String>(
                                value: id,
                                child: Text(
                                  email,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            })
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setDialogState(() {
                            recipientId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 11),
                      DropdownButtonFormField<String>(
                        value: sendMode,
                        dropdownColor: const Color(0xFF071722),
                        style: const TextStyle(color: Color(0xFFE4EBEE)),
                        decoration: _decoration('Rule action'),
                        items: const [
                          DropdownMenuItem(
                            value: 'draft_only',
                            child: Text('Create Draft Only'),
                          ),
                          DropdownMenuItem(
                            value: 'autopilot',
                            child: Text(
                              'Autopilot Send — Preapproval Required',
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setDialogState(() {
                            sendMode = value;
                          });
                        },
                      ),
                      const SizedBox(height: 11),
                      TextField(
                        controller: subjectController,
                        style: const TextStyle(color: Color(0xFFE4EBEE)),
                        decoration: _decoration('Subject template'),
                      ),
                      const SizedBox(height: 11),
                      TextField(
                        controller: bodyController,
                        minLines: 6,
                        maxLines: 10,
                        style: const TextStyle(color: Color(0xFFE4EBEE)),
                        decoration: _decoration('Message template'),
                      ),
                      SwitchListTile(
                        value: enabled,
                        activeColor: _accent,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Enable after saving',
                          style: TextStyle(
                            color: Color(0xFFE4EBEE),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            enabled = value;
                          });
                        },
                      ),
                      if (formError != null) ...[
                        const SizedBox(height: 11),
                        Text(
                          formError!,
                          style: const TextStyle(
                            color: Color(0xFFFF8A80),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: const Color(0xFF03110E),
                  ),
                  onPressed: () {
                    if (nameController.text.trim().isEmpty ||
                        triggerController.text.trim().isEmpty ||
                        subjectController.text.trim().isEmpty ||
                        bodyController.text.trim().isEmpty) {
                      setDialogState(() {
                        formError =
                            'Rule name, trigger, subject, and message are required.';
                      });
                      return;
                    }

                    Navigator.of(dialogContext).pop(<String, dynamic>{
                      'confirmed': true,
                      'name': nameController.text.trim(),
                      'triggerKey': triggerController.text.trim(),
                      'recipientIds': <String>[recipientId],
                      'subjectTemplate': subjectController.text.trim(),
                      'textTemplate': bodyController.text.trim(),
                      'sendMode': sendMode,
                      'enabled': enabled,
                    });
                  },
                  child: const Text('Review Rule'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    triggerController.dispose();
    subjectController.dispose();
    bodyController.dispose();

    if (!mounted || result == null) {
      return;
    }

    final autopilot = result['sendMode'] == 'autopilot';

    final confirmed = await _confirm(
      title: autopilot ? 'Preapprove Autopilot rule?' : 'Save Draft-Only rule?',
      message: autopilot
          ? 'This rule may send later only when its exact server-side '
                'trigger, approved recipients, consent, daily cap, '
                'send window, and suppression checks all pass.'
          : 'This rule may create drafts but cannot send without '
                'a separate approval.',
      confirmLabel: autopilot ? 'Preapprove Rule' : 'Save Rule',
    );

    if (!confirmed) {
      return;
    }

    final body = Map<String, dynamic>.from(result);

    if (autopilot) {
      body
        ..['preapproved'] = true
        ..['confirmationNonce'] = _newNonce();
    }

    await _runMutation(
      action: () async {
        await _api.request(
          method: 'POST',
          path: _route(KorlixAgentEmailApiContract.rulesTemplate),
          body: body,
        );
      },
      successMessage: autopilot
          ? 'Preapproved Autopilot rule saved.'
          : 'Draft-Only rule saved.',
    );
  }

  Widget _statusChip({required String label, required bool positive}) {
    final color = positive ? const Color(0xFF62D6A7) : const Color(0xFFF28B82);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.68)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      width: 205,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF071722),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: color.withValues(alpha: 0.14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF8FA8B1),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE4EBEE),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: _accent),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFE4EBEE),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFA9C6CF), height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _overview() {
    final combined = _combinedStatus;

    final mode = _emailText(combined, const <String>[
      'mode',
      'operatingMode',
      'operating_mode',
    ], fallback: 'draft_only');

    final enabled = _emailBool(combined, const <String>[
      'enabled',
      'settingsEnabled',
      'settings_enabled',
    ]);

    final paused = _emailBool(combined, const <String>[
      'paused',
      'settingsPaused',
      'settings_paused',
      'emergencyPaused',
      'emergency_paused',
    ], fallback: true);

    final provider = _emailBool(combined, const <String>[
      'providerConfigured',
      'provider_configured',
      'resendConfigured',
      'resend_configured',
    ]);

    final dailyCap = _emailInt(combined, const <String>[
      'dailySendCap',
      'daily_send_cap',
    ]);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _summaryCard(
              icon: Icons.tune_rounded,
              label: 'MODE',
              value: mode.replaceAll('_', ' ').toUpperCase(),
              color: _accent,
            ),
            _summaryCard(
              icon: Icons.people_alt_rounded,
              label: 'RECIPIENTS',
              value: '${_recipients.length}',
              color: const Color(0xFF62D6A7),
            ),
            _summaryCard(
              icon: Icons.drafts_rounded,
              label: 'DRAFTS',
              value: '${_drafts.length}',
              color: const Color(0xFFF2C14E),
            ),
            _summaryCard(
              icon: Icons.speed_rounded,
              label: 'DAILY CAP',
              value: dailyCap > 0 ? '$dailyCap' : 'Not set',
              color: const Color(0xFFB794F4),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFF071722),
            border: Border.all(color: const Color(0xFF2B5360)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusChip(
                    label: enabled ? 'EMAIL ENABLED' : 'EMAIL DISABLED',
                    positive: enabled,
                  ),
                  _statusChip(
                    label: paused ? 'EMERGENCY PAUSED' : 'NOT PAUSED',
                    positive: !paused,
                  ),
                  _statusChip(
                    label: provider ? 'PROVIDER READY' : 'PROVIDER NOT READY',
                    positive: provider,
                  ),
                  _statusChip(
                    label: _canSend ? 'CONTROLLED SEND READY' : 'SEND LOCKED',
                    positive: _canSend,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        unawaited(_editSettings());
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: const Color(0xFF03110E),
                ),
                icon: const Icon(Icons.settings_rounded),
                label: const Text(
                  'Agent Email Settings',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Recent Delivery Events',
          style: TextStyle(
            color: Color(0xFFE4EBEE),
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 9),
        if (_events.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: const Color(0xFF071722),
              border: Border.all(color: const Color(0xFF2B5360)),
            ),
            child: const Text(
              'No delivery events are available yet.',
              style: TextStyle(color: Color(0xFFA9C6CF)),
            ),
          )
        else
          ..._events.take(12).map((event) {
            final type = _emailText(event, const <String>[
              'type',
              'eventType',
              'event_type',
              'status',
            ], fallback: 'email_event');

            final detail = _emailText(event, const <String>[
              'message',
              'detail',
              'description',
              'recipientEmail',
              'recipient_email',
            ], fallback: 'Agent Email activity recorded.');

            final time = _emailDate(
              _emailFirst(event, const <String>[
                'createdAt',
                'created_at',
                'occurredAt',
                'occurred_at',
                'timestamp',
              ]),
            );

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: const Color(0xFF071722),
                border: Border.all(color: const Color(0xFF244D5C)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.mark_email_read_rounded, color: _accent, size: 21),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type.replaceAll('_', ' ').toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFFE4EBEE),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          detail,
                          style: const TextStyle(color: Color(0xFFA9C6CF)),
                        ),
                        if (time.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            time,
                            style: const TextStyle(
                              color: Color(0xFF718B95),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _recipientList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Approved Recipients',
                style: TextStyle(
                  color: Color(0xFFE4EBEE),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      unawaited(_addRecipient());
                    },
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: const Color(0xFF03110E),
              ),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_recipients.isEmpty)
          _emptyState(
            icon: Icons.people_outline_rounded,
            title: 'No approved recipients',
            message:
                'Add only addresses manually entered or expressly '
                'confirmed by the user. KORLIX will not scrape or guess them.',
          )
        else
          ..._recipients.map((recipient) {
            final email = _emailText(recipient, const <String>[
              'email',
            ], fallback: 'Email unavailable');

            final name = _emailText(recipient, const <String>[
              'displayName',
              'display_name',
              'name',
            ]);

            final status = _emailText(recipient, const <String>[
              'status',
            ], fallback: 'transactional_only').toLowerCase();

            final scope = _emailText(recipient, const <String>[
              'consentScope',
              'consent_scope',
            ], fallback: 'transactional');

            final blocked = status == 'suppressed' || status == 'unsubscribed';

            return Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: const Color(0xFF071722),
                border: Border.all(
                  color: blocked
                      ? const Color(0xFF8D3344)
                      : const Color(0xFF2B5360),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _accent.withValues(alpha: 0.14),
                    foregroundColor: _accent,
                    child: const Icon(Icons.person_rounded),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? email : name,
                          style: const TextStyle(
                            color: Color(0xFFE4EBEE),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (name.isNotEmpty)
                          Text(
                            email,
                            style: const TextStyle(color: Color(0xFFA9C6CF)),
                          ),
                        const SizedBox(height: 5),
                        Text(
                          '${status.replaceAll('_', ' ')} • '
                          '${scope.replaceAll('_', ' ')}',
                          style: TextStyle(
                            color: blocked
                                ? const Color(0xFFFF8A80)
                                : const Color(0xFF62D6A7),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!blocked)
                    PopupMenuButton<String>(
                      enabled: !_busy,
                      color: const Color(0xFF071722),
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: Color(0xFFA9C6CF),
                      ),
                      onSelected: (value) {
                        unawaited(_setRecipientStatus(recipient, value));
                      },
                      itemBuilder: (context) {
                        return const [
                          PopupMenuItem(
                            value: 'unsubscribed',
                            child: Text('Unsubscribe'),
                          ),
                          PopupMenuItem(
                            value: 'suppressed',
                            child: Text('Suppress'),
                          ),
                        ];
                      },
                    ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _draftList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Agent Email Drafts',
                style: TextStyle(
                  color: Color(0xFFE4EBEE),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      unawaited(_createDraft());
                    },
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: const Color(0xFF03110E),
              ),
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('New Draft'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_drafts.isEmpty)
          _emptyState(
            icon: Icons.drafts_outlined,
            title: 'No drafts yet',
            message:
                '${widget.agent.name} can prepare a draft without '
                'sending anything. Approval and sending remain separate.',
          )
        else
          ..._drafts.map((draft) {
            final messageId = _emailId(draft, const <String>[
              'id',
              'messageId',
              'message_id',
            ]);

            final subject = _emailText(draft, const <String>[
              'subject',
            ], fallback: 'Untitled email');

            final body = _emailText(draft, const <String>[
              'textBody',
              'text_body',
              'body',
            ]);

            final status = _emailText(draft, const <String>[
              'status',
            ], fallback: 'draft').toLowerCase();

            final recipient = _emailText(draft, const <String>[
              'recipientEmail',
              'recipient_email',
              'to',
            ]);

            final sent =
                status == 'sent' ||
                status == 'delivered' ||
                status == 'completed';

            final held = _heldNonces.containsKey(messageId);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: const Color(0xFF071722),
                border: Border.all(
                  color: sent
                      ? const Color(0xFF62D6A7)
                      : held
                      ? const Color(0xFFF2C14E)
                      : const Color(0xFF2B5360),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        sent
                            ? Icons.mark_email_read_rounded
                            : Icons.drafts_rounded,
                        color: sent ? const Color(0xFF62D6A7) : _accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subject,
                              style: const TextStyle(
                                color: Color(0xFFE4EBEE),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (recipient.isNotEmpty)
                              Text(
                                'To: $recipient',
                                style: const TextStyle(
                                  color: Color(0xFFA9C6CF),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _statusChip(
                        label: status.replaceAll('_', ' ').toUpperCase(),
                        positive: sent || held,
                      ),
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      body,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB9CDD4),
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (!sent) ...[
                    const SizedBox(height: 13),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () {
                                  unawaited(
                                    _approveDraft(
                                      draft,
                                      sendAfterApproval: false,
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.verified_rounded),
                          label: const Text('Approve'),
                        ),
                        FilledButton.icon(
                          onPressed: _busy || !_canSend
                              ? null
                              : () {
                                  unawaited(
                                    _approveDraft(
                                      draft,
                                      sendAfterApproval: true,
                                    ),
                                  );
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: const Color(0xFF03110E),
                          ),
                          icon: const Icon(Icons.outgoing_mail),
                          label: const Text('Approve & Send'),
                        ),
                        if (held)
                          OutlinedButton.icon(
                            onPressed: _busy || !_canSend
                                ? null
                                : () {
                                    unawaited(_sendHeldDraft(draft));
                                  },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFF2C14E),
                              side: const BorderSide(color: Color(0xFFF2C14E)),
                            ),
                            icon: const Icon(Icons.send_rounded),
                            label: const Text('Send Approved'),
                          ),
                      ],
                    ),
                    if (!_canSend) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Controlled sending is currently locked by settings, '
                        'emergency pause, provider status, or server policy.',
                        style: TextStyle(
                          color: Color(0xFFF28B82),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _ruleList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFF151A24),
            border: Border.all(
              color: const Color(0xFFF2C14E).withValues(alpha: 0.55),
            ),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.security_rounded, color: Color(0xFFF2C14E)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Autopilot execution is server-controlled. This screen '
                  'may create preapproved rules but cannot run the internal '
                  'trigger or call the Resend webhook.',
                  style: TextStyle(
                    color: Color(0xFFE7D79D),
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Preapproved Rules',
                style: TextStyle(
                  color: Color(0xFFE4EBEE),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      unawaited(_createRule());
                    },
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: const Color(0xFF03110E),
              ),
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('New Rule'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_rules.isEmpty)
          _emptyState(
            icon: Icons.rule_folder_outlined,
            title: 'No Agent Email rules',
            message:
                'Create a Draft-Only rule or explicitly preapprove '
                'a tightly restricted Autopilot rule.',
          )
        else
          ..._rules.map((rule) {
            final name = _emailText(rule, const <String>[
              'name',
            ], fallback: 'Unnamed rule');

            final trigger = _emailText(rule, const <String>[
              'triggerKey',
              'trigger_key',
            ], fallback: 'Trigger unavailable');

            final sendMode = _emailText(rule, const <String>[
              'sendMode',
              'send_mode',
            ], fallback: 'draft_only');

            final enabled = _emailBool(rule, const <String>['enabled']);

            final preapproved = _emailBool(rule, const <String>[
              'preapproved',
              'pre_approved',
            ]);

            return Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: const Color(0xFF071722),
                border: Border.all(
                  color: enabled
                      ? _accent.withValues(alpha: 0.62)
                      : const Color(0xFF2B5360),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    sendMode == 'autopilot'
                        ? Icons.auto_mode_rounded
                        : Icons.drafts_rounded,
                    color: sendMode == 'autopilot'
                        ? const Color(0xFFF2C14E)
                        : _accent,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Color(0xFFE4EBEE),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Trigger: $trigger',
                          style: const TextStyle(color: Color(0xFFA9C6CF)),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${sendMode.replaceAll('_', ' ')} • '
                          '${enabled ? 'enabled' : 'disabled'} • '
                          '${preapproved ? 'preapproved' : 'not preapproved'}',
                          style: const TextStyle(
                            color: Color(0xFF8CDDE8),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _sectionSelector() {
    const sections = <({IconData icon, String label})>[
      (icon: Icons.dashboard_rounded, label: 'Overview'),
      (icon: Icons.people_alt_rounded, label: 'Recipients'),
      (icon: Icons.drafts_rounded, label: 'Drafts'),
      (icon: Icons.auto_mode_rounded, label: 'Autopilot'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: List<Widget>.generate(sections.length, (index) {
          final section = sections[index];

          final selected = _section == index;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: selected,
              selectedColor: _accent.withValues(alpha: 0.22),
              side: BorderSide(
                color: selected ? _accent : const Color(0xFF315866),
              ),
              avatar: Icon(
                section.icon,
                size: 18,
                color: selected ? _accent : const Color(0xFFA9C6CF),
              ),
              label: Text(section.label),
              labelStyle: TextStyle(
                color: selected
                    ? const Color(0xFFE4EBEE)
                    : const Color(0xFFA9C6CF),
                fontWeight: FontWeight.w900,
              ),
              onSelected: (_) {
                setState(() {
                  _section = index;
                });
              },
            ),
          );
        }),
      ),
    );
  }

  Widget _selectedSection() {
    switch (_section) {
      case 1:
        return _recipientList();

      case 2:
        return _draftList();

      case 3:
        return _ruleList();

      case 0:
      default:
        return _overview();
    }
  }

  @override
  Widget build(BuildContext context) {
    final updated = _loadedAt == null
        ? ''
        : _emailDate(_loadedAt!.toUtc().toIso8601String());

    return FractionallySizedBox(
      heightFactor: 0.95,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Material(
            color: const Color(0xFF041019),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 13, 10, 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF071722),
                    border: Border(
                      bottom: BorderSide(
                        color: _accent.withValues(alpha: 0.38),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          color: _accent.withValues(alpha: 0.14),
                          border: Border.all(
                            color: _accent.withValues(alpha: 0.7),
                          ),
                        ),
                        child: Icon(
                          Icons.alternate_email_rounded,
                          color: _accent,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'AGENT EMAIL',
                              style: TextStyle(
                                color: Color(0xFFA9C6CF),
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              widget.agent.name,
                              style: const TextStyle(
                                color: Color(0xFFE4EBEE),
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (updated.isNotEmpty)
                              Text(
                                'Updated $updated',
                                style: const TextStyle(
                                  color: Color(0xFF718B95),
                                  fontSize: 10.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh Agent Email',
                        onPressed: _busy || _loading
                            ? null
                            : () {
                                unawaited(_loadAll());
                              },
                        icon: _busy
                            ? const SizedBox(
                                width: 21,
                                height: 21,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded),
                        color: _accent,
                      ),
                      IconButton(
                        tooltip: 'Close Agent Email',
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.close_rounded),
                        color: const Color(0xFFC7D7DC),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                  color: const Color(0xFF0D1C24),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.verified_user_rounded,
                        size: 20,
                        color: Color(0xFF62D6A7),
                      ),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Draft Only is the safe default. Sending requires '
                          'explicit approval or a preapproved server-side rule. '
                          'Scraped and guessed recipients are prohibited.',
                          style: TextStyle(
                            color: Color(0xFFB9CDD4),
                            height: 1.4,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _sectionSelector(),
                if (_error != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: const Color(0xFF3C1720),
                      border: Border.all(color: const Color(0xFF9C3D4D)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFFFF8A80),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFFFFB4AB),
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _loading
                      ? Center(child: CircularProgressIndicator(color: _accent))
                      : _selectedSection(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// KORLIX_AGENT_EMAIL_NO_INTERNAL_TRIGGER_V1
// KORLIX_AGENT_EMAIL_UI_BUILD133_END
