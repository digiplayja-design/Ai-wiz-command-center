import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';
import 'funnel_meta_performance.dart';
import 'funnel_meta_pages.dart';

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
  bool _busy = false, _denied = false;
  int _generation = 0;
  String? _error, _message;
  String _search = '';
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
    unawaited(_run(_refresh));
  }

  Map<String, dynamic>? get connection => _state['connection'] is Map
      ? Map<String, dynamic>.from(_state['connection'])
      : null;
  bool get ready => _state['configured'] == true;
  bool get reconnect => connection?['needs_reconnect'] == true;
  bool _current(int g) => mounted && !_denied && g == _generation;
  void _clear() {
    _generation++;
    _state = {};
    _attempt = null;
    _search = '';
    _error = null;
    _message = null;
    _busy = false;
  }

  void _deny() {
    if (!mounted) return;
    setState(() {
      _clear();
      _denied = true;
    });
  }

  @override
  void didUpdateWidget(covariant FunnelMetaConnection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      oldWidget.client.removeAccessDeniedListener(_deny);
      widget.client.addAccessDeniedListener(_deny);
      _clear();
      _denied = false;
      unawaited(_run(_refresh));
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.client.removeAccessDeniedListener(_deny);
    super.dispose();
  }

  void _apply(Map<String, dynamic> result, int g) {
    if (!_current(g)) return;
    try {
      validateMetaPages(result);
    } catch (_) {
      setState(() => _state = {});
      rethrow;
    }
    setState(() => _state = result);
  }

  Future<void> _refresh(int g) async {
    final result = await widget.client.request('GET', '/meta/connection');
    _apply(result, g);
  }

  Future<void> _run(Future<void> Function(int) action) async {
    if (_busy || _denied) return;
    final g = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action(g);
    } catch (e) {
      if (_current(g)) {
        if (e is FunnelException && e.status == 409) {
          // Permission/selection changes can clear saved Page details server-side.
          // Hide the previous snapshot even if the status reload fails.
          setState(() => _state = {});
          try {
            await _refresh(g);
          } catch (_) {
            /* Retain the actionable error. */
          }
        }
        if (_current(g)) {
          setState(
            () => _error = e is FunnelException
                ? e.message
                : 'Meta could not complete this request. Try again.',
          );
        }
      }
    } finally {
      if (_current(g)) setState(() => _busy = false);
    }
  }

  Future<void> _begin() => _run((g) async {
    final result = await widget.client.request('POST', '/meta/begin');
    if (!_current(g)) return;
    final uri = Uri.tryParse('${result['authorization_url']}');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'www.facebook.com' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        uri.hasFragment ||
        !RegExp(r'^/v\d{2,3}\.0/dialog/oauth$').hasMatch(uri.path)) {
      throw const FunnelException(
        'Meta sign-in could not be prepared. Try again.',
      );
    }
    if (_current(g)) {
      setState(() {
        _attempt = result;
        _message =
            'Sign-in is ready. Continue to Meta, then return to this window.';
      });
    }
  });
  Future<void> _open() async {
    if (_busy || _denied || _attempt == null) return;
    final uri = Uri.parse('${_attempt!['authorization_url']}');
    // _run invokes its action synchronously, preserving the browser tap gesture.
    await _run((g) async {
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
      if (_current(g)) {
        setState(
          () => _message =
              'Complete sign-in in Meta. Return here and tap Finish connection.',
        );
      }
    });
  }

  Future<void> _finish() => _run((g) async {
    final attempt = _attempt!;
    final result = await widget.client.request(
      'POST',
      '/meta/finish',
      body: {'id': attempt['id'], 'proof': attempt['proof']},
    );
    if (!_current(g)) return;
    _apply(result, g);
    setState(() {
      _attempt = null;
      _message = 'Meta connected. Choose the ad account you want to use.';
    });
    final refreshed = await widget.client.request('POST', '/meta/accounts');
    _apply(refreshed, g);
  });
  Future<void> _accounts() => _run((g) async {
    final result = await widget.client.request('POST', '/meta/accounts');
    _apply(result, g);
  });
  Future<void> _select(Map account) => _run((g) async {
    final result = await widget.client.request(
      'POST',
      '/meta/select',
      body: {'account_id': account['id'], 'version': connection!['version']},
    );
    if (_current(g)) {
      _apply(result, g);
      setState(() {
        _message =
            'Ad account selected. Campaign plans are still local to KORLIX.';
      });
    }
  });
  Future<void> _disconnect() async {
    if (_busy || _denied) return;
    final before = _generation, v = connection?['version'];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Meta?'),
        content: const Text(
          'This removes the saved Meta connection and account and Page details from KORLIX. Your campaign plans remain. Ads already running in Meta keep running. You can also remove KORLIX from Meta Business Integrations to revoke its permission.',
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
    if (confirmed != true || !_current(before)) return;
    await _run((g) async {
      final result = await widget.client.request(
        'POST',
        '/meta/disconnect',
        body: {'confirmed': true, 'version': v},
      );
      if (_current(g)) {
        _apply(result, g);
        setState(() {
          _attempt = null;
          _message = 'Meta connection removed from KORLIX.';
        });
      }
    });
  }

  Future<void> _pageAction(String action, [String? pageId]) => _run((g) async {
    final c = connection!;
    final result = await widget.client.request(
      'POST',
      '/meta/$action',
      body: {
        'version': c['version'],
        'account_id': c['selected_account'],
        'page_id': ?pageId,
      },
    );
    _apply(result, g);
    if (_current(g)) {
      setState(
        () => _message = action == 'select-page'
            ? 'Facebook Page selected for your Meta setup.'
            : action == 'clear-page'
            ? 'Facebook Page selection cleared.'
            : 'Facebook Pages refreshed.',
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    if (_denied) {
      return const Text(
        'Sign in with Enterprise access to manage your Meta connection.',
      );
    }
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
            'Choose the ad accounts you share with KORLIX. Read account details and load performance reports. Ad publishing remains unavailable.',
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
          if (c != null)
            FunnelMetaPages(
              key: ValueKey(
                '${identityHashCode(widget.client)}:${c['version']}',
              ),
              connection: c,
              available: ready && !reconnect && !_busy,
              onAction: _pageAction,
            ),
          FunnelMetaPerformance(
            client: widget.client,
            connection: c,
            available: ready && !reconnect && !_busy,
          ),
        ],
      ),
    );
  }
}
