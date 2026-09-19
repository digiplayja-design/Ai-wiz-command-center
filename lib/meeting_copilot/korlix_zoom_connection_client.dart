import 'dart:convert';

typedef KorlixZoomHeadersBuilder = Future<Map<String, String>> Function();

typedef KorlixZoomJsonTransport =
    Future<KorlixZoomTransportResponse> Function({
      required String method,
      required Uri uri,
      required Map<String, String> headers,
      Object? body,
    });

class KorlixZoomTransportResponse {
  const KorlixZoomTransportResponse({
    required this.statusCode,
    required this.body,
    this.headers = const <String, String>{},
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;

  Map<String, dynamic> decodeObject() {
    final dynamic decoded = jsonDecode(body.isEmpty ? '{}' : body);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }

    throw const FormatException('Expected a JSON object.');
  }
}

class KorlixZoomApiException implements Exception {
  const KorlixZoomApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() =>
      'KorlixZoomApiException('
      '$statusCode, $code, $message)';
}

class KorlixZoomAuthorizationStart {
  const KorlixZoomAuthorizationStart({
    required this.authorizationUri,
    this.expiresAt,
  });

  final Uri authorizationUri;
  final DateTime? expiresAt;
}

class KorlixZoomConnectionStatus {
  const KorlixZoomConnectionStatus({
    required this.connected,
    required this.requiresReauthorization,
    required this.accessTokenExpired,
    this.scope = '',
    this.expiresAt,
    this.connectedAt,
    this.zoomAccountId,
    this.zoomUserId,
  });

  factory KorlixZoomConnectionStatus.fromJson(Map<String, dynamic> json) {
    return KorlixZoomConnectionStatus(
      connected: json['connected'] == true,
      requiresReauthorization:
          (json['requiresReauthorization'] ??
              json['requires_reauthorization']) ==
          true,
      accessTokenExpired:
          (json['accessTokenExpired'] ?? json['access_token_expired']) == true,
      scope: (json['scope'] ?? '').toString(),
      expiresAt: DateTime.tryParse(
        (json['expiresAt'] ?? json['expires_at'] ?? '').toString(),
      ),
      connectedAt: DateTime.tryParse(
        (json['connectedAt'] ?? json['connected_at'] ?? '').toString(),
      ),
      zoomAccountId: _nullableString(
        json['zoomAccountId'] ?? json['zoom_account_id'],
      ),
      zoomUserId: _nullableString(json['zoomUserId'] ?? json['zoom_user_id']),
    );
  }

  final bool connected;
  final bool requiresReauthorization;
  final bool accessTokenExpired;
  final String scope;
  final DateTime? expiresAt;
  final DateTime? connectedAt;
  final String? zoomAccountId;
  final String? zoomUserId;
}

class KorlixZoomMeetingSummary {
  const KorlixZoomMeetingSummary({
    required this.id,
    required this.topic,
    required this.isHost,
    this.uuid,
    this.startTime,
    this.durationMinutes,
    this.timezone,
    this.type,
    this.isAllDay = false,
  });

  factory KorlixZoomMeetingSummary.fromJson(Map<String, dynamic> json) {
    final String id = (json['id'] ?? '').toString().trim();
    final String topic = (json['topic'] ?? '').toString().trim();
    if (id.isEmpty || topic.isEmpty) {
      throw const KorlixZoomApiException(
        statusCode: 502,
        code: 'ZOOM_MEETING_RESPONSE_INVALID',
        message: 'The backend returned an invalid Zoom meeting record.',
      );
    }
    return KorlixZoomMeetingSummary(
      id: id,
      uuid: _nullableString(json['uuid']),
      topic: topic,
      startTime: DateTime.tryParse(
        (json['startTime'] ?? json['start_time'] ?? '').toString(),
      ),
      durationMinutes: _nullableInt(
        json['durationMinutes'] ?? json['duration_minutes'],
      ),
      timezone: _nullableString(json['timezone']),
      type: _nullableInt(json['type']),
      isHost: (json['isHost'] ?? json['is_host']) == true,
      isAllDay: (json['isAllDay'] ?? json['is_all_day']) == true,
    );
  }

