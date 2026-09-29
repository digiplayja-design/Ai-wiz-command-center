import 'dart:async';
import 'package:flutter/material.dart';
import 'bookkeeping_client.dart';
import 'bookkeeping_models.dart';
import 'bookkeeping_file_save.dart';
import 'receipt_dialogs.dart';
import 'bookkeeping_ui.dart';

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
  String? _error, _previewError, _scanKey;
  bool _previewBusy = false, _scanSubmitting = false;
  int _scanOperation = 0, _previewOperation = 0;
  bool _busy = true, _denied = false;
  final _downloadKey = GlobalKey();
  String get _path =>
      '/businesses/${widget.businessId}/receipts/${widget.receipt['id']}';
  bool get _current => mounted && !_denied && !widget.client.sessionChanged;
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
        _error = _previewError = _scanKey = null;
        _scanOperation++;
        _previewOperation++;
        _busy = _previewBusy = _scanSubmitting = false;
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
    unawaited(_loadPreview());
    await _refreshScan();
  }

  Future<void> _loadPreview() async {
    if (!_current ||
        _previewBusy ||
        (widget.receipt['preview_size'] as num? ?? 0) <= 0) {
      return;
    }
    final op = ++_previewOperation;
    setState(() {
      _previewBusy = true;
      _previewError = null;
      _clearImage();
    });
    try {
      final bytes = await widget.client.receiptBytes(
        widget.businessId,
        widget.receipt['id'] as String,
        preview: true,
      );
      if (_current && op == _previewOperation) {
        setState(() => _image = MemoryImage(bytes));
      }
    } catch (e) {
      if (_current && op == _previewOperation) {
        setState(() => _previewError = '$e');
      }
    } finally {
      if (_current && op == _previewOperation) {
        setState(() => _previewBusy = false);
      }
    }
  }

  void _acceptScan(Map<String, dynamic> data) {
    final value = data['scan'];
    if (!data.containsKey('scan') ||
        (value != null &&
            (value is! Map ||
                ![
                  'ready',
                  'scanning',
                  'failed',
                  'expired',
                ].contains(value['state']) ||
                (value['state'] == 'ready' && value['suggestions'] is! Map)))) {
      throw const BookkeepingException(
        'Scan status could not be read. Refresh its status before using suggested fields.',
      );
    }
    _scan = value == null ? null : Map<String, dynamic>.from(value as Map);
    if (_scan != null) _scanKey = null;
  }

  Future<Map<String, dynamic>> _status() => widget.client.request(
    'GET',
    '$_path/scan',
    query: _scanKey == null ? null : {'request_key': _scanKey!},
  );
  Future<void> _refreshScan() async {
    if (!_current || _scanSubmitting) return;
    final op = ++_scanOperation;
    setState(() {
      _busy = true;
      _error = null;
      _scan = null;
    });
    try {
      final data = await _status();
      if (_current && op == _scanOperation) setState(() => _acceptScan(data));
    } catch (e) {
      if (_current && op == _scanOperation) {
        setState(() {
          _scan = null;
          _error = '$e';
        });
      }
    } finally {
      if (_current && op == _scanOperation) setState(() => _busy = false);
    }
  }

  Future<void> _startScan() async {
    if (!_current || _busy) return;
    final confirmed = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReceiptConfirmation(
        title: _scanKey == null
            ? 'Scan receipt with AI?'
            : 'Retry the same scan?',
        message:
            'This sends the receipt to KORLIX’s AI provider to suggest a vendor, printed date, total and currency. A successful scan uses 1 generation credit. A saved result is reused without another provider call. Review every field before recording an entry.',
        button: _scanKey == null ? 'Scan now' : 'Retry same scan',
      ),
    );
    if (!_current || confirmed == null) return;
    final op = ++_scanOperation;
    _scanKey ??= bookkeepingRequestKey();
    setState(() {
      _busy = _scanSubmitting = true;
      _error = null;
      _scan = null;
    });
    try {
      final data = await widget.client.request(
        'POST',
        '$_path/scan',
        body: {'request_key': _scanKey, 'confirmed': true},
      );
      if (_current && op == _scanOperation) setState(() => _acceptScan(data));
    } catch (e) {
      if (!_current || op != _scanOperation) return;
      setState(() {
        _scan = null;
        _error = '$e';
      });
      try {
        final status = await _status();
        if (_current && op == _scanOperation) {
          setState(() {
            _acceptScan(status);
            if (_scan != null) _error = null;
          });
        }
      } catch (statusError) {
        if (_current && op == _scanOperation) {
          setState(() {
            _scan = null;
            _error = '$e\nStatus refresh: $statusError';
          });
        }
      }
    } finally {
      if (_current && op == _scanOperation) {
        setState(() {
          _busy = _scanSubmitting = false;
        });
      }
    }
  }

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await widget.client.receiptBytes(
        widget.businessId,
        widget.receipt['id'] as String,
      );
      if (!mounted || !_current) return;
      if (widget.onDownload != null) {
        await widget.onDownload!(bytes, widget.receipt['filename'] as String);
      } else {
        await saveBookkeepingFile(
          bytes,
          widget.receipt['filename'] as String,
          widget.receipt['mime_type'] as String,
          bookkeepingShareOrigin(_downloadKey, context),
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
    return BookkeepingDialog(
      client: widget.client,
      busy: _scanSubmitting,
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
                    if (_scanSubmitting)
                      const Text(
                        'Checking the submitted scan. Please keep this review open.',
                      ),
                    if (_previewBusy) const Text('Loading original preview…'),
                    if (_previewError != null) ...[
                      Text(_previewError!),
                      TextButton(
                        onPressed: _previewBusy ? null : _loadPreview,
                        child: const Text('Retry preview'),
                      ),
                    ],
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
                            errorBuilder: (_, _, _) => Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'The preview could not be displayed.',
                                ),
                                TextButton(
                                  onPressed: _loadPreview,
                                  child: const Text('Retry preview'),
                                ),
                              ],
                            ),
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
                                  (widget.scanning['available'] != true &&
                                      _scanKey == null)
                              ? null
                              : _startScan,
                          icon: const Icon(Icons.document_scanner_outlined),
                          label: Text(
                            _scanKey != null
                                ? 'Retry same scan'
                                : _scan == null
                                ? 'Scan receipt'
                                : 'Scan again',
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
          onPressed: _scanSubmitting ? null : () => Navigator.pop(context),
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
