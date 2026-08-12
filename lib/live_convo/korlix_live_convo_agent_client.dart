import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'korlix_live_convo_agent.dart';
import 'korlix_live_convo_brain_vault.dart';

// KORLIX_LIVE_CONVO_AGENT_CLIENT_BUILD131_BEGIN

typedef KorlixLiveConvoAgentHeadersBuilder = Map<String, String> Function();

bool _korlixAgentClientBool(Object? value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }

  if (value is num) {
    return value != 0;
  }

  final normalized = (value ?? '').toString().trim().toLowerCase();

  if (<String>{'true', 'yes', 'on', '1'}.contains(normalized)) {
    return true;
  }

  if (<String>{'false', 'no', 'off', '0'}.contains(normalized)) {
    return false;
  }

  return fallback;
}

int _korlixAgentClientInt(Object? value, {int fallback = 0, int minimum = 0}) {
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

String _korlixAgentClientText(Object? value, {String fallback = ''}) {
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

  factory KorlixLiveConvoAgentCatalog.fromJson(Map<String, dynamic> json) {
    final persistenceConfigured = _korlixAgentClientBool(
      json['persistenceConfigured'] ?? json['persistence_configured'],
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
                agent.persistenceConfigured || persistenceConfigured,
          );
        }
      }
    }

    final result = <KorlixLiveConvoAgent>[];

    for (final fallback in KorlixLiveConvoAgent.builtInFallbacks) {
      result.add(
        parsed.remove(fallback.id) ??
            fallback.copyWith(persistenceConfigured: persistenceConfigured),
      );
    }

    result.addAll(parsed.values.where((agent) => agent.active));

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
    final cleanSource = source.replaceAll('_', ' ').trim();

    return cleanSource.isEmpty
        ? 'Version $version'
        : 'Version $version — $cleanSource';
  }

  factory KorlixLiveConvoAgentVersion.fromJson(Map<String, dynamic> json) {
    return KorlixLiveConvoAgentVersion(
      version: _korlixAgentClientInt(json['version'], fallback: 1, minimum: 1),

      source: _korlixAgentClientText(
        json['source'],
        fallback: 'training update',
      ),

      snapshot: Map<String, dynamic>.unmodifiable(
        _korlixAgentClientMap(json['snapshot']) ?? const <String, dynamic>{},
      ),

      createdAt: _korlixAgentClientDate(
        json['createdAt'] ?? json['created_at'],
      ),
    );
  }
}

// KORLIX_AGENT_FILE_MEMORY_CLIENT_MODELS_BUILD131_V1_BEGIN

class KorlixLiveConvoAgentMemoryFileUpload {
  KorlixLiveConvoAgentMemoryFileUpload({
    required String name,
    required Uint8List bytes,
  }) : name = _cleanName(name),
       bytes = Uint8List.fromList(bytes);

  static const List<String> allowedExtensions = <String>[
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'csv',
    'txt',
    'md',
    'rtf',
    'ppt',
    'pptx',
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  static const int maximumFiles = 5;
  static const int maximumBytesPerFile = 10 * 1024 * 1024;

  final String name;
  final Uint8List bytes;

  int get sizeBytes => bytes.length;

  String get extension {
    final match = RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(name);
    return match?.group(1)?.toLowerCase() ?? '';
  }

  String get dedupeKey => '${name.toLowerCase()}|$sizeBytes';

  static String _cleanName(String value) {
    final clean = value.trim().replaceAll(
      RegExp(r'[\\/:*?"<>|\u0000-\u001F]'),
      '_',
    );
    return clean.isEmpty ? 'Source file' : clean;
  }
}

class KorlixLiveConvoAgentMemoryFileMetadata {
  const KorlixLiveConvoAgentMemoryFileMetadata({
    required this.fileName,
    required this.extension,
    required this.mimeType,
    required this.sizeBytes,
    required this.sha256,
    required this.detectedSignature,
    required this.isImage,
  });

  final String fileName;
  final String extension;
  final String mimeType;
  final int sizeBytes;
  final String sha256;
  final String detectedSignature;
  final bool isImage;

  factory KorlixLiveConvoAgentMemoryFileMetadata.fromJson(
    Map<String, dynamic> json,
  ) {
    return KorlixLiveConvoAgentMemoryFileMetadata(
      fileName: _korlixAgentClientText(
        json['fileName'] ?? json['file_name'],
        fallback: 'Source file',
      ),
      extension: _korlixAgentClientText(json['extension']).toLowerCase(),
      mimeType: _korlixAgentClientText(json['mimeType'] ?? json['mime_type']),
      sizeBytes: _korlixAgentClientInt(
        json['sizeBytes'] ?? json['size_bytes'] ?? json['size'],
        minimum: 0,
      ),
      sha256: _korlixAgentClientText(json['sha256']).toLowerCase(),
      detectedSignature: _korlixAgentClientText(
        json['detectedSignature'] ?? json['detected_signature'],
      ).toLowerCase(),
      isImage: _korlixAgentClientBool(json['isImage'] ?? json['is_image']),
    );
  }
}

class KorlixLiveConvoAgentMemoryFileProvenance {
  const KorlixLiveConvoAgentMemoryFileProvenance({
    required this.sourceIndex,
    required this.fileName,
    required this.extension,
    required this.mimeType,
    required this.sizeBytes,
    required this.sha256,
    this.page,
    this.sheet,
    this.row,
    this.slide,
    this.region,
  });

  final int sourceIndex;
  final String fileName;
  final String extension;
  final String mimeType;
  final int sizeBytes;
  final String sha256;
  final String? page;
  final String? sheet;
  final String? row;
  final String? slide;
  final String? region;

