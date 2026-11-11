import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'brain_api.dart';
import 'brain_repository.dart';

enum BrainDocumentDestination { memory, training, both }

extension BrainDocumentDestinationLabel on BrainDocumentDestination {
  String get label => switch (this) {
    BrainDocumentDestination.memory => 'Memory',
    BrainDocumentDestination.training => 'Training',
    BrainDocumentDestination.both => 'Memory & Training',
  };
  bool get includesMemory => this != BrainDocumentDestination.training;
  bool get includesTraining => this != BrainDocumentDestination.memory;
}

class BrainDocumentMemory {
  BrainDocumentMemory._({
    required this.id,
    required this.draft,
    required this.provenance,
  }) : submissionKey = 'brain_pdf:$id:${_nonce()}';

  final String id;
  final Map<String, dynamic> draft;
  final Map<String, dynamic> provenance;
  // Stable across retries of this reviewed item, separate from earlier imports
  // of the same PDF so an edited prior memory is never overwritten silently.
  final String submissionKey;
  bool selected = false, saved = false, alreadySaved = false;

  static String _nonce() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  String get content => draft['content'] as String;
  String get label => draft['label'] as String? ?? 'Suggested memory';
  bool get sensitive => draft['sensitive'] == true;
  String get sourceLabel {
    final file = provenance['fileName']?.toString() ?? 'Uploaded PDF';
    final page = provenance['page']?.toString();
    return page == null || page.isEmpty ? file : '$file · Page $page';
  }

  factory BrainDocumentMemory.fromJson(Map value, int index) {
    // The production preview wraps content and metadata in `draft`. Reading
    // suggestion.content here used to discard every valid PDF memory.
    final raw = value['draft'];
    if (raw is! Map) {
      throw const BrainApiException('The memory preview could not be read.');
    }
    final content = BrainRepository.checkedText(raw['content'], 4000);
    final id = value['id'];
    if (id is! String || id.isEmpty || id.length > 100) {
      throw const BrainApiException('The memory preview could not be read.');
    }
    return BrainDocumentMemory._(
      id: id,
      draft: {
        'content': content,
        'kind': raw['kind'] is String ? raw['kind'] : 'fact',
        'label': raw['label'] is String ? raw['label'] : 'PDF memory ${index + 1}',
        'tags': raw['tags'] is List ? List.of(raw['tags'] as List) : <String>[],
        'importance': raw['importance'] is num ? raw['importance'] : 3,
        'sensitive': raw['sensitive'] == true,
        'source': raw['source'] is String ? raw['source'] : 'file_memory',
      },
      provenance: value['provenance'] is Map
          ? Map<String, dynamic>.from(value['provenance'] as Map)
          : <String, dynamic>{},
    );
  }

  void edit(String value) {
    if (saved) return;
    draft['content'] = BrainRepository.checkedText(value, 4000);
  }
}

/// A native, account-scoped import. Analysis only creates previews; publishing
/// is a separate explicit action. A partial save keeps each acknowledged item.
class BrainDocuments extends ChangeNotifier {
  BrainDocuments(this.repository)
    : _accountRevision = repository.api.auth.revision {
    repository.api.auth.addListener(_authChanged);
  }

  final BrainRepository repository;
  static const supportedExtensions = ['pdf', 'txt', 'md', 'docx', 'csv', 'json'];
  final int _accountRevision;
  bool _disposed = false;
  bool busy = false, trainingSelected = true, trainingPublished = false;
  String? filename, error, notice;
  String expectedTraining = '', trainingDraft = '';
  String memorySummary = '', trainingSummary = '';
  final memories = <BrainDocumentMemory>[];
  final analysisErrors = <String, String>{};
  final _analyzed = <String>{};
  Uint8List? _bytes;
  BrainDocumentDestination destination = BrainDocumentDestination.both;

  bool get isCurrent =>
      !_disposed &&
      repository.api.auth.session != null &&
      repository.api.auth.revision == _accountRevision;
  bool get hasPreview => memories.isNotEmpty || trainingDraft.isNotEmpty;
  bool get hasFile => _bytes != null;
  bool get analysisComplete =>
      (!destination.includesMemory || _analyzed.contains('memory')) &&
      (!destination.includesTraining || _analyzed.contains('training'));
  int get savedCount => memories.where((m) => m.saved).length;
  int get selectedCount => memories.where((m) => m.selected && !m.saved).length;
  bool get hasSelection =>
      selectedCount > 0 ||
      (trainingSelected && trainingDraft.trim().isNotEmpty && !trainingPublished);
  String get combinedTraining => [
    expectedTraining.trim(),
    trainingDraft.trim(),
  ].where((part) => part.isNotEmpty).join('\n\n');

