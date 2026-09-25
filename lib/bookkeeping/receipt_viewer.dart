import 'dart:async';
import 'package:flutter/material.dart';
import 'bookkeeping_client.dart';
import 'bookkeeping_models.dart';
import 'bookkeeping_file_save.dart';
import 'receipt_dialogs.dart';

class BookkeepingReceiptViewer extends StatefulWidget {
  const BookkeepingReceiptViewer({
    super.key,
    required this.client,
    required this.businessId,
    required this.receipt,
    required this.scanning,
    this.canCreate = false,
    this.onDownload,
  });
  final BookkeepingClient client;
  final String businessId;
  final Map<String, dynamic> receipt, scanning;
  final bool canCreate;
  final Future<void> Function(List<int> bytes, String filename)? onDownload;
  @override
  State<BookkeepingReceiptViewer> createState() =>
      _BookkeepingReceiptViewerState();
}

class _BookkeepingReceiptViewerState extends State<BookkeepingReceiptViewer> {
  MemoryImage? _image;
  Map<String, dynamic>? _scan;
  String? _error;
  bool _busy = true, _denied = false;
  final _downloadKey = GlobalKey();
  String get _path =>
      '/businesses/${widget.businessId}/receipts/${widget.receipt['id']}';
  bool get _current => mounted && !_denied;
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
    unawaited(_load());
  }

  void _clearImage() {
    final old = _image;
    _image = null;
    if (old != null) unawaited(old.evict());
  }

  void _deny() {
    if (mounted) {
      setState(() {
        _denied = true;
        _clearImage();
        _scan = null;
        _error = null;
      });
    }
  }

  @override
  void dispose() {
    widget.client.removeAccessDeniedListener(_deny);
    _clearImage();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if ((widget.receipt['preview_size'] as num? ?? 0) > 0) {
        final bytes = await widget.client.receiptBytes(
          widget.businessId,
          widget.receipt['id'] as String,
          preview: true,
        );
        if (!_current) return;
        _image = MemoryImage(bytes);
      }
      final data = await widget.client.request('GET', '$_path/scan');
      if (!_current) return;
      _scan = data['scan'] is Map
          ? Map<String, dynamic>.from(data['scan'] as Map)
          : null;
    } catch (e) {
      if (_current) _error = e.toString();
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _refreshScan() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await widget.client.request('GET', '$_path/scan');
      if (_current) {
        _scan = d['scan'] is Map
            ? Map<String, dynamic>.from(d['scan'] as Map)
            : null;
      }
    } catch (e) {
      if (_current) _error = e.toString();
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _startScan() async {
    final confirmed = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ReceiptConfirmation(
        title: 'Scan receipt with AI?',
        message:
            'This sends the receipt to KORLIX’s AI provider to suggest a vendor, printed date, total and currency. A successful scan uses 1 generation credit. Daily plan and receipt-attempt limits apply. Review every field before recording an entry.',
        button: 'Scan now',
      ),
    );
    if (!_current || confirmed == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await widget.client.request(
        'POST',
        '$_path/scan',
        body: {'request_key': bookkeepingRequestKey(), 'confirmed': true},
      );
      if (_current) {
        _scan = d['scan'] is Map
            ? Map<String, dynamic>.from(d['scan'] as Map)
            : null;
      }
    } catch (e) {
      if (_current) {
        _error = e.toString();
        try {
          final status = await widget.client.request('GET', '$_path/scan');
          if (_current) {
            _scan = status['scan'] is Map
                ? Map<String, dynamic>.from(status['scan'] as Map)
                : null;
          }
        } catch (_) {
          /* Keep the error; no provider retry. */
        }
      }
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    final box = _downloadKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await widget.client.receiptBytes(
        widget.businessId,
        widget.receipt['id'] as String,
      );
      if (!_current) return;
      if (widget.onDownload != null) {
        await widget.onDownload!(bytes, widget.receipt['filename'] as String);
      } else {
        await saveBookkeepingFile(
          bytes,
          widget.receipt['filename'] as String,
          widget.receipt['mime_type'] as String,
          origin,
        );
      }
    } catch (e) {
      if (_current) _error = e.toString();
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _scan?['state'] == 'ready' && _scan?['suggestions'] is Map
        ? Map<String, dynamic>.from(_scan!['suggestions'] as Map)
        : null;
    final created = DateTime.tryParse('${_scan?['created_at']}');
    final pending =
        _scan?['state'] == 'scanning' &&
        (created == null ||
            DateTime.now().toUtc().difference(created).inMinutes < 5);
    return AlertDialog(
      title: Text(
        _denied ? 'Session changed' : widget.receipt['filename'] as String,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: _denied
              ? const Text('Reopen Bookkeeping after signing in.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_busy) const LinearProgressIndicator(),
                    if (_image != null)
                      Container(
                        height: 300,
                        width: double.infinity,
                        color: const Color(0xffeef3f8),
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 5,
                          child: Image(
                            image: _image!,
                            fit: BoxFit.contain,
                            semanticLabel: 'Private receipt preview',
                          ),
                        ),
                      )
                    else if (widget.receipt['mime_type'] == 'application/pdf')
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Row(
                          children: [
                            Icon(Icons.picture_as_pdf_outlined, size: 42),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'PDF original preserved. Download the original to view every page.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: _downloadKey,
                          onPressed: _busy ? null : _download,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Download original'),
                        ),
                        FilledButton.icon(
                          onPressed:
                              _busy ||
                                  pending ||
                                  widget.scanning['available'] != true
                              ? null
                              : _startScan,
                          icon: const Icon(Icons.document_scanner_outlined),
                          label: Text(
                            _scan == null ? 'Scan receipt' : 'Scan again',
                          ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _refreshScan,
                          child: const Text('Refresh scan status'),
                        ),
                      ],
                    ),
                    if (widget.scanning['available'] != true)
                      Text(
                        widget.scanning['reason']?.toString() ??
                            'Scanning is unavailable.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'AI suggestions can be wrong. The printed date may differ from the payment date; an invoice alone does not prove payment.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: Color(0xff566a7f),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Color(0xff9c2525)),
                        ),
                      ),
                    if (pending)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Scan is in progress. Refresh its status shortly. A stalled attempt can be replaced after 5 minutes.',
                        ),
                      ),
                    if (['failed', 'expired'].contains(_scan?['state']))
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'This scan did not finish. Start a new scan explicitly or enter the details manually.',
                        ),
                      ),
                    if (data != null) ...[
                      const Divider(height: 28),
                      const Text(
                        'Suggested fields — verify before use',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _field('Vendor', data['vendor']),
                      _field('Printed date', data['document_date']),
                      _field('Total', data['total']),
                      _field('Currency', data['currency']),
                      _field('Document', data['document_type']),
                      _field('Payment status', data['payment_status']),
                      for (final warning in (data['warnings'] as List? ?? []))
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            warning.toString(),
                            style: const TextStyle(color: Color(0xff94530e)),
                          ),
                        ),
                      if (data['currency'] != 'USD')
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Text(
                            'Currency is not confirmed as USD. The amount will remain blank in the USD entry form.',
                          ),
                        ),
                      if (widget.canCreate)
                        Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              FilledButton(
                                onPressed: _busy
                                    ? null
                                    : () => Navigator.pop(context, {
                                        'kind': 'expense',
                                        'suggestions': data,
                                      }),
                                child: const Text('Use fields for expense'),
                              ),
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => Navigator.pop(context, {
                                        'kind': 'income',
                                        'suggestions': data,
                                      }),
                                child: const Text('Use fields for income'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
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

  Widget _field(String label, dynamic value) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text('$label: ${value ?? 'Not identified'}'),
  );
}
