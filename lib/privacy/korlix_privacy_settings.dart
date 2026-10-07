import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/korlix_theme.dart';
import 'korlix_third_party_ai_consent.dart';

/// Public policy access and the current account's local AI-sharing preferences.
class KorlixPrivacySettings extends StatefulWidget {
  const KorlixPrivacySettings({
    super.key,
    required this.sessionChanges,
    required this.isSessionCurrent,
    this.openLink,
    this.resetChoices,
  });

  final Listenable sessionChanges;
  final bool Function() isSessionCurrent;
  final Future<bool> Function(Uri)? openLink;
  final Future<void> Function()? resetChoices;

  @override
  State<KorlixPrivacySettings> createState() => _KorlixPrivacySettingsState();
}

class _KorlixPrivacySettingsState extends State<KorlixPrivacySettings> {
  bool _resetting = false, _confirming = false, _openingLink = false;
  String? _feedback;
  String? _linkError;
  bool _failed = false;

  Future<void> _open(String file) async {
    if (_openingLink) return;
    final uri = Uri.https('www.korlixdeveloper.com', '/$file');
    setState(() {
      _openingLink = true;
      _linkError = null;
    });
    bool opened = false;
    try {
      opened =
          await (widget.openLink?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
    } catch (_) {
      // A browser handoff failure must leave privacy controls available.
    }
    if (!mounted) return;
    setState(() {
      _openingLink = false;
      if (!opened) {
        _linkError = 'Could not open this page. Visit $uri';
      }
    });
  }

  Future<void> _reset() async {
    if (_resetting || _confirming || !widget.isSessionCurrent()) return;
    setState(() => _confirming = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: widget.sessionChanges,
        builder: (context, _) {
          final current = widget.isSessionCurrent();
          return AlertDialog(
            scrollable: true,
            title: const Text('Reset AI-sharing choices?'),
            content: Text(
              current
                  ? 'Remove saved AI-sharing permissions for this account on '
                        'this device. Features that use this permission will '
                        'ask again before a new request.\n\n'
                        'This does not recall content already sent, delete '
                        'saved records, change other devices, or stop active '
                        'sessions and enabled server automations. Stop sessions '
                        'and pause automations in their feature controls.'
                  : 'Your sign-in changed. Reopen Legal & Privacy from your '
                        'account to manage its choices.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('privacy-reset-confirm'),
                onPressed: current
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                child: const Text('Reset choices'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (confirmed != true || !widget.isSessionCurrent()) return;
    setState(() {
      _resetting = true;
      _feedback = null;
    });
    try {
      // revoke captures its account scope synchronously before awaiting storage.
      await (widget.resetChoices?.call() ?? KorlixThirdPartyAiConsent.revoke());
      if (!mounted || !widget.isSessionCurrent()) return;
      setState(() {
        _failed = false;
        _feedback =
            'AI-sharing choices reset for this account on this device. '
            'Features using this permission will ask again.';
      });
    } catch (_) {
      if (!mounted || !widget.isSessionCurrent()) return;
      setState(() {
        _failed = true;
        _feedback =
            'Could not save the reset. Try again. '
            'The reset has not been confirmed.';
      });
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Legal & Privacy')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.sessionChanges,
          builder: (context, _) {
            final current = widget.isSessionCurrent();
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'Your policies and choices',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Open a policy in your browser or manage saved '
                      'AI-sharing permissions below.',
                      style: TextStyle(color: skin.mutedText, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    if (_linkError != null)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _linkError!,
                          style: TextStyle(color: skin.danger, height: 1.5),
                        ),
                      ),
                    for (final entry in const {
                      'legal.html': 'Legal centre & feature disclosures',
                      'privacy-policy.html': 'Privacy Policy',
                      'terms.html': 'Terms of Use',
                      'subscription-terms.html': 'Subscriptions & billing',
                      'delete-account.html': 'Account & data deletion',
                    }.entries)
                      ListTile(
                        key: ValueKey('privacy-link-${entry.key}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(entry.value),
                        trailing: const Icon(Icons.open_in_new, size: 20),
                        onTap: _openingLink ? null : () => _open(entry.key),
                      ),
                    const Divider(height: 32),
                    Text(
                      'AI-sharing choices',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Saved permissions apply to your current account on '
                      'this device. Resetting makes features using these '
                      'permissions ask again; you can decline the next request. '
                      'It does not undo earlier processing or pause enabled '
                      'automations.',
                      style: TextStyle(color: skin.mutedText, height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      key: const Key('privacy-reset-choices'),
                      onPressed: !current || _resetting || _confirming
                          ? null
                          : _reset,
                      icon: _resetting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.restart_alt),
                      label: const Text(
                        'Reset AI-sharing choices on this device',
                      ),
                    ),
                    if (!current || _feedback != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          !current
                              ? 'Your sign-in changed. Reopen Legal & Privacy '
                                    'from your account to manage its choices.'
                              : _feedback!,
                          key: const Key('privacy-feedback'),
                          style: TextStyle(
                            color: current && _failed ? skin.danger : skin.text,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
