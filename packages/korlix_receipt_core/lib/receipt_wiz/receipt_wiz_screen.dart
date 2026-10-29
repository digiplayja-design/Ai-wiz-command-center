import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../bookkeeping/bookkeeping_file_save.dart';
import '../bookkeeping/bookkeeping_models.dart';
import '../bookkeeping/bookkeeping_ui.dart';
import '../bookkeeping/receipt_picker.dart';
import 'receipt_wiz_capture.dart';
import 'receipt_wiz_batch.dart';
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
    this.batchPicker,
    this.saveFile,
    this.onOpenAccount,
    this.onOpenSubscription,
  });
  final ReceiptWizClient client;
  final Future<bool> Function() ensureConsent;
  final int? initialYear;
  final String? businessId, taxWorkspaceId;
  final bool inboxOnly;
  final Future<BookkeepingPickedReceipt?> Function()? picker, capture;
  final Future<List<BookkeepingPickedReceipt>?> Function()? batchPicker;
  final Future<void> Function(Uint8List, String, String, Rect)? saveFile;
  final VoidCallback? onOpenAccount;
  final Future<void> Function()? onOpenSubscription;
  @override
  State<ReceiptWizScreen> createState() => _ReceiptWizScreenState();
}

class _ReceiptWizScreenState extends State<ReceiptWizScreen> {
  List<Map<String, dynamic>> _receipts = [];
  Map<String, dynamic> _integrations = {};
  Map<String, dynamic> _plan = {};
  final _search = TextEditingController(), _exportKey = GlobalKey();
  Timer? _debounce;
  bool _loading = true,
      _uploading = false,
      _locked = false,
      _needsReview = false,
      _scanAvailable = true;
  bool _inboxTab = false;
  int _offset = 0, _total = 0, _loadOperation = 0, _usedBytes = 0;
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
      _plan = {};
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
      final total = (data['total'] as num?)?.toInt() ?? 0;
      if (_offset > 0 && _offset >= total) {
        _offset = total == 0 ? 0 : ((total - 1) ~/ 30) * 30;
        await _load();
        return;
      }
      setState(() {
        _receipts = wizRows(data['receipts']);
        _integrations = wizMap(data['integrations']);
        _total = (data['total'] as num?)?.toInt() ?? 0;
        _usedBytes = (data['used_bytes'] as num?)?.toInt() ?? 0;
        _plan = wizMap(data['plan']);
        _scanAvailable = data['scanning_available'] == true;
      });
    } catch (e) {
      if (_alive && op == _loadOperation) setState(() => _error = e.toString());
    } finally {
      if (_alive && op == _loadOperation) setState(() => _loading = false);
    }
  }

  void _filter() {
    _debounce?.cancel();
    _offset = 0;
    unawaited(_load());
  }

  Future<void> _batchImport() async {
    if (!_alive || _uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final files =
          await (widget.batchPicker?.call() ?? pickBookkeepingReceiptBatch());
      if (!mounted || !_alive || files == null || files.isEmpty) return;
      validateReceiptBatch(files);
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ReceiptWizBatchImport(
            client: widget.client,
            files: files,
            ensureConsent: widget.ensureConsent,
            scanAvailable: _scanAvailable,
          ),
        ),
      );
      if (_alive) {
        setState(() {
          _inboxTab = true;
          _offset = 0;
        });
        await _load();
      }
    } catch (e) {
      if (_alive) setState(() => _error = e.toString());
    } finally {
      if (_alive) setState(() => _uploading = false);
    }
  }

  Future<void> _choose(bool camera) async {
    if (!_alive || _uploading) return;
    var scanNext = true;
    while (scanNext && _alive) {
      scanNext = await _captureAndSave(camera);
      camera = true;
    }
  }

  Future<bool> _captureAndSave(bool camera) async {
    if (!_alive || _uploading) return false;
    setState(() => _uploading = true);
    try {
      BookkeepingPickedReceipt? photo;
      var again = true;
      while (again && mounted && _alive) {
        if (!mounted) return false;
        photo = await (camera
            ? (widget.capture?.call() ??
                  captureReceiptWiz(context, widget.client))
            : (widget.picker?.call() ?? pickBookkeepingReceipt()));
        if (!mounted || !_alive || photo == null) return false;
        if (photo.bytes.isEmpty || photo.bytes.length > 8 * 1024 * 1024) {
          throw const ReceiptWizException('Choose a photo or PDF up to 8 MB.');
        }
        final choice = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) =>
                ReceiptWizPhotoReview(photo: photo!, client: widget.client),
          ),
        );
        if (!_alive || choice == null) return false;
        again = !choice;
      }
      if (!mounted || !_alive || photo == null) return false;
      _pending = photo;
      _uploadKey = bookkeepingRequestKey();
      return await _process();
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
    return false;
  }

  Future<void> _retryUpload() async {
    if (!_alive || _uploading) return;
    if (await _process() && _alive) await _choose(true);
  }

  Future<bool> _process() async {
    if (!_alive || _pending == null) return false;
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
      if (!mounted || !_alive) return false;
      var receipt = wizMap(data['receipt']);
      _integrations = wizMap(data['integrations']);
      if (receipt['state'] != 'ready') {
        setState(
          () => _notice = 'This upload is still finishing. Keep this screen open, wait two minutes, then retry the same file.',
        );
        await _load();
        return false;
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
          if (!mounted || !_alive) return false;
          receipt = wizMap(scan['receipt']);
        } catch (e) {
          if (!mounted || !_alive) return false;
          note =
              'Your original is saved. ${e.toString()} You can add the details now or retry scanning.';
        }
      } else {
        note = 'Original saved. Add the details below; automatic reading is optional.';
      }
      if (!mounted || !_alive) return false;
      _notice = null;
      return await _open(receipt, notice: note);
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
    return false;
  }

  Future<bool> _open(Map<String, dynamic> receipt, {String? notice}) async {
    if (!mounted || !_alive) return false;
    final action = await Navigator.of(context).push<ReceiptWizReviewAction>(
      MaterialPageRoute<ReceiptWizReviewAction>(
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
    return _alive && action == ReceiptWizReviewAction.scanNext;
  }

  Future<void> _showVaultPrivacy() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Your private receipt vault'),
      content: const SingleChildScrollView(
        child: Text(
          'Your vault opens with your Korlix sign-in. There is no separate vault password.\n\nThe lock means your receipts are private to your account. Your Bookkeeping and Tax Prep receipt inboxes use the same saved records. Sign out of Korlix when using a shared device.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Got it'),
        ),
      ],
    ),
  );

  Future<void> _export() async {
    if (!_alive || _uploading) return;
    setState(() => _uploading = true);
    try {
      final filters = {..._query}..remove('offset');
      final data = await widget.client.request(
        'GET',
        '/export',
        query: filters,
      );
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

  Future<void> _subscription() async {
    await widget.onOpenSubscription?.call();
    if (_alive) await _load();
  }

  Widget _usage() {
    final used = (_plan['scans_this_month'] as num?)?.toInt() ?? 0;
    final limit = (_plan['monthly_scan_limit'] as num?)?.toInt();
    final unlimited = _plan['unlimited'] == true;
    final full = _plan['name'] == 'full';
    return Container(
      key: const Key('receipt-monthly-usage'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF4ECFF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4D2FA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              wizChip(
                full ? 'RECEIPT WIZ FULL' : 'FREE PLAN',
                icon: full
                    ? Icons.workspace_premium_outlined
                    : Icons.auto_awesome_outlined,
              ),
              if (_plan['included'] == true)
                wizChip(
                  'Included with KORLIX',
                  icon: Icons.check_circle_outline,
                  color: wizGreen,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _plan.isEmpty
                ? 'Loading your scan allowance…'
                : unlimited
                ? '$used AI scans this month · Unlimited access'
                : '$used / ${limit ?? 20} AI scans this month',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: wizInk,
            ),
          ),
          const SizedBox(height: 10),
          if (limit != null && limit > 0)
            LinearProgressIndicator(
              value: (used / limit).clamp(0, 1),
              color: used >= limit ? wizCoral : wizTeal,
              backgroundColor: Colors.white,
              minHeight: 7,
              borderRadius: BorderRadius.circular(10),
              semanticsLabel: '$used of $limit monthly AI scans used',
            ),
          const SizedBox(height: 10),
          Text(
            'Resets on the 1st of each month (UTC). Failed scans are returned.\n'
            '${(_usedBytes / 1048576).toStringAsFixed(1)} MB stored'
            '${_plan['max_bytes'] is num ? ' of ${((_plan['max_bytes'] as num) / 1048576).round()} MB' : ''}',
            style: const TextStyle(color: wizMuted, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _scanner() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF6431B1), Color(0xFFAA3768)],
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
              _plan['name'] == 'full'
                  ? 'FULL · MORE ROOM TO SCAN'
                  : 'SCAN · SORT · SAVE',
              icon: Icons.auto_awesome_outlined,
              color: wizMint,
            ),
            ActionChip(
              avatar: const Icon(Icons.lock_outline, color: wizMint, size: 16),
              label: const Text('PRIVATE VAULT'),
              labelStyle: const TextStyle(color: wizMint, fontSize: 11),
              color: const WidgetStatePropertyAll(Color(0xFF45236C)),
              side: BorderSide(color: wizMint.withValues(alpha: .3)),
              onPressed: _showVaultPrivacy,
            ),
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
          style: TextStyle(color: Color(0xFFF7E5FF), height: 1.5),
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
            side: const BorderSide(color: Color(0xFFE3B5E2)),
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Upload receipt files'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const Key('receipt-wiz-batch'),
          onPressed: _uploading ? null : _batchImport,
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          icon: const Icon(Icons.library_add_outlined),
          label: const Text('Import multiple files'),
        ),
        const SizedBox(height: 14),
        const Text(
          'JPG, PNG, WebP or PDF · Up to 8 MB\nAuto-read details, then review and correct.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFF7E5FF), fontSize: 12, height: 1.5),
        ),
      ],
    ),
  );
  Widget _connected() => wizPanel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _usage(),
        const SizedBox(height: 22),
        const Icon(Icons.hub_outlined, color: wizGreen, size: 30),
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
              color: wizGreen,
            ),
            if (wizRows(_integrations['bookkeeping']).isNotEmpty)
              wizChip(
                'Bookkeeping · Connected',
                icon: Icons.check_circle_outline,
                color: wizCoral,
              ),
            if (wizRows(_integrations['tax_prep']).isNotEmpty)
              wizChip(
                'Tax Prep · Connected',
                icon: Icons.check_circle_outline,
                color: wizAmber,
              ),
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
          if (_search.text.isNotEmpty ||
              _category != null ||
              _needsReview ||
              _year != widget.initialYear)
            TextButton.icon(
              onPressed: () {
                _debounce?.cancel();
                setState(() {
                  _search.clear();
                  _category = null;
                  _needsReview = false;
                  _year = widget.initialYear;
                });
                _filter();
              },
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Reset filters'),
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
                _search.text.isNotEmpty ||
                        _category != null ||
                        _needsReview ||
                        _year != null
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
                    _offset = (_offset - 30).clamp(0, 1000000);
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
        onTap: _uploading
            ? null
            : () async {
                if (await _open(r) && _alive) await _choose(true);
              },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: wizCategoryColor(d['category']?.toString())
                      .withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  r['mime_type'] == 'application/pdf'
                      ? Icons.picture_as_pdf_outlined
                      : Icons.receipt_long_outlined,
                  color: wizCategoryColor(d['category']?.toString()),
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
                                ? wizGreen
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
          if (widget.onOpenAccount != null)
            IconButton(
              tooltip: 'Account and settings',
              onPressed: widget.onOpenAccount,
              icon: const Icon(Icons.account_circle_outlined),
            ),
          IconButton(
            tooltip: 'Receipt vault privacy',
            onPressed: _locked ? null : _showVaultPrivacy,
            icon: const Icon(Icons.lock_outline),
          ),
          IconButton(
            tooltip: 'Refresh receipts',
            onPressed: _loading || _locked ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: widget.inboxOnly || _locked
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onOpenSubscription != null)
                  Material(
                    color: const Color(0xFFFFF0D5),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _plan['name'] == 'full'
                                  ? (_plan['included'] == true
                                        ? 'Full included with KORLIX'
                                        : 'Receipt Wiz Full')
                                  : 'More scans. More space.',
                              style: const TextStyle(
                                color: wizInk,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _uploading ? null : _subscription,
                            child: Text(
                              _plan['name'] == 'full' ? 'My plan' : 'Upgrade',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                NavigationBar(
                  indicatorColor: const Color(0xFFE7D5FA),
                  backgroundColor: const Color(0xFFFFFAF5),
                  selectedIndex: _inboxTab ? 1 : 0,
                  onDestinationSelected: (i) =>
                      setState(() => _inboxTab = i == 1),
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
                                onPressed: _retryUpload,
                                child: const Text('Retry saving this receipt'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  // Keep the previous retry available if selection is cancelled.
                                  await _choose(false);
                                },
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
                                    label: const Text('Upload receipt files'),
                                  ),
                                  TextButton.icon(
                                    onPressed: _uploading ? null : _batchImport,
                                    icon: const Icon(
                                      Icons.library_add_outlined,
                                    ),
                                    label: const Text('Import multiple files'),
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
