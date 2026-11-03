import 'package:flutter/material.dart';

import 'copybox_store.dart';

Future<String?> fillCopyBoxTemplate(BuildContext context, String text) async {
  final fields = templateFields(text);
  if (fields.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Add a field such as {{name}} or {{date}} to turn this box into a reusable template.',
        ),
      ),
    );
    return null;
  }
  return showDialog<String>(
    context: context,
    builder: (_) => _TemplateDialog(text: text, fields: fields),
  );
}

class _TemplateDialog extends StatefulWidget {
  const _TemplateDialog({required this.text, required this.fields});
  final String text;
  final List<String> fields;
  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  late final _controllers = {
    for (final field in widget.fields) field: TextEditingController(),
  };
  final _form = GlobalKey<FormState>();
  String get _preview => renderTemplate(widget.text, {
    for (final entry in _controllers.entries)
      entry.key: entry.value.text.isEmpty
          ? '{{${entry.key}}}'
          : entry.value.text,
  });
  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Make it personal'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Fill the fields, then copy your finished text. Your saved template stays unchanged.',
              ),
              const SizedBox(height: 20),
              for (final entry in _controllers.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TextFormField(
                    controller: entry.value,
                    maxLength: 1000,
                    decoration: InputDecoration(
                      labelText: entry.key,
                      counterText: '',
                    ),
                    validator: (v) =>
                        v?.trim().isEmpty != false ? 'Fill this field.' : null,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'PREVIEW',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(_preview, style: const TextStyle(height: 1.6)),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) Navigator.pop(context, _preview);
        },
        child: const Text('Copy finished text'),
      ),
    ],
  );
}

class CopyBoxFocusEditor extends StatefulWidget {
  const CopyBoxFocusEditor({
    super.key,
    required this.title,
    required this.text,
  });
  final String title, text;
  @override
  State<CopyBoxFocusEditor> createState() => _CopyBoxFocusEditorState();
}

class _CopyBoxFocusEditorState extends State<CopyBoxFocusEditor> {
  late final _text = TextEditingController(text: widget.text);
  bool _leaving = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_leaving) return;
    if (_text.text == widget.text) {
      setState(() => _leaving = true);
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Keep these changes?'),
        content: const Text(
          'Save and close to keep your edits, or discard to return to the original box.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    if (mounted && discard == true) {
      setState(() => _leaving = true);
      Navigator.pop(context);
    }
  }

  void _saveAndClose() {
    if (_leaving) return;
    setState(() => _leaving = true);
    Navigator.pop(context, _text.text);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _leaving || _text.text == widget.text,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close focus editor',
          onPressed: _close,
          icon: const Icon(Icons.close),
        ),
        title: const Text('Focus editor'),
        actions: [
          if (MediaQuery.sizeOf(context).width < 480 ||
              MediaQuery.textScalerOf(context).scale(14) >= 21)
            IconButton(
              key: const Key('focus-save'),
              tooltip: 'Save & close',
              onPressed: _saveAndClose,
              icon: const Icon(Icons.check),
            )
          else
            TextButton(
              key: const Key('focus-save'),
              onPressed: _saveAndClose,
              child: const Text('Save & close'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final title = widget.title.isEmpty
                ? 'Just you and your words.'
                : widget.title;
            final scrolls = constraints.maxHeight < 480 ||
                MediaQuery.textScalerOf(context).scale(18) >= 27;
            final editor = TextField(
              key: const Key('focus-text'),
              controller: _text,
              expands: true,
              minLines: null,
              maxLines: null,
              maxLength: 100000,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontSize: 18, height: 1.7),
              decoration: const InputDecoration(
                hintText: 'Give your next idea some room.',
                counterText: '',
              ),
              onChanged: (_) => setState(() {}),
            );
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  label: title,
                  excludeSemantics: true,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (scrolls)
                  SizedBox(height: 260, child: editor)
                else
                  Expanded(child: editor),
                const SizedBox(height: 14),
                Text(
                  '${_text.text.length} characters · Changes are saved when you choose Save & close.',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            );
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: scrolls
                    ? SingleChildScrollView(
                        key: const Key('focus-editor-scroll'),
                        padding: const EdgeInsets.all(24),
                        child: content,
                      )
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: content,
                      ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class CopyBoxAiReview extends StatefulWidget {
  const CopyBoxAiReview({
    super.key,
    required this.original,
    required this.result,
    required this.action,
    required this.onReport,
  });
  final String original, result, action;
  final Future<void> Function(String reason, String details) onReport;
  @override
  State<CopyBoxAiReview> createState() => _CopyBoxAiReviewState();
}

class _CopyBoxAiReviewState extends State<CopyBoxAiReview> {
  bool _reported = false;
  Future<void> _report() async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => _ReportDialog(onReport: widget.onReport),
    );
    if (mounted && sent == true) setState(() => _reported = true);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Review · ${widget.action}'),
    content: SizedBox(
      width: 650,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your original stays in place until you apply the draft. Review facts and wording before using it.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 24),
            const Text(
              'ORIGINAL',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              widget.original,
              style: const TextStyle(height: 1.6),
            ),
            const Divider(height: 36),
            const Text(
              'AI DRAFT',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(widget.result, style: const TextStyle(height: 1.6)),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: _reported ? null : _report,
              icon: Icon(
                _reported ? Icons.check : Icons.flag_outlined,
                size: 17,
              ),
              label: Text(_reported ? 'Report received' : 'Report this output'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Keep original'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, 'new'),
        child: const Text('Save as new box'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, 'apply'),
        child: const Text('Apply draft'),
      ),
    ],
  );
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.onReport});
  final Future<void> Function(String, String) onReport;
  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _details = TextEditingController();
  String? _reason, _error;
  bool _busy = false;
  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || _reason == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onReport(_reason!, _details.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'We could not confirm this report. It may already be saved. Contact support@korlixdeveloper.com before submitting it again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Report AI output'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Your selected reason, details, and an excerpt of this AI output will be sent to KORLIX for review.',
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: _reason,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: const [
                  DropdownMenuItem(
                    value: 'offensive',
                    child: Text('Offensive or harmful'),
                  ),
                  DropdownMenuItem(
                    value: 'inaccurate',
                    child: Text('Inaccurate or misleading'),
                  ),
                  DropdownMenuItem(
                    value: 'privacy',
                    child: Text('Privacy concern'),
                  ),
                  DropdownMenuItem(
                    value: 'other',
                    child: Text('Other concern'),
                  ),
                ],
                onChanged: _busy ? null : (v) => setState(() => _reason = v),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _details,
                maxLength: 1500,
                maxLines: 3,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Details (optional)',
                ),
              ),
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || _reason == null || _error != null ? null : _send,
          child: Text(_busy ? 'Sending…' : 'Send report'),
        ),
      ],
    ),
  );
}
