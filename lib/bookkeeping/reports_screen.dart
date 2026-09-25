import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'bookkeeping_client.dart';
import 'bookkeeping_csv_save.dart';
import 'bookkeeping_models.dart';

const reportTitles = {
  'profit_loss': 'Profit & loss',
  'balance_sheet': 'Balance sheet',
  'trial_balance': 'Trial balance',
};

class BookkeepingReports extends StatefulWidget {
  const BookkeepingReports({
    super.key,
    required this.client,
    required this.businessId,
    required this.businessName,
    required this.initialPeriod,
    this.onExport,
  });
  final BookkeepingClient client;
  final String businessId, businessName, initialPeriod;
  final Future<void> Function(String csv, String filename)? onExport;
  @override
  State<BookkeepingReports> createState() => _BookkeepingReportsState();
}

class _BookkeepingReportsState extends State<BookkeepingReports> {
  late final _period = TextEditingController(text: widget.initialPeriod);
  late String _selectedPeriod = widget.initialPeriod;
  final _exportKey = GlobalKey();
  String _kind = 'profit_loss';
  Map<String, dynamic>? _data;
  String? _error, _notice;
  bool _busy = false, _denied = false;
  bool get _alive => mounted && !_denied && !widget.client.sessionChanged;
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
    unawaited(_load());
  }

  void _deny() {
    if (!mounted) return;
    setState(() {
      _denied = true;
      _data = null;
      _error = null;
      _notice = null;
      _period.clear();
    });
  }

  @override
  void dispose() {
    widget.client.removeAccessDeniedListener(_deny);
    _period.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_alive || _busy) return;
    setState(() {
      _busy = true;
      _data = null;
      _error = null;
      _notice = null;
    });
    try {
      final d = await widget.client.request(
        'GET',
        '/businesses/${widget.businessId}/reports',
        query: {'period': _selectedPeriod},
      );
      if (_alive) setState(() => _data = d);
    } catch (e) {
      if (_alive) setState(() => _error = e.toString());
    } finally {
      if (_alive) setState(() => _busy = false);
    }
  }

  void _apply() {
    if (!RegExp(r'^20\d\d(?:-(?:0[1-9]|1[0-2]))?$').hasMatch(_period.text)) {
      setState(() => _error = 'Use YYYY or YYYY-MM between 2000 and 2099.');
      return;
    }
    FocusScope.of(context).unfocus();
    _selectedPeriod = _period.text;
    unawaited(_load());
  }

  Future<void> _export(String kind) async {
    if (!_alive || _busy) return;
    final box = _exportKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final d = await widget.client.request(
        'GET',
        '/businesses/${widget.businessId}/reports/export',
        query: {'period': _selectedPeriod, 'kind': kind},
      );
      if (!_alive) return;
      if (widget.onExport != null) {
        await widget.onExport!(d['csv'] as String, d['filename'] as String);
      } else {
        await saveBookkeepingCsv(
          d['csv'] as String,
          d['filename'] as String,
          origin,
        );
      }
      if (_alive) {
        setState(
          () => _notice = 'CSV prepared from the latest recorded entries.',
        );
      }
    } catch (e) {
      if (_alive) setState(() => _error = e.toString());
    } finally {
      if (_alive) setState(() => _busy = false);
    }
  }

  Widget _card(List<Widget> children) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xffdce6ef)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
  Widget _amount(String label, Object? cents, {bool total = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: LayoutBuilder(
      builder: (_, box) {
        final style = TextStyle(
          fontSize: total ? 18 : 14,
          fontWeight: total ? FontWeight.w800 : FontWeight.w500,
        );
        final value = Text(bookkeepingMoney(cents), style: style);
        if (box.maxWidth < 430) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: style),
              const SizedBox(height: 4),
              value,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: style)),
            const SizedBox(width: 16),
            Flexible(
              child: Align(alignment: Alignment.centerRight, child: value),
            ),
          ],
        );
      },
    ),
  );
  List<Map<String, dynamic>> get _accounts =>
      bookkeepingRows(_data?['accounts']);
  BigInt _c(Map a, String field) => BigInt.parse(a[field] as String);
  Iterable<Widget> _group(
    String title,
    List<String> kinds,
    String field, {
    bool negate = false,
    bool movement = false,
  }) sync* {
    yield Text(
      title,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
    );
    final accounts = _accounts.where((a) => kinds.contains(a['kind']));
    for (final a in accounts) {
      final value = movement
          ? _c(a, 'period_debit_cents') - _c(a, 'period_credit_cents')
          : _c(a, field);
      if (value == BigInt.zero) continue;
      yield _amount('${a['code']} · ${a['name']}', negate ? -value : value);
    }
  }

  List<Widget> _statement() {
    final s = _data!['summary'] as Map;
    if (_kind == 'profit_loss') {
      return [
        ..._group('Income', ['income'], '', negate: true, movement: true),
        _amount('Total income', s['income_cents'], total: true),
        const Divider(),
        ..._group('Expenses', ['expense'], '', movement: true),
        _amount('Total expenses', s['expense_cents'], total: true),
        const Divider(),
        _amount('Recorded net profit / loss', s['net_cents'], total: true),
        const Text(
          'Cash operating activity only. Contributions, loan principal, transfers and asset purchases remain in the balance-sheet accounts.',
          style: TextStyle(color: Color(0xff566a7f), height: 1.5),
        ),
      ];
    }
    if (_kind == 'balance_sheet') {
      return [
        ..._group('Assets', ['cash', 'asset'], 'closing_cents'),
        _amount('Total assets', s['assets_cents'], total: true),
        const Divider(),
        ..._group('Liabilities', ['liability'], 'closing_cents', negate: true),
        _amount('Total liabilities', s['liabilities_cents'], total: true),
        const Divider(),
        ..._group('Booked equity', ['equity'], 'closing_cents', negate: true),
        _amount(
          'Unclosed earnings · prior calendar years',
          s['prior_earnings_cents'],
        ),
        _amount(
          'Unclosed earnings · current calendar year to date',
          s['current_earnings_cents'],
        ),
        _amount(
          'Total equity including earnings',
          s['total_equity_cents'],
          total: true,
        ),
        const Divider(),
        _amount(
          'Balance check difference',
          s['balance_difference_cents'],
          total: true,
        ),
        const Text(
          'Unclosed earnings are calculated from the recorded income and expense accounts. No closing journal is posted. Calendar-year labels do not select a tax or fiscal year.',
          style: TextStyle(color: Color(0xff566a7f), height: 1.5),
        ),
      ];
    }
    return [
      const Text(
        'Beginning balances + period movements = closing balances',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      for (final a in _accounts.where(
        (a) => [
          'beginning_cents',
          'period_debit_cents',
          'period_credit_cents',
          'closing_cents',
        ].any((f) => _c(a, f) != BigInt.zero),
      )) ...[
        Text(
          '${a['code']} · ${a['name']}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        _amount(
          'Beginning ${_c(a, 'beginning_cents').isNegative ? 'credit' : 'debit'}',
          _c(a, 'beginning_cents').abs(),
        ),
        _amount('Period debits', a['period_debit_cents']),
        _amount('Period credits', a['period_credit_cents']),
        _amount(
          'Closing ${_c(a, 'closing_cents').isNegative ? 'credit' : 'debit'}',
          _c(a, 'closing_cents').abs(),
        ),
        const Divider(),
      ],
      _amount('Total closing debits', s['trial_debit_cents'], total: true),
      _amount('Total closing credits', s['trial_credit_cents'], total: true),
      const Text(
        'CSV includes every account and separate debit and credit columns. Balanced totals do not establish completeness or correct classification.',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(12),
    child: SizedBox(
      width: 980,
      height: math.max(
        260,
        math.min(880, MediaQuery.sizeOf(context).height - 40),
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
                      const Expanded(
                        child: Text(
                          'Financial reports',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close reports',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Text(
                    widget.businessName,
                    style: const TextStyle(color: Color(0xff566a7f)),
                  ),
                  const SizedBox(height: 16),
                  if (_busy) const LinearProgressIndicator(minHeight: 3),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: 180,
                                child: TextField(
                                  controller: _period,
                                  enabled: !_busy,
                                  decoration: const InputDecoration(
                                    labelText: 'Month or year',
                                    hintText: '2027 or 2027-01',
                                  ),
                                  onSubmitted: (_) => _apply(),
                                ),
                              ),
                              FilledButton(
                                onPressed: _busy ? null : _apply,
                                child: const Text('View period'),
                              ),
                              SizedBox(
                                width: 220,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _kind,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Report',
                                  ),
                                  items: reportTitles.entries
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e.key,
                                          child: Text(e.value),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _busy
                                      ? null
                                      : (v) {
                                          if (v != null) {
                                            setState(() {
                                              _kind = v;
                                              _notice = null;
                                            });
                                          }
                                        },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_error != null)
                            _card([
                              Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xff9c2525),
                                ),
                              ),
                            ]),
                          if (_notice != null) _card([Text(_notice!)]),
                          if (_data != null) ...[
                            _card([
                              const Text(
                                'RECORDED BOOKS · USD',
                                style: TextStyle(
                                  color: Color(0xff087e98),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                reportTitles[_kind]!,
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _kind == 'balance_sheet'
                                    ? 'As of ${_data!['as_of']}'
                                    : '${_data!['from_date']} through ${_data!['as_of']}',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${_data!['cash_entry_count']} cash entries · ${_data!['journal_count']} journals in period',
                              ),
                              const SizedBox(height: 12),
                              ..._statement(),
                            ]),
                            _card([
                              const Text(
                                'Before you rely on these reports',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _data!['scope'] as String,
                                style: const TextStyle(height: 1.5),
                              ),
                              for (final w in _data!['warnings'] as List)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Text(
                                    w as String,
                                    style: const TextStyle(
                                      color: Color(0xff875016),
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Text(
                                'Generated ${_data!['generated_at']} · Opening balances: ${(_data!['opening'] as Map?)?['entry_date'] ?? 'not recorded'}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xff566a7f),
                                ),
                              ),
                            ]),
                            Wrap(
                              key: _exportKey,
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                FilledButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _export(_kind),
                                  icon: const Icon(Icons.download_outlined),
                                  label: const Text('Export report CSV'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _export('ledger'),
                                  icon: const Icon(Icons.table_view_outlined),
                                  label: const Text('Export ledger CSV'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Ledger export includes period entries, reversals and current receipt references. Original files stay in the receipt inbox. Journal attachments are not supported yet.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xff566a7f),
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    ),
  );
}
