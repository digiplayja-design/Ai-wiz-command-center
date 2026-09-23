import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'funnel_client.dart';

const metaLocationCategoryNotice =
    'Cities and regions can be saved for undecided or special categories, but preparation review stays incomplete until supported category targeting is available.';
String metaLocationIdentity(Map v) => '${v['type']}:${v['key']}';
bool _locationText(dynamic v, int min) =>
    v is String &&
    v.runes.length >= min &&
    v.runes.length <= 200 &&
    v.trim() == v &&
    !RegExp(r'[\x00-\x1f\x7f-\x9f<>\u2028\u2029]').hasMatch(v) &&
    !v.runes.any((r) => r >= 0xd800 && r <= 0xdfff);
bool metaLocationValid(dynamic v) =>
    v is Map &&
    v.length == 5 &&
    v['key'] is String &&
    RegExp(r'^[0-9]{1,40}$').hasMatch(v['key']) &&
    _locationText(v['name'], 1) &&
    _locationText(v['region'], 0) &&
    v['country'] is String &&
    RegExp(r'^[A-Z]{2}$').hasMatch(v['country']) &&
    ['city', 'region'].contains(v['type']);
bool metaLocationsValid(dynamic v) =>
    v is List &&
    v.length <= 20 &&
    v.every(metaLocationValid) &&
    v.map((x) => metaLocationIdentity(x)).toSet().length == v.length;
bool metaLocationProofShape(dynamic v) =>
    v is String && RegExp(r'^\d{13}\.[a-f0-9]{64}$').hasMatch(v);
String metaLocationsSummary(Map a) => !a.containsKey('geo_locations')
    ? ''
    : 'Meta city and region targets: ${(a['geo_locations'] as List).isEmpty ? '(none selected)' : (a['geo_locations'] as List).map((x) => "${x['name']}${x['region'] == '' ? '' : ', ${x['region']}'} (${x['country']}) · ${x['type']} · Meta key ${x['key']}").join('; ')}';
List<Map<String, dynamic>> validateMetaLocationSearch(
  Map<String, dynamic> r,
  String country,
  String query,
  String kind,
  String fingerprint,
) {
  final rows = r['locations'];
  if (r['source'] != 'meta_location_search' ||
      r['country'] != country ||
      r['query'] != query ||
      r['kind'] != kind ||
      r['fingerprint'] != fingerprint ||
      r['more'] is! bool ||
      rows is! List ||
      rows.length > 30) {
    throw const FunnelException(
      'The Meta location results could not be verified. Search again.',
      503,
    );
  }
  final ids = <String>{};
  for (final x in rows) {
    if (x is! Map || !metaLocationProofShape(x['proof'])) {
      throw const FunnelException(
        'The Meta location result could not be verified. Search again.',
        503,
      );
    }
    final row = Map<String, dynamic>.from(x)..remove('proof');
    if (!metaLocationValid(row) ||
        row['country'] != country ||
        (kind != 'all' && row['type'] != kind) ||
        !ids.add(metaLocationIdentity(row))) {
      throw const FunnelException(
        'Meta returned inconsistent location results. Search again.',
        503,
      );
    }
  }
  return rows.map((x) => Map<String, dynamic>.from(x)).toList();
}

class MetaLocationPicker extends StatefulWidget {
  const MetaLocationPicker({
    super.key,
    required this.client,
    required this.path,
    required this.fingerprint,
    required this.countries,
    required this.blocked,
    required this.active,
    this.scope,
  });
  final FunnelClient client;
  final String path;
  final String fingerprint;
  final List<Map> countries;
  final Set<String> blocked;
  final bool Function() active;
  final ValueListenable<int>? scope;
  @override
  State<MetaLocationPicker> createState() => _MetaLocationPickerState();
}

class _MetaLocationPickerState extends State<MetaLocationPicker> {
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
        query: {
          'q': q,
          'country': country,
          'kind': kind,
          'fingerprint': widget.fingerprint,
        },
      );
      if (!mounted || serial != _serial || _closed || !widget.active()) return;
      final rows = validateMetaLocationSearch(
        r,
        country,
        q,
        kind,
        widget.fingerprint,
      );
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
    title: const Text('Find a Meta city or region'),
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
                    DropdownMenuItem(value: 'all', child: Text('All types')),
                    DropdownMenuItem(value: 'city', child: Text('Cities')),
                    DropdownMenuItem(value: 'region', child: Text('Regions')),
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
                  key: const ValueKey('meta-location-query'),
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
                    'More matches exist. Use a more specific name or location type.',
                  ),
                if (_searched && _rows.isEmpty)
                  const Text(
                    'Meta returned no matching city or region. Try another name or country.',
                  ),
                ..._rows.map((r) {
                  final selected = widget.blocked.contains(
                    metaLocationIdentity(r),
                  );
                  return ListTile(
                    key: ValueKey('meta-location-${metaLocationIdentity(r)}'),
                    title: Text((r['name'] as String).replaceAll(',', ', ')),
                    subtitle: Text(
                      "${r['region'] == '' ? '' : '${r['region']} · '}${r['country']} · ${r['type']}${selected ? ' · Already selected' : ''}",
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
                  'Search reads Meta location names using your connected account. It does not launch ads. Save new choices within 30 minutes; delivery and category eligibility need checking before launch.',
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
