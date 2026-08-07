import 'dart:convert';

import 'korlix_live_convo_agent.dart';

// KORLIX_BRAIN_VAULT_BUILD131_V1_BEGIN

const Set<String> _korlixBrainVaultAllowedTools = <String>{
  'general_chat',
  'live_docs',
  'file_analysis',
  'image_generation',
  'image_improvement',
  'camera',
  'memory',
  'agent_training',
};

const Set<String> _korlixBrainVaultAllowedMemoryKinds = <String>{
  'preference',
  'fact',
  'goal',
  'style',
  'example',
  'correction',
  'vocabulary',
};

String _korlixBrainVaultText(
  Object? value, {
  int maximum = 12000,
  String fallback = '',
}) {
  final text = (value ?? '').toString().trim();

  if (text.isEmpty) {
    return fallback;
  }

  return text.length <= maximum ? text : text.substring(0, maximum);
}

bool _korlixBrainVaultBool(Object? value, {bool fallback = false}) {
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

int _korlixBrainVaultInt(
  Object? value, {
  int fallback = 0,
  int minimum = 0,
  int maximum = 2147483647,
}) {
  final parsed = value is int
      ? value
      : int.tryParse((value ?? '').toString().trim());

  if (parsed == null) {
    return fallback;
  }

  if (parsed < minimum) {
    return minimum;
  }

  if (parsed > maximum) {
    return maximum;
  }

  return parsed;
}

Map<String, dynamic>? _korlixBrainVaultMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }

  return null;
}

List<String> _korlixBrainVaultTags(Object? value) {
  if (value is! Iterable<Object?>) {
    return const <String>[];
  }

  final result = <String>[];
  final seen = <String>{};

  for (final item in value) {
    final clean = _korlixBrainVaultText(item, maximum: 48)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    if (clean.isEmpty || !seen.add(clean)) {
      continue;
    }

    result.add(clean);

    if (result.length >= 12) {
      break;
    }
  }

  return List<String>.unmodifiable(result);
}

List<String> _korlixBrainVaultTools(Object? value) {
  final result = <String>[];
  final seen = <String>{};

  if (value is Iterable<Object?>) {
    for (final item in value) {
      final normalized = _korlixBrainVaultText(item, maximum: 64)
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');

      if (_korlixBrainVaultAllowedTools.contains(normalized) &&
          seen.add(normalized)) {
        result.add(normalized);
      }
    }
  }

  if (!result.contains('general_chat')) {
    result.insert(0, 'general_chat');
  }

  return List<String>.unmodifiable(result);
}

String _korlixBrainVaultAccent(Object? value) {
  final clean = _korlixBrainVaultText(
    value,
    maximum: 7,
    fallback: '21D4F4',
  ).replaceFirst('#', '').toUpperCase();

  return RegExp(r'^[0-9A-F]{6}$').hasMatch(clean) ? clean : '21D4F4';
}

String _korlixBrainVaultMemoryKind(Object? value) {
  final normalized = _korlixBrainVaultText(
    value,
    maximum: 32,
    fallback: 'fact',
  ).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  return _korlixBrainVaultAllowedMemoryKinds.contains(normalized)
      ? normalized
      : 'fact';
}

Map<String, dynamic> _korlixBrainVaultSnapshot(Object? value) {
  final raw = _korlixBrainVaultMap(value) ?? const <String, dynamic>{};

  return <String, dynamic>{
    'name': _korlixBrainVaultText(raw['name'], maximum: 80),
    'description': _korlixBrainVaultText(raw['description'], maximum: 240),
    'icon': _korlixBrainVaultText(
      raw['icon'] ?? raw['iconName'] ?? raw['icon_name'],
      maximum: 64,
      fallback: 'smart_toy',
    ),
    'accent': _korlixBrainVaultAccent(
      raw['accent'] ?? raw['accentHex'] ?? raw['accent_hex'],
    ),
    'mission': _korlixBrainVaultText(raw['mission'], maximum: 2400),
    'trainingInstructions': _korlixBrainVaultText(
      raw['trainingInstructions'] ?? raw['training_instructions'],
      maximum: 12000,
    ),
    'toolIds': _korlixBrainVaultTools(
      raw['toolIds'] ?? raw['tool_ids'] ?? raw['tools'],
    ),
    'memoryEnabled': _korlixBrainVaultBool(
      raw['memoryEnabled'] ?? raw['memory_enabled'],
      fallback: true,
    ),
  };
}

