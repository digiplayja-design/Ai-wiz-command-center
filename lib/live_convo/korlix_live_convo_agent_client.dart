import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'korlix_live_convo_agent.dart';

// KORLIX_LIVE_CONVO_AGENT_CLIENT_BUILD131_BEGIN

typedef KorlixLiveConvoAgentHeadersBuilder =
    Map<String, String> Function();

bool _korlixAgentClientBool(
  Object? value, {
  bool fallback = false,
}) {
  if (value is bool) {
    return value;
  }

  if (value is num) {
    return value != 0;
  }

  final normalized = (value ?? '')
      .toString()
      .trim()
      .toLowerCase();

  if (<String>{'true', 'yes', 'on', '1'}.contains(normalized)) {
    return true;
  }

  if (<String>{'false', 'no', 'off', '0'}.contains(normalized)) {
    return false;
  }

  return fallback;
}

int _korlixAgentClientInt(
  Object? value, {
  int fallback = 0,
  int minimum = 0,
}) {
  final parsed = value is int
      ? value
      : int.tryParse((value ?? '').toString().trim());

  if (parsed == null) {
    return fallback;
  }

  return parsed < minimum ? minimum : parsed;
}

Map<String, dynamic>? _korlixAgentClientMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }

  return null;
}

String _korlixAgentClientText(
  Object? value, {
  String fallback = '',
}) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? fallback : text;
}

DateTime? _korlixAgentClientDate(Object? value) {
  final text = (value ?? '').toString().trim();

  if (text.isEmpty) {
    return null;
  }

  return DateTime.tryParse(text)?.toUtc();
}

class KorlixLiveConvoAgentClientException implements Exception {
  const KorlixLiveConvoAgentClientException(
    this.message, {
    this.code,
    this.statusCode,
  });

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

class KorlixLiveConvoAgentCatalog {
  const KorlixLiveConvoAgentCatalog({
    required this.agents,
    required this.persistenceConfigured,
  });

  final List<KorlixLiveConvoAgent> agents;
  final bool persistenceConfigured;

  KorlixLiveConvoAgent? agentById(String agentId) {
    final normalized = agentId.trim().toLowerCase();

    for (final agent in agents) {
      if (agent.id == normalized) {
        return agent;
      }
    }

    return null;
  }

  factory KorlixLiveConvoAgentCatalog.fromJson(
    Map<String, dynamic> json,
  ) {
    final persistenceConfigured = _korlixAgentClientBool(
      json['persistenceConfigured'] ??
          json['persistence_configured'],
    );

    final parsed = <String, KorlixLiveConvoAgent>{};
    final rawAgents = json['agents'];

    if (rawAgents is Iterable<Object?>) {
      for (final rawAgent in rawAgents) {
        final map = _korlixAgentClientMap(rawAgent);

        if (map == null) {
          continue;
        }

        final agent = KorlixLiveConvoAgent.fromJson(map);

        if (agent.id.isNotEmpty) {
          parsed[agent.id] = agent.copyWith(
            persistenceConfigured:
                agent.persistenceConfigured ||
                persistenceConfigured,
          );
        }
      }
    }

    final result = <KorlixLiveConvoAgent>[];

    for (final fallback
        in KorlixLiveConvoAgent.builtInFallbacks) {
      result.add(
        parsed.remove(fallback.id) ??
            fallback.copyWith(
              persistenceConfigured:
                  persistenceConfigured,
            ),
      );
    }

    result.addAll(
      parsed.values.where(
        (agent) => agent.active,
      ),
    );

    return KorlixLiveConvoAgentCatalog(
      agents: List<KorlixLiveConvoAgent>.unmodifiable(result),
      persistenceConfigured: persistenceConfigured,
    );
  }

  static const KorlixLiveConvoAgentCatalog fallback =
      KorlixLiveConvoAgentCatalog(
        agents: KorlixLiveConvoAgent.builtInFallbacks,
        persistenceConfigured: false,
      );
}

class KorlixLiveConvoAgentVersion {
  const KorlixLiveConvoAgentVersion({
    required this.version,
    required this.source,
    required this.snapshot,
    this.createdAt,
  });

