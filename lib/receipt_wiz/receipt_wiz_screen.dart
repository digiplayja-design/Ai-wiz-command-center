import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../bookkeeping/bookkeeping_file_save.dart';
import '../bookkeeping/bookkeeping_models.dart';
import '../bookkeeping/bookkeeping_ui.dart';
import '../bookkeeping/receipt_picker.dart';
import 'receipt_wiz_capture.dart';
import 'receipt_wiz_client.dart';
import 'receipt_wiz_review.dart';
import 'receipt_wiz_style.dart';

class ReceiptWizScreen extends StatefulWidget {
  const ReceiptWizScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    this.initialYear,
    this.businessId,
    this.taxWorkspaceId,
    this.inboxOnly = false,
    this.picker,
    this.capture,
    this.saveFile,
  });
  final ReceiptWizClient client;
  final Future<bool> Function() ensureConsent;
  final int? initialYear;
  final String? businessId, taxWorkspaceId;
  final bool inboxOnly;
  final Future<BookkeepingPickedReceipt?> Function()? picker, capture;
  final Future<void> Function(Uint8List, String, String, Rect)? saveFile;
  @override
  State<ReceiptWizScreen> createState() => _ReceiptWizScreenState();
}

class _ReceiptWizScreenState extends State<ReceiptWizScreen> {
  List<Map<String, dynamic>> _receipts = [];
  Map<String, dynamic> _integrations = {};
  final _search = TextEditingController(), _exportKey = GlobalKey();
  Timer? _debounce;
  bool _loading = true,
      _uploading = false,
      _locked = false,
      _needsReview = false,
      _scanAvailable = true;
  bool _inboxTab = false;
  int _offset = 0,
      _total = 0,
      _loadOperation = 0,
      _usedBytes = 0,
      _scansToday = 0;
  String? _category, _error, _notice;
  int? _year;
  BookkeepingPickedReceipt? _pending;
  String? _uploadKey;
  bool get _alive => mounted && !_locked && !widget.client.sessionChanged;
  @override
  void initState() {
    super.initState();
    _year = widget.initialYear;
    widget.client.addAccessDeniedListener(_lock);
    unawaited(_load());
  }

  @override
  void dispose() {
    _loadOperation++;
    _debounce?.cancel();
    _search.dispose();
    _pending = null;
    widget.client.removeAccessDeniedListener(_lock);
    widget.client.dispose();
    super.dispose();
  }

  void _lock() {
    if (!mounted) return;
    _loadOperation++;
    _debounce?.cancel();
    setState(() {
      _locked = true;
      _receipts = [];
      _integrations = {};
      _pending = null;
      _uploadKey = null;
      _search.clear();
      _loading = _uploading = false;
      _error = _notice = null;
    });
  }

