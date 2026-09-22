import 'dart:async';
import 'package:flutter/material.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';
import 'funnel_lead_editor.dart';

class FunnelCleanup extends StatefulWidget {
  const FunnelCleanup({
    super.key,
    required this.client,
    required this.funnelId,
    required this.onAccessDenied,
    this.leadId,
  });
  final FunnelClient client;
  final String funnelId;
  final String? leadId;
  final VoidCallback onAccessDenied;
  @override
  State<FunnelCleanup> createState() => _FunnelCleanupState();
}

class _FunnelCleanupState extends State<FunnelCleanup> {
  final _confirmation = TextEditingController();
  DateTime _before = DateTime.now().toUtc().subtract(const Duration(days: 90));
  String _stages = 'both';
  bool _loading = false,
      _deleting = false,
      _denied = false,
      _needsRefresh = false;
  String? _error;
  Map<String, dynamic>? _review;
  bool get _busy => _loading || _deleting;
  List<dynamic> get _selected => _review?['selected'] as List? ?? [];
  String _date(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    if (widget.leadId != null) unawaited(_preview());
  }

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  void _invalidate() {
    _review = null;
    _confirmation.clear();
    _error = null;
  }

  void _close() {
    if (!_deleting) Navigator.pop(context, _needsRefresh ? -1 : null);
  }

  void _failed(Object e) {
    if (!mounted) return;
    final denied = e is FunnelException && (e.status == 401 || e.status == 403);
    setState(() {
      _review = null;
      _confirmation.clear();
      _error = e.toString();
      _denied = denied;
    });
    if (denied) widget.onAccessDenied();
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now().toUtc();
    final value = await showDatePicker(
      context: context,
      initialDate: _before,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: 'Inquiries received before this date (UTC)',
    );
    if (value != null && mounted) {
      setState(() {
        _before = value;
        _invalidate();
      });
    }
  }

