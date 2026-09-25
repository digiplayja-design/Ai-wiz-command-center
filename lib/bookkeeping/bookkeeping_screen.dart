import 'dart:async';
import 'package:flutter/material.dart';
import 'bookkeeping_client.dart';
import 'bookkeeping_csv_save.dart';
import 'bookkeeping_forms.dart';
import 'bookkeeping_models.dart';

const _navy = Color(0xff10253f),
    _cyan = Color(0xff087e98),
    _muted = Color(0xff566a7f);

class BookkeepingScreen extends StatefulWidget {
  const BookkeepingScreen({
    super.key,
    required this.client,
    this.disposeClient = false,
    this.onExport,
  });
  final BookkeepingClient client;
  final bool disposeClient;
  final Future<void> Function(String csv, String filename)? onExport;
  @override
  State<BookkeepingScreen> createState() => _BookkeepingScreenState();
}

class _BookkeepingScreenState extends State<BookkeepingScreen> {
  List<Map<String, dynamic>> _businesses = [];
  Map<String, dynamic>? _business, _overview;
  String _month = bookkeepingDate(DateTime.now()).substring(0, 7);
  int _offset = 0, _operation = 0;
  bool _busy = false, _denied = false;
  String? _error;
  final _dialogs = <DialogRoute<dynamic>>{};
  final _exportKey = GlobalKey();
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
    unawaited(_load());
  }

  @override
  void dispose() {
    _operation++;
    widget.client.removeAccessDeniedListener(_deny);
    if (widget.disposeClient) widget.client.dispose();
    super.dispose();
  }

  void _deny() {
    if (!mounted || _denied) return;
    setState(() {
      _denied = true;
      _operation++;
      _businesses = [];
      _business = null;
      _overview = null;
      _busy = false;
      _error = null;
    });
    final obsolete = _dialogs.toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final r in obsolete) {
        if (r.isActive) r.navigator?.removeRoute(r);
      }
    });
  }

  bool _current(int n) => mounted && !_denied && n == _operation;
  Future<T?> _dialog<T>(Widget child) async {
    final route = DialogRoute<T>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Theme(data: _theme, child: child),
    );
    _dialogs.add(route);
    try {
      return await Navigator.of(context).push(route);
    } finally {
      _dialogs.remove(route);
    }
  }

  Future<void> _load({String? select, bool list = true}) async {
    if (_denied) return;
    final op = ++_operation;
    setState(() {
      _busy = true;
      _error = null;
      _overview = null;
    });
    try {
      if (list) {
        final data = await widget.client.request('GET', '/businesses');
        if (!_current(op)) return;
        _businesses = bookkeepingRows(data['businesses']);
        final target = select ?? _business?['id'];
        _business =
            _businesses.where((b) => b['id'] == target).firstOrNull ??
            _businesses.firstOrNull;
      }
      if (_business != null) {
        final data = await widget.client.request(
          'GET',
          '/businesses/${_business!['id']}/overview',
          query: {'month': _month, 'offset': '$_offset'},
        );
        if (!_current(op)) return;
        _overview = data;
        _business = Map<String, dynamic>.from(data['business'] as Map);
      }
    } catch (e) {
      if (_current(op)) _error = e.toString();
    } finally {
      if (_current(op)) setState(() => _busy = false);
    }
  }

  Future<void> _profile({bool edit = false}) async {
    final op = _operation;
    final result = await _dialog<Map<String, dynamic>>(
      BookkeepingProfileDialog(
        client: widget.client,
        business: edit ? _business : null,
      ),
    );
    if (!_current(op)) return;
    _offset = 0;
    // A closed dialog may follow a lost save response; refresh authoritative data.
    await _load(select: result?['id'] as String?);
  }

  Future<void> _entry(String kind, {Map<String, dynamic>? original}) async {
    if (_business == null || _overview == null) return;
    final op = _operation;
    final saved = await _dialog<Map<String, dynamic>>(
      BookkeepingEntryDialog(
        client: widget.client,
        businessId: _business!['id'] as String,
        categories: bookkeepingRows(_overview!['categories']),
        kind: kind,
        original: original,
      ),
    );
    if (!_current(op)) return;
    if (saved != null) _month = (saved['entry_date'] as String).substring(0, 7);
    _offset = 0;
    await _load(list: false);
  }

  Future<void> _export() async {
    if (_business == null || _busy) return;
    final op = ++_operation;
    final box = _exportKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.client.request(
        'GET',
        '/businesses/${_business!['id']}/export',
        query: {'month': _month},
      );
      if (!_current(op)) return;
      final csv = data['csv'] as String, filename = data['filename'] as String;
      if (widget.onExport != null) {
        await widget.onExport!(csv, filename);
      } else {
        await saveBookkeepingCsv(csv, filename, origin);
      }
    } catch (e) {
      if (_current(op)) _error = e.toString();
    } finally {
      if (_current(op)) setState(() => _busy = false);
    }
  }

  void _changeMonth(int change) {
    final parsed = DateTime.parse('$_month-01');
    final d = DateTime(parsed.year, parsed.month + change);
    if (d.year < 2000 || d.year > 2099) return;
    _month = bookkeepingDate(d).substring(0, 7);
    _offset = 0;
    unawaited(_load(list: false));
  }

  ThemeData get _theme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _cyan,
      brightness: Brightness.light,
      primary: _cyan,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: const Color(0xfff3f7fb),
    textTheme: ThemeData.light().textTheme.apply(
      bodyColor: _navy,
      displayColor: _navy,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      filled: true,
      fillColor: const Color(0xfff8fafc),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Theme(
    data: _theme,
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _navy,
          title: const Text(
            'Bookkeeping 2027',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          actions: [
            if (!_denied)
              IconButton(
                tooltip: 'Refresh records',
                onPressed: _busy ? null : () => _load(),
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        body: _denied
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Your session changed. Sign in again and reopen Bookkeeping.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : LayoutBuilder(
                builder: (context, box) => Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (box.maxWidth >= 1100) _sidebar(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(box.maxWidth < 600 ? 16 : 30),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1180),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_busy)
                                  const LinearProgressIndicator(minHeight: 3),
                                if (_error != null)
                                  _panel(
                                    Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(
                                          color: Color(0xff9c2525),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (_businesses.isEmpty &&
                                    !_busy &&
                                    _error == null)
                                  _welcome()
                                else ...[
                                  _header(),
                                  const SizedBox(height: 22),
                                  _toolbar(),
                                  const SizedBox(height: 20),
                                  if (_overview != null) ...[
                                    _totals(),
                                    const SizedBox(height: 22),
                                    _activity(),
                                  ],
                                  const SizedBox(height: 24),
                                  _scope(),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    ),
  );
  Widget _sidebar() => Container(
    width: 220,
    color: _navy,
    padding: const EdgeInsets.all(22),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/meeting_copilot/korlix_logo.jpeg',
              width: 54,
              height: 54,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'KORLIX',
            style: TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const Text(
            'BOOKKEEPING 2027',
            style: TextStyle(
              color: Color(0xff7fe6f3),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 36),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xff234059),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.dashboard_outlined,
                  color: Color(0xff7fe6f3),
                  size: 20,
                ),
                SizedBox(width: 12),
                Text(
                  'Dashboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'YOUR RECORDBOOK',
            style: TextStyle(
              color: Color(0xff93acbf),
              fontSize: 10,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'One business.\nOne clear picture.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Build the habit today.\nStart 2027 organized.',
            style: TextStyle(color: Color(0xffc0d1dd), height: 1.6),
          ),
          const SizedBox(height: 64),
          const Text(
            'EARLY ACCESS\nManual cash activity · USD',
            style: TextStyle(
              color: Color(0xffa8c0d0),
              fontSize: 11,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
  Widget _panel(Widget child) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xffdde6ee)),
    ),
    child: child,
  );
  Widget _welcome() => _panel(
    Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            'assets/meeting_copilot/korlix_logo.jpeg',
            height: 64,
            width: 64,
          ),
          const SizedBox(height: 22),
          const Text(
            'Your business.\nYour books. A clearer 2027.',
            style: TextStyle(
              fontSize: 32,
              height: 1.2,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Start a private recordbook for your business. Record income received, track expenses paid, and see your monthly activity in one place.',
            style: TextStyle(fontSize: 16, height: 1.6, color: _muted),
          ),
          const SizedBox(height: 16),
          const Text(
            'For independent contractors, sole traders, LLCs, partnerships, S corporations and C corporations.',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _profile(),
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Add your first business'),
          ),
          const SizedBox(height: 24),
          _scope(),
        ],
      ),
    ),
  );
  Widget _header() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'YOUR BUSINESS AT A GLANCE',
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w800,
          color: _cyan,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Make every entry count.',
        style: TextStyle(
          fontSize: 30,
          height: 1.2,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 18),
      Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              key: ValueKey(_business?['id']),
              initialValue: _business?['id'] as String?,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Business'),
              items: _businesses
                  .map(
                    (b) => DropdownMenuItem(
                      value: b['id'] as String,
                      child: Text(
                        b['name'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (id) {
                      _offset = 0;
                      unawaited(_load(select: id));
                    },
            ),
          ),
          TextButton.icon(
            onPressed: _busy || _business == null
                ? null
                : () => _profile(edit: true),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Edit profile'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : () => _profile(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add business'),
          ),
        ],
      ),
      if (_business != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            '${businessStructures[_business!['legal_structure']]} · ${taxTreatments[_business!['tax_treatment']]} tax treatment',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ),
    ],
  );
  Widget _toolbar() => Wrap(
    spacing: 10,
    runSpacing: 10,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xffdde6ee)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: _busy || _month == '2000-01'
                  ? null
                  : () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(_month, style: const TextStyle(fontWeight: FontWeight.w800)),
            IconButton(
              tooltip: 'Next month',
              onPressed: _busy || _month == '2099-12'
                  ? null
                  : () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
      FilledButton.icon(
        onPressed: _busy || _overview == null ? null : () => _entry('income'),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Record income'),
      ),
      OutlinedButton.icon(
        onPressed: _busy || _overview == null ? null : () => _entry('expense'),
        icon: const Icon(Icons.remove, size: 18),
        label: const Text('Record expense'),
      ),
      OutlinedButton.icon(
        key: _exportKey,
        onPressed: _busy || _overview == null ? null : _export,
        icon: const Icon(Icons.download_outlined, size: 18),
        label: const Text('Export month'),
      ),
    ],
  );
  Widget _totals() => LayoutBuilder(
    builder: (_, c) {
      final width = c.maxWidth >= 780 ? (c.maxWidth - 28) / 3 : c.maxWidth;
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          _total(
            'Recorded income',
            _overview!['income_cents'],
            const Color(0xff167753),
            Icons.south_west,
            width,
          ),
          _total(
            'Recorded expenses',
            _overview!['expense_cents'],
            const Color(0xff94530e),
            Icons.north_east,
            width,
          ),
          _total(
            'Net recorded activity',
            _overview!['net_cents'],
            _cyan,
            Icons.account_balance_wallet_outlined,
            width,
          ),
        ],
      );
    },
  );
  Widget _total(
    String label,
    dynamic cents,
    Color color,
    IconData icon,
    double width,
  ) => SizedBox(
    width: width,
    child: _panel(
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(icon, color: color, size: 22),
              ],
            ),
            const SizedBox(height: 16),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                bookkeepingMoney(cents),
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'USD · Selected month',
              style: TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _activity() {
    final entries = bookkeepingRows(_overview!['entries']);
    final count = _overview!['entry_count'] as int;
    return _panel(
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Monthly activity',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
                Text(
                  '$count ${count == 1 ? 'entry' : 'entries'}',
                  style: const TextStyle(color: _muted),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Includes original entries and any correction offsets.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 18),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 26),
                child: Text(
                  'No entries for this month yet. Start with money received or an expense paid.',
                  style: TextStyle(color: _muted, height: 1.6),
                ),
              ),
            ...entries.map(_entryRow),
            if (count > 50)
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${_offset + 1}–${_offset + entries.length} of $count'),
                  TextButton(
                    onPressed: _busy || _offset == 0
                        ? null
                        : () {
                            _offset -= 50;
                            unawaited(_load(list: false));
                          },
                    child: const Text('Previous page'),
                  ),
                  TextButton(
                    onPressed: _busy || _offset + entries.length >= count
                        ? null
                        : () {
                            _offset += 50;
                            unawaited(_load(list: false));
                          },
                    child: const Text('Next page'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _entryRow(Map<String, dynamic> e) {
    final reversed = e['reversed_by'] != null,
        reversal = e['kind'] == 'reversal';
    final label = reversal
        ? 'Correction offset'
        : e['kind'] == 'income'
        ? 'Income'
        : 'Expense';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xffe5edf3))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                bookkeepingMoney(e['amount_cents']),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: _cyan,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                e['entry_date'] as String,
                style: const TextStyle(color: _muted),
              ),
              if (reversed)
                const Text(
                  'Reversed',
                  style: TextStyle(
                    color: Color(0xff94530e),
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            e['purpose'] as String,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            [
              e['category_name'],
              if ((e['counterparty'] as String? ?? '').isNotEmpty)
                e['counterparty'],
            ].join(' · '),
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          if ((e['receipt_reference'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Reference: ${e['receipt_reference']}',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ),
          if (!reversed && !reversal)
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => _entry(e['kind'] as String, original: e),
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('Reverse entry'),
            ),
        ],
      ),
    );
  }

  Widget _scope() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xffe6f3f6),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'YOUR FIRST STEP TOWARD ORGANIZED BOOKS',
          style: TextStyle(
            color: _cyan,
            fontSize: 11,
            letterSpacing: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Live now: business profiles, manual income and expenses, correction history, and monthly CSV export.',
          style: TextStyle(height: 1.6),
        ),
        SizedBox(height: 6),
        Text(
          'Coming next: receipt uploads and scanning. Mileage, reconciliation and accountant reports follow.',
          style: TextStyle(color: _muted, height: 1.6),
        ),
        SizedBox(height: 10),
        Text(
          'Early access · USD cash activity only. Totals reflect entries you record, not a bank balance or a complete profit and loss statement. No bank connection or tax filing yet.',
          style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
        ),
      ],
    ),
  );
}
