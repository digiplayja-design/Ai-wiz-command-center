import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';

Map<String, dynamic> googleAdsState(Map<String, dynamic> value) {
  bool id(dynamic x) => x is String && RegExp(r'^\d{10}$').hasMatch(x);
  bool bounded(dynamic x, int n) => x is String && x.length <= n;
  final c = value['connection'], pending = value['pending'];
  var valid = value['configured'] is bool;
  if (c != null) {
    valid =
        valid &&
        c is Map &&
        c['version'] is int &&
        c['version'] > 0 &&
        c['needs_reconnect'] is bool &&
        c['roots'] is List &&
        c['roots'].length <= 500 &&
        c['roots'].every(id) &&
        c['roots'].toSet().length == c['roots'].length &&
        c['accounts'] is List &&
        c['accounts'].length <= 500;
    if (valid) {
      valid =
          (c['root_id'] == null || c['roots'].contains(c['root_id'])) &&
          (c['root_name'] == null || bounded(c['root_name'], 200)) &&
          (c['login_customer_id'] == null ||
              c['login_customer_id'] == c['root_id']);
      final ids = <String>{};
      for (final a in c['accounts']) {
        if (a is! Map ||
            !id(a['id']) ||
            !ids.add(a['id']) ||
            !bounded(a['name'], 200) ||
            !bounded(a['currency'], 3) ||
            !bounded(a['timezone'], 100) ||
            a['manager'] != false ||
            a['status'] != 'ENABLED' ||
            a['test_account'] is! bool) {
          valid = false;
          break;
        }
      }
      valid =
          valid &&
          (c['accounts'].isEmpty || c['root_id'] != null) &&
          (c['selected_account'] == null ||
              ids.contains(c['selected_account']));
    }
  }
  if (pending != null) {
    valid =
        valid &&
        pending is Map &&
        ['waiting', 'exchanging', 'ready', 'failed'].contains(pending['phase']);
  }
  if (!valid) {
    throw const FunnelException(
      'Google connection details could not be read. Check the connection again.',
    );
  }
  return value;
}

class FunnelGoogleAdsConnection extends StatefulWidget {
  const FunnelGoogleAdsConnection({
    super.key,
    required this.client,
    this.openUrl,
  });
  final FunnelClient client;
  final Future<bool> Function(Uri)? openUrl;
  @override
  State<FunnelGoogleAdsConnection> createState() =>
      _FunnelGoogleAdsConnectionState();
}

