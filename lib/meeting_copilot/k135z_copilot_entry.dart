import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'k135z_zoom_runtime_binding.dart';
import 'korlix_meeting_copilot_access.dart';
import 'korlix_meeting_copilot_route.dart';
import 'korlix_zoom_connection_client.dart';

// A route bookmark is a preference, never authentication or listening consent.
class K135zCopilotEntry extends StatefulWidget {
  const K135zCopilotEntry({super.key, required this.backendBaseUri,
    required this.headersBuilder, required this.authChanges, this.client,
    this.zoomTransport});
  final Uri backendBaseUri;
  final Map<String, String> Function() headersBuilder;
  final Listenable authChanges;
  final http.Client? client;
  final KorlixZoomJsonTransport? zoomTransport;
  @override
  State<K135zCopilotEntry> createState() => _K135zCopilotEntryState();
}

class _K135zCopilotEntryState extends State<K135zCopilotEntry> {
  late final http.Client _client = widget.client ?? http.Client();
  K135zZoomLaunch? _launch, _incoming;
  List<Map<String, String>> _agents = [];
  String? _preferenceKey, _authorization;
  String _message = 'Restoring your agent…';
  bool _loading = true, _initialized = false, _locked = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    widget.authChanges.addListener(_authChanged);
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    _incoming = args is K135zZoomLaunch ? args : null;
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _restore(); });
  }
  String? _currentAuthorization() {
    try { return K135zZoomLaunch.authorization(widget.headersBuilder()); }
    catch (_) { return null; }
  }
  bool _current(int epoch, String authorization) => mounted && epoch == _epoch &&
    _currentAuthorization() == authorization;
  void _authChanged() {
    if (_currentAuthorization() != _authorization) unawaited(_restore());
  }
  Future<Map<String, dynamic>> _read(String path, String authorization) async {
    final base = widget.backendBaseUri;
    if (base.scheme != 'https' || base.host.isEmpty || base.userInfo.isNotEmpty) throw StateError('Invalid backend');
    final req = http.Request('GET', base.resolve(path))..followRedirects = false;
    req.headers.addAll({
      for (final entry in widget.headersBuilder().entries)
        if (entry.key.toLowerCase() != 'authorization') entry.key: entry.value,
      'Authorization': authorization,
    });
    final res = await _client.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200 || res.bodyBytes.length > 2 * 1024 * 1024) throw StateError('Request unavailable');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
  Future<void> _restore() async {
    if (!mounted) return;
    final epoch = ++_epoch, authorization = _currentAuthorization();
    setState(() {
      _launch = null; _agents = []; _preferenceKey = null;
      _authorization = authorization; _loading = authorization != null; _locked = false;
      _message = authorization == null ? 'Sign in to restore Nova Meeting Copilot.' : 'Restoring your agent…';
    });
    if (authorization == null) return;
    try {
      final me = await _read('/api/me', authorization);
      if (!_current(epoch, authorization)) return;
      final userId = me['user']?['id'];
      if (userId is! String || userId.isEmpty) throw StateError('User unavailable');
      if (!korlixMeetingCopilotEnterpriseEnabled(me['profile']?['tier'])) {
        setKorlixMeetingCopilotEnterpriseAccess(false);
        setState(() { _locked = true; _loading = false; });
        return;
      }
      final catalog = await _read('/api/live-convo/agents', authorization);
      if (!_current(epoch, authorization)) return;
      final rows = catalog['agents'];
      if (rows is! List) throw StateError('Agents unavailable');
      final agents = <Map<String, String>>[];
      for (final row in rows) {
        if (row is! Map || row['active'] != true) continue;
        final id = row['id'], name = row['name'];
        if (id is String && RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) &&
            name is String && name.trim().isNotEmpty && !agents.any((a) => a['id'] == id)) {
          agents.add({'id': id, 'name': name});
        }
      }
      final key = 'k135z.copilot.agent.v1.${widget.backendBaseUri.host}.$userId';
      String? saved;
      try { saved = (await SharedPreferences.getInstance()).getString(key); } catch (_) {}
      if (!_current(epoch, authorization)) return;
      final incoming = _incoming;
      final preferred = incoming?.current == true &&
          K135zZoomLaunch.authorization(incoming!.headersBuilder()) == authorization
          ? incoming.agentId : saved;
      _incoming = null;
      setState(() {
        _agents = agents; _preferenceKey = key; _loading = false;
        _message = agents.isEmpty ? 'No available agents. Open Agent Hub to create or enable Nova.'
          : 'Choose your agent once. Copilot will remember it for your next visit.';
      });
      final matches = agents.where((a) => a['id'] == preferred).toList();
      if (matches.length == 1) await _choose(matches.single['id']!);
      else if (preferred == null && agents.length == 1) await _choose(agents.single['id']!);
    } catch (_) {
      if (_current(epoch, authorization)) setState(() {
        _loading = false; _message = 'Could not restore your agent. Tap Retry connection.';
      });
    }
  }
  Future<void> _choose(String id) async {
    final authorization = _authorization, key = _preferenceKey, epoch = _epoch;
    if (authorization == null || key == null || !_current(epoch, authorization) ||
        !_agents.any((a) => a['id'] == id)) return;
    final launch = K135zZoomLaunch(agentId: id, backendBaseUri: widget.backendBaseUri,
      headersBuilder: widget.headersBuilder,
      isCurrent: () => _current(epoch, authorization) && _agents.any((a) => a['id'] == id));
    setKorlixMeetingCopilotEnterpriseAccess(true);
    setState(() => _launch = launch);
    try { await (await SharedPreferences.getInstance()).setString(key, id); } catch (_) {}
  }
  @override
  void dispose() {
    _epoch++;
    widget.authChanges.removeListener(_authChanged);
    if (widget.client == null) _client.close();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    if (_launch != null) return KorlixMeetingCopilotRoute(
      key: ObjectKey(_launch), zoomLaunch: _launch, zoomTransport: widget.zoomTransport);
    return Scaffold(backgroundColor: const Color(0xFF03131E), body: SafeArea(
      child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560),
          child: _locked ? const KorlixMeetingCopilotLockedPanel() : Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Nova Meeting Copilot', style: TextStyle(color: Colors.white,
                fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text(_message, style: const TextStyle(color: Color(0xFF9CB8CA))),
              const SizedBox(height: 18),
              if (_loading) const Center(child: CircularProgressIndicator())
              else ...[
                for (final agent in _agents)
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: FilledButton(
                    onPressed: () => _choose(agent['id']!), child: Text(agent['name']!))),
                OutlinedButton(onPressed: _restore, child: const Text('Retry connection')),
                TextButton(onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                  child: const Text('Return to Korlix')),
              ],
            ],
          ),
        ),
      )),
    ));
  }
}
