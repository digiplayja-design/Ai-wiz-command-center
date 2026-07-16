import 'package:flutter/material.dart';

import 'korlix_live_docs.dart';
import 'korlix_live_docs_live_convo_bridge.dart';

enum KorlixLiveDocsBriefSheetAction { startCapture, approved }

class KorlixLiveDocsBriefSheetResult {
  const KorlixLiveDocsBriefSheetResult.startCapture()
    : action = KorlixLiveDocsBriefSheetAction.startCapture,
      brief = null,
      localPayload = null;

  const KorlixLiveDocsBriefSheetResult.approved({
    required this.brief,
    required this.localPayload,
  }) : action = KorlixLiveDocsBriefSheetAction.approved;

  final KorlixLiveDocsBriefSheetAction action;
  final KorlixLiveDocBrief? brief;
  final Map<String, dynamic>? localPayload;
}

Future<KorlixLiveDocsBriefSheetResult?> showKorlixLiveDocsBriefSheet({
  required BuildContext context,
  required KorlixLiveDocsConversationBridge bridge,
  required bool captureActive,
  required String clientBuild,
  KorlixLiveDocBrief? initialBrief,
}) {
  return showModalBottomSheet<KorlixLiveDocsBriefSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF041019),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: 0.94,
        child: KorlixLiveDocsBriefSheet(
          bridge: bridge,
          captureActive: captureActive,
          clientBuild: clientBuild,
          initialBrief: initialBrief,
        ),
      );
    },
  );
}

class KorlixLiveDocsBriefSheet extends StatefulWidget {
  const KorlixLiveDocsBriefSheet({
    super.key,
    required this.bridge,
    required this.captureActive,
    required this.clientBuild,
    this.initialBrief,
  });

  final KorlixLiveDocsConversationBridge bridge;
  final bool captureActive;
  final String clientBuild;
  final KorlixLiveDocBrief? initialBrief;

  @override
  State<KorlixLiveDocsBriefSheet> createState() =>
      _KorlixLiveDocsBriefSheetState();
}