class _FunnelGoogleAdsConnectionState extends State<FunnelGoogleAdsConnection> {
  Map<String, dynamic>? _state, _attempt;
  Uri? _authorization;
  String? _error, _message, _root;
  String _search = '';
  final _searchController = TextEditingController();
  bool _busy = false, _denied = false;
  int _generation = 0;
  Map<String, dynamic>? get _connection => _state?['connection'] == null
      ? null
      : Map<String, dynamic>.from(_state!['connection']);
  bool _current(int generation) =>
      mounted && !_denied && generation == _generation;

  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
    _run(_refresh);
  }

  void _clear() {
    _generation++;
    _state = null;
    _attempt = null;
    _authorization = null;
    _root = null;
    _search = '';
    _searchController.clear();
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
  void didUpdateWidget(covariant FunnelGoogleAdsConnection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      oldWidget.client.removeAccessDeniedListener(_deny);
      widget.client.addAccessDeniedListener(_deny);
      _clear();
      _denied = false;
      _run(_refresh);
    }
  }

  @override
  void dispose() {
    _generation++;
    _searchController.dispose();
    widget.client.removeAccessDeniedListener(_deny);
    super.dispose();
  }

  void _apply(Map<String, dynamic> value, int generation) {
    if (!_current(generation)) return;
    final state = googleAdsState(value);
    setState(() {
      _state = state;
      final c = _connection, roots = c?['roots'] as List? ?? [];
      if (!roots.contains(_root)) {
        _root =
            c?['root_id'] ?? (roots.length == 1 ? roots.first as String : null);
      }
    });
  }

  Future<void> _refresh(int g) async =>
      _apply(await widget.client.request('GET', '/google-ads/connection'), g);
  Future<void> _run(Future<void> Function(int) task) async {
    if (_busy || _denied) return;
    final g = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await task(g);
    } catch (e) {
      if (_current(g)) {
        setState(() {
          _error = e is FunnelException
              ? e.message
              : 'Google Ads could not complete this request. Try again.';
        });
      }
    } finally {
      if (_current(g)) setState(() => _busy = false);
    }
  }

  void _begin() => _run((g) async {
    final a = await widget.client.request(
      'POST',
      '/google-ads/begin',
      body: {},
    );
    if (!_current(g)) return;
    final u = Uri.tryParse('${a['authorization_url']}');
    if (u == null ||
        u.scheme != 'https' ||
        u.host != 'accounts.google.com' ||
        u.path != '/o/oauth2/v2/auth' ||
        u.userInfo.isNotEmpty ||
        u.port != 443 ||
        u.hasFragment ||
        a['id'] is! String ||
        !RegExp(r'^[a-f0-9-]{36}$').hasMatch(a['id']) ||
        a['proof'] is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(a['proof'])) {
      throw const FunnelException(
        'Google sign-in could not be prepared. Try again.',
      );
    }
    setState(() {
      _attempt = {'id': a['id'], 'proof': a['proof']};
      _authorization = u;
    });
  });

  // Invoke the launcher directly from the tap; Safari needs the user gesture.
  void _open() {
    if (_authorization == null || _busy || _denied) return;
    final g = _generation;
    final opening =
        widget.openUrl?.call(_authorization!) ??
        launchUrl(
          _authorization!,
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_blank',
        );
    opening
        .then((ok) {
          if (_current(g)) {
            setState(() {
              _error = ok
                  ? null
                  : 'The Google window did not open. Tap Continue to Google again.';
              _message = ok
                  ? 'Complete Google sign-in, then return here to finish the connection.'
                  : null;
            });
          }
        })
        .catchError((Object _) {
          if (_current(g)) {
            setState(
              () => _error =
                  'The Google window did not open. Tap Continue to Google again.',
            );
          }
        });
  }

  void _finish() => _run((g) async {
    final result = await widget.client.request(
      'POST',
      '/google-ads/finish',
      body: _attempt,
    );
    if (!_current(g)) return;
    _apply(result, g);
    setState(() {
      _attempt = null;
      _authorization = null;
    });
    await _roots(g);
  });

  Future<void> _roots(int g) async {
    final c = _connection;
    if (c == null) return;
    final result = await widget.client.request(
      'POST',
      '/google-ads/roots',
      body: {'version': c['version']},
    );
    _apply(result, g);
    if (_current(g)) {
      setState(() {
        _search = '';
        _searchController.clear();
        _message =
            'Access accounts refreshed. Load an account below and select the advertising account to use.';
      });
    }
  }

  void _accounts() => _run((g) async {
    final result = await widget.client.request(
      'POST',
      '/google-ads/accounts',
      body: {'root_id': _root, 'version': _connection!['version']},
    );
    _apply(result, g);
    if (_current(g)) {
      setState(() {
        _search = '';
        _searchController.clear();
      });
    }
  });

  void _select(String id) => _run((g) async {
    _apply(
      await widget.client.request(
        'POST',
        '/google-ads/select',
        body: {
          'root_id': _connection!['root_id'],
          'account_id': id,
          'version': _connection!['version'],
        },
      ),
      g,
    );
  });

  Future<void> _disconnect() async {
    final g = _generation, version = _connection?['version'];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Google Ads?'),
        content: const Text(
          'Remove Google credentials, cached account details and pending sign-in from KORLIX. Ads already running on Google keep running. To revoke Google consent too, remove KORLIX in your Google Account connections.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Google connection'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect Google Ads'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_current(g)) return;
    _run((ticket) async {
      _apply(
        await widget.client.request(
          'POST',
          '/google-ads/disconnect',
          body: {'confirmed': true, 'version': version},
        ),
        ticket,
      );
      if (_current(ticket)) {
        setState(() {
          _attempt = null;
          _authorization = null;
          _root = null;
          _search = '';
          _searchController.clear();
        });
      }
    });
  }

  Widget _caption(String text) =>
      Text(text, style: const TextStyle(color: WfStyle.muted, height: 1.5));
  Widget _gap([double height = 12]) => SizedBox(height: height);
  @override
  Widget build(BuildContext context) {
    final c = _connection, ready = !_denied && _state?['configured'] == true;
    final reconnect = c?['needs_reconnect'] == true;
    final usable = ready && !reconnect && !_busy;
    final roots = c?['roots'] as List? ?? [];
    final accounts = (c?['accounts'] as List? ?? [])
        .where(
          (a) => '${a['name']} ${a['id']} ${a['currency']}'
              .toLowerCase()
              .contains(_search.toLowerCase()),
        )
        .toList();
    final status = _denied
        ? 'Access unavailable'
        : _state == null
        ? 'Checking connection'
        : !ready
        ? 'Setup pending'
        : reconnect
        ? 'Reconnect needed'
        : c == null
        ? 'Ready to connect'
        : 'Connected';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: WfStyle.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: WfStyle.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.ads_click, color: WfStyle.cyan),
              const Text(
                'Google Ads accounts',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              WfBadge(status),
            ],
          ),
          _gap(),
          _caption(
            'Connect Google Ads and choose an advertising account. This release reads account details. Reporting and ad publishing are not available here yet.',
          ),
          _gap(8),
          _caption(
            'Google asks for permission to view and manage Ads data. KORLIX currently uses that permission only to read account details. Connecting does not launch ads or change budgets.',
          ),
          if (!_denied && _state != null && !ready) ...[
            _gap(),
            _caption(
              'Google Ads connections need platform setup. Your campaign plans and manual results remain available.',
            ),
          ],
          if (_denied) ...[
            _gap(),
            _caption(
              'Sign in with Enterprise access to use Google Ads connections.',
            ),
          ],
          if (reconnect) ...[
            _gap(),
            _caption(
              'Google access expired or changed. Reconnect to refresh your accounts.',
            ),
          ],
          if (_state?['pending'] != null && _attempt == null) ...[
            _gap(),
            _caption(
              'A sign-in is pending. Finish in the original window, or start a new connection here after 30 seconds.',
            ),
          ],
          if (_error != null) ...[
            _gap(),
            Text(
              _error!,
              style: const TextStyle(color: Colors.orangeAccent, height: 1.5),
            ),
          ],
          if (_message != null) ...[
            _gap(),
            Text(
              _message!,
              style: const TextStyle(color: WfStyle.cyan, height: 1.5),
            ),
          ],
          _gap(18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (_attempt == null)
                FilledButton.icon(
                  onPressed: ready && !_busy ? _begin : null,
                  icon: const Icon(Icons.link),
                  label: Text(
                    c == null ? 'Connect Google Ads' : 'Reconnect Google Ads',
                  ),
                ),
              if (_attempt != null) ...[
                FilledButton.icon(
                  onPressed: ready && !_busy ? _open : null,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Continue to Google'),
                ),
                OutlinedButton.icon(
                  onPressed: ready && !_busy ? _finish : null,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Finish Google connection'),
                ),
                TextButton(
                  onPressed: ready && !_busy ? _begin : null,
                  child: const Text('Start Google sign-in again'),
                ),
              ],
              if (c != null && ready && !reconnect)
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(_roots),
                  child: const Text('Refresh access accounts'),
                ),
              OutlinedButton(
                onPressed: _busy || _denied ? null : () => _run(_refresh),
                child: const Text('Check Google connection'),
              ),
              if (c != null || _state?['pending'] != null || _attempt != null)
                TextButton(
                  onPressed: _busy || _denied ? null : _disconnect,
                  child: const Text('Disconnect Google'),
                ),
            ],
          ),
          if (_busy) ...[_gap(), const LinearProgressIndicator(minHeight: 2)],
          if (c != null && ready && !reconnect) ...[
            _gap(18),
            _caption(
              'Choose an account you can access directly, then load its active advertising accounts. A manager account includes its direct and indirect clients.',
            ),
            _gap(),
            if (roots.isEmpty)
              _caption(
                'No access accounts loaded. Refresh access accounts, or check that your Google login has access to Google Ads.',
              ),
            if (roots.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                key: ValueKey('google-root:$_root:${c['version']}'),
                initialValue: _root,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Access account ID',
                  helperText: 'Direct account or manager account',
                ),
                items: roots
                    .map(
                      (id) => DropdownMenuItem<String>(
                        value: id as String,
                        child: Text(id),
                      ),
                    )
                    .toList(),
                onChanged: _busy ? null : (v) => setState(() => _root = v),
              ),
              _gap(),
              OutlinedButton.icon(
                onPressed: usable && _root != null ? _accounts : null,
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Load Google accounts'),
              ),
            ],
            if (c['root_id'] != null) ...[
              _gap(),
              _caption(
                'Loaded from ${c['root_name'] ?? c['root_id']} · ${c['root_id']}. Account details are a snapshot from the last refresh.',
              ),
              if (_root != c['root_id']) ...[
                _gap(),
                _caption(
                  'Load the new access account to replace the list below.',
                ),
              ],
              if ((c['accounts'] as List).length > 3) ...[
                _gap(),
                TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _search = v),
                  decoration: const InputDecoration(
                    labelText: 'Find a Google account',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ],
              if (accounts.isEmpty) ...[
                _gap(),
                _caption(
                  _search.isEmpty
                      ? 'No active advertising accounts were found under this access account.'
                      : 'No Google accounts match your search.',
                ),
              ],
              for (final a in accounts)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: WfStyle.background,
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
                        a['name'],
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      _gap(6),
                      _caption(
                        '${a['id']} · ${a['currency']} · ${a['timezone']}',
                      ),
                      _gap(),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          WfBadge(
                            a['test_account'] == true
                                ? 'Google test account'
                                : 'Active in Google',
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                usable &&
                                    _root == c['root_id'] &&
                                    c['selected_account'] != a['id']
                                ? () => _select(a['id'])
                                : null,
                            icon: Icon(
                              c['selected_account'] == a['id']
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                            ),
                            label: Text(
                              c['selected_account'] == a['id']
                                  ? 'Selected Google account'
                                  : 'Use Google account',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}
