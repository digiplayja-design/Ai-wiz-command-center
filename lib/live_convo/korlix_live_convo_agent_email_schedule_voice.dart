// K134B_LIVE_CONVO_AGENT_EMAIL_SCHEDULE_VOICE_V1_BEGIN
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'korlix_live_convo_agent_email_voice.dart';

String _svText(Object? value, {int max = 40000, String fallback = ''}) {
  final text = (value ?? '').toString().trim();
  if (text.isEmpty) return fallback;
  return text.length <= max ? text : text.substring(0, max);
}

bool _svBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return <String>{
    'true',
    '1',
    'yes',
    'on',
    'enabled',
    'active',
  }.contains(_svText(value, max: 40).toLowerCase());
}

Map<String, dynamic>? _svMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  return value is Map ? Map<String, dynamic>.from(value) : null;
}

List<Object?> _svList(Object? value) {
  if (value is Iterable) return List<Object?>.from(value);
  final text = _svText(value, max: 500);
  if (text.isEmpty) return const <Object?>[];
  return text
      .split(RegExp(r'[,;|]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String _svLine(Object? value) =>
    _svText(value).replaceAll(RegExp(r'\s+'), ' ').trim();
String _svBlock(Object? value) =>
    _svText(value).replaceAll(RegExp(r'\r\n?'), '\n').trim();

class KorlixLiveConvoAgentEmailScheduleToolCall {
  const KorlixLiveConvoAgentEmailScheduleToolCall({
    required this.callId,
    required this.name,
    required this.arguments,
  });

  final String callId;
  final String name;
  final Map<String, dynamic> arguments;

  String get recipient => _svText(
    arguments['recipient'] ?? arguments['recipientName'] ?? arguments['email'],
    max: 320,
  );
  String get subject =>
      _svText(arguments['subject'] ?? arguments['subjectLine'], max: 200);
  String get body => _svText(
    arguments['body'] ?? arguments['message'] ?? arguments['textBody'],
  );
  String get ruleName =>
      _svText(arguments['ruleName'] ?? arguments['name'], max: 200);
  String get scheduleType => _svText(
    arguments['scheduleType'] ??
        arguments['schedule_type'] ??
        arguments['frequency'],
    max: 40,
  );
  String get scheduleTimezone => _svText(
    arguments['scheduleTimezone'] ??
        arguments['timeZone'] ??
        arguments['timezone'],
    max: 80,
  );
  String get scheduleLocalTime => _svText(
    arguments['scheduleLocalTime'] ??
        arguments['localTime'] ??
        arguments['sendTime'],
    max: 40,
  );
  String get scheduledFor => _svText(
    arguments['scheduledFor'] ??
        arguments['scheduledAt'] ??
        arguments['dateTime'],
    max: 120,
  );
  List<Object?> get scheduleDays => _svList(
    arguments['scheduleDays'] ?? arguments['days'] ?? arguments['weekdays'],
  );

  static List<KorlixLiveConvoAgentEmailScheduleToolCall> fromResponseDone(
    Map<String, dynamic> response,
  ) {
    final output = response['output'];
    if (output is! Iterable) {
      return const <KorlixLiveConvoAgentEmailScheduleToolCall>[];
    }

    final calls = <KorlixLiveConvoAgentEmailScheduleToolCall>[];
    for (final raw in output) {
      final item = _svMap(raw);
      if (item == null) continue;
      final type = _svText(item['type'], max: 80).toLowerCase();
      final name = _svText(item['name'], max: 120);
      if (!<String>{'function_call', 'function'}.contains(type) ||
          name != KorlixLiveConvoAgentEmailScheduleVoiceBridge.toolName) {
        continue;
      }

      final callId = _svText(
        item['call_id'] ?? item['callId'] ?? item['id'],
        max: 180,
      );
      if (callId.isEmpty) continue;
      Map<String, dynamic> arguments = const <String, dynamic>{};
      final direct = _svMap(item['arguments']);
      if (direct != null) {
        arguments = direct;
      } else if (item['arguments'] is String) {
        try {
          arguments =
              _svMap(jsonDecode(item['arguments'] as String)) ??
              const <String, dynamic>{};
        } catch (_) {}
      }
      calls.add(
        KorlixLiveConvoAgentEmailScheduleToolCall(
          callId: callId,
          name: name,
          arguments: Map<String, dynamic>.unmodifiable(arguments),
        ),
      );
    }
    return List<KorlixLiveConvoAgentEmailScheduleToolCall>.unmodifiable(calls);
  }
}

class KorlixLiveConvoAgentEmailPendingSchedule {
  KorlixLiveConvoAgentEmailPendingSchedule({
    required this.agentId,
    required this.callId,
    required this.recipientId,
    required this.recipientName,
    required this.recipientEmail,
    required this.ruleName,
    required this.triggerKey,
    required this.subject,
    required this.body,
    required this.scheduleType,
    required this.scheduleTimezone,
    required this.scheduleLocalTime,
    required List<int> scheduleDays,
    required this.scheduledFor,
    required this.confirmationNonce,
    required this.createdAt,
    required this.expiresAt,
  }) : scheduleDays = List<int>.unmodifiable(scheduleDays);

  final String agentId;
  final String callId;
  final String recipientId;
  final String recipientName;
  final String recipientEmail;
  final String ruleName;
  final String triggerKey;
  final String subject;
  final String body;
  final String scheduleType;
  final String scheduleTimezone;
  final String? scheduleLocalTime;
  final List<int> scheduleDays;
  final String? scheduledFor;
  final String confirmationNonce;
  final DateTime createdAt;
  final DateTime expiresAt;

  factory KorlixLiveConvoAgentEmailPendingSchedule.fromPreparationOutput(
    Map<String, dynamic> output, {
    required String agentId,
    required String confirmationNonce,
    DateTime? now,
    Duration lifetime = const Duration(minutes: 5),
  }) {
    final created = (now ?? DateTime.now()).toUtc();
    final type =
        KorlixLiveConvoAgentEmailScheduleVoiceBridge.normalizeScheduleType(
          output['scheduleType'],
        );
    final timezone =
        KorlixLiveConvoAgentEmailScheduleVoiceBridge.normalizeTimezone(
          output['scheduleTimezone'],
        );
    final localTime = type == 'weekly'
        ? KorlixLiveConvoAgentEmailScheduleVoiceBridge.normalizeLocalTime(
            output['scheduleLocalTime'],
          )
        : null;
    final days = type == 'weekly'
        ? KorlixLiveConvoAgentEmailScheduleVoiceBridge.normalizeScheduleDays(
            output['scheduleDays'],
          )
        : const <int>[];
    final scheduledFor = type == 'once'
        ? KorlixLiveConvoAgentEmailScheduleVoiceBridge.normalizeScheduledFor(
            output['scheduledFor'],
            requireFuture: false,
          )
        : null;
    final cleanAgentId = _svText(agentId, max: 96).toLowerCase();
    final callId = _svText(output['callId'], max: 180);
    final recipientId = _svText(output['recipientId'], max: 100);
    final recipientEmail = _svText(
      output['recipientEmail'],
      max: 320,
    ).toLowerCase();
    final ruleName = _svText(output['ruleName'], max: 200);
    final triggerKey = _svText(output['triggerKey'], max: 120).toLowerCase();
    final subject = _svText(output['subject'], max: 200);
    final body = _svText(output['body']);

    if (cleanAgentId.isEmpty ||
        callId.isEmpty ||
        recipientId.isEmpty ||
        recipientEmail.isEmpty ||
        ruleName.isEmpty ||
        triggerKey.isEmpty ||
        subject.isEmpty ||
        body.isEmpty ||
        confirmationNonce.length < 12) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'The prepared scheduled email is missing protected confirmation data. '
        'No schedule was created and nothing was sent.',
        code: 'agent_email_schedule_voice_pending_invalid',
      );
    }

    return KorlixLiveConvoAgentEmailPendingSchedule(
      agentId: cleanAgentId,
      callId: callId,
      recipientId: recipientId,
      recipientName: _svText(output['recipientName'], max: 160),
      recipientEmail: recipientEmail,
      ruleName: ruleName,
      triggerKey: triggerKey,
      subject: subject,
      body: body,
      scheduleType: type,
      scheduleTimezone: timezone,
      scheduleLocalTime: localTime,
      scheduleDays: days,
      scheduledFor: scheduledFor,
      confirmationNonce: confirmationNonce,
      createdAt: created,
      expiresAt: created.add(lifetime),
    );
  }

  bool isExpired([DateTime? now]) =>
      !(now ?? DateTime.now()).toUtc().isBefore(expiresAt);

  String get scheduleDescription {
    if (scheduleType == 'once') {
      return 'one time at $scheduledFor in $scheduleTimezone';
    }
    final names = KorlixLiveConvoAgentEmailScheduleVoiceBridge.dayNames(
      scheduleDays,
    );
    return 'weekly on ${names.join(', ')} at $scheduleLocalTime in $scheduleTimezone';
  }

  Map<String, dynamic> toRuleBody() => <String, dynamic>{
    'confirmed': true,
    'confirmation': true,
    'preapproved': true,
    'confirmationNonce': confirmationNonce,
    'confirmation_nonce': confirmationNonce,
    'name': ruleName,
    'triggerKey': triggerKey,
    'recipientIds': <String>[recipientId],
    'subjectTemplate': subject,
    'textTemplate': body,
    'htmlTemplate': '',
    'marketing': false,
    'sendMode': 'autopilot',
    'enabled': true,
    'maxSendsPerDay': 1,
    'scheduleType': scheduleType,
    'scheduleTimezone': scheduleTimezone,
    if (scheduleType == 'weekly') 'scheduleLocalTime': scheduleLocalTime,
    if (scheduleType == 'weekly') 'scheduleDays': scheduleDays,
    if (scheduleType == 'once') 'scheduledFor': scheduledFor,
  };

  bool matchesRule(Map<String, dynamic> rule) {
    final recipients = _svList(
      rule['recipientIds'],
    ).map((item) => _svText(item, max: 100)).toList();
    final type = _svText(rule['scheduleType'], max: 40).toLowerCase();
    final timezone = _svText(rule['scheduleTimezone'], max: 80);
    final days = type == 'weekly'
        ? KorlixLiveConvoAgentEmailScheduleVoiceBridge.normalizeScheduleDays(
            rule['scheduleDays'],
          )
        : const <int>[];
    final once = type == 'once'
        ? KorlixLiveConvoAgentEmailScheduleVoiceBridge.normalizeScheduledFor(
            rule['scheduledFor'],
            requireFuture: false,
          )
        : null;

    return _svText(rule['id'], max: 100).isNotEmpty &&
        _svBool(rule['enabled']) &&
        _svBool(rule['preapproved']) &&
        _svText(rule['sendMode'], max: 40).toLowerCase() == 'autopilot' &&
        recipients.length == 1 &&
        recipients.single == recipientId &&
        _svLine(rule['name']) == _svLine(ruleName) &&
        _svLine(rule['subjectTemplate']) == _svLine(subject) &&
        _svBlock(rule['textTemplate']) == _svBlock(body) &&
        type == scheduleType &&
        timezone == scheduleTimezone &&
        (type != 'weekly' ||
            (_svText(rule['scheduleLocalTime'], max: 20) == scheduleLocalTime &&
                _sameDays(days, scheduleDays))) &&
        (type != 'once' || once == scheduledFor);
  }

  static bool _sameDays(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

class KorlixLiveConvoAgentEmailScheduleVoiceBridge {
  const KorlixLiveConvoAgentEmailScheduleVoiceBridge._();

  static const String toolName = 'create_agent_email_schedule';
  static const Map<String, dynamic> toolDefinition = <String, dynamic>{
    'type': 'function',
    'name': toolName,
    'description':
        'Prepare one transactional one-time or weekly Agent Email schedule for '
        'one existing approved recipient. This initial call never creates a '
        'rule and never sends email. Supply the exact recipient, subject, body, '
        'schedule type, and IANA timezone. For once, supply scheduledFor as an '
        'ISO-8601 future date-time with Z or an offset. For weekly, supply '
        'scheduleLocalTime as HH:MM and every schedule day. The application '
        'reads back every detail and waits for a separate spoken yes or no.',
    'parameters': <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'recipient': <String, dynamic>{
          'type': 'string',
          'description': 'Exact approved recipient name or email address.',
        },
        'subject': <String, dynamic>{'type': 'string'},
        'body': <String, dynamic>{'type': 'string'},
        'scheduleType': <String, dynamic>{
          'type': 'string',
          'enum': <String>['once', 'weekly'],
        },
        'scheduleTimezone': <String, dynamic>{
          'type': 'string',
          'description': 'IANA timezone, for example America/New_York.',
        },
        'scheduledFor': <String, dynamic>{
          'type': 'string',
          'description':
              'For once: ISO-8601 future date-time with Z or offset.',
        },
        'scheduleLocalTime': <String, dynamic>{
          'type': 'string',
          'description': 'For weekly: local 24-hour HH:MM time.',
        },
        'scheduleDays': <String, dynamic>{
          'type': 'array',
          'items': <String, dynamic>{'type': 'string'},
          'description': 'For weekly: every full weekday name.',
        },
        'ruleName': <String, dynamic>{'type': 'string'},
      },
      'required': <String>[
        'recipient',
        'subject',
        'body',
        'scheduleType',
        'scheduleTimezone',
      ],
      'additionalProperties': false,
    },
  };

  static bool isAuthorized({
    required bool isCustom,
    required bool active,
    required Iterable<String> toolIds,
  }) => KorlixLiveConvoAgentEmailVoiceBridge.isAuthorized(
    isCustom: isCustom,
    active: active,
    toolIds: toolIds,
  );

  static String normalizeScheduleType(Object? value) {
    final type = _svText(
      value,
      max: 40,
    ).toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    if (<String>{'once', 'one_time', 'onetime', 'single'}.contains(type)) {
      return 'once';
    }
    if (<String>{'weekly', 'every_week', 'recurring_weekly'}.contains(type)) {
      return 'weekly';
    }
    throw const KorlixLiveConvoAgentEmailVoiceException(
      'Choose either a one-time or weekly scheduled email. '
      'No schedule was created and nothing was sent.',
      code: 'agent_email_schedule_voice_type_invalid',
    );
  }

  static String normalizeTimezone(Object? value) {
    var timezone = _svText(value, max: 80);
    if (timezone.toLowerCase() == 'utc') timezone = 'UTC';
    final valid =
        timezone == 'UTC' ||
        RegExp(
          r'^[A-Za-z][A-Za-z0-9._+-]*(?:/[A-Za-z0-9._+-]+)+$',
        ).hasMatch(timezone);
    if (!valid) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'Use a valid IANA timezone such as America/New_York. '
        'No schedule was created and nothing was sent.',
        code: 'agent_email_schedule_voice_timezone_invalid',
      );
    }
    return timezone;
  }

  static String normalizeLocalTime(Object? value) {
    final text = _svText(
      value,
      max: 40,
    ).toLowerCase().replaceAll('.', '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final match = RegExp(
      r'^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$',
    ).firstMatch(text);
    if (match == null) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'Use a clear weekly time such as 09:30 or 9:30 AM. '
        'No schedule was created and nothing was sent.',
        code: 'agent_email_schedule_voice_local_time_invalid',
      );
    }
    var hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '0');
    final suffix = match.group(3);
    if (hour == null || minute == null) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'The weekly email time is invalid. '
        'No schedule was created and nothing was sent.',
        code: 'agent_email_schedule_voice_local_time_invalid',
      );
    }
    final invalid =
        minute < 0 ||
        minute > 59 ||
        (suffix == null && (hour < 0 || hour > 23)) ||
        (suffix != null && (hour < 1 || hour > 12));
    if (invalid) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'The weekly email time is invalid. '
        'No schedule was created and nothing was sent.',
        code: 'agent_email_schedule_voice_local_time_invalid',
      );
    }
    if (suffix == 'am' && hour == 12) hour = 0;
    if (suffix == 'pm' && hour != 12) hour += 12;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  static List<int> normalizeScheduleDays(Object? value) {
    const aliases = <String, int>{
      '0': 0,
      'sun': 0,
      'sunday': 0,
      '1': 1,
      'mon': 1,
      'monday': 1,
      '2': 2,
      'tue': 2,
      'tues': 2,
      'tuesday': 2,
      '3': 3,
      'wed': 3,
      'wednesday': 3,
      '4': 4,
      'thu': 4,
      'thur': 4,
      'thurs': 4,
      'thursday': 4,
      '5': 5,
      'fri': 5,
      'friday': 5,
      '6': 6,
      'sat': 6,
      'saturday': 6,
    };
    final days = <int>{};
    for (final raw in _svList(value)) {
      final day = aliases[_svText(raw, max: 20).toLowerCase()];
      if (day == null) {
        throw const KorlixLiveConvoAgentEmailVoiceException(
          'Weekly schedules require explicit valid weekday names. '
          'No schedule was created and nothing was sent.',
          code: 'agent_email_schedule_voice_days_invalid',
        );
      }
      days.add(day);
    }
    if (days.isEmpty) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'Say every weekday for the weekly schedule. '
        'No schedule was created and nothing was sent.',
        code: 'agent_email_schedule_voice_days_required',
      );
    }
    final result = days.toList()..sort();
    return List<int>.unmodifiable(result);
  }

  static List<String> dayNames(Iterable<int> days) {
    const names = <String>[
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    final sorted = days.toSet().toList()..sort();
    if (sorted.isEmpty || sorted.any((day) => day < 0 || day > 6)) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'The prepared schedule contains invalid weekdays.',
        code: 'agent_email_schedule_voice_days_invalid',
      );
    }
    return List<String>.unmodifiable(sorted.map((day) => names[day]));
  }

  static String normalizeScheduledFor(
    Object? value, {
    DateTime? now,
    bool requireFuture = true,
  }) {
    final raw = _svText(value, max: 120);
    final parsed = DateTime.tryParse(raw);
    final offset = RegExp(
      r'(?:Z|[+-]\d{2}:\d{2})$',
      caseSensitive: false,
    ).hasMatch(raw);
    if (parsed == null || !offset) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'A one-time schedule requires an ISO-8601 date and time with a '
        'timezone offset. No schedule was created and nothing was sent.',
        code: 'agent_email_schedule_voice_timestamp_invalid',
      );
    }
    final utc = parsed.toUtc();
    if (requireFuture && !utc.isAfter((now ?? DateTime.now()).toUtc())) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'The one-time scheduled email must be in the future. '
        'No schedule was created and nothing was sent.',
        code: 'agent_email_schedule_voice_time_must_be_future',
      );
    }
    return utc.toIso8601String();
  }

  static String triggerKeyForCall(String callId) {
    var clean = _svText(callId, max: 180)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_.:-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^[-.:_]+|[-.:_]+$'), '');
    if (clean.isEmpty) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'The LIVE CONVO schedule request has no valid call ID.',
        code: 'agent_email_schedule_voice_call_id_required',
      );
    }
    const prefix = 'schedule.voice.';
    if (clean.length > 120 - prefix.length) {
      clean = clean.substring(0, 120 - prefix.length);
    }
    return '$prefix$clean';
  }

  static String defaultRuleName({
    required String scheduleType,
    required KorlixLiveConvoAgentEmailRecipient recipient,
  }) {
    final label = recipient.displayName.isEmpty
        ? recipient.email
        : recipient.displayName;
    return _svText(
      'Nova ${scheduleType == 'weekly' ? 'Weekly' : 'One-time'} email to $label',
      max: 200,
    );
  }
}

