import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'seo_client.dart';

const _navy = Color(0xFF102A43),
    _cyan = Color(0xFF007D99),
    _muted = Color(0xFF536B7A),
    _line = Color(0xFFDCE6ED);
const _labels = {
  'businessName': 'Business name',
  'website': 'Website',
  'services': 'Products or services',
  'market': 'Target market or service area',
  'facts': 'Verified business facts (optional)',
};
const _limits = {
  'businessName': 120,
  'website': 2000,
  'services': 350,
  'market': 160,
  'facts': 3000,
};
Map<String, dynamic> _map(dynamic x) =>
    x is Map ? Map<String, dynamic>.from(x) : {};
List<Map<String, dynamic>> _rows(dynamic x) =>
    x is List ? x.whereType<Map>().map(_map).toList() : [];
String _s(dynamic x) => x?.toString() ?? '';
bool _running(Map<String, dynamic>? run) =>
    ['queued', 'running'].contains(run?['state']);
String _date(dynamic value) {
  final d = DateTime.tryParse(_s(value))?.toLocal();
  if (d == null) return 'Not scheduled';
  return '${d.month}/${d.day}/${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String seoReportText(Map<String, dynamic> run) {
  final r = _map(run['result']),
      ai = _map(r['ai']),
      coverage = _map(r['coverage']);
  final lines = <String>[
    'KORLIX AI SEO AGENT',
    _s(r['siteUrl']),
    'Scanned: ${r['scannedAt']}',
    'Sample: ${coverage['pagesScanned'] ?? 0} public pages. Health score: ${r['score'] ?? 'Unavailable'}.',
    'The health score is a heuristic, not a search ranking. Google rankings, traffic and indexing status are not measured.',
    _s(ai['summary']),
    ...((r['limitations'] as List?) ?? []).map(_s),
  ];
  for (final f in _rows(r['findings'])) {
    lines.addAll([
      '\n${f['priority']}: ${f['title']}',
      _s(f['detail']),
      _s(f['evidence']),
      _s(f['url']),
    ]);
  }
  for (final a in _rows(ai['actions'])) {
    lines.addAll([
      '\nACTION: ${a['title']}',
      _s(a['why']),
      _s(a['how']),
      _s(a['url']),
    ]);
  }
  for (final d in _rows(ai['drafts'])) {
    lines.addAll([
      '\nDRAFT FOR REVIEW: ${d['title']}',
      _s(d['body']),
      _s(d['url']),
    ]);
  }
  lines.addAll(['\nYOUR NOTES', _s(_map(run['progress'])['notes'])]);
  return lines.join('\n');
}

class SeoAgentScreen extends StatefulWidget {
  const SeoAgentScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    this.disposeClient = true,
    this.openVisibility,
    this.copyText,
    this.openLink,
  });
  final SeoClient client;
  final Future<bool> Function() ensureConsent;
  final bool disposeClient;
  final VoidCallback? openVisibility;
  final Future<void> Function(String)? copyText;
  final Future<bool> Function(Uri)? openLink;
  @override
  State<SeoAgentScreen> createState() => _SeoAgentScreenState();
}

class _SeoAgentScreenState extends State<SeoAgentScreen> {
  final _fields = {for (final k in _labels.keys) k: TextEditingController()};
  final _form = GlobalKey<FormState>();
  final _notes = TextEditingController(), _scroll = ScrollController();
  final _setupFeedback = GlobalKey();
  Map<String, dynamic>? _profile, _active, _selected;
  List<Map<String, dynamic>> _runs = [];
  Set<String> _completed = {};
  bool _loading = true,
      _refreshing = false,
      _busy = false,
      _locked = false,
      _populated = false,
      _dirty = false,
      _polling = false;
  int _tab = 0, _credits = 3;
  String? _error, _notice, _setupError, _requestKey;
  Timer? _timer;
  bool get _working => _busy || _refreshing || _active != null;
  bool get _enabled => _profile?['monitoringEnabled'] == true;