  final int version;
  final String source;
  final Map<String, dynamic> snapshot;
  final DateTime? createdAt;

  String get displayLabel {
    final cleanSource = source
        .replaceAll('_', ' ')
        .trim();

    return cleanSource.isEmpty
        ? 'Version $version'
        : 'Version $version — $cleanSource';
  }

  factory KorlixLiveConvoAgentVersion.fromJson(
    Map<String, dynamic> json,
  ) {
    return KorlixLiveConvoAgentVersion(
      version: _korlixAgentClientInt(
        json['version'],
        fallback: 1,
        minimum: 1,
      ),

      source: _korlixAgentClientText(
        json['source'],
        fallback: 'training update',
      ),

      snapshot: Map<String, dynamic>.unmodifiable(
        _korlixAgentClientMap(
              json['snapshot'],
            ) ??
            const <String, dynamic>{},
      ),

      createdAt: _korlixAgentClientDate(
        json['createdAt'] ??
            json['created_at'],
      ),
    );
  }
}

class KorlixLiveConvoAgentClient {
  KorlixLiveConvoAgentClient({
    required this.backendBaseUrl,
    required this.headersBuilder,
    http.Client? client,
    this.timeout = const Duration(seconds: 45),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final String backendBaseUrl;
  final KorlixLiveConvoAgentHeadersBuilder headersBuilder;
  final Duration timeout;

  final http.Client _client;
  final bool _ownsClient;

  String get _cleanBase {
    final clean = backendBaseUrl
        .trim()
        .replaceFirst(RegExp(r'/+$'), '');

    if (clean.isEmpty) {
      throw const KorlixLiveConvoAgentClientException(
        'The Korlix backend address is unavailable.',
        code: 'backend_address_unavailable',
      );
    }

    return clean;
  }

  Map<String, String> _requestHeaders({
    required bool hasJsonBody,
  }) {
    final headers = Map<String, String>.from(
      headersBuilder(),
    )
      ..removeWhere(
        (name, _) =>
            name.trim().toLowerCase() ==
            'content-type',
      )
      ..['Accept'] = 'application/json';

    if (hasJsonBody) {
      headers['Content-Type'] =
          'application/json; charset=utf-8';
    }

    return headers;
  }

  Uri _requestUri(
    String path, {
    Map<String, String>? queryParameters,
  }) {
    final uri = Uri.parse('$_cleanBase$path');

    final cleanQuery = <String, String>{};

    for (final entry
        in (queryParameters ?? const <String, String>{}).entries) {
      final value = entry.value.trim();

      if (value.isNotEmpty) {
        cleanQuery[entry.key] = value;
      }
    }

    return cleanQuery.isEmpty
        ? uri
        : uri.replace(
            queryParameters: cleanQuery,
          );
  }

  Map<String, dynamic>? _decodeResponse(
    http.Response response,
  ) {
    final body = response.body.trim();

    if (body.isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(body);

      return _korlixAgentClientMap(decoded);
    } catch (_) {
      return null;
    }
  }

  String _responseMessage(
    http.Response response,
    Map<String, dynamic>? decoded, {
    required String fallback,
  }) {
    final error = decoded?['error'];
    final message = decoded?['message'];

    if (error is String && error.trim().isNotEmpty) {
      return error.trim();
    }

    if (error is Map) {
      final nested =
          error['message'] ??
          error['error'] ??
          error['detail'];

      if (nested != null &&
          nested.toString().trim().isNotEmpty) {
        return nested.toString().trim();
      }
    }

    if (message != null &&
        message.toString().trim().isNotEmpty) {
      return message.toString().trim();
    }

    final body = response.body.trim();

    if (body.isNotEmpty &&
        body.length <= 300 &&
        !body.startsWith('<')) {
      return body;
    }

    return fallback;
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    required String fallbackError,
  }) async {
    final request = http.Request(
      method,
      _requestUri(
        path,
        queryParameters: queryParameters,
      ),
    );

    request.headers.addAll(
      _requestHeaders(
        hasJsonBody: body != null,
      ),
    );

    if (body != null) {
      request.body = jsonEncode(body);
    }

    late final http.StreamedResponse streamedResponse;

    try {
      streamedResponse = await _client
          .send(request)
          .timeout(timeout);
    } on TimeoutException {
      throw const KorlixLiveConvoAgentClientException(
        'The Agent Hub request timed out. Please try again.',
        code: 'agent_hub_timeout',
      );
    } on KorlixLiveConvoAgentClientException {
      rethrow;
    } catch (error) {
      throw KorlixLiveConvoAgentClientException(
        'Could not reach the Korlix Agent Hub: $error',
        code: 'agent_hub_network_error',
      );
    }

    final response =
        await http.Response.fromStream(streamedResponse);

    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw KorlixLiveConvoAgentClientException(
        _responseMessage(
          response,
          decoded,
          fallback: fallbackError,
        ),
        code: _korlixAgentClientText(
          decoded?['code'],
          fallback: 'agent_hub_request_failed',
        ),
        statusCode: response.statusCode,
      );
    }

    if (decoded == null) {
      throw const KorlixLiveConvoAgentClientException(
        'The Korlix Agent Hub returned an invalid response.',
        code: 'invalid_agent_hub_response',
      );
    }

    return decoded;
  }