  final String id;
  final String? uuid;
  final String topic;
  final DateTime? startTime;
  final int? durationMinutes;
  final String? timezone;
  final int? type;
  final bool isHost;
  final bool isAllDay;
}

class KorlixZoomConnectionClient {
  KorlixZoomConnectionClient({
    required this.backendBaseUri,
    required this.headersBuilder,
    required this.transport,
    this.agentId,
    this.stillCurrent,
    this.timeout = const Duration(seconds: 15),
  });

  static const String oauthStartPath = '/api/k135z/zoom/oauth/start';

  static const String statusPath = '/api/k135z/zoom/status';

  static const String connectionPath = '/api/k135z/zoom/connection';

  static const String upcomingMeetingsPath =
      '/api/k135z/zoom/'
      'meetings/upcoming';

  final Uri backendBaseUri;

  final KorlixZoomHeadersBuilder headersBuilder;

  final KorlixZoomJsonTransport transport;
  final String? agentId;
  final bool Function()? stillCurrent;
  final Duration timeout;

  void _checkCurrent() {
    if (stillCurrent != null && !stillCurrent!()) {
      throw const KorlixZoomApiException(statusCode: 409,
          code: 'K135Z_CONTEXT_CHANGED', message: 'Reopen Copilot from Agent Hub.');
    }
  }

  Future<KorlixZoomAuthorizationStart> beginAuthorization({
    Uri? returnTo,
  }) async {
    final Map<String, String> query = <String, String>{
      if (returnTo != null) 'return_to': returnTo.toString(),
    };

    final Map<String, dynamic> payload = await _request(
      method: 'GET',
      path: oauthStartPath,
      queryParameters: query,
    );

    final Uri? authorizationUri = Uri.tryParse(
      (payload['authorization_url'] ?? '').toString(),
    );

    if (authorizationUri == null || authorizationUri.scheme != 'https' ||
        !(authorizationUri.host == 'zoom.us' || authorizationUri.host.endsWith('.zoom.us')) ||
        authorizationUri.port != 443 || authorizationUri.userInfo.isNotEmpty ||
        authorizationUri.path != '/oauth/authorize' || authorizationUri.hasFragment ||
        (authorizationUri.queryParameters['state'] ?? '').isEmpty) {
      throw const KorlixZoomApiException(
        statusCode: 502,
        code: 'ZOOM_AUTHORIZATION_URL_INVALID',
        message:
            'The backend did not return '
            'a secure Zoom authorization URL.',
      );
    }

    return KorlixZoomAuthorizationStart(
      authorizationUri: authorizationUri,

      expiresAt: DateTime.tryParse((payload['expires_at'] ?? '').toString()),
    );
  }

  Future<KorlixZoomConnectionStatus> getStatus() async {
    final Map<String, dynamic> payload = await _request(
      method: 'GET',
      path: statusPath,
    );

    final dynamic value = payload['status'];

    if (value is! Map) {
      throw const KorlixZoomApiException(
        statusCode: 502,
        code: 'ZOOM_STATUS_RESPONSE_INVALID',
        message:
            'The backend returned an '
            'invalid Zoom status response.',
      );
    }

    return KorlixZoomConnectionStatus.fromJson(
      Map<String, dynamic>.from(value),
    );
  }

  Future<List<KorlixZoomMeetingSummary>> listUpcomingMeetings() async {
    final Map<String, dynamic> payload = await _request(
      method: 'GET',
      path: upcomingMeetingsPath,
    );

    final dynamic values = payload['meetings'];

    if (values is! List) {
      throw const KorlixZoomApiException(
        statusCode: 502,
        code: 'ZOOM_MEETINGS_RESPONSE_INVALID',
        message: 'The backend returned an invalid upcoming-meetings response.',
      );
    }

    final List<KorlixZoomMeetingSummary> meetings =
        <KorlixZoomMeetingSummary>[];
    for (final dynamic value in values) {
      if (value is! Map) {
        throw const KorlixZoomApiException(
          statusCode: 502,
          code: 'ZOOM_MEETING_RESPONSE_INVALID',
          message: 'The backend returned an invalid Zoom meeting record.',
        );
      }
      meetings.add(
        KorlixZoomMeetingSummary.fromJson(Map<String, dynamic>.from(value)),
      );
    }
    return List<KorlixZoomMeetingSummary>.unmodifiable(meetings);
  }

