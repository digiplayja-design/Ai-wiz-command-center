import 'package:flutter/material.dart';
import 'bookkeeping_client.dart';
import 'bookkeeping_models.dart';
import 'mileage_models.dart';

class MileageForm extends StatefulWidget {
  const MileageForm({
    super.key,
    required this.client,
    required this.businessId,
    this.original,
    this.voidOnly = false,
  });
  final BookkeepingClient client;
  final String businessId;
  final Map<String, dynamic>? original;
  final bool voidOnly;
  @override
  State<MileageForm> createState() => _MileageFormState();
}

class _MileageFormState extends State<MileageForm> {
  final _form = GlobalKey<FormState>();
  late final _fields = tripFields(
    widget.original,
  ).map((k, v) => MapEntry(k, TextEditingController(text: v)));
  late String _method = widget.original?['method'] as String? ?? 'miles';
  Map<String, dynamic>? _review;
  bool _busy = false, _attempted = false, _denied = false;
  String? _error;
  String get _title => widget.voidOnly
      ? 'Void trip'
      : widget.original != null
      ? 'Correct trip'
      : 'Record trip';
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
  }

  void _deny() {
    if (mounted) {
      setState(() {
        _denied = true;
        _review = null;
        _error = null;
        for (final c in _fields.values) {
          c.clear();
        }
      });
    }
  }

  @override
  void dispose() {
    widget.client.removeAccessDeniedListener(_deny);
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String value(String key) => _fields[key]!.text.trim();
  void _prepare() {
    if (!_form.currentState!.validate()) return;
    if (!widget.voidOnly && _method == 'odometer') {
      final start = mileageTenths(value('odometer_start'), odometer: true),
          end = mileageTenths(value('odometer_end'), odometer: true);
      if (start == null ||
          end == null ||
          end - start < BigInt.one ||
          end - start > BigInt.from(99999)) {
        setState(
          () => _error =
              'Ending odometer must be higher; trip distance must be 0.1–9,999.9 miles.',
        );
        return;
      }
    }
    setState(() {
      _error = null;
      _review = {
        'request_key': bookkeepingRequestKey(),
        'confirmed': true,
        if (widget.original != null) 'reason': value('reason'),
        if (!widget.voidOnly) ...{
          for (final name in [
            'trip_date',
            'vehicle',
            'origin',
            'destination',
            'purpose',
          ])
            name: value(name),
          'method': _method,
          if (_method == 'miles')
            'miles': value('miles')
          else ...{
            'odometer_start': value('odometer_start'),
            'odometer_end': value('odometer_end'),
          },
        },
      };
    });
  }

  Future<void> _save() async {
    if (_busy || _denied || _review == null) return;
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
    });
    try {
      final suffix = widget.original == null
          ? ''
          : '/${widget.original!['id']}/${widget.voidOnly ? 'void' : 'correct'}';
      final d = await widget.client.request(
        'POST',
        '/businesses/${widget.businessId}/mileage$suffix',
        body: _review,
      );
      if (!mounted || _denied) return;
      Navigator.pop(context, {
        'trip_date': widget.voidOnly
            ? widget.original!['trip_date']
            : (d['trip'] as Map)['trip_date'],
      });
    } catch (e) {
      if (mounted && !_denied) setState(() => _error = e.toString());
    } finally {
      if (mounted && !_denied) setState(() => _busy = false);
    }
  }

  Widget _text(String key, String label, {int? max, bool number = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          controller: _fields[key],
          decoration: InputDecoration(labelText: label),
          maxLength: max,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : null,
          validator: (v) => key == 'trip_date'
              ? validateBookkeepingDate(v)
              : number
              ? validateMileage(v, odometer: key != 'miles')
              : validateMileageText(v, max!),
        ),
      );
  @override
  Widget build(BuildContext context) {
    final distance = widget.voidOnly
        ? widget.original!['distance_tenths']
        : _method == 'miles'
        ? mileageTenths(value('miles'))
        : (mileageTenths(value('odometer_end'), odometer: true) ??
                  BigInt.zero) -
              (mileageTenths(value('odometer_start'), odometer: true) ??
                  BigInt.zero);
    return AlertDialog(
      title: Text(
        _review == null
            ? _title
            : 'Review ${widget.voidOnly
                  ? 'exclusion'
                  : widget.original != null
                  ? 'correction'
                  : 'trip'}',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: _denied
              ? const Text('Session changed. Reopen Bookkeeping.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_review != null) ...[
                      Text(
                        '${mileageDecimal(distance)} miles',
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!widget.voidOnly) ...[
                        Text('Trip date: ${value('trip_date')}'),
                        Text('Vehicle: ${value('vehicle')}'),
                        Text('${value('origin')} → ${value('destination')}'),
                        Text('Business purpose: ${value('purpose')}'),
                        if (_method == 'odometer')
                          Text(
                            'Odometer: ${value('odometer_start')} → ${value('odometer_end')} mi',
                          ),
                      ],
                      if (widget.original != null) ...[
                        const SizedBox(height: 12),
                        Text('Reason: ${value('reason')}'),
                        Text(
                          'Original: ${widget.original!['trip_date']} · ${mileageDecimal(widget.original!['distance_tenths'])} mi · ${widget.original!['vehicle']}',
                        ),
                      ],
                      const SizedBox(height: 18),
                      Text(
                        widget.voidOnly
                            ? 'The original stays in history and is excluded from mileage totals. No cash entry is changed.'
                            : widget.original != null
                            ? 'The replacement and exclusion of the original save together. Date or vehicle changes can change totals in both periods. History is preserved.'
                            : 'Confirm the actual trip date, route, business purpose and miles driven. This saves a distance record; no cash expense or deduction is calculated.',
                      ),
                    ] else
                      Form(
                        key: _form,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.voidOnly) ...[
                              Text(
                                '${widget.original!['trip_date']} · ${mileageDecimal(widget.original!['distance_tenths'])} miles',
                              ),
                              Text(
                                '${widget.original!['origin']} → ${widget.original!['destination']}',
                              ),
                              const SizedBox(height: 14),
                            ] else ...[
                              const Text(
                                'Record an actual business trip. Use a distinct, consistent vehicle nickname so your totals stay together.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xff566a7f),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _text('trip_date', 'Trip date (YYYY-MM-DD)'),
                              _text('vehicle', 'Vehicle nickname', max: 80),
                              _text('origin', 'Starting place', max: 160),
                              _text('destination', 'Destination', max: 160),
                              _text('purpose', 'Business purpose', max: 500),
                              DropdownButtonFormField<String>(
                                initialValue: _method,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Distance method',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'miles',
                                    child: Text('Miles driven'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'odometer',
                                    child: Text('Odometer readings'),
                                  ),
                                ],
                                onChanged: (v) => setState(() {
                                  _method = v!;
                                  _error = null;
                                }),
                              ),
                              const SizedBox(height: 16),
                              if (_method == 'miles')
                                _text('miles', 'Miles driven', number: true)
                              else ...[
                                _text(
                                  'odometer_start',
                                  'Starting odometer (miles)',
                                  number: true,
                                ),
                                _text(
                                  'odometer_end',
                                  'Ending odometer (miles)',
                                  number: true,
                                ),
                              ],
                            ],
                            if (widget.original != null)
                              _text(
                                'reason',
                                'Reason for correction',
                                max: 500,
                              ),
                          ],
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          '$_error${_attempted ? ' Retry uses the same reviewed request. You may also close and refresh.' : ''}',
                          style: const TextStyle(color: Color(0xff9c2525)),
                        ),
                      ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (!_denied && _review != null && !_attempted)
          TextButton(
            onPressed: () => setState(() => _review = null),
            child: const Text('Edit'),
          ),
        if (!_denied)
          FilledButton(
            onPressed: _busy
                ? null
                : _review == null
                ? _prepare
                : _save,
            child: Text(
              _busy
                  ? 'Saving…'
                  : _review == null
                  ? 'Review trip'
                  : _attempted
                  ? 'Retry same save'
                  : widget.voidOnly
                  ? 'Confirm exclusion'
                  : 'Confirm and save trip',
            ),
          ),
      ],
    );
  }
}
