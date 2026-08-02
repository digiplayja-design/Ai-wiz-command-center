import 'dart:async';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';

import 'korlix_live_convo_agent.dart';
import 'korlix_live_convo_agent_client.dart';

// KORLIX_AGENT_FILE_MEMORY_SHEET_BUILD131_V1_BEGIN

Future<int?> showKorlixLiveConvoAgentFileMemorySheet({
  required BuildContext context,
  required KorlixLiveConvoAgentClient client,
  required KorlixLiveConvoAgent agent,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xCC02070C),
    builder: (sheetContext) {
      return _KorlixAgentFileMemorySheet(client: client, agent: agent);
    },
  );
}

Color _korlixAgentFileMemoryAccent(String value) {
  final clean = value.trim().replaceFirst('#', '').toUpperCase();

  if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(clean)) {
    return const Color(0xFF21D4F4);
  }

  return Color(int.parse('FF$clean', radix: 16));
}

String _korlixAgentFileMemoryKindLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'fact':
      return 'Fact';
    case 'goal':
      return 'Goal';
    case 'style':
      return 'Style';
    case 'example':
      return 'Example';
    case 'correction':
      return 'Correction';
    case 'vocabulary':
      return 'Vocabulary';
    case 'preference':
    default:
      return 'Preference';
  }
}

IconData _korlixAgentFileMemoryKindIcon(String value) {
  switch (value.trim().toLowerCase()) {
    case 'fact':
      return Icons.fact_check_rounded;
    case 'goal':
      return Icons.flag_rounded;
    case 'style':
      return Icons.tune_rounded;
    case 'example':
      return Icons.lightbulb_rounded;
    case 'correction':
      return Icons.rule_rounded;
    case 'vocabulary':
      return Icons.translate_rounded;
    case 'preference':
    default:
      return Icons.favorite_rounded;
  }
}

Color _korlixAgentFileMemoryKindColor(String value) {
  switch (value.trim().toLowerCase()) {
    case 'fact':
      return const Color(0xFF69D9E8);
    case 'goal':
      return const Color(0xFFF2C14E);
    case 'style':
      return const Color(0xFFB794F4);
    case 'example':
      return const Color(0xFFFFB86B);
    case 'correction':
      return const Color(0xFFFF7185);
    case 'vocabulary':
      return const Color(0xFF7CC4FF);
    case 'preference':
    default:
      return const Color(0xFF62D6A7);
  }
}

String _korlixAgentFileMemorySizeLabel(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }

  final kilobytes = bytes / 1024;

  if (kilobytes < 1024) {
    return '${kilobytes.toStringAsFixed(kilobytes < 10 ? 1 : 0)} KB';
  }

  final megabytes = kilobytes / 1024;

  return '${megabytes.toStringAsFixed(megabytes < 10 ? 1 : 0)} MB';
}

class _KorlixAgentFileMemoryReviewItem {
  _KorlixAgentFileMemoryReviewItem({
    required this.suggestion,
    this.selected = false,
    this.saved = false,
  });

  KorlixLiveConvoAgentMemoryFileSuggestion suggestion;
  bool selected;
  bool saved;
}

class _KorlixAgentFileMemorySheet extends StatefulWidget {
  const _KorlixAgentFileMemorySheet({
    required this.client,
    required this.agent,
  });

  final KorlixLiveConvoAgentClient client;
  final KorlixLiveConvoAgent agent;

  @override
  State<_KorlixAgentFileMemorySheet> createState() {
    return _KorlixAgentFileMemorySheetState();
  }
}

