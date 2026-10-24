import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:korlix_receipt_core/privacy/korlix_third_party_ai_consent.dart';

import 'receipt_auth.dart';

class ReceiptAccountScreen extends StatefulWidget {
  const ReceiptAccountScreen({
    super.key,
    required this.auth,
    required this.largeText,
    required this.highContrast,
    required this.reduceMotion,
    required this.preference,
    this.onOpenPlan,
  });
  final ReceiptAuthController auth;
  final bool largeText, highContrast, reduceMotion;
  final Future<void> Function(String, bool) preference;
  final Future<void> Function()? onOpenPlan;
  @override
  State<ReceiptAccountScreen> createState() => _ReceiptAccountScreenState();
}

class _ReceiptAccountScreenState extends State<ReceiptAccountScreen> {
  late bool _large = widget.largeText,
      _contrast = widget.highContrast,
      _motion = widget.reduceMotion;
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();
  bool _busy = false;
  String? _notice;

  Future<void> _open(String path) async {
    final uri = Uri.https('www.korlixdeveloper.com', '/$path');
    bool opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      /* Show the address when no browser is available. */
    }
    if (!opened && mounted) {
      setState(() => _notice = 'Open $uri in your browser.');
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Request deletion of your KORLIX account?'),
        content: const Text(
          'This requests deletion of your shared KORLIX account and associated data, '
          'including receipts used in KORLIX AI. It does not delete only this app. '
          'Export receipts you want to keep first.\n\n'
          'Support may need to verify your request. Cancel any paid subscriptions separately with your billing provider.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep account'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Request deletion'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await widget.auth.requestAccountDeletion();
      if (mounted) {
        setState(
          () => _notice = 'Your account deletion request was received. Support may contact you to verify it.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _notice = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change(String key, bool value) async {
    setState(() {
      if (key == 'large_text') _large = value;
      if (key == 'high_contrast') _contrast = value;
      if (key == 'reduce_motion') _motion = value;
    });
    try {
      await widget.preference(key, value);
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = 'This setting could not be saved. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Account & settings')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          widget.auth.session?.email ?? 'KORLIX account',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'One account for Receipt Wiz and KORLIX AI. Your receipt library is shared across both apps.',
        ),
        const SizedBox(height: 24),
        if (widget.onOpenPlan != null) ...[
          ListTile(
            leading: const Icon(
              Icons.workspace_premium_outlined,
              color: Color(0xFF7145C7),
            ),
            title: const Text('Receipt Wiz plan'),
            subtitle: const Text(
              'Monthly scan allowance, upgrade and purchases',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onOpenPlan,
          ),
          const Divider(height: 28),
        ],
        Semantics(
          header: true,
          child: Text(
            'Accessibility',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        SwitchListTile(
          title: const Text('Larger text'),
          subtitle: const Text(
            'Keeps any larger text size set on your device.',
          ),
          value: _large,
          onChanged: (v) => _change('large_text', v),
        ),
        SwitchListTile(
          title: const Text('Higher contrast'),
          value: _contrast,
          onChanged: (v) => _change('high_contrast', v),
        ),
        SwitchListTile(
          title: const Text('Reduce motion'),
          value: _motion,
          onChanged: (v) => _change('reduce_motion', v),
        ),
        const Divider(height: 32),
        Semantics(
          header: true,
          child: Text(
            'Legal & Privacy',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ListTile(
          title: const Text('Terms of Use'),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _open('terms.html'),
        ),
        ListTile(
          title: const Text('Privacy Policy'),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _open('privacy-policy.html'),
        ),
        ListTile(
          title: const Text('Receipt storage & account deletion'),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _open('delete-account.html'),
        ),
        ListTile(
          title: const Text('Reset AI scanning consent'),
          subtitle: const Text(
            'You will be asked before sending another receipt to OpenAI. Manual entry stays available.',
          ),
          onTap: () async {
            try {
              await KorlixThirdPartyAiConsent.revoke();
              if (mounted) {
                setState(() => _notice = 'AI scanning consent reset.');
              }
            } catch (_) {
              if (mounted) {
                setState(
                  () =>
                      _notice = 'Consent could not be reset. Please try again.',
                );
              }
            }
          },
        ),
        FutureBuilder<PackageInfo>(
          future: _info,
          builder: (context, snapshot) => ListTile(
            title: const Text('KORLIX Receipt Wiz'),
            subtitle: SelectableText(
              snapshot.hasData
                  ? 'Version ${snapshot.data!.version} • Build ${snapshot.data!.buildNumber}'
                  : snapshot.hasError
                  ? 'Version information unavailable'
                  : 'Version information loading…',
            ),
          ),
        ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Semantics(liveRegion: true, child: Text(_notice!)),
          ),
        const Divider(height: 32),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await widget.auth.signOut();
                  } catch (_) {
                    if (mounted) {
                      setState(() {
                        _busy = false;
                        _notice =
                            'Could not finish signing out. Please try again.';
                      });
                    }
                  }
                },
          child: const Text('Sign out of Receipt Wiz'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _delete,
          child: const Text('Request KORLIX account deletion'),
        ),
      ],
    ),
  );
}