  Map<String, dynamic> _requiredMap(
    Map<String, dynamic> response,
    String key, {
    required String errorMessage,
  }) {
    final map = _korlixAgentClientMap(
      response[key],
    );

    if (map == null) {
      throw KorlixLiveConvoAgentClientException(
        errorMessage,
        code: 'missing_agent_hub_payload',
      );
    }

    return map;
  }

  Future<KorlixLiveConvoAgentCatalog> loadCatalog() async {
    final response = await _requestJson(
      method: 'GET',
      path: KorlixLiveConvoAgentApiContract.catalogPath,
      fallbackError: 'Could not load LIVE CONVO agents.',
    );

    return KorlixLiveConvoAgentCatalog.fromJson(response);
  }

  Future<KorlixLiveConvoAgentModelProof>
  loadModelProof() async {
    final response = await _requestJson(
      method: 'GET',
      path: KorlixLiveConvoAgentApiContract.modelProofPath,
      fallbackError: 'Could not verify the LIVE CONVO models.',
    );

    final nested = _korlixAgentClientMap(
      response['modelProof'] ??
          response['model_proof'],
    );

    return KorlixLiveConvoAgentModelProof.fromJson(
      nested ?? response,
    );
  }

  Future<KorlixLiveConvoAgentRuntime> loadRuntime({
    required String agentId,
    required String characterName,
    required String language,
  }) async {
    final response = await _requestJson(
      method: 'GET',
      path: KorlixLiveConvoAgentApiContract.runtimePath(
        agentId,
      ),
      queryParameters: <String, String>{
        'characterName': characterName,
        'language': language,
      },
      fallbackError: 'Could not activate the selected agent.',
    );

    final runtime = _requiredMap(
      response,
      'runtime',
      errorMessage:
          'The selected agent returned no runtime configuration.',
    );

    return KorlixLiveConvoAgentRuntime.fromJson(runtime);
  }

  Future<KorlixLiveConvoAgent> createCustomAgent(
    KorlixLiveConvoCustomAgentDraft draft,
  ) async {
    final response = await _requestJson(
      method: 'POST',
      path: KorlixLiveConvoAgentApiContract.catalogPath,
      body: draft.toJson(),
      fallbackError: 'Could not create the custom agent.',
    );

    return KorlixLiveConvoAgent.fromJson(
      _requiredMap(
        response,
        'agent',
        errorMessage:
            'The custom-agent service returned no agent.',
      ),
    );
  }

