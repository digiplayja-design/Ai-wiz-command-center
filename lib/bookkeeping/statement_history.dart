import 'dart:async';
import 'package:flutter/material.dart';
import 'bookkeeping_client.dart';
import 'bookkeeping_csv_save.dart';
import 'bookkeeping_models.dart';
import 'bookkeeping_ui.dart';
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
  String? _error, _pendingPath, _selectedId, _exportError, _exportNotice;
  bool _busy = false, _writing = false, _denied = false, _listLoaded = false;
  int _operation = 0;
  final _exportKey = GlobalKey(), _feedbackKey = GlobalKey();
  bool get _alive => mounted && !_denied && !widget.client.sessionChanged;
  bool _current(int op) => _alive && op == _operation;
  String get _base => '/businesses/${widget.businessId}/statements';
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
      _selectedId = null;
      _error = _exportError = _exportNotice = null;
      _busy = _writing = false;
    });
  }

  @override
  void dispose() {
    _operation++;
    widget.client.removeAccessDeniedListener(_deny);
    super.dispose();
  }

  Future<void> _load([String? id]) async {
    if (_busy || !_alive || (id == null && _pendingBody != null)) return;
    final op = ++_operation;
    setState(() {
      _busy = true;
      _selectedId = id;
      _detail = null;
      _error = _exportError = _exportNotice = null;
      if (id == null) {
        _statements = [];
        _listLoaded = false;
      }
    });
    try {
      final data = await widget.client.request(
        'GET',
        id == null ? _base : '$_base/$id',
      );
      if (!mounted || !_current(op)) return;
      setState(() {
        if (id == null) {
          _statements = bookkeepingRows(data['statements']);
          _listLoaded = true;
        } else {
          _detail = data;
        }
      });
    } catch (e) {
      if (_current(op)) setState(() => _error = '$e');
    } finally {
      if (_current(op)) setState(() => _busy = false);
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
          scrollable: true,
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
  String _purpose(Map<String, dynamic> candidate) =>
      (candidate['purpose'] as String?)?.trim().isNotEmpty == true
      ? candidate['purpose'] as String
      : 'Purpose unavailable';
  Future<void> _match(
    Map<String, dynamic> row,
    Map<String, dynamic> candidate,
  ) async {
    if (_busy || !_alive || _pendingBody != null || _selectedId == null) return;
    final statement = _selectedId;
    if (!await _confirm(
      'Match statement row?',
      'Statement line ${row['line']}: ${row['date']} · ${row['description']} · ${bookkeepingMoney(row['amount_cents'])} USD.\n\nRecorded purpose: ${_purpose(candidate)}\nRecord ID: ${candidate['entry_id']}\n${candidate['date']} · ${candidate['source'] ?? candidate['kind']} · ${candidate['kind']} · ${bookkeepingMoney(candidate['amount_cents'])} USD.\n\nCheck your original statement and books. This records a match decision only.',
    )) {
      return;
    }
    if (!_alive || _selectedId != statement) return;
    _pendingPath = '$_base/$statement/rows/${row['line']}/match';
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
    if (_busy || !_alive || _pendingBody != null || _selectedId == null) return;
    final statement = _selectedId, controller = TextEditingController();
    try {
      final reason = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Correct statement match'),
          scrollable: true,
          content: TextField(
            controller: controller,
            maxLength: 500,
            minLines: 2,
            maxLines: 5,
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
      if (!_alive ||
          reason == null ||
          reason.isEmpty ||
          _selectedId != statement) {
        return;
      }
      if (!await _confirm(
        'Unmatch row ${row['line']}?',
        'The prior match stays in the audit history. Reason: $reason',
      )) {
        return;
      }
      if (!_alive || _selectedId != statement) return;
      _pendingPath = '$_base/$statement/rows/${row['line']}/unmatch';
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
    if (_busy || !_alive || _pendingBody == null || _pendingPath == null) {
      return;
    }
    final op = ++_operation, statement = _selectedId!;
    setState(() {
      _busy = _writing = true;
      _detail = null;
      _error = _exportError = _exportNotice = null;
    });
    try {
      await widget.client.request('POST', _pendingPath!, body: _pendingBody);
      if (!mounted || !_current(op)) return;
      setState(() {
        _pendingBody = null;
        _pendingPath = null;
        _busy = _writing = false;
      });
      await _load(statement);
    } catch (e) {
      if (_current(op)) setState(() => _error = '$e');
    } finally {
      if (_current(op)) {
        setState(() {
          _busy = _writing = false;
        });
      }
    }
  }

  Future<void> _more(Map<String, dynamic> row) async {
    final offset = row['candidate_next_offset'],
        revision = row['candidate_revision'];
    if (_busy ||
        !_alive ||
        _detail == null ||
        _pendingBody != null ||
        offset is! int ||
        revision is! String) {
      return;
    }
    final statement = _selectedId!,
        line = row['line'],
        account = _detail!['statement']['cash_account'];
    final op = ++_operation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.client.request(
        'GET',
        '$_base/$statement/rows/$line/candidates',
        query: {'offset': '$offset', 'revision': revision},
      );
      if (!mounted || !_current(op)) return;
      final raw = data['candidates'];
      if (raw is! List ||
          raw.any(
            (c) =>
                c is! Map ||
                c['entry_id'] is! String ||
                (c['entry_id'] as String).isEmpty,
          )) {
        throw const BookkeepingException(
          'Candidate details changed. Refresh the statement before continuing.',
          409,
        );
      }
      final page = bookkeepingRows(raw),
          loaded = bookkeepingRows(row['candidates']);
      final total = data['total'], next = data['next_offset'];
      if (data['statement_id'] != statement ||
          data['row_line'] != line ||
          data['cash_account'] != account ||
          data['revision'] != revision ||
          data['offset'] != offset ||
          offset != loaded.length ||
          total is! int ||
          total != row['candidate_total'] ||
          page.length > 5 ||
          page.length != (total - offset).clamp(0, 5) ||
          next !=
              (offset + page.length < total ? offset + page.length : null) ||
          {
                ...loaded.map((c) => c['entry_id']),
                ...page.map((c) => c['entry_id']),
              }.length !=
              loaded.length + page.length) {
        throw const BookkeepingException(
          'Candidate details changed. Refresh the statement before continuing.',
          409,
        );
      }
      setState(() {
        _detail!['statement']['rows'] =
            bookkeepingRows(_detail!['statement']['rows'])
                .map(
                  (r) => r['line'] == line
                      ? {
                          ...r,
                          'candidates': [...loaded, ...page],
                          'candidate_next_offset': next,
                        }
                      : r,
                )
                .toList();
      });
    } catch (e) {
      if (_current(op)) {
        setState(() {
          _error = '$e';
          if (e is BookkeepingException && e.status == 409) _detail = null;
        });
      }
    } finally {
      if (_current(op)) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    if (_busy || !_alive || _detail == null || _pendingBody != null) return;
    final op = ++_operation, statement = _selectedId!;
    setState(() {
      _busy = true;
      _exportError = _exportNotice = null;
    });
    try {
      final data = await widget.client.request(
        'GET',
        '$_base/$statement/export',
      );
      if (!mounted || !_current(op)) return;
      if (widget.onExport != null) {
        await widget.onExport!(
          data['csv'] as String,
          data['filename'] as String,
        );
      } else {
        await saveBookkeepingCsv(
          data['csv'] as String,
          data['filename'] as String,
          bookkeepingShareOrigin(_exportKey, context),
        );
      }
      if (_current(op)) setState(() => _exportNotice = 'Review CSV prepared.');
    } catch (e) {
      if (_current(op)) setState(() => _exportError = '$e');
    } finally {
      if (_current(op)) {
        setState(() => _busy = false);
        revealBookkeepingFeedback(_feedbackKey, () => _current(op));
      }
    }
  }

  @override
  Widget build(BuildContext context) => BookkeepingDialog(
    client: widget.client,
    busy: _writing,
    title: Text(
      _selectedId == null ? 'Saved statements' : 'Review statement matches',
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
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xff9c2525)),
                ),
              ),
            if (_pendingBody != null)
              TextButton(
                onPressed: _busy ? null : _send,
                child: const Text('Retry same decision'),
              ),
            TextButton(
              onPressed: _busy ? null : () => _load(_selectedId),
              child: Text(
                _selectedId == null
                    ? 'Refresh statements'
                    : 'Refresh statement',
              ),
            ),
            if (_selectedId == null) ...[
              if (_listLoaded && _statements.isEmpty && !_busy)
                const Text('No saved statements yet.'),
              for (final s in _statements)
                ListTile(
                  title: Text(
                    '${s['statement_year']} · ${s['row_count']} rows · cash account ${s['cash_account']}',
                  ),
                  subtitle: Text(
                    'Imported ${s['created_at']}${s['has_repeated_rows'] == true ? ' · repeated rows reviewed' : ''}',
                  ),
                  onTap: _busy || _pendingBody != null
                      ? null
                      : () => _load(s['id'] as String),
                ),
            ],
            if (_detail != null) ...[
              Text(
                '${_detail!['statement']['statement_year']} · account ${_detail!['statement']['cash_account']}',
              ),
              for (final key in [
                'duplicate_review_reason',
                'overlap_review_reason',
              ])
                if ((_detail!['statement'][key] as String?)?.isNotEmpty == true)
                  Text(
                    '${key == 'duplicate_review_reason' ? 'Repeated-row' : 'Overlap'} review reason: ${_detail!['statement'][key]}',
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
                _row(row),
            ],
            Semantics(
              key: _feedbackKey,
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_exportError != null)
                    Text(
                      _exportError!,
                      style: const TextStyle(color: Color(0xff9c2525)),
                    ),
                  if (_exportNotice != null) Text(_exportNotice!),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      if (_detail != null)
        TextButton.icon(
          key: _exportKey,
          onPressed: _busy || _pendingBody != null ? null : _export,
          icon: const Icon(Icons.download_outlined),
          label: const Text('Export review CSV'),
        ),
      if (_selectedId != null)
        TextButton(
          onPressed: _busy || _pendingBody != null ? null : () => _load(),
          child: const Text('All statements'),
        ),
      TextButton(
        onPressed: _writing ? null : () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
  Widget _row(Map<String, dynamic> row) {
    final decision = _lastDecision(row['line'] as int),
        candidates = bookkeepingRows(row['candidates']);
    final matched = decision?['action'] == 'match';
    final total = row['candidate_total'];
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
              ? row['needs_review'] == true
                    ? 'Needs review: the matched record was reversed or no longer qualifies. Correct the match to choose a replacement.'
                    : 'Matched to recorded entry ${decision!['entry_id']}'
              : decision?['action'] == 'unmatch'
              ? 'Unmatched after correction'
              : '${row['status']}',
        ),
        if (matched)
          TextButton(
            onPressed: _busy || _pendingBody != null
                ? null
                : () => _unmatch(row, decision!),
            child: const Text('Correct match'),
          ),
        if (!matched) ...[
          Text(
            total is int
                ? '${candidates.length} of $total candidates loaded'
                : '${candidates.length} candidate(s)',
          ),
          for (final candidate in candidates)
            TextButton(
              onPressed: _busy || _pendingBody != null
                  ? null
                  : () => _match(row, candidate),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Review match: ${_purpose(candidate)}\n${candidate['date']} · ${candidate['kind']} · ${candidate['entry_id']}',
                ),
              ),
            ),
          if (row['candidate_next_offset'] is int &&
              row['candidate_revision'] is String)
            TextButton(
              onPressed: _busy || _pendingBody != null
                  ? null
                  : () => _more(row),
              child: const Text('Show more candidates'),
            ),
        ],
      ],
    );
  }
}
