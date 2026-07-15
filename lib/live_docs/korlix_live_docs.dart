import 'dart:convert';

/// Document categories supported by the first Korlix LIVE DOCS contract.
enum KorlixLiveDocType {
  professionalLetter,
  businessProposal,
  businessReport,
  resumeAndCoverLetter,
  meetingSummary,
  custom,
}

extension KorlixLiveDocTypeValues on KorlixLiveDocType {
  String get wireValue {
    switch (this) {
      case KorlixLiveDocType.professionalLetter:
        return 'professional_letter';
      case KorlixLiveDocType.businessProposal:
        return 'business_proposal';
      case KorlixLiveDocType.businessReport:
        return 'business_report';
      case KorlixLiveDocType.resumeAndCoverLetter:
        return 'resume_cover_letter';
      case KorlixLiveDocType.meetingSummary:
        return 'meeting_summary';
      case KorlixLiveDocType.custom:
        return 'custom';
    }
  }

  String get displayName {
    switch (this) {
      case KorlixLiveDocType.professionalLetter:
        return 'Professional Letter';
      case KorlixLiveDocType.businessProposal:
        return 'Business Proposal';
      case KorlixLiveDocType.businessReport:
        return 'Business Report';
      case KorlixLiveDocType.resumeAndCoverLetter:
        return 'Résumé and Cover Letter';
      case KorlixLiveDocType.meetingSummary:
        return 'Meeting Summary';
      case KorlixLiveDocType.custom:
        return 'Custom Document';
    }
  }
}

KorlixLiveDocType korlixLiveDocTypeFromWire(Object? value) {
  final normalized = (value?.toString() ?? '').trim().toLowerCase();

  for (final candidate in KorlixLiveDocType.values) {
    if (candidate.wireValue == normalized) {
      return candidate;
    }
  }

  return KorlixLiveDocType.custom;
}

enum KorlixLiveDocOutputFormat { docx, pdf, plainText, markdown }

extension KorlixLiveDocOutputFormatValues on KorlixLiveDocOutputFormat {
  String get wireValue {
    switch (this) {
      case KorlixLiveDocOutputFormat.docx:
        return 'docx';
      case KorlixLiveDocOutputFormat.pdf:
        return 'pdf';
      case KorlixLiveDocOutputFormat.plainText:
        return 'txt';
      case KorlixLiveDocOutputFormat.markdown:
        return 'md';
    }
  }

  String get displayName {
    switch (this) {
      case KorlixLiveDocOutputFormat.docx:
        return 'Microsoft Word';
      case KorlixLiveDocOutputFormat.pdf:
        return 'PDF';
      case KorlixLiveDocOutputFormat.plainText:
        return 'Plain Text';
      case KorlixLiveDocOutputFormat.markdown:
        return 'Markdown';
    }
  }
}

KorlixLiveDocOutputFormat? korlixLiveDocOutputFormatFromWire(Object? value) {
  final normalized = (value?.toString() ?? '').trim().toLowerCase();

  for (final candidate in KorlixLiveDocOutputFormat.values) {
    if (candidate.wireValue == normalized) {
      return candidate;
    }
  }

  return null;
}

enum KorlixLiveDocJobStatus {
  draft,
  awaitingConfirmation,
  queued,
  processing,
  completed,
  failed,
  cancelled,
}

extension KorlixLiveDocJobStatusValues on KorlixLiveDocJobStatus {
  String get wireValue {
    switch (this) {
      case KorlixLiveDocJobStatus.draft:
        return 'draft';
      case KorlixLiveDocJobStatus.awaitingConfirmation:
        return 'awaiting_confirmation';
      case KorlixLiveDocJobStatus.queued:
        return 'queued';
      case KorlixLiveDocJobStatus.processing:
        return 'processing';
      case KorlixLiveDocJobStatus.completed:
        return 'completed';
      case KorlixLiveDocJobStatus.failed:
        return 'failed';
      case KorlixLiveDocJobStatus.cancelled:
        return 'cancelled';
    }
  }
}

KorlixLiveDocJobStatus korlixLiveDocJobStatusFromWire(Object? value) {
  final normalized = (value?.toString() ?? '').trim().toLowerCase();

  for (final candidate in KorlixLiveDocJobStatus.values) {
    if (candidate.wireValue == normalized) {
      return candidate;
    }
  }

  return KorlixLiveDocJobStatus.draft;
}

