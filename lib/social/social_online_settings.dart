import 'dart:async';
import 'package:flutter/material.dart';
import '../sounds/korlix_sound_service.dart';
import 'social_client.dart';
import 'social_design.dart';

/// Per-account choices; only accepted connections can be enrolled by the server.
class SocialOnlineSettings extends StatefulWidget {
  const SocialOnlineSettings({super.key, required this.client, this.peer});
  final SocialClient client;
  final SocialMap? peer;
  @override
  State<SocialOnlineSettings> createState() => _SocialOnlineSettingsState();
}

class _SocialOnlineSettingsState extends State<SocialOnlineSettings> {
  final _search = TextEditingController();
  final Map<String, SocialMap> _watches = {};
  List<SocialMap> _peers = [];
  bool _loading = true, _more = false;
  String? _saving, _error;
  int _offset = 0, _generation = 0;
  bool get _active => mounted && widget.client.available;

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_access);
    unawaited(_load());
  }

  void _access() {
    if (!mounted || widget.client.available) return;
    _generation++;
    setState(() {
      _peers = [];
      _watches.clear();
      _search.clear();
    });
  }

  Future<void> _load({bool more = false}) async {
    if (!_active) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await widget.client.get('online_watches');
      final response = widget.peer == null
          ? await widget.client.get('connections', {
              'state': 'accepted',
              'q': _search.text.trim(),
              'offset': more ? _offset + 40 : 0,
            })
          : {
              'items': [widget.peer!],
            };
      if (!_active || generation != _generation) return;
      final peers = socialItems(response['items']);
      setState(() {
        _watches.clear();
        for (final row in socialItems(state['items'])) {
          _watches['${socialMap(row['peer'])['id']}'] = row;
        }
        _offset = more ? _offset + 40 : 0;
        _more = peers.length > 40;
        _peers = [if (more) ..._peers, ...peers.take(40)];
      });
    } catch (e) {
      if (_active && generation == _generation) setState(() => _error = '$e');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save(SocialMap peer, bool enabled, String sound) async {
    if (!_active || _saving != null) return;
    final id = '${peer['id']}';
    // Keep browser audio activation attached to the user's tap.
    unawaited(kKorlixSounds.activate());
    setState(() {
      _saving = id;
      _error = null;
    });
    try {
      await widget.client.post('online_watch_set', {
        'peer': id,
        'enabled': enabled,
        'sound': sound,
      });
      if (!_active) return;
      setState(() {
        if (enabled) {
          _watches[id] = {'peer': peer, 'sound': sound};
        } else {
          _watches.remove(id);
        }
      });
      if (!mounted) return;
      socialNotice(
        context,
        enabled ? 'Online alert saved.' : 'Online alert turned off.',
      );
    } catch (e) {
      if (_active) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_access);
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Online alerts')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: !_active
              ? const Center(
                  child: Text(
                    'Your session changed. Reopen Social after signing in.',
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text(
                      'Know when your people are here',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Choose up to 50 connections. Alerts start the next time they come online and respect their online visibility. You will get at most one alert per person every 15 minutes.',
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Bell and short ring play while KORLIX is open and sounds are enabled. For background alerts, also enable “Selected connections online” in Social notifications. Your phone controls background sounds, Silent mode and Focus.',
                    ),
                    const SizedBox(height: 18),
                    if (widget.peer == null)
                      TextField(
                        controller: _search,
                        enabled: !_loading && _saving == null,
                        decoration: InputDecoration(
                          labelText: 'Find a connection',
                          suffixIcon: IconButton(
                            tooltip: 'Search connections',
                            onPressed: _loading || _saving != null
                                ? null
                                : () => _load(),
                            icon: const Icon(Icons.search),
                          ),
                        ),
                        onSubmitted: (_) => _load(),
                      ),
                    if (_loading) const LinearProgressIndicator(),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (!_loading && _peers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No connections found. Follow someone and wait for them to accept, then choose an online alert here.',
                        ),
                      ),
                    for (final peer in _peers) ...[
                      const SizedBox(height: 14),
                      _choice(peer),
                    ],
                    if (_more)
                      TextButton(
                        onPressed: _loading || _saving != null
                            ? null
                            : () => _load(more: true),
                        child: const Text('Load more connections'),
                      ),
                    if (_error != null && !_loading)
                      TextButton(
                        onPressed: _saving != null ? null : () => _load(),
                        child: const Text('Refresh settings'),
                      ),
                  ],
                ),
        ),
      ),
    ),
  );

  Widget _choice(SocialMap peer) {
    final id = '${peer['id']}', watch = _watches['${peer['id']}'];
    final enabled = watch != null, sound = '${watch?['sound'] ?? 'bell'}';
    return SocialPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${peer['name'] ?? 'Connection'}',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          Text('@${peer['handle'] ?? ''}'),
          SwitchListTile.adaptive(
            key: ValueKey('online-watch-$id'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Notify me when online'),
            value: enabled,
            onChanged: _loading || _saving != null
                ? null
                : (value) => _save(peer, value, sound),
          ),
          if (enabled) ...[
            DropdownButtonFormField<String>(
              key: ValueKey('online-sound-$id-$sound'),
              initialValue: sound,
              decoration: const InputDecoration(labelText: 'Alert sound'),
              items: const [
                DropdownMenuItem(value: 'bell', child: Text('Bell')),
                DropdownMenuItem(value: 'ring', child: Text('Short ring')),
                DropdownMenuItem(value: 'silent', child: Text('Silent')),
              ],
              onChanged: _loading || _saving != null
                  ? null
                  : (value) {
                      if (value != null) unawaited(_save(peer, true, value));
                    },
            ),
            if (sound != 'silent')
              TextButton.icon(
                icon: const Icon(Icons.volume_up_outlined),
                label: const Text('Test sound'),
                onPressed: () async {
                  await kKorlixSounds.activate();
                  if (_active) {
                    await kKorlixSounds.play(
                      sound == 'ring' ? KorlixSound.ringtone : KorlixSound.bell,
                    );
                  }
                },
              ),
          ],
          if (_saving == id) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
