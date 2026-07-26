// KORLIX_LIVE_CONVO_AGENT_MODEL_BUILD131_BEGIN

String _korlixAgentString(
  Object? value, {
  String fallback = '',
  int maximum = 12000,
}) {
  final text = (value ?? '').toString().trim();

  if (text.isEmpty) {
    return fallback;
  }

  if (text.length <= maximum) {
    return text;
  }

  return text.substring(0, maximum);
}

String _korlixAgentId(
  Object? value, {
  String fallback = 'general',
}) {
  final normalized = (value ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  if (normalized.isEmpty ||
      !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(normalized)) {
    return fallback;
  }

  return normalized.length <= 96
      ? normalized
      : normalized.substring(0, 96);
}

bool _korlixAgentBool(
  Object? value, {
  bool fallback = false,
}) {
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

int _korlixAgentInt(
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

List<String> _korlixAgentStringList(
  Object? value, {
  List<String> fallback = const <String>[],
  int maximumItems = 50,
  int maximumLength = 160,
}) {
  if (value is! Iterable<Object?>) {
    return List<String>.unmodifiable(fallback);
  }

  final result = <String>[];
  final seen = <String>{};

  for (final item in value) {
    final clean = _korlixAgentString(
      item,
      maximum: maximumLength,
    );

    final key = clean.toLowerCase();

    if (clean.isEmpty || !seen.add(key)) {
      continue;
    }

    result.add(clean);

    if (result.length >= maximumItems) {
      break;
    }
  }

  return List<String>.unmodifiable(result);
}

Map<String, dynamic>? _korlixAgentMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }

  return null;
}

DateTime? _korlixAgentDateTime(Object? value) {
  final text = (value ?? '').toString().trim();

  if (text.isEmpty) {
    return null;
  }

  return DateTime.tryParse(text)?.toUtc();
}

String _korlixAgentAccent(
  Object? value, {
  String fallback = '21D4F4',
}) {
  final candidate = (value ?? '')
      .toString()
      .trim()
      .replaceFirst('#', '')
      .toUpperCase();

  return RegExp(r'^[0-9A-F]{6}$').hasMatch(candidate)
      ? candidate
      : fallback;
}

class KorlixLiveConvoAgent {
  const KorlixLiveConvoAgent({
    required this.id,
    required this.name,
    required this.description,
    required this.iconName,
    required this.accentHex,
    required this.mission,
    this.trainingInstructions = '',
    this.toolIds = const <String>['general_chat'],
    this.memoryEnabled = true,
    this.memoryCount = 0,
    this.isCustom = false,
    this.active = true,
    this.version = 1,
    this.createdAt,
    this.updatedAt,
    this.persistenceConfigured = false,
  });

  final String id;
  final String name;
  final String description;
  final String iconName;
  final String accentHex;
  final String mission;
  final String trainingInstructions;
  final List<String> toolIds;
  final bool memoryEnabled;
  final int memoryCount;
  final bool isCustom;
  final bool active;
  final int version;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool persistenceConfigured;

  bool get isBuiltIn => !isCustom;

  bool get canUseLiveDocs => toolIds.contains('live_docs');

  bool get canUseImageGeneration => toolIds.contains('image_generation');

  bool get canUseMemory => memoryEnabled && toolIds.contains('memory');

  bool get hasPublishedTraining => trainingInstructions.trim().isNotEmpty;

  bool get memoryPersistenceReady =>
      canUseMemory && persistenceConfigured;

  String get memorySummary {
    if (!memoryEnabled) {
      return 'Memory off';
    }

    if (!persistenceConfigured) {
      return 'Memory setup required';
    }

    return memoryCount == 1
        ? '1 memory'
        : '$memoryCount memories';
  }

  factory KorlixLiveConvoAgent.fromJson(
    Map<String, dynamic> json,
  ) {
    final id = _korlixAgentId(
      json['id'] ??
          json['agentId'] ??
          json['agent_id'],
    );

    final fallback = KorlixLiveConvoAgent.fallbackForId(id);

    final rawTools =
        json['toolIds'] ??
        json['tool_ids'] ??
        json['tools'];

    return KorlixLiveConvoAgent(
      id: id,

      name: _korlixAgentString(
        json['name'],
        fallback: fallback.name,
        maximum: 80,
      ),

      description: _korlixAgentString(
        json['description'],
        fallback: fallback.description,
        maximum: 240,
      ),

      iconName: _korlixAgentString(
        json['icon'] ??
            json['iconName'] ??
            json['icon_name'],
        fallback: fallback.iconName,
        maximum: 64,
      ),

      accentHex: _korlixAgentAccent(
        json['accent'] ??
            json['accentHex'] ??
            json['accent_hex'],
        fallback: fallback.accentHex,
      ),

      mission: _korlixAgentString(
        json['mission'],
        fallback: fallback.mission,
        maximum: 2400,
      ),

      trainingInstructions: _korlixAgentString(
        json['trainingInstructions'] ??
            json['training_instructions'],
        maximum: 12000,
      ),

      toolIds: _korlixAgentStringList(
        rawTools,
        fallback: fallback.toolIds,
      ),

      memoryEnabled: _korlixAgentBool(
        json['memoryEnabled'] ??
            json['memory_enabled'],
        fallback: fallback.memoryEnabled,
      ),

      memoryCount: _korlixAgentInt(
        json['memoryCount'] ??
            json['memory_count'],
        minimum: 0,
      ),

      isCustom: _korlixAgentBool(
        json['isCustom'] ??
            json['is_custom'],
        fallback: fallback.isCustom,
      ),

      active: _korlixAgentBool(
        json['active'],
        fallback: true,
      ),

      version: _korlixAgentInt(
        json['version'],
        fallback: 1,
        minimum: 1,
      ),

      createdAt: _korlixAgentDateTime(
        json['createdAt'] ??
            json['created_at'],
      ),

      updatedAt: _korlixAgentDateTime(
        json['updatedAt'] ??
            json['updated_at'],
      ),

      persistenceConfigured: _korlixAgentBool(
        json['persistenceConfigured'] ??
            json['persistence_configured'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'description': description,
      'icon': iconName,
      'accent': accentHex,
      'mission': mission,
      'trainingInstructions': trainingInstructions,
      'toolIds': toolIds,
      'memoryEnabled': memoryEnabled,
      'memoryCount': memoryCount,
      'isCustom': isCustom,
      'active': active,
      'version': version,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'persistenceConfigured': persistenceConfigured,
    };
  }

  KorlixLiveConvoAgent copyWith({
    String? name,
    String? description,
    String? iconName,
    String? accentHex,
    String? mission,
    String? trainingInstructions,
    List<String>? toolIds,
    bool? memoryEnabled,
    int? memoryCount,
    bool? isCustom,
    bool? active,
    int? version,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? persistenceConfigured,
  }) {
    return KorlixLiveConvoAgent(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      iconName: iconName ?? this.iconName,
      accentHex: accentHex ?? this.accentHex,
      mission: mission ?? this.mission,
      trainingInstructions:
          trainingInstructions ?? this.trainingInstructions,
      toolIds: toolIds ?? this.toolIds,
      memoryEnabled: memoryEnabled ?? this.memoryEnabled,
      memoryCount: memoryCount ?? this.memoryCount,
      isCustom: isCustom ?? this.isCustom,
      active: active ?? this.active,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      persistenceConfigured:
          persistenceConfigured ?? this.persistenceConfigured,
    );
  }

  static KorlixLiveConvoAgent fallbackForId(String value) {
    final id = _korlixAgentId(value);

    for (final agent in builtInFallbacks) {
      if (agent.id == id) {
        return agent;
      }
    }

    return generalFallback;
  }

  static const KorlixLiveConvoAgent generalFallback =
      KorlixLiveConvoAgent(
        id: 'general',
        name: 'General Korlix',
        description:
            'Flexible everyday conversation and problem solving.',
        iconName: 'auto_awesome',
        accentHex: '21D4F4',
        mission:
            'Handle broad requests naturally and use specialist tools '
            'only when they are genuinely useful.',
        toolIds: <String>[
          'general_chat',
          'live_docs',
          'file_analysis',
          'image_generation',
          'image_improvement',
          'camera',
          'memory',
          'agent_training',
        ],
      );

  static const List<KorlixLiveConvoAgent> builtInFallbacks =
      <KorlixLiveConvoAgent>[
        generalFallback,

        KorlixLiveConvoAgent(
          id: 'doc_wizard',
          name: 'Doc Wizard',
          description:
              'Reports, spreadsheets, Word documents, and PDFs.',
          iconName: 'description',
          accentHex: '62D6A7',
          mission:
              'Plan, create, revise, and explain professional '
              'documents without inventing facts.',
          toolIds: <String>[
            'general_chat',
            'live_docs',
            'file_analysis',
            'memory',
            'agent_training',
          ],
        ),

        KorlixLiveConvoAgent(
          id: 'language_teacher',
          name: 'Language Teacher',
          description:
              'Conversation practice, lessons, corrections, and vocabulary.',
          iconName: 'translate',
          accentHex: 'F2C14E',
          mission:
              'Teach the chosen language at the requested level and '
              'remember approved learning goals.',
          toolIds: <String>[
            'general_chat',
            'file_analysis',
            'memory',
            'agent_training',
          ],
        ),

        KorlixLiveConvoAgent(
          id: 'my_assistant',
          name: 'My Assistant',
          description:
              'Personal planning, writing, organization, and follow-through.',
          iconName: 'support_agent',
          accentHex: 'B794F4',
          mission:
              'Act as a reliable personal assistant while confirming '
              'consequential actions and sensitive memories.',
          toolIds: <String>[
            'general_chat',
            'live_docs',
            'file_analysis',
            'camera',
            'memory',
            'agent_training',
          ],
        ),

        KorlixLiveConvoAgent(
          id: 'graphic_designer',
          name: 'Graphic Designer',
          description:
              'Branding, design briefs, image creation, and visual direction.',
          iconName: 'palette',
          accentHex: 'FF8A65',
          mission:
              'Create clear visual concepts and follow approved '
              'brand memories without claiming nonexistent assets.',
          toolIds: <String>[
            'general_chat',
            'file_analysis',
            'image_generation',
            'image_improvement',
            'camera',
            'memory',
            'agent_training',
          ],
        ),
      ];
}

class KorlixLiveConvoAgentMemory {
  const KorlixLiveConvoAgentMemory({
    required this.id,
    required this.agentId,
    required this.kind,
    required this.content,
    this.label = '',
    this.tags = const <String>[],
    this.importance = 3,
    this.sensitive = false,
    this.source = 'user_confirmed',
    this.active = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String agentId;
  final String kind;
  final String label;
  final String content;
  final List<String> tags;
  final int importance;
  final bool sensitive;
  final String source;
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory KorlixLiveConvoAgentMemory.fromJson(
    Map<String, dynamic> json,
  ) {
    return KorlixLiveConvoAgentMemory(
      id: _korlixAgentString(
        json['id'],
        maximum: 160,
      ),

      agentId: _korlixAgentId(
        json['agentId'] ??
            json['agent_id'],
      ),

      kind: _korlixAgentId(
        json['kind'],
        fallback: 'preference',
      ),

      label: _korlixAgentString(
        json['label'],
        maximum: 120,
      ),

      content: _korlixAgentString(
        json['content'],
        maximum: 4000,
      ),

      tags: _korlixAgentStringList(
        json['tags'],
        maximumItems: 12,
        maximumLength: 48,
      ),

      importance: _korlixAgentInt(
        json['importance'],
        fallback: 3,
        minimum: 1,
        maximum: 5,
      ),

      sensitive: _korlixAgentBool(
        json['sensitive'],
      ),

      source: _korlixAgentString(
        json['source'],
        fallback: 'user_confirmed',
        maximum: 80,
      ),

      active: _korlixAgentBool(
        json['active'],
        fallback: true,
      ),

      createdAt: _korlixAgentDateTime(
        json['createdAt'] ??
            json['created_at'],
      ),

      updatedAt: _korlixAgentDateTime(
        json['updatedAt'] ??
            json['updated_at'],
      ),
    );
  }
}

class KorlixLiveConvoAgentModelProof {
  const KorlixLiveConvoAgentModelProof({
    this.liveConvoModel = '',
    this.liveDocsDocumentModel = '',
    this.liveDocsReasoningEffort = '',
    this.deterministicAuditEngine = false,
  });

  final String liveConvoModel;
  final String liveDocsDocumentModel;
  final String liveDocsReasoningEffort;
  final bool deterministicAuditEngine;

  factory KorlixLiveConvoAgentModelProof.fromJson(
    Map<String, dynamic> json,
  ) {
    return KorlixLiveConvoAgentModelProof(
      liveConvoModel: _korlixAgentString(
        json['liveConvoModel'] ??
            json['live_convo_model'],
        maximum: 160,
      ),

      liveDocsDocumentModel: _korlixAgentString(
        json['liveDocsDocumentModel'] ??
            json['live_docs_document_model'],
        maximum: 160,
      ),

      liveDocsReasoningEffort: _korlixAgentString(
        json['liveDocsReasoningEffort'] ??
            json['live_docs_reasoning_effort'],
        maximum: 40,
      ),

      deterministicAuditEngine: _korlixAgentBool(
        json['deterministicAuditEngine'] ??
            json['deterministic_audit_engine'],
      ),
    );
  }

  bool get provesGpt56DocumentReasoning {
    return liveDocsDocumentModel == 'gpt-5.6' &&
        liveDocsReasoningEffort == 'high';
  }
}

class KorlixLiveConvoAppliedMemory {
  const KorlixLiveConvoAppliedMemory({
    required this.id,
    required this.kind,
    required this.label,
    required this.importance,
    required this.sensitive,
  });

  final String id;
  final String kind;
  final String label;
  final int importance;
  final bool sensitive;

  factory KorlixLiveConvoAppliedMemory.fromJson(
    Map<String, dynamic> json,
  ) {
    return KorlixLiveConvoAppliedMemory(
      id: _korlixAgentString(
        json['id'],
        maximum: 160,
      ),

      kind: _korlixAgentId(
        json['kind'],
        fallback: 'preference',
      ),

      label: _korlixAgentString(
        json['label'],
        maximum: 120,
      ),

      importance: _korlixAgentInt(
        json['importance'],
        fallback: 3,
        minimum: 1,
        maximum: 5,
      ),

      sensitive: _korlixAgentBool(
        json['sensitive'],
      ),
    );
  }
}

class KorlixLiveConvoAgentRuntime {
  const KorlixLiveConvoAgentRuntime({
    required this.agent,
    this.toolIds = const <String>[],
    this.memoryCount = 0,
    this.appliedMemories = const <KorlixLiveConvoAppliedMemory>[],
    this.modelProof = const KorlixLiveConvoAgentModelProof(),
    this.persistenceConfigured = false,
    this.runtimeVersion = '',
  });

  final KorlixLiveConvoAgent agent;
  final List<String> toolIds;
  final int memoryCount;
  final List<KorlixLiveConvoAppliedMemory> appliedMemories;
  final KorlixLiveConvoAgentModelProof modelProof;
  final bool persistenceConfigured;
  final String runtimeVersion;

  factory KorlixLiveConvoAgentRuntime.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawAgent = _korlixAgentMap(json['agent']);

    final rawMemories = json['appliedMemories'] ??
        json['applied_memories'];

    final appliedMemories = <KorlixLiveConvoAppliedMemory>[];

    if (rawMemories is Iterable<Object?>) {
      for (final item in rawMemories) {
        final map = _korlixAgentMap(item);

        if (map != null) {
          appliedMemories.add(
            KorlixLiveConvoAppliedMemory.fromJson(map),
          );
        }
      }
    }

    final rawProof = _korlixAgentMap(
      json['modelProof'] ??
          json['model_proof'],
    );

    final persistenceConfigured = _korlixAgentBool(
      json['persistenceConfigured'] ??
          json['persistence_configured'],
    );

    final parsedAgent = rawAgent == null
        ? KorlixLiveConvoAgent.generalFallback
        : KorlixLiveConvoAgent.fromJson(rawAgent);

    return KorlixLiveConvoAgentRuntime(
      agent: parsedAgent.copyWith(
        persistenceConfigured: persistenceConfigured,
      ),

      toolIds: _korlixAgentStringList(
        json['toolIds'] ??
            json['tool_ids'],
        fallback: parsedAgent.toolIds,
      ),

      memoryCount: _korlixAgentInt(
        json['memoryCount'] ??
            json['memory_count'],
        minimum: 0,
      ),

      appliedMemories:
          List<KorlixLiveConvoAppliedMemory>.unmodifiable(
        appliedMemories,
      ),

      modelProof: rawProof == null
          ? const KorlixLiveConvoAgentModelProof()
          : KorlixLiveConvoAgentModelProof.fromJson(rawProof),

      persistenceConfigured: persistenceConfigured,

      runtimeVersion: _korlixAgentString(
        json['runtimeVersion'] ??
            json['runtime_version'],
        maximum: 120,
      ),
    );
  }
}

class KorlixLiveConvoAgentTrainingUpdate {
  const KorlixLiveConvoAgentTrainingUpdate({
    required this.instructions,
    required this.confirmed,
    this.toolIds,
    this.memoryEnabled,
    this.source = 'user_confirmed_training',
  });

  final String instructions;
  final bool confirmed;
  final List<String>? toolIds;
  final bool? memoryEnabled;
  final String source;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'confirmed': confirmed,
      'trainingInstructions': instructions.trim(),
      if (toolIds != null) 'toolIds': toolIds,
      if (memoryEnabled != null)
        'memoryEnabled': memoryEnabled,
      'source': source.trim(),
    };
  }
}

class KorlixLiveConvoCustomAgentDraft {
  const KorlixLiveConvoCustomAgentDraft({
    required this.name,
    required this.mission,
    this.description = '',
    this.iconName = 'smart_toy',
    this.accentHex = '21D4F4',
    this.trainingInstructions = '',
    this.toolIds = const <String>[
      'general_chat',
      'memory',
      'agent_training',
    ],
    this.memoryEnabled = true,
  });

  final String name;
  final String description;
  final String mission;
  final String iconName;
  final String accentHex;
  final String trainingInstructions;
  final List<String> toolIds;
  final bool memoryEnabled;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name.trim(),
      'description': description.trim(),
      'mission': mission.trim(),
      'icon': iconName.trim(),
      'accent': _korlixAgentAccent(accentHex),
      'trainingInstructions': trainingInstructions.trim(),
      'toolIds': toolIds,
      'memoryEnabled': memoryEnabled,
    };
  }
}