/// A user-authorized file that may be used by the Document Agent.
class KorlixLiveDocSourceFile {
  KorlixLiveDocSourceFile({
    required this.id,
    required this.displayName,
    required this.mimeType,
    required this.sizeBytes,
    required DateTime uploadedAt,
    this.storagePath,
  }) : uploadedAt = uploadedAt.toUtc();

  final String id;
  final String displayName;
  final String mimeType;
  final int sizeBytes;
  final DateTime uploadedAt;
  final String? storagePath;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'display_name': displayName,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      'uploaded_at': uploadedAt.toIso8601String(),
      if (storagePath != null) 'storage_path': storagePath,
    };
  }

  factory KorlixLiveDocSourceFile.fromJson(Map<String, dynamic> json) {
    final storagePath = _cleanString(json['storage_path']);

    return KorlixLiveDocSourceFile(
      id: _cleanString(json['id']),
      displayName: _cleanString(json['display_name']),
      mimeType: _cleanString(json['mime_type']),
      sizeBytes: _asInt(json['size_bytes']) ?? 0,
      uploadedAt: _asDateTime(json['uploaded_at']) ?? DateTime.now().toUtc(),
      storagePath: storagePath.isEmpty ? null : storagePath,
    );
  }
}

/// Confirmed specification generated from the LIVE CONVO interview.
class KorlixLiveDocBrief {
  KorlixLiveDocBrief({
    required this.id,
    required this.documentType,
    required this.title,
    required this.audience,
    required this.goal,
    this.tone = 'professional',
    this.targetLengthPages,
    List<String> requiredSections = const <String>[],
    List<KorlixLiveDocOutputFormat> outputFormats =
        const <KorlixLiveDocOutputFormat>[
          KorlixLiveDocOutputFormat.docx,
          KorlixLiveDocOutputFormat.pdf,
        ],
    List<KorlixLiveDocSourceFile> sourceFiles =
        const <KorlixLiveDocSourceFile>[],
    Map<String, String> confirmedFacts = const <String, String>{},
    List<String> unresolvedQuestions = const <String>[],
    this.allowWebResearch = false,
    required DateTime createdAt,
    DateTime? confirmedAt,
    this.approvedToStart = false,
  }) : requiredSections = List<String>.unmodifiable(
         _uniqueCleanStrings(requiredSections),
       ),
       outputFormats = List<KorlixLiveDocOutputFormat>.unmodifiable(
         <KorlixLiveDocOutputFormat>{...outputFormats},
       ),
       sourceFiles = List<KorlixLiveDocSourceFile>.unmodifiable(sourceFiles),
       confirmedFacts = Map<String, String>.unmodifiable(
         _cleanStringMap(confirmedFacts),
       ),
       unresolvedQuestions = List<String>.unmodifiable(
         _uniqueCleanStrings(unresolvedQuestions),
       ),
       createdAt = createdAt.toUtc(),
       confirmedAt = confirmedAt?.toUtc();

  final String id;
  final KorlixLiveDocType documentType;
  final String title;
  final String audience;
  final String goal;
  final String tone;
  final int? targetLengthPages;
  final List<String> requiredSections;
  final List<KorlixLiveDocOutputFormat> outputFormats;
  final List<KorlixLiveDocSourceFile> sourceFiles;
  final Map<String, String> confirmedFacts;
  final List<String> unresolvedQuestions;
  final bool allowWebResearch;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final bool approvedToStart;

  List<String> get validationErrors {
    final errors = <String>[];

    if (id.trim().isEmpty) {
      errors.add('The brief requires an ID.');
    }

    if (title.trim().isEmpty) {
      errors.add('Confirm the document title.');
    }

    if (audience.trim().isEmpty) {
      errors.add('Confirm who will read the document.');
    }

    if (goal.trim().isEmpty) {
      errors.add('Confirm the document goal.');
    }

    if (tone.trim().isEmpty) {
      errors.add('Confirm the writing tone.');
    }

    if (outputFormats.isEmpty) {
      errors.add('Select at least one output format.');
    }

    final pages = targetLengthPages;

    if (pages != null && (pages < 1 || pages > 100)) {
      errors.add('Target length must be between 1 and 100 pages.');
    }

    if (unresolvedQuestions.isNotEmpty) {
      errors.add('Resolve all open questions before starting the job.');
    }

    final sourceIds = <String>{};

    for (final sourceFile in sourceFiles) {
      if (sourceFile.id.trim().isEmpty) {
        errors.add('Every source file requires an ID.');
      } else if (!sourceIds.add(sourceFile.id)) {
        errors.add('Duplicate source file ID: ${sourceFile.id}.');
      }
    }

    if (approvedToStart && confirmedAt == null) {
      errors.add('An approved brief requires a confirmation timestamp.');
    }

    return List<String>.unmodifiable(errors);
  }

