import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../sounds/korlix_sound_actions.dart';
import '../theme/korlix_theme.dart';

/// Confirms and submits a deletion request without implying deletion is complete.
class KorlixAccountDeletionDialog extends StatefulWidget {
  const KorlixAccountDeletionDialog({
    super.key,
    required this.sessionChanges,
    required this.isSessionCurrent,
    required this.submitRequest,
    this.showAppleSubscriptions = false,
    this.openLink,
  });

  final Listenable sessionChanges;
  final bool Function() isSessionCurrent;
  final Future<void> Function() submitRequest;
  final bool showAppleSubscriptions;
  final Future<bool> Function(Uri)? openLink;

  @override
  State<KorlixAccountDeletionDialog> createState() =>
      _KorlixAccountDeletionDialogState();
}

class _KorlixAccountDeletionDialogState
    extends State<KorlixAccountDeletionDialog> {
  bool _submitting = false;
  bool _attempted = false;
  bool _openingLink = false;
  String? _error;

  Future<void> _openLink(Uri uri) async {
    if (_openingLink || _submitting || !widget.isSessionCurrent()) return;
    setState(() {
      _openingLink = true;
      _error = null;
    });
    bool opened = false;
    try {
      opened =
          await (widget.openLink?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
    } catch (_) {
      // A missing browser or canceled handoff must leave the dialog usable.
    }
    if (!mounted) return;
    setState(() {
      _openingLink = false;
      if (!opened) _error = 'Could not open this page. Please try again.';
    });
  }

  Future<void> _submit() async {
    if (_submitting || _openingLink || !widget.isSessionCurrent()) return;
    setState(() {
      _submitting = true;
      _attempted = true;
      _error = null;
    });
    try {
      await widget.submitRequest().timeout(const Duration(seconds: 15));
      if (!mounted || !widget.isSessionCurrent()) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted || !widget.isSessionCurrent()) return;
      setState(() {
        _error =
            'We could not confirm whether your request was recorded. '
            'Try again, or contact support@korlixdeveloper.com for help. '
            'Your account has not been confirmed deleted.';
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
        final enabled = current && !_submitting && !_openingLink;
        return PopScope(
          canPop: !_submitting || !current,
          child: AlertDialog(
            backgroundColor: skin.panel,
            scrollable: true,
            title: Text(
              'Request account deletion?',
              style: TextStyle(color: skin.text),
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'This sends a request to delete your Korlix AI account and '
                  'associated data. It does not immediately delete the account. '
                  'Support may need to verify ownership or clarify the request.',
                  style: TextStyle(color: skin.text, height: 1.4),
                ),
                const SizedBox(height: 14),
                Text(
                  'Export any records you want to keep before requesting deletion. '
                  'Cancel recurring subscriptions separately with the provider '
                  'that bills you. Account deletion does not automatically cancel '
                  'a subscription or issue a refund.',
                  style: TextStyle(color: skin.mutedText, height: 1.4),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('account-deletion-policy'),
                  style: korlixSoundButtonStyle(null),
                  onPressed: korlixSoundAction(
                    enabled
                        ? () => _openLink(
                            Uri.https(
                              'www.korlixdeveloper.com',
                              '/delete-account.html',
                            ),
                          )
                        : null,
                  ),
                  child: const Text('Read account and data deletion policy'),
                ),
                if (widget.showAppleSubscriptions)
                  TextButton(
                    key: const Key('account-deletion-apple-subscriptions'),
                    style: korlixSoundButtonStyle(null),
                    onPressed: korlixSoundAction(
                      enabled
                          ? () => _openLink(
                              Uri.https(
                                'apps.apple.com',
                                '/account/subscriptions',
                              ),
                            )
                          : null,
                    ),
                    child: const Text('Manage Apple subscriptions'),
                  ),
                if (!current || _error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      current
                          ? _error!
                          : 'Your sign-in changed. Close this dialog '
                                'and reopen account settings to continue.',
                      key: const Key('account-deletion-feedback'),
                      style: TextStyle(color: skin.text, height: 1.4),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                style: korlixSoundButtonStyle(null),
                onPressed: korlixSoundAction(
                  _submitting && current
                      ? null
                      : () => Navigator.of(context).pop(false),
                ),
                child: Text(current && !_attempted ? 'Cancel' : 'Close'),
              ),
              FilledButton(
                key: const Key('account-deletion-submit'),
                style: korlixSoundButtonStyle(
                  FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                ),
                onPressed: korlixSoundAction(enabled ? _submit : null),
                child: Text(
                  _submitting
                      ? 'Sending request…'
                      : _attempted
                      ? 'Try again'
                      : 'Request deletion',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
