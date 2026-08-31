import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

typedef KorlixLiveConvoAgentEmailHeadersBuilder =
    Map<String, String> Function();

String _text(Object? value, {int maximum = 40000, String fallback = ''}) {
  final result = (value ?? '').toString().trim();

  if (result.isEmpty) {
    return fallback;
  }

  return result.length <= maximum ? result : result.substring(0, maximum);
}

bool _bool(Object? value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }

  if (value is num) {
    return value != 0;
  }

  final normalized = _text(value).toLowerCase();

  if (<String>{
    'true',
    '1',
    'yes',
    'on',
    'enabled',
    'active',
  }.contains(normalized)) {
    return true;
  }

  if (<String>{
    'false',
    '0',
    'no',
    'off',
    'disabled',
    'inactive',
  }.contains(normalized)) {
    return false;
  }

  return fallback;
}

Map<String, dynamic>? _map(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  return value is Map ? Map<String, dynamic>.from(value) : null;
}

String _nameKey(Object? value) {
  return _text(value, maximum: 320)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class KorlixLiveConvoAgentEmailVoiceException implements Exception {
  const KorlixLiveConvoAgentEmailVoiceException(
    this.message, {
    this.code = 'agent_email_voice_draft_failed',
    this.statusCode,
  });

  final String message;
  final String code;
  final int? statusCode;

  @override
  String toString() => message;
}

class KorlixLiveConvoAgentEmailToolCall {
  const KorlixLiveConvoAgentEmailToolCall({
    required this.callId,
    required this.name,
    required this.arguments,
  });

  final String callId;
  final String name;
  final Map<String, dynamic> arguments;

  String get recipient {
    return _text(
      arguments['recipient'] ??
          arguments['recipientName'] ??
          arguments['recipient_name'] ??
          arguments['email'],
      maximum: 320,
    );
  }

  String get subject {
    return _text(
      arguments['subject'] ?? arguments['subjectLine'],
      maximum: 200,
    );
  }

  String get body {
    return _text(
      arguments['body'] ??
          arguments['message'] ??
          arguments['textBody'] ??
          arguments['text_body'],
    );
  }

  static List<KorlixLiveConvoAgentEmailToolCall> fromResponseDone(
    Map<String, dynamic> response,
  ) {
    final rawOutput = response['output'];

    if (rawOutput is! Iterable) {
      return const <KorlixLiveConvoAgentEmailToolCall>[];
    }

    final calls = <KorlixLiveConvoAgentEmailToolCall>[];

    for (final raw in rawOutput) {
      final item = _map(raw);

      if (item == null) {
        continue;
      }

      final type = _text(item['type'], maximum: 80).toLowerCase();

      final name = _text(item['name'], maximum: 120);

      if (!<String>{'function_call', 'function'}.contains(type) ||
          name != KorlixLiveConvoAgentEmailVoiceBridge.toolName) {
        continue;
      }

      final callId = _text(
        item['call_id'] ?? item['callId'] ?? item['id'],
        maximum: 180,
      );

      if (callId.isEmpty) {
        continue;
      }

      Map<String, dynamic> arguments = const <String, dynamic>{};

      final rawArguments = item['arguments'];

      final directArguments = _map(rawArguments);

      if (directArguments != null) {
        arguments = directArguments;
      } else if (rawArguments is String && rawArguments.trim().isNotEmpty) {
        try {
          arguments =
              _map(jsonDecode(rawArguments)) ?? const <String, dynamic>{};
        } catch (_) {
          arguments = const <String, dynamic>{};
        }
      }

      calls.add(
        KorlixLiveConvoAgentEmailToolCall(
          callId: callId,
          name: KorlixLiveConvoAgentEmailVoiceBridge.toolName,
          arguments: Map<String, dynamic>.unmodifiable(arguments),
        ),
      );
    }

    return List<KorlixLiveConvoAgentEmailToolCall>.unmodifiable(calls);
  }
}

class KorlixLiveConvoAgentEmailRecipient {
  const KorlixLiveConvoAgentEmailRecipient({
    required this.id,
    required this.email,
    required this.displayName,
    required this.consentStatus,
    required this.active,
    this.unsubscribedAt,
    this.suppressedAt,
  });

  final String id;
  final String email;
  final String displayName;
  final String consentStatus;
  final bool active;
  final String? unsubscribedAt;
  final String? suppressedAt;

  bool get eligible {
    return active &&
        (unsubscribedAt == null || unsubscribedAt!.isEmpty) &&
        (suppressedAt == null || suppressedAt!.isEmpty) &&
        !<String>{
          'unsubscribed',
          'suppressed',
          'blocked',
          'revoked',
          'inactive',
          'rejected',
        }.contains(consentStatus.toLowerCase());
  }

  factory KorlixLiveConvoAgentEmailRecipient.fromJson(
    Map<String, dynamic> json,
  ) {
    final unsubscribed = _text(
      json['unsubscribedAt'] ?? json['unsubscribed_at'],
      maximum: 100,
    );

    final suppressed = _text(
      json['suppressedAt'] ?? json['suppressed_at'],
      maximum: 100,
    );

    return KorlixLiveConvoAgentEmailRecipient(
      id: _text(
        json['id'] ?? json['recipientId'] ?? json['recipient_id'],
        maximum: 100,
      ).toLowerCase(),

      email: _text(
        json['email'] ?? json['emailAddress'],
        maximum: 320,
      ).toLowerCase(),

      displayName: _text(
        json['displayName'] ??
            json['display_name'] ??
            json['name'] ??
            json['recipientName'],
        maximum: 160,
      ),

      consentStatus: _text(
        json['consentStatus'] ?? json['consent_status'] ?? json['status'],
        maximum: 80,
        fallback: 'transactional_only',
      ).toLowerCase(),

      active: _bool(
        json['active'] ?? json['isActive'] ?? json['is_active'],
        fallback: true,
      ),

      unsubscribedAt: unsubscribed.isEmpty ? null : unsubscribed,

      suppressedAt: suppressed.isEmpty ? null : suppressed,
    );
  }
}

class _RecipientScore {
  const _RecipientScore(this.recipient, this.score);

  final KorlixLiveConvoAgentEmailRecipient recipient;

  final int score;
}

class KorlixLiveConvoAgentEmailVoiceBridge {
  const KorlixLiveConvoAgentEmailVoiceBridge._();

  static const String toolName = 'create_agent_email_draft';

  static const Map<String, dynamic> toolDefinition = <String, dynamic>{
    'type': 'function',

    'name': toolName,

    'description':
        'Create one transactional Agent Email '
        'draft only when the user explicitly asks '
        'to draft or save an email. Match only an '
        'existing approved recipient. This action '
        'never adds a recipient, approves or sends '
        'a draft, changes settings, or triggers '
        'Autopilot.',

    'parameters': <String, dynamic>{
      'type': 'object',

      'properties': <String, dynamic>{
        'recipient': <String, dynamic>{
          'type': 'string',
          'description':
              'The exact approved recipient '
              'name or email address.',
        },

        'subject': <String, dynamic>{
          'type': 'string',
          'description': 'The email subject.',
        },

        'body': <String, dynamic>{
          'type': 'string',
          'description':
              'The complete transactional '
              'email message.',
        },
      },

      'required': <String>['recipient', 'subject', 'body'],

      'additionalProperties': false,
    },
  };

  static bool isAuthorized({
    required bool isCustom,
    required bool active,
    required Iterable<String> toolIds,
  }) {
    return isCustom &&
        active &&
        toolIds.any((tool) => tool.trim().toLowerCase() == 'agent_email');
  }

  static KorlixLiveConvoAgentEmailRecipient selectApprovedRecipient({
    required String query,
    required Iterable<KorlixLiveConvoAgentEmailRecipient> recipients,
  }) {
    final cleanQuery = _text(query, maximum: 320).toLowerCase();

    if (cleanQuery.isEmpty) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'Say the exact approved recipient '
        'name or email address.',
        code: 'agent_email_voice_recipient_required',
      );
    }

    final eligible = recipients
        .where((recipient) => recipient.eligible)
        .toList();

    if (eligible.isEmpty) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'No approved Agent Email recipient '
        'is available. Nothing was sent.',
        code: 'agent_email_voice_no_approved_recipients',
      );
    }

    if (cleanQuery.contains('@')) {
      final exact = eligible
          .where((recipient) => recipient.email.toLowerCase() == cleanQuery)
          .toList();

      if (exact.length == 1) {
        return exact.single;
      }

      throw const KorlixLiveConvoAgentEmailVoiceException(
        'That email address is not an '
        'active approved recipient. '
        'Nothing was sent.',
        code: 'agent_email_voice_recipient_not_found',
      );
    }

    final queryKey = _nameKey(cleanQuery);

    final queryTokens = queryKey
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toSet();

    final scored = <_RecipientScore>[];

    for (final recipient in eligible) {
      final nameKey = _nameKey(recipient.displayName);

      final nameTokens = nameKey
          .split(' ')
          .where((token) => token.isNotEmpty)
          .toSet();

      final localKey = _nameKey(recipient.email.split('@').first);

      var score = 0;

      if (nameKey.isNotEmpty && nameKey == queryKey) {
        score = 900;
      } else if (nameKey.startsWith('$queryKey ')) {
        score = 800;
      } else if (queryTokens.isNotEmpty &&
          queryTokens.every(nameTokens.contains)) {
        score = 700;
      } else if (localKey == queryKey) {
        score = 650;
      }

      if (score > 0) {
        scored.add(_RecipientScore(recipient, score));
      }
    }

    if (scored.isEmpty) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'I could not match that name to one '
        'approved recipient. Say the full '
        'approved name or email address. '
        'Nothing was sent.',
        code: 'agent_email_voice_recipient_not_found',
      );
    }

    scored.sort((left, right) => right.score.compareTo(left.score));

    final best = scored
        .where((candidate) => candidate.score == scored.first.score)
        .toList();

    if (best.length != 1) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'More than one approved recipient '
        'matches that name. Say the full '
        'email address. Nothing was sent.',
        code: 'agent_email_voice_recipient_ambiguous',
      );
    }

    return best.single.recipient;
  }

  static String idempotencyKeyForCall(String callId) {
    final clean = _text(callId, maximum: 160)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    if (clean.isEmpty) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'The LIVE CONVO email-draft request '
        'had no valid call ID. '
        'Nothing was sent.',
        code: 'agent_email_voice_call_id_required',
      );
    }

    return ('live-convo-agent-email-draft:'
        '$clean');
  }
}

