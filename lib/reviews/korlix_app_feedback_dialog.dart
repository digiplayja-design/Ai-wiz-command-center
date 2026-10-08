import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../sounds/korlix_sound_actions.dart';
import '../support/korlix_ai_report_client.dart';
import '../theme/korlix_theme.dart';

/// General feedback uses the authenticated, durable private support queue.
/// It never sends a score or changes eligibility for a public store review.
Future<String> submitKorlixAppFeedback({
  required String baseUrl,
  required Map<String, String> headers,
  required String topic,
  required String details,
  http.Client? client,
}) => submitKorlixAiReport(
  endpoint: Uri.parse(
    '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/report-output',
  ),
  headers: headers,
  contentType: 'app_feedback',
  appArea: 'app_feedback',
  reason: topic,
  details: details.trim(),
  prompt: '',
  outputSummary: '',
  platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
  client: client,
);

/// Returns a durable receipt only after the backend confirms this submission.
/// Any sign-in change invalidates the open form rather than sending its draft
/// under a different account. Callers should pass their auth revision notifier.
Future<String?> showKorlixAppFeedbackDialog(
  BuildContext context, {
  required String baseUrl,
  required Map<String, String> Function() headersBuilder,
  required Listenable sessionChanges,
}) async {
  var current = true;
  void invalidateSession() => current = false;
  sessionChanges.addListener(invalidateSession);
  final String? receipt;
  try {
    receipt = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => KorlixAppFeedbackDialog(
        sessionChanges: sessionChanges,
        isSessionCurrent: () => current,
        submitFeedback: (topic, details) => submitKorlixAppFeedback(
          baseUrl: baseUrl,
          headers: headersBuilder(),
          topic: topic,
          details: details,
        ),
      ),
    );
  } finally {
    sessionChanges.removeListener(invalidateSession);
  }
  if (!current) return null;
  if (receipt != null && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Feedback sent privately to KORLIX. Thank you.'),
      ),
    );
  }
  return receipt;
}

class KorlixAppFeedbackDialog extends StatefulWidget {
  const KorlixAppFeedbackDialog({
    super.key,
    required this.sessionChanges,
    required this.submitFeedback,
    this.isSessionCurrent,
  });

  final Listenable sessionChanges;
  final Future<String> Function(String topic, String details) submitFeedback;
  final bool Function()? isSessionCurrent;

  @override
  State<KorlixAppFeedbackDialog> createState() =>
      _KorlixAppFeedbackDialogState();
}

class _KorlixAppFeedbackDialogState extends State<KorlixAppFeedbackDialog> {
  final _form = GlobalKey<FormState>();
  final _details = TextEditingController();
  String _topic = 'General feedback';
  String? _error;
  bool _submitting = false;
  bool _sessionCurrent = true;

  @override
  void initState() {
    super.initState();
    _sessionCurrent = widget.isSessionCurrent?.call() ?? true;
    widget.sessionChanges.addListener(_sessionChanged);
  }

  @override
  void didUpdateWidget(covariant KorlixAppFeedbackDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionChanges != widget.sessionChanges) {
      oldWidget.sessionChanges.removeListener(_sessionChanged);
      widget.sessionChanges.addListener(_sessionChanged);
      _sessionChanged();
    }
  }

  void _sessionChanged() {
    if (!mounted || !_sessionCurrent) return;
    _details.clear();
    setState(() {
      _sessionCurrent = false;
      _topic = 'General feedback';
      _error = null;
    });
  }

  @override
  void dispose() {
    widget.sessionChanges.removeListener(_sessionChanged);
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting ||
        !_sessionCurrent ||
        !(widget.isSessionCurrent?.call() ?? true) ||
        !_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final receipt = await widget.submitFeedback(_topic, _details.text.trim());
      if (!mounted || !_sessionCurrent) return;
      Navigator.of(context).pop(receipt);
    } catch (error) {
      if (!mounted || !_sessionCurrent) return;
      setState(() {
        // The existing transport confirms durable receipts and never retries
        // uncertain requests. Keep the draft available without claiming success.
        _error = error is KorlixAiReportException
            ? error.message
                  .replaceAll('reports', 'feedback')
                  .replaceAll('report', 'feedback')
                  .replaceAll('Reporting', 'Feedback')
            : 'We could not confirm whether your feedback was received. '
                  'Contact support@korlixdeveloper.com for help before sending again.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final enabled = _sessionCurrent && !_submitting;
    return PopScope(
      canPop: !_submitting || !_sessionCurrent,
      child: AlertDialog(
        backgroundColor: skin.panel,
        scrollable: true,
        title: Text('Share feedback', style: TextStyle(color: skin.text)),
        content: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tell us what you love, what needs fixing, or what you would '
                'like next. Sent privately to KORLIX support; this is not posted '
                'as a store review.',
                style: TextStyle(color: skin.mutedText, height: 1.4),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('app-feedback-topic-$_sessionCurrent'),
                initialValue: _topic,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Topic'),
                items:
                    const [
                          'General feedback',
                          'Something I love',
                          'Problem or bug',
                          'Idea or suggestion',
                          'Privacy or safety concern',
                        ]
                        .map(
                          (topic) => DropdownMenuItem(
                            value: topic,
                            child: Text(topic, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                onChanged: enabled
                    ? (value) => setState(() => _topic = value!)
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('app-feedback-details'),
                controller: _details,
                enabled: enabled,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Your feedback',
                  helperText: 'Avoid adding passwords, payment details, or other sensitive information.',
                  helperMaxLines: 4,
                  alignLabelWithHint: true,
                ),
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'Enter your feedback.'
                    : null,
              ),
              if (!_sessionCurrent || _error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _sessionCurrent ? _error! : 'Your sign-in changed. Close this dialog and reopen feedback.',
                    key: const Key('app-feedback-status'),
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
              _submitting && _sessionCurrent
                  ? null
                  : () => Navigator.of(context).pop(),
            ),
            child: Text(
              _error != null || !_sessionCurrent ? 'Close' : 'Cancel',
            ),
          ),
          FilledButton(
            key: const Key('app-feedback-submit'),
            style: korlixSoundButtonStyle(null),
            onPressed: korlixSoundAction(enabled ? _submit : null),
            child: Text(
              _submitting && _sessionCurrent
                  ? 'Sending feedback…'
                  : 'Send feedback',
            ),
          ),
        ],
      ),
    );
  }
}