  bool get canRequestConfirmation => validationErrors.isEmpty;

  bool get canStartJob {
    return validationErrors.isEmpty && approvedToStart && confirmedAt != null;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'document_type': documentType.wireValue,
      'title': title,
      'audience': audience,
      'goal': goal,
      'tone': tone,
      'target_length_pages': targetLengthPages,
      'required_sections': requiredSections,
      'output_formats': outputFormats
          .map((format) => format.wireValue)
          .toList(growable: false),
      'source_files': sourceFiles
          .map((file) => file.toJson())
          .toList(growable: false),
      'confirmed_facts': confirmedFacts,
      'unresolved_questions': unresolvedQuestions,
      'allow_web_research': allowWebResearch,
      'created_at': createdAt.toIso8601String(),
      'confirmed_at': confirmedAt?.toIso8601String(),
      'approved_to_start': approvedToStart,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory KorlixLiveDocBrief.fromJson(Map<String, dynamic> json) {
    final parsedSourceFiles = <KorlixLiveDocSourceFile>[];
    final rawSourceFiles = json['source_files'];

    if (rawSourceFiles is List<dynamic>) {
      for (final item in rawSourceFiles) {
        if (item is Map<String, dynamic>) {
          parsedSourceFiles.add(KorlixLiveDocSourceFile.fromJson(item));
        }
      }
    }

    final parsedFormats = <KorlixLiveDocOutputFormat>[];

    for (final item in _asStringList(json['output_formats'])) {
      final parsed = korlixLiveDocOutputFormatFromWire(item);

      if (parsed != null && !parsedFormats.contains(parsed)) {
        parsedFormats.add(parsed);
      }
    }

    return KorlixLiveDocBrief(
      id: _cleanString(json['id']),
      documentType: korlixLiveDocTypeFromWire(json['document_type']),
      title: _cleanString(json['title']),
      audience: _cleanString(json['audience']),
      goal: _cleanString(json['goal']),
      tone: _cleanString(json['tone']).isEmpty
          ? 'professional'
          : _cleanString(json['tone']),
      targetLengthPages: _asInt(json['target_length_pages']),
      requiredSections: _asStringList(json['required_sections']),
      outputFormats: parsedFormats,
      sourceFiles: parsedSourceFiles,
      confirmedFacts: _asStringMap(json['confirmed_facts']),
      unresolvedQuestions: _asStringList(json['unresolved_questions']),
      allowWebResearch: _asBool(json['allow_web_research']),
      createdAt: _asDateTime(json['created_at']) ?? DateTime.now().toUtc(),
      confirmedAt: _asDateTime(json['confirmed_at']),
      approvedToStart: _asBool(json['approved_to_start']),
    );
  }

  factory KorlixLiveDocBrief.fromJsonString(String value) {
    final decoded = jsonDecode(value);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('LIVE DOCS brief must be a JSON object.');
    }

    return KorlixLiveDocBrief.fromJson(decoded);
  }

