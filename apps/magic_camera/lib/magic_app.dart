import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:korlix_receipt_core/auth/korlix_http.dart' as transport;
import 'package:korlix_receipt_core/auth/korlix_session_refresh.dart';
import 'package:korlix_receipt_core/privacy/korlix_third_party_ai_consent.dart';
import 'package:korlix_magic_core/magic_client.dart';
import 'package:korlix_magic_core/magic_screen.dart';
import 'package:korlix_magic_core/magic_theme.dart';

import 'magic_auth.dart';
import 'magic_auth_screen.dart';
import 'magic_billing.dart';
import 'magic_plan.dart';

class MagicCameraApp extends StatefulWidget {
  const MagicCameraApp({super.key, required this.auth});
  final MagicAuthController auth;
  @override
  State<MagicCameraApp> createState() => _MagicCameraAppState();
}

class _MagicCameraAppState extends State<MagicCameraApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    transport.configureClientFactory(
      () => KorlixSessionHttpClient(
        inner: http.Client(),
        sessions: widget.auth.sessions,
        baseUrl: widget.auth.backendUrl,
      ),
    );
    unawaited(widget.auth.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) unawaited(widget.auth.resume());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    transport.configureClientFactory(null);
    widget.auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.auth,
    builder: (context, _) {
      final a = widget.auth;
      return MaterialApp(
        key: ValueKey(
          a.session == null
              ? 'signed-out'
              : korlixSessionIdentity(a.session!.accessToken),
        ),
        title: 'Korlix Magic Camera',
        debugShowCheckedModeBanner: false,
        theme: magicTheme(),
        home: !a.ready
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : a.session == null
            ? MagicAuthScreen(auth: a)
            : _Home(auth: a),
      );
    },
  );
}

class _Home extends StatefulWidget {
  const _Home({required this.auth});
  final MagicAuthController auth;
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  late final MagicClient _client = MagicClient(
    backendUrl: widget.auth.backendUrl,
    headers: widget.auth.headers,
    sessionChanges: widget.auth,
  );
  late final MagicBillingService _billing = MagicBillingService(
    backendUrl: widget.auth.backendUrl,
    headers: widget.auth.headers,
    sessionChanges: widget.auth,
  );
  @override
  void initState() {
    super.initState();
    unawaited(_billing.start());
  }

  @override
  void dispose() {
    _client.dispose();
    _billing.dispose();
    super.dispose();
  }

  Future<void> _plan() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => MagicPlan(billing: _billing)),
    );
  }

  void _account() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => _Account(auth: widget.auth, onPlan: _plan),
    ),
  );
  @override
  Widget build(BuildContext context) => MagicScreen(
    client: _client,
    standalone: true,
    onAccount: _account,
    onUpgrade: _plan,
    ensureConsent: () => ensureKorlixThirdPartyAiConsent(
      context: context,
      featureName: 'Korlix Magic Camera',
      providers: const {KorlixThirdPartyAiProvider.openAi},
      dataCategories: const {
        KorlixThirdPartyAiDataCategory.imagesAndPhotos,
        KorlixThirdPartyAiDataCategory.typedTextAndPrompts,
      },
    ),
  );
}

class _Account extends StatefulWidget {
  const _Account({required this.auth, required this.onPlan});
  final MagicAuthController auth;
  final VoidCallback onPlan;
  @override
  State<_Account> createState() => _AccountState();
}

class _AccountState extends State<_Account> {
  String? _message;
  bool _busy = false;
  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Request account deletion?'),
        content: const Text(
          'This requests deletion of your shared KORLIX account, including your other KORLIX apps. Manage any store subscriptions separately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep account'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Request deletion'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => _busy = true);
    try {
      await widget.auth.requestAccountDeletion();
      if (mounted) {
        setState(() => _message = 'Your deletion request was received.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Your deletion request was not sent. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _link(String path) async {
    final url = Uri.https('www.korlixdeveloper.com', '/$path');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication) &&
          mounted) {
        setState(() => _message = 'Open $url in your browser.');
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Open $url in your browser.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your Korlix account')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Center(child: MagicMark(size: 100)),
        const SizedBox(height: 20),
        Text(widget.auth.session?.email ?? '', textAlign: TextAlign.center),
        const SizedBox(height: 20),
        ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: const Text('Your magic plan'),
          onTap: widget.onPlan,
        ),
        const ListTile(
          leading: Icon(Icons.privacy_tip_outlined),
          title: Text('Your photo privacy'),
          subtitle: Text(
            'Captures are processed privately and removed after processing or expiry. Only finished images appear in your gallery. You can delete saved photos at any time.',
          ),
        ),
        ListTile(
          title: const Text('Privacy policy'),
          onTap: () => _link('privacy-policy'),
        ),
        ListTile(
          title: const Text('Terms of use'),
          onTap: () => _link('terms-of-use'),
        ),
        if (_message != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_message!)),
        OutlinedButton(
          onPressed: _busy ? null : () => widget.auth.signOut(),
          child: const Text('Sign out'),
        ),
        TextButton(
          onPressed: _busy ? null : _delete,
          child: const Text('Request account deletion'),
        ),
      ],
    ),
  );
}
