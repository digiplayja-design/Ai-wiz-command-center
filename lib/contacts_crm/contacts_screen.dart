import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../live_convo/korlix_live_convo_agent_client.dart';
import '../live_convo/korlix_live_convo_agent_email_sheet.dart';
import 'contacts_client.dart';
import 'contact_editor.dart';
import 'contact_import.dart';
import 'contacts_style.dart';
import 'contact_profile.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, required this.client});
  final ContactsClient client;
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scaffold = GlobalKey<ScaffoldState>();
  final Set<String> _selected = {};
  String? _focusedId;
  bool _filtersOpen = false, _compact = false;
  BuildContext? _surfaceContext;
  BuildContext get _dialogContext => _surfaceContext ?? context;
  Timer? _debounce;
  int _generation = 0, _offset = 0, _count = 0, _total = 0;
  bool _loading = true, _locked = false, _operation = false;
  String? _error, _emailAgent;
  String _category = '', _source = '', _segment = '', _sort = 'name';
  List<Map<String, dynamic>> _contacts = [];
  Map<String, dynamic> _categoryCounts = {};

  @override
  void initState() {
    super.initState();
    widget.client.onAccessDenied = _lock;
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    widget.client.onAccessDenied = null;
    widget.client.dispose();
    super.dispose();
  }

  void _lock() {
    if (!mounted) return;
    _generation++;
    setState(() {
      _locked = true;
      _contacts = [];
      _selected.clear();
      _focusedId = null;
      _total = 0;
      _count = 0;
      _categoryCounts = {};
      _loading = false;
    });
    final route = ModalRoute.of(context);
    if (route != null) Navigator.of(context).popUntil((r) => r == route);
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.client.request('GET', '/capabilities'),
        widget.client.request('GET', '/counts'),
        widget.client.request(
          'GET',
          '',
          query: {
            'q': _search.text,
            'category': _category,
            'source': _source,
            'segment': _segment,
            'sort': _sort,
            'offset': '$_offset',
            'limit': '50',
          },
        ),
      ]);
      if (!mounted || generation != _generation) return;
      setState(() {
        _locked = false;
        _emailAgent = results[0]['emailAgentId'];
        _total = results[1]['total'] ?? 0;
        _categoryCounts = Map<String, dynamic>.from(
          results[1]['categories'] ?? {},
        );
        _count = results[2]['count'] ?? 0;
        _contacts = (results[2]['contacts'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final ids = _contacts.map((c) => c['id'].toString()).toSet();
        _selected.removeWhere((id) => !ids.contains(id));
        if (!ids.contains(_focusedId)) {
          _focusedId = _contacts.isEmpty
              ? null
              : _contacts.first['id'].toString();
        }
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _filter(void Function() change) {
    setState(() {
      change();
      _offset = 0;
      _selected.clear();
    });
    unawaited(_load());
  }

  void _notify(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _edit([Map<String, dynamic>? c, int section = 0]) async {
    final saved = await showDialog<bool>(
      context: _dialogContext,
      barrierDismissible: false,
      builder: (_) => ContactEditor(
        contact: c,
        initialSection: section,
        onSave: (body) async {
          await widget.client.request(
            c == null ? 'POST' : 'PUT',
            c == null ? '' : '/${c['id']}',
            body: body,
          );
        },
      ),
    );
    if (saved == true && mounted) {
      _notify('Contact saved');
      await _load();
    }
  }

  Future<void> _import([String source = 'spreadsheet']) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: _dialogContext,
      barrierDismissible: false,
      builder: (_) =>
          ContactImport(client: widget.client, initialSource: source),
    );
    if (result != null && mounted) {
      _notify(
        '${result['imported']} contacts imported. ${result['duplicates']} existing contacts skipped.',
      );
      await _load();
    }
  }

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: _dialogContext,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _action(Future<void> Function() fn) async {
    if (_operation) return;
    setState(() => _operation = true);
    try {
      await fn();
    } catch (e) {
      _notify(e.toString());
    } finally {
      if (mounted) setState(() => _operation = false);
    }
  }

  Future<void> _email(Map<String, dynamic> c) => _action(() async {
    final id = _emailAgent;
    if (id == null) {
      _notify(
        'Nova Email must be configured for your Enterprise account first.',
      );
      return;
    }
    if (!await _confirm(
      'Link ${c['name']} to Nova Email?',
      'This adds the contact to Nova’s recipients. Choose a draft or autonomous rule in Email Center. No email is sent by this action.',
    )) {
      return;
    }
    final result = await widget.client.request(
      'POST',
      '/${c['id']}/email-link',
      body: {'confirmed': true, 'agentId': id},
    );
    _notify(result['message']);
    if (!mounted) return;
    final agentClient = KorlixLiveConvoAgentClient(
      backendBaseUrl: widget.client.backendBaseUrl,
      headersBuilder: widget.client.headersBuilder,
    );
    try {
      final catalog = await agentClient.loadCatalog();
      final agent = catalog.agentById(id);
      if (agent != null && mounted) {
        await showKorlixLiveConvoAgentEmailSheet(
          context: _dialogContext,
          client: agentClient,
          agent: agent,
        );
      }
    } finally {
      agentClient.close();
    }
  });
  Future<void> _call(Map<String, dynamic> c) => _action(() async {
    final result = await widget.client.request('GET', '/${c['id']}/call-brief');
    if (!mounted) return;
    final brief = '${result['name']}\n${result['phone']}\n${result['brief']}';
    await showDialog<void>(
      context: _dialogContext,
      builder: (_) => AlertDialog(
        title: const Text('Nova call brief'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(brief),
            const SizedBox(height: 16),
            Text(result['message']),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: brief));
              _notify('Call brief copied');
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy brief'),
          ),
        ],
      ),
    );
  });
  Future<void> _archive(Map<String, dynamic> c) => _action(() async {
    if (!await _confirm(
      'Archive ${c['name']}?',
      'The contact is removed from your active list and linked Nova Email activity is suppressed.',
    )) {
      return;
    }
    await widget.client.request(
      'DELETE',
      '/${c['id']}',
      body: {'version': c['version'], 'confirmed': true},
    );
    if (mounted) {
      _offset = 0;
      await _load();
      _notify('Contact archived');
    }
  });
  void _reset() {
    _debounce?.cancel();
    _search.clear();
    _filter(() {
      _category = '';
      _source = '';
      _segment = '';
      _sort = 'name';
    });
  }

  Future<void> _favorite(Map<String, dynamic> c) => _action(() async {
    await widget.client.request(
      'PUT',
      '/${c['id']}',
      body: {...c, 'favorite': c['favorite'] != true},
    );
    await _load();
  });
  Future<void> _bulkStatus(String category) => _action(() async {
    final rows = _contacts
        .where((c) => _selected.contains(c['id'].toString()))
        .toList();
    int saved = 0;
    final failures = <String>[];
    for (var start = 0; start < rows.length; start += 4) {
      await Future.wait(
        rows.skip(start).take(4).map((c) async {
          try {
            await widget.client.request(
              'PUT',
              '/${c['id']}',
              body: {...c, 'category': category},
            );
            saved++;
          } catch (e) {
            failures.add('${c['name']}: $e');
          }
        }),
      );
      if (_locked) break;
    }
    if (!mounted) return;
    _selected.clear();
    await _load();
    _notify(
      failures.isEmpty
          ? '$saved contacts moved to ${contactLabel(category)}.'
          : '$saved contacts updated. ${failures.length} could not be updated. ${failures.first}',
    );
  });
  void _copy(String value) {
    unawaited(Clipboard.setData(ClipboardData(text: value)));
    _notify('Copied to clipboard');
  }

  Widget _profile(Map<String, dynamic> c, {bool sheet = false}) =>
      ContactProfile(
        key: ValueKey('profile-${c['id']}'),
        contact: c,
        busy: _operation,
        onEdit: (section) {
          if (sheet) Navigator.pop(_dialogContext);
          unawaited(_edit(c, section));
        },
        onEmail: () {
          if (sheet) Navigator.pop(_dialogContext);
          unawaited(_email(c));
        },
        onCall: () {
          if (sheet) Navigator.pop(_dialogContext);
          unawaited(_call(c));
        },
        onCopy: _copy,
        onFavorite: () {
          if (sheet) Navigator.pop(_dialogContext);
          unawaited(_favorite(c));
        },
        onArchive: () {
          if (sheet) Navigator.pop(_dialogContext);
          unawaited(_archive(c));
        },
        onClose: sheet ? () => Navigator.pop(_dialogContext) : null,
      );
  void _selectContact(Map<String, dynamic> c) {
    setState(() => _focusedId = c['id'].toString());
    if (MediaQuery.sizeOf(context).width < 1380) {
      showModalBottomSheet<void>(
        context: _dialogContext,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => Padding(
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .88,
            child: _profile(c, sheet: true),
          ),
        ),
      );
    }
  }

  Map<String, dynamic>? get _focusedContact {
    for (final c in _contacts) {
      if (c['id'].toString() == _focusedId) return c;
    }
    return null;
  }

  Widget _navItem(
    String label,
    IconData icon,
    String segment, {
    String? count,
  }) {
    final selected = _segment == segment && _category.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected
            ? CrmStyle.cyan.withValues(alpha: .09)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            _filter(() {
              _segment = segment;
              _category = '';
            });
            _scaffold.currentState?.closeDrawer();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? CrmStyle.cyan.withValues(alpha: .16)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? CrmStyle.cyan : CrmStyle.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? CrmStyle.cyan : CrmStyle.muted,
                    ),
                  ),
                ),
                if (count != null)
                  Text(
                    count,
                    style: TextStyle(
                      fontSize: 10,
                      color: selected ? CrmStyle.cyan : CrmStyle.muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _brandMark(double size) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .22),
    child: Image.asset(
      'assets/meeting_copilot/korlix_logo.jpeg',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'KORLIX logo',
    ),
  );

  Widget _sidebar() => Container(
    width: 210,
    decoration: const BoxDecoration(
      color: CrmStyle.sidebar,
      border: Border(right: BorderSide(color: CrmStyle.line)),
    ),
    child: Material(
      color: CrmStyle.sidebar,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 28),
              child: Row(
                children: [
                  _brandMark(38),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'KORLIX',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                      Text(
                        'CONTACTS',
                        style: TextStyle(
                          fontSize: 8,
                          color: CrmStyle.muted,
                          letterSpacing: 3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 0, 12),
                    child: CrmSectionLabel('Workspace'),
                  ),
                  _navItem(
                    'All contacts',
                    Icons.people_outline_rounded,
                    '',
                    count: '$_total',
                  ),
                  _navItem(
                    'Favorites',
                    Icons.star_outline_rounded,
                    'favorites',
                  ),
                  _navItem(
                    'Follow-ups',
                    Icons.event_available_outlined,
                    'follow_up',
                  ),
                  _navItem(
                    'Email ready',
                    Icons.mark_email_read_outlined,
                    'email_ready',
                  ),
                  _navItem(
                    'Call ready',
                    Icons.phone_forwarded_outlined,
                    'call_ready',
                  ),
                  _navItem(
                    'Missing details',
                    Icons.contact_page_outlined,
                    'missing_details',
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 27, 0, 12),
                    child: CrmSectionLabel('Relationships'),
                  ),
                  for (final category in contactCategories)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Material(
                        color: _category == category
                            ? CrmStyle.category(category).withValues(alpha: .07)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(9),
                          onTap: () {
                            _filter(() {
                              _category = category;
                              _segment = '';
                            });
                            _scaffold.currentState?.closeDrawer();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: CrmStyle.category(category),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    contactLabel(category),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _category == category
                                          ? CrmStyle.text
                                          : CrmStyle.muted,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${_categoryCounts[category] ?? 0}',
                                  style: const TextStyle(
                                    color: CrmStyle.muted,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 24, 0, 12),
                    child: CrmSectionLabel('Bring your people'),
                  ),
                  for (final e in const {
                    'phone': 'Phone contacts',
                    'email': 'Email contacts',
                    'facebook': 'Facebook export',
                    'spreadsheet': 'Spreadsheet',
                  }.entries)
                    ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      leading: Icon(
                        switch (e.key) {
                          'phone' => Icons.smartphone_rounded,
                          'email' => Icons.alternate_email_rounded,
                          'facebook' => Icons.facebook_outlined,
                          _ => Icons.table_chart_outlined,
                        },
                        color: CrmStyle.muted,
                        size: 16,
                      ),
                      title: Text(
                        e.value,
                        style: const TextStyle(
                          fontSize: 11,
                          color: CrmStyle.muted,
                        ),
                      ),
                      minLeadingWidth: 15,
                      onTap: () {
                        _scaffold.currentState?.closeDrawer();
                        unawaited(_import(e.key));
                      },
                    ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.all(18),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                border: Border.all(color: CrmStyle.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 17,
                    color: CrmStyle.violet,
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Enterprise workspace',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Your contacts stay private',
                          style: TextStyle(fontSize: 9, color: CrmStyle.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _topbar(bool desktop) => Container(
    height: 72,
    padding: EdgeInsets.symmetric(horizontal: desktop ? 28 : 14),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: CrmStyle.line)),
    ),
    child: Row(
      children: [
        if (!desktop)
          IconButton(
            tooltip: 'Open workspace navigation',
            onPressed: () => _scaffold.currentState?.openDrawer(),
            icon: const Icon(Icons.menu_rounded, size: 21),
          ),
        if (Navigator.of(context).canPop())
          IconButton(
            tooltip: 'Back to Korlix',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
          ),
        Expanded(
          child: desktop
              ? const Row(
                  children: [
                    Text(
                      'Workspace',
                      style: TextStyle(color: CrmStyle.muted, fontSize: 12),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: CrmStyle.muted,
                      ),
                    ),
                    Text(
                      'Contacts',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    _brandMark(28),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'KORLIX',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        const CrmBadge('ENTERPRISE', color: CrmStyle.violet),
        const SizedBox(width: 10),
        IconButton(
          tooltip: 'Refresh contacts',
          onPressed: _loading ? null : _load,
          icon: const Icon(
            Icons.refresh_rounded,
            size: 19,
            color: CrmStyle.muted,
          ),
        ),
      ],
    ),
  );
  Widget _metric(
    String title,
    int count,
    String subtitle,
    IconData icon,
    Color color, {
    bool mobile = false,
  }) => Container(
    padding: EdgeInsets.all(mobile ? 13 : 18),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color.withValues(alpha: .075), CrmStyle.surface],
      ),
      border: Border.all(color: CrmStyle.line),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: CrmStyle.muted,
                  fontSize: mobile ? 10 : 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (!mobile) Icon(icon, size: 17, color: color),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '$count',
          style: TextStyle(
            fontSize: mobile ? 25 : 29,
            fontWeight: FontWeight.w700,
            letterSpacing: -.6,
            height: 1,
          ),
        ),
        if (!mobile) ...[
          const SizedBox(height: 9),
          Text(
            subtitle,
            style: const TextStyle(color: CrmStyle.muted, fontSize: 10),
          ),
        ],
      ],
    ),
  );
  Widget _summary(bool mobile) => Row(
    children: [
      Expanded(
        child: _metric(
          'Total contacts',
          _total,
          'One connected workspace',
          Icons.people_outline_rounded,
          CrmStyle.cyan,
          mobile: mobile,
        ),
      ),
      SizedBox(width: mobile ? 8 : 12),
      Expanded(
        child: _metric(
          'Customers',
          _categoryCounts['customer'] ?? 0,
          'Relationships that matter',
          Icons.work_outline_rounded,
          CrmStyle.violet,
          mobile: mobile,
        ),
      ),
      SizedBox(width: mobile ? 8 : 12),
      Expanded(
        child: _metric(
          mobile ? 'Personal' : 'Friends & family',
          (_categoryCounts['friend'] ?? 0) + (_categoryCounts['family'] ?? 0),
          'Your inner circle',
          Icons.favorite_outline_rounded,
          CrmStyle.pink,
          mobile: mobile,
        ),
      ),
      if (!mobile) ...[
        const SizedBox(width: 12),
        Expanded(
          child: _metric(
            'Leads',
            _categoryCounts['lead'] ?? 0,
            'Your next conversations',
            Icons.near_me_outlined,
            CrmStyle.gold,
          ),
        ),
      ],
    ],
  );
  Widget _choice(
    String label,
    String value,
    Map<String, String> items,
    void Function(String) update,
  ) => SizedBox(
    width: 185,
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: items.entries
          .map(
            (e) => DropdownMenuItem(
              value: e.key,
              child: Text(
                e.value,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (v) => _filter(() => update(v!)),
    ),
  );
  Widget _filters(bool mobile) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('contact-search'),
              controller: _search,
              focusNode: _searchFocus,
              decoration: InputDecoration(
                hintText: mobile
                    ? 'Find a contact…'
                    : 'Search people, companies, phone or email',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: CrmStyle.muted,
                  size: 20,
                ),
                suffixIcon: _search.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _debounce?.cancel();
                          _search.clear();
                          _filter(() {});
                        },
                        icon: const Icon(Icons.close_rounded, size: 16),
                      )
                    : mobile
                    ? null
                    : const Padding(
                        padding: EdgeInsets.all(12),
                        child: CrmBadge('Ctrl / Cmd K', color: CrmStyle.muted),
                      ),
              ),
              onChanged: (_) {
                setState(() {});
                _debounce?.cancel();
                _debounce = Timer(
                  const Duration(milliseconds: 300),
                  () => _filter(() {}),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
            icon: Icon(
              _filtersOpen ? Icons.close_rounded : Icons.tune_rounded,
              size: 16,
            ),
            label: Text(mobile ? 'Filter' : 'Filters'),
          ),
        ],
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: _filtersOpen
            ? Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _choice('Smart view', _segment, const {
                      '': 'All contacts',
                      'favorites': 'Favorites',
                      'follow_up': 'Follow-up due',
                      'missing_details': 'Missing details',
                      'email_ready': 'Email ready',
                      'call_ready': 'Call ready',
                    }, (v) => _segment = v),
                    _choice('Source', _source, const {
                      '': 'All sources',
                      'manual': 'Manual',
                      'phone': 'Phone',
                      'email': 'Email',
                      'facebook': 'Facebook',
                      'spreadsheet': 'Spreadsheet',
                    }, (v) => _source = v),
                    _choice('Sort', _sort, const {
                      'name': 'Name A–Z',
                      'updated_at': 'Recently updated',
                      'follow_up_on': 'Next follow-up',
                    }, (v) => _sort = v),
                    TextButton(
                      onPressed: _reset,
                      child: const Text('Reset filters'),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink(),
      ),
      if (mobile) ...[
        const SizedBox(height: 13),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: ChoiceChip(
                  label: Text('All $_total'),
                  selected: _category.isEmpty,
                  onSelected: (_) => _filter(() => _category = ''),
                ),
              ),
              for (final c in contactCategories)
                Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: ChoiceChip(
                    label: Text(
                      '${contactLabel(c)} ${_categoryCounts[c] ?? 0}',
                    ),
                    selected: _category == c,
                    onSelected: (_) => _filter(() => _category = c),
                  ),
                ),
            ],
          ),
        ),
      ],
      if (_segment.isNotEmpty ||
          _source.isNotEmpty ||
          (_category.isNotEmpty && !mobile))
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (_category.isNotEmpty) RelationshipBadge(_category),
              if (_segment.isNotEmpty)
                CrmBadge(contactLabel(_segment), color: CrmStyle.violet),
              if (_source.isNotEmpty)
                CrmBadge(
                  'From ${contactLabel(_source)}',
                  color: CrmStyle.muted,
                ),
              InkWell(
                onTap: _reset,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Text(
                    'Clear all',
                    style: TextStyle(fontSize: 11, color: CrmStyle.muted),
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
  Widget _tableHeader(bool wide) {
    final all = _contacts.isNotEmpty && _selected.length == _contacts.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: CrmStyle.surface,
        border: Border(bottom: BorderSide(color: CrmStyle.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Checkbox(
              tristate: true,
              value: all
                  ? true
                  : _selected.isEmpty
                  ? false
                  : null,
              onChanged: _operation
                  ? null
                  : (v) => setState(() {
                      if (all) {
                        _selected.clear();
                      } else {
                        _selected.addAll(
                          _contacts.map((c) => c['id'].toString()),
                        );
                      }
                    }),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(flex: 3, child: CrmSectionLabel('Contact')),
          if (wide) ...[
            const Expanded(flex: 3, child: CrmSectionLabel('Reach out')),
            const Expanded(flex: 2, child: CrmSectionLabel('Status')),
            const Expanded(flex: 2, child: CrmSectionLabel('Follow-up')),
          ],
          const SizedBox(width: 38),
        ],
      ),
    );
  }

  Widget _contactRow(Map<String, dynamic> c, bool wide) {
    final active = _focusedId == c['id'].toString(),
        selected = _selected.contains(c['id'].toString()),
        blocked = c['do_not_contact'] == true;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          c['name'],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 5),
        Text(
          (c['company'] ?? '').isNotEmpty
              ? c['company']
              : contactLabel(c['source'] ?? 'manual'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, color: CrmStyle.muted),
        ),
      ],
    );
    return Material(
      color: active ? CrmStyle.cyan.withValues(alpha: .04) : Colors.transparent,
      child: InkWell(
        onTap: () => _selectContact(c),
        hoverColor: CrmStyle.raised.withValues(alpha: .7),
        child: Container(
          key: ValueKey('contact-row-${c['id']}'),
          padding: EdgeInsets.fromLTRB(
            8,
            _compact ? 10 : 17,
            8,
            _compact ? 10 : 17,
          ),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: active ? CrmStyle.cyan : Colors.transparent,
                width: 2,
              ),
              bottom: const BorderSide(color: CrmStyle.line, width: .6),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Checkbox(
                      value: selected,
                      onChanged: _operation
                          ? null
                          : (v) => setState(() {
                              if (v == true) {
                                _selected.add(c['id'].toString());
                              } else {
                                _selected.remove(c['id'].toString());
                              }
                            }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        ContactAvatar(contact: c, size: wide ? 34 : 40),
                        const SizedBox(width: 10),
                        Expanded(child: text),
                        if (c['favorite'] == true)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              Icons.star_rounded,
                              color: CrmStyle.gold,
                              size: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (wide) ...[
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c['email'] ?? 'Add an email',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            c['phone'] ?? 'Add a phone number',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: CrmStyle.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: blocked
                            ? const CrmBadge('Blocked', color: CrmStyle.danger)
                            : RelationshipBadge(c['category']),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        c['follow_up_on'] == null
                            ? '—'
                            : contactDate(c['follow_up_on']),
                        style: TextStyle(
                          fontSize: 10,
                          color: contactDue(c) ? CrmStyle.gold : CrmStyle.muted,
                        ),
                      ),
                    ),
                  ],
                  SizedBox(
                    width: 36,
                    child: PopupMenuButton<String>(
                      tooltip: 'Options for ${c['name']}',
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: CrmStyle.muted,
                        size: 18,
                      ),
                      onSelected: (v) {
                        if (v == 'edit') _edit(c);
                        if (v == 'favorite') _favorite(c);
                        if (v == 'archive') _archive(c);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit contact'),
                        ),
                        PopupMenuItem(
                          value: 'favorite',
                          child: Text(
                            c['favorite'] == true
                                ? 'Remove favorite'
                                : 'Add favorite',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'archive',
                          child: Text('Archive'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!wide)
                Padding(
                  padding: const EdgeInsets.only(left: 56, top: 12, right: 8),
                  child: Row(
                    children: [
                      RelationshipBadge(c['category']),
                      const SizedBox(width: 8),
                      if (blocked)
                        const Icon(
                          Icons.block_rounded,
                          color: CrmStyle.danger,
                          size: 14,
                        ),
                      Expanded(
                        child: Text(
                          c['email'] ?? c['phone'] ?? 'Add contact details',
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: CrmStyle.muted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: CrmStyle.muted,
                        size: 15,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactsList() => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 680;
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: CrmStyle.surface.withValues(alpha: .55),
          border: Border.all(color: CrmStyle.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: _selected.isEmpty
                        ? Row(
                            children: [
                              const Text(
                                'Your contacts',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              CrmBadge('$_count', color: CrmStyle.muted),
                            ],
                          )
                        : Text(
                            '${_selected.length} selected',
                            style: const TextStyle(
                              color: CrmStyle.cyan,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  if (_selected.isNotEmpty)
                    PopupMenuButton<String>(
                      tooltip: 'Assign relationship status',
                      enabled: !_operation,
                      onSelected: _bulkStatus,
                      itemBuilder: (_) => [
                        for (final c in contactCategories)
                          PopupMenuItem(value: c, child: Text(contactLabel(c))),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Text(
                              'Set status',
                              style: TextStyle(
                                fontSize: 11,
                                color: CrmStyle.cyan,
                              ),
                            ),
                            SizedBox(width: 5),
                            Icon(
                              Icons.expand_more_rounded,
                              size: 16,
                              color: CrmStyle.cyan,
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_selected.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear selection',
                      onPressed: () => setState(() => _selected.clear()),
                      icon: const Icon(Icons.close_rounded, size: 16),
                    )
                  else
                    IconButton(
                      tooltip: _compact
                          ? 'Comfortable spacing'
                          : 'Compact spacing',
                      onPressed: () => setState(() => _compact = !_compact),
                      icon: Icon(
                        _compact
                            ? Icons.view_agenda_outlined
                            : Icons.density_small_rounded,
                        size: 17,
                        color: CrmStyle.muted,
                      ),
                    ),
                ],
              ),
            ),
            if (_loading || _operation)
              const LinearProgressIndicator(
                minHeight: 2,
                color: CrmStyle.cyan,
                backgroundColor: CrmStyle.line,
              ),
            _tableHeader(wide),
            Expanded(
              child: _contacts.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: CrmStyle.cyan.withValues(alpha: .06),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.people_outline_rounded,
                                  size: 36,
                                  color: CrmStyle.cyan,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                _loading
                                    ? 'Opening your workspace…'
                                    : _total == 0
                                    ? 'Your network starts here.'
                                    : 'No matching contacts.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 9),
                              Text(
                                _total == 0
                                    ? 'Add someone new or bring your contacts together.'
                                    : 'Try another search or clear your filters.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: CrmStyle.muted,
                                  fontSize: 12,
                                  height: 1.6,
                                ),
                              ),
                              if (!_loading)
                                TextButton(
                                  onPressed: _total == 0
                                      ? () => _edit()
                                      : _reset,
                                  child: Text(
                                    _total == 0
                                        ? 'Add your first contact'
                                        : 'Clear filters',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      key: const PageStorageKey('crm-list'),
                      itemCount: _contacts.length,
                      itemBuilder: (_, i) => _contactRow(_contacts[i], wide),
                    ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: CrmStyle.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _count == 0
                          ? 'No contacts to display'
                          : '${_offset + 1}–${_offset + _contacts.length} of $_count contacts',
                      style: const TextStyle(
                        fontSize: 10,
                        color: CrmStyle.muted,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: _offset == 0 || _loading
                        ? null
                        : () {
                            _selected.clear();
                            _offset = (_offset - 50).clamp(0, 100000);
                            unawaited(_load());
                          },
                    icon: const Icon(Icons.chevron_left_rounded, size: 19),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: _offset + 50 >= _count || _loading
                        ? null
                        : () {
                            _selected.clear();
                            _offset += 50;
                            unawaited(_load());
                          },
                    icon: const Icon(Icons.chevron_right_rounded, size: 19),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
  Widget _workspace(bool mobile, bool studio) => Padding(
    padding: EdgeInsets.fromLTRB(
      mobile ? 16 : 26,
      mobile ? 19 : 26,
      mobile ? 16 : 26,
      mobile ? 12 : 22,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mobile)
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Contacts',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                ),
              ),
              Tooltip(
                message: 'Import contacts',
                child: OutlinedButton(
                  key: const Key('import-contacts'),
                  onPressed: _import,
                  child: const Icon(Icons.file_upload_outlined, size: 19),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'New contact',
                child: FilledButton(
                  key: const Key('new-contact'),
                  onPressed: () => _edit(),
                  child: const Icon(Icons.add_rounded, size: 20),
                ),
              ),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contacts',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.2,
                      ),
                    ),
                    SizedBox(height: 7),
                    Text(
                      'The people behind your next opportunity.',
                      style: TextStyle(color: CrmStyle.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                key: const Key('import-contacts'),
                onPressed: _import,
                icon: const Icon(Icons.file_upload_outlined, size: 16),
                label: const Text('Import contacts'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                key: const Key('new-contact'),
                onPressed: () => _edit(),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('New contact'),
              ),
            ],
          ),
        const SizedBox(height: 22),
        _summary(mobile),
        const SizedBox(height: 22),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _filters(mobile),
                    const SizedBox(height: 17),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: CrmStyle.danger,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: CrmStyle.danger,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _load,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    Expanded(child: _contactsList()),
                  ],
                ),
              ),
              if (studio) ...[
                const SizedBox(width: 20),
                SizedBox(
                  width: 300,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _focusedContact == null
                        ? Container(
                            width: 300,
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: CrmStyle.surface,
                              border: Border.all(color: CrmStyle.line),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.auto_awesome_outlined,
                                  color: CrmStyle.violet,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Your Contact Studio',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                  ),
                                ),
                                SizedBox(height: 9),
                                Text(
                                  'Select a person to see their details and prepare your next move with Nova.',
                                  style: TextStyle(
                                    color: CrmStyle.muted,
                                    fontSize: 12,
                                    height: 1.7,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _profile(_focusedContact!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Theme(
    data: CrmStyle.theme,
    child: Builder(
      builder: (surface) {
        _surfaceContext = surface;
        final desktop = MediaQuery.sizeOf(context).width >= 1100;
        final mobile = MediaQuery.sizeOf(context).width < 700;
        final studio = MediaQuery.sizeOf(context).width >= 1380;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
                _searchFocus.requestFocus(),
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
                _searchFocus.requestFocus(),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              key: _scaffold,
              drawer: _locked ? null : Drawer(width: 240, child: _sidebar()),
              body: SafeArea(
                child: _locked
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CrmBadge(
                                'ENTERPRISE',
                                color: CrmStyle.violet,
                              ),
                              const SizedBox(height: 22),
                              const Icon(
                                Icons.lock_outline_rounded,
                                size: 42,
                                color: CrmStyle.violet,
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'Contacts CRM requires Enterprise.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Sign in with your Enterprise account to open this workspace.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: CrmStyle.muted,
                                  height: 1.6,
                                ),
                              ),
                              const SizedBox(height: 20),
                              OutlinedButton(
                                onPressed: _load,
                                child: const Text('Check access again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          if (desktop) _sidebar(),
                          Expanded(
                            child: Column(
                              children: [
                                _topbar(desktop),
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, box) {
                                      final minimum = mobile ? 660.0 : 740.0;
                                      final extra = _filtersOpen ? 150.0 : 0.0;
                                      final height =
                                          box.maxHeight < minimum + extra
                                          ? minimum + extra
                                          : box.maxHeight;
                                      return SingleChildScrollView(
                                        child: SizedBox(
                                          height: height,
                                          child: _workspace(mobile, studio),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