  /// Instruction sent to the future Document Agent after user confirmation.
  String toAgentInstruction() {
    final buffer = StringBuffer()
      ..writeln('KORLIX LIVE DOCS AGENT BRIEF')
      ..writeln()
      ..writeln('Document type: ${documentType.displayName}')
      ..writeln('Title: $title')
      ..writeln('Audience: $audience')
      ..writeln('Goal: $goal')
      ..writeln('Tone: $tone')
      ..writeln(
        'Target length: '
        '${targetLengthPages == null ? 'Use professional judgment' : '$targetLengthPages page(s)'}',
      )
      ..writeln(
        'Output formats: '
        '${outputFormats.map((format) => format.displayName).join(', ')}',
      )
      ..writeln(
        'Live web research authorized: ${allowWebResearch ? 'Yes' : 'No'}',
      )
      ..writeln()
      ..writeln('REQUIRED SECTIONS:');

    if (requiredSections.isEmpty) {
      buffer.writeln(
        '- Use a professional structure appropriate for the document type.',
      );
    } else {
      for (var index = 0; index < requiredSections.length; index += 1) {
        buffer.writeln('${index + 1}. ${requiredSections[index]}');
      }
    }

    buffer
      ..writeln()
      ..writeln('CONFIRMED FACTS:');

    if (confirmedFacts.isEmpty) {
      buffer.writeln('- No additional facts were confirmed.');
    } else {
      for (final fact in confirmedFacts.entries) {
        buffer.writeln('- ${fact.key}: ${fact.value}');
      }
    }

    buffer
      ..writeln()
      ..writeln('AUTHORIZED SOURCE FILES:');

    if (sourceFiles.isEmpty) {
      buffer.writeln('- No source files were supplied.');
    } else {
      for (final sourceFile in sourceFiles) {
        buffer.writeln(
          '- ${sourceFile.displayName} '
          '(${sourceFile.mimeType}, ${sourceFile.sizeBytes} bytes)',
        );
      }
    }

    buffer
      ..writeln()
      ..writeln('MANDATORY QUALITY RULES:')
      ..writeln('- Do not invent names, dates, amounts, quotations, or claims.')
      ..writeln(
        '- Use clear [CONFIRM ...] placeholders whenever a fact is missing.',
      )
      ..writeln(
        '- Keep user-provided facts separate from calculations or research.',
      )
      ..writeln(
        '- Preserve source attribution and list assumptions in the result.',
      )
      ..writeln(
        '- Produce an editable draft that the user must review before use.',
      );

    return buffer.toString().trim();
  }
}

