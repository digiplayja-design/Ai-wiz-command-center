import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../live_convo/agent_studio_client.dart'
    show agentAccountScope, agentStudioKey;

typedef SocialMap = Map<String, dynamic>;
SocialMap socialMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : {};
List<SocialMap> socialItems(dynamic v) =>
    v is List ? v.map(socialMap).toList() : [];
String socialId() => agentStudioKey();

class SocialException implements Exception {
  const SocialException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class SocialClient extends ChangeNotifier {
  SocialClient({
    required this.baseUrl,
    required this.headersBuilder,
    this.sessionChanges,
    http.Client? client,
  }) : _http = client ?? http.Client(),
       _owns = client == null {
    _scope = agentAccountScope(headersBuilder());
    sessionChanges?.addListener(_check);
  }
  final String baseUrl;
  final Map<String, String> Function() headersBuilder;
  final Listenable? sessionChanges;
  final http.Client _http;
  final bool _owns;
  final String callDevice = socialId();
  late final String _scope;
  bool _closed = false, _denied = false;
  bool get available => !_closed && !_denied;

  /// Notify active media controllers before a session owner replaces or
  /// disposes this client. Disposing a ChangeNotifier alone emits no event.
  void invalidateSession() {
    if (_closed || _denied) return;
    _denied = true;
    notifyListeners();
  }

  void _check() {
    if (!_closed &&
        !_denied &&
        (_scope.isEmpty || _scope != agentAccountScope(headersBuilder()))) {
      invalidateSession();
    }
  }

  void _guard() {
    _check();
    if (!available) {
      throw const SocialException(
        'Your session changed. Sign in and reopen KORLIX Social.',
        401,
      );
    }
  }

  Future<SocialMap> get(String action, [SocialMap data = const {}]) =>
      _request('GET', action, data);
  Future<SocialMap> post(String action, [SocialMap data = const {}]) =>
      _request('POST', action, data);
  Future<SocialMap> _request(
    String method,
    String action,
    SocialMap data,
  ) async {
    _guard();
    final uri = Uri.parse(
      '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/social/$action',
    );
    final request =
        http.Request(
            method,
            method == 'GET'
                ? uri.replace(
                    queryParameters: data.map((k, v) => MapEntry(k, '$v')),
                  )
                : uri,
          )
          ..headers.addAll({
            ...headersBuilder(),
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          });
    if (method == 'POST') request.body = jsonEncode(data);
    return _send(request);
  }

  Future<SocialMap> uploadPhoto(Uint8List bytes) async {
    _guard();
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
      throw const SocialException('Choose a photo smaller than 8 MB.');
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
        '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/social/profile_photo',
      ),
    );
    request.headers.addEntries(
      headersBuilder().entries.where(
        (entry) => entry.key.toLowerCase() != 'content-type',
      ),
    );
    request.headers['Accept'] = 'application/json';
    request.files.add(
      http.MultipartFile.fromBytes('photo', bytes, filename: 'profile-photo'),
    );
    return _send(request);
  }

  Future<SocialMap> uploadAlbumPhoto({
    required String album,
    required String id,
    required Uint8List bytes,
  }) async {
    _guard();
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
      throw const SocialException('Choose a photo smaller than 8 MB.');
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
        '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/social/album_upload',
      ).replace(queryParameters: {'album': album, 'photo': id}),
    );
    request.headers.addEntries(
      headersBuilder().entries.where(
        (e) => e.key.toLowerCase() != 'content-type',
      ),
    );
    request.files.add(
      http.MultipartFile.fromBytes('photo', bytes, filename: 'album-photo'),
    );
    return _send(request, timeout: const Duration(seconds: 120));
  }

  Future<SocialMap> uploadAttachment({
    required Uint8List bytes,
    required String filename,
    required String kind,
    required String id,
    required SocialMap destination,
  }) async {
    _guard();
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      throw const SocialException('Choose an attachment smaller than 20 MB.');
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
        '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/social/attachment_upload',
      ).replace(
        queryParameters: {
          'id': id,
          'kind': kind,
          ...destination.map((k, v) => MapEntry(k, '$v')),
        },
      ),
    );
    request.headers.addEntries(
      headersBuilder().entries.where(
        (e) => e.key.toLowerCase() != 'content-type',
      ),
    );
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    return _send(request, timeout: const Duration(seconds: 120));
  }

  Future<SocialMap> _send(
    http.BaseRequest request, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
      _guard();
      if (response.statusCode == 401) {
        _denied = true;
        notifyListeners();
      }
      SocialMap result;
      try {
        result = socialMap(jsonDecode(utf8.decode(response.bodyBytes)));
      } catch (_) {
        throw const SocialException(
          'The response could not be read. Refresh and try again.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SocialException(
          result['error']?.toString() ??
              'KORLIX Social is unavailable. Try again.',
          response.statusCode,
        );
      }
      return result;
    } on TimeoutException {
      _guard();
      throw const SocialException(
        'Still waiting for a response. Refresh before retrying.',
      );
    } on http.ClientException {
      _guard();
      throw const SocialException('Check your connection and refresh.');
    }
  }

  @override
  void dispose() {
    _closed = true;
    sessionChanges?.removeListener(_check);
    if (_owns) _http.close();
    super.dispose();
  }
}
