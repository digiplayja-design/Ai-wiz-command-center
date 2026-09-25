import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'bookkeeping_client.dart';
import 'bookkeeping_csv_save.dart';
import 'bookkeeping_models.dart';
import 'ledger_models.dart';
import 'ledger_form.dart';

class BookkeepingLedger extends StatefulWidget {
  const BookkeepingLedger({
    super.key,
    required this.client,
    required this.businessId,
    required this.businessName,
    this.onExport,
  });
  final BookkeepingClient client;
  final String businessId, businessName;
  final Future<void> Function(String csv, String filename)? onExport;
  @override
  State<BookkeepingLedger> createState() => _BookkeepingLedgerState();
}

class _BookkeepingLedgerState extends State<BookkeepingLedger> {
  final _month = TextEditingController(
    text: bookkeepingDate(DateTime.now()).substring(0, 7),
  );
  final _exportKey = GlobalKey();
  late String _selectedMonth = _month.text;
  Map<String, dynamic>? _data;
  bool _busy = false, _denied = false;
  String? _error;
  int _offset = 0;
  bool get _alive => mounted && !_denied;
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
        _data = null;
        _error = null;
        _month.clear();
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
    if (!_alive) return;
    setState(() {
      _busy = true;
      _error = null;
      _data = null;
    });
    try {
      final d = await widget.client.request(
        'GET',
        '/businesses/${widget.businessId}/ledger',
        query: {'month': _selectedMonth, 'offset': '$_offset'},
      );
      if (_alive) {
        setState(() => _data = d);
      }
    } catch (e) {
      if (_alive) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (_alive) {
        setState(() => _busy = false);
      }
    }
  }

  void _apply() {
    if (!RegExp(r'^20\d\d-(0[1-9]|1[0-2])$').hasMatch(_month.text)) {
      setState(() => _error = 'Use YYYY-MM between 2000 and 2099.');
      return;
    }
    _selectedMonth = _month.text;
    _offset = 0;
    unawaited(_load());
  }

  Future<void> _entry({
    String kind = 'contribution',
    Map<String, dynamic>? original,
    bool account = false,
  }) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LedgerForm(
        client: widget.client,
        businessId: widget.businessId,
        accounts: bookkeepingRows(_data?['accounts']),
        initialKind: kind,
        original: original,
        accountOnly: account,
      ),
    );
    if (!_alive) return;
    if (result?['entry_date'] != null) {
      _selectedMonth = (result!['entry_date'] as String).substring(0, 7);
      _month.text = _selectedMonth;
      _offset = 0;
    }
    await _load();
  }

  Future<void> _export() async {
    final box = _exportKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await widget.client.request(
        'GET',
        '/businesses/${widget.businessId}/ledger/export',
        query: {'month': _selectedMonth},
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
    } catch (e) {
      if (_alive) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (_alive) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _card(List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xfff3f7fb),
      border: Border.all(color: const Color(0xffdde6ee)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
  Widget _journal(Map<String, dynamic> j, List<Map<String, dynamic>> accounts) {
    final reverse = j['kind'] == 'reversal',
        reversed = j['reversed_by'] != null;
    return _card([
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            ledgerKinds[j['kind']] ?? 'Journal',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          Text('${j['entry_date']}'),
          if (reverse || reversed)
            Text(
              reverse ? 'Offset entry' : 'Reversed',
              style: const TextStyle(color: Color(0xff875016)),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text(j['purpose'] as String),
      const SizedBox(height: 10),
      for (final l in bookkeepingRows(j['lines']))
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '${l['debit_cents'] == '0' ? 'Credit' : 'Debit'} ${bookkeepingMoney(l['debit_cents'] == '0' ? l['credit_cents'] : l['debit_cents'])} · ${accounts.where((a) => a['code'] == l['account']).firstOrNull?['name'] ?? l['account']}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      if (!reverse && !reversed)
        TextButton.icon(
          onPressed: _busy ? null : () => _entry(original: j),
          icon: const Icon(Icons.undo, size: 16),
          label: const Text('Reverse journal'),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = bookkeepingRows(_data?['accounts']),
        journals = bookkeepingRows(_data?['journals']);
    final opening = _data?['opening'] as Map?;
    final count = _data?['journal_count'] as int? ?? 0;
    BigInt debits = BigInt.zero, credits = BigInt.zero;
    for (final a in accounts) {
      final n = BigInt.parse(a['balance_cents'] as String);
      if (n.isNegative) {
        credits -= n;
      } else {
        debits += n;
      }
    }
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 980,
        height: math.max(
          260,
          math.min(850, MediaQuery.sizeOf(context).height - 40),
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
                            'Accounts & journals',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close ledger',
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
                    Expanded(
                      child: ListView(
                        children: [
                          const Text(
                            'Give every business dollar a place.',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Track owner funds, borrowing, assets and transfers. Balances include recorded operating cash entries and journal history.',
                            style: TextStyle(height: 1.5),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton.icon(
                                onPressed: _busy || _data == null
                                    ? null
                                    : () => _entry(),
                                icon: const Icon(Icons.add),
                                label: const Text('Record journal'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy || _data == null
                                    ? null
                                    : () => _entry(account: true),
                                icon: const Icon(
                                  Icons.account_balance_outlined,
                                ),
                                label: const Text('Add account'),
                              ),
                              OutlinedButton(
                                onPressed:
                                    _busy || _data == null || opening != null
                                    ? null
                                    : () => _entry(kind: 'opening'),
                                child: const Text('Set opening balances'),
                              ),
                              OutlinedButton.icon(
                                key: _exportKey,
                                onPressed: _busy || _data == null
                                    ? null
                                    : _export,
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('Export combined ledger'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: 190,
                                child: TextField(
                                  controller: _month,
                                  enabled: !_busy,
                                  decoration: const InputDecoration(
                                    labelText: 'Ledger month (YYYY-MM)',
                                  ),
                                  onSubmitted: (_) => _apply(),
                                ),
                              ),
                              FilledButton(
                                onPressed: _busy ? null : _apply,
                                child: const Text('Apply month'),
                              ),
                              TextButton.icon(
                                onPressed: _busy ? null : _load,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Refresh ledger'),
                              ),
                            ],
                          ),
                          if (_busy)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: LinearProgressIndicator(),
                            ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xff9c2525),
                                ),
                              ),
                            ),
                          if (_data != null) ...[
                            const SizedBox(height: 18),
                            _card([
                              Text(
                                opening == null
                                    ? 'No opening balances recorded'
                                    : 'Opening balances: ${opening['entry_date']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                opening == null
                                    ? 'For an existing business, enter prior closing balances before treating the account totals as complete. For a new business, record actual startup funding.'
                                    : 'Activity must be dated after this closing date. To replace opening balances, reverse the original document first.',
                              ),
                              if (opening != null)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () {
                                          _selectedMonth =
                                              (opening['entry_date'] as String)
                                                  .substring(0, 7);
                                          _month.text = _selectedMonth;
                                          _offset = 0;
                                          unawaited(_load());
                                        },
                                  child: const Text('View opening month'),
                                ),
                            ]),
                            Text(
                              'Recorded balances as of ${_data!['as_of']}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Debit and credit indicate the balance side. These totals come from your records; they are not reconciled bank balances or a complete financial statement.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xff566a7f),
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _card([
                              Wrap(
                                spacing: 24,
                                runSpacing: 10,
                                children: [
                                  Text(
                                    'Debits ${bookkeepingMoney(debits)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    'Credits ${bookkeepingMoney(credits)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    debits == credits
                                        ? 'Balanced'
                                        : 'Difference ${bookkeepingMoney((debits - credits).abs())}',
                                    style: TextStyle(
                                      color: debits == credits
                                          ? const Color(0xff087e98)
                                          : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ]),
                            ExpansionTile(
                              title: Text(
                                'Chart of accounts (${accounts.length})',
                              ),
                              initiallyExpanded: true,
                              tilePadding: EdgeInsets.zero,
                              children: [
                                for (final a in accounts)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 9,
                                    ),
                                    child: LayoutBuilder(
                                      builder: (context, size) {
                                        final title = Text(
                                          '${a['code']} · ${a['name']}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        );
                                        final balance = Text(
                                          ledgerBalance(a['balance_cents']),
                                          style: const TextStyle(
                                            color: Color(0xff087e98),
                                          ),
                                        );
                                        return size.maxWidth < 500
                                            ? Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [title, balance],
                                              )
                                            : Row(
                                                children: [
                                                  Expanded(child: title),
                                                  const SizedBox(width: 16),
                                                  balance,
                                                ],
                                              );
                                      },
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Journal history · $_selectedMonth',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Operating income and expense history remains on the dashboard. Combined CSV includes both histories and all reversals.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xff566a7f),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (journals.isEmpty)
                              _card([
                                const Text(
                                  'No journals in this month. Record owner funds, a loan, an asset purchase or a transfer to get started.',
                                ),
                              ]),
                            for (final j in journals) _journal(j, accounts),
                            if (count > 50)
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    '${_offset + 1}–${math.min(_offset + journals.length, count)} of $count',
                                  ),
                                  TextButton(
                                    onPressed: _busy || _offset == 0
                                        ? null
                                        : () {
                                            _offset = math.max(0, _offset - 50);
                                            unawaited(_load());
                                          },
                                    child: const Text('Previous journals'),
                                  ),
                                  TextButton(
                                    onPressed: _busy || _offset + 50 >= count
                                        ? null
                                        : () {
                                            _offset += 50;
                                            unawaited(_load());
                                          },
                                    child: const Text('Next journals'),
                                  ),
                                ],
                              ),
                          ],
                          const SizedBox(height: 18),
                          const Text(
                            'Manual USD records · Choose named cash accounts in the income and expense forms. Named accounts also support transfers and journals. Interest, fees and other operating costs use the main expense form. Open Reports on the dashboard for recorded financial statements and ledger exports. Bank reconciliation and depreciation are not performed.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xff566a7f),
                              height: 1.5,
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
}
