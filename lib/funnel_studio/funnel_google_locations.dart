import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'funnel_client.dart';

const googleLocationCatalogVersion = 'google-locations-2026-08-12';
const googleLocationTypes = <String>{
  'City',
  'State',
  'Province',
  'Region',
  'Department',
  'Canton',
  'Governorate',
  'Prefecture',
  'Autonomous Community',
  'Division',
  'Territory',
  'Union Territory',
  'Okrug',
};
bool googleLocationValid(dynamic v) =>
    v is Map &&
    v.length == 4 &&
    v['id'] is String &&
    RegExp(r'^[1-9][0-9]{0,9}$').hasMatch(v['id']) &&
    v['name'] is String &&
    (v['name'] as String).runes.isNotEmpty &&
    (v['name'] as String).runes.length <= 300 &&
    (v['name'] as String).trim() == v['name'] &&
    !RegExp(r'[\x00-\x1f\x7f-\x9f<>\u2028\u2029]').hasMatch(v['name']) &&
    !(v['name'] as String).runes.any((r) => r >= 0xd800 && r <= 0xdfff) &&
    v['country'] is String &&
    RegExp(r'^[A-Z]{2}$').hasMatch(v['country']) &&
    googleLocationTypes.contains(v['type']);
bool googleLocationsValid(dynamic v) =>
    v is List &&
    v.length <= 20 &&
    v.every(googleLocationValid) &&
    v.map((x) => x['id']).toSet().length == v.length;
String googleLocationsSummary(Map a) => !a.containsKey('geo_locations')
    ? ''
    : 'City and region targets: ${(a['geo_locations'] as List).isEmpty ? '(none selected)' : (a['geo_locations'] as List).map((x) => '${x['name']} · ${x['type']} · Google ID ${x['id']}').join('; ')}';

List<Map<String, dynamic>> validateGoogleLocationSearch(
  Map<String, dynamic> r,
  String country,
  String query,
  String kind,
) {
  final rows = r['locations'];
  if (r['source'] != 'google_location_catalog' ||
      r['catalog_version'] != googleLocationCatalogVersion ||
      r['country'] != country ||
      r['query'] != query ||
      r['kind'] != kind ||
      r['more'] is! bool ||
      rows is! List ||
      rows.length > 30 ||
      rows.any(
        (x) =>
            !googleLocationValid(x) ||
            x['country'] != country ||
            (kind == 'city' && x['type'] != 'City') ||
            (kind == 'region' && x['type'] == 'City'),
      ) ||
      rows.map((x) => x['id']).toSet().length != rows.length) {
    throw const FunnelException(
      'The location results could not be verified. Search again.',
      503,
    );
  }
  return rows.map((x) => Map<String, dynamic>.from(x)).toList();
}

class GoogleLocationPicker extends StatefulWidget {
  const GoogleLocationPicker({
    super.key,
    required this.client,
    required this.path,
    required this.countries,
    required this.blocked,
    required this.active,
    this.scope,
  });
  final FunnelClient client;
  final String path;
  final List<Map> countries;
  final Set<String> blocked;
  final bool Function() active;
  final ValueListenable<int>? scope;
  @override
  State<GoogleLocationPicker> createState() => _GoogleLocationPickerState();
}

class _GoogleLocationPickerState extends State<GoogleLocationPicker> {
  final _query = TextEditingController();
  late String _country;
  String _kind = 'all';
  int _serial = 0;
  bool _busy = false, _closed = false, _searched = false, _more = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  @override
  void initState() {
    super.initState();
    _country = widget.countries.any((x) => x['code'] == 'US')
        ? 'US'
        : widget.countries.first['code'];
    widget.client.addAccessDeniedListener(_deny);
    widget.scope?.addListener(_deny);
  }

  void _deny() {
    if (!mounted) return;
    _closed = true;
    _reset();
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _reset() {
    _serial++;
    _rows = [];
    _busy = false;
    _searched = false;
    _more = false;
    _error = null;
  }

  @override
  void dispose() {
    _serial++;
    widget.client.removeAccessDeniedListener(_deny);
    widget.scope?.removeListener(_deny);
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_busy || _closed || !widget.active()) return;
    final q = _query.text.trim(), country = _country, kind = _kind;
    if (q.runes.length < 2 || q.runes.length > 80) {
      setState(() => _error = 'Enter 2–80 characters.');
      return;
    }
    final serial = ++_serial;
    setState(() {
      _busy = true;
      _rows = [];
      _error = null;
      _searched = false;
      _more = false;
    });
    try {
      final r = await widget.client.request(
        'GET',
        '${widget.path}/locations',
        query: {'q': q, 'country': country, 'kind': kind},
      );
      if (!mounted || serial != _serial || _closed || !widget.active()) return;
      final rows = validateGoogleLocationSearch(r, country, q, kind);
      setState(() {
        _rows = rows;
        _more = r['more'];
        _searched = true;
      });
    } catch (e) {
      if (!mounted || serial != _serial || _closed || !widget.active()) return;
      if (e is FunnelException && [401, 403, 404].contains(e.status)) {
        _deny();
        return;
      }
      setState(
        () => _error = e is FunnelException
            ? e.message
            : 'Location search failed. Try again.',
      );
    } finally {
      if (mounted && serial == _serial) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Find a city or region'),
    content: SizedBox(
      width: 560,
      height: math.min(520, MediaQuery.sizeOf(context).height * .62),
      child: _closed
          ? const Text(
              'This workspace is no longer available. Close this search.',
            )
          : ListView(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _country,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Search country',
                  ),
                  items: widget.countries
                      .map(
                        (x) => DropdownMenuItem<String>(
                          value: x['code'],
                          child: Text(
                            x['name'],
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _country = v;
                        _reset();
                      });
                    }
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: _kind,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Location type'),
                  items: const [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text('All types'),
                    ),
                    DropdownMenuItem(value: 'city', child: Text('Cities')),
                    DropdownMenuItem(
                      value: 'region',
                      child: Text('Regions'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _kind = v;
                        _reset();
                      });
                    }
                  },
                ),
                TextField(
                  key: const ValueKey('google-location-query'),
                  controller: _query,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'City or region name',
                    hintText: 'For example: Columbus, Ohio',
                  ),
                  onChanged: (_) => setState(_reset),
                  onSubmitted: (_) => unawaited(_search()),
                ),
                FilledButton(
                  onPressed: _busy ? null : _search,
                  child: Text(_busy ? 'Searching…' : 'Search locations'),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_more)
                  const Text(
                    'More matches exist. Add a state or region name to narrow your search.',
                  ),
                if (_searched && _rows.isEmpty)
                  const Text(
                    'No matching city or region in this reference list. Try another name or country.',
                  ),
                ..._rows.map((r) {
                  final selected = widget.blocked.contains(r['id']);
                  return ListTile(
                    key: ValueKey('google-location-${r['id']}'),
                    title: Text((r['name'] as String).replaceAll(',', ', ')),
                    subtitle: Text(
                      '${r['type']}${selected ? ' · Already selected' : ''}',
                    ),
                    enabled: !selected,
                    onTap: selected
                        ? null
                        : () {
                            if (!_closed && widget.active()) {
                              Navigator.pop(context, r);
                            }
                          },
                  );
                }),
                const Text(
                  'Google reference: August 2026. Availability and delivery eligibility need checking before launch.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close search'),
      ),
    ],
  );
}
