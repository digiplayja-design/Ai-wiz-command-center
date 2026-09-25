import 'package:flutter/material.dart';
import 'bookkeeping_client.dart';
import 'bookkeeping_models.dart';

class BookkeepingProfileDialog extends StatefulWidget {
  const BookkeepingProfileDialog({
    super.key,
    required this.client,
    this.business,
  });
  final BookkeepingClient client;
  final Map<String, dynamic>? business;
  @override
  State<BookkeepingProfileDialog> createState() =>
      _BookkeepingProfileDialogState();
}

class _BookkeepingProfileDialogState extends State<BookkeepingProfileDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.business?['name'] ?? '',
  );
  late String _structure =
      widget.business?['legal_structure'] ?? 'sole_proprietor';
  late String _treatment = widget.business?['tax_treatment'] ?? 'unsure';
  late bool _contractor = widget.business?['contractor_income'] == true;
  final _requestKey = bookkeepingRequestKey();
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _submitted;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final payload =
        _submitted ??
        {
          'name': _name.text.trim(),
          'legal_structure': _structure,
          'tax_treatment': _treatment,
          'contractor_income': _contractor,
          if (widget.business == null)
            'request_key': _requestKey
          else
            'version': widget.business!['version'],
        };
    setState(() {
      _submitted = payload;
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.client.request(
        widget.business == null ? 'POST' : 'PUT',
        '/businesses${widget.business == null ? '' : '/${widget.business!['id']}'}',
        body: payload,
      );
      if (mounted) Navigator.pop(context, result['business']);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.business == null ? 'Add your business' : 'Business profile',
    ),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Keep a separate recordbook for each business. Your legal structure and tax treatment may differ.',
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _name,
                enabled: _submitted == null,
                decoration: const InputDecoration(labelText: 'Business name'),
                maxLength: 120,
                validator: (s) => s == null || s.trim().isEmpty
                    ? 'Enter your business name.'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _structure,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Legal structure'),
                items: businessStructures.entries
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: _submitted != null
                    ? null
                    : (s) => setState(() {
                        _structure = s!;
                        if (!allowedTreatments(s).contains(_treatment)) {
                          _treatment = 'unsure';
                        }
                      }),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                key: ValueKey('treatment-$_structure-$_treatment'),
                initialValue: _treatment,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Federal tax treatment',
                ),
                items: allowedTreatments(_structure)
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(
                          taxTreatments[s]!,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _submitted != null
                    ? null
                    : (s) => setState(() => _treatment = s!),
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('I receive contractor / 1099 income'),
                subtitle: const Text(
                  '1099 income is not a legal business structure.',
                ),
                value: _contractor,
                onChanged: _submitted != null
                    ? null
                    : (v) => setState(() => _contractor = v!),
              ),
              const SizedBox(height: 10),
              const Text(
                'This first release records manual USD cash activity. Choosing a tax treatment does not make a tax election.',
                style: TextStyle(fontSize: 12, color: Color(0xff506279)),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    '$_error\nYou can retry this same request or close and refresh.',
                    style: const TextStyle(color: Color(0xff9c2525)),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(
          _busy
              ? 'Saving…'
              : _submitted != null
              ? 'Retry same save'
              : 'Save business',
        ),
      ),
    ],
  );
}

class BookkeepingEntryDialog extends StatefulWidget {
  const BookkeepingEntryDialog({
    super.key,
    required this.client,
    required this.businessId,
    required this.categories,
    required this.kind,
    this.original,
    this.receipt,
    this.suggestions,
  });
  final BookkeepingClient client;
  final String businessId, kind;
  final List<Map<String, dynamic>> categories;
  final Map<String, dynamic>? original, receipt, suggestions;
  @override
  State<BookkeepingEntryDialog> createState() => _BookkeepingEntryDialogState();
}

