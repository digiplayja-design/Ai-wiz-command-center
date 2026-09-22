import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';

class FunnelMetaConnection extends StatefulWidget {
  const FunnelMetaConnection({super.key, required this.client, this.openUrl});
  final FunnelClient client;
  final Future<bool> Function(Uri)? openUrl;
  @override
  State<FunnelMetaConnection> createState() => _FunnelMetaConnectionState();
}

class _FunnelMetaConnectionState extends State<FunnelMetaConnection> {
  Map<String, dynamic> _state = {};
  Map<String, dynamic>? _attempt;
  bool _busy = false;
  String? _error, _message;
  String _search = '';
  @override
  void initState() {
    super.initState();
    unawaited(_run(_refresh));
  }

  Map<String, dynamic>? get connection => _state['connection'] is Map
      ? Map<String, dynamic>.from(_state['connection'])
      : null;
  bool get ready => _state['configured'] == true;
  bool get reconnect => connection?['needs_reconnect'] == true;
  Future<void> _refresh() async {
    final result = await widget.client.request('GET', '/meta/connection');
    if (mounted) setState(() => _state = result);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _begin() => _run(() async {
    final result = await widget.client.request('POST', '/meta/begin');
    final uri = Uri.tryParse('${result['authorization_url']}');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'www.facebook.com' ||
        uri.userInfo.isNotEmpty) {
      throw const FunnelException(
        'Meta sign-in could not be prepared. Try again.',
      );
    }
    if (mounted) {
      setState(() {
        _attempt = result;
        _message =
            'Sign-in is ready. Continue to Meta, then return to this window.';
      });
    }
  });
  Future<void> _open() async {
    if (_busy || _attempt == null) return;
    final uri = Uri.parse('${_attempt!['authorization_url']}');
    // _run invokes its action synchronously, preserving the browser tap gesture.
    await _run(() async {
      final opened =
          await (widget.openUrl?.call(uri) ??
              launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
                webOnlyWindowName: '_blank',
              ));
      if (!opened) {
        throw const FunnelException(
          'The sign-in window did not open. Tap Continue to Meta again.',
        );
      }
      if (mounted) {
        setState(
          () => _message =
              'Complete sign-in in Meta. Return here and tap Finish connection.',
        );
      }
    });
  }

  Future<void> _finish() => _run(() async {
    final attempt = _attempt!;
    final result = await widget.client.request(
      'POST',
      '/meta/finish',
      body: {'id': attempt['id'], 'proof': attempt['proof']},
    );
    if (!mounted) return;
    setState(() {
      _state = result;
      _attempt = null;
      _message = 'Meta connected. Choose the ad account you want to use.';
    });
    final refreshed = await widget.client.request('POST', '/meta/accounts');
    if (mounted) setState(() => _state = refreshed);
  });
  Future<void> _accounts() => _run(() async {
    final result = await widget.client.request('POST', '/meta/accounts');
    if (mounted) setState(() => _state = result);
  });
  Future<void> _select(Map account) => _run(() async {
    final result = await widget.client.request(
      'POST',
      '/meta/select',
      body: {'account_id': account['id'], 'version': connection!['version']},
    );
    if (mounted) {
      setState(() {
        _state = result;
        _message =
            'Ad account selected. Campaign plans are still local to KORLIX.';
      });
    }
  });
  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Meta?'),
        content: const Text(
          'This removes the saved Meta connection and account details from KORLIX. Your campaign plans remain. Ads already running in Meta keep running. You can also remove KORLIX from Meta Business Integrations to revoke its permission.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep connection'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect Meta'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      final result = await widget.client.request(
        'POST',
        '/meta/disconnect',
        body: {'confirmed': true, 'version': connection?['version']},
      );
      if (mounted) {
        setState(() {
          _state = result;
          _attempt = null;
          _message = 'Meta connection removed from KORLIX.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = connection;
    final accounts = (c?['accounts'] as List? ?? [])
        .where(
          (a) => ('${a['name']} ${a['id']} ${a['currency']}')
              .toLowerCase()
              .contains(_search.toLowerCase()),
        )
        .toList();
    final pending = _state['pending'] != null;
    final status = c != null
        ? (reconnect ? 'Reconnect needed' : 'Connected')
        : ready
        ? 'Ready to connect'
        : 'Setup pending';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: WfStyle.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: WfStyle.cyan.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.hub_outlined, color: WfStyle.cyan),
              const Text(
                'Meta ad accounts',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              WfBadge(status),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Connect your reach.',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose the ad accounts you share with KORLIX. This connection reads account details. Ad publishing and automatic spend reporting are coming next.',
            style: TextStyle(color: WfStyle.muted, height: 1.5),
          ),
          if (!ready) ...[
            const SizedBox(height: 14),
            const Text(
              'Meta connections need platform setup. Your saved campaign plans and manual results are available now.',
              style: TextStyle(color: WfStyle.cyan, height: 1.5),
            ),
          ],
          if (reconnect) ...[
            const SizedBox(height: 14),
            const Text(
              'Meta access has expired or changed. Reconnect to load your available accounts.',
              style: TextStyle(color: Colors.amber, height: 1.5),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(color: Colors.orangeAccent, height: 1.5),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 14),
            Text(
              _message!,
              style: const TextStyle(color: WfStyle.cyan, height: 1.5),
            ),
          ],
          if (pending && _attempt == null) ...[
            const SizedBox(height: 12),
            const Text(
              'A sign-in was started in another window or before this page reloaded. Finish in the original window, or start a new connection here.',
              style: TextStyle(color: WfStyle.muted, height: 1.5),
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (_attempt == null)
                FilledButton.icon(
                  onPressed: ready && !_busy ? _begin : null,
                  icon: const Icon(Icons.link),
                  label: Text(c != null ? 'Reconnect Meta' : 'Connect Meta'),
                ),
              if (_attempt != null) ...[
                FilledButton.icon(
                  onPressed: _busy ? null : _open,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Continue to Meta'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _finish,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Finish connection'),
                ),
                TextButton(
                  onPressed: _busy ? null : _begin,
                  child: const Text('Start again'),
                ),
              ],
              if (c != null && ready && !reconnect)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _accounts,
                  icon: const Icon(Icons.sync),
                  label: const Text('Refresh ad accounts'),
                ),
              OutlinedButton(
                onPressed: _busy ? null : () => _run(_refresh),
                child: const Text('Check connection'),
              ),
              if (c != null || pending || _attempt != null)
                TextButton(
                  onPressed: _busy ? null : _disconnect,
                  child: const Text('Disconnect'),
                ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (c != null) ...[
            const SizedBox(height: 18),
            Text(
              'Access expires: ${DateTime.tryParse('${c['expires_at']}')?.toLocal().toString().split('.').first ?? 'Check connection'}',
              style: const TextStyle(color: WfStyle.muted, fontSize: 12),
            ),
            if (c['refreshed_at'] != null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Account details are a snapshot from the last refresh.',
                  style: TextStyle(color: WfStyle.muted, fontSize: 12),
                ),
              ),
            const SizedBox(height: 14),
            if ((c['accounts'] as List? ?? []).length > 3)
              TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Find an ad account',
                  hintText: 'Name, account ID or currency',
                ),
              ),
            if (accounts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _search.isNotEmpty
                      ? 'No accounts match your search.'
                      : reconnect
                      ? 'Reconnect to refresh your account list.'
                      : 'No ad accounts loaded. Refresh accounts, or check that your Meta login has access to an ad account.',
                  style: const TextStyle(color: WfStyle.muted, height: 1.5),
                ),
              ),
            for (final a in accounts)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF071B29),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: c['selected_account'] == a['id']
                        ? WfStyle.cyan
                        : WfStyle.line,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${a['name']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${a['id']} · ${a['currency']} · ${a['timezone']}',
                      style: const TextStyle(color: WfStyle.muted, height: 1.5),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        WfBadge(
                          a['status'] == 1
                              ? 'Active in Meta'
                              : 'Meta status ${a['status']}',
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              _busy ||
                                  !ready ||
                                  reconnect ||
                                  c['selected_account'] == a['id']
                              ? null
                              : () => _select(Map.from(a)),
                          icon: Icon(
                            c['selected_account'] == a['id']
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                          ),
                          label: Text(
                            c['selected_account'] == a['id']
                                ? 'Selected account'
                                : 'Use this account',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
