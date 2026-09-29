import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'bookkeeping_client.dart';
import 'bookkeeping_models.dart';
import 'file_reader.dart';
import 'bookkeeping_ui.dart';

List<String> statementHeaders(String text) {
  final value = text.startsWith('\uFEFF') ? text.substring(1) : text;
  final result = <String>[];
  var field = '', quoted = false, closed = false;
  for (var i = 0; i < value.length; i++) {
    final ch = value[i];
    if (quoted) {
      if (ch == '"' && i + 1 < value.length && value[i + 1] == '"') {
        field += '"';
        i++;
      } else if (ch == '"') {
        quoted = false;
        closed = true;
      } else {
        field += ch;
      }
    } else if (ch == '"') {
      if (field.isNotEmpty || closed) {
        throw const FormatException('Invalid CSV header.');
      }
      quoted = true;
    } else if (ch == ',' || ch == '\n' || ch == '\r') {
      result.add(field.trim());
      field = '';
      closed = false;
      if (ch != ',') break;
    } else {
      if (closed) throw const FormatException('Invalid CSV header.');
      field += ch;
    }
    if (i == value.length - 1) result.add(field.trim());
  }
  if (quoted ||
      result.length < 3 ||
      result.any((h) => h.isEmpty || h.length > 80) ||
      result.map((h) => h.toLowerCase()).toSet().length != result.length) {
    throw const FormatException(
      'Choose a CSV with distinct date, description and amount headers.',
    );
  }
  return result;
}

class BookkeepingStatementPreview extends StatefulWidget {
  const BookkeepingStatementPreview({
    super.key,
    required this.client,
    required this.businessId,
    required this.cashAccounts,
    this.pickCsv,
  });
  final BookkeepingClient client;
  final String businessId;
  final List<Map<String, dynamic>> cashAccounts;
  final Future<(String, Uint8List)?> Function()? pickCsv;
  @override
  State<BookkeepingStatementPreview> createState() =>
      _BookkeepingStatementPreviewState();
}

