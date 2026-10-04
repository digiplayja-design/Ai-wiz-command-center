import 'dart:async';
import 'package:flutter/material.dart';
import 'contacts_client.dart';
import 'contacts_style.dart';

class CrmDirectoryScreen extends StatefulWidget {
  const CrmDirectoryScreen({super.key, required this.client});
  final ContactsClient client;
  @override
  State<CrmDirectoryScreen> createState() => _CrmDirectoryScreenState();
}

class _CrmDirectoryScreenState extends State<CrmDirectoryScreen> {
  final _query = TextEditingController(),
      _city = TextEditingController(),
      _country = TextEditingController();
  final _previewAnchor = GlobalKey();
  CrmJson _settings = {}, _preview = {};
  List<String> _categories = [];
  String _category = '';
  bool _verified = false,
      _loading = true,
      _busy = false,
      _dirty = false,
      _hasLoaded = false,
      _locked = false;
  String? _error, _notice;
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_lock);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.client.removeAccessDeniedListener(_lock);
    _query.dispose();
    _city.dispose();
    _country.dispose();
    super.dispose();
  }

  void _lock() {
    if (!mounted) return;
    setState(() {
      _locked = true;
      _settings = {};
      _preview = {};
      _query.clear();
      _city.clear();
      _country.clear();
    });
  }

  void _setSettings(CrmJson settings, {bool keepEdits = false}) {
    _settings = settings;
    if (keepEdits) return;
    final f = crmMap(settings['filters']);
    _query.text = f['q'] ?? '';
    _category = f['category'] ?? '';
    _city.text = f['city'] ?? '';
    _country.text = f['country'] ?? '';
    _verified = f['verified_only'] == true;
    _dirty = false;
  }

  Future<void> _load() async {
    try {
      final r = await widget.client.request('GET', '/directory-sync');
      if (!mounted || _locked) return;
      setState(() {
        _setSettings(crmMap(r['settings']));
        _categories = (r['categories'] as List? ?? [])
            .whereType<String>()
            .toList();
        _loading = false;
        _hasLoaded = true;
        _error = null;
      });
    } catch (e) {
      if (mounted && !_locked) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    if (_busy || _locked) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Reload saved filters?'),
          content: const Text(
            'This replaces your unsaved filter changes with the latest saved settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Reload'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted || _locked) return;
    }
    await _run(_load);
  }

  CrmJson get _filters => {
    'q': _query.text.trim(),
    'category': _category,
    'city': _city.text.trim(),
    'country': _country.text.trim(),
    'verified_only': _verified,
  };
  void _changed() => setState(() {
    _dirty = true;
    _preview = {};
    _notice = null;
  });
  Future<void> _run(Future<void> Function() fn) async {
    if (_busy || _locked) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async => _run(() async {
    final r = await widget.client.request(
      'PUT',
      '/directory-sync',
      body: {'version': _settings['version'] ?? 0, 'filters': _filters},
    );
    if (!mounted || _locked) return;
    setState(() {
      _setSettings(crmMap(r['settings']));
      _notice =
          'Filters saved. Turn on auto-pull or pull matching listings now.';
    });
  });
  Future<void> _showPreview() async => _run(() async {
    final r = await widget.client.request(
      'POST',
      '/directory-sync/preview',
      body: {'filters': _filters},
    );
    if (!mounted || _locked) return;
    setState(() => _preview = r);
    await WidgetsBinding.instance.endOfFrame;
    final anchor = _previewAnchor.currentContext;
    if (mounted && !_locked && anchor != null && anchor.mounted) {
      await Scrollable.ensureVisible(
        anchor,
        duration: const Duration(milliseconds: 250),
      );
    }
  });
  String get _filterSummary => [
    _category.isEmpty ? 'All business categories' : _category,
    if (_query.text.trim().isNotEmpty) 'Search: ${_query.text.trim()}',
    _city.text.trim().isEmpty
        ? 'All cities and service areas'
        : 'City / service area: ${_city.text.trim()}',
    _country.text.trim().isEmpty
        ? 'All countries'
        : 'Country: ${_country.text.trim()}',
    if (_verified) 'Verified listings only',
  ].join('\n');
  Future<bool> _confirm(bool automatic) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(
            automatic
                ? 'Enable automatic imports?'
                : 'Pull matching listings now?',
          ),
          content: SingleChildScrollView(
            child: Text(
              '$_filterSummary\n\n${_dirty || (_settings['version'] ?? 0) == 0 ? 'These filters will be saved automatically. ${!automatic && _settings['enabled'] == true ? 'Auto-pull will pause when the new filters are saved. ' : ''}\n\n' : ''}Add up to 100 currently matching KORLIX Business Directory listings as CRM leads${automatic ? ' each hour' : ''}. Existing and archived contacts are skipped.\n\nEmail and call permission will remain unset for imported leads.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(automatic ? 'Enable auto-pull' : 'Import leads'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _action(String action, {bool? enabled}) async {
    if (_busy || _locked || !_hasLoaded) return;
    if ((action == 'run' || enabled == true) &&
        !await _confirm(enabled == true)) {
      return;
    }
    if (!mounted || _locked) return;
    await _run(() async {
      // Activation is one clear action, including the first default selection.
      // Pausing never saves or discards unsaved filter edits.
      final pausing = action == 'toggle' && enabled == false;
      if (!pausing && (_dirty || (_settings['version'] ?? 0) == 0)) {
        final saved = await widget.client.request(
          'PUT',
          '/directory-sync',
          body: {'version': _settings['version'] ?? 0, 'filters': _filters},
        );
        if (!mounted || _locked) return;
        setState(() => _setSettings(crmMap(saved['settings'])));
      }
      final r = await widget.client.request(
        'POST',
        '/directory-sync/actions',
        body: {
          'action': action,
          'version': _settings['version'],
          'enabled': ?enabled,
          'confirmed': true,
        },
      );
      if (!mounted || _locked) return;
      if (action == 'run') {
        await _load();
        if (mounted && !_locked) {
          setState(() {
            _preview = {};
            _notice =
                '${r['imported']} leads added. ${r['skipped']} changed or duplicate listings skipped.';
          });
        }
      } else {
        setState(() {
          _setSettings(crmMap(r['settings']), keepEdits: pausing && _dirty);
          _notice = enabled == true
              ? 'Auto-pull is on. The first check starts shortly.'
              : 'Auto-pull paused.';
        });
      }
    });
  }

  String _time(dynamic value) {
    final d = DateTime.tryParse('$value');
    if (d == null) return 'Not yet';
    final local = d.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final saved = (_settings['version'] ?? 0) > 0,
        enabled = _settings['enabled'] == true,
        canRun = !_busy && _hasLoaded;
    return Theme(
      data: CrmStyle.theme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('CRM · Auto-pull listings'),
          actions: [
            IconButton(
              tooltip: 'Refresh import status',
              onPressed: _busy || _locked ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: _locked
              ? const Center(child: Text('Reopen CRM after signing in.'))
              : _loading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  CrmStyle.violet.withValues(alpha: .2),
                                  CrmStyle.cyan.withValues(alpha: .07),
                                ],
                              ),
                              border: Border.all(color: CrmStyle.line),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.storefront_rounded,
                                  color: CrmStyle.cyan,
                                  size: 32,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Find businesses. Build your contact list.',
                                  style: TextStyle(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Bring published KORLIX Business Directory listings into your CRM as leads. Choose the kinds of businesses and places you want, then preview or import.',
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Imports include public business names, available email and phone numbers, websites and location details. Source: KORLIX Business Directory.',
                                  style: TextStyle(
                                    color: CrmStyle.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            'Choose your listings',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            key: const Key('directory-query'),
                            controller: _query,
                            enabled: !_busy,
                            maxLength: 120,
                            onChanged: (_) => _changed(),
                            decoration: const InputDecoration(
                              labelText: 'Business name or keyword',
                              hintText:
                                  'For example: plumbing, bakery or solar',
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            key: ValueKey('directory-category-$_category'),
                            initialValue: _category,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Business category',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('All categories'),
                              ),
                              for (final c in _categories)
                                DropdownMenuItem(
                                  value: c,
                                  child: Text(
                                    c,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (v) {
                                    _category = v ?? '';
                                    _changed();
                                  },
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, box) {
                              final fields = [
                                TextField(
                                  key: const Key('directory-city'),
                                  controller: _city,
                                  enabled: !_busy,
                                  maxLength: 100,
                                  onChanged: (_) => _changed(),
                                  decoration: const InputDecoration(
                                    labelText: 'City or service area',
                                    hintText: 'For example: Kingston',
                                  ),
                                ),
                                TextField(
                                  key: const Key('directory-country'),
                                  controller: _country,
                                  enabled: !_busy,
                                  maxLength: 100,
                                  onChanged: (_) => _changed(),
                                  decoration: const InputDecoration(
                                    labelText: 'Country',
                                    hintText:
                                        'Use the listing’s country, e.g. Jamaica',
                                  ),
                                ),
                              ];
                              return box.maxWidth < 550
                                  ? Column(
                                      children: [
                                        fields[0],
                                        const SizedBox(height: 12),
                                        fields[1],
                                      ],
                                    )
                                  : Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: fields[0]),
                                        const SizedBox(width: 16),
                                        Expanded(child: fields[1]),
                                      ],
                                    );
                            },
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _verified,
                            onChanged: _busy
                                ? null
                                : (v) {
                                    _verified = v ?? false;
                                    _changed();
                                  },
                            title: const Text('Verified listings only'),
                            subtitle: const Text(
                              'Uses the current Directory verified badge.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                key: const Key('directory-preview'),
                                onPressed: _busy ? null : _showPreview,
                                icon: const Icon(Icons.preview_outlined),
                                label: const Text('Preview matches'),
                              ),
                              FilledButton.icon(
                                key: const Key('directory-save'),
                                onPressed: _busy ? null : _save,
                                icon: const Icon(Icons.save_outlined),
                                label: const Text('Save filters'),
                              ),
                            ],
                          ),
                          if (_dirty || !saved)
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Text(
                                'Enable auto-pull or Pull now will save these filters for you. Save filters alone keeps imports paused.',
                                style: TextStyle(
                                  color: CrmStyle.gold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                _error!,
                                style: const TextStyle(color: CrmStyle.danger),
                              ),
                            ),
                          if (_notice != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                _notice!,
                                style: const TextStyle(color: CrmStyle.cyan),
                              ),
                            ),
                          const SizedBox(height: 24),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    enabled
                                        ? 'Auto-pull is on'
                                        : 'Auto-pull is paused',
                                    style: TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700,
                                      color: enabled
                                          ? CrmStyle.cyan
                                          : CrmStyle.gold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Checks every hour. Up to 100 new listings per run. Duplicates are checked by listing ID, email and phone, including archived contacts.',
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Leads added: ${_settings['imported_total'] ?? 0}\nLast check: ${_time(_settings['last_run_at'])}${enabled ? '\nNext check: ${_time(_settings['next_run_at'])}' : ''}',
                                  ),
                                  if (crmMap(
                                        _settings['last_result'],
                                      )['reason'] !=
                                      null)
                                    Text(
                                      '${crmMap(_settings['last_result'])['reason']}',
                                    ),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton.icon(
                                        key: const Key('directory-pull-now'),
                                        onPressed: canRun
                                            ? () => _action('run')
                                            : null,
                                        icon: const Icon(
                                          Icons.download_rounded,
                                        ),
                                        label: const Text('Pull now'),
                                      ),
                                      OutlinedButton(
                                        key: const Key('directory-toggle'),
                                        onPressed: canRun
                                            ? () => _action(
                                                'toggle',
                                                enabled: !enabled,
                                              )
                                            : null,
                                        child: Text(
                                          enabled
                                              ? 'Pause auto-pull'
                                              : 'Enable auto-pull',
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () =>
                                                  Navigator.pop(context, true),
                                        child: const Text(
                                          'View imported contacts',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Imported leads start with no email or call permission. Record permission on the contact before using outreach features.',
                                    style: TextStyle(
                                      color: CrmStyle.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_preview.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Text(
                              '${_preview['available_in_batch'] ?? 0}${_preview['more_available'] == true ? '+' : ''} new matches',
                              key: _previewAnchor,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Preview of up to 25 new listings. Current and archived CRM matches are excluded. Listings are checked again when imported.',
                              style: TextStyle(
                                color: CrmStyle.muted,
                                fontSize: 12,
                              ),
                            ),
                            if (crmRows(_preview['businesses']).isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Text(
                                  'No new matching listings. Try a broader category or location.',
                                ),
                              ),
                            for (final b in crmRows(_preview['businesses']))
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${b['name']}',
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '${b['category']} · ${[b['city'], b['country']].where((v) => v != null && v != '').join(', ')}',
                                      ),
                                      if (b['email'] != null)
                                        Text('${b['email']}'),
                                      if (b['phone'] != null)
                                        Text('${b['phone']}'),
                                      if (b['website'] != null &&
                                          b['website'] != '')
                                        Text('${b['website']}'),
                                      if (b['verified'] == true)
                                        const Text(
                                          'Verified listing',
                                          style: TextStyle(
                                            color: CrmStyle.cyan,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