class KorlixBrainVaultAgent {
  const KorlixBrainVaultAgent({
    required this.name,
    required this.description,
    required this.iconName,
    required this.accentHex,
    required this.mission,
    required this.trainingInstructions,
    required this.toolIds,
    required this.memoryEnabled,
  });

  final String name;
  final String description;
  final String iconName;
  final String accentHex;
  final String mission;
  final String trainingInstructions;
  final List<String> toolIds;
  final bool memoryEnabled;

  bool get hasPublishedTraining => trainingInstructions.trim().isNotEmpty;

  factory KorlixBrainVaultAgent.fromAgent(KorlixLiveConvoAgent agent) {
    return KorlixBrainVaultAgent(
      name: _korlixBrainVaultText(agent.name, maximum: 80),
      description: _korlixBrainVaultText(agent.description, maximum: 240),
      iconName: _korlixBrainVaultText(
        agent.iconName,
        maximum: 64,
        fallback: 'smart_toy',
      ),
      accentHex: _korlixBrainVaultAccent(agent.accentHex),
      mission: _korlixBrainVaultText(agent.mission, maximum: 2400),
      trainingInstructions: _korlixBrainVaultText(
        agent.trainingInstructions,
        maximum: 12000,
      ),
      toolIds: _korlixBrainVaultTools(agent.toolIds),
      memoryEnabled: agent.memoryEnabled,
    );
  }

  factory KorlixBrainVaultAgent.fromJson(Map<String, dynamic> json) {
    return KorlixBrainVaultAgent(
      name: _korlixBrainVaultText(
        json['name'],
        maximum: 80,
        fallback: 'Imported Korlix Agent',
      ),
      description: _korlixBrainVaultText(json['description'], maximum: 240),
      iconName: _korlixBrainVaultText(
        json['icon'] ?? json['iconName'] ?? json['icon_name'],
        maximum: 64,
        fallback: 'smart_toy',
      ),
      accentHex: _korlixBrainVaultAccent(
        json['accent'] ?? json['accentHex'] ?? json['accent_hex'],
      ),
      mission: _korlixBrainVaultText(
        json['mission'],
        maximum: 2400,
        fallback:
            'Help the user while following Korlix safety, privacy, and '
            'authorization rules.',
      ),
      trainingInstructions: _korlixBrainVaultText(
        json['trainingInstructions'] ?? json['training_instructions'],
        maximum: 12000,
      ),
      toolIds: _korlixBrainVaultTools(
        json['toolIds'] ?? json['tool_ids'] ?? json['tools'],
      ),
      memoryEnabled: _korlixBrainVaultBool(
        json['memoryEnabled'] ?? json['memory_enabled'],
        fallback: true,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'description': description,
      'icon': iconName,
      'accent': accentHex,
      'mission': mission,
      'trainingInstructions': trainingInstructions,
      'toolIds': toolIds,
      'memoryEnabled': memoryEnabled,
    };
  }

  KorlixLiveConvoCustomAgentDraft toCustomAgentDraft({
    required String nameOverride,
  }) {
    return KorlixLiveConvoCustomAgentDraft(
      name: _korlixBrainVaultText(nameOverride, maximum: 80, fallback: name),
      description: description,
      mission: mission,
      iconName: iconName,
      accentHex: accentHex,
      trainingInstructions: trainingInstructions,
      toolIds: toolIds,
      memoryEnabled: memoryEnabled,
    );
  }
}

class KorlixBrainVaultMemory {
  const KorlixBrainVaultMemory({
    required this.kind,
    required this.label,
    required this.content,
    required this.tags,
    required this.importance,
    required this.sensitive,
    required this.source,
  });

  final String kind;
  final String label;
  final String content;
  final List<String> tags;
  final int importance;
  final bool sensitive;
  final String source;

  factory KorlixBrainVaultMemory.fromMemory(KorlixLiveConvoAgentMemory memory) {
    return KorlixBrainVaultMemory(
      kind: _korlixBrainVaultMemoryKind(memory.kind),
      label: _korlixBrainVaultText(memory.label, maximum: 120),
      content: _korlixBrainVaultText(memory.content, maximum: 4000),
      tags: _korlixBrainVaultTags(memory.tags),
      importance: memory.importance < 1
          ? 1
          : memory.importance > 5
          ? 5
          : memory.importance,
      sensitive: memory.sensitive,
      source: _korlixBrainVaultText(
        memory.source,
        maximum: 80,
        fallback: 'user_confirmed',
      ),
    );
  }

