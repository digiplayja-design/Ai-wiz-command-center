import '../receipt_wiz/receipt_wiz_entry.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../bookkeeping/bookkeeping_client.dart';
import '../bookkeeping/bookkeeping_models.dart';
import '../bookkeeping/bookkeeping_file_save.dart';
import 'tax_prep_models.dart';
import 'tax_prep_report.dart';

const _ink = Color(0xFF152D46),
    _teal = Color(0xFF087E91),
    _muted = Color(0xFF617285),
    _line = Color(0xFFDDE7EF);

class TaxPrepScreen extends StatefulWidget {
  const TaxPrepScreen({
    super.key,
    required this.client,
    this.disposeClient = false,
    this.initialBusinessId,
    this.initialYear,
    this.openBookkeeping,
    this.saveFile,
    this.renderPdf,
  });
  final BookkeepingClient client;
  final bool disposeClient;
  final String? initialBusinessId;
  final int? initialYear;
  final Future<void> Function()? openBookkeeping;
  final Future<void> Function(Uint8List, String, String, Rect)? saveFile;
  final Future<Uint8List> Function(Map<String, dynamic>)? renderPdf;
  @override
  State<TaxPrepScreen> createState() => _TaxPrepScreenState();
}

class _TaxPrepScreenState extends State<TaxPrepScreen> {
  List<Map<String, dynamic>> _workspaces = [], _businesses = [];
  Map<String, dynamic>? _packet, _pendingSave, _pendingBooks;
  Map<String, dynamic> _data = {};
  bool _loading = true,
      _busy = false,
      _locked = false,
      _dirty = false,
      _dialogOpen = false;
  int _year = DateTime.now().year, _tab = 0, _operation = 0;
  String? _error, _createKey;
  final _exportKey = GlobalKey();
  Map<String, dynamic> get _w => taxMap(_packet?['workspace']);
  bool get _has => _packet != null;
  bool get _stale => _packet?['stale'] == true;
  List<Map<String, dynamic>> get _books => taxRows(_w['books']);
  @override
  void initState() {
    super.initState();
    _year = widget.initialYear ?? _year;
    widget.client.addAccessDeniedListener(_lock);
    unawaited(_load());
  }

  @override
  void dispose() {
    _operation++;
    widget.client.removeAccessDeniedListener(_lock);
    if (widget.disposeClient) widget.client.dispose();
    super.dispose();
  }

