import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'brain_api.dart';
import 'brain_documents.dart';
import 'brain_repository.dart';

class BrainDocumentScreen extends StatefulWidget {
  const BrainDocumentScreen({
    super.key,
    required this.repository,
    required this.requestConsent,
    required this.onSaved,
    this.initialDestination = BrainDocumentDestination.both,
  });

  final BrainRepository repository;
  final Future<bool> Function() requestConsent;
  final ValueChanged<Map<String, dynamic>> onSaved;
  final BrainDocumentDestination initialDestination;

  @override
  State<BrainDocumentScreen> createState() => _BrainDocumentScreenState();
}

class _BrainDocumentScreenState extends State<BrainDocumentScreen> {
  late final BrainDocuments _documents;
  late BrainDocumentDestination _destination;
  final _training = TextEditingController();
  bool _picking = false, _saving = false;
  String? _error;
  Route<dynamic>? _dialogRoute;

  @override
  void initState() {
    super.initState();
    _documents = BrainDocuments(widget.repository)..addListener(_changed);
    _destination = widget.initialDestination;
  }

  void _changed() {
    if (!mounted) return;
    if (!_documents.isCurrent) {
      _training.clear();
      _saving = false;
      final route = _dialogRoute;
      _dialogRoute = null;
      if (route != null && route.isActive) route.navigator?.removeRoute(route);
    }
    setState(() {});
  }

  bool get _busy => _picking || _documents.busy;

