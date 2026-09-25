import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'bookkeeping_client.dart';
import 'bookkeeping_forms.dart';
import 'bookkeeping_models.dart';
import 'receipt_dialogs.dart';
import 'receipt_picker.dart';
import 'receipt_viewer.dart';

class BookkeepingReceipts extends StatefulWidget {
  const BookkeepingReceipts({
    super.key,
    required this.client,
    required this.businessId,
    required this.businessName,
    required this.categories,
    this.entry,
    this.cashAccounts = const [],
    this.picker,
  });
  final BookkeepingClient client;
  final String businessId, businessName;
  final List<Map<String, dynamic>> categories, cashAccounts;
  final Map<String, dynamic>? entry;
  final Future<BookkeepingPickedReceipt?> Function({bool camera})? picker;
  @override
  State<BookkeepingReceipts> createState() => _BookkeepingReceiptsState();
}

class _BookkeepingReceiptsState extends State<BookkeepingReceipts> {
  List<Map<String, dynamic>> _receipts = [];
  Map<String, dynamic> _scanning = {};
  int _offset = 0, _total = 0, _used = 0;
  bool _busy = false, _denied = false;
  late bool _history = widget.entry != null;
  String? _error, _notice, _uploadKey;
  BookkeepingPickedReceipt? _picked;
  String get _base => '/businesses/${widget.businessId}/receipts';
  bool get _alive => mounted && !_denied && !widget.client.sessionChanged;
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
        _receipts = [];
        _picked = null;
        _error = null;
        _notice = null;
      });
    }
  }

  @override
  void dispose() {
    widget.client.removeAccessDeniedListener(_deny);
    _picked = null;
    super.dispose();
  }

  Future<T?> _dialog<T>(Widget child) => showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (_) => child,
  );
  Future<void> _load() async {
    if (!_alive) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.client.request(
        'GET',
        _base,
        query: {'offset': '$_offset'},
      );
      if (!_alive) return;
      final history = _history
          ? await widget.client.request(
              'GET',
              '/businesses/${widget.businessId}/entries/${widget.entry!['id']}/receipts',
            )
          : null;
      if (!_alive) return;
      setState(() {
        _receipts = bookkeepingRows((history ?? data)['receipts']);
        _scanning = Map<String, dynamic>.from(data['scanning'] as Map? ?? {});
        _total = data['total'] as int;
        _used = data['used_bytes'] as int;
      });
    } catch (e) {
      if (_alive) setState(() => _error = e.toString());
    } finally {
      if (_alive) setState(() => _busy = false);
    }
  }

  Future<void> _pick(bool camera) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final file = await (widget.picker ?? pickBookkeepingReceipt)(
        camera: camera,
      );
      if (_alive && file != null) {
        setState(() {
          _picked = file;
          _uploadKey = bookkeepingRequestKey();
        });
      }
    } catch (e) {
      if (_alive) setState(() => _error = e.toString());
    } finally {
      if (_alive) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    if (_picked == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.client.uploadReceipt(
        widget.businessId,
        _uploadKey!,
        _picked!.name,
        _picked!.bytes,
      );
      if (!_alive) return;
      final ready = (result['receipt'] as Map)['state'] == 'ready';
      setState(() {
        _notice = ready
            ? 'Original saved privately. Open it to scan or record an entry.'
            : 'Upload is still pending. Refresh shortly. If interrupted, retry the same file after 10 minutes.';
        if (ready) {
          _picked = null;
          _uploadKey = null;
        }
        _history = false;
        _offset = 0;
      });
    } catch (e) {
      if (_alive) {
        setState(() => _error = '$e Retry upload keeps the same request.');
      }
    } finally {
      if (_alive) {
        setState(() => _busy = false);
        await _loadPreservingError();
      }
    }
  }

  Future<void> _loadPreservingError() async {
    final error = _error;
    await _load();
    if (_alive && error != null) setState(() => _error = error);
  }

  Future<void> _mutate(
    String method,
    String path,
    Map<String, dynamic> body,
  ) async {
    if (!_alive) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.client.request(method, path, body: body);
    } catch (e) {
      if (_alive) setState(() => _error = e.toString());
    } finally {
      if (_alive) {
        setState(() => _busy = false);
        await _loadPreservingError();
      }
    }
  }

  Future<void> _entry(
    Map<String, dynamic> receipt,
    String kind, [
    Map<String, dynamic>? suggestions,
  ]) async {
    final saved = await _dialog<Map<String, dynamic>>(
      BookkeepingEntryDialog(
        client: widget.client,
        businessId: widget.businessId,
        categories: widget.categories,
        cashAccounts: widget.cashAccounts,
        kind: kind,
        receipt: receipt,
        suggestions: suggestions,
      ),
    );
    if (!mounted || !_alive) return;
    if (saved != null) {
      Navigator.pop(context, saved);
    } else {
      await _load();
    }
  }

  Future<void> _view(Map<String, dynamic> receipt) async {
    final result = await _dialog<Map<String, dynamic>>(
      BookkeepingReceiptViewer(
        client: widget.client,
        businessId: widget.businessId,
        receipt: receipt,
        scanning: _scanning,
        canCreate: !_history && receipt['link'] == null,
      ),
    );
    if (!_alive) return;
    if (result != null) {
      await _entry(
        receipt,
        result['kind'] as String,
        Map<String, dynamic>.from(result['suggestions'] as Map),
      );
    } else {
      await _load();
    }
  }

  Future<void> _link(Map<String, dynamic> receipt) async {
    final entry =
        widget.entry ??
        await _dialog<Map<String, dynamic>>(
          ReceiptEntryPicker(
            client: widget.client,
            businessId: widget.businessId,
          ),
        );
    if (!_alive || entry == null) return;
    final confirmed = await _dialog<Map<String, dynamic>>(
      ReceiptConfirmation(
        title: 'Attach original receipt?',
        message:
            '${receipt['filename']}\n\n${bookkeepingMoney(entry['amount_cents'])} · ${entry['entry_date']}\n${entry['purpose']}\n\nThe file and link history are retained with your records, including after a link correction.',
        button: 'Confirm attachment',
      ),
    );
    if (!_alive || confirmed == null) return;
    await _mutate('POST', '$_base/${receipt['id']}/link', {
      'confirmed': true,
      'entry_id': entry['id'],
    });
  }

  Future<void> _unlink(Map<String, dynamic> receipt) async {
    final body = await _dialog<Map<String, dynamic>>(
      ReceiptConfirmation(
        title: 'Correct receipt link',
        message:
            'Remove this current association? The original file and previous link stay in the history. You can attach it to the correct entry afterward.',
        button: 'Confirm correction',
        reason: true,
      ),
    );
    if (!_alive || body == null) return;
    await _mutate('POST', '$_base/${receipt['id']}/unlink', {
      ...body,
      'link_id': (receipt['link'] as Map)['id'],
    });
  }

  Future<void> _delete(Map<String, dynamic> receipt) async {
    final body = await _dialog<Map<String, dynamic>>(
      ReceiptConfirmation(
        title: 'Delete unused receipt?',
        message:
            '${receipt['filename']}\n\nThis removes the stored original and preview. Download a copy first if you need it. Files previously attached to entries are retained instead.',
        button: 'Delete receipt',
      ),
    );
    if (!_alive || body == null) return;
    await _mutate('DELETE', '$_base/${receipt['id']}', body);
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: SizedBox(
      width: 880,
      height: math.max(
        260,
        math.min(760, MediaQuery.sizeOf(context).height - 48),
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
                      Expanded(
                        child: Text(
                          _history ? 'Entry receipt history' : 'Receipt inbox',
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close receipts',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Text(
                    widget.businessName,
                    style: const TextStyle(color: Color(0xff566a7f)),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: [
                        if (widget.entry != null) ...[
                          Text(
                            '${bookkeepingMoney(widget.entry!['amount_cents'])} · ${widget.entry!['entry_date']}\n${widget.entry!['purpose']}',
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    setState(() {
                                      _history = !_history;
                                      _offset = 0;
                                    });
                                    unawaited(_load());
                                  },
                            child: Text(
                              _history
                                  ? 'Choose from receipt inbox'
                                  : 'Back to entry history',
                            ),
                          ),
                        ],
                        if (!_history) ...[
                          const Text(
                            'Save the original. Keep the story behind every entry.',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'JPG, PNG, WebP or PDF · Up to 8 MB per file · PDF up to 10 pages. AI scanning supports up to 3 PDF pages.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xff566a7f),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: _busy ? null : () => _pick(false),
                                icon: const Icon(Icons.upload_file),
                                label: const Text('Choose file'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy ? null : () => _pick(true),
                                icon: const Icon(Icons.add_a_photo_outlined),
                                label: const Text('Take photo'),
                              ),
                              TextButton.icon(
                                onPressed: _busy ? null : _load,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Refresh receipts'),
                              ),
                            ],
                          ),
                          if (_picked != null)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _picked!.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '${(_picked!.bytes.length / 1024).ceil()} KB · Ready to upload',
                                    ),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        FilledButton(
                                          onPressed: _busy ? null : _upload,
                                          child: const Text('Upload original'),
                                        ),
                                        TextButton(
                                          onPressed: _busy
                                              ? null
                                              : () => setState(() {
                                                  _picked = null;
                                                  _uploadKey = null;
                                                }),
                                          child: const Text('Clear selection'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            '${(_used / (1024 * 1024)).toStringAsFixed(1)} of 250 MB used across your businesses · 1,000 file limit',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const Divider(height: 24),
                        ],
                        if (_busy) const LinearProgressIndicator(),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Color(0xff9c2525)),
                            ),
                          ),
                        if (_notice != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(_notice!),
                          ),
                        if (_receipts.isEmpty && !_busy)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Text(
                              _history
                                  ? 'No receipt history for this entry yet.'
                                  : 'Your receipt inbox is ready. Add your first original above.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        for (final receipt in _receipts) _card(receipt),
                        if (!_history && _total > 30)
                          Wrap(
                            spacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '${_offset + 1}–${math.min(_offset + 30, _total)} of $_total',
                              ),
                              TextButton(
                                onPressed: _busy || _offset == 0
                                    ? null
                                    : () {
                                        _offset -= 30;
                                        unawaited(_load());
                                      },
                                child: const Text('Previous'),
                              ),
                              TextButton(
                                onPressed: _busy || _offset + 30 >= _total
                                    ? null
                                    : () {
                                        _offset += 30;
                                        unawaited(_load());
                                      },
                                child: const Text('Next page'),
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
  Widget _card(Map<String, dynamic> receipt) {
    final ready = receipt['state'] == 'ready';
    final link = receipt['link'] as Map?;
    final current = link != null && link['unlinked_at'] == null;
    final eligibleTarget =
        widget.entry == null ||
        (widget.entry!['kind'] != 'reversal' &&
            widget.entry!['reversed_by'] == null);
    final summary = receipt['linked_entry'] as Map?;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  receipt['mime_type'] == 'application/pdf'
                      ? Icons.picture_as_pdf_outlined
                      : Icons.receipt_long_outlined,
                  color: const Color(0xff087e98),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    receipt['filename'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${((receipt['byte_size'] as num) / 1024).ceil()} KB · ${receipt['state']}',
              style: const TextStyle(fontSize: 12),
            ),
            if (current)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  summary == null
                      ? 'Attached to this entry'
                      : 'Attached: ${bookkeepingMoney(summary['amount_cents'])} · ${summary['entry_date']}\n${summary['purpose']}',
                ),
              ),
            if (link?['unlinked_at'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Previous attachment · ${link!['unlink_reason']}'),
              ),
            if (!ready)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Refresh to check progress. An interrupted upload can be retried with the same file after 10 minutes.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (ready)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _view(receipt),
                    child: const Text('View / scan'),
                  ),
                if (ready && !_history && link == null) ...[
                  if (widget.entry == null) ...[
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _entry(receipt, 'expense'),
                      child: const Text('Record expense'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _entry(receipt, 'income'),
                      child: const Text('Record income'),
                    ),
                  ],
                  if (eligibleTarget)
                    TextButton(
                      onPressed: _busy ? null : () => _link(receipt),
                      child: Text(
                        widget.entry == null
                            ? 'Link existing entry'
                            : 'Attach to this entry',
                      ),
                    ),
                ],
                if (current)
                  TextButton(
                    onPressed: _busy ? null : () => _unlink(receipt),
                    child: const Text('Correct link'),
                  ),
                if (!_history && receipt['retained'] != true && link == null)
                  TextButton(
                    onPressed: _busy ? null : () => _delete(receipt),
                    child: Text(
                      receipt['state'] == 'deleting'
                          ? 'Retry deletion'
                          : 'Delete unused',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