class _KorlixAgentFileMemorySheetState
    extends State<_KorlixAgentFileMemorySheet> {
  final List<KorlixLiveConvoAgentMemoryFileUpload> _files =
      <KorlixLiveConvoAgentMemoryFileUpload>[];

  final List<_KorlixAgentFileMemoryReviewItem> _reviewItems =
      <_KorlixAgentFileMemoryReviewItem>[];

  KorlixLiveConvoAgentMemoryFilePreview? _preview;

  bool _picking = false;
  bool _analyzing = false;
  bool _saving = false;

  int _savedCount = 0;

  String? _error;

  bool get _busy => _picking || _analyzing || _saving;

  int get _selectedCount {
    return _reviewItems.where((item) => item.selected && !item.saved).length;
  }

  String _cleanError(Object error) {
    return error
        .toString()
        .replaceFirst('KorlixLiveConvoAgentClientException: ', '')
        .replaceFirst('Exception: ', '')
        .trim();
  }

  void _close() {
    if (_busy) {
      return;
    }

    Navigator.of(context).pop(_savedCount > 0 ? _savedCount : null);
  }

  void _invalidatePreview() {
    _preview = null;
    _reviewItems.clear();
  }

  Future<void> _pickFiles() async {
    if (_busy) {
      return;
    }

    setState(() {
      _picking = true;
      _error = null;
    });

    fp.FilePickerResult? result;

    try {
      result = await fp.FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: fp.FileType.custom,
        allowedExtensions:
            KorlixLiveConvoAgentMemoryFileUpload.allowedExtensions,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _picking = false;
          _error = 'Could not open the file picker: ${_cleanError(error)}';
        });
      }

      return;
    }

    if (!mounted) {
      return;
    }

    if (result == null || result.files.isEmpty) {
      setState(() {
        _picking = false;
      });

      return;
    }

    final accepted = <KorlixLiveConvoAgentMemoryFileUpload>[];
    final messages = <String>[];

    final existingKeys = <String>{for (final file in _files) file.dedupeKey};

    for (final picked in result.files) {
      final cleanName = picked.name.trim().isEmpty
          ? 'Source file ${_files.length + accepted.length + 1}'
          : picked.name.trim();

      final bytes = picked.bytes;

      if (bytes == null || bytes.isEmpty) {
        messages.add('$cleanName could not be read on this device.');
        continue;
      }

      final upload = KorlixLiveConvoAgentMemoryFileUpload(
        name: cleanName,
        bytes: bytes,
      );

      if (!KorlixLiveConvoAgentMemoryFileUpload.allowedExtensions.contains(
        upload.extension,
      )) {
        messages.add('$cleanName is not a supported Agent memory file.');
        continue;
      }

      if (upload.sizeBytes >
          KorlixLiveConvoAgentMemoryFileUpload.maximumBytesPerFile) {
        messages.add('$cleanName exceeds the 10 MB file limit.');
        continue;
      }

      if (existingKeys.contains(upload.dedupeKey) ||
          accepted.any((file) => file.dedupeKey == upload.dedupeKey)) {
        messages.add('$cleanName is already attached.');
        continue;
      }

      if (_files.length + accepted.length >=
          KorlixLiveConvoAgentMemoryFileUpload.maximumFiles) {
        messages.add('Only five files may be analyzed at once.');
        break;
      }

      accepted.add(upload);
    }

    setState(() {
      _picking = false;

      if (accepted.isNotEmpty) {
        _files.addAll(accepted);
        _invalidatePreview();
      }

      _error = messages.isEmpty ? null : messages.take(4).join('\n');
    });
  }

  void _removeFile(int index) {
    if (_busy || index < 0 || index >= _files.length) {
      return;
    }

    setState(() {
      _files.removeAt(index);
      _invalidatePreview();
      _error = null;
    });
  }

  void _clearFiles() {
    if (_busy || _files.isEmpty) {
      return;
    }

    setState(() {
      _files.clear();
      _invalidatePreview();
      _error = null;
    });
  }

  Future<void> _analyzeFiles() async {
    if (_busy || _files.isEmpty) {
      return;
    }

    setState(() {
      _analyzing = true;
      _error = null;
    });

    try {
      final preview = await widget.client.analyzeMemoryFiles(
        agentId: widget.agent.id,
        files: List<KorlixLiveConvoAgentMemoryFileUpload>.unmodifiable(_files),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _preview = preview;
        _reviewItems
          ..clear()
          ..addAll(
            preview.suggestions.map(
              (suggestion) =>
                  _KorlixAgentFileMemoryReviewItem(suggestion: suggestion),
            ),
          );
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _cleanError(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _analyzing = false;
        });
      }
    }
  }

  Future<void> _editSuggestion(int index) async {
    if (_busy || index < 0 || index >= _reviewItems.length) {
      return;
    }

    final item = _reviewItems[index];

    if (item.saved) {
      return;
    }

    final updated =
        await showModalBottomSheet<KorlixLiveConvoAgentMemoryFileSuggestion>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          barrierColor: const Color(0xCC02070C),
          builder: (sheetContext) {
            return _KorlixAgentFileMemorySuggestionEditor(
              agent: widget.agent,
              suggestion: item.suggestion,
            );
          },
        );

    if (!mounted || updated == null) {
      return;
    }

    setState(() {
      item.suggestion = updated;
      _error = null;
    });
  }

  void _setAllSelected(bool selected) {
    if (_busy) {
      return;
    }

    setState(() {
      for (final item in _reviewItems) {
        if (!item.saved) {
          item.selected = selected;
        }
      }
    });
  }

  Future<bool> _confirmSelectedMemories(int count) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF071722),
          title: Text(
            count == 1
                ? 'Save this file-derived memory?'
                : 'Save $count file-derived memories?',
            style: const TextStyle(
              color: Color(0xFFF0F7F8),
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'Only the selected and reviewed records will be saved privately '
            'to ${widget.agent.name}. The uploaded source files themselves '
            'will not be retained by Korlix.',
            style: const TextStyle(color: Color(0xFFBBD0D6), height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Review Again'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF62D6A7),
                foregroundColor: const Color(0xFF03110E),
              ),
              icon: const Icon(Icons.verified_rounded),
              label: Text(
                count == 1 ? 'Approve and Save' : 'Approve and Save $count',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<void> _saveSelected() async {
    if (_busy) {
      return;
    }

    final selected = <_KorlixAgentFileMemoryReviewItem>[
      for (final item in _reviewItems)
        if (item.selected && !item.saved) item,
    ];

    if (selected.isEmpty) {
      setState(() {
        _error = 'Select at least one reviewed memory before saving.';
      });

      return;
    }

    final confirmed = await _confirmSelectedMemories(selected.length);

    if (!mounted || !confirmed) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    Object? saveError;

    for (final item in selected) {
      try {
        await widget.client.saveMemory(
          agentId: widget.agent.id,
          draft: item.suggestion.confirmedDraft(),
        );

        if (!mounted) {
          return;
        }

        setState(() {
          item.saved = true;
          item.selected = false;
          _savedCount += 1;
        });
      } catch (error) {
        saveError = error;
        break;
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _saving = false;

      if (saveError != null) {
        _error =
            '$_savedCount selected '
            '${_savedCount == 1 ? 'memory was' : 'memories were'} saved, '
            'but the remaining save stopped: ${_cleanError(saveError)}';
      }
    });

    if (saveError != null) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _savedCount == 1
                ? '1 file-derived memory was saved.'
                : '$_savedCount file-derived memories were saved.',
          ),
          backgroundColor: const Color(0xFF17644D),
        ),
      );

    await Future<void>.delayed(const Duration(milliseconds: 160));

    if (mounted) {
      Navigator.of(context).pop(_savedCount);
    }
  }

  Widget _buildHeader(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: accent.withValues(alpha: 0.14),
              border: Border.all(color: accent.withValues(alpha: 0.72)),
            ),
            child: Icon(Icons.attach_file_rounded, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ATTACH MEMORY FILES',
                  style: TextStyle(
                    color: Color(0xFFF0F7F8),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Analyze files, review every suggestion, then approve only '
                  'the memories ${widget.agent.name} should keep.',
                  style: const TextStyle(
                    color: Color(0xFFA9C6CF),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close file-memory review',
            onPressed: _busy ? null : _close,
            icon: const Icon(Icons.close_rounded),
            color: const Color(0xFFC7D7DC),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyNotice() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF0B2A24),
        border: Border.all(color: const Color(0xFF62D6A7)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: Color(0xFF62D6A7)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Files are treated as untrusted reference data. They cannot '
              'override Korlix safety, privacy, authorization, tool, or '
              'confirmation rules. Nothing is saved automatically.',
              style: TextStyle(
                color: Color(0xFFD8E7EA),
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    final message = _error?.trim() ?? '';

    if (message.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF32131B),
        border: Border.all(color: const Color(0xFFFF7185)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFFF8B9B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFFFD5DB), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileCard(KorlixLiveConvoAgentMemoryFileUpload file, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: const Color(0xFF071722),
        border: Border.all(color: const Color(0xFF244D5C)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.insert_drive_file_outlined,
            color: Color(0xFF8CDDE8),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF0F7F8),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${file.extension.toUpperCase()} · '
                  '${_korlixAgentFileMemorySizeLabel(file.sizeBytes)}',
                  style: const TextStyle(
                    color: Color(0xFF8FA8B1),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove file',
            onPressed: _busy
                ? null
                : () {
                    _removeFile(index);
                  },
            icon: const Icon(Icons.close_rounded),
            color: const Color(0xFFFF8B9B),
          ),
        ],
      ),
    );
  }

  Widget _buildFileSection(Color accent) {
    final remaining =
        KorlixLiveConvoAgentMemoryFileUpload.maximumFiles - _files.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF06131C),
        border: Border.all(color: accent.withValues(alpha: 0.46)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'FILES TO ANALYZE (${_files.length}/5)',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    fontSize: 12,
                  ),
                ),
              ),
              if (_files.isNotEmpty)
                TextButton(
                  onPressed: _busy ? null : _clearFiles,
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_files.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Attach PDF, Word, Excel, CSV, text, PowerPoint, JPG, PNG, '
                'or WEBP files. Up to five files, 10 MB each.',
                style: TextStyle(color: Color(0xFFA9C6CF), height: 1.45),
              ),
            )
          else
            for (var index = 0; index < _files.length; index += 1)
              _buildFileCard(_files[index], index),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy || remaining <= 0
                ? null
                : () {
                    unawaited(_pickFiles());
                  },
            style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: BorderSide(color: accent.withValues(alpha: 0.76)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _picking
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_link_rounded),
            label: Text(
              remaining <= 0
                  ? 'Five-File Limit Reached'
                  : _files.isEmpty
                  ? 'Choose Memory Files'
                  : 'Add More Files',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          if (_files.isNotEmpty) ...[
            const SizedBox(height: 9),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      unawaited(_analyzeFiles());
                    },
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: const Color(0xFF03110E),
                disabledBackgroundColor: const Color(0xFF33454B),
                disabledForegroundColor: const Color(0xFF83969C),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              icon: _analyzing
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Color(0xFF03110E),
                      ),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(
                _analyzing ? 'Analyzing Files…' : 'Analyze for Memory',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImportance(int value, Color color) {
    final safe = value < 1
        ? 1
        : value > 5
        ? 5
        : value;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 1; index <= 5; index += 1)
          Icon(
            index <= safe ? Icons.star_rounded : Icons.star_border_rounded,
            size: 15,
            color: index <= safe ? color : const Color(0xFF607680),
          ),
      ],
    );
  }

  Widget _buildSuggestionCard(
    _KorlixAgentFileMemoryReviewItem item,
    int index,
  ) {
    final suggestion = item.suggestion;
    final draft = suggestion.draft;
    final color = _korlixAgentFileMemoryKindColor(draft.kind);

    final title = draft.label.trim().isEmpty
        ? _korlixAgentFileMemoryKindLabel(draft.kind)
        : draft.label.trim();

    final location = suggestion.provenance.locationLabel;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: item.saved ? const Color(0xFF0B2A24) : const Color(0xFF071722),
        border: Border.all(
          color: item.saved
              ? const Color(0xFF62D6A7)
              : item.selected
              ? color
              : color.withValues(alpha: 0.48),
          width: item.selected ? 1.7 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: item.saved || item.selected,
                onChanged: _busy || item.saved
                    ? null
                    : (value) {
                        setState(() {
                          item.selected = value == true;
                          _error = null;
                        });
                      },
              ),
              const SizedBox(width: 4),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: color.withValues(alpha: 0.15),
                  border: Border.all(color: color.withValues(alpha: 0.68)),
                ),
                child: Icon(
                  item.saved
                      ? Icons.cloud_done_rounded
                      : _korlixAgentFileMemoryKindIcon(draft.kind),
                  color: item.saved ? const Color(0xFF62D6A7) : color,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFF0F7F8),
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      children: [
                        _KorlixFileMemoryBadge(
                          text: _korlixAgentFileMemoryKindLabel(
                            draft.kind,
                          ).toUpperCase(),
                          color: color,
                        ),
                        if (draft.sensitive)
                          const _KorlixFileMemoryBadge(
                            text: 'SENSITIVE',
                            color: Color(0xFFFFB86B),
                          ),
                        if (item.saved)
                          const _KorlixFileMemoryBadge(
                            text: 'SAVED',
                            color: Color(0xFF62D6A7),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit suggestion',
                onPressed: _busy || item.saved
                    ? null
                    : () {
                        unawaited(_editSuggestion(index));
                      },
                icon: const Icon(Icons.edit_outlined),
                color: const Color(0xFF8CDDE8),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            suggestion.editableContent,
            style: const TextStyle(
              color: Color(0xFFD8E7EA),
              height: 1.45,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: const Color(0xFF041019),
              border: Border.all(color: const Color(0xFF244D5C)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.provenance.fileName,
                  style: const TextStyle(
                    color: Color(0xFF8CDDE8),
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    location,
                    style: const TextStyle(
                      color: Color(0xFFA9C6CF),
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Text(
                      'Importance',
                      style: TextStyle(
                        color: Color(0xFF8FA8B1),
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(width: 7),
                    _buildImportance(draft.importance, color),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(Color accent) {
    final preview = _preview;

    if (preview == null) {
      return const SizedBox.shrink();
    }

    final allSelected = _reviewItems
        .where((item) => !item.saved)
        .every((item) => item.selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFF081B25),
            border: Border.all(color: const Color(0xFF28596A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MEMORY PREVIEW',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                preview.summary.trim().isEmpty
                    ? '${preview.suggestions.length} durable memory '
                          'suggestions were found.'
                    : preview.summary,
                style: const TextStyle(color: Color(0xFFD8E7EA), height: 1.45),
              ),
              const SizedBox(height: 9),
              Text(
                preview.sourceRetentionMessage.trim().isEmpty
                    ? 'The source files were used only for this preview and '
                          'were not retained by Korlix.'
                    : preview.sourceRetentionMessage,
                style: const TextStyle(
                  color: Color(0xFF8FA8B1),
                  height: 1.4,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 12, 9),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_reviewItems.length} SUGGESTED '
                  '${_reviewItems.length == 1 ? 'MEMORY' : 'MEMORIES'}',
                  style: const TextStyle(
                    color: Color(0xFF8CDDE8),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    fontSize: 12,
                  ),
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        _setAllSelected(!allSelected);
                      },
                child: Text(allSelected ? 'Select None' : 'Select All'),
              ),
            ],
          ),
        ),
        for (var index = 0; index < _reviewItems.length; index += 1)
          _buildSuggestionCard(_reviewItems[index], index),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFF06131C),
            border: Border.all(color: accent.withValues(alpha: 0.46)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _selectedCount == 0
                    ? 'Select the reviewed memories to save.'
                    : _selectedCount == 1
                    ? '1 reviewed memory is selected.'
                    : '$_selectedCount reviewed memories are selected.',
                style: const TextStyle(
                  color: Color(0xFFD8E7EA),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _busy || _selectedCount == 0
                    ? null
                    : () {
                        unawaited(_saveSelected());
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF62D6A7),
                  foregroundColor: const Color(0xFF03110E),
                  disabledBackgroundColor: const Color(0xFF33454B),
                  disabledForegroundColor: const Color(0xFF83969C),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Color(0xFF03110E),
                        ),
                      )
                    : const Icon(Icons.verified_rounded),
                label: Text(
                  _saving
                      ? 'Saving Approved Memories…'
                      : _selectedCount == 1
                      ? 'Approve and Save 1 Memory'
                      : 'Approve and Save $_selectedCount Memories',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(Color accent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
      decoration: const BoxDecoration(
        color: Color(0xFF06131C),
        border: Border(top: BorderSide(color: Color(0xFF173541))),
      ),
      child: Row(
        children: [
          Icon(
            _savedCount > 0
                ? Icons.cloud_done_rounded
                : Icons.lock_outline_rounded,
            color: _savedCount > 0 ? const Color(0xFF62D6A7) : accent,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _savedCount > 0
                  ? '$_savedCount approved '
                        '${_savedCount == 1 ? 'memory has' : 'memories have'} '
                        'been saved.'
                  : 'Suggestions begin unchecked and are saved only after '
                        'your approval.',
              style: const TextStyle(
                color: Color(0xFFA9C6CF),
                height: 1.35,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: _busy ? null : _close,
            child: Text(_savedCount > 0 ? 'Done' : 'Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final accent = _korlixAgentFileMemoryAccent(widget.agent.accentHex);

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxWidth: 900,
            maxHeight: screenSize.height * 0.95,
          ),
          margin: const EdgeInsets.only(top: 20),
          decoration: const BoxDecoration(
            color: Color(0xFF041019),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 34,
                offset: Offset(0, -8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                _buildHeader(accent),
                if (_busy)
                  const LinearProgressIndicator(
                    minHeight: 3,
                    color: Color(0xFF69D9E8),
                    backgroundColor: Color(0xFF123A47),
                  ),
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.only(bottom: 18 + bottomInset),
                    children: [
                      _buildSafetyNotice(),
                      _buildErrorBanner(),
                      _buildFileSection(accent),
                      _buildPreview(accent),
                    ],
                  ),
                ),
                _buildFooter(accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KorlixAgentFileMemorySuggestionEditor extends StatefulWidget {
  const _KorlixAgentFileMemorySuggestionEditor({
    required this.agent,
    required this.suggestion,
  });

  final KorlixLiveConvoAgent agent;
  final KorlixLiveConvoAgentMemoryFileSuggestion suggestion;

  @override
  State<_KorlixAgentFileMemorySuggestionEditor> createState() {
    return _KorlixAgentFileMemorySuggestionEditorState();
  }
}

class _KorlixAgentFileMemorySuggestionEditorState
    extends State<_KorlixAgentFileMemorySuggestionEditor> {
  late final TextEditingController _labelController;
  late final TextEditingController _contentController;
  late final TextEditingController _tagsController;

  late String _kind;
  late int _importance;
  late bool _sensitive;

  String? _validation;

  @override
  void initState() {
    super.initState();

    final draft = widget.suggestion.draft;

    _labelController = TextEditingController(text: draft.label);
    _contentController = TextEditingController(
      text: widget.suggestion.editableContent,
    );
    _tagsController = TextEditingController(text: draft.tags.join(', '));

    _kind = draft.kind;
    _importance = draft.importance;
    _sensitive = draft.sensitive;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _contentController.dispose();
    _tagsController.dispose();

    super.dispose();
  }

  List<String> _normalizedTags() {
    final result = <String>[];
    final seen = <String>{};

    for (final raw in _tagsController.text.split(RegExp(r'[\n,;]+'))) {
      final clean = raw.trim();

      if (clean.isEmpty || !seen.add(clean.toLowerCase())) {
        continue;
      }

      result.add(clean.length <= 48 ? clean : clean.substring(0, 48));

      if (result.length >= 12) {
        break;
      }
    }

    return List<String>.unmodifiable(result);
  }

  void _submit() {
    final content = _contentController.text.trim();

    if (content.isEmpty) {
      setState(() {
        _validation = 'Enter the memory content before updating the preview.';
      });

      return;
    }

    Navigator.of(context).pop(
      widget.suggestion.copyWithDraft(
        KorlixLiveConvoMemoryDraft(
          content: content,
          confirmed: false,
          kind: _kind,
          label: _labelController.text.trim(),
          tags: _normalizedTags(),
          importance: _importance,
          sensitive: _sensitive,
          source: widget.suggestion.draft.source,
        ),
      ),
    );
  }

  InputDecoration _decoration({
    required String label,
    String? hint,
    String? helper,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      alignLabelWithHint: true,
      filled: true,
      fillColor: const Color(0xFF071722),
      labelStyle: const TextStyle(
        color: Color(0xFF8CDDE8),
        fontWeight: FontWeight.w800,
      ),
      hintStyle: const TextStyle(color: Color(0xFF718A96)),
      helperStyle: const TextStyle(color: Color(0xFF8FA8B1), height: 1.3),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF244D5C)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF69D9E8), width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = _korlixAgentFileMemoryAccent(widget.agent.accentHex);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final screenSize = MediaQuery.sizeOf(context);

    final sourceLocation = widget.suggestion.provenance.locationLabel;

    final sourceLabel = sourceLocation.isEmpty
        ? widget.suggestion.provenance.fileName
        : '${widget.suggestion.provenance.fileName} · $sourceLocation';

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxWidth: 760,
            maxHeight: screenSize.height * 0.92,
          ),
          margin: const EdgeInsets.only(top: 28),
          padding: EdgeInsets.fromLTRB(18, 14, 18, 18 + bottomInset),
          decoration: const BoxDecoration(
            color: Color(0xFF041019),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          color: accent.withValues(alpha: 0.14),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.72),
                          ),
                        ),
                        child: Icon(Icons.edit_note_rounded, color: accent),
                      ),
                      const SizedBox(width: 11),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'EDIT MEMORY SUGGESTION',
                              style: TextStyle(
                                color: Color(0xFFF0F7F8),
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'This updates the preview only. Nothing is saved '
                              'until you select and approve it.',
                              style: TextStyle(
                                color: Color(0xFFA9C6CF),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close editor',
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.close_rounded),
                        color: const Color(0xFFC7D7DC),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _labelController,
                    maxLength: 120,
                    style: const TextStyle(color: Color(0xFFF0F7F8)),
                    decoration: _decoration(
                      label: 'Memory label',
                      hint: 'Example: Weekly report style',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _contentController,
                    minLines: 5,
                    maxLines: 12,
                    maxLength: 3600,
                    style: const TextStyle(
                      color: Color(0xFFF0F7F8),
                      height: 1.4,
                    ),
                    decoration: _decoration(
                      label: 'Memory content',
                      helper:
                          'The verified source reference is appended '
                          'automatically when saved.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'MEMORY TYPE',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final kind in const <String>[
                        'preference',
                        'fact',
                        'goal',
                        'style',
                        'example',
                        'correction',
                        'vocabulary',
                      ])
                        ChoiceChip(
                          selected: kind == _kind,
                          showCheckmark: false,
                          onSelected: (_) {
                            setState(() {
                              _kind = kind;
                              _validation = null;
                            });
                          },
                          avatar: Icon(
                            _korlixAgentFileMemoryKindIcon(kind),
                            size: 18,
                            color: kind == _kind
                                ? _korlixAgentFileMemoryKindColor(kind)
                                : const Color(0xFF8FA8B1),
                          ),
                          label: Text(_korlixAgentFileMemoryKindLabel(kind)),
                          labelStyle: TextStyle(
                            color: kind == _kind
                                ? const Color(0xFFF0F7F8)
                                : const Color(0xFFB1C4CA),
                            fontWeight: FontWeight.w800,
                          ),
                          selectedColor: _korlixAgentFileMemoryKindColor(
                            kind,
                          ).withValues(alpha: 0.20),
                          backgroundColor: const Color(0xFF071722),
                          side: BorderSide(
                            color: kind == _kind
                                ? _korlixAgentFileMemoryKindColor(kind)
                                : const Color(0xFF244D5C),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _tagsController,
                    maxLength: 260,
                    style: const TextStyle(color: Color(0xFFF0F7F8)),
                    decoration: _decoration(
                      label: 'Tags',
                      hint: 'reports, schedule, style',
                      helper: 'Separate tags with commas. Maximum 12 tags.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: const Color(0xFF071722),
                      border: Border.all(color: const Color(0xFF244D5C)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'IMPORTANCE: $_importance OF 5',
                          style: const TextStyle(
                            color: Color(0xFF8CDDE8),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                        Slider(
                          value: _importance.toDouble(),
                          min: 1,
                          max: 5,
                          divisions: 4,
                          label: '$_importance',
                          onChanged: (value) {
                            setState(() {
                              _importance = value.round();
                              _validation = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    value: _sensitive,
                    onChanged: (value) {
                      setState(() {
                        _sensitive = value;
                        _validation = null;
                      });
                    },
                    activeThumbColor: const Color(0xFFFFB86B),
                    activeTrackColor: const Color(
                      0xFFFFB86B,
                    ).withValues(alpha: 0.38),
                    tileColor: const Color(0xFF071722),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFF244D5C)),
                    ),
                    secondary: const Icon(
                      Icons.privacy_tip_outlined,
                      color: Color(0xFFFFB86B),
                    ),
                    title: const Text(
                      'Sensitive memory',
                      style: TextStyle(
                        color: Color(0xFFF0F7F8),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: const Text(
                      'Mark health, financial, identity, authentication, '
                      'private-contact, or similarly sensitive information.',
                      style: TextStyle(color: Color(0xFFA9C6CF), height: 1.35),
                    ),
                  ),
                  const SizedBox(height: 11),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      color: const Color(0xFF081B25),
                      border: Border.all(color: const Color(0xFF28596A)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.source_outlined,
                          color: Color(0xFF8CDDE8),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            sourceLabel,
                            style: const TextStyle(
                              color: Color(0xFFD8E7EA),
                              height: 1.4,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if ((_validation ?? '').isNotEmpty) ...[
                    const SizedBox(height: 11),
                    Text(
                      _validation!,
                      style: const TextStyle(
                        color: Color(0xFFFF9EAD),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 15),
                  FilledButton.icon(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: const Color(0xFF03110E),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text(
                      'Update Preview',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KorlixFileMemoryBadge extends StatelessWidget {
  const _KorlixFileMemoryBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.68)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// KORLIX_AGENT_FILE_MEMORY_SHEET_BUILD131_V1_END