  static void validatePdf(String filename, Uint8List bytes) {
    if (!filename.toLowerCase().endsWith('.pdf')) {
      throw const BrainApiException('Choose a PDF document.');
    }
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const BrainApiException('Choose a nonempty PDF no larger than 10 MB.');
    }
    if (bytes.length < 5 ||
        bytes[0] != 0x25 || bytes[1] != 0x50 || bytes[2] != 0x44 ||
        bytes[3] != 0x46 || bytes[4] != 0x2d) {
      throw const BrainApiException(
        'This file is not a readable PDF. Export it as a PDF and try again.',
      );
    }
  }

  static void validateFile(String filename, Uint8List bytes) {
    final extension = filename.split('.').last.toLowerCase();
    if (!filename.contains('.') || !supportedExtensions.contains(extension)) {
      throw const BrainApiException('Choose a PDF, TXT, Markdown, DOCX, CSV, or JSON document.');
    }
    if (extension == 'pdf') {
      validatePdf(filename, bytes);
      return;
    }
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const BrainApiException('Choose a nonempty document no larger than 10 MB.');
    }
    if (extension == 'docx') {
      if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4b || bytes[2] != 0x03 || bytes[3] != 0x04) {
        throw const BrainApiException('This file is not a readable DOCX. Export the document again.');
      }
      return;
    }
    try {
      final text = utf8.decode(bytes);
      if (text.contains('\u0000') || text.trim().isEmpty) throw const FormatException();
      if (extension == 'json') jsonDecode(text);
    } on FormatException {
      throw const BrainApiException('This document is not readable UTF-8 text. Export it as a PDF or UTF-8 file.');
    }
  }

  void choose(String name, Uint8List bytes, BrainDocumentDestination target) {
    _check();
    if (busy) throw const BrainApiException('Wait for this import to finish.');
    validateFile(name, bytes);
    filename = name.split(RegExp(r'[/\\]')).last;
    _bytes = bytes;
    destination = target;
    expectedTraining = trainingDraft = memorySummary = trainingSummary = '';
    memories.clear();
    _analyzed.clear();
    analysisErrors.clear();
    error = notice = null;
    trainingSelected = true;
    trainingPublished = false;
    _notify();
  }

  void _check() {
    if (!isCurrent) {
      throw const BrainApiException(
        'Your account changed. Close this import and open it again.',
      );
    }
  }

  void _authChanged() {
    if (isCurrent || _disposed) return;
    _bytes = null;
    filename = null;
    expectedTraining = trainingDraft = memorySummary = trainingSummary = '';
    memories.clear();
    analysisErrors.clear();
    error = 'Your account changed. Close this import and open it again.';
    notice = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> analyze() async {
    _check();
    if (busy || _bytes == null || filename == null) return;
    busy = true;
    error = notice = null;
    _notify();
    try {
      await repository.load();
      _check();
      expectedTraining = repository.training;
      for (final kind in [
        if (destination.includesMemory) 'memory',
        if (destination.includesTraining) 'training',
      ]) {
        if (_analyzed.contains(kind)) continue;
        try {
          // The shared file service accepts plain text, not a JSON extension.
          // Preserve JSON imports as an explicit .json.txt text attachment.
          final uploadName = filename!.toLowerCase().endsWith('.json')
              ? '$filename.txt' : filename!;
          final value = await repository.api.analyze(kind, uploadName, _bytes!);
          _check();
          if (value['requiresApproval'] != true || value['autoSaved'] != false) {
            throw const BrainApiException('This PDF preview requires a newer server.');
          }
          if (kind == 'memory') {
            final suggestions = value['suggestions'];
            if (suggestions is! List || suggestions.isEmpty || suggestions.length > 20) {
              throw const BrainApiException('No usable memories were found in this PDF.');
            }
            final next = <BrainDocumentMemory>[];
            for (var i = 0; i < suggestions.length; i++) {
              if (suggestions[i] is! Map) {
                throw const BrainApiException('The memory preview could not be read.');
              }
              next.add(BrainDocumentMemory.fromJson(suggestions[i] as Map, i));
            }
            memories.addAll(next);
            memorySummary = value['summary']?.toString() ?? '';
          } else {
            trainingDraft = BrainRepository.checkedText(value['trainingDraft'], 12000);
            trainingSummary = value['summary']?.toString() ?? '';
          }
          _analyzed.add(kind);
          analysisErrors.remove(kind);
        } catch (failure) {
          _check();
          analysisErrors[kind] = failure.toString();
        }
        _notify();
      }
      if (analysisComplete) _bytes = null;
      notice = hasPreview ? 'Review the PDF draft. Nothing has been saved yet.' : null;
    } finally {
      busy = false;
      _notify();
    }
  }

  void selectMemory(BrainDocumentMemory memory, bool selected) {
    if (busy || memory.saved || !memories.contains(memory)) return;
    memory.selected = selected;
    _notify();
  }

  void editMemory(BrainDocumentMemory memory, String content) {
    _check();
    if (busy || !memories.contains(memory)) return;
    memory.edit(content);
    _notify();
  }

  void editTraining(String value) {
    if (busy || trainingPublished) return;
    trainingDraft = value;
    _notify();
  }

  void selectTraining(bool selected) {
    if (busy || trainingPublished) return;
    trainingSelected = selected;
    _notify();
  }

  Future<void> refreshTraining() async {
    _check();
    if (busy) return;
    busy = true;
    _notify();
    try {
      await repository.load();
      _check();
      expectedTraining = repository.training;
      error = null;
      notice = 'Current training refreshed. Review the addition before saving.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<Map<String, dynamic>> save({required bool confirmed}) async {
    _check();
    if (!confirmed) throw const BrainApiException('Review and confirm the PDF import first.');
    if (busy) throw const BrainApiException('Wait for this import to finish.');
    if (!hasSelection) throw const BrainApiException('Select at least one item to save.');
    final publishTraining = trainingSelected && trainingDraft.trim().isNotEmpty && !trainingPublished;
    final combined = combinedTraining;
    if (publishTraining && combined.length > 12000) {
      throw const BrainApiException(
        'Existing training plus this addition exceeds 12,000 characters. Shorten the draft before publishing.',
      );
    }
    busy = true;
    error = notice = null;
    _notify();
    try {
      await repository.load();
      _check();
      // Verify the complete preview before any write in a Both import.
      if (publishTraining && repository.training != expectedTraining && repository.training != combined) {
        throw const BrainApiException(
          'Training changed in another app. Refresh current training and review the addition again.',
        );
      }
      for (final memory in memories.where((m) => m.selected && !m.saved)) {
        _check();
        final content = BrainRepository.checkedText(memory.content, 4000);
        final existing = repository.memories.where(
          (m) => m['content']?.toString().trim().toLowerCase() == content.toLowerCase(),
        );
        if (existing.isNotEmpty) {
          memory.saved = memory.alreadySaved = true;
          _notify();
          continue;
        }
        final result = await repository.api.json(
          'POST', '${BrainApi.agentPath}/memories',
          {...memory.draft, 'content': content, 'confirmed': true,
            'memoryKey': memory.submissionKey},
        );
        _check();
        final row = result['memory'];
        if (row is! Map || row['id'] is! String || row['content'] != content) {
          throw const BrainApiException('The saved memory was not confirmed. Refresh My Brain before trying again.');
        }
        repository.acceptVoiceMemory(Map<String, dynamic>.from(row));
        memory.saved = true;
        _notify();
      }
      if (publishTraining) {
        _check();
        if (repository.training != combined) {
          await repository.saveTraining(combined, expectedTraining);
          _check();
          if (repository.training != combined) {
            throw const BrainApiException('The complete training addition was not confirmed. Refresh My Brain.');
          }
        }
        trainingPublished = true;
        _notify();
      }
      notice = 'Saved to My Brain. Resume or restart Rici to use the updated knowledge.';
      return repository.snapshot;
    } catch (failure) {
      error = failure.toString();
      notice = savedCount > 0 || trainingPublished
          ? 'The confirmed items remain saved. Review the remaining items below.'
          : null;
      rethrow;
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    repository.api.auth.removeListener(_authChanged);
    _disposed = true;
    _bytes = null;
    super.dispose();
  }
}