  Future<KorlixLiveConvoAgent> updateAgent({
    required String agentId,
    required Map<String, dynamic> changes,
  }) async {
    final response = await _requestJson(
      method: 'PUT',
      path: KorlixLiveConvoAgentApiContract.agentPath(
        agentId,
      ),
      body: changes,
      fallbackError: 'Could not update the LIVE CONVO agent.',
    );

    return KorlixLiveConvoAgent.fromJson(
      _requiredMap(
        response,
        'agent',
        errorMessage:
            'The agent-update service returned no agent.',
      ),
    );
  }

  Future<KorlixLiveConvoAgent> saveTraining({
    required String agentId,
    required KorlixLiveConvoAgentTrainingUpdate update,
  }) async {
    if (!update.confirmed) {
      throw const KorlixLiveConvoAgentClientException(
        'Confirm the training before saving it.',
        code: 'training_confirmation_required',
      );
    }

    if (update.instructions.trim().isEmpty) {
      throw const KorlixLiveConvoAgentClientException(
        'Enter the training instructions first.',
        code: 'training_instructions_required',
      );
    }

    final response = await _requestJson(
      method: 'POST',
      path: KorlixLiveConvoAgentApiContract.trainingPath(
        agentId,
      ),
      body: update.toJson(),
      fallbackError: 'Could not save the agent training.',
    );

    return KorlixLiveConvoAgent.fromJson(
      _requiredMap(
        response,
        'agent',
        errorMessage:
            'The training service returned no updated agent.',
      ),
    );
  }

  Future<List<KorlixLiveConvoAgentMemory>> loadMemories({
    required String agentId,
  }) async {
    final response = await _requestJson(
      method: 'GET',
      path: KorlixLiveConvoAgentApiContract.memoriesPath(
        agentId,
      ),
      fallbackError: 'Could not load the agent memories.',
    );

    final rawMemories = response['memories'];
    final memories = <KorlixLiveConvoAgentMemory>[];

    if (rawMemories is Iterable<Object?>) {
      for (final rawMemory in rawMemories) {
        final map = _korlixAgentClientMap(rawMemory);

        if (map != null) {
          memories.add(
            KorlixLiveConvoAgentMemory.fromJson(map),
          );
        }
      }
    }

    return List<KorlixLiveConvoAgentMemory>.unmodifiable(
      memories,
    );
  }

  Future<KorlixLiveConvoAgentMemory> saveMemory({
    required String agentId,
    required KorlixLiveConvoMemoryDraft draft,
  }) async {
    if (!draft.confirmed) {
      throw const KorlixLiveConvoAgentClientException(
        'Confirm the memory before saving it.',
        code: 'memory_confirmation_required',
      );
    }

    if (draft.content.trim().isEmpty) {
      throw const KorlixLiveConvoAgentClientException(
        'Enter the memory content first.',
        code: 'memory_content_required',
      );
    }

    final response = await _requestJson(
      method: 'POST',
      path: KorlixLiveConvoAgentApiContract.memoriesPath(
        agentId,
      ),
      body: draft.toJson(),
      fallbackError: 'Could not save the long-term memory.',
    );

    return KorlixLiveConvoAgentMemory.fromJson(
      _requiredMap(
        response,
        'memory',
        errorMessage:
            'The memory service returned no saved memory.',
      ),
    );
  }

  Future<int> forgetMemories({
    required String agentId,
    required String query,
    required bool confirmed,
  }) async {
    final cleanQuery = query.trim();

    if (!confirmed) {
      throw const KorlixLiveConvoAgentClientException(
        'Confirm before forgetting agent memories.',
        code: 'forget_confirmation_required',
      );
    }

    if (cleanQuery.isEmpty) {
      throw const KorlixLiveConvoAgentClientException(
        'Describe the memory that should be forgotten.',
        code: 'memory_query_required',
      );
    }

    final response = await _requestJson(
      method: 'POST',
      path:
          KorlixLiveConvoAgentApiContract.forgetMemoryPath(
        agentId,
      ),
      body: <String, dynamic>{
        'confirmed': true,
        'query': cleanQuery,
      },
      fallbackError: 'Could not forget the matching memories.',
    );

    return _korlixAgentClientInt(
      response['removed'],
      minimum: 0,
    );
  }