  factory KorlixLiveConvoAgentMemoryFileProvenance.fromJson(
    Map<String, dynamic> json,
  ) {
    String? optionalText(Object? value) {
      final clean = _korlixAgentClientText(value);
      return clean.isEmpty ? null : clean;
    }

    return KorlixLiveConvoAgentMemoryFileProvenance(
      sourceIndex: _korlixAgentClientInt(
        json['sourceIndex'] ?? json['source_index'],
        minimum: 0,
      ),
      fileName: _korlixAgentClientText(
        json['fileName'] ?? json['file_name'],
        fallback: 'Source file',
      ),
      extension: _korlixAgentClientText(json['extension']).toLowerCase(),
      mimeType: _korlixAgentClientText(json['mimeType'] ?? json['mime_type']),
      sizeBytes: _korlixAgentClientInt(
        json['sizeBytes'] ?? json['size_bytes'] ?? json['size'],
        minimum: 0,
      ),
      sha256: _korlixAgentClientText(json['sha256']).toLowerCase(),
      page: optionalText(json['page']),
      sheet: optionalText(json['sheet']),
      row: optionalText(json['row']),
      slide: optionalText(json['slide']),
      region: optionalText(json['region']),
    );
  }

  String get sourceLine {
    final parts = <String>['Source file: $fileName'];

    if (page != null) {
      parts.add('Page $page');
    }

    if (sheet != null) {
      parts.add('Sheet $sheet');
    }

    if (row != null) {
      parts.add('Row $row');
    }

    if (slide != null) {
      parts.add('Slide $slide');
    }

    if (region != null) {
      parts.add('Region $region');
    }

    if (mimeType.isNotEmpty) {
      parts.add('MIME: $mimeType');
    }

    if (sha256.isNotEmpty) {
      parts.add('SHA-256: $sha256');
    }

    return '[${parts.join(' | ')}]';
  }

  String get locationLabel {
    final parts = <String>[];

    if (page != null) {
      parts.add('Page $page');
    }

    if (sheet != null) {
      parts.add('Sheet $sheet');
    }

    if (row != null) {
      parts.add('Row $row');
    }

    if (slide != null) {
      parts.add('Slide $slide');
    }

    if (region != null) {
      parts.add('Region $region');
    }

    return parts.join(' · ');
  }
}

class KorlixLiveConvoAgentMemoryFileSuggestion {
  const KorlixLiveConvoAgentMemoryFileSuggestion({
    required this.id,
    required this.draft,
    required this.provenance,
  });

  final String id;
  final KorlixLiveConvoMemoryDraft draft;
  final KorlixLiveConvoAgentMemoryFileProvenance provenance;

  factory KorlixLiveConvoAgentMemoryFileSuggestion.fromJson(
    Map<String, dynamic> json,
  ) {
    final draftMap =
        _korlixAgentClientMap(json['draft']) ?? const <String, dynamic>{};

    final provenanceMap =
        _korlixAgentClientMap(json['provenance']) ?? const <String, dynamic>{};

    final rawTags = draftMap['tags'];
    final tags = <String>[];
    final seen = <String>{};

    if (rawTags is Iterable<Object?>) {
      for (final value in rawTags) {
        final clean = _korlixAgentClientText(value);

        if (clean.isEmpty || !seen.add(clean.toLowerCase())) {
          continue;
        }

        tags.add(clean.length <= 48 ? clean : clean.substring(0, 48));

        if (tags.length >= 12) {
          break;
        }
      }
    }

    final rawImportance = _korlixAgentClientInt(
      draftMap['importance'],
      fallback: 3,
      minimum: 1,
    );

    final importance = rawImportance > 5 ? 5 : rawImportance;

    return KorlixLiveConvoAgentMemoryFileSuggestion(
      id: _korlixAgentClientText(
        json['id'],
        fallback: 'file-memory-suggestion',
      ),
      draft: KorlixLiveConvoMemoryDraft(
        content: _korlixAgentClientText(draftMap['content']),
        confirmed: false,
        kind: _korlixAgentClientText(draftMap['kind'], fallback: 'fact'),
        label: _korlixAgentClientText(draftMap['label']),
        tags: List<String>.unmodifiable(tags),
        importance: importance,
        sensitive: _korlixAgentClientBool(draftMap['sensitive']),
        source: _korlixAgentClientText(
          draftMap['source'],
          fallback: 'file_memory',
        ),
      ),
      provenance: KorlixLiveConvoAgentMemoryFileProvenance.fromJson(
        provenanceMap,
      ),
    );
  }

  String get editableContent {
    return draft.content
        .replaceFirst(RegExp(r'\s*\[Source file:[^\]]+\]\s*$'), '')
        .trim();
  }

  KorlixLiveConvoAgentMemoryFileSuggestion copyWithDraft(
    KorlixLiveConvoMemoryDraft value,
  ) {
    return KorlixLiveConvoAgentMemoryFileSuggestion(
      id: id,
      draft: value,
      provenance: provenance,
    );
  }