class _BookkeepingStatementPreviewState
    extends State<BookkeepingStatementPreview> {
  String? _csv,
      _filename,
      _error,
      _account,
      _date,
      _description,
      _amount,
      _debit,
      _credit;
  String _duplicateReason = '', _overlapReason = '';
  bool _overlapConfirmed = false;
  String _year = DateTime.now().year.toString();
  List<String> _headers = [];
  Map<String, dynamic>? _preview;
  bool _busy = false,
      _split = false,
      _denied = false,
      _importConfirmed = false,
      _duplicatesConfirmed = false;
  Map<String, dynamic>? _pendingImport, _imported;
  int _operation = 0;
  @override
  void initState() {
    super.initState();
    _account = widget.cashAccounts.isEmpty
        ? null
        : widget.cashAccounts.first['code'] as String;
    widget.client.addAccessDeniedListener(_deny);
  }

  void _deny() {
    if (!mounted) return;
    setState(() {
      _denied = true;
      _operation++;
      _csv = null;
      _preview = null;
      _pendingImport = null;
      _imported = null;
      _headers = [];
      _duplicateReason = '';
      _overlapReason = '';
      _overlapConfirmed = false;
      _duplicatesConfirmed = false;
      _error = null;
      _busy = false;
    });
  }

  @override
  void dispose() {
    _operation++;
    widget.client.removeAccessDeniedListener(_deny);
    super.dispose();
  }

  Future<(String, Uint8List)?> _pick() async {
    if (widget.pickCsv != null) return widget.pickCsv!();
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      allowMultiple: false,
      withData: false,
      withReadStream: true,
    );
    if (selected == null || selected.files.isEmpty) return null;
    final file = selected.files.single;
    return (
      file.name,
      await readBookkeepingFile(
        advertisedSize: file.size,
        maxBytes: 256 * 1024,
        limitMessage: 'Choose a CSV statement up to 256 KB.',
        bytes: file.bytes,
        stream: file.readStream,
      ),
    );
  }

  Future<void> _select() async {
    if (_busy || _denied || _pendingImport != null) return;
    final op = ++_operation;
    setState(() {
      _busy = true;
      _error = null;
      _csv = null;
      _preview = null;
      _filename = null;
      _headers = [];
      _date = _description = _amount = _debit = _credit = null;
      _duplicateReason = '';
      _overlapReason = '';
      _overlapConfirmed = false;
      _duplicatesConfirmed = false;
      _importConfirmed = false;
    });
    try {
      final picked = await _pick();
      if (!mounted || _denied || op != _operation) return;
      if (picked != null) {
        if (picked.$2.isEmpty || picked.$2.length > 256 * 1024) {
          throw const BookkeepingException(
            'Choose a CSV statement up to 256 KB.',
          );
        }
        String text;
        try {
          text = utf8.decode(picked.$2, allowMalformed: false);
        } on FormatException {
          throw const BookkeepingException(
            'Export your statement as a UTF-8 CSV and choose the file again.',
          );
        }
        final headers = statementHeaders(text);
        setState(() {
          _filename = picked.$1;
          _csv = text;
          _headers = headers;
          _date = _description = _amount = _debit = _credit = null;
          _duplicateReason = '';
          _overlapReason = '';
          _overlapConfirmed = false;
          _duplicatesConfirmed = false;
        });
      }
    } catch (e) {
      if (mounted && !_denied && op == _operation) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted && !_denied && op == _operation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _review() async {
    if (_busy || _denied || _csv == null || _pendingImport != null) return;
    final fields = [
      _date,
      _description,
      ...(_split ? [_debit, _credit] : [_amount]),
    ];
    if (_account == null ||
        fields.any((v) => v == null) ||
        fields.toSet().length != fields.length) {
      setState(
        () => _error =
            'Choose a cash account and map distinct statement columns.',
      );
      return;
    }
    if (!RegExp(r'^20\d\d$').hasMatch(_year)) {
      setState(() => _error = 'Use a year from 2000 to 2099.');
      return;
    }
    final op = ++_operation;
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
      _importConfirmed = false;
      _duplicateReason = '';
      _overlapReason = '';
      _overlapConfirmed = false;
      _duplicatesConfirmed = false;
    });
    try {
      final result = await widget.client.request(
        'POST',
        '/businesses/${widget.businessId}/statements/preview',
        body: {
          'csv': _csv,
          'cash_account': _account,
          'year': _year,
          'mapping': {
            'date': _date,
            'description': _description,
            if (_split) ...{
              'debit': _debit,
              'credit': _credit,
            } else
              'amount': _amount,
          },
        },
      );
      if (mounted && !_denied && op == _operation) {
        setState(() => _preview = result);
      }
    } catch (e) {
      if (mounted && !_denied && op == _operation) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted && !_denied && op == _operation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _import() async {
    if (_busy || _denied || _preview == null || _imported != null) return;
    if (_preview!['invalid_count'] != 0 || !_importConfirmed) {
      setState(
        () => _error =
            'Fix invalid rows and confirm your review before importing.',
      );
      return;
    }
    if (_preview!['duplicate_count'] != 0 &&
        (!_duplicatesConfirmed ||
            _duplicateReason.trim().length < 10 ||
            _duplicateReason.trim().length > 500)) {
      setState(
        () => _error =
            'Check each repeated line against the original bank statement, confirm they are distinct transactions, and enter a reason of 10–500 characters.',
      );
      return;
    }
    if (_preview!['fully_overlapping'] == true) {
      setState(
        () => _error =
            'Every row already appears in saved statements. Review the existing imports.',
      );
      return;
    }
    if ((_preview!['overlap_count'] as int? ?? 0) > 0 &&
        (!_overlapConfirmed ||
            _overlapReason.trim().length < 10 ||
            _overlapReason.trim().length > 500)) {
      setState(
        () => _error =
            'Review the overlapping rows and explain why this partial overlap should be retained.',
      );
      return;
    }
    _pendingImport ??= {
      'csv': _csv,
      'cash_account': _account,
      'year': _year,
      'mapping': {
        'date': _date,
        'description': _description,
        if (_split) ...{
          'debit': _debit,
          'credit': _credit,
        } else
          'amount': _amount,
      },
      if ((_preview!['overlap_count'] as int? ?? 0) > 0) ...{
        'overlap_review_reason': _overlapReason.trim(),
        'overlap_snapshot': _preview!['overlap_snapshot'],
      },
      'request_key': bookkeepingRequestKey(),
      'confirmed': true,
      if (_preview!['duplicate_count'] != 0)
        'duplicate_review_reason': _duplicateReason.trim(),
    };
    final op = ++_operation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.client.request(
        'POST',
        '/businesses/${widget.businessId}/statements/import',
        body: _pendingImport,
      );
      if (mounted && !_denied && op == _operation) {
        setState(() {
          _imported = Map<String, dynamic>.from(data['statement'] as Map);
          _pendingImport = null;
        });
      }
    } catch (e) {
      if (mounted && !_denied && op == _operation) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted && !_denied && op == _operation) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _column(String label, String? value, void Function(String?) change) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: _headers
              .map(
                (h) => DropdownMenuItem(
                  value: h,
                  child: Text(h, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: _busy || _pendingImport != null || _imported != null
              ? null
              : (v) => setState(() {
                  change(v);
                  _preview = null;
                }),
        ),
      );
  @override
  Widget build(BuildContext context) => BookkeepingDialog(
    client: widget.client,
    busy: _busy && _pendingImport != null,
    title: const Text('Statement CSV preview'),
    content: SizedBox(
      width: 650,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose a bank statement CSV, map its columns and review possible matches. This preview does not import, post or reconcile transactions.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed:
                  _busy ||
                      _denied ||
                      _pendingImport != null ||
                      _imported != null
                  ? null
                  : _select,
              icon: const Icon(Icons.upload_file),
              label: const Text('Choose CSV'),
            ),
            if (_filename != null && !_denied)
              Text(_filename!, overflow: TextOverflow.ellipsis),
            if (_csv != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: DropdownButtonFormField<String>(
                  initialValue: _account,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Recorded cash account',
                  ),
                  items: widget.cashAccounts
                      .map(
                        (a) => DropdownMenuItem(
                          value: a['code'] as String,
                          child: Text(
                            '${a['name']} (${a['code']})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged:
                      _busy || _pendingImport != null || _imported != null
                      ? null
                      : (v) => setState(() {
                          _account = v;
                          _preview = null;
                        }),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _year,
                decoration: const InputDecoration(
                  labelText: 'Calendar year (YYYY)',
                ),
                keyboardType: TextInputType.number,
                maxLength: 4,
                enabled: !_busy && _pendingImport == null && _imported == null,
                onChanged: (v) => setState(() {
                  _year = v;
                  _preview = null;
                }),
              ),
              _column('Date column (YYYY-MM-DD)', _date, (v) => _date = v),
              _column(
                'Description column',
                _description,
                (v) => _description = v,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Separate debit and credit columns'),
                value: _split,
                onChanged: _busy || _pendingImport != null || _imported != null
                    ? null
                    : (v) => setState(() {
                        _split = v;
                        _preview = null;
                      }),
              ),
              Text(
                _split
                    ? 'Debit/withdrawal reduces cash; credit/deposit adds cash. Use a blank or 0 in the unused column.'
                    : 'Use negative amounts for withdrawals and positive amounts for deposits.',
              ),
              const Text(
                'Use USD numbers such as 1234.56 and dates as YYYY-MM-DD.',
              ),
              if (_split) ...[
                _column('Debit / withdrawal column', _debit, (v) => _debit = v),
                _column('Credit / deposit column', _credit, (v) => _credit = v),
              ] else
                _column('Signed amount column', _amount, (v) => _amount = v),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xff9c2525)),
                ),
              ),
            if (_preview != null) ...[
              const SizedBox(height: 18),
              Text(
                '${_preview!['row_count']} rows · ${_preview!['invalid_count']} invalid · ${_preview!['duplicate_count']} duplicates',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text(
                'Suggestions are based on matching amount and a date within three days. Check the source statement before correcting your books.',
              ),
              for (final row in bookkeepingRows(_preview!['entries']).take(500))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Line ${row['line']}: ${row['description'] ?? row['error']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    row['error'] as String? ??
                        '${row['date']} · ${row['amount_cents']} cents · ${row['status']} · ${row['candidate_total'] ?? (row['candidates'] as List?)?.length ?? 0} candidate(s)',
                  ),
                ),
              if (_preview!['duplicate_count'] != 0 && _imported == null) ...[
                const Text(
                  'Repeated rows may be separate bank transactions. Compare every flagged line with the original statement. Also review any overlap with earlier imports below.',
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'I checked the repeated lines and confirm they are distinct transactions.',
                  ),
                  value: _duplicatesConfirmed,
                  onChanged: _busy || _pendingImport != null
                      ? null
                      : (v) => setState(() => _duplicatesConfirmed = v == true),
                ),
                TextField(
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Reason for repeated rows',
                  ),
                  enabled: !_busy && _pendingImport == null,
                  onChanged: (v) => _duplicateReason = v,
                ),
              ],
              if (_preview!['fully_overlapping'] == true)
                const Text(
                  'Every row already appears in saved statements. Open the existing import instead.',
                ),
              if ((_preview!['overlap_count'] as int? ?? 0) > 0 &&
                  _imported == null) ...[
                Text(
                  '${_preview!['overlap_count']} rows overlap earlier imports. Imported rows do not post money. Check the original statements before retaining overlapping source rows.',
                ),
                for (final overlap in bookkeepingRows(
                  _preview!['overlap_snapshot'],
                ))
                  Text(
                    'Line ${overlap['line']} overlaps statement ${overlap['statement_id']}, line ${overlap['existing_line']}',
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'I reviewed these overlaps against the original statements.',
                  ),
                  value: _overlapConfirmed,
                  onChanged: _busy || _pendingImport != null
                      ? null
                      : (v) => setState(() => _overlapConfirmed = v == true),
                ),
                TextField(
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  enabled: !_busy && _pendingImport == null,
                  decoration: const InputDecoration(
                    labelText: 'Reason for partial overlap',
                  ),
                  onChanged: (v) => _overlapReason = v,
                ),
              ],
              if (_imported == null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'I reviewed the statement rows and selected cash account.',
                  ),
                  subtitle: const Text(
                    'Import saves normalized rows only. It does not post income, expenses or matches.',
                  ),
                  value: _importConfirmed,
                  onChanged: _busy || _pendingImport != null
                      ? null
                      : (v) => setState(() => _importConfirmed = v == true),
                ),
              if (_imported != null)
                Text(
                  'Imported ${_imported!['row_count']} rows. Open Saved statements to review matches.',
                ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy && _pendingImport != null
            ? null
            : () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      FilledButton(
        onPressed:
            _csv == null ||
                _busy ||
                _denied ||
                _pendingImport != null ||
                _imported != null
            ? null
            : _review,
        child: Text(_busy ? 'Checking…' : 'Preview possible matches'),
      ),
      if (_preview != null && _imported == null)
        FilledButton(
          onPressed:
              _busy || _denied || (!_importConfirmed && _pendingImport == null)
              ? null
              : _import,
          child: Text(
            _pendingImport == null
                ? 'Import reviewed rows'
                : 'Retry same import',
          ),
        ),
    ],
  );
}
