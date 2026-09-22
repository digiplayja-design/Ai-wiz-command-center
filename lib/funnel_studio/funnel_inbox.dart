import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../workforce/workforce_style.dart';
import 'funnel_client.dart';
import 'funnel_csv_save.dart';
import 'funnel_lead_editor.dart';
import 'funnel_cleanup.dart';

class FunnelInbox extends StatefulWidget {
  const FunnelInbox({
    super.key,
    required this.client,
    required this.funnelId,
    required this.onQueue,
    this.onOpenContacts,
    this.onExport,
  });
  final FunnelClient client;
  final String funnelId;
  final Future<void> Function(String) onQueue;
  final Future<void> Function()? onOpenContacts;
  final Future<void> Function(String csv, String filename)? onExport;
  @override
  State<FunnelInbox> createState() => _FunnelInboxState();
}

class _FunnelInboxState extends State<FunnelInbox> {
  final _exportKey = GlobalKey();
  final _search = TextEditingController(), _source = TextEditingController();
  DateTimeRange? _dates;
  String _status = '';
  Map<String, String> _applied = {};
  Map<String, dynamic>? _data;
  List<String?> _cursors = [null];
  int _page = 0;
  bool _busy = false, _denied = false;
  String? _error, _notice;
  String _date(DateTime d) => d.toIso8601String().substring(0, 10);
  Map<String, String> get _edited => {
    if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
    if (_source.text.trim().isNotEmpty) 'source': _source.text.trim(),
    if (_status.isNotEmpty) 'status': _status,
    if (_dates != null) 'from': _date(_dates!.start),
    if (_dates != null) 'to': _date(_dates!.end),
  };
  bool get _changed => !mapEquals(_edited, _applied);
  List<dynamic> get _leads => _data?['leads'] as List? ?? [];

  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _search.dispose();
    _source.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() fn) async {
    if (_busy || _denied) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          if (e is FunnelException && (e.status == 401 || e.status == 403)) {
            _denied = true;
            _data = null;
            _search.clear();
            _source.clear();
            _status = '';
            _applied = {};
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load({
    bool reset = false,
    int? page,
    bool keepFilters = false,
  }) => _run(() async {
    final target = reset ? 0 : (page ?? _page);
    final filters = reset && !keepFilters
        ? _edited
        : Map<String, String>.from(_applied);
    final cursors = reset ? <String?>[null] : List<String?>.from(_cursors);
    final snapshot = reset ? null : _data?['snapshot']?.toString();
    if (reset) {
      setState(() {
        _data = null;
        _applied = filters;
        _cursors = [null];
        _page = 0;
      });
    }
    final result = await widget.client.request(
      'GET',
      '/${widget.funnelId}/inbox',
      query: {
        ...filters,
        'snapshot': ?snapshot,
        if (cursors[target] != null) 'cursor': cursors[target]!,
      },
    );
    if (!mounted) return;
    if (result['leads'] is! List || result['snapshot'] is! String) {
      throw const FunnelException(
        'The lead inbox upgrade is not available yet. Try again after deployment.',
      );
    }
    final next = result['next_cursor'] as String?;
    final updated = cursors.take(target + 1).toList();
    if (next != null) updated.add(next);
    setState(() {
      _data = result;
      _applied = filters;
      _page = target;
      _cursors = updated;
    });
  });

  Future<void> _manageLead(String id) async {
    if (_busy || _denied) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FunnelLeadEditor(
        client: widget.client,
        funnelId: widget.funnelId,
        leadId: id,
        onAccessDenied: () {
          if (!mounted) return;
          setState(() {
            _denied = true;
            _data = null;
            _search.clear();
            _source.clear();
            _status = '';
            _applied = {};
          });
        },
      ),
    );
    if (!mounted || _denied || saved != true) return;
    await _load(reset: true, keepFilters: true);
    if (mounted && !_denied) setState(() => _notice = 'Lead details saved.');
  }

  Future<void> _pickDates() async {
    final today = DateTime.now().toUtc();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year + 1, 12, 31),
      initialDateRange: _dates,
      helpText: 'Filter inquiry dates (UTC)',
    );
    if (mounted && picked != null) setState(() => _dates = picked);
  }

  Future<void> _cleanup({String? leadId}) async {
    if (_busy || _denied) return;
    final removed = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FunnelCleanup(
        client: widget.client,
        funnelId: widget.funnelId,
        leadId: leadId,
        onAccessDenied: () {
          if (!mounted) return;
          setState(() {
            _denied = true;
            _data = null;
            _search.clear();
            _source.clear();
            _status = '';
            _applied = {};
          });
        },
      ),
    );
    if (!mounted || _denied || removed == null) return;
    await _load(reset: true, keepFilters: true);
    if (mounted && !_denied) {
      setState(
        () => _notice = removed < 0
            ? (_error == null
                  ? 'Inbox refreshed. Review the remaining inquiries before trying again.'
                  : 'Deletion was not confirmed. Reload the inbox before trying again.')
            : '$removed ${removed == 1 ? 'inquiry' : 'inquiries'} deleted. Linked CRM contacts and Email Center records were retained.',
      );
    }
  }

  Future<void> _export() => _run(() async {
    final result = await widget.client.request(
      'GET',
      '/${widget.funnelId}/inbox/export',
      query: {..._applied, 'snapshot': _data!['snapshot'].toString()},
    );
    if (!mounted) return;
    final csv = result['csv'] as String?,
        filename = result['filename'] as String?;
    if (csv == null || filename == null) {
      throw const FunnelException(
        'The export could not be prepared. Please try again.',
      );
    }
    if (widget.onExport != null) {
      await widget.onExport!(csv, filename);
    } else {
      final box = _exportKey.currentContext?.findRenderObject() as RenderBox?;
      final origin = box == null
          ? const Rect.fromLTWH(20, 80, 100, 40)
          : box.localToGlobal(Offset.zero) & box.size;
      await saveFunnelCsv(csv, filename, origin);
    }
    if (mounted) {
      setState(
        () =>
            _notice = 'Export prepared: ${result['count']} matching inquiries.',
      );
    }
  });

  Widget _button(String label, IconData icon, VoidCallback? action) =>
      OutlinedButton.icon(
        onPressed: _busy || _denied ? null : action,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
  Widget _metric(String value, String label, Color color, double width) =>
      Container(
        width: width,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: WfStyle.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WfStyle.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: WfStyle.muted)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_denied) {
      return const Text(
        'Sign in with an Enterprise account to view this inbox.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your lead inbox',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Find the right conversation. Turn interest into a reviewed next step.',
          style: TextStyle(color: WfStyle.muted, height: 1.5),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth < 420 ? (box.maxWidth - 12) / 2 : 190.0;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metric(
                  '${_data?['total'] ?? '—'}',
                  'Total inquiries',
                  WfStyle.cyan,
                  width,
                ),
                _metric(
                  '${_data?['filtered_total'] ?? '—'}',
                  'Matching filters',
                  WfStyle.violet,
                  width,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        if (_data?['status_totals'] is Map) ...[
          const Text(
            'Lead stages',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final stage in funnelLeadStatuses.entries)
                WfBadge(
                  '${stage.value} · ${_data!['status_totals'][stage.key] ?? 0}',
                  color: WfStyle.violet,
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Owner-set stages across the applied search, source and dates.',
            style: TextStyle(color: WfStyle.muted, fontSize: 12),
          ),
          const SizedBox(height: 24),
        ],
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: constraints.maxWidth < 650
                    ? constraints.maxWidth
                    : constraints.maxWidth - 252,
                child: TextField(
                  key: const ValueKey('inbox-search'),
                  controller: _search,
                  enabled: !_busy,
                  maxLength: 160,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _load(reset: true),
                  decoration: const InputDecoration(
                    labelText: 'Search inquiries',
                    hintText: 'Name, email, phone or message',
                    prefixIcon: Icon(Icons.search),
                    counterText: '',
                  ),
                ),
              ),
              SizedBox(
                width: constraints.maxWidth < 650 ? constraints.maxWidth : 240,
                child: TextField(
                  key: const ValueKey('inbox-source'),
                  controller: _source,
                  enabled: !_busy,
                  maxLength: 120,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _load(reset: true),
                  decoration: const InputDecoration(
                    labelText: 'Source',
                    hintText: 'Exact source, e.g. facebook',
                    counterText: '',
                  ),
                ),
              ),
              SizedBox(
                width: constraints.maxWidth < 650 ? constraints.maxWidth : 240,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('inbox-status-$_status'),
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Lead status'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All statuses'),
                    ),
                    for (final stage in funnelLeadStatuses.entries)
                      DropdownMenuItem(
                        value: stage.key,
                        child: Text(stage.value),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _status = value!),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _button(
              _dates == null
                  ? 'All dates (UTC)'
                  : '${_date(_dates!.start)} → ${_date(_dates!.end)} UTC',
              Icons.date_range,
              _pickDates,
            ),
            FilledButton.icon(
              onPressed: _busy ? null : () => _load(reset: true),
              icon: const Icon(Icons.filter_alt_outlined, size: 18),
              label: const Text('Apply filters'),
            ),
            _button('Clear', Icons.filter_alt_off_outlined, () {
              setState(() {
                _search.clear();
                _source.clear();
                _dates = null;
                _status = '';
              });
              unawaited(_load(reset: true));
            }),
            _button('Refresh leads', Icons.refresh, () => _load(reset: true)),
          ],
        ),
        if (_changed)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Apply filters to update results and export.',
              style: TextStyle(color: WfStyle.gold),
            ),
          ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            KeyedSubtree(
              key: _exportKey,
              child: _button(
                'Export filtered CSV',
                Icons.download_outlined,
                _data == null || _changed || _data!['filtered_total'] == 0
                    ? null
                    : _export,
              ),
            ),
            if (widget.onOpenContacts != null)
              _button(
                'Open Contacts CRM',
                Icons.people_outline,
                widget.onOpenContacts,
              ),
            _button(
              'Clean up old inquiries',
              Icons.delete_sweep_outlined,
              () => _cleanup(),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Export up to 5,000 matching inquiries, including owner-set statuses and private notes. For larger lists, narrow the date range. Source tags and identities are visitor-supplied.',
          style: TextStyle(fontSize: 12, height: 1.5, color: WfStyle.muted),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(_error!, style: const TextStyle(color: WfStyle.danger)),
          ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(_notice!, style: const TextStyle(color: WfStyle.cyan)),
          ),
        if ((_data?['campaigns'] as List? ?? []).isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text(
            'Where matching inquiries came from',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _data!['campaigns'] as List)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: WfStyle.raised,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${c['source']} / ${c['campaign']} · ${c['leads']}',
                    style: const TextStyle(color: WfStyle.cyan, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Top 8 source / campaign pairs across all matching inquiries.',
            style: TextStyle(fontSize: 12, color: WfStyle.muted),
          ),
        ],
        const SizedBox(height: 24),
        if (_data != null && _leads.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            child: Text(
              _data!['total'] == 0
                  ? 'Your next lead will appear here. Share a published page to get started.'
                  : 'No inquiries match these filters. Try a different search or date range.',
              style: const TextStyle(color: WfStyle.muted, height: 1.5),
            ),
          ),
        for (final lead in _leads)
          _lead(Map<String, dynamic>.from(lead as Map)),
        if (_data != null && (_leads.isNotEmpty || _page > 0))
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _button(
                'Previous',
                Icons.chevron_left,
                _page > 0 && !_changed ? () => _load(page: _page - 1) : null,
              ),
              Text(
                'Page ${_page + 1} · ${_data!['filtered_total']} matching inquiries',
                style: const TextStyle(color: WfStyle.muted),
              ),
              _button(
                'Next',
                Icons.chevron_right,
                _cursors.length > _page + 1 && !_changed
                    ? () => _load(page: _page + 1)
                    : null,
              ),
            ],
          ),
        const SizedBox(height: 18),
        const Text(
          'Refresh to include newly received inquiries. Inquiries permit a response to that request; they do not grant marketing or outbound-call permission. CRM preferences still apply.',
          style: TextStyle(color: WfStyle.muted, fontSize: 12, height: 1.5),
        ),
      ],
    );
  }

  Widget _lead(Map<String, dynamic> lead) {
    final source = lead['utm']?['utm_source']?.toString() ?? '';
    final created =
        DateTime.tryParse(
          '${lead['created_at']}',
        )?.toLocal().toString().split('.').first ??
        '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: WfStyle.background,
        border: Border.all(color: WfStyle.line),
        borderRadius: BorderRadius.circular(16),
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
                '${lead['name']}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              WfBadge(
                lead['contact_id'] == null ? 'Inquiry' : 'CRM linked',
                color: WfStyle.violet,
              ),
              WfBadge(funnelLeadStatuses[lead['inbox_status']] ?? 'New'),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            '${lead['email']}',
            style: const TextStyle(color: WfStyle.cyan),
          ),
          if ('${lead['phone'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SelectableText('${lead['phone']}'),
            ),
          if ('${lead['message'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                '${lead['message']}',
                style: const TextStyle(height: 1.5),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            '$created · ${source.isEmpty ? 'Direct / untagged' : source}',
            style: const TextStyle(fontSize: 12, color: WfStyle.muted),
          ),
          const SizedBox(height: 14),
          if ('${lead['private_note'] ?? ''}'.isNotEmpty) ...[
            const Text(
              'Private note',
              style: TextStyle(
                color: WfStyle.violet,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${lead['private_note']}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(height: 1.5),
            ),
            const SizedBox(height: 14),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (lead['inbox_version'] is int)
                _button(
                  'Manage lead',
                  Icons.edit_note,
                  () => _manageLead('${lead['id']}'),
                ),
              _button(
                'Delete inquiry',
                Icons.delete_outline,
                () => _cleanup(leadId: '${lead['id']}'),
              ),
              _button(
                'Queue follow-up',
                Icons.playlist_add,
                () => _run(() => widget.onQueue('${lead['id']}')),
              ),
              _button(
                'Copy email',
                Icons.copy_outlined,
                () => _run(() async {
                  await Clipboard.setData(
                    ClipboardData(text: '${lead['email']}'),
                  );
                  if (mounted) setState(() => _notice = 'Email copied.');
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