class KorlixLiveConvoMemoryDraft {
  const KorlixLiveConvoMemoryDraft({
    required this.content,
    required this.confirmed,
    this.kind = 'preference',
    this.label = '',
    this.tags = const <String>[],
    this.importance = 3,
    this.sensitive = false,
    this.source = 'user_confirmed',
  });

  final String content;
  final bool confirmed;
  final String kind;
  final String label;
  final List<String> tags;
  final int importance;
  final bool sensitive;
  final String source;

  Map<String, dynamic> toJson() {
    final safeImportance = importance < 1
        ? 1
        : importance > 5
            ? 5
            : importance;

    return <String, dynamic>{
      'confirmed': confirmed,
      'kind': kind.trim(),
      'label': label.trim(),
      'content': content.trim(),
      'tags': tags,
      'importance': safeImportance,
      'sensitive': sensitive,
      'source': source.trim(),
    };
  }
}

class KorlixLiveConvoAgentApiContract {
  const KorlixLiveConvoAgentApiContract._();

  static const String catalogPath =
      '/api/live-convo/agents';

  static const String modelProofPath =
      '/api/live-convo/agents/model-proof';

  static String agentPath(String agentId) {
    return '$catalogPath/${Uri.encodeComponent(agentId)}';
  }

  static String runtimePath(String agentId) {
    return '${agentPath(agentId)}/runtime';
  }

  static String trainingPath(String agentId) {
    return '${agentPath(agentId)}/training';
  }

  static String memoriesPath(String agentId) {
    return '${agentPath(agentId)}/memories';
  }

  static String forgetMemoryPath(String agentId) {
    return '${memoriesPath(agentId)}/forget';
  }

  static String memoryPath(
    String agentId,
    String memoryId,
  ) {
    return '${memoriesPath(agentId)}/'
        '${Uri.encodeComponent(memoryId)}';
  }

  static String versionsPath(String agentId) {
    return '${agentPath(agentId)}/versions';
  }

  static String restoreVersionPath(
    String agentId,
    int version,
  ) {
    return '${versionsPath(agentId)}/$version/restore';
  }
}

// KORLIX_LIVE_CONVO_AGENT_MODEL_BUILD131_END