/// Persistent job state returned by the future LIVE DOCS backend.
class KorlixLiveDocJob {
  KorlixLiveDocJob({
    required this.id,
    required this.briefId,
    required this.status,
    required int progressPercent,
    required this.stage,
    List<KorlixLiveDocSourceFile> outputFiles =
        const <KorlixLiveDocSourceFile>[],
    this.errorMessage,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : progressPercent = progressPercent < 0
           ? 0
           : (progressPercent > 100 ? 100 : progressPercent),
       outputFiles = List<KorlixLiveDocSourceFile>.unmodifiable(outputFiles),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc();

  final String id;
  final String briefId;
  final KorlixLiveDocJobStatus status;
  final int progressPercent;
  final String stage;
  final List<KorlixLiveDocSourceFile> outputFiles;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isTerminal {
    switch (status) {
      case KorlixLiveDocJobStatus.completed:
      case KorlixLiveDocJobStatus.failed:
      case KorlixLiveDocJobStatus.cancelled:
        return true;
      case KorlixLiveDocJobStatus.draft:
      case KorlixLiveDocJobStatus.awaitingConfirmation:
      case KorlixLiveDocJobStatus.queued:
      case KorlixLiveDocJobStatus.processing:
        return false;
    }
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'brief_id': briefId,
      'status': status.wireValue,
      'progress_percent': progressPercent,
      'stage': stage,
      'output_files': outputFiles
          .map((file) => file.toJson())
          .toList(growable: false),
      'error_message': errorMessage,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory KorlixLiveDocJob.fromJson(Map<String, dynamic> json) {
    final parsedOutputs = <KorlixLiveDocSourceFile>[];
    final rawOutputs = json['output_files'];

    if (rawOutputs is List<dynamic>) {
      for (final item in rawOutputs) {
        if (item is Map<String, dynamic>) {
          parsedOutputs.add(KorlixLiveDocSourceFile.fromJson(item));
        }
      }
    }

    final error = _cleanString(json['error_message']);

    return KorlixLiveDocJob(
      id: _cleanString(json['id']),
      briefId: _cleanString(json['brief_id']),
      status: korlixLiveDocJobStatusFromWire(json['status']),
      progressPercent: _asInt(json['progress_percent']) ?? 0,
      stage: _cleanString(json['stage']),
      outputFiles: parsedOutputs,
      errorMessage: error.isEmpty ? null : error,
      createdAt: _asDateTime(json['created_at']) ?? DateTime.now().toUtc(),
      updatedAt: _asDateTime(json['updated_at']) ?? DateTime.now().toUtc(),
    );
  }
}

/// Incrementally receives structured updates from the LIVE CONVO interview.
class KorlixLiveDocsBriefBuilder {
  KorlixLiveDocType documentType = KorlixLiveDocType.custom;
  String title = '';
  String audience = '';
  String goal = '';
  String tone = 'professional';
  int? targetLengthPages;
  bool allowWebResearch = false;

  final List<String> _requiredSections = <String>[];
  final List<KorlixLiveDocOutputFormat> _outputFormats =
      <KorlixLiveDocOutputFormat>[
        KorlixLiveDocOutputFormat.docx,
        KorlixLiveDocOutputFormat.pdf,
      ];
  final List<KorlixLiveDocSourceFile> _sourceFiles =
      <KorlixLiveDocSourceFile>[];
  final Map<String, String> _confirmedFacts = <String, String>{};
  final List<String> _unresolvedQuestions = <String>[];

  void applyConversationUpdate(Map<String, dynamic> update) {
    if (update.containsKey('document_type')) {
      documentType = korlixLiveDocTypeFromWire(update['document_type']);
    }

    if (update.containsKey('title')) {
      title = _cleanString(update['title']);
    }

    if (update.containsKey('audience')) {
      audience = _cleanString(update['audience']);
    }

    if (update.containsKey('goal')) {
      goal = _cleanString(update['goal']);
    }

    if (update.containsKey('tone')) {
      final nextTone = _cleanString(update['tone']);
      tone = nextTone.isEmpty ? 'professional' : nextTone;
    }

    if (update.containsKey('target_length_pages')) {
      targetLengthPages = _asInt(update['target_length_pages']);
    }

    if (update.containsKey('allow_web_research')) {
      allowWebResearch = _asBool(update['allow_web_research']);
    }

    if (update.containsKey('required_sections')) {
      _requiredSections
        ..clear()
        ..addAll(
          _uniqueCleanStrings(_asStringList(update['required_sections'])),
        );
    }

    if (update.containsKey('output_formats')) {
      _outputFormats.clear();

      for (final rawFormat in _asStringList(update['output_formats'])) {
        final parsed = korlixLiveDocOutputFormatFromWire(rawFormat);

        if (parsed != null && !_outputFormats.contains(parsed)) {
          _outputFormats.add(parsed);
        }
      }
    }

    if (update.containsKey('confirmed_facts')) {
      _confirmedFacts
        ..clear()
        ..addAll(_asStringMap(update['confirmed_facts']));
    }

    if (update.containsKey('unresolved_questions')) {
      _unresolvedQuestions
        ..clear()
        ..addAll(
          _uniqueCleanStrings(_asStringList(update['unresolved_questions'])),
        );
    }
  }

  void addRequiredSection(String section) {
    _addUniqueString(_requiredSections, section);
  }

  void addOutputFormat(KorlixLiveDocOutputFormat format) {
    if (!_outputFormats.contains(format)) {
      _outputFormats.add(format);
    }
  }

  void addSourceFile(KorlixLiveDocSourceFile sourceFile) {
    final existingIndex = _sourceFiles.indexWhere(
      (existing) => existing.id == sourceFile.id,
    );

    if (existingIndex >= 0) {
      _sourceFiles[existingIndex] = sourceFile;
    } else {
      _sourceFiles.add(sourceFile);
    }
  }

  void putConfirmedFact(String name, String value) {
    final cleanName = name.trim();
    final cleanValue = value.trim();

    if (cleanName.isEmpty || cleanValue.isEmpty) {
      return;
    }

    _confirmedFacts[cleanName] = cleanValue;
  }

  void addUnresolvedQuestion(String question) {
    _addUniqueString(_unresolvedQuestions, question);
  }

  void resolveQuestion(String question) {
    final normalized = question.trim().toLowerCase();

    _unresolvedQuestions.removeWhere(
      (existing) => existing.toLowerCase() == normalized,
    );
  }

  KorlixLiveDocBrief buildDraft({required String id, DateTime? createdAt}) {
    return _build(
      id: id,
      createdAt: createdAt ?? DateTime.now().toUtc(),
      approvedToStart: false,
      confirmedAt: null,
    );
  }

  KorlixLiveDocBrief buildApproved({
    required String id,
    DateTime? createdAt,
    DateTime? confirmedAt,
  }) {
    final brief = _build(
      id: id,
      createdAt: createdAt ?? DateTime.now().toUtc(),
      approvedToStart: true,
      confirmedAt: confirmedAt ?? DateTime.now().toUtc(),
    );

    if (!brief.canStartJob) {
      throw StateError(
        'LIVE DOCS brief is incomplete: '
        '${brief.validationErrors.join(' ')}',
      );
    }

    return brief;
  }

  KorlixLiveDocBrief _build({
    required String id,
    required DateTime createdAt,
    required bool approvedToStart,
    required DateTime? confirmedAt,
  }) {
    return KorlixLiveDocBrief(
      id: id.trim(),
      documentType: documentType,
      title: title.trim(),
      audience: audience.trim(),
      goal: goal.trim(),
      tone: tone.trim().isEmpty ? 'professional' : tone.trim(),
      targetLengthPages: targetLengthPages,
      requiredSections: _requiredSections,
      outputFormats: _outputFormats,
      sourceFiles: _sourceFiles,
      confirmedFacts: _confirmedFacts,
      unresolvedQuestions: _unresolvedQuestions,
      allowWebResearch: allowWebResearch,
      createdAt: createdAt,
      confirmedAt: confirmedAt,
      approvedToStart: approvedToStart,
    );
  }
}

/// App/backend JSON contract. This file does not make network requests.
class KorlixLiveDocsApiContract {
  static const String schemaVersion = 'korlix.live_docs.v1';

  static const String createJobPath = '/api/live-docs/jobs';

  static String jobPath(String jobId) {
    return '$createJobPath/${Uri.encodeComponent(jobId)}';
  }

  static String cancelJobPath(String jobId) {
    return '${jobPath(jobId)}/cancel';
  }

  static String revisionPath(String jobId) {
    return '${jobPath(jobId)}/revisions';
  }

  static Map<String, dynamic> createJobPayload({
    required KorlixLiveDocBrief brief,
    required String idempotencyKey,
    required String clientBuild,
  }) {
    if (!brief.canStartJob) {
      throw StateError(
        'A LIVE DOCS job requires an approved and complete brief.',
      );
    }

    if (idempotencyKey.trim().isEmpty) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'The idempotency key cannot be empty.',
      );
    }

    return <String, dynamic>{
      'schema_version': schemaVersion,
      'idempotency_key': idempotencyKey.trim(),
      'client_build': clientBuild.trim(),
      'brief': brief.toJson(),
    };
  }

  static Map<String, dynamic> revisionPayload({
    required String instruction,
    required int baseVersion,
  }) {
    if (instruction.trim().isEmpty) {
      throw ArgumentError.value(
        instruction,
        'instruction',
        'The revision instruction cannot be empty.',
      );
    }

    if (baseVersion < 1) {
      throw ArgumentError.value(
        baseVersion,
        'baseVersion',
        'The base version must be at least 1.',
      );
    }

    return <String, dynamic>{
      'schema_version': schemaVersion,
      'instruction': instruction.trim(),
      'base_version': baseVersion,
    };
  }
}

String _cleanString(Object? value) {
  return (value?.toString() ?? '').trim();
}

int? _asInt(Object? value) {
  if (value == null) {
    return null;
  }

  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value.toString().trim());
}

