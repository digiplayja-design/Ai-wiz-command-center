import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../bookkeeping/bookkeeping_file_save.dart';
import '../bookkeeping/bookkeeping_models.dart';
import '../bookkeeping/bookkeeping_ui.dart';
import '../bookkeeping/receipt_picker.dart';
import 'receipt_wiz_client.dart';
import 'receipt_wiz_style.dart';

class ReceiptWizPhotoReview extends StatefulWidget {
  const ReceiptWizPhotoReview({
    super.key,
    required this.photo,
    required this.client,
  });
  final BookkeepingPickedReceipt photo;
  final ReceiptWizClient client;
  @override
  State<ReceiptWizPhotoReview> createState() => _ReceiptWizPhotoReviewState();
}

class _ReceiptWizPhotoReviewState extends State<ReceiptWizPhotoReview> {
  bool _locked = false;
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_lock);
  }

  void _lock() {
    if (mounted) setState(() => _locked = true);
  }

  @override
  void dispose() {
    widget.client.removeAccessDeniedListener(_lock);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: wizTheme(context),
    child: Scaffold(
      appBar: AppBar(title: const Text('Check your receipt')),
      body: _locked
          ? const Center(child: Text('Sign in again to continue.'))
          : SafeArea(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Can you read the merchant, date and total? Pinch to zoom.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: widget.photo.name.toLowerCase().endsWith('.pdf')
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.picture_as_pdf_outlined,
                                  size: 80,
                                  color: wizTeal,
                                ),
                                SizedBox(height: 12),
                                Text('PDF ready to save and read'),
                              ],
                            ),
                          )
                        : InteractiveViewer(
                            minScale: 1,
                            maxScale: 6,
                            child: Center(
                              child: Image.memory(
                                widget.photo.bytes,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const Text(
                                  'This image cannot be previewed. Choose JPG, PNG or WebP.',
                                ),
                              ),
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Choose again'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.pop(context, true),
                            icon: const Icon(Icons.document_scanner_outlined),
                            label: const Text('Save receipt'),
                          ),
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

enum ReceiptWizReviewAction { scanNext, viewReceipts }

class ReceiptWizReview extends StatefulWidget {
  const ReceiptWizReview({
    super.key,
    required this.client,
    required this.receipt,
    required this.ensureConsent,
    this.notice,
    this.integrations = const {},
  });
  final ReceiptWizClient client;
  final Map<String, dynamic> receipt, integrations;
  final Future<bool> Function() ensureConsent;
  final String? notice;
  @override
  State<ReceiptWizReview> createState() => _ReceiptWizReviewState();
}

class _ReceiptWizReviewState extends State<ReceiptWizReview> {
  late Map<String, dynamic> _receipt;
  final _fields = <String, TextEditingController>{};
  final _items = TextEditingController();
  List<String> _warnings = [];
  String _category = 'Uncategorized';
  bool _busy = false,
      _locked = false,
      _dirty = false,
      _saved = false,
      _requireComplete = false,
      _waitingForScan = false;
  String? _error, _notice;
  Uint8List? _preview;
  int _operation = 0;
  final _form = GlobalKey<FormState>(), _exportKey = GlobalKey();
  bool get _alive => mounted && !_locked && !widget.client.sessionChanged;
  @override
  void initState() {
    super.initState();
    _receipt = widget.receipt;
    _waitingForScan = wizMap(_receipt['scan'])['state'] == 'scanning';
    _notice = widget.notice;
    for (final key in [
      'merchant',
      'date',
      'total',
      'subtotal',
      'tax',
      'tip',
      'currency',
      'description',
    ]) {
      _fields[key] = TextEditingController();
    }
    _setFields();
    widget.client.addAccessDeniedListener(_lock);
    unawaited(_loadPreview());
  }

  void _setFields() {
    final d = wizMap(_receipt['details']);
    for (final e in _fields.entries) {
      e.value.text = d[e.key]?.toString() ?? '';
    }
    _category = wizCategories.contains(d['category'])
        ? d['category']
        : 'Uncategorized';
    _items.text = (d['items'] as List? ?? []).whereType<String>().join('\n');
    _warnings = (d['warnings'] as List? ?? []).whereType<String>().toList();
    _dirty = false;
  }

  void _lock() {
    if (!mounted) return;
    _operation++;
    setState(() {
      _locked = true;
      _receipt = {};
      _preview = null;
      for (final c in _fields.values) {
        c.clear();
      }
      _items.clear();
      _warnings = [];
      _saved = false;
      _dirty = false;
      _error = _notice = null;
      _busy = false;
    });
  }

  @override
  void dispose() {
    _operation++;
    widget.client.removeAccessDeniedListener(_lock);
    for (final c in _fields.values) {
      c.dispose();
    }
    _items.dispose();
    _preview = null;
    super.dispose();
  }

  Future<void> _loadPreview() async {
    if ((_receipt['preview_size'] as num? ?? 0) == 0) return;
    final op = _operation;
    try {
      final bytes = await widget.client.receiptBytes(
        _receipt['id'],
        preview: true,
      );
      if (_alive && op == _operation) setState(() => _preview = bytes);
    } catch (_) {
      if (_alive && op == _operation) {
        setState(
          () => _notice =
              'The preview is unavailable. Your original can still be downloaded.',
        );
      }
    }
  }

  Future<bool> _discard() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Discard unsaved edits?'),
            content: const Text('The saved receipt will remain in your inbox.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Keep editing'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Discard edits'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _save(bool reviewed) async {
    if (!_alive || _busy) return;
    _requireComplete = reviewed;
    final valid = _form.currentState!.validate();
    final itemsError = _itemsError();
    if (!valid || itemsError != null) {
      setState(() => _error = itemsError);
      return;
    }
    final op = ++_operation;
    setState(() {
      _busy = true;
      _saved = false;
      _error = null;
      _notice = null;
    });
    try {
      final details = {
        ...wizMap(_receipt['details']),
        for (final e in _fields.entries)
          e.key: e.key == 'currency'
              ? e.value.text.trim().toUpperCase()
              : e.value.text.trim(),
        'category': _category,
        'items': _itemLines,
        'warnings': _warnings,
      };
      final data = await widget.client.request(
        'PUT',
        '/${_receipt['id']}',
        body: {
          'version': _receipt['version'],
          'details': details,
          'reviewed': reviewed,
        },
      );
      if (!mounted || !_alive || op != _operation) return;
      setState(() {
        _receipt = wizMap(data['receipt']);
        _setFields();
        _saved = true;
        _waitingForScan = false;
        _notice = data['possible_duplicate'] == true
            ? 'Saved. Another receipt has the same merchant, date and total. Check your inbox for a possible duplicate.'
            : 'Saved in your private receipt inbox and connected finance inboxes.';
      });
    } catch (e) {
      if (_alive && op == _operation) setState(() => _error = e.toString());
    } finally {
      if (_alive && op == _operation) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    if (!_alive || _busy || !await _discard() || !_alive) return;
    if (!await widget.ensureConsent() || !_alive) return;
    final op = ++_operation;
    setState(() {
      _busy = true;
      _saved = false;
      _error = null;
      _notice = 'Reading the receipt. Your original is already saved.';
    });
    try {
      final data = await widget.client.request(
        'POST',
        '/${_receipt['id']}/scan',
        body: {'confirmed': true, 'request_key': bookkeepingRequestKey()},
      );
      if (!mounted || !_alive || op != _operation) return;
      setState(() {
        _receipt = wizMap(data['receipt']);
        _setFields();
        final scan = wizMap(_receipt['scan']);
        _waitingForScan = scan['state'] == 'scanning';
        _applySuggestion(scan);
        _notice = _waitingForScan
            ? 'This scan is still running. Refresh to check it.'
            : 'Review the extracted details, then save your corrections.';
      });
    } catch (e) {
      if (_alive && op == _operation) setState(() => _error = e.toString());
    } finally {
      if (_alive && op == _operation) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    if (_busy || !await _discard() || !_alive) return;
    final op = ++_operation;
    setState(() {
      _busy = true;
      _saved = false;
    });
    try {
      final d = await widget.client.request('GET', '/${_receipt['id']}');
      if (_alive && op == _operation) {
        setState(() {
          _receipt = wizMap(d['receipt']);
          _setFields();
          _error = null;
          _notice = null;
          if (_waitingForScan) {
            final scan = wizMap(_receipt['scan']);
            _waitingForScan = scan['state'] == 'scanning';
            _applySuggestion(scan);
            _notice = _waitingForScan
                ? 'This scan is still running. Refresh to check it.'
                : scan['state'] == 'ready'
                ? 'Review the extracted details, then save your corrections.'
                : 'The scan did not finish. Your original is saved; retry reading or enter the details.';
          }
        });
      }
    } catch (e) {
      if (_alive && op == _operation) setState(() => _error = e.toString());
    } finally {
      if (_alive && op == _operation) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    if (_busy || !_alive) return;
    final op = ++_operation;
    setState(() => _busy = true);
    try {
      final bytes = await widget.client.receiptBytes(_receipt['id']);
      if (!mounted || !_alive || op != _operation) return;
      await saveBookkeepingFile(
        bytes,
        _receipt['filename'],
        _receipt['mime_type'],
        bookkeepingShareOrigin(_exportKey, context),
      );
    } catch (e) {
      if (_alive) setState(() => _error = e.toString());
    } finally {
      if (_alive && op == _operation) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy || !_alive) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove this receipt?'),
        content: const Text(
          'This removes the original and its details from Receipt Wiz and the shared Bookkeeping and Tax Prep inboxes. Previously downloaded copies remain separate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep receipt'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove receipt'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || !_alive) return;
    final op = ++_operation;
    setState(() => _busy = true);
    try {
      await widget.client.request(
        'DELETE',
        '/${_receipt['id']}',
        body: {'confirmed': true},
      );
      if (!mounted || !_alive || op != _operation) return;
      setState(() => _dirty = false);
      Navigator.pop(context);
    } catch (e) {
      if (_alive) setState(() => _error = e.toString());
    } finally {
      if (_alive && op == _operation) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate() async {
    final current = DateTime.tryParse(_fields['date']!.text) ?? DateTime.now();
    final initial = current.year < 2000 || current.year > 2099
        ? DateTime.now()
        : current;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2099, 12, 31),
    );
    if (!_alive || date == null) return;
    setState(() {
      _fields['date']!.text = bookkeepingDate(date);
      _dirty = true;
    });
  }

  List<String> get _itemLines => _items.text
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  String? _itemsError() {
    final lines = _itemLines;
    if (lines.length > 40 ||
        lines.any(
          (s) => s.length > 180 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(s),
        )) {
      return 'Use up to 40 item lines, 180 characters each.';
    }
    return null;
  }

  void _applySuggestion(Map<String, dynamic> scan) {
    final suggestion = wizMap(scan['suggestion']);
    if (scan['state'] != 'ready' || suggestion.isEmpty) return;
    for (final e in _fields.entries) {
      e.value.text = suggestion[e.key]?.toString() ?? '';
    }
    _category = wizCategories.contains(suggestion['category'])
        ? suggestion['category']
        : 'Uncategorized';
    _items.text = (suggestion['items'] as List? ?? []).whereType<String>().join(
      '\n',
    );
    _warnings = (suggestion['warnings'] as List? ?? [])
        .whereType<String>()
        .toList();
    _dirty = true;
  }

  void _finish(ReceiptWizReviewAction action) {
    if (!_alive || _busy || _dirty || !_saved) return;
    Navigator.of(context).pop(action);
  }

  Widget _savedActions() => ColoredBox(
    color: const Color(0xFFEAF8F5),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _receipt['reviewed'] == true
                  ? 'Receipt saved'
                  : 'Saved for later review',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: wizTeal,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('scan-next-receipt'),
                  onPressed: _busy
                      ? null
                      : () => _finish(ReceiptWizReviewAction.scanNext),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Scan next receipt'),
                ),
                OutlinedButton.icon(
                  key: const Key('view-saved-receipts'),
                  onPressed: _busy
                      ? null
                      : () => _finish(ReceiptWizReviewAction.viewReceipts),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('View receipts'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _field(
    String key,
    String label, {
    bool required = false,
    int lines = 1,
  }) => TextFormField(
    key: ValueKey('receipt-$key'),
    controller: _fields[key],
    enabled: !_busy,
    onChanged: (_) => setState(() => _dirty = true),
    maxLines: lines,
    maxLength: key == 'description'
        ? 1000
        : key == 'merchant'
        ? 160
        : null,
    keyboardType: ['total', 'subtotal', 'tax', 'tip'].contains(key)
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    textCapitalization: key == 'currency'
        ? TextCapitalization.characters
        : TextCapitalization.none,
    decoration: InputDecoration(
      labelText: label,
      errorMaxLines: 3,
      suffixIcon: key == 'date'
          ? IconButton(
              tooltip: 'Choose receipt date',
              onPressed: _busy ? null : _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
            )
          : null,
    ),
    validator: (v) {
      final value = (v ?? '').trim();
      if (required && _requireComplete && value.isEmpty) {
        return 'Add $label or save for later';
      }
      if (value.isEmpty) return null;
      if (key == 'date') {
        final date = DateTime.tryParse(value);
        if (!RegExp(r'^20\d{2}-\d{2}-\d{2}$').hasMatch(value) ||
            date == null ||
            bookkeepingDate(date) != value) {
          return 'Use a valid date: YYYY-MM-DD';
        }
      }
      if (['total', 'subtotal', 'tax', 'tip'].contains(key) &&
          !RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(value)) {
        return 'Use an amount such as 28.40';
      }
      if (key == 'currency' &&
          !RegExp(r'^[A-Z]{3}$').hasMatch(value.toUpperCase())) {
        return 'Use 3 letters, such as USD';
      }
      return null;
    },
  );
  @override
  Widget build(BuildContext context) => Theme(
    data: wizTheme(context),
    child: PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, result) async {
        if (_busy) return;
        if (!didPop && await _discard() && mounted) {
          setState(() => _dirty = false);
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        bottomNavigationBar: _saved && !_dirty && !_locked
            ? _savedActions()
            : null,
        appBar: AppBar(
          title: const Text('Review receipt'),
          actions: [
            IconButton(
              tooltip: 'Refresh receipt',
              onPressed: _busy || _locked ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              key: _exportKey,
              tooltip: 'Download original',
              onPressed: _busy || _locked ? null : _download,
              icon: const Icon(Icons.file_download_outlined),
            ),
          ],
        ),
        body: _locked
            ? const Center(
                child: Text('Your session changed. Reopen THE RECEIPT WIZ.'),
              )
            : Form(
                key: _form,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1040),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_busy) const LinearProgressIndicator(),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                _error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          if (_notice != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                _notice!,
                                style: const TextStyle(color: wizTeal),
                              ),
                            ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              wizChip(
                                _receipt['reviewed'] == true
                                    ? 'Reviewed'
                                    : 'Needs review',
                                icon: Icons.fact_check_outlined,
                              ),
                              wizChip(
                                'Original saved',
                                icon: Icons.lock_outline,
                              ),
                              if (wizRows(
                                widget.integrations['bookkeeping'],
                              ).isNotEmpty)
                                wizChip(
                                  'Bookkeeping inbox',
                                  icon: Icons.account_balance_wallet_outlined,
                                ),
                              if (wizRows(
                                widget.integrations['tax_prep'],
                              ).isNotEmpty)
                                wizChip(
                                  'Tax Prep inbox',
                                  icon: Icons.folder_open_outlined,
                                ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          LayoutBuilder(
                            builder: (c, box) {
                              final image = Container(
                                height: box.maxWidth > 740 ? 550 : 340,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8EFF2),
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: _preview != null
                                    ? InteractiveViewer(
                                        minScale: 1,
                                        maxScale: 6,
                                        child: Image.memory(
                                          _preview!,
                                          fit: BoxFit.contain,
                                        ),
                                      )
                                    : Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _receipt['mime_type'] ==
                                                      'application/pdf'
                                                  ? Icons
                                                        .picture_as_pdf_outlined
                                                  : Icons.receipt_long_outlined,
                                              size: 66,
                                              color: wizTeal,
                                            ),
                                            const SizedBox(height: 14),
                                            const Text(
                                              'Original available to download',
                                            ),
                                          ],
                                        ),
                                      ),
                              );
                              final fields = Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _field(
                                    'merchant',
                                    'Merchant',
                                    required: true,
                                  ),
                                  const SizedBox(height: 14),
                                  _field(
                                    'date',
                                    'Date (YYYY-MM-DD)',
                                    required: true,
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: _field(
                                          'total',
                                          'Total',
                                          required: true,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _field(
                                          'currency',
                                          'Currency',
                                          required: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  DropdownButtonFormField<String>(
                                    key: ValueKey('category-$_category'),
                                    initialValue: _category,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Category',
                                    ),
                                    items: [
                                      for (final c in wizCategories)
                                        DropdownMenuItem(
                                          value: c,
                                          child: Text(c),
                                        ),
                                    ],
                                    onChanged: _busy
                                        ? null
                                        : (v) => setState(() {
                                            _category = v!;
                                            _dirty = true;
                                          }),
                                  ),
                                  const SizedBox(height: 14),
                                  _field(
                                    'description',
                                    'Description / what was this for? (optional)',
                                    lines: 3,
                                  ),
                                ],
                              );
                              return box.maxWidth > 740
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: image),
                                        const SizedBox(width: 24),
                                        Expanded(child: fields),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        image,
                                        const SizedBox(height: 20),
                                        fields,
                                      ],
                                    );
                            },
                          ),
                          const SizedBox(height: 18),
                          ExpansionTile(
                            title: const Text('More receipt details'),
                            subtitle: const Text(
                              'Subtotal, tax, tip and editable items',
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    for (final key in [
                                      'subtotal',
                                      'tax',
                                      'tip',
                                    ])
                                      SizedBox(
                                        width: 180,
                                        child: _field(
                                          key,
                                          key[0].toUpperCase() +
                                              key.substring(1),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              TextFormField(
                                key: const Key('receipt-items'),
                                controller: _items,
                                enabled: !_busy,
                                minLines: 3,
                                maxLines: 8,
                                decoration: const InputDecoration(
                                  labelText: 'Receipt items (optional)',
                                  helperText:
                                      'One item per line · Up to 40 items, 180 characters each',
                                  helperMaxLines: 3,
                                ),
                                onChanged: (_) => setState(() => _dirty = true),
                                validator: (_) => _itemsError(),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                          for (final warning in _warnings)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(warning)),
                                ],
                              ),
                            ),
                          const SizedBox(height: 16),
                          const Text(
                            'Review the original before using these details in your books. Saving a receipt does not post an expense or calculate a tax deduction.',
                            style: TextStyle(color: wizMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              FilledButton.icon(
                                key: const Key('save-reviewed-receipt'),
                                onPressed: _busy ? null : () => _save(true),
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('Save reviewed receipt'),
                              ),
                              OutlinedButton(
                                onPressed: _busy ? null : () => _save(false),
                                child: const Text('Save for later'),
                              ),
                              TextButton.icon(
                                onPressed: _busy || _receipt['state'] != 'ready'
                                    ? null
                                    : _scan,
                                icon: const Icon(Icons.auto_awesome_outlined),
                                label: const Text('Read receipt again'),
                              ),
                              TextButton.icon(
                                onPressed: _busy ? null : _delete,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Remove'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}
