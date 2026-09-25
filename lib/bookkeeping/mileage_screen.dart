import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'bookkeeping_client.dart';
import 'bookkeeping_csv_save.dart';
import 'bookkeeping_models.dart';
import 'mileage_form.dart';
import 'mileage_models.dart';

class BookkeepingMileage extends StatefulWidget {
  const BookkeepingMileage({
    super.key,
    required this.client,
    required this.businessId,
    required this.businessName,
    this.onExport,
  });
  final BookkeepingClient client;
  final String businessId, businessName;
  final Future<void> Function(String csv, String filename)? onExport;
  @override
  State<BookkeepingMileage> createState() => _BookkeepingMileageState();
}

class _BookkeepingMileageState extends State<BookkeepingMileage> {
  final _period = TextEditingController(
        text: bookkeepingDate(DateTime.now()).substring(0, 7),
      ),
      _vehicle = TextEditingController();
  final _exportKey = GlobalKey();
  String _selectedPeriod = bookkeepingDate(DateTime.now()).substring(0, 7),
      _selectedVehicle = '';
  Map<String, dynamic>? _data;
  int _offset = 0;
  bool _busy = false, _denied = false;
  String? _error;
  bool get _alive => mounted && !_denied;
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
    unawaited(_load());
  }

  void _deny() {
    if (mounted) {
      setState(() {
        _denied = true;
        _data = null;
        _error = null;
        _period.clear();
        _vehicle.clear();
      });
    }
  }

  @override
  void dispose() {
    widget.client.removeAccessDeniedListener(_deny);
    _period.dispose();
    _vehicle.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_alive) return;
    setState(() {
      _busy = true;
      _error = null;
      _data = null;
    });
    try {
      final d = await widget.client.request(
        'GET',
        '/businesses/${widget.businessId}/mileage',
        query: {
          'period': _selectedPeriod,
          'vehicle': _selectedVehicle,
          'offset': '$_offset',
        },
      );
      if (_alive) setState(() => _data = d);
    } catch (e) {
      if (_alive) setState(() => _error = e.toString());
    } finally {
      if (_alive) setState(() => _busy = false);
    }
  }

  void _apply() {
    if (!RegExp(r'^20\d\d(?:-(?:0[1-9]|1[0-2]))?$').hasMatch(_period.text) ||
        _vehicle.text.trim().length > 80) {
      setState(
        () => _error =
            'Use YYYY or YYYY-MM (2000–2099), and a vehicle nickname up to 80 characters.',
      );
      return;
    }
    _selectedPeriod = _period.text;
    _selectedVehicle = _vehicle.text.trim();
    _offset = 0;
    unawaited(_load());
  }

  Future<void> _entry({
    Map<String, dynamic>? trip,
    bool voidOnly = false,
  }) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MileageForm(
        client: widget.client,
        businessId: widget.businessId,
        original: trip,
        voidOnly: voidOnly,
      ),
    );
    if (!_alive) return;
    if (result != null) {
      _selectedPeriod = (result['trip_date'] as String).substring(
        0,
        _selectedPeriod.length,
      );
      _period.text = _selectedPeriod;
      _selectedVehicle = '';
      _vehicle.clear();
      _offset = 0;
    }
    await _load();
  }

  Future<void> _export() async {
    final box = _exportKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await widget.client.request(
        'GET',
        '/businesses/${widget.businessId}/mileage/export',
        query: {'period': _selectedPeriod, 'vehicle': _selectedVehicle},
      );
      if (!_alive) return;
      if (widget.onExport != null) {
        await widget.onExport!(d['csv'] as String, d['filename'] as String);
      } else {
        await saveBookkeepingCsv(
          d['csv'] as String,
          d['filename'] as String,
          origin,
        );
      }
    } catch (e) {
      if (_alive) setState(() => _error = e.toString());
    } finally {
      if (_alive) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = bookkeepingRows(_data?['trips']);
    final summary = _data?['summary'] as Map?;
    final count = _data?['record_count'] as int? ?? 0;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 960,
        height: math.max(
          260,
          math.min(800, MediaQuery.sizeOf(context).height - 48),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _denied
              ? const Center(
                  child: Text(
                    'Session changed. Reopen Bookkeeping after signing in.',
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Business mileage',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close mileage',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    Text(
                      widget.businessName,
                      style: const TextStyle(color: Color(0xff566a7f)),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: ListView(
                        children: [
                          const Text(
                            'Every trip has a purpose. Keep yours on record.',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Manual business-trip log · Miles only. No GPS tracking, tax rate, reimbursement or cash expense is calculated.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xff566a7f),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton.icon(
                                onPressed: _busy ? null : () => _entry(),
                                icon: const Icon(Icons.add_road),
                                label: const Text('Record trip'),
                              ),
                              OutlinedButton.icon(
                                key: _exportKey,
                                onPressed: _busy || _data == null
                                    ? null
                                    : _export,
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('Export mileage'),
                              ),
                              TextButton.icon(
                                onPressed: _busy ? null : _load,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Refresh mileage'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: 220,
                                child: TextField(
                                  controller: _period,
                                  enabled: !_busy,
                                  decoration: const InputDecoration(
                                    labelText: 'Period (YYYY or YYYY-MM)',
                                  ),
                                  maxLength: 7,
                                ),
                              ),
                              SizedBox(
                                width: 260,
                                child: TextField(
                                  controller: _vehicle,
                                  enabled: !_busy,
                                  decoration: const InputDecoration(
                                    labelText: 'Vehicle filter (optional)',
                                    helperText:
                                        'Exact nickname; blank for all.',
                                  ),
                                  maxLength: 80,
                                ),
                              ),
                              OutlinedButton(
                                onPressed: _busy ? null : _apply,
                                child: const Text('Apply filters'),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () {
                                        _period.text = _selectedPeriod
                                            .substring(0, 4);
                                        _apply();
                                      },
                                child: const Text('Whole year'),
                              ),
                            ],
                          ),
                          if ((_data?['vehicles'] as List? ?? []).isNotEmpty)
                            Text(
                              'Recorded vehicles: ${(_data!['vehicles'] as List).join(', ')}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xff566a7f),
                              ),
                            ),
                          const SizedBox(height: 16),
                          if (_busy) const LinearProgressIndicator(),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xff9c2525),
                                ),
                              ),
                            ),
                          if (summary != null) ...[
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xffe6f3f6),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${mileageDecimal(summary['distance_tenths'])} miles',
                                    style: const TextStyle(
                                      fontSize: 29,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xff087e98),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${summary['trip_count']} included trips · ${summary['excluded_count']} excluded records',
                                  ),
                                  Text(
                                    '$_selectedPeriod · ${_selectedVehicle.isEmpty ? 'All vehicles' : _selectedVehicle}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Trip history',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Corrected and voided records remain visible and contribute zero to the total.',
                              style: TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (rows.isEmpty && !_busy && _data != null)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'No trips in this period. Record a trip or change the filters.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          for (final trip in rows) _card(trip),
                          if (count > 50)
                            Wrap(
                              spacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '${_offset + 1}–${math.min(_offset + 50, count)} of $count records',
                                ),
                                TextButton(
                                  onPressed: _busy || _offset == 0
                                      ? null
                                      : () {
                                          _offset -= 50;
                                          unawaited(_load());
                                        },
                                  child: const Text('Previous trips'),
                                ),
                                TextButton(
                                  onPressed: _busy || _offset + 50 >= count
                                      ? null
                                      : () {
                                          _offset += 50;
                                          unawaited(_load());
                                        },
                                  child: const Text('Next trips'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> trip) {
    final excluded = trip['void_id'] != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${trip['trip_date']} · ${trip['vehicle']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '${mileageDecimal(trip['distance_tenths'])} mi${excluded ? ' · Excluded' : ''}',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: excluded
                    ? const Color(0xff566a7f)
                    : const Color(0xff087e98),
              ),
            ),
            const SizedBox(height: 8),
            Text('${trip['origin']} → ${trip['destination']}'),
            Text(trip['purpose'] as String),
            if (trip['method'] == 'odometer')
              Text(
                'Odometer ${mileageDecimal(trip['start_tenths'])} → ${mileageDecimal(trip['end_tenths'])} mi',
                style: const TextStyle(fontSize: 12),
              ),
            if (trip['correction_of'] != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Replacement for an earlier record',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            if (excluded)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${trip['replacement_id'] == null ? 'Voided' : 'Corrected'}: ${trip['void_reason']}',
                ),
              )
            else
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => _entry(trip: trip),
                    child: const Text('Correct trip'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _entry(trip: trip, voidOnly: true),
                    child: const Text('Void trip'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