  factory KorlixBrainVaultMemory.fromJson(Map<String, dynamic> json) {
    final content = _korlixBrainVaultText(json['content'], maximum: 4000);

    if (content.isEmpty) {
      throw const FormatException(
        'A BRAIN VAULT memory contains no usable content.',
      );
    }

    return KorlixBrainVaultMemory(
      kind: _korlixBrainVaultMemoryKind(json['kind']),
      label: _korlixBrainVaultText(json['label'], maximum: 120),
      content: content,
      tags: _korlixBrainVaultTags(json['tags']),
      importance: _korlixBrainVaultInt(
        json['importance'],
        fallback: 3,
        minimum: 1,
        maximum: 5,
      ),
      sensitive: _korlixBrainVaultBool(json['sensitive']),
      source: _korlixBrainVaultText(
        json['source'],
        maximum: 80,
        fallback: 'brain_vault_export',
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'kind': kind,
      'label': label,
      'content': content,
      'tags': tags,
      'importance': importance,
      'sensitive': sensitive,
      'source': source,
    };
  }

  KorlixLiveConvoMemoryDraft toMemoryDraft() {
    return KorlixLiveConvoMemoryDraft(
      content: content,
      confirmed: true,
      kind: kind,
      label: label,
      tags: tags,
      importance: importance,
      sensitive: sensitive,
      source: 'brain_vault_import',
    );
  }
}

class KorlixBrainVaultVersion {
  const KorlixBrainVaultVersion({
    required this.version,
    required this.source,
    required this.snapshot,
    this.createdAt,
  });

  final int version;
  final String source;
  final Map<String, dynamic> snapshot;
  final DateTime? createdAt;

