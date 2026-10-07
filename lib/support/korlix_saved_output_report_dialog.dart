import 'package:flutter/material.dart';

import '../sounds/korlix_sound_actions.dart';
import '../theme/korlix_theme.dart';
import 'korlix_ai_report_client.dart';

class KorlixSavedOutputReportDialog extends StatefulWidget {
  const KorlixSavedOutputReportDialog({
    super.key,
    required this.sessionChanges,
    required this.isSessionCurrent,
    required this.submitReport,
  });

  final Listenable sessionChanges;
  final bool Function() isSessionCurrent;
  final Future<String> Function(String reason, String details) submitReport;

  @override
  State<KorlixSavedOutputReportDialog> createState() =>
      _KorlixSavedOutputReportDialogState();
}

class _KorlixSavedOutputReportDialogState
    extends State<KorlixSavedOutputReportDialog> {
  final _form = GlobalKey<FormState>();
  final _details = TextEditingController();
  String? _reason;
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting ||
        !widget.isSessionCurrent() ||
        !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final reportId = await widget.submitReport(
        _reason!,
        _details.text.trim(),
      );
      if (mounted && widget.isSessionCurrent()) {
        Navigator.of(context).pop(reportId);
      }
    } catch (error) {
      if (!mounted || !widget.isSessionCurrent()) return;
      setState(() {
        _error = error is KorlixAiReportException
            ? error.message
            : 'We could not confirm whether your report was received. '
                  'Contact support@korlixdeveloper.com for help.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    return ListenableBuilder(
      listenable: widget.sessionChanges,
      builder: (context, _) {
        final current = widget.isSessionCurrent();
        final enabled = current && !_submitting;
        return PopScope(
          canPop: !_submitting || !current,
          child: AlertDialog(
            backgroundColor: skin.panel,
            scrollable: true,
            title: Text(
              'Report saved output',
              style: TextStyle(color: skin.text),
            ),
            content: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Tell us what needs review. An excerpt of this saved prompt '
                    'and response will be included with your report.',
                    style: TextStyle(color: skin.mutedText, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: const Key('saved-report-reason'),
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    items:
                        const [
                              'Unsafe or harmful',
                              'False or misleading',
                              'Hate or harassment',
                              'Sexual content',
                              'Privacy concern',
                              'Other',
                            ]
                            .map(
                              (reason) => DropdownMenuItem(
                                value: reason,
                                child: Text(
                                  reason,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: enabled
                        ? (value) => setState(() => _reason = value)
                        : null,
                    validator: (value) =>
                        value == null ? 'Choose a reason.' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const Key('saved-report-details'),
                    controller: _details,
                    enabled: enabled,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'What happened?',
                      helperText:
                          'Optional unless you select Other. Avoid adding passwords or payment details.',
                      helperMaxLines: 4,
                      alignLabelWithHint: true,
                    ),
                    validator: (value) =>
                        _reason == 'Other' && (value?.trim().isEmpty ?? true)
                        ? 'Describe what needs review.'
                        : null,
                  ),
                  if (!current || _error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        current
                            ? _error!
                            : 'Your sign-in changed. Close this dialog and reopen your saved output.',
                        key: const Key('saved-report-feedback'),
                        style: TextStyle(color: skin.text, height: 1.4),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                style: korlixSoundButtonStyle(null),
                onPressed: korlixSoundAction(
                  _submitting && current
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
                child: Text(_error != null || !current ? 'Close' : 'Cancel'),
              ),
              FilledButton(
                key: const Key('saved-report-submit'),
                style: korlixSoundButtonStyle(null),
                onPressed: korlixSoundAction(enabled ? _submit : null),
                child: Text(_submitting ? 'Sending report…' : 'Submit report'),
              ),
            ],
          ),
        );
      },
    );
  }
}
