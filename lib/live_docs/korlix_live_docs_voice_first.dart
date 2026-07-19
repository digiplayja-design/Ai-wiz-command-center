// KORLIX_LIVE_DOCS_VOICE_FIRST_BUILD131_BEGIN
import 'korlix_live_docs.dart';

class KorlixLiveDocsVoiceFirstPlan {
  const KorlixLiveDocsVoiceFirstPlan({
    required this.brief,
    required this.instructions,
    required this.formats,
    required this.spokenConfirmation,
  });

  final KorlixLiveDocBrief brief;
  final String instructions;
  final List<KorlixLiveDocOutputFormat> formats;
  final String spokenConfirmation;

  Map<String, dynamic> toRealtimeSummary() {
    return <String, dynamic>{
      'success': false,
      'code': 'voice_confirmation_required',
      'message': spokenConfirmation,
      'title': brief.title,
      'audience': brief.audience,
      'tone': brief.tone,
      'allow_web_research': brief.allowWebResearch,
      'formats': formats
          .map((format) => format.wireValue)
          .toList(growable: false),
      'source_count': brief.sourceFiles.length,
      'credits_required': 3,
    };
  }
}

String _korlixVoiceFirstClean(Object? value, {int max = 12000}) {
  final clean = (value?.toString() ?? '').trim();
  return clean.length <= max ? clean : clean.substring(0, max);
}

List<KorlixLiveDocOutputFormat> _korlixVoiceFirstFormatsIn(String value) {
  final text = value.toLowerCase();
  final formats = <KorlixLiveDocOutputFormat>[];

  void add(KorlixLiveDocOutputFormat format) {
    if (!formats.contains(format)) {
      formats.add(format);
    }
  }

  if (RegExp(r'\b(xlsx|excel|spreadsheet|workbook)\b').hasMatch(text)) {
    add(KorlixLiveDocOutputFormat.xlsx);
  }

  if (RegExp(r'\b(docx|word|word document)\b').hasMatch(text)) {
    add(KorlixLiveDocOutputFormat.docx);
  }

  if (RegExp(r'\bpdf\b').hasMatch(text)) {
    add(KorlixLiveDocOutputFormat.pdf);
  }

  return formats;
}

List<KorlixLiveDocOutputFormat> _korlixVoiceFirstToolFormats(
  Iterable<Object?> values,
) {
  final formats = <KorlixLiveDocOutputFormat>[];

  for (final value in values) {
    final parsed = korlixLiveDocOutputFormatFromWire(value);
    if (parsed != null &&
        <KorlixLiveDocOutputFormat>{
          KorlixLiveDocOutputFormat.xlsx,
          KorlixLiveDocOutputFormat.docx,
          KorlixLiveDocOutputFormat.pdf,
        }.contains(parsed) &&
        !formats.contains(parsed)) {
      formats.add(parsed);
    }
  }

  return formats;
}

String _korlixVoiceFirstLatestFormatClause(String request) {
  final lower = request.toLowerCase();
  if (lower.isEmpty) {
    return '';
  }

  final formatMatches = RegExp(
    r'\b(xlsx|excel|spreadsheet|workbook|docx|word document|word|pdf)\b',
  ).allMatches(lower).toList(growable: false);

  if (formatMatches.isEmpty) {
    return '';
  }

  final last = formatMatches.last.start;
  var start = 0;

  for (final separator in <RegExp>[
    RegExp(r'[.!?;\n]'),
    RegExp(r','),
    RegExp(r'\b(?:instead|actually|rather|change that to|make that)\b'),
  ]) {
    for (final match in separator.allMatches(lower)) {
      if (match.end <= last && match.end > start) {
        start = match.end;
      }
    }
  }

  return lower.substring(start).trim();
}

List<KorlixLiveDocOutputFormat> korlixLiveDocsResolveVoiceFirstFormats({
  required String latestUserRequest,
  Iterable<Object?> toolFormats = const <Object?>[],
  bool spreadsheetSource = false,
  bool technicianAuditRequest = false,
}) {
  final latestClause = _korlixVoiceFirstLatestFormatClause(latestUserRequest);
  final spokenFormats = _korlixVoiceFirstFormatsIn(latestClause);

  if (spokenFormats.isNotEmpty) {
    return List<KorlixLiveDocOutputFormat>.unmodifiable(spokenFormats);
  }

  final structuredFormats = _korlixVoiceFirstToolFormats(toolFormats);
  if (structuredFormats.isNotEmpty) {
    return List<KorlixLiveDocOutputFormat>.unmodifiable(structuredFormats);
  }

  if (spreadsheetSource || technicianAuditRequest) {
    return const <KorlixLiveDocOutputFormat>[KorlixLiveDocOutputFormat.xlsx];
  }

  return const <KorlixLiveDocOutputFormat>[
    KorlixLiveDocOutputFormat.docx,
    KorlixLiveDocOutputFormat.pdf,
  ];
}

