import 'package:flutter/material.dart';

import '../bookkeeping/bookkeeping_models.dart';
import '../bookkeeping/receipt_picker.dart';
import 'receipt_wiz_client.dart';
import 'receipt_wiz_style.dart';

class ReceiptImportItem {
  ReceiptImportItem(BookkeepingPickedReceipt file)
    : file = file,
      name = file.name,
      requestKey = bookkeepingRequestKey();
  BookkeepingPickedReceipt? file;
  final String name, requestKey;
  String status = 'Ready to upload';
  bool saved = false, reused = false;
}

/// Sequential imports keep memory and scan requests bounded. A failed upload
/// retains its idempotency key; saved originals are never uploaded again.
class ReceiptImportQueue extends ChangeNotifier {
  ReceiptImportQueue({
    required this.client,
    required List<BookkeepingPickedReceipt> files,
  }) {
    validateReceiptBatch(files);
    items = files.map(ReceiptImportItem.new).toList();
    client.addAccessDeniedListener(_lock);
  }
  final ReceiptWizClient client;
  late final List<ReceiptImportItem> items;
  bool running = false, started = false, locked = false;
  bool _disposed = false, _stop = false;
  bool get _alive => !_disposed && !locked && !client.sessionChanged;
  int get savedCount => items.where((item) => item.saved).length;
  int get remainingCount => items.length - savedCount;

  void _lock() {
    if (_disposed) return;
    locked = true;
    _stop = true;
    for (final item in items) {
      item.file = null;
    }
    items.clear();
    notifyListeners();
  }

  void stop() {
    _stop = true;
  }

  Future<void> start({required bool scan}) async {
    if (!_alive || running) return;
    started = running = true;
    _stop = false;
    notifyListeners();
    try {
      for (final item in items.toList()) {
        if (!_alive || _stop) break;
        if (item.saved || item.file == null) continue;
        item.status = 'Saving original…';
        notifyListeners();
        try {
          final uploaded = await client.upload(
            item.requestKey,
            item.name,
            item.file!.bytes,
          );
          if (!_alive) return;
          final receipt = wizMap(uploaded['receipt']);
          if (receipt['state'] != 'ready') {
            item.status = 'Still processing. Wait two minutes, then retry.';
            continue;
          }
          item.saved = true;
          item.file = null;
          item.reused = uploaded['reused'] == true;
          item.status = item.reused
              ? 'Already saved · existing copy kept'
              : 'Saved · ready for manual review';
          if (scan && !item.reused && !_stop) {
            item.status = 'Original saved · reading details…';
            notifyListeners();
            try {
              final result = await client.request(
                'POST',
                '/${receipt['id']}/scan',
                body: {
                  'confirmed': true,
                  'request_key': bookkeepingRequestKey(),
                },
              );
              if (!_alive) return;
              final state = wizMap(wizMap(result['receipt'])['scan'])['state'];
              item.status = state == 'ready'
                  ? 'Saved · check the extracted details'
                  : 'Saved · check scan status in Receipts';
            } catch (e) {
              if (!_alive) return;
              item.status =
                  'Original saved · $e Review or retry scanning in Receipts.';
            }
          }
        } catch (e) {
          if (!_alive) return;
          item.status = 'Not saved · $e';
        } finally {
          if (_alive) notifyListeners();
        }
      }
    } finally {
      running = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stop = true;
    client.removeAccessDeniedListener(_lock);
    for (final item in items) {
      item.file = null;
    }
    items.clear();
    super.dispose();
  }
}

class ReceiptWizBatchImport extends StatefulWidget {
  const ReceiptWizBatchImport({
    super.key,
    required this.client,
    required this.files,
    required this.ensureConsent,
    required this.scanAvailable,
  });
  final ReceiptWizClient client;
  final List<BookkeepingPickedReceipt> files;
  final Future<bool> Function() ensureConsent;
  final bool scanAvailable;
  @override
  State<ReceiptWizBatchImport> createState() => _ReceiptWizBatchImportState();
}

class _ReceiptWizBatchImportState extends State<ReceiptWizBatchImport> {
  late final ReceiptImportQueue _queue;
  late bool _scan;
  bool _consenting = false, _stopping = false;
  String? _error;
  bool get _busy => _queue.running || _consenting;
  @override
  void initState() {
    super.initState();
    _scan = widget.scanAvailable;
    _queue = ReceiptImportQueue(client: widget.client, files: widget.files);
    _queue.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _queue.removeListener(_refresh);
    _queue.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy || _queue.locked) return;
    setState(() {
      _consenting = true;
      _stopping = false;
      _error = null;
    });
    try {
      final scan = _scan && await widget.ensureConsent();
      if (!mounted || _queue.locked || widget.client.sessionChanged) return;
      setState(() {
        _consenting = false;
        _scan = scan;
      });
      await _queue.start(scan: scan);
    } catch (_) {
      if (mounted && !_queue.locked) {
        setState(
          () => _error =
              'Could not start this import. Try again, or turn off AI reading to save originals.',
        );
      }
    } finally {
      if (mounted) setState(() => _consenting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: wizTheme(context),
    child: PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Import receipt files')),
        body: _queue.locked
            ? const Center(
                child: Text('Your session changed. Reopen Receipt WIZ.'),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    _queue.started
                        ? '${_queue.savedCount} of ${_queue.items.length} originals saved'
                        : '${_queue.items.length} files ready to upload',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  const Text(
                    'Up to 10 files · 8 MB each · 40 MB total. Originals are saved to your private KORLIX receipt vault. Review amounts and dates before using them.',
                  ),
                  if (!_queue.started)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Read receipt details with AI'),
                      subtitle: Text(
                        widget.scanAvailable
                            ? 'Uses one scan per new receipt, subject to your plan. Exact duplicates reuse the saved copy.'
                            : 'Automatic reading is currently unavailable. You can still save originals and add details.',
                      ),
                      value: _scan,
                      onChanged: _busy || !widget.scanAvailable
                          ? null
                          : (v) => setState(() => _scan = v ?? false),
                    ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(),
                    ),
                  for (final item in _queue.items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        item.saved
                            ? Icons.check_circle_outline
                            : Icons.description_outlined,
                        color: item.saved ? wizGreen : wizMuted,
                      ),
                      title: Text(item.name),
                      subtitle: Text(item.status),
                    ),
                  const SizedBox(height: 16),
                  if (_queue.remainingCount > 0 && !_queue.running)
                    FilledButton.icon(
                      key: const Key('receipt-batch-start'),
                      onPressed: _busy ? null : _start,
                      icon: const Icon(Icons.file_upload_outlined),
                      label: Text(
                        _queue.started ? 'Retry unsaved files' : 'Upload files',
                      ),
                    ),
                  if (_queue.running)
                    OutlinedButton(
                      onPressed: _stopping
                          ? null
                          : () {
                              _queue.stop();
                              setState(() => _stopping = true);
                            },
                      child: Text(
                        _stopping
                            ? 'Finishing current file…'
                            : 'Stop after current file',
                      ),
                    ),
                  if (_queue.started && !_busy) ...[
                    if (_queue.remainingCount > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Unsaved files stay in this queue while it is open. Retry here, or choose them again later. Saved originals are kept even if scanning fails.',
                        ),
                      ),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('View receipts'),
                    ),
                  ],
                ],
              ),
      ),
    ),
  );
}