  bool _current(int n) => mounted && !_locked && n == _operation;
  void _lock() {
    if (!mounted) return;
    _operation++;
    if (_dialogOpen) Navigator.of(context).pop();
    setState(() {
      _locked = true;
      _workspaces = [];
      _businesses = [];
      _packet = _pendingSave = _pendingBooks = null;
      _data = {};
      _error = null;
      _busy = false;
      _dirty = false;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _accept(Map<String, dynamic> p) {
    _packet = taxPacket(p);
    _year = _w['year'];
    _data = taxMap(jsonDecode(jsonEncode(_w['data'])));
    _dirty = false;
    _pendingSave = _pendingBooks = null;
    _error = null;
  }

  void _changed(void Function() edit) {
    if (_busy || _locked) return;
    setState(() {
      edit();
      _dirty = true;
      _pendingSave = null;
      _error = null;
    });
  }

  Future<T?> _dialog<T>(Widget Function(BuildContext) builder) async {
    if (_locked) return null;
    _dialogOpen = true;
    try {
      return await showDialog<T>(
        context: context,
        barrierDismissible: false,
        builder: builder,
      );
    } finally {
      _dialogOpen = false;
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await _dialog<bool>(
        (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;
  Future<bool> _discard() async =>
      !_dirty ||
      await _confirm(
        'Discard unsaved changes?',
        'Your latest organizer edits have not been saved.',
      );
  Future<void> _load({String? id}) async {
    if (_locked || _busy) return;
    final op = ++_operation;
    setState(() => _busy = true);
    try {
      final index = await widget.client.request('GET', '/tax-prep');
      if (!_current(op)) return;
      if (index['workspaces'] is! List || index['businesses'] is! List) {
        throw const BookkeepingException(
          'The tax workspace list could not be read.',
        );
      }
      _workspaces = taxRows(index['workspaces']);
      _businesses = taxRows(index['businesses']);
      final target =
          id ?? _workspaces.where((x) => x['year'] == _year).firstOrNull?['id'];
      if (target != null) {
        final p = taxPacket(
          await widget.client.request('GET', '/tax-prep/$target'),
          expectedId: target,
        );
        if (!_current(op)) return;
        _accept(p);
      } else {
        _packet = null;
        _data = {};
        _dirty = false;
      }
      if (_current(op)) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (_current(op)) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    } finally {
      if (_current(op)) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    if (_busy || !await _discard() || !mounted || _locked) return;
    await _load(id: _w['id']);
  }

  Future<void> _selectYear(int value) async {
    if (_busy || value == _year || !await _discard() || !mounted || _locked) {
      return;
    }
    setState(() {
      _year = value;
      _dirty = false;
      _packet = null;
      _data = {};
      _createKey = null;
      _tab = 0;
      _pendingSave = _pendingBooks = null;
      _error = null;
    });
    await _load();
  }

  Future<void> _create() async {
    if (_busy || _locked) return;
    final op = ++_operation;
    setState(() => _busy = true);
    try {
      final key = _createKey ??= bookkeepingRequestKey();
      final p = await widget.client.request(
        'POST',
        '/tax-prep',
        body: {
          'request_key': key,
          'year': _year,
          'business_ids': widget.initialBusinessId == null
              ? []
              : [widget.initialBusinessId],
        },
      );
      if (!_current(op)) return;
      setState(() => _accept(p));
      _workspaces.removeWhere((x) => x['year'] == _year);
      _workspaces.add({
        'id': _w['id'],
        'year': _year,
        'version': _w['version'],
      });
      _createKey = null;
    } catch (e) {
      if (_current(op)) setState(() => _error = '$e');
    } finally {
      if (_current(op)) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _locked || !_has || !_dirty) return;
    final op = ++_operation;
    setState(() => _busy = true);
    try {
      _pendingSave ??= {
        'version': _w['version'],
        'request_key': bookkeepingRequestKey(),
        'data': jsonDecode(jsonEncode(_data)),
      };
      final p = taxPacket(
        await widget.client.request(
          'PUT',
          '/tax-prep/${_w['id']}',
          body: _pendingSave,
        ),
        expectedId: _w['id'],
      );
      if (!_current(op)) return;
      setState(() => _accept(p));
    } catch (e) {
      if (_current(op)) setState(() => _error = '$e');
    } finally {
      if (_current(op)) setState(() => _busy = false);
    }
  }

  Future<void> _linkBooks() async {
    if (_busy || _locked || !_has) return;
    if (_dirty) {
      _feedback('Save your organizer edits before refreshing linked books.');
      return;
    }
    final selected = Set<String>.from(
      _pendingBooks?['business_ids'] ?? _w['businessIds'],
    );
    if (widget.initialBusinessId != null && _pendingBooks == null) {
      selected.add(widget.initialBusinessId!);
    }
    final ids = await _dialog<List<String>>(
      (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Link your Bookkeeping records'),
          content: SizedBox(
            width: 530,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pull recorded USD books for January 1–December 31, $_year. Each business stays separate.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'When source records change, account review marks reset. Notes for remaining accounts are kept.',
                  ),
                  const SizedBox(height: 14),
                  if (_businesses.isEmpty)
                    const Text(
                      'Create a business in Bookkeeping first, or continue with a personal organizer.',
                    ),
                  for (final b in _businesses)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: selected.contains(b['id']),
                      title: Text(b['name']),
                      subtitle: Text(
                        taxTreatments[b['tax_treatment']] ??
                            'Confirm tax treatment',
                      ),
                      onChanged: (v) => update(() {
                        if (v == true) {
                          selected.add(b['id']);
                        } else {
                          selected.remove(b['id']);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, selected.toList()..sort()),
              child: const Text('Link and refresh'),
            ),
          ],
        ),
      ),
    );
    if (ids == null || !mounted || _locked) return;
    final op = ++_operation;
    setState(() => _busy = true);
    try {
      if (_pendingBooks == null ||
          jsonEncode(_pendingBooks!['business_ids']) != jsonEncode(ids) ||
          _pendingBooks!['version'] != _w['version']) {
        _pendingBooks = {
          'version': _w['version'],
          'request_key': bookkeepingRequestKey(),
          'business_ids': ids,
          'confirmed': true,
        };
      }
      final p = taxPacket(
        await widget.client.request(
          'POST',
          '/tax-prep/${_w['id']}/books',
          body: _pendingBooks,
        ),
        expectedId: _w['id'],
      );
      if (!_current(op)) return;
      setState(() => _accept(p));
    } catch (e) {
      if (_current(op)) setState(() => _error = '$e');
    } finally {
      if (_current(op)) setState(() => _busy = false);
    }
  }

  void _feedback(String s) {
    if (mounted && !_locked) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> _editNotes() async {
    final c = TextEditingController(text: _data['notes']);
    try {
      final s = await _dialog<String>(
        (d) => AlertDialog(
          title: const Text('Questions for your preparer'),
          content: SizedBox(
            width: 520,
            child: TextField(
              controller: c,
              maxLines: 7,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText:
                    'Questions, unusual transactions or records to discuss. Do not enter tax IDs or bank details.',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, c.text),
              child: const Text('Keep note'),
            ),
          ],
        ),
      );
      if (s != null && mounted && !_locked) _changed(() => _data['notes'] = s);
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    }
  }

  Future<void> _review(String businessId, Map<String, dynamic> a) async {
    final reviews = taxMap(_data['reviews']),
        mine = taxMap(reviews[businessId]),
        r = taxMap(mine[a['code']]);
    String status = r['status'] ?? 'pending';
    final c = TextEditingController(text: r['note'] ?? '');
    try {
      final result = await _dialog<Map<String, dynamic>>(
        (d) => StatefulBuilder(
          builder: (d, update) => AlertDialog(
            title: Text('${a['code']} · ${a['name']}'),
            content: SizedBox(
              width: 510,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recorded book amount: ${bookkeepingMoney(a['book_cents'])}',
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Review classification and supporting records. This mark does not decide tax deductibility.',
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      isExpanded: true,
                      items: taxReviewStatuses.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => update(() => status = v!),
                      decoration: const InputDecoration(
                        labelText: 'Review status',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: c,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Review note',
                        hintText:
                            'Questions, evidence or adjustments to discuss.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(d),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(d, {'status': status, 'note': c.text}),
                child: const Text('Keep review'),
              ),
            ],
          ),
        ),
      );
      if (result != null && mounted && !_locked) {
        _changed(() {
          mine[a['code']] = result;
          reviews[businessId] = mine;
          _data['reviews'] = reviews;
        });
      }
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    }
  }

  Future<void> _export(String format) async {
    if (_busy || _locked || !_has || _dirty || _stale) return;
    final op = ++_operation;
    setState(() => _busy = true);
    try {
      final w = Map<String, dynamic>.from(_w);
      final r = await widget.client.request(
        'POST',
        '/tax-prep/${w['id']}/export',
        body: {
          'version': w['version'],
          'fingerprint': w['fingerprint'],
          'format': format,
        },
      );
      if (!_current(op)) return;
      Uint8List bytes;
      String mime, name;
      if (format == 'csv') {
        if (r['csv'] is! String ||
            r['year'] != w['year'] ||
            r['version'] != w['version']) {
          throw const BookkeepingException(
            'The export did not match your organizer. Refresh and retry.',
          );
        }
        bytes = Uint8List.fromList(utf8.encode(r['csv']));
        mime = 'text/csv';
        name = 'KORLIX-Tax-Prep-${w['year']}-r${w['version']}.csv';
      } else {
        final packet = taxPacket(taxMap(r['packet']), expectedId: w['id']);
        if (taxMap(packet['workspace'])['version'] != w['version']) {
          throw const BookkeepingException(
            'The packet changed. Refresh and retry.',
          );
        }
        try {
          bytes = await (widget.renderPdf ?? buildTaxPrepPdf)(packet);
        } catch (_) {
          throw const BookkeepingException(
            'The PDF could not be prepared. Try the CSV export or link fewer businesses.',
          );
        }
        mime = 'application/pdf';
        name = 'KORLIX-Tax-Prep-${w['year']}-r${w['version']}.pdf';
      }
      if (!_current(op)) return;
      final box = _exportKey.currentContext?.findRenderObject() as RenderBox?;
      final origin = box == null
          ? const Rect.fromLTWH(0, 0, 1, 1)
          : box.localToGlobal(Offset.zero) & box.size;
      await (widget.saveFile ?? saveBookkeepingFile)(bytes, name, mime, origin);
    } catch (e) {
      if (_current(op)) setState(() => _error = '$e');
    } finally {
      if (_current(op)) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (_busy ||
        _locked ||
        !_has ||
        !await _confirm(
          'Remove this tax organizer?',
          'This removes the checklist, review notes and saved snapshots for this year. Original Bookkeeping records remain available.',
        ) ||
        !mounted ||
        _locked) {
      return;
    }
    final op = ++_operation;
    setState(() => _busy = true);
    try {
      final r = await widget.client.request(
        'DELETE',
        '/tax-prep/${_w['id']}',
        body: {'version': _w['version'], 'confirmed': true},
      );
      if (!_current(op)) return;
      if (r['deleted'] != true) {
        throw const BookkeepingException(
          'Removal was not confirmed. Refresh before retrying.',
        );
      }
      setState(() {
        _packet = null;
        _data = {};
        _dirty = false;
        _pendingSave = _pendingBooks = null;
        _workspaces.removeWhere((x) => x['year'] == _year);
        _error = null;
      });
    } catch (e) {
      if (_current(op)) setState(() => _error = '$e');
    } finally {
      if (_current(op)) setState(() => _busy = false);
    }
  }

  Future<void> _openBooks() async {
    if (_busy || !await _discard() || !mounted || _locked) return;
    if (widget.openBookkeeping != null) {
      await widget.openBookkeeping!();
      if (mounted && !_locked) await _load(id: _w['id']);
    } else {
      Navigator.of(context).pop();
    }
  }

  Widget _card(Widget child, {EdgeInsets padding = const EdgeInsets.all(24)}) =>
      Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Material(type: MaterialType.transparency, child: child),
      );
  Widget _heading(String s) => Text(
    s,
    style: const TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: _ink,
    ),
  );
  Widget _note(String s) =>
      Text(s, style: const TextStyle(color: _muted, fontSize: 13, height: 1.5));
  Widget _pill(String s) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFE8F5F7),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      s,
      style: const TextStyle(
        color: _teal,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
  Widget _stat(String label, String value) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF2F7FA),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: _ink,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
  Widget _overview() {
    final checks = taxMap(_data['checklist']);
    final ready = checks.values.where((v) => v == 'ready').length,
        na = checks.values.where((v) => v == 'not_applicable').length;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _pill('United States · USD · Calendar year'),
              _pill(
                _dirty ? 'Unsaved edits' : 'Saved revision ${_w['version']}',
              ),
              if (_stale) _pill('Books changed'),
            ],
          ),
          const SizedBox(height: 18),
          _heading('Your $_year preparation workspace'),
          const SizedBox(height: 8),
          _note(
            'Bring your records together, review each business and prepare a clear handoff.',
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: (ready + na) / taxChecklist.length,
            color: _teal,
            backgroundColor: _line,
            minHeight: 7,
            borderRadius: BorderRadius.circular(10),
          ),
          const SizedBox(height: 10),
          _note(
            '$ready organized · $na not applicable · ${taxChecklist.length - ready - na} to gather. Organization progress only.',
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                key: const ValueKey('tax-save'),
                onPressed: _busy || !_dirty ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(_busy ? 'Working…' : 'Save organizer'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('tax-link'),
                onPressed: _busy || _dirty ? null : _linkBooks,
                icon: const Icon(Icons.link, size: 18),
                label: const Text('Link / refresh books'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _openBooks,
                icon: const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 18,
                ),
                label: const Text('Open Bookkeeping'),
              ),
            ],
          ),
          if (_dirty) ...[
            const SizedBox(height: 8),
            _note('Save edits to enable book refresh and exports.'),
          ],
          if (_stale) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4DE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Linked Bookkeeping records changed after this snapshot. Refresh the linked books and review affected accounts before exporting.',
                style: TextStyle(color: Color(0xFF7F5810), height: 1.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _personal() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading('Personal organizer'),
            const SizedBox(height: 8),
            _note(
              'Mark the records you have organized. Keep originals securely; use your preparer’s secure process for tax IDs and source tax forms.',
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              key: ValueKey('filing-${_w['id']}-${_w['version']}'),
              initialValue: _data['filingStatus'],
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Expected filing status · confirm eligibility',
                border: OutlineInputBorder(),
              ),
              items: taxFilingStatuses.entries
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (v) => _changed(() => _data['filingStatus'] = v),
            ),
            const SizedBox(height: 18),
            _note('States to discuss with your preparer (up to 10)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: taxStates
                  .map(
                    (s) => FilterChip(
                      label: Text(s),
                      selected: (_data['states'] as List).contains(s),
                      onSelected: _busy
                          ? null
                          : (yes) {
                              final states = List<String>.from(_data['states']);
                              if (yes && states.length >= 10) {
                                _feedback(
                                  'Choose up to 10 states. Note any others for your preparer.',
                                );
                                return;
                              }
                              _changed(() {
                                if (yes) {
                                  states.add(s);
                                } else {
                                  states.remove(s);
                                }
                                _data['states'] = states;
                              });
                            },
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading('Gather your documents'),
            const SizedBox(height: 6),
            _note(
              'Selecting “Not applicable” is your assessment, not an eligibility determination.',
            ),
            const SizedBox(height: 14),
            for (final e in taxChecklist.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: LayoutBuilder(
                  builder: (c, s) {
                    final field = DropdownButtonFormField<String>(
                      key: ValueKey(
                        'check-${e.key}-${_w['id']}-${_w['version']}',
                      ),
                      initialValue: taxMap(_data['checklist'])[e.key],
                      isExpanded: true,
                      items: taxChecklistStatuses.entries
                          .map(
                            (x) => DropdownMenuItem(
                              value: x.key,
                              child: Text(x.value),
                            ),
                          )
                          .toList(),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      onChanged: _busy
                          ? null
                          : (v) =>
                                _changed(() => _data['checklist'][e.key] = v),
                    );
                    return s.maxWidth < 560
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.value,
                                style: const TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              field,
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.value,
                                  style: const TextStyle(
                                    color: _ink,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 20),
                              SizedBox(width: 180, child: field),
                            ],
                          );
                  },
                ),
              ),
            const Divider(height: 30),
            Row(
              children: [
                Expanded(child: _heading('Questions for your preparer')),
                IconButton(
                  key: const ValueKey('tax-edit-notes'),
                  tooltip: 'Edit preparer notes',
                  onPressed: _busy ? null : _editNotes,
                  icon: const Icon(Icons.edit_outlined, color: _teal),
                ),
              ],
            ),
            _note(
              (_data['notes'] as String).isEmpty
                  ? 'Record unusual transactions, missing records and questions here.'
                  : _data['notes'],
            ),
          ],
        ),
      ),
    ],
  );
  Widget _businessReview() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('Linked business records'),
      const SizedBox(height: 7),
      _note(
        'Snapshot: ${_w['snapshotAt']}. Income and expense figures are annual recorded activity. Other accounts show the recorded year-end balance.',
      ),
      const SizedBox(height: 16),
      if (_books.isEmpty)
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.link, size: 38, color: _teal),
              const SizedBox(height: 12),
              _heading('Connect your Bookkeeping'),
              const SizedBox(height: 8),
              _note(
                'Pull income, expenses, balances, receipt-link counts and recorded mileage into this organizer.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy || _dirty ? null : _linkBooks,
                icon: const Icon(Icons.add_link),
                label: const Text('Choose businesses'),
              ),
            ],
          ),
        ),
      for (final b in _books) ...[
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(taxMap(b['business'])['name']),
              const SizedBox(height: 7),
              _note(
                '${businessStructures[taxMap(b['business'])['legal_structure']] ?? 'Business'} · ${taxTreatments[taxMap(b['business'])['tax_treatment']] ?? 'Confirm tax treatment'}',
              ),
              const SizedBox(height: 8),
              _note('${b['treatmentNote']}'),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (c, s) {
                  final wide = s.maxWidth >= 610;
                  final width = wide ? (s.maxWidth - 24) / 3 : s.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: width,
                        child: _stat(
                          'Recorded income',
                          bookkeepingMoney(
                            taxMap(b['summary'])['income_cents'],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _stat(
                          'Recorded expenses',
                          bookkeepingMoney(
                            taxMap(b['summary'])['expense_cents'],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _stat(
                          'Net book result',
                          bookkeepingMoney(taxMap(b['summary'])['net_cents']),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              _note(
                'Book figures require tax adjustments. They do not calculate taxable income or a refund.',
              ),
              const SizedBox(height: 12),
              _note(
                '${taxMiles(taxMap(b['mileage'])['distance_tenths'])} active recorded miles · ${taxMap(b['mileage'])['trip_count']} trips. No mileage deduction calculated.',
              ),
              _note(
                '${taxMap(b['receipts'])['without_receipt']} of ${taxMap(b['receipts'])['expense_count']} active expenses have no linked receipt. Check supporting records; a link does not establish deductibility.',
              ),
              for (final warning in b['warnings'] as List? ?? [])
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _note('Review: $warning'),
                ),
              const Divider(height: 32),
              _heading('Review the accounts'),
              const SizedBox(height: 7),
              _note(
                'Keep evidence notes and questions for your preparer. Corrections to source figures belong in Bookkeeping.',
              ),
              const SizedBox(height: 12),
              if (taxRows(b['accounts']).isEmpty)
                _note('No account activity is present in this snapshot.'),
              for (final a in taxRows(b['accounts'])) ...[
                _accountRow(taxMap(b['business'])['id'], a),
                const Divider(height: 22),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
      _note(
        'These are manual recorded books. Statement matching progress does not establish complete reconciliation. Review inventory, depreciation, accruals, payroll, owner basis and fiscal-year requirements separately.',
      ),
    ],
  );
  Widget _accountRow(String bid, Map<String, dynamic> a) {
    final r = taxMap(taxMap(taxMap(_data['reviews'])[bid])[a['code']]);
    final status = r['status'] ?? 'pending';
    return LayoutBuilder(
      builder: (c, s) {
        final description = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${a['code']} · ${a['name']}',
              style: const TextStyle(fontWeight: FontWeight.w700, color: _ink),
            ),
            const SizedBox(height: 5),
            _note('${a['kind']} · ${bookkeepingMoney(a['book_cents'])}'),
            if ('${r['note'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 4),
              _note('${r['note']}'),
            ],
          ],
        );
        final action = OutlinedButton.icon(
          key: ValueKey('review-$bid-${a['code']}'),
          onPressed: _busy ? null : () => _review(bid, a),
          icon: Icon(
            status == 'reviewed'
                ? Icons.check_circle_outline
                : status == 'ask_preparer'
                ? Icons.help_outline
                : Icons.edit_note,
            size: 18,
          ),
          label: Text(taxReviewStatuses[status] ?? 'Needs review'),
        );
        return s.maxWidth < 560
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [description, const SizedBox(height: 10), action],
              )
            : Row(
                children: [
                  Expanded(child: description),
                  const SizedBox(width: 18),
                  action,
                ],
              );
      },
    );
  }

  Widget _handoff() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading('Prepare your handoff'),
            const SizedBox(height: 9),
            _note(
              'Download a draft packet with your checklist, business summaries, review notes and source references. Unresolved items remain visible for your preparer.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF7F9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Preparation workspace\nTax liability, refunds and filing are not calculated or submitted here. Final return preparation and filing require a qualified preparer or supported filing provider.',
                style: TextStyle(color: _ink, height: 1.6),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              key: _exportKey,
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  key: const ValueKey('tax-export-pdf'),
                  onPressed: _busy || _dirty || _stale
                      ? null
                      : () => _export('packet'),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Download PDF packet'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('tax-export-csv'),
                  onPressed: _busy || _dirty || _stale
                      ? null
                      : () => _export('csv'),
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('Download CSV'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _note(
              _dirty
                  ? 'Save your edits before downloading.'
                  : _stale
                  ? 'Refresh and review the changed books before downloading.'
                  : 'Downloads stay under your control. Nothing is sent to a preparer automatically.',
            ),
            const Divider(height: 32),
            _heading('Before filing'),
            const SizedBox(height: 10),
            _note(
              'Confirm all income sources, document completeness, jurisdiction, filing status and entity treatment. Check the applicable year’s tax rules, required adjustments and state obligations. Keep original documents and complete ledger exports with your records.',
            ),
            const SizedBox(height: 20),
            _heading('Official guidance'),
            const SizedBox(height: 8),
            for (final source in taxRows(_packet?['sources']))
              TextButton.icon(
                onPressed: () async {
                  final uri = Uri.tryParse('${source['url']}');
                  if (uri != null &&
                      uri.scheme == 'https' &&
                      uri.host == 'www.irs.gov') {
                    await launchUrl(uri, webOnlyWindowName: '_blank');
                  }
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text('${source['label']}'),
              ),
            const Divider(height: 28),
            TextButton.icon(
              onPressed: _busy ? null : _remove,
              icon: const Icon(Icons.delete_outline, color: Colors.deepOrange),
              label: const Text(
                'Remove this organizer',
                style: TextStyle(color: Colors.deepOrange),
              ),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _empty() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.fact_check_outlined, size: 48, color: _teal),
        const SizedBox(height: 18),
        _heading('Start your $_year tax organizer'),
        const SizedBox(height: 10),
        _note(
          'Organize personal tax documents and connect business records already saved in KORLIX Bookkeeping.',
        ),
        const SizedBox(height: 12),
        _note(
          'U.S. preparation · USD · Calendar year. Business records remain separate by entity. Tax calculation and filing will use a separate filing integration.',
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          key: const ValueKey('tax-create'),
          onPressed: _busy ? null : _create,
          icon: const Icon(Icons.add),
          label: const Text('Start organizer'),
        ),
        const SizedBox(height: 14),
        _note(
          'No tax IDs, bank details or source tax-form uploads are needed to start. This organizer does not use AI processing or spend generation credits.',
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(seedColor: _teal),
      scaffoldBackgroundColor: const Color(0xFFF6F9FC),
      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
    ),
    child: PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && !_busy && await _discard() && mounted) {
          setState(() => _dirty = false);
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'KORLIX Tax Prep',
            style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
          ),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'Refresh tax organizer',
              onPressed: _busy || _locked ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _locked
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Your session changed. Sign in again and reopen Tax Prep.',
                  ),
                ),
              )
            : _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Padding(
                      padding: EdgeInsets.all(
                        MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ReceiptWizEntry(client:widget.client,year:_year,taxWorkspaceId:_w['id'] as String?),
                          LayoutBuilder(
                            builder: (c, s) {
                              final year = SizedBox(
                                width: 180,
                                child: DropdownButtonFormField<int>(
                                  key: ValueKey('tax-year-$_year'),
                                  initialValue: _year,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Calendar year',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: [
                                    for (
                                      var y = DateTime.now().year + 1;
                                      y >= 2000;
                                      y--
                                    )
                                      DropdownMenuItem(
                                        value: y,
                                        child: Text(
                                          '$y${y > DateTime.now().year ? ' · Planning' : ''}',
                                        ),
                                      ),
                                  ],
                                  onChanged: _busy
                                      ? null
                                      : (v) => _selectYear(v!),
                                ),
                              );
                              final intro = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'A clearer tax season.',
                                    style: TextStyle(
                                      fontSize: 29,
                                      fontWeight: FontWeight.w800,
                                      color: _ink,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _note('Organize. Review. Hand off.'),
                                ],
                              );
                              return s.maxWidth < 600
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        intro,
                                        const SizedBox(height: 18),
                                        year,
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        Expanded(child: intro),
                                        const SizedBox(width: 16),
                                        year,
                                      ],
                                    );
                            },
                          ),
                          const SizedBox(height: 24),
                          if (_error != null) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEEE5),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xFF8B3E17),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                          if (_busy)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 14),
                              child: LinearProgressIndicator(),
                            ),
                          if (!_has)
                            _empty()
                          else ...[
                            _overview(),
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                for (var i = 0; i < 3; i++)
                                  ChoiceChip(
                                    key: ValueKey('tax-tab-$i'),
                                    label: Text(
                                      [
                                        'Personal organizer',
                                        'Business review',
                                        'Export packet',
                                      ][i],
                                    ),
                                    selected: _tab == i,
                                    onSelected: (_) => setState(() => _tab = i),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            if (_tab == 0)
                              _personal()
                            else if (_tab == 1)
                              _businessReview()
                            else
                              _handoff(),
                          ],
                          const SizedBox(height: 24),
                          _note(
                            'Preparation only. A completed checklist does not establish tax eligibility, reconciled books or filing readiness.',
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}