class _KorlixLiveDocsBriefSheetState extends State<KorlixLiveDocsBriefSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _audienceController;
  late final TextEditingController _goalController;
  late final TextEditingController _toneController;
  late final TextEditingController _pagesController;
  late final TextEditingController _sectionsController;

  late KorlixLiveDocType _documentType;
  late Set<KorlixLiveDocOutputFormat> _outputFormats;
  late bool _allowWebResearch;

  String? _validationMessage;

  @override
  void initState() {
    super.initState();

    final initial = widget.initialBrief;

    _documentType = initial?.documentType ?? KorlixLiveDocType.custom;

    _titleController = TextEditingController(
      text: initial?.title ?? widget.bridge.suggestedTitle,
    );

    _audienceController = TextEditingController(text: initial?.audience ?? '');

    _goalController = TextEditingController(
      text: initial?.goal ?? widget.bridge.suggestedGoal,
    );

    _toneController = TextEditingController(
      text: initial?.tone ?? 'professional',
    );

    _pagesController = TextEditingController(
      text: initial?.targetLengthPages?.toString() ?? '',
    );

    _sectionsController = TextEditingController(
      text: initial?.requiredSections.join('\n') ?? '',
    );

    _outputFormats = <KorlixLiveDocOutputFormat>{
      ...(initial?.outputFormats ??
          const <KorlixLiveDocOutputFormat>[
            KorlixLiveDocOutputFormat.docx,
            KorlixLiveDocOutputFormat.pdf,
          ]),
    };

    _allowWebResearch = initial?.allowWebResearch ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _audienceController.dispose();
    _goalController.dispose();
    _toneController.dispose();
    _pagesController.dispose();
    _sectionsController.dispose();

    super.dispose();
  }

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        color: Color(0xFF8CDDE8),
        fontWeight: FontWeight.w700,
      ),
      hintStyle: const TextStyle(color: Color(0xFF718A96)),
      filled: true,
      fillColor: const Color(0xFF071722),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF1C5162)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF69D9E8), width: 1.6),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFEAF4F6),
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  void _approveBrief() {
    setState(() {
      _validationMessage = null;
    });

    final pagesText = _pagesController.text.trim();
    int? targetPages;

    if (pagesText.isNotEmpty) {
      targetPages = int.tryParse(pagesText);

      if (targetPages == null) {
        setState(() {
          _validationMessage = 'Page count must be a whole number.';
        });
        return;
      }
    }

    if (_outputFormats.isEmpty) {
      setState(() {
        _validationMessage = 'Select at least one output format.';
      });
      return;
    }

    final builder = KorlixLiveDocsBriefBuilder()
      ..documentType = _documentType
      ..title = _titleController.text.trim()
      ..audience = _audienceController.text.trim()
      ..goal = _goalController.text.trim()
      ..tone = _toneController.text.trim()
      ..targetLengthPages = targetPages
      ..allowWebResearch = _allowWebResearch;

    builder.applyConversationUpdate(<String, dynamic>{
      'output_formats': _outputFormats
          .map((format) => format.wireValue)
          .toList(growable: false),
    });

    final sections = _sectionsController.text
        .split(RegExp(r'[\n,;]+'))
        .map((section) => section.trim())
        .where((section) => section.isNotEmpty);

    for (final section in sections) {
      builder.addRequiredSection(section);
    }

    if (widget.bridge.hasCapturedTurns) {
      builder.putConfirmedFact(
        'LIVE CONVO captured instructions',
        widget.bridge.combinedInstructions,
      );

      builder.putConfirmedFact(
        'Captured LIVE CONVO turns',
        widget.bridge.capturedTurnCount.toString(),
      );
    }

    try {
      final now = DateTime.now().toUtc();

      final brief = builder.buildApproved(
        id: 'live-docs-${now.microsecondsSinceEpoch}',
        createdAt: now,
        confirmedAt: now,
      );

      final localPayload = KorlixLiveDocsApiContract.createJobPayload(
        brief: brief,
        idempotencyKey: 'local-${brief.id}-${now.microsecondsSinceEpoch}',
        clientBuild: widget.clientBuild,
      );

      Navigator.of(context).pop(
        KorlixLiveDocsBriefSheetResult.approved(
          brief: brief,
          localPayload: localPayload,
        ),
      );
    } catch (error) {
      final message = error
          .toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('StateError: ', '');

      setState(() {
        _validationMessage = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    final capturedTurns = widget.bridge.capturedTurns;

    final previewTurns = capturedTurns.length <= 4
        ? capturedTurns
        : capturedTurns.sublist(capturedTurns.length - 4);

    return Material(
      color: const Color(0xFF041019),
      child: ListView(
        padding: EdgeInsets.fromLTRB(18, 14, 18, 26 + bottomInset),
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFF123A47),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.description_rounded,
                  color: Color(0xFF69D9E8),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KORLIX LIVE DOCS',
                      style: TextStyle(
                        color: Color(0xFFF2F7F8),
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Review the instructions captured from LIVE CONVO.',
                      style: TextStyle(color: Color(0xFF9BB2BC), height: 1.3),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close document brief',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                color: const Color(0xFFC7D7DC),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFF0B2732),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1F6071)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, color: Color(0xFF62D6A7)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'LOCAL BUILD 131 PREVIEW — approving this brief '
                    'creates a local payload only. No document job, '
                    'upload, backend request, charge, or deployment '
                    'will occur.',
                    style: TextStyle(
                      color: Color(0xFFC7D7DC),
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (capturedTurns.isNotEmpty) ...[
            _sectionLabel(
              'Captured conversation — ${capturedTurns.length} '
              '${capturedTurns.length == 1 ? 'turn' : 'turns'}',
            ),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFF06131C),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF244D5C)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < previewTurns.length; index += 1)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: index == previewTurns.length - 1 ? 0 : 10,
                      ),
                      child: Text(
                        '${previewTurns[index].source.toUpperCase()}: '
                        '${previewTurns[index].text}',
                        style: const TextStyle(
                          color: Color(0xFFB9CDD4),
                          height: 1.35,
                        ),
                      ),
                    ),
                  if (capturedTurns.length > previewTurns.length) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${capturedTurns.length - previewTurns.length} '
                      'earlier turn(s) are also included.',
                      style: const TextStyle(
                        color: Color(0xFF69D9E8),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          _sectionLabel('Document type'),
          DropdownButtonFormField<KorlixLiveDocType>(
            value: _documentType,
            isExpanded: true,
            dropdownColor: const Color(0xFF071722),
            decoration: _decoration('Type'),
            items: KorlixLiveDocType.values
                .map(
                  (type) => DropdownMenuItem<KorlixLiveDocType>(
                    value: type,
                    child: Text(type.displayName),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) {
                return;
              }

              setState(() {
                _documentType = value;
              });
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _titleController,
            style: const TextStyle(color: Color(0xFFF0F5F6)),
            decoration: _decoration(
              'Document title',
              hint: 'Example: Expansion Funding Proposal',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _audienceController,
            style: const TextStyle(color: Color(0xFFF0F5F6)),
            decoration: _decoration(
              'Audience',
              hint: 'Who will read or receive it?',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _goalController,
            minLines: 4,
            maxLines: 10,
            style: const TextStyle(color: Color(0xFFF0F5F6)),
            decoration: _decoration(
              'Goal and instructions',
              hint: 'Describe what the finished document must accomplish.',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _toneController,
            style: const TextStyle(color: Color(0xFFF0F5F6)),
            decoration: _decoration(
              'Tone',
              hint: 'Professional, persuasive, concise…',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _pagesController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Color(0xFFF0F5F6)),
            decoration: _decoration(
              'Target pages — optional',
              hint: 'Example: 8',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _sectionsController,
            minLines: 3,
            maxLines: 8,
            style: const TextStyle(color: Color(0xFFF0F5F6)),
            decoration: _decoration(
              'Required sections — optional',
              hint: 'Enter one section per line.',
            ),
          ),
          const SizedBox(height: 18),
          _sectionLabel('Output formats'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final format in KorlixLiveDocOutputFormat.values)
                FilterChip(
                  selected: _outputFormats.contains(format),
                  selectedColor: const Color(0xFF17617A),
                  backgroundColor: const Color(0xFF071722),
                  checkmarkColor: const Color(0xFFEAF8FA),
                  side: const BorderSide(color: Color(0xFF2A6070)),
                  label: Text(format.displayName),
                  labelStyle: TextStyle(
                    color: _outputFormats.contains(format)
                        ? const Color(0xFFF2FBFC)
                        : const Color(0xFFA9C0C8),
                    fontWeight: FontWeight.w700,
                  ),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _outputFormats.add(format);
                      } else {
                        _outputFormats.remove(format);
                      }
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _allowWebResearch,
            activeThumbColor: const Color(0xFF62D6A7),
            title: const Text(
              'Allow live web research',
              style: TextStyle(
                color: Color(0xFFF0F5F6),
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: const Text(
              'The future Document Agent may use current external '
              'sources only when this is enabled.',
              style: TextStyle(color: Color(0xFF91A8B1), height: 1.35),
            ),
            onChanged: (value) {
              setState(() {
                _allowWebResearch = value;
              });
            },
          ),
          if (_validationMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF35131A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF8D3344)),
              ),
              child: Text(
                _validationMessage!,
                style: const TextStyle(
                  color: Color(0xFFFFB7C1),
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (!widget.captureActive)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(
                    context,
                  ).pop(const KorlixLiveDocsBriefSheetResult.startCapture());
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF69D9E8),
                  side: const BorderSide(color: Color(0xFF37798B)),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.graphic_eq_rounded),
                label: const Text(
                  'Start New Voice Brief',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF69D9E8),
                  side: const BorderSide(color: Color(0xFF37798B)),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.mic_rounded),
                label: const Text(
                  'Continue LIVE CONVO',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _approveBrief,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF62D6A7),
                foregroundColor: const Color(0xFF03110E),
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              icon: const Icon(Icons.verified_rounded),
              label: const Text(
                'Approve Local Brief',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