  Future<void> _preview() async {
    if (_busy || _denied) return;
    setState(() {
      _loading = true;
      _invalidate();
    });
    try {
      final result = await widget.client.request(
        'POST',
        '/${widget.funnelId}/inbox/cleanup/preview',
        body: widget.leadId != null
            ? {'mode': 'single', 'lead_id': widget.leadId}
            : {
                'mode': 'retention',
                'before': _date(_before),
                'statuses': _stages == 'both' ? ['won', 'lost'] : [_stages],
              },
      );
      if (!mounted) return;
      final rows = result['selected'];
      if (rows is! List ||
          rows.length > 100 ||
          result['eligible'] is! int ||
          result['blocked'] is! int ||
          result['matched'] is! int ||
          result['eligible'] < rows.length ||
          result['blocked'] < 0 ||
          result['matched'] != result['eligible'] + result['blocked'] ||
          result['blocked_examples'] is! List ||
          (result['blocked_examples'] as List).any(
            (row) =>
                row is! Map ||
                row['name'] is! String ||
                row['reason'] is! String,
          ) ||
          (rows.isNotEmpty &&
              (result['review_token'] is! String ||
                  result['review_token'].isEmpty)) ||
          rows.any(
            (row) =>
                row is! Map ||
                row['id'] is! String ||
                row['name'] is! String ||
                row['email'] is! String ||
                row['created_at'] is! String ||
                DateTime.tryParse(row['created_at']) == null ||
                !funnelLeadStatuses.containsKey(row['status']) ||
                row['followups'] is! int ||
                row['sequences'] is! int,
          )) {
        throw const FunnelException(
          'Cleanup could not prepare a complete review. Please try again.',
        );
      }
      setState(() => _review = result);
    } catch (e) {
      _failed(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    if (_busy ||
        _denied ||
        _selected.isEmpty ||
        _confirmation.text != 'DELETE') {
      return;
    }
    final expected = _selected.length, token = _review!['review_token'];
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      final result = await widget.client.request(
        'POST',
        '/${widget.funnelId}/inbox/cleanup/delete',
        body: {'review_token': token, 'confirmation': 'DELETE'},
      );
      if (!mounted) return;
      if (result['deleted_count'] != expected || result['replayed'] is! bool) {
        throw const FunnelException(
          'Deletion could not be confirmed. Close and refresh the inbox before reviewing again.',
        );
      }
      Navigator.pop(context, expected);
    } catch (e) {
      _needsRefresh = true;
      _failed(e);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_deleting && !_needsRefresh,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !_deleting) _close();
    },
    child: AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(
        _denied
            ? 'Sign in required'
            : widget.leadId == null
            ? 'Clean up old inquiries'
            : 'Delete inquiry',
      ),
      content: SizedBox(
        width: 700,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_denied)
              const Text(
                'Sign in with an Enterprise account to manage this inbox.',
              )
            else ...[
              const Text(
                'Review the exact inquiries before deleting. Each batch contains up to 100 eligible records.',
                style: TextStyle(color: WfStyle.muted, height: 1.5),
              ),
              if (widget.leadId == null) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _chooseDate,
                  icon: const Icon(Icons.date_range),
                  label: Text('Before ${_date(_before)} (UTC)'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  key: const ValueKey('cleanup-stages'),
                  initialValue: _stages,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Closed stages'),
                  items: const [
                    DropdownMenuItem(
                      value: 'both',
                      child: Text('Won and lost'),
                    ),
                    DropdownMenuItem(value: 'won', child: Text('Won only')),
                    DropdownMenuItem(value: 'lost', child: Text('Lost only')),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _stages = v!;
                          _invalidate();
                        }),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Uses all closed inquiries in this funnel before the cutoff, independent of inbox filters. This is a manual cleanup; no recurring deletion is enabled.',
                  style: TextStyle(
                    color: WfStyle.muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _busy ? null : _preview,
                icon: const Icon(Icons.preview_outlined),
                label: Text(
                  _review == null ? 'Preview cleanup' : 'Refresh preview',
                ),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: WfStyle.danger),
                  ),
                ),
              if (_needsRefresh)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'The deletion result was not confirmed. Closing this window will refresh the inbox. A new preview is required before another attempt.',
                    style: TextStyle(color: WfStyle.gold, height: 1.5),
                  ),
                ),
              if (_review != null) ...[
                const Divider(height: 32),
                Text(
                  '${_review!['matched']} matching · ${_review!['eligible']} eligible · ${_review!['blocked']} protected',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                  ),
                ),
                if (_review!['eligible'] > _selected.length)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'This review contains the oldest 100 eligible inquiries. Additional records require a separate preview and confirmation.',
                      style: TextStyle(color: WfStyle.gold, height: 1.5),
                    ),
                  ),
                if (_review!['blocked'] > 0) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Protected inquiries are excluded',
                    style: TextStyle(
                      color: WfStyle.gold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Open tasks, active sequences, and recorded email activity must be handled in Follow-ups or Email Center. Deletion never cancels or stops a message.',
                    style: TextStyle(color: WfStyle.muted, height: 1.5),
                  ),
                  for (final row in _review!['blocked_examples'] as List)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${row['name']} · ${row['reason']}',
                        style: const TextStyle(fontSize: 12, height: 1.5),
                      ),
                    ),
                  if (_review!['blocked'] > 5)
                    const Text(
                      'Showing the first 5 protected records.',
                      style: TextStyle(color: WfStyle.muted, fontSize: 12),
                    ),
                ],
                if (_selected.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 18),
                    child: Text(
                      'No inquiries can be deleted from this selection.',
                    ),
                  )
                else ...[
                  const SizedBox(height: 20),
                  Text(
                    '${_selected.length} ${_selected.length == 1 ? 'inquiry' : 'inquiries'} selected for permanent deletion',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final row in _selected)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: WfStyle.background,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${row['name']}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${row['email']}',
                            style: const TextStyle(color: WfStyle.cyan),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${funnelLeadStatuses[row['status']]} · ${DateTime.parse(row['created_at']).toUtc().toIso8601String().replaceFirst('T', ' ').replaceFirst('Z', ' UTC')}',
                            style: const TextStyle(
                              color: WfStyle.muted,
                              fontSize: 12,
                            ),
                          ),
                          if (row['followups'] > 0 || row['sequences'] > 0)
                            Text(
                              'Local history removed: ${row['followups']} resolved tasks, ${row['sequences']} stopped sequences.',
                              style: const TextStyle(
                                color: WfStyle.gold,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 18),
                  const Text(
                    'This permanently removes the selected inquiries, private notes and listed local history. CRM contacts and Email Center records are kept. Inquiry and campaign counts will decrease.',
                    style: TextStyle(color: WfStyle.gold, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'The review expires after 10 minutes. Changed records require a new preview.',
                    style: TextStyle(color: WfStyle.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 18),
                  const Text('Type DELETE to confirm'),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('cleanup-confirmation'),
                    controller: _confirmation,
                    enabled: !_busy,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(hintText: 'DELETE'),
                    autocorrect: false,
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : _close,
          child: const Text('Close'),
        ),
        if (!_denied && _selected.isNotEmpty)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: WfStyle.danger,
              foregroundColor: WfStyle.background,
            ),
            onPressed: _busy || _confirmation.text != 'DELETE' ? null : _delete,
            child: Text(
              _deleting
                  ? 'Deleting…'
                  : 'Delete ${_selected.length} ${_selected.length == 1 ? 'inquiry' : 'inquiries'}',
            ),
          ),
      ],
    ),
  );
}
