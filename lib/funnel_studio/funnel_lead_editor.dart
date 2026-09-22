import 'dart:async';
import 'package:flutter/material.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';

const funnelLeadStatuses = <String, String>{
  'new': 'New',
  'in_review': 'In review',
  'qualified': 'Qualified',
  'won': 'Won',
  'lost': 'Lost',
};

class FunnelLeadEditor extends StatefulWidget {
  const FunnelLeadEditor({
    super.key,
    required this.client,
    required this.funnelId,
    required this.leadId,
    required this.onAccessDenied,
  });
  final FunnelClient client;
  final String funnelId, leadId;
  final VoidCallback onAccessDenied;
  @override
  State<FunnelLeadEditor> createState() => _FunnelLeadEditorState();
}

class _FunnelLeadEditorState extends State<FunnelLeadEditor> {
  final _note = TextEditingController();
  Map<String, dynamic>? _lead;
  String _status = 'new';
  String? _error;
  bool _loading = false, _saving = false, _denied = false, _conflict = false;
  int _scheduled = 0, _deliveryReview = 0, _revision = 0;
  bool get _busy => _loading || _saving;
  bool get _dirty =>
      _lead != null &&
      (_status != _lead!['inbox_status'] ||
          _note.text != _lead!['private_note']);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Map<String, dynamic> _validated(Map<String, dynamic> data) {
    final raw = data['lead'];
    if (raw is! Map ||
        raw['id'] != widget.leadId ||
        raw['inbox_version'] is! int ||
        raw['inbox_version'] < 1 ||
        !funnelLeadStatuses.containsKey(raw['inbox_status']) ||
        raw['private_note'] is! String ||
        raw['name'] is! String ||
        raw['email'] is! String ||
        data['scheduled_followups'] is! int ||
        data['delivery_review'] is! int) {
      throw const FunnelException(
        'Could not confirm the saved lead details. Reload before trying again.',
      );
    }
    return Map<String, dynamic>.from(raw);
  }

  void _failed(Object error) {
    if (!mounted) return;
    final denied =
        error is FunnelException &&
        (error.status == 401 || error.status == 403);
    setState(() {
      _error = error.toString();
      _conflict = true;
      if (denied) {
        _denied = true;
        _lead = null;
        _note.clear();
        _status = 'new';
        _scheduled = 0;
        _deliveryReview = 0;
      }
    });
    if (denied) widget.onAccessDenied();
  }

  Future<bool> _discard() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Discard these edits?'),
            content: const Text(
              'Your unsaved status and private note will be discarded.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Discard edits'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _close() async {
    if (_saving) return;
    if (await _discard() && mounted) Navigator.pop(context, false);
  }

  Future<void> _load() async {
    if (_busy || _denied) return;
    if (!await _discard() || !mounted) return;
    setState(() {
      _loading = true;
      _lead = null;
      _note.clear();
      _error = null;
      _conflict = false;
    });
    try {
      final result = await widget.client.request(
        'GET',
        '/${widget.funnelId}/inbox/${widget.leadId}',
      );
      if (!mounted) return;
      final lead = _validated(result);
      setState(() {
        _lead = lead;
        _status = lead['inbox_status'];
        _note.text = lead['private_note'];
        _scheduled = result['scheduled_followups'];
        _deliveryReview = result['delivery_review'];
        _revision++;
      });
    } catch (e) {
      _failed(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _denied || _conflict || !_dirty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.client.request(
        'PATCH',
        '/${widget.funnelId}/inbox/${widget.leadId}',
        body: {
          'version': _lead!['inbox_version'],
          'status': _status,
          'private_note': _note.text,
        },
      );
      if (!mounted) return;
      final saved = _validated(result);
      if (saved['inbox_status'] != _status ||
          saved['private_note'] != _note.text.trim() ||
          saved['inbox_version'] < _lead!['inbox_version']) {
        throw const FunnelException(
          'Could not confirm the saved lead details. Reload before trying again.',
        );
      }
      Navigator.pop(context, true);
    } catch (e) {
      _failed(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving && !_dirty,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !_saving) unawaited(_close());
    },
    child: AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(_denied ? 'Sign in required' : 'Manage lead'),
      content: SizedBox(
        width: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_denied)
              const Text(
                'Sign in with an Enterprise account to manage this inbox.',
              )
            else ...[
              if (_lead != null) ...[
                Text(
                  '${_lead!['name']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  '${_lead!['email']}',
                  style: const TextStyle(color: WfStyle.cyan),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  key: ValueKey('lead-status-$_revision'),
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Lead status'),
                  items: [
                    for (final entry in funnelLeadStatuses.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _status = value!),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('lead-private-note'),
                  controller: _note,
                  enabled: !_busy,
                  minLines: 4,
                  maxLines: 9,
                  maxLength: 4000,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Private note',
                    hintText: 'Record the next step or what you learned.',
                    alignLabelWithHint: true,
                  ),
                ),
                const Text(
                  'Visible in your inbox and included in CSV exports.',
                  style: TextStyle(color: WfStyle.muted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Status and notes organize this inquiry. They do not change CRM permissions or stop follow-ups. Manage scheduled replies in Follow-ups.',
                  style: TextStyle(color: WfStyle.muted, height: 1.5),
                ),
                if (_status == 'won') ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Won is your assessment of the inquiry; it does not record or verify revenue.',
                    style: TextStyle(
                      color: WfStyle.muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
                if (_scheduled > 0 || _deliveryReview > 0) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Scheduled follow-ups: $_scheduled · Delivery review: $_deliveryReview',
                    style: const TextStyle(color: WfStyle.gold, height: 1.5),
                  ),
                ],
              ],
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: WfStyle.danger)),
              ],
              if (_conflict || (_lead == null && !_busy))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reload saved details'),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _close,
          child: Text(_dirty ? 'Discard changes' : 'Close'),
        ),
        if (!_denied)
          FilledButton(
            onPressed: _busy || _conflict || !_dirty ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save status & note'),
          ),
      ],
    ),
  );
}