  factory KorlixBrainVaultVersion.fromJson(Map<String, dynamic> json) {
    return KorlixBrainVaultVersion(
      version: _korlixBrainVaultInt(
        json['version'],
        fallback: 1,
        minimum: 1,
        maximum: 1000000,
      ),
      source: _korlixBrainVaultText(
        json['source'],
        maximum: 80,
        fallback: 'training_update',
      ),
      snapshot: Map<String, dynamic>.unmodifiable(
        _korlixBrainVaultSnapshot(json['snapshot']),
      ),
      createdAt: DateTime.tryParse(
        _korlixBrainVaultText(
          json['createdAt'] ?? json['created_at'],
          maximum: 64,
        ),
      )?.toUtc(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': version,
      'source': source,
      'snapshot': snapshot,
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}

class KorlixBrainVaultPackage {
  const KorlixBrainVaultPackage({
    required this.schema,
    required this.mode,
    required this.exportedAt,
    required this.agent,
    required this.memories,
    required this.versions,
  });

  static const String schemaId = 'korlix.brain.v1';
  static const String templateMode = 'template';
  static const String privateBackupMode = 'private_backup';
  static const int maximumBytes = 2 * 1024 * 1024;
  static const int maximumMemories = 500;
  static const int maximumVersions = 100;

  final String schema;
  final String mode;
  final DateTime exportedAt;
  final KorlixBrainVaultAgent agent;
  final List<KorlixBrainVaultMemory> memories;
  final List<KorlixBrainVaultVersion> versions;

  bool get isPrivateBackup => mode == privateBackupMode;

  int get sensitiveMemoryCount =>
      memories.where((memory) => memory.sensitive).length;

  factory KorlixBrainVaultPackage.fromAgent({
    required KorlixLiveConvoAgent agent,
    required Iterable<KorlixLiveConvoAgentMemory> memories,
    required Iterable<KorlixBrainVaultVersion> versions,
    required bool includeMemories,
    required bool includeSensitiveMemories,
    required bool includeVersionHistory,
    required String mode,
    DateTime? exportedAt,
  }) {
    final selectedMemories = includeMemories
        ? memories
              .where((memory) => includeSensitiveMemories || !memory.sensitive)
              .take(maximumMemories)
              .map(KorlixBrainVaultMemory.fromMemory)
              .toList(growable: false)
        : const <KorlixBrainVaultMemory>[];

    final selectedVersions = includeVersionHistory
        ? versions.take(maximumVersions).toList(growable: false)
        : const <KorlixBrainVaultVersion>[];

    return KorlixBrainVaultPackage(
      schema: schemaId,
      mode: mode == privateBackupMode ? privateBackupMode : templateMode,
      exportedAt: (exportedAt ?? DateTime.now()).toUtc(),
      agent: KorlixBrainVaultAgent.fromAgent(agent),
      memories: List<KorlixBrainVaultMemory>.unmodifiable(selectedMemories),
      versions: List<KorlixBrainVaultVersion>.unmodifiable(selectedVersions),
    );
  }

  factory KorlixBrainVaultPackage.decode(String source) {
    final bytes = utf8.encode(source);

    if (bytes.length > maximumBytes) {
      throw const FormatException(
        'This BRAIN VAULT file is larger than the 2 MB safety limit.',
      );
    }

    final decoded = jsonDecode(source);
    final map = _korlixBrainVaultMap(decoded);

    if (map == null) {
      throw const FormatException(
        'This BRAIN VAULT file does not contain a JSON object.',
      );
    }

    final schema = _korlixBrainVaultText(map['schema'], maximum: 80);

    if (schema != schemaId) {
      throw const FormatException(
        'This file is not a supported KORLIX BRAIN VAULT package.',
      );
    }

    final rawAgent = _korlixBrainVaultMap(map['agent']);

    if (rawAgent == null) {
      throw const FormatException(
        'This BRAIN VAULT package contains no agent profile.',
      );
    }

    final memories = <KorlixBrainVaultMemory>[];
    final rawMemories = map['memories'];

    if (rawMemories is Iterable<Object?>) {
      for (final rawMemory in rawMemories.take(maximumMemories)) {
        final memoryMap = _korlixBrainVaultMap(rawMemory);

        if (memoryMap != null) {
          memories.add(KorlixBrainVaultMemory.fromJson(memoryMap));
        }
      }
    }

    final versions = <KorlixBrainVaultVersion>[];
    final rawVersions = map['versions'];

    if (rawVersions is Iterable<Object?>) {
      for (final rawVersion in rawVersions.take(maximumVersions)) {
        final versionMap = _korlixBrainVaultMap(rawVersion);

        if (versionMap != null) {
          versions.add(KorlixBrainVaultVersion.fromJson(versionMap));
        }
      }
    }

    final mode = _korlixBrainVaultText(
      map['mode'],
      maximum: 32,
      fallback: templateMode,
    );

    return KorlixBrainVaultPackage(
      schema: schemaId,
      mode: mode == privateBackupMode ? privateBackupMode : templateMode,
      exportedAt:
          DateTime.tryParse(
            _korlixBrainVaultText(
              map['exportedAt'] ?? map['exported_at'],
              maximum: 64,
            ),
          )?.toUtc() ??
          DateTime.now().toUtc(),
      agent: KorlixBrainVaultAgent.fromJson(rawAgent),
      memories: List<KorlixBrainVaultMemory>.unmodifiable(memories),
      versions: List<KorlixBrainVaultVersion>.unmodifiable(versions),
    );
  }

  KorlixBrainVaultPackage withSensitiveMemories(bool includeSensitiveMemories) {
    final filtered = includeSensitiveMemories
        ? memories
        : memories.where((memory) => !memory.sensitive).toList(growable: false);

    return KorlixBrainVaultPackage(
      schema: schema,
      mode: mode,
      exportedAt: exportedAt,
      agent: agent,
      memories: List<KorlixBrainVaultMemory>.unmodifiable(filtered),
      versions: versions,
    );
  }

  List<KorlixLiveConvoMemoryDraft> memoryDrafts({
    required bool includeSensitiveMemories,
  }) {
    return memories
        .where((memory) => includeSensitiveMemories || !memory.sensitive)
        .map((memory) => memory.toMemoryDraft())
        .toList(growable: false);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schema': schemaId,
      'mode': mode,
      'exportedAt': exportedAt.toIso8601String(),
      'agent': agent.toJson(),
      'memories': memories.map((memory) => memory.toJson()).toList(),
      'versions': versions.map((version) => version.toJson()).toList(),
      'notice': <String, dynamic>{
        'purpose':
            'Portable KORLIX agent configuration and approved memory backup.',
        'containsSensitiveMemories': sensitiveMemoryCount > 0,
        'trainingHistoryIsReferenceOnly': true,
        'excluded': const <String>[
          'authentication tokens',
          'account identifiers',
          'API keys',
          'store purchases',
          'AI GAS balances',
          'subscription data',
          'raw voice recordings',
          'temporary LIVE CONVO context',
          'hidden KORLIX system instructions',
        ],
      },
    };
  }

  String encodePretty() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }

  String get suggestedFileName {
    final slug = agent.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    final stamp = exportedAt
        .toIso8601String()
        .replaceAll(RegExp(r'[-:]'), '')
        .replaceAll(RegExp(r'\..+$'), '')
        .replaceAll('T', '_');

    return '${slug.isEmpty ? 'korlix_agent' : slug}_$stamp.korlixbrain';
  }
}

// KORLIX_BRAIN_VAULT_BUILD131_V1_END