  Future<bool> disconnect() async {
    final Map<String, dynamic> payload = await _request(
      method: 'DELETE',
      path: connectionPath,
    );

    return payload['ok'] == true;
  }

  Future<Map<String, dynamic>> _request({
    required String method,
    required String path,

    Map<String, String> queryParameters = const <String, String>{},

    Object? body,
  }) async {
    _checkCurrent();
    final selected = agentId;
    if (selected == null || selected.trim() != selected || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(selected)) {
      throw const KorlixZoomApiException(statusCode: 400,
          code: 'KORLIX_AGENT_SELECTION_REQUIRED', message: 'Select an active agent first.');
    }
    if (backendBaseUri.scheme != 'https' || backendBaseUri.host.isEmpty ||
        backendBaseUri.userInfo.isNotEmpty || backendBaseUri.hasQuery || backendBaseUri.hasFragment) {
      throw const KorlixZoomApiException(statusCode: 400,
          code: 'K135Z_BACKEND_ADDRESS_INVALID', message: 'A secure backend address is required.');
    }
    final supplied = await headersBuilder().timeout(timeout);
    _checkCurrent();
    final headers = <String, String>{};
    for (final entry in supplied.entries) {
      final name = entry.key.toLowerCase();
      if (headers.containsKey(name) || entry.value.contains('\r') || entry.value.contains('\n')) {
        throw const KorlixZoomApiException(statusCode: 400,
            code: 'K135Z_HEADERS_INVALID', message: 'Request headers are invalid.');
      }
      headers[name] = entry.value;
    }
    if (!RegExp(r'^Bearer [^\s]+$', caseSensitive: false).hasMatch(headers['authorization'] ?? '')) {
      throw const KorlixZoomApiException(statusCode: 401,
          code: 'KORLIX_AUTH_REQUIRED', message: 'Sign in before connecting Zoom.');
    }
    for (final value in <String?>[headers['x-korlix-agent-id'],
        queryParameters['agent_id'], queryParameters['agentId']]) {
      if (value != null && value != selected) {
        throw const KorlixZoomApiException(statusCode: 400,
            code: 'KORLIX_AGENT_SELECTION_REQUIRED', message: 'Agent selection conflicts.');
      }
    }
    headers['accept'] = 'application/json';
    if (body != null) headers['content-type'] = 'application/json';
    final boundQuery = <String, String>{...queryParameters, 'agent_id': selected};

    final Uri uri = backendBaseUri
        .resolve(path)
        .replace(
          queryParameters: boundQuery,
        );

    final KorlixZoomTransportResponse response = await transport(
      method: method,
      uri: uri,
      headers: headers,
      body: body,
    ).timeout(timeout);
    _checkCurrent();

    final Map<String, dynamic> payload = response.decodeObject();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final dynamic errorValue = payload['error'];

      final Map<String, dynamic> error = errorValue is Map
          ? Map<String, dynamic>.from(errorValue)
          : const <String, dynamic>{};

      throw KorlixZoomApiException(
        statusCode: response.statusCode,

        code: (error['code'] ?? 'K135Z_ZOOM_REQUEST_FAILED').toString(),

        message:
            (error['message'] ??
                    'The Zoom integration '
                        'request failed.')
                .toString(),
      );
    }

    return payload;
  }
}

String? _nullableString(dynamic value) {
  final String normalized = (value ?? '').toString().trim();

  return normalized.isEmpty ? null : normalized;
}

int? _nullableInt(dynamic value) {
  if (value is int) {
    return value;
  }

  return int.tryParse((value ?? '').toString());
}
