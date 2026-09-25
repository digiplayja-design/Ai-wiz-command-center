import 'dart:async';
import 'package:flutter/material.dart';
import 'bookkeeping_client.dart';
import 'bookkeeping_csv_save.dart';
import 'bookkeeping_models.dart';
import 'statement_balance_worksheet.dart';

class BookkeepingStatementHistory extends StatefulWidget {
  const BookkeepingStatementHistory({
    super.key,
    required this.client,
    required this.businessId,
    this.onExport,
  });
  final BookkeepingClient client;
  final String businessId;
  final Future<void> Function(String csv, String filename)? onExport;
  @override
  State<BookkeepingStatementHistory> createState() =>
      _BookkeepingStatementHistoryState();
}

class _BookkeepingStatementHistoryState
    extends State<BookkeepingStatementHistory> {
  List<Map<String, dynamic>> _statements = [];
  Map<String, dynamic>? _detail, _pendingBody;
  String? _error, _notice, _pendingPath;
  bool _busy = false, _denied = false;
  int _operation = 0;
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
      _operation++;
      _statements = [];
      _detail = null;
      _pendingBody = null;
      _pendingPath = null;
      _error = null;
      _notice = null;
      _busy = false;
    });
  }

  @override
  void dispose() {
    _operation++;
    widget.client.removeAccessDeniedListener(_deny);
    super.dispose();
  }

  String get _base => '/businesses/${widget.businessId}/statements';
  Future<void> _load([String? id]) async {
    if (_busy || _denied) return;
    final op = ++_operation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.client.request(
        'GET',
        id == null ? _base : '$_base/$id',
      );
      if (!mounted || _denied || op != _operation) return;
      setState(() {
        if (id == null) {
          _statements = bookkeepingRows(data['statements']);
        } else {
          _detail = data;
        }
      });
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

  Map<String, dynamic>? _lastDecision(int line) {
    Map<String, dynamic>? last;
    for (final d in bookkeepingRows(_detail?['decisions'])) {
      if (d['row_line'] == line) last = d;
    }
    return last;
  }

  Future<bool> _confirm(String title, String detail) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(detail),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirm decision'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _match(
    Map<String, dynamic> row,
    Map<String, dynamic> candidate,
  ) async {
    if (_busy || _denied || _pendingBody != null) return;
    if (!await _confirm(
      'Match statement row?',
      'Statement line ${row['line']}: ${row['date']} · ${row['description']} · ${row['amount_cents']} cents.\n\nRecorded ${candidate['date']} · ${candidate['kind']} · ${candidate['amount_cents']} cents.\n\nCheck your original statement and books. This records a match decision only.',
    )) {
      return;
    }
    final id = _detail!['statement']['id'];
    _pendingPath = '$_base/$id/rows/${row['line']}/match';
    _pendingBody = {
      'entry_id': candidate['entry_id'],
      'request_key': bookkeepingRequestKey(),
      'confirmed': true,
    };
    await _send();
  }

  Future<void> _unmatch(
    Map<String, dynamic> row,
    Map<String, dynamic> match,
  ) async {
    if (_busy || _denied || _pendingBody != null) return;
    final controller = TextEditingController();
    try {
      final reason = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Correct statement match'),
          content: TextField(
            controller: controller,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Reason for correction',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, controller.text.trim()),
              child: const Text('Review correction'),
            ),
          ],
        ),
      );
      if (reason == null || reason.isEmpty) return;
      if (!mounted || _denied) return;
      if (!await _confirm(
        'Unmatch row ${row['line']}?',
        'The prior match stays in the audit history. Reason: $reason',
      )) {
        return;
      }
      final id = _detail!['statement']['id'];
      _pendingPath = '$_base/$id/rows/${row['line']}/unmatch';
      _pendingBody = {
        'previous_match_id': match['id'],
        'reason': reason,
        'request_key': bookkeepingRequestKey(),
        'confirmed': true,
      };
      await _send();
    } finally {
      controller.dispose();
    }
  }

  Future<void> _send() async {
    if (_busy || _denied || _pendingBody == null || _pendingPath == null) {
      return;
    }
    final op = ++_operation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.request('POST', _pendingPath!, body: _pendingBody);
      if (!mounted || _denied || op != _operation) return;
      final id = _detail!['statement']['id'] as String;
      setState(() {
        _pendingBody = null;
        _pendingPath = null;
        _busy = false;
      });
      await _load(id);
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

  Future<void> _export() async {
    if (_busy || _denied || _detail == null) return;
    final op = ++_operation;
    final statementId = _detail!['statement']['id'] as String;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final data = await widget.client.request(
        'GET',
        '$_base/$statementId/export',
      );
      if (!mounted || _denied || op != _operation) return;
      if (widget.onExport != null) {
        await widget.onExport!(
          data['csv'] as String,
          data['filename'] as String,
        );
      } else {
        await saveBookkeepingCsv(
          data['csv'] as String,
          data['filename'] as String,
          const Rect.fromLTWH(0, 0, 1, 1),
        );
      }
      if (mounted && !_denied && op == _operation) {
        setState(() => _notice = 'Review CSV prepared.');
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

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _detail == null ? 'Saved statements' : 'Review statement matches',
    ),
    content: SizedBox(
      width: 680,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A suggested match is not proof of a bank transaction. Review the original statement and recorded entry before confirming. Imports do not change accounting balances.',
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xff9c2525)),
                ),
              ),
            if (_notice != null) Text(_notice!),
            if (_pendingBody != null)
              TextButton(
                onPressed: _busy || _denied ? null : _send,
                child: const Text('Retry same decision'),
              ),
            if (_detail == null) ...[
              if (_statements.isEmpty && !_busy)
                const Text('No saved statements yet.'),
              for (final s in _statements)
                ListTile(
                  title: Text(
                    '${s['statement_year']} · ${s['row_count']} rows · cash account ${s['cash_account']}',
                  ),
                  subtitle: Text('Imported ${s['created_at']}'),
                  onTap: _busy || _denied
                      ? null
                      : () => _load(s['id'] as String),
                ),
            ] else ...[
              Text(
                '${_detail!['statement']['statement_year']} · account ${_detail!['statement']['cash_account']}',
              ),
              if (_detail!['coverage'] is Map) ...[
                const SizedBox(height: 12),
                Text(
                  'Review progress: ${_detail!['coverage']['matched_count']} matched · ${_detail!['coverage']['open_count']} open of ${_detail!['coverage']['row_count']} rows',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Imported dates ${_detail!['coverage']['from_date']} to ${_detail!['coverage']['through_date']}',
                ),
                Text(
                  'Signed statement total ${_detail!['coverage']['statement_net_cents']} cents · matched ${_detail!['coverage']['matched_net_cents']} cents · open ${_detail!['coverage']['open_net_cents']} cents',
                ),
                Text('${_detail!['coverage']['scope']}'),
                StatementBalanceWorksheet(
                  key: ValueKey(_detail!['statement']['id']),
                  statementNetCents:
                      _detail!['coverage']['statement_net_cents'] as String,
                ),
              ],
              for (final row in bookkeepingRows(_detail!['statement']['rows']))
                Builder(
                  builder: (context) {
                    final decision = _lastDecision(row['line'] as int);
                    final matched = decision?['action'] == 'match';
                    final candidates = bookkeepingRows(row['candidates']);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(),
                        Text(
                          'Line ${row['line']}: ${row['date']} · ${row['description']} · ${row['amount_cents']} cents',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          matched
                              ? 'Matched to recorded entry ${decision!['entry_id']}'
                              : decision?['action'] == 'unmatch'
                              ? 'Unmatched after correction'
                              : '${row['status']} · ${candidates.length} candidate(s)',
                        ),
                        if (matched)
                          TextButton(
                            onPressed: _busy || _denied || _pendingBody != null
                                ? null
                                : () => _unmatch(row, decision!),
                            child: const Text('Correct match'),
                          ),
                        if (!matched)
                          for (final candidate in candidates)
                            TextButton(
                              onPressed:
                                  _busy || _denied || _pendingBody != null
                                  ? null
                                  : () => _match(row, candidate),
                              child: Text(
                                'Review match: ${candidate['date']} · ${candidate['kind']} · ${candidate['entry_id']}',
                              ),
                            ),
                      ],
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      if (_detail != null)
        TextButton.icon(
          onPressed: _busy || _denied ? null : _export,
          icon: const Icon(Icons.download_outlined),
          label: const Text('Export review CSV'),
        ),
      if (_detail != null)
        TextButton(
          onPressed: _busy ? null : () => setState(() => _detail = null),
          child: const Text('All statements'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