  Future<void> _choosePdf() async {
    if (_busy) return;
    setState(() { _picking = true; _error = null; });
    try {
      final files = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: BrainDocuments.supportedExtensions,
        allowMultiple: false,
        withData: true,
      );
      if (!mounted || files == null) return;
      final file = files.files.single;
      if (file.size > 10 * 1024 * 1024 || file.bytes == null) {
        throw const BrainApiException('Choose a readable document no larger than 10 MB.');
      }
      _documents.choose(file.name, file.bytes!, _destination);
      _training.clear();
    } catch (failure) {
      if (mounted) setState(() => _error = failure.toString());
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _analyze() async {
    if (_busy) return;
    setState(() { _picking = true; _error = null; });
    try {
      if (!await widget.requestConsent() || !mounted) return;
      await _documents.analyze();
      if (mounted) _training.text = _documents.trainingDraft;
    } catch (failure) {
      if (mounted) setState(() => _error = failure.toString());
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _edit(BrainDocumentMemory memory) async {
    if (!_documents.isCurrent || _busy) return;
    final edited = await showDialog<String>(
      context: context,
      builder: (context) {
        _dialogRoute = ModalRoute.of(context);
        if (!_documents.isCurrent) {
          return const AlertDialog(content: Text('Your account changed. Close this import and open it again.'));
        }
        return _DocumentMemoryEditor(content: memory.content);
      },
    );
    _dialogRoute = null;
    if (!mounted || !_documents.isCurrent || edited == null) return;
    try {
      _documents.editMemory(memory, edited);
    } catch (failure) {
      setState(() => _error = failure.toString());
    }
  }

  Future<void> _save() async {
    if (_busy || !_documents.hasSelection) return;
    final memoryCount = _documents.selectedCount;
    final publishTraining = _documents.trainingSelected &&
        _documents.trainingDraft.trim().isNotEmpty && !_documents.trainingPublished;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        _dialogRoute = ModalRoute.of(context);
        return AlertDialog(
        title: const Text('Save this PDF knowledge?'),
        content: Text([
          if (memoryCount > 0) 'Save $memoryCount selected ${memoryCount == 1 ? 'memory' : 'memories'}.',
          if (publishTraining) 'Add the reviewed training to your current instructions.',
          'These changes apply to your shared KORLIX general voice agent.',
        ].join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep reviewing')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve & save')),
        ],
        );
      },
    );
    _dialogRoute = null;
    if (!mounted || !_documents.isCurrent || confirmed != true) return;
    setState(() { _saving = true; _error = null; });
    try {
      await _documents.save(confirmed: true);
    } catch (failure) {
      if (mounted) setState(() => _error = failure.toString());
    } finally {
      // A failed later item must not hide earlier acknowledged saves on home.
      if (mounted) {
        if (_documents.isCurrent) widget.onSaved(widget.repository.snapshot);
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _refreshTraining() async {
    try {
      setState(() => _error = null);
      await _documents.refreshTraining();
    } catch (failure) {
      if (mounted) setState(() => _error = failure.toString());
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('Upload PDF')),
      body: !_documents.isCurrent
          ? const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Your account changed. Close this import and open it again.'),
            ))
          : SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Text('Teach Rici from a document', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Choose Memory for facts to remember, Training for instructions, or both. Review the extracted draft before saving.'),
            const SizedBox(height: 20),
            DropdownButtonFormField<BrainDocumentDestination>(
              initialValue: _destination,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Use this document for'),
              items: [
                for (final item in BrainDocumentDestination.values)
                  DropdownMenuItem(value: item, child: Text(item.label)),
              ],
              onChanged: _busy || _documents.hasPreview ? null : (value) {
                if (value != null) {
                  setState(() {
                    _destination = value;
                    _documents.destination = value;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _choosePdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_documents.filename == null ? 'Choose PDF or document' : 'Choose another document'),
            ),
            if (_documents.filename != null) ...[
              const SizedBox(height: 8),
              Text(_documents.filename!, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('Destination: ${_documents.destination.label}'),
            ],
            const SizedBox(height: 8),
            const Text('PDF, TXT, Markdown, DOCX, CSV or JSON · up to 10 MB. The document is analyzed to create a draft; KORLIX saves only the knowledge you approve.'),
            const SizedBox(height: 12),
            if (_documents.hasFile)
              OutlinedButton.icon(
                onPressed: _busy ? null : _analyze,
                icon: const Icon(Icons.auto_awesome),
                label: Text(_documents.hasPreview ? 'Analyze remaining destination' : 'Analyze document'),
              ),
            if (!_documents.hasPreview)
              Text(_destination == BrainDocumentDestination.both
                  ? 'Uses 1 file-analysis credit for Memory and 1 for Training when each preview succeeds.'
                  : 'Uses 1 file-analysis credit when the preview succeeds.'),
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(_saving ? 'Saving the approved items…' : _documents.busy ? 'Reading your PDF. Larger documents can take a few minutes…' : 'Preparing your document…'),
            ],
            for (final entry in _documents.analysisErrors.entries)
              _message('${entry.key == 'memory' ? 'Memory' : 'Training'} preview: ${entry.value}', error: true),
            if (_documents.memories.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Review memories', style: Theme.of(context).textTheme.titleLarge),
              const Text('Select each memory you want to save. You can edit it first.'),
              if (_documents.memorySummary.isNotEmpty) _message(_documents.memorySummary),
              for (final memory in _documents.memories) _memoryCard(memory),
            ],
            if (_documents.trainingDraft.isNotEmpty || _documents.trainingSummary.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Review training', style: Theme.of(context).textTheme.titleLarge),
              if (_documents.trainingSummary.isNotEmpty) _message(_documents.trainingSummary),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Current training'),
                subtitle: const Text('Your existing instructions are preserved.'),
                children: [
                  Align(alignment: Alignment.centerLeft, child: SelectableText(
                    _documents.expectedTraining.isEmpty ? 'No existing training.' : _documents.expectedTraining,
                  )),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _training,
                enabled: !_busy && !_documents.trainingPublished,
                minLines: 5,
                maxLines: 14,
                maxLength: 12000,
                onChanged: _documents.editTraining,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Training to add',
                  alignLabelWithHint: true,
                ),
              ),
              Text('${_documents.combinedTraining.length} / 12,000 total characters with existing training.'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _documents.trainingSelected,
                onChanged: _busy || _documents.trainingPublished ? null : (value) => _documents.selectTraining(value == true),
                title: Text(_documents.trainingPublished ? 'Training saved' : 'Add this training'),
                subtitle: const Text('The reviewed text will be added after your existing instructions.'),
              ),
              if (!_documents.trainingPublished)
                TextButton(onPressed: _busy ? null : _refreshTraining, child: const Text('Refresh current training')),
            ],
            if (_error != null || _documents.error != null) _message(_error ?? _documents.error!, error: true),
            if (_documents.notice != null) _message(_documents.notice!),
            if (_documents.hasPreview) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy || !_documents.hasSelection ? null : _save,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Review & save selected items'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: Text(_documents.savedCount > 0 || _documents.trainingPublished ? 'Done' : 'Cancel import'),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _message(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Semantics(liveRegion: true, child: Text(text,
      style: error ? TextStyle(color: Theme.of(context).colorScheme.error) : null,
    )),
  );

  Widget _memoryCard(BrainDocumentMemory memory) => Card(
    margin: const EdgeInsets.only(top: 12),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: memory.saved || memory.selected,
          onChanged: _busy || memory.saved ? null : (value) => _documents.selectMemory(memory, value == true),
          title: Text(memory.label),
          subtitle: Text(memory.saved ? memory.alreadySaved ? 'Already in My Brain' : 'Saved to My Brain' : memory.sourceLabel),
        ),
        SelectableText(memory.content),
        if (memory.sensitive)
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('Contains sensitive information. Save only if you want Rici to retain it.')),
        if (!memory.saved)
          Align(alignment: Alignment.centerLeft, child: TextButton(
            onPressed: _busy ? null : () => _edit(memory),
            child: const Text('Edit memory'),
          )),
      ]),
    ),
  );

  @override
  void dispose() {
    _documents.removeListener(_changed);
    _documents.dispose();
    _training.dispose();
    super.dispose();
  }
}

class _DocumentMemoryEditor extends StatefulWidget {
  const _DocumentMemoryEditor({required this.content});
  final String content;
  @override
  State<_DocumentMemoryEditor> createState() => _DocumentMemoryEditorState();
}

class _DocumentMemoryEditorState extends State<_DocumentMemoryEditor> {
  late final TextEditingController _controller = TextEditingController(text: widget.content);
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Review memory'),
    content: SizedBox(width: 520, child: SingleChildScrollView(child: TextField(
      controller: _controller,
      minLines: 5,
      maxLines: 14,
      maxLength: 4000,
      decoration: const InputDecoration(labelText: 'Memory to save'),
    ))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Use edited memory')),
    ],
  );
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
}