class KorlixLiveConvoAgentEmailVoiceClient {
  KorlixLiveConvoAgentEmailVoiceClient({
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
    final clean = _text(agentId, maximum: 96).toLowerCase();

    if (clean.isEmpty) {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'Select the authorized Nova agent '
        'first. Nothing was sent.',
        code: 'agent_email_voice_agent_required',
      );
    }

    return ('/api/live-convo/agents/'
        '${Uri.encodeComponent(clean)}'
        '/email');
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
        'The KORLIX backend is unavailable. '
        'Nothing was sent.',
        code: 'agent_email_voice_backend_required',
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
        'Sign in to KORLIX before creating '
        'an Agent Email draft. '
        'Nothing was sent.',
        code: 'agent_email_voice_sign_in_required',
        statusCode: 401,
      );
    }

    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }

    final uri = Uri.parse('$base$path').replace(queryParameters: query);

    try {
      final request = http.Request(method, uri)..headers.addAll(headers);

      if (body != null) {
        request.body = jsonEncode(body);
      }

      final streamed = await _client.send(request).timeout(timeout);

      final response = await http.Response.fromStream(
        streamed,
      ).timeout(timeout);

      Map<String, dynamic> payload = <String, dynamic>{};

      if (response.body.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(response.body);

          payload = _map(decoded) ?? <String, dynamic>{'data': decoded};
        } catch (_) {
          payload = <String, dynamic>{'message': response.body.trim()};
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw KorlixLiveConvoAgentEmailVoiceException(
          _text(
            payload['message'] ?? payload['error'] ?? payload['detail'],
            maximum: 800,
            fallback:
                'KORLIX could not complete '
                'the Agent Email draft '
                'request. Nothing was sent.',
          ),
          code: _text(
            payload['code'] ?? payload['errorCode'] ?? payload['error_code'],
            maximum: 120,
            fallback: 'agent_email_voice_request_failed',
          ),
          statusCode: response.statusCode,
        );
      }

      return payload;
    } on TimeoutException {
      throw const KorlixLiveConvoAgentEmailVoiceException(
        'The Agent Email draft request '
        'timed out. Nothing was sent.',
        code: 'agent_email_voice_timeout',
        statusCode: 504,
      );
    }
  }

  List<Object?> _list(Object? payload, String key, [int depth = 0]) {
    if (depth > 5) {
      return const <Object?>[];
    }

    if (payload is Iterable) {
      return List<Object?>.from(payload);
    }

    final map = _map(payload);

    if (map == null) {
      return const <Object?>[];
    }

    if (map[key] is Iterable) {
      return List<Object?>.from(map[key] as Iterable);
    }

    for (final nestedKey in <String>['data', 'items', 'results', 'rows']) {
      final found = _list(map[nestedKey], key, depth + 1);

      if (found.isNotEmpty) {
        return found;
      }
    }

    return const <Object?>[];
  }

  Future<List<KorlixLiveConvoAgentEmailRecipient>> listApprovedRecipients({
    required String agentId,
  }) async {
    final payload = await _request(
      method: 'GET',
      path: '${_basePath(agentId)}/recipients',
      query: const <String, String>{'limit': '100'},
    );

    final recipients = _list(payload, 'recipients')
        .map(_map)
        .whereType<Map<String, dynamic>>()
        .map(KorlixLiveConvoAgentEmailRecipient.fromJson)
        .where(
          (recipient) => recipient.id.isNotEmpty && recipient.email.isNotEmpty,
        )
        .toList(growable: false);

    return List<KorlixLiveConvoAgentEmailRecipient>.unmodifiable(recipients);
  }

  Future<Map<String, dynamic>> executeDraftToolCall({
    required String agentId,
    required KorlixLiveConvoAgentEmailToolCall call,
  }) async {
    try {
      if (call.recipient.isEmpty) {
        throw const KorlixLiveConvoAgentEmailVoiceException(
          'Say the exact approved recipient '
          'name or email address.',
          code: 'agent_email_voice_recipient_required',
        );
      }

      if (call.subject.isEmpty) {
        throw const KorlixLiveConvoAgentEmailVoiceException(
          'Tell me the email subject before '
          'I create the draft.',
          code: 'agent_email_voice_subject_required',
        );
      }

      if (call.body.isEmpty) {
        throw const KorlixLiveConvoAgentEmailVoiceException(
          'Tell me the email message before '
          'I create the draft.',
          code: 'agent_email_voice_body_required',
        );
      }

      final recipients = await listApprovedRecipients(agentId: agentId);

      final recipient =
          KorlixLiveConvoAgentEmailVoiceBridge.selectApprovedRecipient(
            query: call.recipient,
            recipients: recipients,
          );

      final key = KorlixLiveConvoAgentEmailVoiceBridge.idempotencyKeyForCall(
        call.callId,
      );

      final payload = await _request(
        method: 'POST',

        path: '${_basePath(agentId)}/drafts',

        body: <String, dynamic>{
          'confirmed': true,
          'confirmation': true,

          'recipientId': recipient.id,

          'subject': call.subject,

          'textBody': call.body,

          'idempotencyKey': key,

          'marketing': false,

          'purpose': 'transactional',

          'source': 'live_convo_voice_draft',
        },
      );

      final draft = _map(payload['draft']) ?? payload;

      final status = _text(
        draft['status'],
        maximum: 40,
        fallback: 'draft',
      ).toLowerCase();

      final sent =
          _bool(payload['sent']) ||
          _bool(draft['sent']) ||
          status == 'sent' ||
          _text(draft['sentAt'] ?? draft['sent_at']).isNotEmpty;

      if (sent) {
        throw const KorlixLiveConvoAgentEmailVoiceException(
          'The server returned an unsafe '
          'send result for a draft-only '
          'action.',
          code: 'agent_email_voice_draft_only_boundary_failed',
        );
      }

      final replayed = _bool(payload['replayed']);

      final label = recipient.displayName.isEmpty
          ? recipient.email
          : ('${recipient.displayName} '
                'at ${recipient.email}');

      return <String, dynamic>{
        'success': true,

        'code': replayed
            ? 'agent_email_voice_draft_replayed'
            : 'agent_email_voice_draft_created',

        'message': replayed
            ? ('The existing matching draft '
                  'for $label is ready for '
                  'review. Nothing was sent.')
            : ('The email draft for $label '
                  'was created and is ready for '
                  'review. Nothing was sent.'),

        'draftId': _text(
          draft['id'] ?? draft['messageId'] ?? draft['message_id'],
          maximum: 100,
        ),

        'recipientName': recipient.displayName,

        'recipientEmail': recipient.email,

        'subject': call.subject,

        'status': status,

        'replayed': replayed,

        'sent': false,

        'nothingSent': true,
      };
    } on KorlixLiveConvoAgentEmailVoiceException catch (error) {
      return <String, dynamic>{
        'success': false,

        'code': error.code,

        'message': error.message.contains('Nothing was sent')
            ? error.message
            : ('${error.message} '
                  'Nothing was sent.'),

        'statusCode': error.statusCode,

        'sent': false,

        'nothingSent': true,
      };
    } catch (error) {
      return <String, dynamic>{
        'success': false,

        'code': 'agent_email_voice_unexpected_error',

        'message':
            'KORLIX could not create the '
            'Agent Email draft: '
            '${_text(error, maximum: 500)} '
            'Nothing was sent.',

        'sent': false,

        'nothingSent': true,
      };
    }
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
