import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'messenger_auth.dart';

class MessengerAccountScreen extends StatefulWidget {
  const MessengerAccountScreen({super.key, required this.auth});
  final MessengerAuthController auth;
  @override
  State<MessengerAccountScreen> createState() => _MessengerAccountScreenState();
}

class _MessengerAccountScreenState extends State<MessengerAccountScreen> {
  bool _busy = false;
  String? _notice;

  Future<void> _open(String path) async {
    final url = Uri.https('www.korlixdeveloper.com', '/$path');
    try {
      if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      /* Keep the link available when the system cannot open it. */
    }
    if (mounted) setState(() => _notice = 'Open $url in your browser.');
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await action();
      if (mounted) setState(() => _notice = success);
    } catch (error) {
      if (mounted) setState(() => _notice = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request KORLIX account deletion?'),
        content: const Text(
          'This affects your shared KORLIX account and its associated data across KORLIX apps, including Social. It does not delete only Messenger. Support may need to verify your request. Cancel any paid subscriptions separately with your billing provider.',
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
    if (approved == true && mounted) {
      await _run(
        widget.auth.requestAccountDeletion,
        success: 'Your account deletion request was received. Support may contact you to verify it.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Account & help')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          widget.auth.session?.email ?? 'KORLIX account',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'Your KORLIX account, contacts and conversations work here and in KORLIX AI. Messenger has its own sign-in session.',
        ),
        const SizedBox(height: 24),
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
          title: const Text('Account deletion information'),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _open('delete-account.html'),
        ),
        const ListTile(
          title: Text('KORLIX Messenger'),
          subtitle: Text('Version 0.1.0 • Build 1'),
        ),
        if (_notice != null)
          Semantics(liveRegion: true, child: SelectableText(_notice!)),
        const Divider(height: 32),
        OutlinedButton(
          onPressed: _busy ? null : () => _run(widget.auth.signOut),
          child: const Text('Sign out of Messenger'),
        ),
        TextButton(
          onPressed: _busy ? null : _delete,
          child: const Text('Request KORLIX account deletion'),
        ),
      ],
    ),
  );
}
