import 'dart:async';
import 'package:flutter/material.dart';
import 'bookkeeping_client.dart';
import 'bookkeeping_models.dart';

class ReceiptConfirmation extends StatefulWidget {
  const ReceiptConfirmation({
    super.key,
    required this.title,
    required this.message,
    required this.button,
    this.reason = false,
  });
  final String title, message, button;
  final bool reason;
  @override
  State<ReceiptConfirmation> createState() => _ReceiptConfirmationState();
}

class _ReceiptConfirmationState extends State<ReceiptConfirmation> {
  final _form = GlobalKey<FormState>();
  String _reason = '';
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.message),
              if (widget.reason) ...[
                const SizedBox(height: 16),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Reason for correction',
                  ),
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  onChanged: (v) => _reason = v,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter a reason.' : null,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, {
              'confirmed': true,
              'reason': _reason.trim(),
            });
          }
        },
        child: Text(widget.button),
      ),
    ],
  );
}

class ReceiptEntryPicker extends StatefulWidget {
  const ReceiptEntryPicker({
    super.key,
    required this.client,
    required this.businessId,
  });
  final BookkeepingClient client;
  final String businessId;
  @override
  State<ReceiptEntryPicker> createState() => _ReceiptEntryPickerState();
}

class _ReceiptEntryPickerState extends State<ReceiptEntryPicker> {
  late final _month = TextEditingController(
    text: bookkeepingDate(DateTime.now()).substring(0, 7),
  );
  List<Map<String, dynamic>> _entries = [];
  int _offset = 0, _total = 0;
  bool _busy = false, _denied = false;
  String? _error;
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
        _entries = [];
        _error = null;
      });
    }
  }

  @override
  void dispose() {
    widget.client.removeAccessDeniedListener(_deny);
    _month.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_denied) return;
    if (!RegExp(r'^20\d\d-(0[1-9]|1[0-2])$').hasMatch(_month.text)) {
      setState(() => _error = 'Use YYYY-MM, for example 2027-01.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _entries = [];
    });
    try {
      final d = await widget.client.request(
        'GET',
        '/businesses/${widget.businessId}/overview',
        query: {'month': _month.text, 'offset': '$_offset'},
      );
      if (mounted && !_denied) {
        setState(() {
          _total = d['entry_count'] as int;
          _entries = bookkeepingRows(d['entries'])
              .where((e) => e['kind'] != 'reversal' && e['reversed_by'] == null)
              .toList();
        });
      }
    } catch (e) {
      if (mounted && !_denied) setState(() => _error = e.toString());
    } finally {
      if (mounted && !_denied) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose an existing entry'),
    content: SizedBox(
      width: 600,
      height: 420,
      child: _denied
          ? const Text('Session changed.')
          : Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _month,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: 'Month (YYYY-MM)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              _offset = 0;
                              unawaited(_load());
                            },
                      child: const Text('Find entries'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                Expanded(
                  child: _entries.isEmpty && !_busy
                      ? const Center(
                          child: Text(
                            'No eligible entries on this page. Try another month or page.',
                          ),
                        )
                      : ListView(
                          children: _entries
                              .map(
                                (e) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    '${bookkeepingMoney(e['amount_cents'])} · ${e['kind']}',
                                  ),
                                  subtitle: Text(
                                    '${e['entry_date']}\n${e['purpose']}',
                                  ),
                                  isThreeLine: true,
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: _busy
                                      ? null
                                      : () => Navigator.pop(context, e),
                                ),
                              )
                              .toList(),
                        ),
                ),
                if (_total > 50)
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _busy || _offset == 0
                            ? null
                            : () {
                                _offset -= 50;
                                unawaited(_load());
                              },
                        child: const Text('Previous'),
                      ),
                      TextButton(
                        onPressed: _busy || _offset + 50 >= _total
                            ? null
                            : () {
                                _offset += 50;
                                unawaited(_load());
                              },
                        child: const Text('Next page'),
                      ),
                    ],
                  ),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