class KorlixLiveConvoAgentEmailScheduleVoiceClient {
  KorlixLiveConvoAgentEmailScheduleVoiceClient({
    required this.backendBaseUrl,
    required this.headersBuilder,
    http.Client? client,
    this.timeout = const Duration(seconds: 45),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final String backendBaseUrl;
  final KorlixLiveConvoAgentEmailHeadersBuilder headersBuilder;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  String _basePath(String agentId) {
    final clean = _svText(agentId, max: 96).toLowerCase();
    if (clean.isEmpty) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'Select the authorized Nova agent first. '
        'No schedule was created and nothing was sent.',
        code: 'agent_email_schedule_voice_agent_required',
      );
    }
    return '/api/live-convo/agents/${Uri.encodeComponent(clean)}/email';
  }

  Future<Map<String, dynamic>> _request({
    required String method,
    required String path,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final base = backendBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'The KORLIX backend is unavailable. No schedule was created.',
        code: 'agent_email_schedule_voice_backend_required',
      );
    }
    final headers = Map<String, String>.from(headersBuilder())
      ..['Accept'] = 'application/json';
    final signedIn = headers.entries.any(
      (entry) =>
          entry.key.toLowerCase() == 'authorization' &&
          entry.value.trim().toLowerCase().startsWith('bearer '),
    );
    if (!signedIn) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'Sign in to KORLIX before preparing a scheduled email. '
        'No schedule was created and nothing was sent.',
        code: 'agent_email_schedule_voice_sign_in_required',
        statusCode: 401,
      );
    }
    if (body != null) headers['Content-Type'] = 'application/json';

    try {
      final uri = Uri.parse('$base$path').replace(queryParameters: query);
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(timeout);
      Map<String, dynamic> payload = <String, dynamic>{};
      if (response.body.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(response.body);
          payload = _svMap(decoded) ?? <String, dynamic>{'data': decoded};
        } catch (_) {
          payload = <String, dynamic>{'message': response.body.trim()};
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw KorlixLiveConvoAgentEmailVoiceException(
          _svText(
            payload['message'] ?? payload['error'] ?? payload['detail'],
            max: 800,
            fallback: 'KORLIX could not complete the scheduled email request.',
          ),
          code: _svText(
            payload['code'] ?? payload['errorCode'],
            max: 120,
            fallback: 'agent_email_schedule_voice_request_failed',
          ),
          statusCode: response.statusCode,
        );
      }
      return payload;
    } on TimeoutException {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'The scheduled email request timed out. Review the Nova Email Control '
        'Center before retrying.',
        code: 'agent_email_schedule_voice_timeout',
        statusCode: 504,
      );
    }
  }

  List<Object?> _findList(Object? payload, String key, [int depth = 0]) {
    if (depth > 5) return const <Object?>[];
    if (payload is Iterable) return List<Object?>.from(payload);
    final map = _svMap(payload);
    if (map == null) return const <Object?>[];
    if (map[key] is Iterable) return List<Object?>.from(map[key] as Iterable);
    for (final nested in <String>['data', 'items', 'results', 'rows']) {
      final found = _findList(map[nested], key, depth + 1);
      if (found.isNotEmpty) return found;
    }
    return const <Object?>[];
  }

  Future<List<KorlixLiveConvoAgentEmailRecipient>> _approvedRecipients({
    required String agentId,
  }) async {
    final payload = await _request(
      method: 'GET',
      path: '${_basePath(agentId)}/recipients',
      query: const <String, String>{'limit': '100'},
    );
    final recipients = _findList(payload, 'recipients')
        .map(_svMap)
        .whereType<Map<String, dynamic>>()
        .map(KorlixLiveConvoAgentEmailRecipient.fromJson)
        .where((item) => item.id.isNotEmpty && item.email.isNotEmpty)
        .toList(growable: false);
    return List<KorlixLiveConvoAgentEmailRecipient>.unmodifiable(recipients);
  }

  Future<Map<String, dynamic>> prepareScheduleToolCall({
    required String agentId,
    required KorlixLiveConvoAgentEmailScheduleToolCall call,
    DateTime? now,
  }) async {
    try {
      if (call.recipient.isEmpty || call.subject.isEmpty || call.body.isEmpty) {
        throw const KorlixLiveConvoAgentEmailVoiceException(
          'Recipient, subject, and complete message are required. '
          'No schedule was created and nothing was sent.',
          code: 'agent_email_schedule_voice_content_required',
        );
      }
      final type =
          KorlixLiveConvoAgentEmailScheduleVoiceBridge.normalizeScheduleType(
            call.scheduleType,
          );
      final timezone =
          KorlixLiveConvoAgentEmailScheduleVoiceBridge.normalizeTimezone(
            call.scheduleTimezone,
          );
      final recipients = await _approvedRecipients(agentId: agentId);
      final recipient =
          KorlixLiveConvoAgentEmailVoiceBridge.selectApprovedRecipient(
            query: call.recipient,
            recipients: recipients,
          );
      final localTime = type == 'weekly'
          ? KorlixLiveConvoAgentEmailScheduleVoiceBridge.normalizeLocalTime(
              call.scheduleLocalTime,
            )
          : null;
      final days = type == 'weekly'
          ? KorlixLiveConvoAgentEmailScheduleVoiceBridge.normalizeScheduleDays(
              call.scheduleDays,
            )
          : const <int>[];
      final scheduledFor = type == 'once'
          ? KorlixLiveConvoAgentEmailScheduleVoiceBridge.normalizeScheduledFor(
              call.scheduledFor,
              now: now,
            )
          : null;
      final ruleName = call.ruleName.isNotEmpty
          ? call.ruleName
          : KorlixLiveConvoAgentEmailScheduleVoiceBridge.defaultRuleName(
              scheduleType: type,
              recipient: recipient,
            );
      final triggerKey =
          KorlixLiveConvoAgentEmailScheduleVoiceBridge.triggerKeyForCall(
            call.callId,
          );
      final description = type == 'once'
          ? 'one time at $scheduledFor in $timezone'
          : 'weekly on ${KorlixLiveConvoAgentEmailScheduleVoiceBridge.dayNames(days).join(', ')} '
                'at $localTime in $timezone';
      final label = recipient.displayName.isEmpty
          ? recipient.email
          : '${recipient.displayName} at ${recipient.email}';

      return <String, dynamic>{
        'success': true,
        'code': 'agent_email_schedule_voice_confirmation_required',
        'message':
            'A scheduled email for $label is prepared for $description. Read '
            'back the exact recipient, subject, message, and schedule, then '
            'ask for a separate yes or no. No schedule was created and '
            'nothing was sent.',
        'callId': call.callId,
        'recipientId': recipient.id,
        'recipientName': recipient.displayName,
        'recipientEmail': recipient.email,
        'ruleName': ruleName,
        'triggerKey': triggerKey,
        'subject': call.subject,
        'body': call.body,
        'scheduleType': type,
        'scheduleTimezone': timezone,
        'scheduleLocalTime': localTime,
        'scheduleDays': days,
        'scheduleDayNames': type == 'weekly'
            ? KorlixLiveConvoAgentEmailScheduleVoiceBridge.dayNames(days)
            : const <String>[],
        'scheduledFor': scheduledFor,
        'scheduleDescription': description,
        'pendingConfirmation': true,
        'ruleCreated': false,
        'scheduled': false,
        'sent': false,
        'nothingSent': true,
      };
    } on KorlixLiveConvoAgentEmailVoiceException catch (error) {
      return <String, dynamic>{
        'success': false,
        'code': error.code,
        'message': error.message,
        'statusCode': error.statusCode,
        'pendingConfirmation': false,
        'ruleCreated': false,
        'scheduled': false,
        'sent': false,
        'nothingSent': true,
      };
    } catch (error) {
      return <String, dynamic>{
        'success': false,
        'code': 'agent_email_schedule_voice_unexpected_error',
        'message':
            'KORLIX could not prepare the scheduled email: '
            '${_svText(error, max: 500)} No schedule was created and nothing '
            'was sent.',
        'ruleCreated': false,
        'scheduled': false,
        'sent': false,
        'nothingSent': true,
      };
    }
  }

  Future<Map<String, dynamic>> createApprovedSchedule({
    required KorlixLiveConvoAgentEmailPendingSchedule pending,
    DateTime? now,
  }) async {
    var started = false;
    var accepted = false;
    try {
      if (pending.isExpired(now)) {
        throw const KorlixLiveConvoAgentEmailVoiceException(
          'That spoken schedule confirmation expired. Ask Nova to prepare it '
          'again. No schedule was created and nothing was sent.',
          code: 'agent_email_schedule_voice_confirmation_expired',
        );
      }
      started = true;
      final payload = await _request(
        method: 'POST',
        path: '${_basePath(pending.agentId)}/rules',
        body: pending.toRuleBody(),
      );
      accepted = true;
      final rule =
          _svMap(payload['rule']) ?? _svMap(payload['data']) ?? payload;
      final sent =
          _svBool(payload['sent']) ||
          _svBool(rule['sent']) ||
          _svText(rule['sentAt']).isNotEmpty;
      if (sent) {
        throw const KorlixLiveConvoAgentEmailVoiceException(
          'The server returned an unsafe immediate-send result. Review the '
          'Nova Email Control Center immediately.',
          code: 'agent_email_schedule_voice_no_immediate_send_boundary_failed',
        );
      }
      if (!pending.matchesRule(rule)) {
        throw const KorlixLiveConvoAgentEmailVoiceException(
          'The saved rule response did not match the exact spoken schedule. '
          'Review the Nova Email Control Center before retrying.',
          code: 'agent_email_schedule_voice_created_rule_mismatch',
        );
      }
      final ruleId = _svText(rule['id'], max: 100);
      final nextRunAt = _svText(rule['nextRunAt'], max: 120);
      if (ruleId.isEmpty || nextRunAt.isEmpty) {
        throw const KorlixLiveConvoAgentEmailVoiceException(
          'KORLIX could not verify the saved schedule ID and next run time. '
          'Review the Nova Email Control Center before retrying.',
          code: 'agent_email_schedule_voice_created_rule_unverified',
        );
      }
      return <String, dynamic>{
        'success': true,
        'code': 'agent_email_schedule_voice_created',
        'message':
            'The exact ${pending.scheduleType == 'weekly' ? 'weekly' : 'one-time'} '
            'email schedule for ${pending.recipientEmail} was created and '
            'preapproved. No email was sent now.',
        'ruleId': ruleId,
        'recipientEmail': pending.recipientEmail,
        'ruleName': pending.ruleName,
        'subject': pending.subject,
        'body': pending.body,
        'scheduleType': pending.scheduleType,
        'scheduleTimezone': pending.scheduleTimezone,
        'scheduleLocalTime': pending.scheduleLocalTime,
        'scheduleDays': pending.scheduleDays,
        'scheduledFor': pending.scheduledFor,
        'nextRunAt': nextRunAt,
        'preapproved': true,
        'ruleCreated': true,
        'scheduled': true,
        'sent': false,
        'nothingSentNow': true,
      };
    } on KorlixLiveConvoAgentEmailVoiceException catch (error) {
      final status = error.statusCode ?? 0;
      final unknown =
          accepted ||
          (started &&
              (status == 0 ||
                  status >= 500 ||
                  error.code == 'agent_email_schedule_voice_timeout'));
      return <String, dynamic>{
        'success': false,
        'code': error.code,
        'message': unknown
            ? 'KORLIX could not confirm the final schedule-creation result. '
                  'Review the Nova Email Control Center before retrying.'
            : error.message,
        'statusCode': error.statusCode,
        'ruleCreated': false,
        'scheduled': false,
        'sent': false,
        'scheduleStatusUnknown': unknown,
        'retrySafe': !unknown,
      };
    } catch (error) {
      return <String, dynamic>{
        'success': false,
        'code': 'agent_email_schedule_voice_create_unexpected_error',
        'message': started
            ? 'KORLIX could not confirm the final schedule-creation result. '
                  'Review the Nova Email Control Center before retrying.'
            : 'KORLIX could not create the schedule. Nothing was sent.',
        'ruleCreated': false,
        'scheduled': false,
        'sent': false,
        'scheduleStatusUnknown': started,
        'retrySafe': !started,
      };
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

// K134B_LIVE_CONVO_AGENT_EMAIL_SCHEDULE_VOICE_V1_END