  KorlixLiveConvoMemoryDraft confirmedDraft() {
    final body = editableContent;
    final sourceLine = provenance.sourceLine;

    final content = body.isEmpty ? sourceLine : '$body\n\n$sourceLine';

    final tags = <String>[];
    final seen = <String>{};

    void addTag(String value) {
      final clean = value.trim();

      if (clean.isEmpty || !seen.add(clean.toLowerCase())) {
        return;
      }

      tags.add(clean.length <= 48 ? clean : clean.substring(0, 48));
    }

    addTag('file_memory');

    if (provenance.sha256.isNotEmpty) {
      addTag(
        'file_${provenance.sha256.substring(0, provenance.sha256.length < 12 ? provenance.sha256.length : 12)}',
      );
    }

    if (provenance.extension.isNotEmpty) {
      addTag('ext_${provenance.extension}');
    }

    for (final tag in draft.tags) {
      addTag(tag);
    }

    return KorlixLiveConvoMemoryDraft(
      content: content,
      confirmed: true,
      kind: draft.kind,
      label: draft.label,
      tags: List<String>.unmodifiable(tags.take(12)),
      importance: draft.importance,
      sensitive: draft.sensitive,
      source: draft.source.trim().isEmpty ? 'file_memory' : draft.source,
    );
  }
}

class KorlixLiveConvoAgentMemoryFilePreview {
  const KorlixLiveConvoAgentMemoryFilePreview({
    required this.analysisVersion,
    required this.summary,
    required this.files,
    required this.suggestions,
    required this.requiresApproval,
    required this.autoSaved,
    required this.sourceStoredByKorlix,
    required this.sourceRetentionMessage,
    required this.maximumFiles,
    required this.maximumBytesPerFile,
    required this.maximumSuggestions,
    required this.creditsUsed,
    this.tier,
  });

  final String analysisVersion;
  final String summary;
  final List<KorlixLiveConvoAgentMemoryFileMetadata> files;
  final List<KorlixLiveConvoAgentMemoryFileSuggestion> suggestions;
  final bool requiresApproval;
  final bool autoSaved;
  final bool sourceStoredByKorlix;
  final String sourceRetentionMessage;
  final int maximumFiles;
  final int maximumBytesPerFile;
  final int maximumSuggestions;
  final int creditsUsed;
  final String? tier;

  factory KorlixLiveConvoAgentMemoryFilePreview.fromJson(
    Map<String, dynamic> json,
  ) {
    final files = <KorlixLiveConvoAgentMemoryFileMetadata>[];

    final rawFiles = json['files'];

    if (rawFiles is Iterable<Object?>) {
      for (final rawFile in rawFiles) {
        final map = _korlixAgentClientMap(rawFile);

        if (map != null) {
          files.add(KorlixLiveConvoAgentMemoryFileMetadata.fromJson(map));
        }
      }
    }

    final suggestions = <KorlixLiveConvoAgentMemoryFileSuggestion>[];

    final rawSuggestions = json['suggestions'];

    if (rawSuggestions is Iterable<Object?>) {
      for (final rawSuggestion in rawSuggestions) {
        final map = _korlixAgentClientMap(rawSuggestion);

        if (map != null) {
          suggestions.add(
            KorlixLiveConvoAgentMemoryFileSuggestion.fromJson(map),
          );
        }
      }
    }

    final retention =
        _korlixAgentClientMap(json['sourceRetention']) ??
        _korlixAgentClientMap(json['source_retention']) ??
        const <String, dynamic>{};

    final limits =
        _korlixAgentClientMap(json['limits']) ?? const <String, dynamic>{};

    final requiresApproval = _korlixAgentClientBool(
      json['requiresApproval'] ?? json['requires_approval'],
      fallback: true,
    );

    final autoSaved = _korlixAgentClientBool(
      json['autoSaved'] ?? json['auto_saved'],
    );

    final sourceStoredByKorlix = _korlixAgentClientBool(
      retention['storedByKorlix'] ?? retention['stored_by_korlix'],
    );

    if (!requiresApproval || autoSaved) {
      throw const KorlixLiveConvoAgentClientException(
        'The Agent file-memory preview did not preserve explicit user approval.',
        code: 'agent_memory_file_approval_boundary_failed',
      );
    }

    if (sourceStoredByKorlix) {
      throw const KorlixLiveConvoAgentClientException(
        'The Agent file-memory preview unexpectedly retained the source file.',
        code: 'agent_memory_file_retention_boundary_failed',
      );
    }

    if (suggestions.isEmpty) {
      throw const KorlixLiveConvoAgentClientException(
        'No durable memory suggestions were returned from the attached files.',
        code: 'agent_memory_file_no_suggestions',
      );
    }

    final rawTier = _korlixAgentClientText(json['tier']);

    return KorlixLiveConvoAgentMemoryFilePreview(
      analysisVersion: _korlixAgentClientText(
        json['analysisVersion'] ?? json['analysis_version'],
      ),
      summary: _korlixAgentClientText(json['summary']),
      files: List<KorlixLiveConvoAgentMemoryFileMetadata>.unmodifiable(files),
      suggestions: List<KorlixLiveConvoAgentMemoryFileSuggestion>.unmodifiable(
        suggestions,
      ),
      requiresApproval: requiresApproval,
      autoSaved: autoSaved,
      sourceStoredByKorlix: sourceStoredByKorlix,
      sourceRetentionMessage: _korlixAgentClientText(retention['message']),
      maximumFiles: _korlixAgentClientInt(
        limits['maximumFiles'] ?? limits['maximum_files'],
        fallback: KorlixLiveConvoAgentMemoryFileUpload.maximumFiles,
        minimum: 1,
      ),
      maximumBytesPerFile: _korlixAgentClientInt(
        limits['maximumBytesPerFile'] ?? limits['maximum_bytes_per_file'],
        fallback: KorlixLiveConvoAgentMemoryFileUpload.maximumBytesPerFile,
        minimum: 1,
      ),
      maximumSuggestions: _korlixAgentClientInt(
        limits['maximumSuggestions'] ?? limits['maximum_suggestions'],
        fallback: 20,
        minimum: 1,
      ),
      creditsUsed: _korlixAgentClientInt(
        json['creditsUsed'] ?? json['credits_used'],
        minimum: 0,
      ),
      tier: rawTier.isEmpty ? null : rawTier,
    );
  }
}

// KORLIX_AGENT_FILE_MEMORY_CLIENT_MODELS_BUILD131_V1_END

// KORLIX_AGENT_FILE_TRAINING_CLIENT_MODELS_BUILD132_V1_BEGIN

class KorlixLiveConvoAgentTrainingFilePreview {
  const KorlixLiveConvoAgentTrainingFilePreview({
    required this.analysisVersion,
    required this.summary,
    required this.trainingDraft,
    required this.files,
    required this.requiresApproval,
    required this.autoSaved,
    required this.sourceStoredByKorlix,
    required this.sourceRetentionMessage,
    required this.maximumFiles,
    required this.maximumBytesPerFile,
    required this.maximumTrainingCharacters,
    required this.creditsUsed,
    this.tier,
  });