class _BookkeepingEntryDialogState extends State<BookkeepingEntryDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController(),
      _party = TextEditingController(),
      _purpose = TextEditingController(),
      _reference = TextEditingController();
  late final _date = TextEditingController(
    text: bookkeepingDate(DateTime.now()),
  );
  String? _category, _error;
  bool _busy = false, _attempted = false, _receiptReviewed = false;
  Map<String, dynamic>? _review;
  bool get _reversing => widget.original != null;
  List<Map<String, dynamic>> get _categories =>
      widget.categories.where((c) => c['kind'] == widget.kind).toList();
  @override
  void initState() {
    super.initState();
    _category = _categories.isEmpty
        ? null
        : _categories.first['code'] as String;
    final data = widget.suggestions;
    if (data != null) {
      if (data['currency'] == 'USD' &&
          validateBookkeepingAmount(data['total'] as String?) == null) {
        _amount.text = data['total'] as String;
      }
      _party.text = data['vendor'] as String? ?? '';
      if (validateBookkeepingDate(data['document_date'] as String?) == null) {
        _date.text = data['document_date'] as String;
      }
    }
    if (widget.receipt != null) {
      _reference.text = (widget.receipt!['filename'] as String).substring(
        0,
        (widget.receipt!['filename'] as String).length.clamp(0, 160),
      );
    }
  }

  @override
  void dispose() {
    for (final c in [_amount, _party, _purpose, _reference, _date]) {
      c.dispose();
    }
    super.dispose();
  }

  void _prepare() {
    if (!_form.currentState!.validate()) return;
    if (widget.receipt != null && !_receiptReviewed) {
      setState(
        () => _error = 'Check the receipt details before reviewing this entry.',
      );
      return;
    }
    setState(() {
      _error = null;
      _review = {
        'request_key': bookkeepingRequestKey(),
        'confirmed': true,
        if (widget.receipt != null) 'receipt_reviewed': true,
        if (_reversing)
          'reason': _purpose.text.trim()
        else ...{
          'kind': widget.kind,
          'amount': _amount.text,
          'entry_date': _date.text,
          'category': _category,
          'counterparty': _party.text.trim(),
          'purpose': _purpose.text.trim(),
          'receipt_reference': _reference.text.trim(),
        },
      };
    });
  }

  Future<void> _save() async {
    if (_busy || _review == null) return;
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
    });
    try {
      await widget.client.request(
        'POST',
        widget.receipt != null
            ? '/businesses/${widget.businessId}/receipts/${widget.receipt!['id']}/entries'
            : '/businesses/${widget.businessId}/entries${_reversing ? '/${widget.original!['id']}/reverse' : ''}',
        body: _review,
      );
      if (mounted) {
        Navigator.pop(context, {
          'entry_date': _reversing
              ? widget.original!['entry_date']
              : _review!['entry_date'],
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.kind == 'income' ? 'income' : 'expense';
    return AlertDialog(
      title: Text(
        _reversing
            ? 'Reverse entry'
            : _review == null
            ? 'Record $label'
            : 'Review $label',
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: _review != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _reversing
                          ? 'Reverse ${bookkeepingMoney(widget.original!['amount_cents'])}'
                          : '\$${_review!['amount']} USD',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!_reversing) ...[
                      if (widget.receipt != null)
                        Text(
                          'Attached original: ${widget.receipt!['filename']}',
                        ),
                      Text('Date received / paid: ${_review!['entry_date']}'),
                      Text(
                        'Category: ${_categories.firstWhere((c) => c['code'] == _category)['name']}',
                      ),
                      if (_party.text.trim().isNotEmpty)
                        Text('Customer / vendor: ${_party.text.trim()}'),
                      if (_reference.text.trim().isNotEmpty)
                        Text('Receipt reference: ${_reference.text.trim()}'),
                    ],
                    const SizedBox(height: 12),
                    Text(_purpose.text.trim()),
                    const SizedBox(height: 18),
                    Text(
                      _reversing
                          ? 'The original stays in your history. An equal offset is recorded on ${widget.original!['entry_date']}, changing that month’s totals. Record a replacement separately if needed.'
                          : 'Save this once the amount, date and category are correct. Saved entries stay in your history; use a reversal to correct a mistake.',
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          '$_error\nRetry uses the same request to avoid duplicate entries. You can also close and refresh.',
                          style: const TextStyle(color: Color(0xff9c2525)),
                        ),
                      ),
                  ],
                )
              : Form(
                  key: _form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_reversing) ...[
                        Text(
                          '${bookkeepingMoney(widget.original!['amount_cents'])} · ${widget.original!['entry_date']}',
                        ),
                        const SizedBox(height: 8),
                        Text(widget.original!['purpose'] as String),
                        const SizedBox(height: 16),
                      ] else ...[
                        const Text(
                          'Record money actually received or paid for business operations. Use Accounts & journals for loans, owner funding, transfers and asset purchases. This form records activity through Recorded cash control (1000).',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xff506279),
                          ),
                        ),
                        if (widget.receipt != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Receipt: ${widget.receipt!['filename']}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Text(
                            'Verify the currency and actual payment date. Unpaid invoices do not belong in cash activity. Attaching an original preserves it with your entry history.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _amount,
                          decoration: const InputDecoration(
                            labelText: 'Amount (USD)',
                            prefixText: '\$ ',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: validateBookkeepingAmount,
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _date,
                          decoration: const InputDecoration(
                            labelText: 'Date received / paid',
                            hintText: 'YYYY-MM-DD',
                          ),
                          validator: validateBookkeepingDate,
                        ),
                        const SizedBox(height: 18),
                        DropdownButtonFormField<String>(
                          initialValue: _category,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                          ),
                          items: _categories
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c['code'] as String,
                                  child: Text(
                                    c['name'] as String,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (c) => _category = c,
                          validator: (c) =>
                              c == null ? 'Choose a category.' : null,
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _party,
                          decoration: const InputDecoration(
                            labelText: 'Customer / vendor (optional)',
                          ),
                          maxLength: 160,
                        ),
                        const SizedBox(height: 8),
                      ],
                      TextFormField(
                        controller: _purpose,
                        decoration: InputDecoration(
                          labelText: _reversing
                              ? 'Reason for correction'
                              : 'Business purpose',
                        ),
                        minLines: 2,
                        maxLines: 4,
                        maxLength: 500,
                        validator: (s) => s == null || s.trim().isEmpty
                            ? 'Describe why this entry was made.'
                            : null,
                      ),
                      if (!_reversing) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _reference,
                          decoration: const InputDecoration(
                            labelText: 'Receipt / invoice reference (optional)',
                            helperText:
                                'Attach original files from the receipt inbox.',
                            helperMaxLines: 2,
                          ),
                          maxLength: 160,
                        ),
                        const Text(
                          'Categories organize your records; they do not determine tax deductibility.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xff506279),
                          ),
                        ),
                        if (widget.receipt != null)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'I checked the receipt, amount, currency and date paid / received.',
                            ),
                            value: _receiptReviewed,
                            onChanged: (v) => setState(() {
                              _receiptReviewed = v!;
                              _error = null;
                            }),
                          ),
                      ],
                      if (_error != null)
                        Text(
                          _error!,
                          style: const TextStyle(color: Color(0xff9c2525)),
                        ),
                    ],
                  ),
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (_review != null && !_attempted)
          TextButton(
            onPressed: () => setState(() => _review = null),
            child: const Text('Edit'),
          ),
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
                ? 'Review entry'
                : _attempted
                ? 'Retry same save'
                : _reversing
                ? 'Confirm reversal'
                : 'Confirm and save',
          ),
        ),
      ],
    );
  }
}