bool _korlixVoiceFirstIsSpreadsheet(KorlixLiveDocSourceFile file) {
  final name = file.displayName.toLowerCase();
  final mime = file.mimeType.toLowerCase();
  return name.endsWith('.xlsx') ||
      name.endsWith('.xls') ||
      name.endsWith('.csv') ||
      mime.contains('spreadsheet') ||
      mime.contains('excel') ||
      mime.contains('csv');
}

bool _korlixVoiceFirstIsTechnicianAudit(String value) {
  final text = value.toLowerCase();
  return text.contains('audit') &&
      (text.contains('technician') ||
          text.contains('installer') ||
          text.contains('installation'));
}

String _korlixVoiceFirstTitle({
  required String requestedTitle,
  required String request,
  required bool technicianAudit,
  required List<KorlixLiveDocSourceFile> sourceFiles,
}) {
  final explicit = _korlixVoiceFirstClean(requestedTitle, max: 300);
  if (explicit.isNotEmpty) {
    return explicit;
  }

  final text = request.toLowerCase();
  if (technicianAudit && text.contains('december') && text.contains('2024')) {
    return 'December 2024 Technician Audit Summary';
  }

  if (technicianAudit) {
    return 'Technician Audit Summary';
  }

  if (sourceFiles.isNotEmpty) {
    final name = sourceFiles.first.displayName.trim();
    final withoutExtension = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    if (withoutExtension.isNotEmpty) {
      return '$withoutExtension Report';
    }
  }

  return 'Korlix LIVE DOCS Report';
}

String _korlixVoiceFirstFormatSummary(List<KorlixLiveDocOutputFormat> formats) {
  if (formats.length == 1) {
    return formats.first.displayName;
  }

  final names = formats.map((format) => format.displayName).toList();
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

KorlixLiveDocsVoiceFirstPlan korlixLiveDocsBuildVoiceFirstPlan({
  required String latestUserRequest,
  String requestedTitle = '',
  String requestedAudience = '',
  String requestedTone = '',
  Iterable<Object?> requestedFormats = const <Object?>[],
  List<KorlixLiveDocSourceFile> sourceFiles = const <KorlixLiveDocSourceFile>[],
  DateTime? now,
}) {
  final request = _korlixVoiceFirstClean(latestUserRequest);
  if (request.isEmpty) {
    throw StateError('A complete LIVE DOCS request is required.');
  }

  final spreadsheetSource = sourceFiles.any(_korlixVoiceFirstIsSpreadsheet);
  final technicianAudit = _korlixVoiceFirstIsTechnicianAudit(request);
  final formats = korlixLiveDocsResolveVoiceFirstFormats(
    latestUserRequest: request,
    toolFormats: requestedFormats,
    spreadsheetSource: spreadsheetSource,
    technicianAuditRequest: technicianAudit,
  );

  final audience = _korlixVoiceFirstClean(requestedAudience, max: 300);
  final tone = _korlixVoiceFirstClean(requestedTone, max: 200);
  final title = _korlixVoiceFirstTitle(
    requestedTitle: requestedTitle,
    request: request,
    technicianAudit: technicianAudit,
    sourceFiles: sourceFiles,
  );

  final timestamp = (now ?? DateTime.now()).toUtc();
  final builder = KorlixLiveDocsBriefBuilder()
    ..documentType = KorlixLiveDocType.custom
    ..title = title
    ..audience = audience.isEmpty ? 'Internal operations' : audience
    ..goal = request
    ..tone = tone.isEmpty ? 'Professional' : tone
    ..targetLengthPages = technicianAudit ? 2 : null
    ..allowWebResearch = false;

  builder.applyConversationUpdate(<String, dynamic>{
    'output_formats': formats
        .map((format) => format.wireValue)
        .toList(growable: false),
  });

  for (final sourceFile in sourceFiles) {
    builder.addSourceFile(sourceFile);
  }

  builder.putConfirmedFact('Latest user instruction', request);
  builder.putConfirmedFact('Voice-first defaults', 'Web research disabled');

  final brief = builder.buildApproved(
    id: 'live-docs-voice-${timestamp.microsecondsSinceEpoch}',
    createdAt: timestamp,
    confirmedAt: timestamp,
  );

  final formatSummary = _korlixVoiceFirstFormatSummary(formats);
  final sourceSummary = sourceFiles.isEmpty
      ? 'the information in our conversation'
      : '${sourceFiles.length} attached ${sourceFiles.length == 1 ? 'file' : 'files'}';

  final spokenConfirmation =
      'I will create “${brief.title}” for ${brief.audience} as $formatSummary, '
      'using $sourceSummary, with a ${brief.tone.toLowerCase()} tone and no '
      'live web research. This uses 3 credits. Shall I generate it now? '
      'Please say yes or no.';

  return KorlixLiveDocsVoiceFirstPlan(
    brief: brief,
    instructions: request,
    formats: List<KorlixLiveDocOutputFormat>.unmodifiable(formats),
    spokenConfirmation: spokenConfirmation,
  );
}

// KORLIX_LIVE_DOCS_VOICE_FIRST_BUILD131_END