  Map<String, String> get _query => {
    'offset': '$_offset',
    if (_search.text.trim().isNotEmpty) 'query': _search.text.trim(),
    'category': ?_category,
    if (_needsReview) 'needs_review': 'true',
    if (_year != null) 'year': '$_year',
    if (widget.businessId != null) 'business_id': widget.businessId!,
    if (widget.taxWorkspaceId != null)
      'tax_workspace_id': widget.taxWorkspaceId!,
  };
  Future<void> _load() async {
    if (!mounted || !_alive) return;
    final op = ++_loadOperation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.client.request('GET', '', query: _query);
      if (!_alive || op != _loadOperation) return;
      setState(() {
        _receipts = wizRows(data['receipts']);
        _integrations = wizMap(data['integrations']);
        _total = (data['total'] as num?)?.toInt() ?? 0;
        _usedBytes = (data['used_bytes'] as num?)?.toInt() ?? 0;
        _scansToday = (data['scans_today'] as num?)?.toInt() ?? 0;
        _scanAvailable = data['scanning_available'] == true;
      });
    } catch (e) {
      if (_alive && op == _loadOperation) setState(() => _error = e.toString());
    } finally {
      if (_alive && op == _loadOperation) setState(() => _loading = false);
    }
  }

  void _filter() {
    _offset = 0;
    unawaited(_load());
  }

  Future<void> _choose(bool camera) async {
    if (!_alive || _uploading) return;
    setState(() => _uploading = true);
    try {
      BookkeepingPickedReceipt? photo;
      var again = true;
      while (again && mounted && _alive) {
        if (!mounted) return;
        photo = await (camera
            ? (widget.capture?.call() ??
                  captureReceiptWiz(context, widget.client))
            : (widget.picker?.call() ?? pickBookkeepingReceipt()));
        if (!mounted || !_alive || photo == null) return;
        if (photo.bytes.isEmpty || photo.bytes.length > 8 * 1024 * 1024) {
          throw const ReceiptWizException('Choose a photo or PDF up to 8 MB.');
        }
        final choice = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) =>
                ReceiptWizPhotoReview(photo: photo!, client: widget.client),
          ),
        );
        if (!_alive || choice == null) return;
        again = !choice;
      }
      if (!mounted || !_alive || photo == null) return;
      _pending = photo;
      _uploadKey = bookkeepingRequestKey();
      await _process();
    } catch (e) {
      if (_alive) {
        setState(() {
          _error = e.toString();
          _notice = null;
        });
      }
    } finally {
      if (_alive) setState(() => _uploading = false);
    }
  }

  Future<void> _process() async {
    if (!_alive || _pending == null) return;
    setState(() {
      _uploading = true;
      _error = null;
      _notice = 'Saving your original receipt…';
    });
    try {
      final data = await widget.client.upload(
        _uploadKey!,
        _pending!.name,
        _pending!.bytes,
      );
      if (!mounted || !_alive) return;
      var receipt = wizMap(data['receipt']);
      _integrations = wizMap(data['integrations']);
      if (receipt['state'] != 'ready') {
        setState(
          () => _notice =
              'This upload is still finishing. Keep this screen open, wait two minutes, then retry the same file.',
        );
        await _load();
        return;
      }
      _pending = null;
      _uploadKey = null;
      String? note;
      if (data['reused'] == true) {
        note =
            'This exact receipt is already saved. We opened the existing copy.';
      } else if (_scanAvailable && await widget.ensureConsent() && _alive) {
        setState(
          () => _notice =
              'Original saved. Reading the merchant, amount and category…',
        );
        try {
          final scan = await widget.client.request(
            'POST',
            '/${receipt['id']}/scan',
            body: {'confirmed': true, 'request_key': bookkeepingRequestKey()},
          );
          if (!mounted || !_alive) return;
          receipt = wizMap(scan['receipt']);
        } catch (e) {
          if (!mounted || !_alive) return;
          note =
              'Your original is saved. ${e.toString()} You can add the details now or retry scanning.';
        }
      } else {
        note =
            'Original saved. Add the details below; automatic reading is optional.';
      }
      if (!mounted || !_alive) return;
      _notice = null;
      await _open(receipt, notice: note);
    } catch (e) {
      if (_alive) {
        setState(() {
          _error = e.toString();
          _notice = null;
        });
      }
    } finally {
      if (_alive) setState(() => _uploading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> receipt, {String? notice}) async {
    if (!mounted || !_alive) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReceiptWizReview(
          client: widget.client,
          receipt: receipt,
          ensureConsent: widget.ensureConsent,
          integrations: _integrations,
          notice: notice,
        ),
      ),
    );
    if (_alive) {
      setState(() => _inboxTab = true);
      await _load();
    }
  }

  Future<void> _export() async {
    if (!_alive || _uploading) return;
    setState(() => _uploading = true);
    try {
      final data = await widget.client.request('GET', '/export', query: _query);
      if (!mounted || !_alive) return;
      await (widget.saveFile ?? saveBookkeepingFile)(
        Uint8List.fromList(utf8.encode(data['csv'] as String)),
        data['filename'] as String,
        'text/csv',
        bookkeepingShareOrigin(_exportKey, context),
      );
      if (_alive) {
        setState(
          () => _notice =
              'Exported ${data['count']} receipts matching your filters.',
        );
      }
    } catch (e) {
      if (_alive) {
        setState(() {
          _error = e.toString();
          _notice = null;
        });
      }
    } finally {
      if (_alive) setState(() => _uploading = false);
    }
  }

  Widget _scanner() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF102F45), Color(0xFF075766)],
      ),
      borderRadius: BorderRadius.circular(28),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            wizChip(
              'FREE · EVERY PLAN',
              icon: Icons.auto_awesome_outlined,
              color: wizMint,
            ),
            wizChip('PRIVATE VAULT', icon: Icons.lock_outline, color: wizMint),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          'Little receipts.\nEverything in order.',
          style: TextStyle(
            fontSize: 31,
            height: 1.1,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -.8,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Scan once. Find it fast. Keep your connected finance inboxes in sync.',
          style: TextStyle(color: Color(0xFFBFE0E8), height: 1.5),
        ),
        const SizedBox(height: 22),
        Container(
          height: 210,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .035),
            border: Border.all(color: wizMint.withValues(alpha: .35)),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Center(
            child: Transform.rotate(
              angle: -.055,
              child: Container(
                width: 138,
                height: 174,
                padding: const EdgeInsets.all(19),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFFFC),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .18),
                      blurRadius: 25,
                      offset: const Offset(8, 14),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.receipt_long_outlined,
                      color: wizTeal,
                      size: 34,
                    ),
                    const SizedBox(height: 14),
                    for (final width in [78.0, 92.0, 64.0]) ...[
                      Container(
                        width: width,
                        height: 6,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCDDDDA),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 9),
                    ],
                    const Spacer(),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TOTAL',
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: wizInk,
                          ),
                        ),
                        Icon(Icons.check_circle, color: wizTeal, size: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          key: const Key('receipt-wiz-camera'),
          onPressed: _uploading ? null : () => _choose(true),
          style: FilledButton.styleFrom(
            backgroundColor: wizMint,
            foregroundColor: wizInk,
            padding: const EdgeInsets.symmetric(vertical: 18),
          ),
          icon: const Icon(Icons.document_scanner_outlined, size: 25),
          label: const Text(
            'Open large scanner',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('receipt-wiz-upload'),
          onPressed: _uploading ? null : () => _choose(false),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF82B6C1)),
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Choose photo or PDF'),
        ),
        const SizedBox(height: 14),
        const Text(
          'JPG, PNG, WebP or PDF · Up to 8 MB\nAuto-read details, then review and correct.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFBFE0E8), fontSize: 12, height: 1.5),
        ),
      ],
    ),
  );
  Widget _connected() => wizPanel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.hub_outlined, color: wizTeal, size: 30),
        const SizedBox(height: 12),
        const Text(
          'One receipt. Connected inboxes.',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: wizInk,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Your original and corrections stay together. When you have a Bookkeeping business or Tax Prep organizer, its shared receipt inbox includes your scans automatically.',
          style: TextStyle(color: wizMuted, height: 1.5),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            wizChip(
              'Receipt Wiz · Always saved',
              icon: Icons.check_circle_outline,
            ),
            if (wizRows(_integrations['bookkeeping']).isNotEmpty)
              wizChip(
                'Bookkeeping · Connected',
                icon: Icons.check_circle_outline,
              ),
            if (wizRows(_integrations['tax_prep']).isNotEmpty)
              wizChip('Tax Prep · Connected', icon: Icons.check_circle_outline),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 12),
        const Text(
          'Made for real life',
          style: TextStyle(fontWeight: FontWeight.w700, color: wizInk),
        ),
        const SizedBox(height: 10),
        for (final (icon, title) in [
          (
            Icons.auto_awesome_outlined,
            'Automatic merchant, date, amount and category',
          ),
          (Icons.edit_note_outlined, 'Add the purpose in your own words'),
          (Icons.copy_all_outlined, 'Exact duplicate detection'),
          (Icons.search, 'Search, filter and export your receipts'),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: wizTeal),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: const TextStyle(color: wizInk)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Text(
          '$_scansToday / 100 free AI scans today · No credits used\n${(_usedBytes / 1048576).toStringAsFixed(1)} / 250 MB stored',
          style: const TextStyle(color: wizMuted, fontSize: 12, height: 1.6),
        ),
      ],
    ),
  );
  Widget _inbox() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Your receipt inbox',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: wizInk,
              ),
            ),
          ),
          IconButton(
            key: _exportKey,
            tooltip: 'Export filtered receipts as CSV',
            onPressed: _uploading || _locked ? null : _export,
            icon: const Icon(Icons.file_download_outlined, color: wizTeal),
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('receipt-wiz-search'),
        controller: _search,
        decoration: InputDecoration(
          hintText: 'Search merchant, items or description',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _search.clear();
                    _filter();
                  },
                  icon: const Icon(Icons.close),
                ),
        ),
        onChanged: (_) {
          setState(() {});
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 350), _filter);
        },
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilterChip(
            label: const Text('Needs review'),
            selected: _needsReview,
            onSelected: (v) {
              setState(() => _needsReview = v);
              _filter();
            },
          ),
          SizedBox(
            width: 210,
            child: DropdownButtonFormField<String>(
              key: ValueKey('filter-$_category'),
              initialValue: _category ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('All categories'),
                ),
                for (final c in wizCategories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) {
                setState(() => _category = v == '' ? null : v);
                _filter();
              },
            ),
          ),
          SizedBox(
            width: 155,
            child: DropdownButtonFormField<int>(
              key: ValueKey('year-$_year'),
              initialValue: _year ?? 0,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Year'),
              items: [
                const DropdownMenuItem(value: 0, child: Text('All years')),
                for (var y = DateTime.now().year + 1; y >= 2000; y--)
                  DropdownMenuItem(value: y, child: Text('$y')),
              ],
              onChanged: (v) {
                setState(() => _year = v == 0 ? null : v);
                _filter();
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      if (_year != null)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Receipts without a date are included so you can assign the correct year.',
            style: TextStyle(color: wizMuted, fontSize: 12),
          ),
        ),
      if (_loading) const LinearProgressIndicator(),
      if (!_loading && _receipts.isEmpty)
        wizPanel(
          Column(
            children: [
              const Icon(Icons.receipt_long_outlined, size: 44, color: wizTeal),
              const SizedBox(height: 12),
              Text(
                _search.text.isNotEmpty || _category != null || _needsReview
                    ? 'No receipts match these filters.'
                    : 'Your receipts belong here.',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Take a clear photo or choose a PDF to get started.',
                textAlign: TextAlign.center,
                style: TextStyle(color: wizMuted),
              ),
            ],
          ),
        ),
      for (final r in _receipts)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _receiptTile(r),
        ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: Text(
              '$_total receipt${_total == 1 ? '' : 's'}${_total > 0 ? ' · ${_offset + 1}–${(_offset + _receipts.length).clamp(0, _total)}' : ''}',
              style: const TextStyle(color: wizMuted),
            ),
          ),
          IconButton(
            tooltip: 'Previous receipts',
            onPressed: _offset == 0 || _loading
                ? null
                : () {
                    _offset = (_offset - 30).clamp(0, 1000);
                    unawaited(_load());
                  },
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Next receipts',
            onPressed: _offset + 30 >= _total || _loading
                ? null
                : () {
                    _offset += 30;
                    unawaited(_load());
                  },
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    ],
  );
  Widget _receiptTile(Map<String, dynamic> r) {
    final d = wizMap(r['details']);
    final merchant = d['merchant']?.toString() ?? '';
    final state = r['state']?.toString() ?? '';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _uploading ? null : () => _open(r),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: wizTeal.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  r['mime_type'] == 'application/pdf'
                      ? Icons.picture_as_pdf_outlined
                      : Icons.receipt_long_outlined,
                  color: wizTeal,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      merchant.isEmpty ? r['filename'] ?? 'Receipt' : merchant,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: wizInk,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${(d['date'] ?? '').toString().isEmpty ? 'Date needed' : d['date']} · ${d['category'] ?? 'Uncategorized'}',
                      style: const TextStyle(color: wizMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          wizAmount(d),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: wizInk,
                          ),
                        ),
                        Text(
                          state != 'ready'
                              ? state
                              : r['reviewed'] == true
                              ? 'Reviewed'
                              : 'Needs review',
                          style: TextStyle(
                            color: r['reviewed'] == true
                                ? wizTeal
                                : Colors.deepOrange,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: wizMuted),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: wizTheme(context),
    child: Scaffold(
      appBar: AppBar(
        title: const Text(
          'THE RECEIPT WIZ',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: .5,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh receipts',
            onPressed: _loading || _locked ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: widget.inboxOnly || _locked
          ? null
          : NavigationBar(
              selectedIndex: _inboxTab ? 1 : 0,
              onDestinationSelected: (i) => setState(() => _inboxTab = i == 1),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.document_scanner_outlined),
                  label: 'Scan',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  label: 'Receipts',
                ),
              ],
            ),
      body: _locked
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Your session changed. Sign in again and reopen THE RECEIPT WIZ.',
                ),
              ),
            )
          : SingleChildScrollView(
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_uploading) const LinearProgressIndicator(),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      if (_notice != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            _notice!,
                            style: const TextStyle(color: wizTeal),
                          ),
                        ),
                      if (_pending != null && !_uploading)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Wrap(
                            spacing: 12,
                            children: [
                              FilledButton(
                                onPressed: _process,
                                child: const Text('Retry saving this receipt'),
                              ),
                              TextButton(
                                onPressed: () => setState(() {
                                  _pending = null;
                                  _uploadKey = null;
                                  _notice = null;
                                }),
                                child: const Text('Choose a different receipt'),
                              ),
                            ],
                          ),
                        ),
                      if (!widget.inboxOnly && !_inboxTab)
                        LayoutBuilder(
                          builder: (c, b) => b.maxWidth >= 850
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 5, child: _scanner()),
                                    const SizedBox(width: 24),
                                    Expanded(flex: 4, child: _connected()),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _scanner(),
                                    const SizedBox(height: 18),
                                    _connected(),
                                  ],
                                ),
                        ),
                      if (widget.inboxOnly) ...[
                        wizPanel(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Automatically saved from THE RECEIPT WIZ',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                  color: wizInk,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'These are your shared originals and current details. Changes here are also visible in Receipt Wiz.',
                                style: TextStyle(color: wizMuted),
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    onPressed: _uploading
                                        ? null
                                        : () => _choose(true),
                                    icon: const Icon(
                                      Icons.document_scanner_outlined,
                                    ),
                                    label: const Text('Scan receipt'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _uploading
                                        ? null
                                        : () => _choose(false),
                                    icon: const Icon(Icons.upload_file),
                                    label: const Text('Choose photo or PDF'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 30),
                      if (widget.inboxOnly || _inboxTab) _inbox(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
    ),
  );
}
