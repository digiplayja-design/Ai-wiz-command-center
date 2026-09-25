import 'package:flutter/material.dart';
import 'bookkeeping_client.dart';
import 'bookkeeping_models.dart';
import 'ledger_models.dart';

class _Line {
  _Line(this.account, this.side, [String amount = ''])
    : amount = TextEditingController(text: amount);
  String account, side;
  final TextEditingController amount;
}

class LedgerForm extends StatefulWidget {
  const LedgerForm({
    super.key,
    required this.client,
    required this.businessId,
    required this.accounts,
    this.initialKind = 'contribution',
    this.original,
    this.accountOnly = false,
  });
  final BookkeepingClient client;
  final String businessId, initialKind;
  final List<Map<String, dynamic>> accounts;
  final Map<String, dynamic>? original;
  final bool accountOnly;
  @override
  State<LedgerForm> createState() => _LedgerFormState();
}

class _LedgerFormState extends State<LedgerForm> {
  final _form = GlobalKey<FormState>();
  final _date = TextEditingController(text: bookkeepingDate(DateTime.now())),
      _purpose = TextEditingController(),
      _amount = TextEditingController(),
      _name = TextEditingController();
  late String _kind = widget.initialKind;
  String _accountKind = 'cash';
  final _lines = <_Line>[];
  Map<String, dynamic>? _review;
  bool _busy = false, _attempted = false, _denied = false;
  String? _error;
  bool get _advanced => _kind == 'opening' || _kind == 'adjustment';
  bool get _reversing => widget.original != null;
  List<Map<String, dynamic>> _options(String side) => widget.accounts
      .where((a) => ledgerAllowed(_kind, side).contains(a['kind']))
      .toList();
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
    _resetLines();
  }

  void _resetLines() {
    for (final l in _lines) {
      l.amount.dispose();
    }
    _lines.clear();
    for (final side in ['debit', 'credit']) {
      final options = _options(side);
      _lines.add(
        _Line(
          options
                      .where((a) => !_lines.any((l) => l.account == a['code']))
                      .firstOrNull?['code']
                  as String? ??
              '',
          side,
        ),
      );
    }
    if (_kind == 'distribution' &&
        widget.accounts.any((a) => a['code'] == '3100')) {
      _lines[0].account = '3100';
    }
    if (_kind == 'opening' && widget.accounts.any((a) => a['code'] == '3200')) {
      _lines[1].account = '3200';
    }
  }

  void _deny() {
    if (!mounted) return;
    setState(() {
      _denied = true;
      _review = null;
      _error = null;
      for (final c in [
        _date,
        _purpose,
        _amount,
        _name,
        ..._lines.map((l) => l.amount),
      ]) {
        c.clear();
      }
    });
  }

  @override
  void dispose() {
    widget.client.removeAccessDeniedListener(_deny);
    for (final c in [
      _date,
      _purpose,
      _amount,
      _name,
      ..._lines.map((l) => l.amount),
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _prepare() {
    if (!_form.currentState!.validate()) return;
    final base = <String, dynamic>{
      'request_key': bookkeepingRequestKey(),
      'confirmed': true,
    };
    if (widget.accountOnly) {
      base.addAll({'name': _name.text.trim(), 'kind': _accountKind});
    } else if (_reversing) {
      base['reason'] = _purpose.text.trim();
    } else {
      final entries = <Map<String, dynamic>>[];
      final seen = <String>{};
      BigInt debit = BigInt.zero, credit = BigInt.zero;
      for (final l in _lines) {
        if (l.account.isEmpty || !seen.add(l.account)) {
          setState(() => _error = 'Choose a different account for each line.');
          return;
        }
        final amount = _advanced ? l.amount.text : _amount.text;
        final n = ledgerCents(amount);
        if (l.side == 'debit') {
          debit += n;
        } else {
          credit += n;
        }
        entries.add({'account': l.account, 'side': l.side, 'amount': amount});
      }
      if (debit != credit) {
        setState(
          () => _error =
              'Debits and credits must balance. Difference: ${bookkeepingMoney((debit - credit).abs())}.',
        );
        return;
      }
      base.addAll({
        'kind': _kind,
        'entry_date': _date.text,
        'purpose': _purpose.text.trim(),
        'lines': entries,
      });
    }
    setState(() {
      _error = null;
      _review = base;
    });
  }

  Future<void> _save() async {
    if (_busy || _denied || _review == null) return;
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
    });
    try {
      final suffix = widget.accountOnly
          ? 'accounts'
          : _reversing
          ? 'journals/${widget.original!['id']}/reverse'
          : 'journals';
      final d = await widget.client.request(
        'POST',
        '/businesses/${widget.businessId}/ledger/$suffix',
        body: _review,
      );
      if (mounted && !_denied) {
        Navigator.pop(
          context,
          widget.accountOnly
              ? {'account': d['account']}
              : Map<String, dynamic>.from(d['journal'] as Map),
        );
      }
    } catch (e) {
      if (mounted && !_denied) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && !_denied) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _text(
    TextEditingController c,
    String label, {
    bool amount = false,
    bool date = false,
    int max = 500,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: c,
      decoration: InputDecoration(labelText: label),
      maxLength: amount || date ? null : max,
      keyboardType: amount
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      validator: amount
          ? validateBookkeepingAmount
          : date
          ? validateBookkeepingDate
          : (v) => ledgerText(v, max),
    ),
  );
  Widget _account(_Line l, int index) => DropdownButtonFormField<String>(
    key: ValueKey('account-$index-$_kind-${l.side}-${l.account}'),
    initialValue: l.account.isEmpty ? null : l.account,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: _advanced
          ? 'Account ${index + 1}'
          : l.side == 'debit'
          ? 'Debit account (receives value)'
          : 'Credit account (gives value)',
    ),
    items: _options(l.side)
        .map(
          (a) => DropdownMenuItem(
            value: a['code'] as String,
            child: Text(
              '${a['code']} · ${a['name']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(),
    onChanged: (v) => setState(() => l.account = v!),
    validator: (v) => v == null ? 'Choose an account.' : null,
  );
  Widget _line(_Line l, int index) => Container(
    key: ObjectKey(l),
    margin: const EdgeInsets.only(bottom: 16),
    padding: _advanced ? const EdgeInsets.all(12) : EdgeInsets.zero,
    decoration: _advanced
        ? BoxDecoration(
            color: const Color(0xfff3f7fb),
            borderRadius: BorderRadius.circular(12),
          )
        : null,
    child: Column(
      children: [
        _account(l, index),
        if (_advanced) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: l.side,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Balance side'),
            items: const [
              DropdownMenuItem(value: 'debit', child: Text('Debit')),
              DropdownMenuItem(value: 'credit', child: Text('Credit')),
            ],
            onChanged: (v) => setState(() => l.side = v!),
          ),
          const SizedBox(height: 12),
          _text(l.amount, 'Amount ${index + 1} (USD)', amount: true),
          if (_lines.length > 2)
            TextButton(
              onPressed: () => setState(() {
                _lines.remove(l);
                l.amount.dispose();
              }),
              child: Text('Remove line ${index + 1}'),
            ),
        ],
      ],
    ),
  );
  String _accountName(String code) =>
      widget.accounts.where((a) => a['code'] == code).firstOrNull?['name']
          as String? ??
      code;
  Widget _reviewContent() {
    if (widget.accountOnly) {
      return Text(
        '${_review!['name']}\n${ledgerAccountKinds[_review!['kind']]}\n\nThis creates a named manual account. No bank connection is made. Account names and types are fixed after saving.',
      );
    }
    final lines = _reversing
        ? bookkeepingRows(widget.original!['lines'])
              .map(
                (l) => {
                  'account': l['account'],
                  'side': l['debit_cents'] == '0' ? 'debit' : 'credit',
                  'amount': ledgerAmount(
                    l['debit_cents'] == '0'
                        ? l['credit_cents']
                        : l['debit_cents'],
                  ),
                },
              )
              .toList()
        : bookkeepingRows(_review!['lines']);
    BigInt total = BigInt.zero;
    for (final l in lines) {
      if (l['side'] == 'debit') {
        total += ledgerCents(l['amount'] as String);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _reversing
              ? 'Reverse ${ledgerKinds[widget.original!['kind']]}'
              : ledgerKinds[_kind]!,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(
          'Date: ${_reversing ? widget.original!['entry_date'] : _review!['entry_date']}',
        ),
        Text(
          _reversing
              ? _review!['reason'] as String
              : _review!['purpose'] as String,
        ),
        const SizedBox(height: 16),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${l['side'] == 'debit' ? 'Debit' : 'Credit'} ${bookkeepingMoney(ledgerCents(l['amount'] as String))}\n${_accountName(l['account'] as String)}',
            ),
          ),
        Text(
          'Balanced · ${bookkeepingMoney(total)} each side',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xff087e98),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _reversing
              ? 'This offsets every line on the original date. The original remains in history. To correct the details, save a new journal after reversing.'
              : _kind == 'opening'
              ? 'Confirm these are prior closing balances, with no activity duplicated in KORLIX. The app will reject activity dated on or before this date.'
              : 'Confirm the date, accounts and amounts. A saved journal is permanent; corrections use a reversal.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _review != null
          ? 'Review ${widget.accountOnly
                ? 'account'
                : _reversing
                ? 'reversal'
                : 'journal'}'
          : widget.accountOnly
          ? 'Add account'
          : _reversing
          ? 'Reverse journal'
          : _kind == 'opening'
          ? 'Opening balances'
          : 'Record journal',
    ),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: _denied
            ? const Text('Session changed. Reopen Bookkeeping.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_review != null)
                    _reviewContent()
                  else
                    Form(
                      key: _form,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.accountOnly) ...[
                            _text(_name, 'Account name', max: 80),
                            DropdownButtonFormField<String>(
                              initialValue: _accountKind,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Account type',
                              ),
                              items: ledgerAccountKinds.entries
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(e.value),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _accountKind = v!),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Use a distinct account name. Names and types are fixed after saving; no bank credentials are needed.',
                            ),
                          ] else if (_reversing) ...[
                            Text(
                              '${widget.original!['entry_date']} · ${widget.original!['purpose']}',
                            ),
                            const SizedBox(height: 16),
                            _text(_purpose, 'Reason for reversal'),
                          ] else ...[
                            if (widget.initialKind != 'opening') ...[
                              DropdownButtonFormField<String>(
                                initialValue: _kind,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Transaction type',
                                ),
                                items: ledgerKinds.entries
                                    .where(
                                      (e) =>
                                          e.key != 'opening' &&
                                          e.key != 'reversal',
                                    )
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e.key,
                                        child: Text(
                                          e.value,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => setState(() {
                                  _kind = v!;
                                  _error = null;
                                  _resetLines();
                                }),
                              ),
                              const SizedBox(height: 16),
                            ],
                            Text(
                              ledgerHelp(_kind),
                              style: const TextStyle(
                                color: Color(0xff566a7f),
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _text(
                              _date,
                              _kind == 'opening'
                                  ? 'Prior closing date (YYYY-MM-DD)'
                                  : 'Journal date (YYYY-MM-DD)',
                              date: true,
                            ),
                            _text(_purpose, 'Description'),
                            if (!_advanced)
                              _text(_amount, 'Amount (USD)', amount: true),
                            for (int i = 0; i < _lines.length; i++)
                              _line(_lines[i], i),
                            if (_advanced && _lines.length < 100)
                              TextButton.icon(
                                onPressed: () => setState(
                                  () => _lines.add(_Line('', 'debit')),
                                ),
                                icon: const Icon(Icons.add),
                                label: const Text('Add balance line'),
                              ),
                          ],
                        ],
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '$_error${_attempted ? ' Retry preserves the reviewed request. You may also close and refresh.' : ''}',
                        style: const TextStyle(color: Color(0xff9c2525)),
                      ),
                    ),
                ],
              ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      if (!_denied && _review != null && !_attempted)
        TextButton(
          onPressed: () => setState(() => _review = null),
          child: const Text('Edit'),
        ),
      if (!_denied)
        FilledButton(
          onPressed: _busy
              ? null
              : _review == null
              ? _prepare
              : _save,
          child: Text(
            _busy
                ? 'Saving…'
                : _review == null
                ? 'Review'
                : _attempted
                ? 'Retry same save'
                : 'Confirm and save',
          ),
        ),
    ],
  );
}