  final String analysisVersion;
  final String summary;
  final String trainingDraft;
  final List<KorlixLiveConvoAgentMemoryFileMetadata> files;
  final bool requiresApproval;
  final bool autoSaved;
  final bool sourceStoredByKorlix;
  final String sourceRetentionMessage;
  final int maximumFiles;
  final int maximumBytesPerFile;
  final int maximumTrainingCharacters;
  final int creditsUsed;
  final String? tier;

  factory KorlixLiveConvoAgentTrainingFilePreview.fromJson(
    Map<String, dynamic> json,
  ) {
    final files = <KorlixLiveConvoAgentMemoryFileMetadata>[];
    final rawFiles = json['files'];

    if (rawFiles is Iterable<Object?>) {
      for (final rawFile in rawFiles) {
        final map = _korlixAgentClientMap(rawFile);

        if (map != null) {
          files.add(KorlixLiveConvoAgentMemoryFileMetadata.fromJson(map));
        }
      }
    }

    final retention =
        _korlixAgentClientMap(json['sourceRetention']) ??
        _korlixAgentClientMap(json['source_retention']) ??
        const <String, dynamic>{};

    final limits =
        _korlixAgentClientMap(json['limits']) ?? const <String, dynamic>{};

    final requiresApproval = _korlixAgentClientBool(
      json['requiresApproval'] ?? json['requires_approval'],
      fallback: true,
    );

    final autoSaved = _korlixAgentClientBool(
      json['autoSaved'] ?? json['auto_saved'],
    );

    final sourceStoredByKorlix = _korlixAgentClientBool(
      retention['storedByKorlix'] ?? retention['stored_by_korlix'],
    );

    if (!requiresApproval || autoSaved) {
      throw const KorlixLiveConvoAgentClientException(
        'The training-document preview did not preserve explicit user approval.',
        code: 'agent_training_file_approval_boundary_failed',
      );
    }

    if (sourceStoredByKorlix) {
      throw const KorlixLiveConvoAgentClientException(
        'The training-document preview unexpectedly retained the source file.',
        code: 'agent_training_file_retention_boundary_failed',
      );
    }

    final maximumTrainingCharacters = _korlixAgentClientInt(
      limits['maximumTrainingCharacters'] ??
          limits['maximum_training_characters'],
      fallback: 12000,
      minimum: 1,
    );

    final trainingDraft = _korlixAgentClientText(
      json['trainingDraft'] ??
          json['training_draft'] ??
          json['draft'] ??
          json['instructions'],
    );

    if (trainingDraft.isEmpty) {
      throw const KorlixLiveConvoAgentClientException(
        'No usable training draft was returned from the attached files.',
        code: 'agent_training_file_no_draft',
      );
    }

    if (trainingDraft.length > maximumTrainingCharacters) {
      throw const KorlixLiveConvoAgentClientException(
        'The generated training draft exceeds the allowed training limit.',
        code: 'agent_training_file_draft_too_large',
      );
    }

    final rawTier = _korlixAgentClientText(json['tier']);

    return KorlixLiveConvoAgentTrainingFilePreview(
      analysisVersion: _korlixAgentClientText(
        json['analysisVersion'] ?? json['analysis_version'],
      ),
      summary: _korlixAgentClientText(json['summary']),
      trainingDraft: trainingDraft,
      files: List<KorlixLiveConvoAgentMemoryFileMetadata>.unmodifiable(files),
      requiresApproval: requiresApproval,
      autoSaved: autoSaved,
      sourceStoredByKorlix: sourceStoredByKorlix,
      sourceRetentionMessage: _korlixAgentClientText(retention['message']),
      maximumFiles: _korlixAgentClientInt(
        limits['maximumFiles'] ?? limits['maximum_files'],
        fallback: KorlixLiveConvoAgentMemoryFileUpload.maximumFiles,
        minimum: 1,
      ),
      maximumBytesPerFile: _korlixAgentClientInt(
        limits['maximumBytesPerFile'] ?? limits['maximum_bytes_per_file'],
        fallback: KorlixLiveConvoAgentMemoryFileUpload.maximumBytesPerFile,
        minimum: 1,
      ),
      maximumTrainingCharacters: maximumTrainingCharacters,
      creditsUsed: _korlixAgentClientInt(
        json['creditsUsed'] ?? json['credits_used'],
        minimum: 0,
      ),
      tier: rawTier.isEmpty ? null : rawTier,
    );
  }
}

// KORLIX_AGENT_FILE_TRAINING_CLIENT_MODELS_BUILD132_V1_END

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
    final clean = backendBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');

    if (clean.isEmpty) {
      throw const KorlixLiveConvoAgentClientException(
        'The Korlix backend address is unavailable.',
        code: 'backend_address_unavailable',
      );
    }