  Future<void> deleteMemory({
    required String agentId,
    required String memoryId,
    required bool confirmed,
  }) async {
    if (!confirmed) {
      throw const KorlixLiveConvoAgentClientException(
        'Confirm before deleting this memory.',
        code: 'memory_delete_confirmation_required',
      );
    }

    await _requestJson(
      method: 'DELETE',
      path: KorlixLiveConvoAgentApiContract.memoryPath(
        agentId,
        memoryId,
      ),
      body: const <String, dynamic>{
        'confirmed': true,
      },
      fallbackError: 'Could not delete the memory.',
    );
  }

  Future<void> clearMemories({
    required String agentId,
    required bool confirmed,
  }) async {
    if (!confirmed) {
      throw const KorlixLiveConvoAgentClientException(
        'Confirm before clearing all agent memories.',
        code: 'memory_clear_confirmation_required',
      );
    }

    await _requestJson(
      method: 'DELETE',
      path: KorlixLiveConvoAgentApiContract.memoriesPath(
        agentId,
      ),
      body: const <String, dynamic>{
        'confirmed': true,
      },
      fallbackError: 'Could not clear the agent memories.',
    );
  }

  Future<List<KorlixLiveConvoAgentVersion>> loadVersions({
    required String agentId,
  }) async {
    final response = await _requestJson(
      method: 'GET',
      path: KorlixLiveConvoAgentApiContract.versionsPath(
        agentId,
      ),
      fallbackError:
          'Could not load the agent training history.',
    );

    final rawVersions = response['versions'];
    final versions = <KorlixLiveConvoAgentVersion>[];

    if (rawVersions is Iterable<Object?>) {
      for (final rawVersion in rawVersions) {
        final map = _korlixAgentClientMap(rawVersion);

        if (map != null) {
          versions.add(
            KorlixLiveConvoAgentVersion.fromJson(map),
          );
        }
      }
    }

    versions.sort(
      (left, right) =>
          right.version.compareTo(left.version),
    );

    return List<KorlixLiveConvoAgentVersion>.unmodifiable(
      versions,
    );
  }

  Future<KorlixLiveConvoAgent> restoreVersion({
    required String agentId,
    required int version,
    required bool confirmed,
  }) async {
    if (!confirmed) {
      throw const KorlixLiveConvoAgentClientException(
        'Confirm before restoring this training version.',
        code: 'version_restore_confirmation_required',
      );
    }

    final response = await _requestJson(
      method: 'POST',
      path:
          KorlixLiveConvoAgentApiContract.restoreVersionPath(
        agentId,
        version,
      ),
      body: const <String, dynamic>{
        'confirmed': true,
      },
      fallbackError:
          'Could not restore the selected training version.',
    );

    return KorlixLiveConvoAgent.fromJson(
      _requiredMap(
        response,
        'agent',
        errorMessage:
            'The restore service returned no updated agent.',
      ),
    );
  }

  Future<void> deleteOrResetAgent({
    required String agentId,
    required bool confirmed,
  }) async {
    if (!confirmed) {
      throw const KorlixLiveConvoAgentClientException(
        'Confirm before resetting or deleting this agent.',
        code: 'agent_delete_confirmation_required',
      );
    }

    await _requestJson(
      method: 'DELETE',
      path: KorlixLiveConvoAgentApiContract.agentPath(
        agentId,
      ),
      body: const <String, dynamic>{
        'confirmed': true,
      },
      fallbackError:
          'Could not reset or delete the selected agent.',
    );
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

// KORLIX_LIVE_CONVO_AGENT_CLIENT_BUILD131_END
