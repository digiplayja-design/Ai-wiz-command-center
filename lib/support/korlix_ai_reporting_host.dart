import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ai_wiz_command_center/auth/korlix_http.dart' as http;

import 'korlix_ai_report_client.dart';
import 'korlix_saved_output_report_dialog.dart';

/// Reporting stays inside the app on routes without a saved output card,
/// including live voice and podcast playback. This does not capture the screen,
/// microphone audio, or unrelated conversation history.
class KorlixAiReportingHost extends StatefulWidget {
  const KorlixAiReportingHost({
    super.key,
    required this.child,
    required this.navigatorKey,
    required this.sessionChanges,
    required this.accountScope,
    required this.headersBuilder,
    required this.endpoint,
    this.client,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final Listenable sessionChanges;
  final String? Function() accountScope;
  final Future<Map<String, String>> Function() headersBuilder;
  final Uri endpoint;
  final http.Client? client;

  @override
  State<KorlixAiReportingHost> createState() => _KorlixAiReportingHostState();
}

class _KorlixAiReportingHostState extends State<KorlixAiReportingHost> {
  bool _presenting = false;

  Future<void> _open() async {
    if (_presenting) return;
    final account = widget.accountScope();
    final dialogContext = widget.navigatorKey.currentState?.overlay?.context;
    if (account == null || account.isEmpty || dialogContext == null) return;

    var validSession = true;
    void invalidateSession() => validSession = false;
    bool current() => mounted && validSession && widget.accountScope() == account;
    final changes = widget.sessionChanges;
    changes.addListener(invalidateSession);
    setState(() => _presenting = true);
    try {
      final receipt = await showDialog<String>(
        context: dialogContext,
        barrierDismissible: false,
        builder: (_) => KorlixSavedOutputReportDialog(
          title: 'Report AI content',
          description:
              'Tell us which feature you used and describe or quote the AI '
              'content that needs review. Your description and reason will '
              'be sent privately to KORLIX support.',
          detailsRequired: true,
          sessionChanges: changes,
          isSessionCurrent: current,
          submitReport: (reason, details) async {
            if (!current()) {
              throw const KorlixAiReportException(
                'Your account changed. Open the report again.',
              );
            }
            final headers = await widget.headersBuilder();
            return submitKorlixAiReport(
              endpoint: widget.endpoint,
              headers: headers,
              reason: reason,
              details: details,
              prompt: '',
              outputSummary: details,
              contentType: 'ai_output',
              appArea: 'app_wide_ai_reporting',
              platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
              isCurrent: current,
              client: widget.client,
            );
          },
        ),
      );
      if (receipt == null || !current() || !dialogContext.mounted) return;
      await showDialog<void>(
        context: dialogContext,
        builder: (context) => AlertDialog(
          title: const Text('Report received'),
          content: SelectableText(
            'Your report was saved for review.\n\nReference: $receipt',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } finally {
      changes.removeListener(invalidateSession);
      if (mounted) setState(() => _presenting = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.sessionChanges,
    builder: (context, _) {
      final signedIn = widget.accountScope()?.isNotEmpty == true;
      // Scaffolds own keyboard avoidance. Hide the footer while typing instead
      // of covering input controls or applying the keyboard inset twice.
      final showFooter = signedIn && MediaQuery.viewInsetsOf(context).bottom == 0;
      return Column(
        children: [
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: showFooter,
              child: widget.child,
            ),
          ),
          if (showFooter)
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    key: const Key('app-wide-report-ai-content'),
                    onPressed: _presenting ? null : _open,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(Icons.flag_outlined, size: 20),
                    label: const Text(
                      'Report AI content',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