bool _asBool(Object? value) {
  if (value is bool) {
    return value;
  }

  final normalized = (value?.toString() ?? '').trim().toLowerCase();

  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}

DateTime? _asDateTime(Object? value) {
  if (value is DateTime) {
    return value.toUtc();
  }

  final text = _cleanString(value);

  if (text.isEmpty) {
    return null;
  }

  return DateTime.tryParse(text)?.toUtc();
}

List<String> _asStringList(Object? value) {
  if (value is! List<dynamic>) {
    return const <String>[];
  }

  return value
      .map(_cleanString)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, String> _asStringMap(Object? value) {
  if (value is! Map<String, dynamic>) {
    return const <String, String>{};
  }

  final result = <String, String>{};

  for (final entry in value.entries) {
    final key = entry.key.trim();
    final itemValue = _cleanString(entry.value);

    if (key.isNotEmpty && itemValue.isNotEmpty) {
      result[key] = itemValue;
    }
  }

  return result;
}

List<String> _uniqueCleanStrings(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];

  for (final value in values) {
    final cleanValue = value.trim();
    final comparisonValue = cleanValue.toLowerCase();

    if (cleanValue.isNotEmpty && seen.add(comparisonValue)) {
      result.add(cleanValue);
    }
  }

  return result;
}

Map<String, String> _cleanStringMap(Map<String, String> values) {
  final result = <String, String>{};

  for (final entry in values.entries) {
    final key = entry.key.trim();
    final value = entry.value.trim();

    if (key.isNotEmpty && value.isNotEmpty) {
      result[key] = value;
    }
  }

  return result;
}

void _addUniqueString(List<String> values, String value) {
  final cleanValue = value.trim();

  if (cleanValue.isEmpty) {
    return;
  }

  final exists = values.any(
    (existing) => existing.toLowerCase() == cleanValue.toLowerCase(),
  );

  if (!exists) {
    values.add(cleanValue);
  }
}