    return clean;
  }

  Map<String, String> _requestHeaders({required bool hasJsonBody}) {
    final headers = Map<String, String>.from(headersBuilder())
      ..removeWhere((name, _) => name.trim().toLowerCase() == 'content-type')
      ..['Accept'] = 'application/json';

    if (hasJsonBody) {
      headers['Content-Type'] = 'application/json; charset=utf-8';
    }

    return headers;
  }

  Uri _requestUri(String path, {Map<String, String>? queryParameters}) {
    final uri = Uri.parse('$_cleanBase$path');

    final cleanQuery = <String, String>{};

    for (final entry in (queryParameters ?? const <String, String>{}).entries) {
      final value = entry.value.trim();

      if (value.isNotEmpty) {
        cleanQuery[entry.key] = value;
      }
    }

    return cleanQuery.isEmpty ? uri : uri.replace(queryParameters: cleanQuery);
  }

  Map<String, dynamic>? _decodeResponse(http.Response response) {
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
      final nested = error['message'] ?? error['error'] ?? error['detail'];

      if (nested != null && nested.toString().trim().isNotEmpty) {
        return nested.toString().trim();
      }
    }

    if (message != null && message.toString().trim().isNotEmpty) {
      return message.toString().trim();
    }

    final body = response.body.trim();

    if (body.isNotEmpty && body.length <= 300 && !body.startsWith('<')) {
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
    // KORLIX_LIVE_CONVO_FRESH_RUNTIME_BUILD131_V1
    final normalizedMethod = method.trim().toUpperCase();
    final effectiveQueryParameters = <String, String>{
      ...?queryParameters,
      if (normalizedMethod == 'GET')
        '_korlixFresh': DateTime.now().microsecondsSinceEpoch.toString(),
    };
    final request = http.Request(
      normalizedMethod,
      _requestUri(path, queryParameters: effectiveQueryParameters),
    );

    request.headers.addAll(_requestHeaders(hasJsonBody: body != null));

    if (body != null) {
      request.body = jsonEncode(body);
    }

    late final http.StreamedResponse streamedResponse;

    try {
      streamedResponse = await _client.send(request).timeout(timeout);
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

    final response = await http.Response.fromStream(streamedResponse);

    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw KorlixLiveConvoAgentClientException(
        _responseMessage(response, decoded, fallback: fallbackError),
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
    final map = _korlixAgentClientMap(response[key]);

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

  Future<KorlixLiveConvoAgentModelProof> loadModelProof() async {
    final response = await _requestJson(
      method: 'GET',
      path: KorlixLiveConvoAgentApiContract.modelProofPath,
      fallbackError: 'Could not verify the LIVE CONVO models.',
    );

    final nested = _korlixAgentClientMap(
      response['modelProof'] ?? response['model_proof'],
    );

    return KorlixLiveConvoAgentModelProof.fromJson(nested ?? response);
  }

  Future<KorlixLiveConvoAgentRuntime> loadRuntime({
    required String agentId,
    required String characterName,
    required String language,
  }) async {
    final response = await _requestJson(
      method: 'GET',
      path: KorlixLiveConvoAgentApiContract.runtimePath(agentId),
      queryParameters: <String, String>{
        'characterName': characterName,
        'language': language,
      },
      fallbackError: 'Could not activate the selected agent.',
    );

    final runtime = _requiredMap(
      response,
      'runtime',
      errorMessage: 'The selected agent returned no runtime configuration.',
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
        errorMessage: 'The custom-agent service returned no agent.',
      ),
    );
  }

  Future<KorlixLiveConvoAgent> updateAgent({
    required String agentId,
    required Map<String, dynamic> changes,
  }) async {
    final response = await _requestJson(
      method: 'PUT',
      path: KorlixLiveConvoAgentApiContract.agentPath(agentId),
      body: changes,
      fallbackError: 'Could not update the LIVE CONVO agent.',
    );

    return KorlixLiveConvoAgent.fromJson(
      _requiredMap(
        response,
        'agent',
        errorMessage: 'The agent-update service returned no agent.',
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

    final mode = update.mode.trim().toLowerCase();

    if (mode != 'append' && mode != 'replace') {
      throw const KorlixLiveConvoAgentClientException(
        'Choose whether to append to or replace the current training.',
        code: 'training_mode_invalid',
      );
    }

    final response = await _requestJson(
      method: 'POST',
      path: KorlixLiveConvoAgentApiContract.trainingPath(agentId),
      body: update.toJson(),
      fallbackError: 'Could not save the agent training.',
    );

    return KorlixLiveConvoAgent.fromJson(
      _requiredMap(
        response,
        'agent',
        errorMessage: 'The training service returned no updated agent.',
      ),
    );
  }

  Future<List<KorlixLiveConvoAgentMemory>> loadMemories({
    required String agentId,
  }) async {
    final response = await _requestJson(
      method: 'GET',
      path: KorlixLiveConvoAgentApiContract.memoriesPath(agentId),
      fallbackError: 'Could not load the agent memories.',
    );

    final rawMemories = response['memories'];
    final memories = <KorlixLiveConvoAgentMemory>[];

    if (rawMemories is Iterable<Object?>) {
      for (final rawMemory in rawMemories) {
        final map = _korlixAgentClientMap(rawMemory);

        if (map != null) {
          memories.add(KorlixLiveConvoAgentMemory.fromJson(map));
        }
      }
    }

    return List<KorlixLiveConvoAgentMemory>.unmodifiable(memories);
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
      path: KorlixLiveConvoAgentApiContract.memoriesPath(agentId),
      body: draft.toJson(),
      fallbackError: 'Could not save the long-term memory.',
    );

    return KorlixLiveConvoAgentMemory.fromJson(
      _requiredMap(
        response,
        'memory',
        errorMessage: 'The memory service returned no saved memory.',
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
      path: KorlixLiveConvoAgentApiContract.forgetMemoryPath(agentId),
      body: <String, dynamic>{'confirmed': true, 'query': cleanQuery},
      fallbackError: 'Could not forget the matching memories.',
    );

    return _korlixAgentClientInt(response['removed'], minimum: 0);
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
      path: KorlixLiveConvoAgentApiContract.memoryPath(agentId, memoryId),
      body: const <String, dynamic>{'confirmed': true},
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
      path: KorlixLiveConvoAgentApiContract.memoriesPath(agentId),
      body: const <String, dynamic>{'confirmed': true},
      fallbackError: 'Could not clear the agent memories.',
    );
  }

  // KORLIX_AGENT_FILE_MEMORY_MULTIPART_CLIENT_BUILD131_V1_BEGIN
  Future<KorlixLiveConvoAgentMemoryFilePreview> analyzeMemoryFiles({
    required String agentId,
    required List<KorlixLiveConvoAgentMemoryFileUpload> files,
  }) async {
    if (files.isEmpty) {
      throw const KorlixLiveConvoAgentClientException(
        'Attach at least one file for Agent memory analysis.',
        code: 'agent_memory_file_required',
      );
    }

    if (files.length > KorlixLiveConvoAgentMemoryFileUpload.maximumFiles) {
      throw const KorlixLiveConvoAgentClientException(
        'Attach no more than five files at once.',
        code: 'agent_memory_file_count_exceeded',
      );
    }

    final seen = <String>{};

    for (final file in files) {
      if (file.bytes.isEmpty) {
        throw KorlixLiveConvoAgentClientException(
          '${file.name} is empty or could not be read on this device.',
          code: 'agent_memory_file_empty',
        );
      }

      if (file.sizeBytes >
          KorlixLiveConvoAgentMemoryFileUpload.maximumBytesPerFile) {
        throw KorlixLiveConvoAgentClientException(
          '${file.name} exceeds the 10 MB Agent memory file limit.',
          code: 'agent_memory_file_too_large',
        );
      }

      if (!KorlixLiveConvoAgentMemoryFileUpload.allowedExtensions.contains(
        file.extension,
      )) {
        throw KorlixLiveConvoAgentClientException(
          '${file.name} is not a supported Agent memory file.',
          code: 'agent_memory_file_type_unsupported',
        );
      }

      if (!seen.add(file.dedupeKey)) {
        throw KorlixLiveConvoAgentClientException(
          '${file.name} is attached more than once.',
          code: 'agent_memory_file_duplicate',
        );
      }
    }

    final request = http.MultipartRequest(
      'POST',
      _requestUri(
        '${KorlixLiveConvoAgentApiContract.agentPath(agentId)}'
        '/memory-files/analyze',
      ),
    );

    request.headers.addAll(_requestHeaders(hasJsonBody: false));

    for (final file in files) {
      request.files.add(
        http.MultipartFile.fromBytes('files', file.bytes, filename: file.name),
      );
    }

    late final http.StreamedResponse streamedResponse;

    final analysisTimeout = timeout.inMilliseconds < 120000
        ? const Duration(seconds: 120)
        : timeout;

    try {
      streamedResponse = await _client.send(request).timeout(analysisTimeout);
    } on TimeoutException {
      throw const KorlixLiveConvoAgentClientException(
        'Agent memory file analysis timed out. Please try again.',
        code: 'agent_memory_file_timeout',
      );
    } on KorlixLiveConvoAgentClientException {
      rethrow;
    } catch (error) {
      throw KorlixLiveConvoAgentClientException(
        'Could not reach the Agent memory file-analysis service: $error',
        code: 'agent_memory_file_network_error',
      );
    }

    final response = await http.Response.fromStream(streamedResponse);

    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw KorlixLiveConvoAgentClientException(
        _responseMessage(
          response,
          decoded,
          fallback: 'Could not analyze the attached Agent memory files.',
        ),
        code: _korlixAgentClientText(
          decoded?['code'],
          fallback: 'agent_memory_file_analysis_failed',
        ),
        statusCode: response.statusCode,
      );
    }

    if (decoded == null) {
      throw const KorlixLiveConvoAgentClientException(
        'The Agent memory file-analysis service returned an invalid response.',
        code: 'invalid_agent_memory_file_response',
      );
    }

    return KorlixLiveConvoAgentMemoryFilePreview.fromJson(decoded);
  }
  // KORLIX_AGENT_FILE_MEMORY_MULTIPART_CLIENT_BUILD131_V1_END

  // KORLIX_AGENT_FILE_TRAINING_MULTIPART_CLIENT_BUILD132_V1_BEGIN
  Future<KorlixLiveConvoAgentTrainingFilePreview> analyzeTrainingFiles({
    required String agentId,
    required List<KorlixLiveConvoAgentMemoryFileUpload> files,
  }) async {
    if (files.isEmpty) {
      throw const KorlixLiveConvoAgentClientException(
        'Attach at least one file for Agent training analysis.',
        code: 'agent_training_file_required',
      );
    }

    if (files.length > KorlixLiveConvoAgentMemoryFileUpload.maximumFiles) {
      throw const KorlixLiveConvoAgentClientException(
        'Attach no more than five files at once.',
        code: 'agent_training_file_count_exceeded',
      );
    }

    final seen = <String>{};

    for (final file in files) {
      if (file.bytes.isEmpty) {
        throw KorlixLiveConvoAgentClientException(
          '${file.name} is empty or could not be read on this device.',
          code: 'agent_training_file_empty',
        );
      }

      if (file.sizeBytes >
          KorlixLiveConvoAgentMemoryFileUpload.maximumBytesPerFile) {
        throw KorlixLiveConvoAgentClientException(
          '${file.name} exceeds the 10 MB Agent training file limit.',
          code: 'agent_training_file_too_large',
        );
      }

      if (!KorlixLiveConvoAgentMemoryFileUpload.allowedExtensions.contains(
        file.extension,
      )) {
        throw KorlixLiveConvoAgentClientException(
          '${file.name} is not a supported Agent training file.',
          code: 'agent_training_file_type_unsupported',
        );
      }

      if (!seen.add(file.dedupeKey)) {
        throw KorlixLiveConvoAgentClientException(
          '${file.name} is attached more than once.',
          code: 'agent_training_file_duplicate',
        );
      }
    }

    final request = http.MultipartRequest(
      'POST',
      _requestUri(
        KorlixLiveConvoAgentApiContract.trainingFilesAnalyzePath(agentId),
      ),
    );

    request.headers.addAll(_requestHeaders(hasJsonBody: false));

    for (final file in files) {
      request.files.add(
        http.MultipartFile.fromBytes('files', file.bytes, filename: file.name),
      );
    }

    late final http.StreamedResponse streamedResponse;

    final analysisTimeout = timeout.inMilliseconds < 120000
        ? const Duration(seconds: 120)
        : timeout;

    try {
      streamedResponse = await _client.send(request).timeout(analysisTimeout);
    } on TimeoutException {
      throw const KorlixLiveConvoAgentClientException(
        'Agent training-document analysis timed out. Please try again.',
        code: 'agent_training_file_timeout',
      );
    } on KorlixLiveConvoAgentClientException {
      rethrow;
    } catch (error) {
      throw KorlixLiveConvoAgentClientException(
        'Could not reach the Agent training-document service: $error',
        code: 'agent_training_file_network_error',
      );
    }

    final response = await http.Response.fromStream(streamedResponse);
    final decoded = _decodeResponse(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw KorlixLiveConvoAgentClientException(
        _responseMessage(
          response,
          decoded,
          fallback: 'Could not analyze the attached Agent training files.',
        ),
        code: _korlixAgentClientText(
          decoded?['code'],
          fallback: 'agent_training_file_analysis_failed',
        ),
        statusCode: response.statusCode,
      );
    }

    if (decoded == null) {
      throw const KorlixLiveConvoAgentClientException(
        'The Agent training-document service returned an invalid response.',
        code: 'invalid_agent_training_file_response',
      );
    }

    return KorlixLiveConvoAgentTrainingFilePreview.fromJson(decoded);
  }
  // KORLIX_AGENT_FILE_TRAINING_MULTIPART_CLIENT_BUILD132_V1_END

  Future<List<KorlixLiveConvoAgentVersion>> loadVersions({
    required String agentId,
  }) async {
    final response = await _requestJson(
      method: 'GET',
      path: KorlixLiveConvoAgentApiContract.versionsPath(agentId),
      fallbackError: 'Could not load the agent training history.',
    );

    final rawVersions = response['versions'];
    final versions = <KorlixLiveConvoAgentVersion>[];

    if (rawVersions is Iterable<Object?>) {
      for (final rawVersion in rawVersions) {
        final map = _korlixAgentClientMap(rawVersion);

        if (map != null) {
          versions.add(KorlixLiveConvoAgentVersion.fromJson(map));
        }
      }
    }

    versions.sort((left, right) => right.version.compareTo(left.version));

    return List<KorlixLiveConvoAgentVersion>.unmodifiable(versions);
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
      path: KorlixLiveConvoAgentApiContract.restoreVersionPath(
        agentId,
        version,
      ),
      body: const <String, dynamic>{'confirmed': true},
      fallbackError: 'Could not restore the selected training version.',
    );

    return KorlixLiveConvoAgent.fromJson(
      _requiredMap(
        response,
        'agent',
        errorMessage: 'The restore service returned no updated agent.',
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
      path: KorlixLiveConvoAgentApiContract.agentPath(agentId),
      body: const <String, dynamic>{'confirmed': true},
      fallbackError: 'Could not reset or delete the selected agent.',
    );
  }

  // KORLIX_BRAIN_VAULT_CREDENTIAL_CLIENT_BUILD131_V2_BEGIN

  void _validateBrainVaultCredentialPassword(
    String password, {
    String label = 'BRAIN VAULT password',
  }) {
    if (password.length < 12 || password.length > 128) {
      throw KorlixLiveConvoAgentClientException(
        '$label must contain 12 to 128 characters.',
        code: 'brain_vault_password_policy_failed',
      );
    }
  }

  Future<Map<String, dynamic>> loadBrainVaultSecurityStatus() async {
    return _requestJson(
      method: 'GET',
      path: '/api/brain-vault/security-status',
      fallbackError: 'Could not load BRAIN VAULT security settings.',
    );
  }

  Future<void> verifyBrainVaultPassword({required String password}) async {
    _validateBrainVaultCredentialPassword(password);

    final response = await _requestJson(
      method: 'POST',
      path: '/api/brain-vault/password/verify',
      body: <String, dynamic>{'vaultPassword': password},
      fallbackError: 'Could not unlock BRAIN VAULT.',
    );

    if (!_korlixAgentClientBool(response['verified'])) {
      throw const KorlixLiveConvoAgentClientException(
        'KORLIX could not verify the BRAIN VAULT password.',
        code: 'brain_vault_password_unverified',
      );
    }
  }

  Future<void> setBrainVaultPassword({
    required String accountPassword,
    required String vaultPassword,
    required String confirmVaultPassword,
  }) async {
    _validateBrainVaultCredentialPassword(vaultPassword);

    if (vaultPassword != confirmVaultPassword) {
      throw const KorlixLiveConvoAgentClientException(
        'The BRAIN VAULT passwords do not match.',
        code: 'brain_vault_password_confirmation_mismatch',
      );
    }

    await _requestJson(
      method: 'POST',
      path: '/api/brain-vault/password/set',
      body: <String, dynamic>{
        'accountPassword': accountPassword,
        'vaultPassword': vaultPassword,
        'confirmVaultPassword': confirmVaultPassword,
      },
      fallbackError: 'Could not set the BRAIN VAULT password.',
    );
  }

  Future<void> changeBrainVaultPassword({
    required String accountPassword,
    required String currentVaultPassword,
    required String newVaultPassword,
    required String confirmVaultPassword,
  }) async {
    _validateBrainVaultCredentialPassword(
      currentVaultPassword,
      label: 'Current BRAIN VAULT password',
    );
    _validateBrainVaultCredentialPassword(
      newVaultPassword,
      label: 'New BRAIN VAULT password',
    );

    if (newVaultPassword != confirmVaultPassword) {
      throw const KorlixLiveConvoAgentClientException(
        'The new BRAIN VAULT passwords do not match.',
        code: 'brain_vault_password_confirmation_mismatch',
      );
    }

    await _requestJson(
      method: 'POST',
      path: '/api/brain-vault/password/change',
      body: <String, dynamic>{
        'accountPassword': accountPassword,
        'currentVaultPassword': currentVaultPassword,
        'newVaultPassword': newVaultPassword,
        'confirmVaultPassword': confirmVaultPassword,
      },
      fallbackError: 'Could not change the BRAIN VAULT password.',
    );
  }

  Future<void> resetBrainVaultPassword({
    required String accountPassword,
    required String newVaultPassword,
    required String confirmVaultPassword,
  }) async {
    _validateBrainVaultCredentialPassword(
      newVaultPassword,
      label: 'New BRAIN VAULT password',
    );

    if (newVaultPassword != confirmVaultPassword) {
      throw const KorlixLiveConvoAgentClientException(
        'The new BRAIN VAULT passwords do not match.',
        code: 'brain_vault_password_confirmation_mismatch',
      );
    }

    await _requestJson(
      method: 'POST',
      path: '/api/brain-vault/password/reset',
      body: <String, dynamic>{
        'accountPassword': accountPassword,
        'newVaultPassword': newVaultPassword,
        'confirmVaultPassword': confirmVaultPassword,
      },
      fallbackError: 'Could not reset the BRAIN VAULT password.',
    );
  }

  // KORLIX_BRAIN_VAULT_CREDENTIAL_CLIENT_BUILD131_V2_END

  // KORLIX_BRAIN_VAULT_CLIENT_BUILD131_V1_BEGIN

  Future<KorlixBrainVaultPackage> loadBrainPackage({
    required KorlixLiveConvoAgent agent,
    required bool includeMemories,
    required bool includeSensitiveMemories,
    required bool includeVersionHistory,
    required String mode,
  }) async {
    final memories = includeMemories
        ? await loadMemories(agentId: agent.id)
        : const <KorlixLiveConvoAgentMemory>[];

    final versions = includeVersionHistory
        ? await loadVersions(agentId: agent.id)
        : const <KorlixLiveConvoAgentVersion>[];

    final brainVersions = versions
        .map(
          (version) => KorlixBrainVaultVersion.fromJson(<String, dynamic>{
            'version': version.version,
            'source': version.source,
            'snapshot': version.snapshot,
            'createdAt': version.createdAt?.toIso8601String(),
          }),
        )
        .toList(growable: false);

    return KorlixBrainVaultPackage.fromAgent(
      agent: agent,
      memories: memories,
      versions: brainVersions,
      includeMemories: includeMemories,
      includeSensitiveMemories: includeSensitiveMemories,
      includeVersionHistory: includeVersionHistory,
      mode: mode,
    );
  }

  Future<KorlixLiveConvoAgent> createAgentFromBrainPackage({
    required KorlixBrainVaultPackage package,
    required String nameOverride,
    required bool includeMemories,
    required bool includeSensitiveMemories,
  }) async {
    final created = await createCustomAgent(
      package.agent.toCustomAgentDraft(nameOverride: nameOverride),
    );

    final memoryDrafts = includeMemories
        ? package.memoryDrafts(
            includeSensitiveMemories: includeSensitiveMemories,
          )
        : const <KorlixLiveConvoMemoryDraft>[];

    try {
      for (final draft in memoryDrafts) {
        await saveMemory(agentId: created.id, draft: draft);
      }
    } catch (_) {
      try {
        await deleteOrResetAgent(agentId: created.id, confirmed: true);
      } catch (_) {
        // The original import error remains authoritative.
      }

      rethrow;
    }

    return created.copyWith(memoryCount: memoryDrafts.length);
  }

  Future<KorlixLiveConvoAgent> duplicateAgentBrain({
    required KorlixLiveConvoAgent sourceAgent,
    required String nameOverride,
    required bool includeMemories,
    required bool includeSensitiveMemories,
  }) async {
    final package = await loadBrainPackage(
      agent: sourceAgent,
      includeMemories: includeMemories,
      includeSensitiveMemories: true,
      includeVersionHistory: false,
      mode: includeMemories
          ? KorlixBrainVaultPackage.privateBackupMode
          : KorlixBrainVaultPackage.templateMode,
    );

    return createAgentFromBrainPackage(
      package: package,
      nameOverride: nameOverride,
      includeMemories: includeMemories,
      includeSensitiveMemories: includeSensitiveMemories,
    );
  }

  // KORLIX_BRAIN_VAULT_CLIENT_BUILD131_V1_END

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

// KORLIX_LIVE_CONVO_AGENT_CLIENT_BUILD131_END