  @override
  void initState() {
    super.initState();
    widget.client.onAccessDenied = _lock;
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _fields.values) {
      c.dispose();
    }
    _notes.dispose();
    _scroll.dispose();
    widget.client.onAccessDenied = null;
    if (widget.disposeClient) widget.client.dispose();
    super.dispose();
  }

  bool _alive() {
    if (!mounted || _locked) return false;
    try {
      widget.client.checkAccess();
    } catch (_) {
      _lock();
      return false;
    }
    return mounted && !_locked;
  }

  void _lock() {
    if (!mounted || _locked) return;
    _timer?.cancel();
    setState(() {
      _locked = true;
      _profile = _active = _selected = null;
      _runs = [];
      _completed = {};
      _error = _notice = _setupError = _requestKey = null;
      for (final c in _fields.values) {
        c.clear();
      }
      _notes.clear();
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _feedback(String message) {
    if (!_alive()) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _go(int tab) {
    if (!_alive()) return;
    FocusScope.of(context).unfocus();
    setState(() => _tab = tab);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _populate(Map<String, dynamic> data) {
    for (final entry in _fields.entries) {
      entry.value.text = _s(data[entry.key]);
    }
  }

  void _select(Map<String, dynamic> run) {
    _selected = run;
    final p = _map(run['progress']);
    _completed = ((p['completedActions'] as List?) ?? []).map(_s).toSet();
    _notes.text = _s(p['notes']);
  }

  void _merge(Map<String, dynamic> run) {
    _runs = [run, ..._runs.where((r) => r['id'] != run['id'])]
      ..sort((a, b) => _s(b['createdAt']).compareTo(_s(a['createdAt'])));
  }

  Future<void> _load() async {
    if (!_alive() || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      final data = await widget.client.load();
      if (!_alive()) return;
      setState(() {
        _profile = data['profile'] is Map ? _map(data['profile']) : null;
        _runs = _rows(data['runs']);
        _active = _runs.where(_running).firstOrNull;
        _credits = (data['creditCost'] is num
            ? (data['creditCost'] as num).toInt()
            : 3);
        if (!_populated) {
          _populate(_map(_profile?['data']));
          _populated = true;
          if (_profile == null) _tab = 2;
        }
        _loading = false;
        _error = null;
      });
      _schedule();
    } catch (e) {
      if (_alive()) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (mounted && !_locked && _active != null) {
      _timer = Timer(const Duration(seconds: 3), () => unawaited(_poll()));
    }
  }

  Future<void> _poll() async {
    if (!_alive() || _polling || _active == null) return;
    final id = _s(_active?['id']);
    _polling = true;
    try {
      final run = await widget.client.run(id);
      if (!_alive()) return;
      setState(() {
        _merge(run);
        _active = _running(run) ? run : null;
        if (_selected?['id'] == id) _select(run);
        if (!_running(run)) {
          _requestKey = null;
          _notice = run['state'] == 'completed'
              ? 'Your SEO audit is ready. Open the report to review your next steps.'
              : _s(run['error']);
        }
      });
      if (!_running(run)) await _load();
    } catch (e) {
      if (_alive()) {
        setState(
          () => _error =
              '$e Your audit remains saved. Refresh to check its progress.',
        );
      }
    } finally {
      _polling = false;
      _schedule();
    }
  }

  Future<void> _saveProfile() async {
    if (!_alive() || _working) return;
    if (!(_form.currentState?.validate() ?? false)) {
      _feedback('Complete the required business details.');
      return;
    }
    final values = {
      for (final e in _fields.entries) e.key: e.value.text.trim(),
    };
    final oldSite = _s(_map(_profile?['data'])['website']);
    final wasEnabled = _enabled;
    setState(() {
      _busy = true;
      _setupError = _error = null;
    });
    try {
      final p = await widget.client.saveProfile(values);
      if (!_alive()) return;
      setState(() {
        _profile = p;
        _populated = true;
        _dirty = false;
        _requestKey = null;
        _populate(_map(p['data']));
        _notice = wasEnabled && oldSite != _s(_map(p['data'])['website'])
            ? 'Business saved. The website changed; review and enable weekly monitoring again.'
            : 'Business saved. You are ready to run an SEO audit.';
      });
      _go(0);
    } catch (e) {
      if (_alive()) {
        setState(() => _setupError = e.toString());
        _feedback(e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!_alive() || _setupError == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!_alive()) return;
    final target = _setupFeedback.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(target, alignment: 0.2);
    }
  }

  bool _ready() {
    if (_profile != null && !_dirty) return true;
    _go(2);
    _feedback(
      'Save your business setup before running an audit or enabling monitoring.',
    );
    return false;
  }

  Future<void> _start() async {
    if (!_alive() || _working || !_ready()) return;
    setState(() {
      _busy = true;
      _error = _notice = null;
    });
    try {
      if (!await widget.ensureConsent() || !_alive()) return;
      _requestKey ??= seoRequestKey();
      final run = await widget.client.start(_requestKey!);
      if (!_alive()) return;
      setState(() {
        _merge(run);
        _select(run);
        _active = _running(run) ? run : null;
      });
      _go(1);
      _schedule();
      if (!_running(run)) {
        _requestKey = null;
        await _load();
      }
    } catch (e) {
      if (_alive()) {
        setState(() => _error = e.toString());
        _feedback(e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return _alive() && accepted == true;
  }

  Future<void> _monitor(bool enabled) async {
    if (!_alive() ||
        _busy ||
        _refreshing ||
        (enabled && (_active != null || !_ready()))) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (enabled) {
        if (!await _confirm(
              'Enable weekly monitoring?',
              'KORLIX will automatically audit up to 5 public website pages each week and prepare findings and drafts. Your business details and sampled public page text are sent to OpenAI to prepare the report. Each audit uses $_credits credits and 1 generation while monitoring is enabled. You can pause it here. Drafts are never published automatically.',
              'Enable weekly',
            ) ||
            !_alive()) {
          return;
        }
        if (!await widget.ensureConsent() || !_alive()) return;
      }
      final p = await widget.client.setMonitoring(enabled);
      if (!_alive()) return;
      setState(() {
        _profile = p;
        _error = null;
        _notice = enabled
            ? 'Weekly monitoring enabled. Your next audit is shown below.'
            : 'Weekly monitoring paused. Any audit already started may finish.';
      });
    } catch (e) {
      if (_alive()) {
        setState(() => _error = e.toString());
        _feedback(e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openReport(String id) async {
    if (!_alive() || _busy) return;
    setState(() => _busy = true);
    try {
      final run = await widget.client.run(id);
      if (!_alive()) return;
      setState(() => _select(run));
      _go(1);
    } catch (e) {
      _feedback(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveProgress() async {
    if (!_alive() || _busy || _selected == null) return;
    final id = _s(_selected?['id']);
    setState(() => _busy = true);
    try {
      final run = await widget.client.progress(id, {
        'completedActions': _completed.toList(),
        'notes': _notes.text.trim(),
      });
      if (!_alive()) return;
      setState(() {
        _merge(run);
        if (_selected?['id'] == id) _select(run);
      });
      _feedback('Your review progress was saved.');
    } catch (e) {
      _feedback(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove({bool all = false}) async {
    if (!_alive() || _working || (!all && _selected == null)) return;
    final id = _s(_selected?['id']);
    setState(() => _busy = true);
    try {
      if (!await _confirm(
            all ? 'Clear SEO Agent data?' : 'Delete this report?',
            all
                ? 'This removes your business setup, reports and review notes, and stops weekly monitoring. Used credits are not refunded.'
                : 'This removes the saved report and its review notes. Used credits are not refunded.',
            'Delete',
          ) ||
          !_alive()) {
        return;
      }
      if (all) {
        await widget.client.clear();
      } else {
        await widget.client.remove(id);
      }
      if (!_alive()) return;
      setState(() {
        _selected = null;
        _completed = {};
        _notes.clear();
        if (all) {
          _populated = _dirty = false;
          _requestKey = _setupError = _notice = null;
          _profile = _active = null;
          _runs = [];
          for (final field in _fields.values) {
            field.clear();
          }
        } else {
          _runs = _runs.where((run) => run['id'] != id).toList();
        }
      });
      await _load();
    } catch (e) {
      _feedback(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String text) async {
    if (!_alive()) return;
    try {
      if (widget.copyText != null) {
        await widget.copyText!(text);
      } else {
        await Clipboard.setData(ClipboardData(text: text));
      }
      if (_alive()) {
        _feedback('Copied. Review facts and wording before publishing.');
      }
    } catch (_) {
      _feedback('Select the text to copy it manually.');
    }
  }

  Future<void> _open(String value) async {
    if (!_alive()) return;
    try {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          !['https', 'http'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const SeoException('This page link is unavailable.');
      }
      final ok = widget.openLink != null
          ? await widget.openLink!(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (_alive() && !ok) _feedback('This page could not be opened.');
    } catch (e) {
      _feedback(e.toString());
    }
  }

  Widget _panel(Widget child, {Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: _line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );
  Widget _heading(String title, [String? subtitle]) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            color: _navy,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: _muted, height: 1.5)),
        ],
      ],
    ),
  );
  Widget _pill(String text, {bool dark = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: dark ? const Color(0xFF21455D) : const Color(0xFFE9F5F8),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: dark ? const Color(0xFF9BE7F6) : _cyan,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
  Widget _link(String value) => value.isEmpty
      ? const SizedBox.shrink()
      : TextButton.icon(
          onPressed: () => _open(value),
          icon: const Icon(Icons.open_in_new, size: 15),
          label: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
        );
  Widget _hero() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(26),
    margin: const EdgeInsets.only(bottom: 20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: const LinearGradient(
        colors: [Color(0xFF0C2035), Color(0xFF153E55)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _pill('KORLIX AI SEO AGENT', dark: true),
            _pill('AUDIT · PLAN · IMPROVE', dark: true),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'A clearer path to\nbetter search visibility.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            height: 1.15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 13),
        const Text(
          'Turn your website into a practical action plan. KORLIX reviews public pages, explains the issues and drafts your next improvements.',
          style: TextStyle(color: Color(0xFFD0E3EB), fontSize: 16, height: 1.5),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              key: const Key('seo-audit'),
              onPressed: _working ? null : _start,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8CE5F5),
                foregroundColor: _navy,
                disabledBackgroundColor: const Color(0xFF466373),
                disabledForegroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
              ),
              icon: const Icon(Icons.travel_explore),
              label: Text(_active != null ? 'Audit in progress' : 'Audit now'),
            ),
            Text(
              '$_credits credits + 1 generation per audit\nUp to 5 public pages',
              style: const TextStyle(color: Color(0xFFB5D0DD), height: 1.5),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'Available with Ultra Premium & Enterprise. Audits share your business details and sampled public page text with OpenAI to prepare your report.',
          style: TextStyle(color: Color(0xFFB5D0DD), height: 1.5),
        ),
      ],
    ),
  );
  Widget _activity() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 19,
              height: 19,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                _active?['state'] == 'queued'
                    ? 'Your audit is queued'
                    : 'KORLIX is reviewing your website',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _navy,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _s(_active?['phase']).isEmpty
              ? 'Preparing the next step…'
              : _s(_active?['phase']),
        ),
        if ((_active?['charged'] as num? ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${_active!['charged']} credits + 1 generation reserved',
              style: const TextStyle(color: _muted),
            ),
          ),
        const SizedBox(height: 8),
        const Text(
          'You can leave this screen. Your report will be saved here.',
          style: TextStyle(color: _muted),
        ),
      ],
    ),
    color: const Color(0xFFF0F8FA),
  );
  Widget _overview() {
    final latest = _runs.where((r) => r['state'] == 'completed').firstOrNull;
    final result = _map(latest?['result']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(
                _s(_map(_profile?['data'])['businessName']).isEmpty
                    ? 'Your search workspace'
                    : _s(_map(_profile?['data'])['businessName']),
                _s(_map(_profile?['data'])['website']),
              ),
              Wrap(
                spacing: 32,
                runSpacing: 18,
                children: [
                  _stat(
                    'Latest health score',
                    result['score'] == null ? '—' : '${result['score']}/100',
                  ),
                  _stat('Saved audits', '${_runs.length}'),
                  _stat('Weekly monitoring', _enabled ? 'Enabled' : 'Paused'),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Health scores describe the sampled pages using a heuristic. They are not search rankings.',
                style: TextStyle(color: _muted),
              ),
              if (latest != null) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _openReport(_s(latest['id'])),
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('Open latest report'),
                ),
              ],
            ],
          ),
        ),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(
                'Your weekly SEO agent',
                'Keep a fresh view of your website without starting every audit yourself.',
              ),
              SwitchListTile.adaptive(
                key: const Key('seo-monitoring'),
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                onChanged:
                    _busy || _refreshing || (!_enabled && _active != null)
                    ? null
                    : _monitor,
                title: const Text(
                  'Weekly monitoring',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '$_credits credits + 1 generation per automatic audit while enabled. Pause anytime.',
                ),
              ),
              const Divider(height: 28),
              Text(
                _enabled
                    ? 'Next audit: ${_date(_profile?['nextRunAt'])}'
                    : 'Weekly audits are paused.',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _navy,
                ),
              ),
              if (_s(_profile?['pauseReason']).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Monitoring notice: ${_profile!['pauseReason']}',
                    style: const TextStyle(color: _muted),
                  ),
                ),
              const SizedBox(height: 10),
              const Text(
                'KORLIX produces findings and drafts for your review. It does not publish changes to your website.',
                style: TextStyle(color: _muted, height: 1.5),
              ),
            ],
          ),
        ),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading('From evidence to your next edit'),
              _step(
                Icons.fact_check_outlined,
                '01  Understand your website',
                'Review page checks, missing information and the evidence behind each finding.',
              ),
              _step(
                Icons.auto_awesome_outlined,
                '02  Plan the improvements',
                'Explore content opportunities and a prioritized action list tailored to your business.',
              ),
              _step(
                Icons.edit_note,
                '03  Make it yours',
                'Review suggested metadata, outlines and FAQs. Copy the drafts and track your progress.',
              ),
              const SizedBox(height: 10),
              const Text(
                'This audit does not measure Google rankings, traffic or indexing status, and cannot guarantee search placement.',
                style: TextStyle(color: _muted, height: 1.5),
              ),
              if (widget.openVisibility != null) ...[
                const Divider(height: 28),
                TextButton.icon(
                  onPressed: () {
                    if (_alive()) widget.openVisibility!();
                  },
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Explore AI Visibility'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w700,
          color: _navy,
        ),
      ),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: _muted)),
    ],
  );
  Widget _step(IconData icon, String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _cyan),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 5),
              Text(body, style: const TextStyle(color: _muted, height: 1.5)),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _setup() => _panel(
    Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(
            'Your business, in focus',
            'Tell KORLIX what you do and who you serve. Add only details you can verify. Audits and weekly monitoring are available with Ultra Premium & Enterprise.',
          ),
          for (final entry in _labels.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextFormField(
                key: Key('seo-${entry.key}'),
                controller: _fields[entry.key],
                enabled: !_working,
                minLines: entry.key == 'facts' ? 3 : 1,
                maxLines: entry.key == 'facts'
                    ? 6
                    : (entry.key == 'services' ? 3 : 1),
                maxLength: _limits[entry.key],
                keyboardType: entry.key == 'website'
                    ? TextInputType.url
                    : TextInputType.text,
                decoration: InputDecoration(
                  labelText: entry.value,
                  hintText: entry.key == 'website'
                      ? 'https://yourbusiness.com'
                      : null,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (entry.key != 'facts' && value.isEmpty) {
                    return 'Enter ${entry.value.toLowerCase()}.';
                  }
                  if (entry.key == 'website') {
                    final uri = Uri.tryParse(
                      value.contains('://') ? value : 'https://$value',
                    );
                    if (uri == null ||
                        uri.scheme != 'https' ||
                        !uri.host.contains('.') ||
                        uri.userInfo.isNotEmpty) {
                      return 'Enter a public HTTPS website address.';
                    }
                  }
                  return null;
                },
                onChanged: (_) => setState(() => _dirty = true),
              ),
            ),
          const Text(
            'Changing the website pauses weekly monitoring so you can review the new site before enabling it again.',
            style: TextStyle(color: _muted, height: 1.5),
          ),
          const SizedBox(height: 18),
          if (_setupError != null)
            Padding(
              key: _setupFeedback,
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                _setupError!,
                key: const Key('seo-setup-error'),
                style: const TextStyle(color: Color(0xFFAC2525)),
              ),
            ),
          FilledButton.icon(
            key: const Key('seo-save-profile'),
            onPressed: _working ? null : _saveProfile,
            icon: const Icon(Icons.check),
            label: Text(_busy ? 'Saving…' : 'Save business setup'),
          ),
          if (_dirty)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'You have unsaved changes.',
                style: TextStyle(color: _muted),
              ),
            ),
          if (_profile != null) ...[
            const Divider(height: 36),
            TextButton.icon(
              onPressed: _working ? null : () => _remove(all: true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Clear SEO Agent data'),
            ),
          ],
        ],
      ),
    ),
  );
  Widget _history() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Your audit history',
          'Open a report to see its full evidence and improvement plan.',
        ),
        if (_runs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Text(
              'Your first SEO report starts with an audit.',
              style: TextStyle(color: _muted),
            ),
          ),
        for (final run in _runs)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: _line),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _pill(_s(run['state']).toUpperCase()),
                      _pill(
                        run['source'] == 'weekly'
                            ? 'WEEKLY AUDIT'
                            : 'ON-DEMAND AUDIT',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _date(run['createdAt']),
                    style: const TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((run['charged'] as num? ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${run['charged']} credits + 1 generation ${_running(run) ? 'reserved' : 'used'}',
                        style: const TextStyle(color: _muted),
                      ),
                    ),
                  if (_s(run['error']).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_s(run['error'])),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: Key('seo-open-${run['id']}'),
                    onPressed: _busy ? null : () => _openReport(_s(run['id'])),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Open report'),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
  Widget _report() {
    final run = _selected!,
        r = _map(run['result']),
        ai = _map(r['ai']),
        coverage = _map(r['coverage']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _selected = null),
          icon: const Icon(Icons.arrow_back),
          label: const Text('All reports'),
        ),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill(_s(run['state']).toUpperCase()),
                  _pill(
                    run['source'] == 'weekly'
                        ? 'WEEKLY AUDIT'
                        : 'ON-DEMAND AUDIT',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _heading('Your SEO improvement plan', _date(run['createdAt'])),
              if (_running(run)) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 14),
                Text(_s(run['phase'])),
              ],
              if (run['state'] == 'failed')
                Text(
                  _s(run['error']).isEmpty
                      ? 'This audit could not finish. Start a new audit when you are ready.'
                      : _s(run['error']),
                ),
              if (run['state'] == 'completed') ...[
                Wrap(
                  spacing: 30,
                  runSpacing: 18,
                  children: [
                    _stat('Heuristic health score', '${r['score'] ?? '—'}/100'),
                    _stat(
                      'Public pages sampled',
                      '${coverage['pagesScanned'] ?? 0}/${coverage['pageLimit'] ?? 5}',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SelectableText(
                  _s(ai['summary']),
                  style: const TextStyle(color: _navy, height: 1.6),
                ),
                const SizedBox(height: 16),
                const Text(
                  'This score is not a ranking. Google rankings, traffic and indexing status are not measured. Findings apply to the sampled pages.',
                  style: TextStyle(color: _muted, height: 1.5),
                ),
                for (final limit in ((r['limitations'] as List?) ?? []))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _s(limit),
                      style: const TextStyle(color: _muted),
                    ),
                  ),
                const SizedBox(height: 12),
                _link(_s(r['siteUrl'])),
                OutlinedButton.icon(
                  key: const Key('seo-copy-report'),
                  onPressed: () => _copy(seoReportText(run)),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy report'),
                ),
              ],
            ],
          ),
        ),
        if (run['state'] == 'completed') ...[
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heading(
                  'Evidence & findings',
                  'Review what KORLIX observed before deciding what to change.',
                ),
                if (_rows(r['findings']).isEmpty)
                  const Text('No findings were reported for this sample.'),
                for (final finding in _rows(r['findings']))
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      _s(finding['title']),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(_s(finding['priority']).toUpperCase()),
                    childrenPadding: const EdgeInsets.only(bottom: 18),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(_s(finding['detail'])),
                      const SizedBox(height: 10),
                      if (_s(finding['evidence']).isNotEmpty)
                        SelectableText(
                          'Evidence: ${finding['evidence']}',
                          style: const TextStyle(color: _muted),
                        ),
                      _link(_s(finding['url'])),
                    ],
                  ),
                if (_rows(r['pages']).isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Pages in this sample'),
                    children: [
                      for (final page in _rows(r['pages']))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_s(page['title']).isNotEmpty)
                                Text(_s(page['title'])),
                              _link(_s(page['url'])),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heading(
                  'Content opportunities',
                  'Ideas based on your business and the sampled pages. Search volumes and ranking positions are not measured.',
                ),
                if (_rows(ai['opportunities']).isEmpty)
                  const Text(
                    'No content opportunities were returned for this audit.',
                  ),
                for (final opportunity in _rows(ai['opportunities']))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _s(opportunity['topic']),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _navy,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Search intent: ${opportunity['intent']}',
                          style: const TextStyle(color: _cyan),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          _s(opportunity['rationale']),
                          style: const TextStyle(color: _muted, height: 1.5),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heading(
                  'Your action list',
                  'Mark the actions you have reviewed and record what you changed. These marks do not apply changes to your website.',
                ),
                for (final action in _rows(ai['actions']))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          key: Key('seo-action-${action['id']}'),
                          title: Text(
                            _s(action['title']),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${_s(action['priority']).toUpperCase()} · Mark reviewed',
                          ),
                          value: _completed.contains(_s(action['id'])),
                          onChanged: _busy
                              ? null
                              : (value) => setState(() {
                                  if (value == true) {
                                    _completed.add(_s(action['id']));
                                  } else {
                                    _completed.remove(_s(action['id']));
                                  }
                                }),
                        ),
                        SelectableText(
                          _s(action['why']),
                          style: const TextStyle(color: _muted),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(_s(action['how'])),
                        _link(_s(action['url'])),
                      ],
                    ),
                  ),
                TextField(
                  key: const Key('seo-notes'),
                  controller: _notes,
                  minLines: 3,
                  maxLines: 7,
                  maxLength: 2000,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Your review notes',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('seo-save-progress'),
                  onPressed: _busy ? null : _saveProgress,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save review progress'),
                ),
              ],
            ),
          ),
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heading(
                  'Drafts you can work with',
                  'Review facts, voice and relevance before copying these into your website. Nothing is published automatically.',
                ),
                if (_rows(ai['drafts']).isEmpty)
                  const Text('No drafts were returned for this audit.'),
                for (final draft in _rows(ai['drafts']))
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      _s(draft['title']),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _s(draft['type']).replaceAll('_', ' ').toUpperCase(),
                    ),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    childrenPadding: const EdgeInsets.only(bottom: 18),
                    children: [
                      SelectableText(
                        _s(draft['body']),
                        style: const TextStyle(height: 1.6),
                      ),
                      _link(_s(draft['url'])),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _copy('${draft['title']}\n\n${draft['body']}'),
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy draft'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
        if (!_running(run))
          TextButton.icon(
            onPressed: _working ? null : _remove,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete report'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _cyan),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF4F7FA),
      textTheme: Theme.of(
        context,
      ).textTheme.apply(bodyColor: _navy, displayColor: _navy),
    );
    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('KORLIX AI SEO Agent'),
          backgroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'Refresh SEO Agent',
              onPressed: _locked || _busy || _refreshing ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: _locked
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Your sign-in changed. Reopen SEO Agent to continue.',
                    ),
                  ),
                )
              : _loading
              ? const Center(child: CircularProgressIndicator())
              : SelectionArea(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(18),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _hero(),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                for (final (index, label, icon) in [
                                  (0, 'Overview', Icons.dashboard_outlined),
                                  (1, 'Reports', Icons.analytics_outlined),
                                  (
                                    2,
                                    'Business setup',
                                    Icons.business_outlined,
                                  ),
                                ])
                                  ChoiceChip(
                                    key: Key('seo-tab-$index'),
                                    selected: _tab == index,
                                    onSelected: (_) => _go(index),
                                    avatar: Icon(icon, size: 18),
                                    label: Text(label),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            if (_busy || _refreshing)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 16),
                                child: LinearProgressIndicator(),
                              ),
                            if (_error != null)
                              _panel(
                                Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Color(0xFF9E2222),
                                  ),
                                ),
                                color: const Color(0xFFFFF3F1),
                              ),
                            if (_notice != null && _notice!.isNotEmpty)
                              _panel(
                                Text(
                                  _notice!,
                                  style: const TextStyle(color: _navy),
                                ),
                                color: const Color(0xFFE9F6F8),
                              ),
                            if (_active != null) _activity(),
                            if (_tab == 0) _overview(),
                            if (_tab == 1)
                              _selected == null ? _history() : _report(),
                            if (_tab == 2) _setup(),
                            const SizedBox(height: 20),
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
}
