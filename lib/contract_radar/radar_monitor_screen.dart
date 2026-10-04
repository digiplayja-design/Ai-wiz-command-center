import 'package:flutter/material.dart';
import 'radar_client.dart';

Map<String, dynamic> radarMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Map<String, dynamic>> radarRows(dynamic value) =>
    value is List ? value.whereType<Map>().map(radarMap).toList() : [];

/// The monitor never starts an AI job. Enabling background checks is explicit.
class RadarMonitorScreen extends StatefulWidget {
  const RadarMonitorScreen({
    super.key,
    required this.client,
    required this.openLink,
    this.openOpportunity,
  });
  final RadarClient client;
  final Future<void> Function(String) openLink;
  final void Function(String)? openOpportunity;

  @override
  State<RadarMonitorScreen> createState() => _RadarMonitorScreenState();
}

class _RadarMonitorScreenState extends State<RadarMonitorScreen> {
  final _zone = TextEditingController(), _time = TextEditingController();
  Map<String, dynamic> _data = {};
  bool _loading = true, _busy = false, _enabled = false, _locked = false;
  String? _error, _message;
  Set<int> _days = {7, 3, 1};
  bool _unreadOnly = false, _haveSettings = false;
  final _savedNoticeIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _zone.dispose();
    _time.dispose();
    super.dispose();
  }

  Future<void> _load({bool restoreSettings = false}) async {
    try {
      final value = await widget.client.monitor();
      if (!mounted) return;
      final settings = radarMap(value['settings']);
      setState(() {
        _data = value;
        if (!_haveSettings || restoreSettings) {
          _enabled = settings['enabled'] == true;
          _zone.text = '${settings['timezone'] ?? 'America/New_York'}';
          final time = '${settings['digest_time'] ?? '09:00'}';
          _time.text = time.length >= 5 ? time.substring(0, 5) : '09:00';
          _haveSettings = true;
          _days = (settings['deadline_days'] as List? ?? [7, 3, 1])
              .whereType<num>()
              .map((v) => v.toInt())
              .toSet();
        }
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
        if (e is RadarException && e.status == 401) {
          _locked = true;
          _data = {};
          _zone.clear();
          _time.clear();
        }
      });
    }
  }

  Future<void> _act(
    Future<void> Function() action,
    String message, {
    bool restoreSettings = false,
  }) async {
    if (_busy || _locked) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
      if (!mounted) return;
      await _load(restoreSettings: restoreSettings);
      if (mounted && !_locked && _error == null) {
        setState(() => _message = message);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          if (e is RadarException && e.status == 401) {
            _locked = true;
            _data = {};
            _zone.clear();
            _time.clear();
          }
        });
      }
      if (mounted && !_locked) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String content, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _save() async {
    if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(_time.text.trim()) ||
        _zone.text.trim().isEmpty) {
      setState(
        () => _error =
            'Enter a time in HH:MM format and an IANA timezone, such as America/New_York.',
      );
      return;
    }
    final old = radarMap(_data['settings']);
    if (_enabled && old['enabled'] != true) {
      if (!await _confirm(
        'Turn on daily monitoring?',
        'KORLIX will check saved deadlines daily and add in-app reminders. When the SAM.gov connection is available, enabled saved searches and notice details are checked too. These checks use 0 AI credits. No emails or bids are sent. You can pause them here.',
        'Turn on',
      )) {
        return;
      }
      if (!mounted) return;
    }
    await _act(
      () async {
        await widget.client.saveMonitorSettings({
          'version': old['version'] ?? 0,
          'enabled': _enabled,
          'timezone': _zone.text.trim(),
          'digest_time': _time.text.trim(),
          'deadline_days': _days.toList()..sort((a, b) => b.compareTo(a)),
        });
      },
      _enabled
          ? 'Daily checks enabled. Alerts appear here after the next scheduled check.'
          : 'Automatic checks paused. Your saved searches remain available.',
      restoreSettings: true,
    );
  }

  Widget _card(String title, List<Widget> children, {IconData? icon}) {
    final color = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: color.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, color: color.primary),
              const SizedBox(height: 8),
            ],
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _alertDetails(Map<String, dynamic> alert) {
    final data = radarMap(alert['data']);
    final previous = radarMap(data['previous']),
        current = radarMap(data['current']);
    final changes = <String>[];
    if (previous['deadline'] != current['deadline']) {
      changes.add(
        'Deadline: ${previous['deadline'] ?? 'Not listed'} → ${current['deadline'] ?? 'Not listed'}',
      );
    }
    if (previous['title'] != current['title']) {
      changes.add(
        'Title updated: ${current['title'] ?? 'Check official notice'}',
      );
    }
    if (previous['active'] != current['active']) {
      changes.add(
        'Notice status: ${current['active'] == true ? 'Active' : 'Check official notice'}',
      );
    }
    final digest = alert['kind'] == 'digest' ? data : radarMap(data['digest']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final change in changes)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(change)),
        for (final search in radarRows(digest['searches']))
          Text(
            '${search['name'] ?? 'Saved search'}: ${search['count'] ?? 0} notices${search['truncated'] == true ? ' (more may be available)' : ''}',
          ),
        if (radarRows(digest['searches']).isNotEmpty)
          const Text(
            'Expand a saved search above to open and save its latest notices.',
          ),
      ],
    );
  }

  Widget _searchResults(Map<String, dynamic> search) {
    final result = radarMap(search['result']);
    final rows = radarRows(result['opportunities']);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('Latest notices · ${rows.length}'),
      children: [
        if (result['truncated'] == true)
          const Text(
            'More notices may be available. Narrow your keywords or check SAM.gov.',
          ),
        for (final notice in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${notice['title'] ?? 'SAM.gov notice'}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text('${notice['agency'] ?? ''}'),
                Text(
                  'Listed deadline: ${notice['deadline'] ?? 'Check official notice'}',
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () =>
                          widget.openLink('${notice['sourceUrl'] ?? ''}'),
                      child: const Text('Official notice'),
                    ),
                    if (notice['noticeId'] != null)
                      OutlinedButton(
                        onPressed:
                            _busy ||
                                _savedNoticeIds.contains(
                                  '${notice['noticeId']}',
                                )
                            ? null
                            : () => _act(() async {
                                await widget.client.saveDirectNotice(
                                  '${notice['noticeId']}',
                                );
                                if (mounted) {
                                  setState(
                                    () => _savedNoticeIds.add(
                                      '${notice['noticeId']}',
                                    ),
                                  );
                                }
                              }, 'Notice saved to your pipeline.'),
                        child: Text(
                          _savedNoticeIds.contains('${notice['noticeId']}')
                              ? 'Saved'
                              : 'Save notice',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = radarMap(_data['capabilities']);
    final ready = capabilities['monitor_ready'] == true;
    final directReady = capabilities['direct_sam_ready'] == true;
    final searches = radarRows(_data['searches']);
    final alerts = radarRows(_data['alerts']);
    final unread = alerts.where((a) => a['read_at'] == null).length;
    final visible = alerts
        .where((a) => !_unreadOnly || a['read_at'] == null)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Radar alerts'),
        actions: [
          IconButton(
            tooltip: 'Refresh alerts',
            onPressed: _busy || _locked ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _locked
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Your session changed. Reopen Contract Radar after signing in.',
                  ),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_error != null)
                        _card('Please check', [Text(_error!)]),
                      if (_message != null) _card('Updated', [Text(_message!)]),
                      if (_busy) const LinearProgressIndicator(),
                      _card('Daily checks, fewer missed opportunities', [
                        const Text(
                          'Get daily reminders for saved deadlines. When connected, SAM.gov searches also create a daily in-app digest and saved SAM notices are checked for changes. Always confirm the latest requirements with the buyer.',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '0 AI credits for monitoring. AI discovery and bid reviews keep their displayed credit cost and require your action.',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Keep up to 5 searches. Daily SAM.gov detail checks cover up to 10 saved notices; larger pipelines rotate across days.',
                        ),
                        if (!directReady) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Direct SAM.gov needs the site owner to connect a SAM.gov API key. Saved deadline reminders still work when monitoring is enabled. Use official web discovery for new opportunities meanwhile.',
                          ),
                        ],
                        SwitchListTile.adaptive(
                          key: const Key('radar-monitor-enabled'),
                          contentPadding: EdgeInsets.zero,
                          value: _enabled,
                          onChanged: _busy || (!ready && !_enabled)
                              ? null
                              : (v) => setState(() => _enabled = v),
                          title: const Text('Automatic daily checks'),
                          subtitle: Text(
                            _enabled
                                ? 'Save to apply your schedule.'
                                : 'Paused until you turn this on and save.',
                          ),
                        ),
                        TextField(
                          key: const Key('radar-monitor-timezone'),
                          controller: _zone,
                          enabled: !_busy,
                          decoration: const InputDecoration(
                            labelText: 'Timezone',
                            hintText: 'America/New_York',
                            helperText:
                                'Use an IANA timezone, for example America/Jamaica.',
                            helperMaxLines: 3,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          key: const Key('radar-monitor-time'),
                          controller: _time,
                          enabled: !_busy,
                          keyboardType: TextInputType.datetime,
                          decoration: const InputDecoration(
                            labelText: 'Daily check time (24-hour)',
                            hintText: '09:00',
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Remind me before a saved deadline'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final day in [14, 7, 3, 1])
                              FilterChip(
                                label: Text(
                                  '$day ${day == 1 ? 'day' : 'days'}',
                                ),
                                selected: _days.contains(day),
                                onSelected: _busy
                                    ? null
                                    : (v) => setState(() {
                                        if (v) {
                                          _days.add(day);
                                        } else {
                                          _days.remove(day);
                                        }
                                      }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          key: const Key('radar-monitor-save'),
                          onPressed: _busy ? null : _save,
                          icon: const Icon(Icons.schedule),
                          label: const Text('Save monitoring settings'),
                        ),
                      ], icon: Icons.radar),
                      _card('Saved searches · ${searches.length}', [
                        if (searches.isEmpty)
                          const Text(
                            'Use “Save this search” on Find. Your current keywords, NAICS and state are kept together.',
                          ),
                        for (final search in searches)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${search['name'] ?? search['query'] ?? 'Saved search'}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Text('${search['query'] ?? ''}'),
                                Text(
                                  [
                                    if ('${search['naics'] ?? ''}'.isNotEmpty)
                                      'NAICS ${search['naics']}',
                                    if ('${search['state'] ?? ''}'.isNotEmpty)
                                      '${search['state']}',
                                    search['enabled'] == true
                                        ? 'Included when monitoring is on'
                                        : 'Paused',
                                  ].join(' · '),
                                ),
                                if (radarRows(
                                  radarMap(search['result'])['opportunities'],
                                ).isNotEmpty)
                                  _searchResults(search),
                                if (search['last_checked_at'] != null)
                                  Text(
                                    'Last checked: ${search['last_checked_at']}',
                                  ),
                                if ('${search['last_error'] ?? ''}'.isNotEmpty)
                                  Text('${search['last_error']}'),
                                TextButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          if (!await _confirm(
                                            'Remove saved search?',
                                            'This stops monitoring this search. Your saved opportunities remain available.',
                                            'Remove',
                                          )) {
                                            return;
                                          }
                                          if (!mounted) return;
                                          await _act(
                                            () => widget.client.removeSearch(
                                              '${search['id']}',
                                            ),
                                            'Search removed.',
                                          );
                                        },
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Remove search'),
                                ),
                              ],
                            ),
                          ),
                      ], icon: Icons.bookmark_outline),
                      _card('Alerts · $unread unread', [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilterChip(
                              label: const Text('Unread only'),
                              selected: _unreadOnly,
                              onSelected: (v) =>
                                  setState(() => _unreadOnly = v),
                            ),
                            TextButton(
                              onPressed: _busy || unread == 0
                                  ? null
                                  : () => _act(
                                      widget.client.markAllAlertsRead,
                                      'All alerts marked read.',
                                    ),
                              child: const Text('Mark all read'),
                            ),
                            TextButton(
                              onPressed: _busy || alerts.isEmpty
                                  ? null
                                  : () async {
                                      if (!await _confirm(
                                        'Clear alert history?',
                                        'This removes these alerts. Your monitoring settings and saved opportunities remain.',
                                        'Clear',
                                      )) {
                                        return;
                                      }
                                      if (!mounted) return;
                                      await _act(
                                        widget.client.clearAlerts,
                                        'Alert history cleared.',
                                      );
                                    },
                              child: const Text('Clear history'),
                            ),
                          ],
                        ),
                        if (visible.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              'No alerts here yet. Scheduled checks appear here after monitoring is enabled.',
                            ),
                          ),
                        for (final alert in visible)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${alert['title'] ?? 'Contract update'}',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: alert['read_at'] == null
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text('${alert['message'] ?? ''}'),
                                _alertDetails(alert),
                                const SizedBox(height: 6),
                                Text(
                                  '${alert['created_at'] ?? ''}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    if ('${alert['source_url'] ?? ''}'
                                        .isNotEmpty)
                                      TextButton.icon(
                                        onPressed: () => widget.openLink(
                                          '${alert['source_url']}',
                                        ),
                                        icon: const Icon(Icons.open_in_new),
                                        label: const Text('Official notice'),
                                      ),
                                    if (radarMap(
                                              alert['data'],
                                            )['opportunity_id'] !=
                                            null &&
                                        widget.openOpportunity != null)
                                      TextButton(
                                        onPressed: () => widget.openOpportunity!(
                                          '${radarMap(alert['data'])['opportunity_id']}',
                                        ),
                                        child: const Text('Saved opportunity'),
                                      ),
                                    if (alert['read_at'] == null)
                                      TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _act(
                                                () =>
                                                    widget.client.markAlertRead(
                                                      '${alert['id']}',
                                                    ),
                                                'Alert marked read.',
                                              ),
                                        child: const Text('Mark read'),
                                      ),
                                  ],
                                ),
                                const Divider(),
                              ],
                            ),
                          ),
                      ], icon: Icons.notifications_active_outlined),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
