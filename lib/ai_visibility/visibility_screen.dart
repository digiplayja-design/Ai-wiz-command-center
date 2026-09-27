import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'visibility_client.dart';

const _ink = Color(0xFF102C45),
    _accent = Color(0xFF5B47C7),
    _muted = Color(0xFF53697A),
    _line = Color(0xFFDDE5EC);
const _labels = {
  'businessName': 'Business name',
  'website': 'Business website',
  'services': 'Service or product category',
  'market': 'Target market',
  'facts': 'Business facts',
};
const _required = {
  'businessName': 'Enter your business name.',
  'website': 'Enter your website.',
  'services': 'Describe your service or product category.',
  'market': 'Enter a city, country or target market.',
};
Map<String, dynamic> _map(dynamic x) =>
    x is Map ? Map<String, dynamic>.from(x) : {};
List<Map<String, dynamic>> _rows(dynamic x) =>
    x is List ? x.whereType<Map>().map(_map).toList() : [];
String _s(dynamic x) => x?.toString() ?? '';
List<String> visibilitySuggestedQuestions(Map<String, dynamic> p) => [
  'Which businesses offer ${p['services']} in ${p['market']}? Compare relevant options using public sources.',
  'Who can a customer contact for ${p['services']} in ${p['market']}? Explain the options and cite sources.',
  'Which providers should a customer consider for ${p['services']} in ${p['market']}, and what should they compare? Cite sources.',
];
Map<String, dynamic>? comparableVisibilityRun(
  Map<String, dynamic> current,
  List<Map<String, dynamic>> runs,
) {
  final f = _s(_map(current['result'])['fingerprint']);
  if (f.isEmpty) return null;
  return runs
      .where(
        (r) =>
            r['id'] != current['id'] &&
            r['state'] == 'completed' &&
            _map(r['result'])['fingerprint'] == f &&
            _s(r['createdAt']).compareTo(_s(current['createdAt'])) < 0,
      )
      .firstOrNull;
}

String visibilityReportText(Map<String, dynamic> run) {
  final r = _map(run['result']), b = _map(r['business']);
  final lines = <String>[
    'KORLIX AI VISIBILITY',
    '${b['businessName']} · ${b['website']}',
    'Scanned: ${r['scannedAt']}',
    '${r['provider']} · ${r['model']}',
    'Name matches: ${r['nameMatches']}/${r['sampleCount']} · Website citations: ${r['siteCitations']}/${r['sampleCount']}',
    _s(r['limits']),
    _s(r['summary']),
  ];
  for (final sample in _rows(r['samples'])) {
    lines.addAll([
      '\nQUESTION: ${sample['question']}',
      _s(sample['answer']),
      'CITED SOURCES:',
      ..._rows(sample['citations']).map((x) => _s(x['url'])),
    ]);
  }
  for (final o in _rows(r['observations'])) {
    lines.addAll(['\n${o['topic']}', _s(o['observation']), _s(o['sourceUrl'])]);
  }
  for (final a in _rows(r['actions'])) {
    lines.addAll([
      '\n${a['priority']}: ${a['title']}',
      _s(a['why']),
      _s(a['how']),
    ]);
  }
  for (final d in _rows(r['drafts'])) {
    lines.addAll([
      '\n${d['title']}',
      _s(d['body']),
      ...((d['sourceUrls'] as List?) ?? []).map(_s),
    ]);
  }
  final p = _map(run['progress']);
  lines.addAll([
    '\nOWNER-RECORDED OUTCOMES (not attributed automatically)',
    'Inquiries: ${p['inquiries'] ?? 0}; bookings: ${p['bookings'] ?? 0}',
    _s(p['notes']),
  ]);
  return lines.join('\n');
}

class AiVisibilityScreen extends StatefulWidget {
  const AiVisibilityScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    this.openLink,
    this.copyText,
    this.disposeClient = true,
  });
  final VisibilityClient client;
  final Future<bool> Function() ensureConsent;
  final Future<bool> Function(Uri)? openLink;
  final Future<void> Function(String)? copyText;
  final bool disposeClient;
  @override
  State<AiVisibilityScreen> createState() => _AiVisibilityScreenState();
}

class _AiVisibilityScreenState extends State<AiVisibilityScreen> {
  final _fields = {for (final k in _labels.keys) k: TextEditingController()},
      _anchors = {for (final k in _labels.keys) k: GlobalKey()},
      _focusNodes = {for (final k in _labels.keys) k: FocusNode()};
  final _questions = List.generate(3, (_) => TextEditingController());
  final _scroll = ScrollController();
  final _setupFeedback = GlobalKey();
  Map<String, dynamic>? _profile, _active, _selected;
  List<Map<String, dynamic>> _runs = [];
  bool _loading = true,
      _refreshing = false,
      _busy = false,
      _locked = false,
      _loadedProfile = false,
      _dirty = false,
      _attempted = false,
      _customQuestions = false,
      _polling = false,
      _savingProfile = false;
  int _tab = 0;
  String? _error, _notice, _setupError, _requestKey;
  Timer? _timer;
  bool get _working => _busy || _refreshing || _active != null;
  @override
  void initState() {
    super.initState();
    widget.client.onAccessDenied = _lock;
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [..._fields.values, ..._questions]) {
      c.dispose();
    }
    for (final n in _focusNodes.values) {
      n.dispose();
    }
    _scroll.dispose();
    widget.client.onAccessDenied = null;
    if (widget.disposeClient) widget.client.dispose();
    super.dispose();
  }

  void _lock() {
    if (!mounted) return;
    _timer?.cancel();
    setState(() {
      _locked = true;
      _profile = _active = _selected = null;
      _runs = [];
      _error = _notice = _setupError = _requestKey = null;
      for (final c in [..._fields.values, ..._questions]) {
        c.clear();
      }
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _go(int tab) {
    if (_locked) return;
    FocusScope.of(context).unfocus();
    setState(() => _tab = tab);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _feedback(String message) {
    if (!mounted || _locked) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
      );
  }

  void _populate(Map<String, dynamic> p) {
    for (final e in _fields.entries) {
      e.value.text = _s(p[e.key]);
    }
    final qs = (p['questions'] as List?) ?? [];
    for (var i = 0; i < 3; i++) {
      _questions[i].text = i < qs.length ? _s(qs[i]) : '';
    }
    _customQuestions =
        qs.isNotEmpty && !listEquals(qs, visibilitySuggestedQuestions(p));
  }

  Future<void> _load() async {
    if (_locked || _refreshing) return;
    _refreshing = true;
    try {
      final d = await widget.client.load();
      if (!mounted || _locked) return;
      setState(() {
        _profile = d['profile'] == null ? null : _map(d['profile']);
        _runs = _rows(d['runs']);
        _active = _runs.where((r) => r['state'] == 'running').firstOrNull;
        if (!_loadedProfile) {
          _populate(_map(_profile?['data']));
          _loadedProfile = true;
          if (_profile == null) _tab = 2;
        }
        _loading = false;
        _error = null;
      });
      _schedule();
    } catch (e) {
      if (mounted && !_locked) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    } finally {
      _refreshing = false;
      if (mounted) setState(() {});
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (mounted && !_locked && _active != null) {
      _timer = Timer(const Duration(seconds: 3), () => unawaited(_poll()));
    }
  }

  Future<void> _poll() async {
    if (_polling || _locked || _active == null) return;
    _polling = true;
    try {
      final r = await widget.client.run(_s(_active?['id']));
      if (!mounted || _locked) return;
      setState(() {
        _active = r['state'] == 'running' ? r : null;
        if (_selected?['id'] == r['id']) _selected = r;
      });
      if (r['state'] != 'running') {
        _requestKey = null;
        await _load();
        if (mounted && !_locked) {
          setState(
            () => _notice = r['state'] == 'completed'
                ? 'Your KORLIX visibility report is ready.'
                : _s(r['error']),
          );
        }
      }
    } catch (e) {
      if (mounted && !_locked) {
        setState(
          () =>
              _error = '$e The scan remains saved. Refresh to check progress.',
        );
      }
    } finally {
      _polling = false;
      _schedule();
    }
  }

  Future<void> _saveProfile() async {
    if (_working || _locked) return;
    final p = {for (final e in _fields.entries) e.key: e.value.text.trim()};
    final missing = _required.keys.where((k) => p[k]!.isEmpty).firstOrNull;
    if (missing != null) {
      setState(() {
        _attempted = true;
        _setupError = 'Complete the required fields marked above.';
      });
      _feedback('Please complete the highlighted field.');
      _focusNodes[missing]!.requestFocus();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _locked) return;
      final field = _anchors[missing]?.currentContext;
      if (field != null && field.mounted) {
        await Scrollable.ensureVisible(
          field,
          alignment: 0.15,
          duration: const Duration(milliseconds: 250),
        );
      }
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = _savingProfile = true;
      _setupError = _error = null;
    });
    try {
      final saved = await widget.client.saveProfile({
        ...p,
        'questions': _questions.map((c) => c.text.trim()).toList(),
      });
      if (!mounted || _locked) return;
      setState(() {
        _profile = saved;
        _loadedProfile = true;
        _dirty = _attempted = false;
        _requestKey = null;
        _populate(_map(saved['data']));
        _notice = 'Business setup saved. Your visibility scan is ready.';
      });
      _go(0);
      _feedback('Business setup saved.');
    } catch (e) {
      if (!mounted || _locked) return;
      setState(() => _setupError = e.toString());
      _feedback(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = _savingProfile = false;
        });
      }
    }
    // Restore the form before bringing server feedback into view. Text field
    // focus/layout changes while saving must not override this final scroll.
    if (!mounted || _locked || _setupError == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _locked) return;
    // Cancel any earlier field-reveal animation before showing feedback.
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.offset);
    final c = _setupFeedback.currentContext;
    if (c != null && c.mounted) {
      await Scrollable.ensureVisible(
        c,
        alignment: 0.2,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  Future<void> _start() async {
    if (_working || _locked) return;
    if (_profile == null || _dirty) {
      _go(2);
      _feedback('Save your business setup before scanning.');
      return;
    }
    setState(() {
      _busy = true;
      _error = _notice = null;
    });
    try {
      if (!await widget.ensureConsent() || !mounted || _locked) return;
      _requestKey ??= visibilityRequestKey();
      final r = await widget.client.start(_requestKey!);
      if (!mounted || _locked) return;
      setState(() {
        _selected = r;
        _active = r['state'] == 'running' ? r : null;
      });
      _go(1);
      if (_active != null) {
        _schedule();
      } else {
        _requestKey = null;
        await _load();
      }
    } catch (e) {
      if (mounted && !_locked) {
        setState(() => _error = e.toString());
        _feedback(e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openReport(String id) async {
    if (_busy || _locked) return;
    setState(() => _busy = true);
    try {
      final r = await widget.client.run(id);
      if (!mounted || _locked) return;
      setState(() => _selected = r);
      _go(1);
    } catch (e) {
      if (mounted && !_locked) {
        setState(() => _error = e.toString());
        _feedback(e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _saveProgress(Map<String, dynamic> data) async {
    if (_busy || _locked || _selected == null) return false;
    final id = _s(_selected?['id']);
    setState(() => _busy = true);
    try {
      final r = await widget.client.progress(id, data);
      if (!mounted || _locked) return false;
      setState(() {
        if (_selected?['id'] == id) _selected = r;
        _runs = _runs.map((x) => x['id'] == id ? r : x).toList();
      });
      return true;
    } catch (e) {
      _feedback(e.toString());
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _remove({bool all = false}) async {
    if (_working || _locked) return;
    final id = _selected?['id'];
    if (!all && id == null) return;
    if (!await _confirm(
          all ? 'Clear AI Visibility?' : 'Remove this report?',
          all
              ? 'Remove your business setup and all visibility reports and progress. Used credits are not refunded.'
              : 'Remove this saved report and its progress records.',
        ) ||
        !mounted ||
        _locked) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (all) {
        await widget.client.clear();
      } else {
        await widget.client.remove(_s(id));
      }
      if (!mounted || _locked) return;
      setState(() {
        _selected = null;
        if (all) {
          _loadedProfile = _dirty = _attempted = false;
          _setupError = null;
          _requestKey = null;
        }
      });
      await _load();
      _feedback(all ? 'AI Visibility records removed.' : 'Report removed.');
    } catch (e) {
      _feedback(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String value) async {
    try {
      if (widget.copyText != null) {
        await widget.copyText!(value);
      } else {
        await Clipboard.setData(ClipboardData(text: value));
      }
      _feedback('Copied. Review and verify before publishing.');
    } catch (_) {
      _feedback(
        'Copy was unavailable. Select the report text and copy it manually.',
      );
    }
  }

  Future<void> _open(String value) async {
    try {
      final u = Uri.parse(value);
      if (u.scheme != 'https' || u.userInfo.isNotEmpty) {
        throw const VisibilityException('This source link is unavailable.');
      }
      final ok = widget.openLink != null
          ? await widget.openLink!(u)
          : await launchUrl(u, mode: LaunchMode.externalApplication);
      if (!ok) throw const VisibilityException('Could not open this source.');
    } catch (e) {
      _feedback(e.toString());
    }
  }

  Widget _card(Widget child) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: _line),
    ),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: SizedBox(width: double.infinity, child: child),
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
            color: _ink,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: _muted, height: 1.4)),
        ],
      ],
    ),
  );
  Widget _source(String url, [String? title]) => TextButton.icon(
    onPressed: () => _open(url),
    icon: const Icon(Icons.open_in_new, size: 16),
    label: Text(title?.isNotEmpty == true ? title! : url, softWrap: true),
  );
  Widget _metrics(Map<String, dynamic> r) => Wrap(
    spacing: 16,
    runSpacing: 12,
    children: [
      for (final v in [
        ('Name appears', '${r['nameMatches'] ?? 0} / ${r['sampleCount'] ?? 3}'),
        (
          'Website cited',
          '${r['siteCitations'] ?? 0} / ${r['sampleCount'] ?? 3}',
        ),
      ])
        Container(
          width: 240,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF2EEFF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(v.$1, style: const TextStyle(color: _muted)),
              Text(
                v.$2,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: _accent,
                ),
              ),
              const Text(
                'sampled answers',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
    ],
  );
  Widget _overview() {
    final p = _map(_profile?['data']),
        latest = _runs.where((r) => r['state'] == 'completed').firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'When customers ask AI,\ndoes your business appear?',
          'See the sampled answers. Improve the information that customers can find.',
        ),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(
                _profile == null
                    ? 'Start with your business'
                    : _s(p['businessName']),
                _profile == null
                    ? 'Add your website, category and target market.'
                    : _s(p['website']),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    key: const Key('visibility-scan'),
                    onPressed: _working ? null : _start,
                    icon: const Icon(Icons.travel_explore),
                    label: Text(
                      _active != null
                          ? 'Scan in progress'
                          : 'Run visibility scan',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _go(2),
                    icon: const Icon(Icons.business),
                    label: const Text('Business setup'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                '3 credits per completed scan · Ultra Premium / Enterprise. Failed scans use no credits.',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 10),
              const Text(
                'Each scan checks three OpenAI API web-search answers and reviews your website through search. Results are samples, not a ranking or a guarantee. Other AI platforms are not measured.',
                style: TextStyle(color: _muted, height: 1.4),
              ),
              if (p['questions'] is List) ...[
                const Divider(height: 28),
                const Text(
                  'Your discovery questions',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final q in p['questions'])
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('• $q'),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (latest != null)
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heading('Latest completed scan', _s(latest['completedAt'])),
                _metrics(_map(latest['result'])),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _busy ? null : () => _openReport(_s(latest['id'])),
                  child: const Text('Open report'),
                ),
              ],
            ),
          )
        else
          _card(
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A practical path to better information',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 12),
                Text(
                  '1. See three real sampled answers and their sources.\n2. Review website observations and prioritized actions.\n3. Edit service-page, product-description and FAQ drafts.\n4. Run again and compare matching questions.',
                  style: TextStyle(height: 1.8),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _setup() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Business setup',
        'Complete the four required fields (*). Use a category, such as office cleaning, instead of your brand name.',
      ),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in _fields.entries)
              Padding(
                key: _anchors[e.key],
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  key: Key('visibility-${e.key}'),
                  controller: e.value,
                  focusNode: _focusNodes[e.key],
                  enabled: !_working,
                  maxLength: switch (e.key) {
                    'businessName' => 120,
                    'website' => 2000,
                    'services' => 350,
                    'market' => 160,
                    _ => 3000,
                  },
                  minLines: e.key == 'facts' ? 3 : 1,
                  maxLines: e.key == 'facts' ? 7 : 2,
                  keyboardType: e.key == 'website'
                      ? TextInputType.url
                      : TextInputType.multiline,
                  autocorrect: e.key != 'website',
                  onChanged: (_) => setState(() {
                    _dirty = true;
                    if (['services', 'market'].contains(e.key) &&
                        !_customQuestions) {
                      for (final q in _questions) {
                        q.clear();
                      }
                    }
                  }),
                  decoration: InputDecoration(
                    labelText:
                        '${_labels[e.key]}${_required.containsKey(e.key) ? ' *' : ' (optional)'}',
                    hintText: switch (e.key) {
                      'website' => 'yourbusiness.com',
                      'services' => 'Office cleaning, catering, software…',
                      'market' => 'City, region or country',
                      'facts' =>
                        'Accurate details you want included in draft content',
                      _ => null,
                    },
                    errorText: _attempted && e.value.text.trim().isEmpty
                        ? _required[e.key]
                        : null,
                    errorMaxLines: 3,
                  ),
                ),
              ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Customize discovery questions'),
              subtitle: const Text('Optional · three unbranded questions'),
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Leave all three blank for suggested questions. Keep your business name and website out of these questions so the samples can show whether they appear naturally.',
                  ),
                ),
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: TextField(
                      key: Key('visibility-question-$i'),
                      controller: _questions[i],
                      enabled: !_working,
                      minLines: 2,
                      maxLines: 5,
                      maxLength: 800,
                      onChanged: (_) => setState(() {
                        _dirty = _customQuestions = true;
                      }),
                      decoration: InputDecoration(
                        labelText: 'Question ${i + 1}',
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: _working
                      ? null
                      : () => setState(() {
                          _dirty = true;
                          _customQuestions = false;
                          for (final q in _questions) {
                            q.clear();
                          }
                        }),
                  child: const Text('Use suggested questions'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'KORLIX sends the discovery questions, your business setup and public website details to OpenAI when you approve a scan. Saved reports are private to your account.',
              style: TextStyle(color: _muted, height: 1.4),
            ),
            if (_setupError != null)
              Padding(
                key: _setupFeedback,
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _setupError!,
                  key: const Key('visibility-setup-error'),
                  style: const TextStyle(color: Color(0xFFB3261E)),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('visibility-save-profile'),
              onPressed: _working ? null : _saveProfile,
              icon: _savingProfile
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(
                _savingProfile ? 'Saving setup…' : 'Save business setup',
              ),
            ),
          ],
        ),
      ),
      if (_profile != null)
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: TextButton(
            onPressed: _working ? null : () => _remove(all: true),
            child: const Text('Clear my AI Visibility data'),
          ),
        ),
    ],
  );
  Widget _history() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Reports & progress',
        'Repeat a scan after updating your website. Matching questions can be compared; results naturally vary.',
      ),
      if (_runs.isEmpty)
        _card(const Text('Your first completed scan will appear here.')),
      for (final r in _runs)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _s(
                        _map(_map(r['result'])['business'])['businessName'],
                      ).isEmpty
                      ? 'Visibility scan'
                      : _s(_map(_map(r['result'])['business'])['businessName']),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${r['state']} · ${r['createdAt']}',
                  style: const TextStyle(color: _muted),
                ),
                if (r['state'] == 'completed')
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Name appears ${_map(r['result'])['nameMatches']}/3 · Website cited ${_map(r['result'])['siteCitations']}/3',
                    ),
                  ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _busy ? null : () => _openReport(_s(r['id'])),
                  child: const Text('Open report'),
                ),
              ],
            ),
          ),
        ),
    ],
  );
  Widget _report() {
    final run = _selected!,
        r = _map(run['result']),
        progress = _map(run['progress']),
        previous = comparableVisibilityRun(run, _runs);
    final completed = ((progress['completedActions'] as List?) ?? [])
        .map(_s)
        .toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _selected = null),
          icon: const Icon(Icons.arrow_back),
          label: const Text('All reports'),
        ),
        _heading('KORLIX visibility report', _s(run['createdAt'])),
        if (run['state'] != 'completed')
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  run['state'] == 'running'
                      ? _s(run['phase'])
                      : _s(run['error']),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  run['state'] == 'running'
                      ? 'This can take a few minutes. You can leave this page and reopen it to follow the saved scan.'
                      : 'No credits were charged. Start a new scan when ready.',
                ),
                if (run['state'] == 'running')
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          )
        else ...[
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heading(
                  _s(_map(r['business'])['businessName']),
                  _s(_map(r['business'])['website']),
                ),
                _metrics(r),
                const SizedBox(height: 16),
                Text(
                  _s(r['limits']),
                  style: const TextStyle(color: _muted, height: 1.4),
                ),
                const SizedBox(height: 12),
                if (previous == null)
                  const Text(
                    'New baseline: no earlier comparable scan is available.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  )
                else
                  Text(
                    'Compared with ${previous['completedAt']} using the same business and questions: name matches ${_delta(r['nameMatches'], _map(previous['result'])['nameMatches'])}; website citations ${_delta(r['siteCitations'], _map(previous['result'])['siteCitations'])}. This is sample variation, not proof of a ranking change.',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('visibility-copy-report'),
                      onPressed: () => _copy(visibilityReportText(run)),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy report'),
                    ),
                    FilledButton(
                      onPressed: _working ? null : _start,
                      child: const Text('Run again'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _heading(
            'The sampled answers',
            'Name matches are literal. Website citations come from the answer’s cited links, not every page retrieved during research.',
          ),
          for (final sample in _rows(r['samples']))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _card(
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: 12),
                  title: Text(_s(sample['question'])),
                  subtitle: Text(
                    'Name ${sample['nameMatched'] == true ? 'matched' : 'not matched'} · Website ${sample['siteCited'] == true ? 'cited' : 'not cited'}',
                  ),
                  children: [
                    SelectableText(_s(sample['answer'])),
                    const SizedBox(height: 12),
                    for (final source in _rows(sample['citations']))
                      _source(_s(source['url']), _s(source['title'])),
                    if (_rows(sample['citations']).isEmpty)
                      const Text(
                        'No inline source citations were returned. Retrieved sources are shown below.',
                      ),
                    ExpansionTile(
                      title: const Text('All retrieved sources'),
                      children: [
                        for (final source in _rows(sample['retrievedSources']))
                          _source(_s(source['url']), _s(source['title'])),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          _heading(
            'Website observations',
            r['websiteObserved'] == true
                ? 'Search-based observations; check each original page.'
                : 'Website material was not observed in this scan.',
          ),
          _card(Text(_s(r['summary']), style: const TextStyle(height: 1.5))),
          for (final o in _rows(r['observations']))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _s(o['topic']),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_s(o['observation'])),
                    _source(_s(o['sourceUrl'])),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 22),
          _heading(
            'Your improvement plan',
            'Mark an action complete after you have reviewed and applied it.',
          ),
          for (final a in _rows(r['actions']))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: completed.contains(a['id']),
                      onChanged: _busy
                          ? null
                          : (v) {
                              final next = {...completed};
                              if (v == true) {
                                next.add(_s(a['id']));
                              } else {
                                next.remove(a['id']);
                              }
                              unawaited(
                                _saveProgress({
                                  ...progress,
                                  'completedActions': next.toList(),
                                }),
                              );
                            },
                      title: Text(
                        _s(a['title']),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text('${a['priority']} priority'),
                    ),
                    Text(
                      _s(a['why']),
                      style: const TextStyle(color: _muted, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(_s(a['how'])),
                    if (_s(a['sourceUrl']).isNotEmpty)
                      _source(_s(a['sourceUrl'])),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          _heading(
            'Content drafts',
            'Review every fact and replace placeholders before you publish.',
          ),
          for (final d in _rows(r['drafts']))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _card(
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(_s(d['title'])),
                  subtitle: Text(_s(d['type']).replaceAll('_', ' ')),
                  children: [
                    SelectableText(_s(d['body'])),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _copy(_s(d['body'])),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy draft'),
                    ),
                    for (final u in (d['sourceUrls'] as List?) ?? [])
                      _source(_s(u)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          _card(
            _ProgressEditor(
              key: ValueKey('progress-${run['id']}'),
              progress: progress,
              busy: _busy,
              onSave: _saveProgress,
            ),
          ),
        ],
        const SizedBox(height: 14),
        if (run['state'] != 'running')
          TextButton(
            onPressed: _working ? null : () => _remove(),
            child: const Text('Remove this report'),
          ),
      ],
    );
  }

  String _delta(dynamic a, dynamic b) {
    final n = (a is num ? a : 0) - (b is num ? b : 0);
    return n > 0 ? '+$n' : '$n';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accent,
        brightness: Brightness.light,
      ).copyWith(surface: Colors.white, onSurface: _ink),
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFAFBFD),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
        ),
      ),
    );
    return Theme(
      data: theme,
      child: LayoutBuilder(
        builder: (context, c) {
          final desktop = c.maxWidth >= 1000;
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.white,
              title: const Text(
                'KORLIX AI Visibility',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              actions: [
                IconButton(
                  onPressed: _busy || _refreshing || _locked ? null : _load,
                  tooltip: 'Refresh visibility',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            bottomNavigationBar: desktop || _locked
                ? null
                : NavigationBar(
                    selectedIndex: _tab,
                    onDestinationSelected: _go,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.travel_explore),
                        label: 'Overview',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.assessment_outlined),
                        label: 'Reports',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.business_outlined),
                        label: 'Business',
                      ),
                    ],
                  ),
            body: SafeArea(
              child: _locked
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Your session changed. Close this screen, sign in and reopen AI Visibility.',
                        ),
                      ),
                    )
                  : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (desktop)
                          SizedBox(
                            width: 210,
                            child: Material(
                              color: _ink,
                              child: Column(
                                children: [
                                  const SizedBox(height: 30),
                                  Image.asset(
                                    'assets/branding/korlix_mini_mark.png',
                                    width: 58,
                                    height: 58,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'KORLIX',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 21,
                                      letterSpacing: 3,
                                    ),
                                  ),
                                  const SizedBox(height: 30),
                                  for (final item in [
                                    (Icons.travel_explore, 'Overview', 0),
                                    (Icons.assessment_outlined, 'Reports', 1),
                                    (Icons.business_outlined, 'Business', 2),
                                  ])
                                    ListTile(
                                      selected: _tab == item.$3,
                                      selectedTileColor: const Color(
                                        0xFF35446F,
                                      ),
                                      textColor: Colors.white,
                                      iconColor: Colors.white,
                                      selectedColor: Colors.white,
                                      leading: Icon(item.$1),
                                      title: Text(item.$2),
                                      onTap: () => _go(item.$3),
                                    ),
                                  const Spacer(),
                                  const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Text(
                                      'Be easier to discover.\nBe clearer to choose.',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _scroll,
                            padding: EdgeInsets.all(desktop ? 34 : 16),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1140,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_error != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 16,
                                        ),
                                        child: _card(
                                          Text(
                                            _error!,
                                            style: const TextStyle(
                                              color: Color(0xFFB3261E),
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (_notice != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 16,
                                        ),
                                        child: _card(Text(_notice!)),
                                      ),
                                    if (_active != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 18,
                                        ),
                                        child: _card(
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'KORLIX is working: ${_active!['phase']}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              const LinearProgressIndicator(),
                                              TextButton(
                                                onPressed: _busy
                                                    ? null
                                                    : () => _openReport(
                                                        _s(_active!['id']),
                                                      ),
                                                child: const Text(
                                                  'Follow scan',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    switch (_tab) {
                                      0 => _overview(),
                                      1 =>
                                        _selected == null
                                            ? _history()
                                            : _report(),
                                      _ => _setup(),
                                    },
                                    const SizedBox(height: 30),
                                    const Text(
                                      'Private to your account. Reports are sampled observations and working drafts. Publishing content and recording outcomes remain your choice.',
                                      style: TextStyle(
                                        color: _muted,
                                        fontSize: 12,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _ProgressEditor extends StatefulWidget {
  const _ProgressEditor({
    super.key,
    required this.progress,
    required this.busy,
    required this.onSave,
  });
  final Map<String, dynamic> progress;
  final bool busy;
  final Future<bool> Function(Map<String, dynamic>) onSave;
  @override
  State<_ProgressEditor> createState() => _ProgressEditorState();
}

class _ProgressEditorState extends State<_ProgressEditor> {
  late final TextEditingController _inquiries, _bookings, _notes;
  String? _error;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _inquiries = TextEditingController(
      text: _s(widget.progress['inquiries'] ?? 0),
    );
    _bookings = TextEditingController(
      text: _s(widget.progress['bookings'] ?? 0),
    );
    _notes = TextEditingController(text: _s(widget.progress['notes']));
  }

  @override
  void dispose() {
    _inquiries.dispose();
    _bookings.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final i = int.tryParse(_inquiries.text), b = int.tryParse(_bookings.text);
    if (i == null ||
        b == null ||
        i < 0 ||
        b < 0 ||
        i > 1000000 ||
        b > 1000000) {
      setState(
        () => _error = 'Enter whole-number counts between 0 and 1,000,000.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await widget.onSave({
      ...widget.progress,
      'inquiries': i,
      'bookings': b,
      'notes': _notes.text.trim(),
    });
    if (mounted) {
      setState(() {
        _saving = false;
        _error = ok
            ? 'Progress saved.'
            : 'Progress could not be saved. Your entries remain here; retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Track business outcomes',
        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text(
        'Optional manual notes for this report. These counts do not prove that AI visibility caused an inquiry or booking.',
        style: TextStyle(color: _muted, height: 1.4),
      ),
      const SizedBox(height: 16),
      TextField(
        key: const Key('visibility-inquiries'),
        controller: _inquiries,
        enabled: !widget.busy && !_saving,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Inquiries recorded'),
      ),
      const SizedBox(height: 14),
      TextField(
        key: const Key('visibility-bookings'),
        controller: _bookings,
        enabled: !widget.busy && !_saving,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Bookings recorded'),
      ),
      const SizedBox(height: 14),
      TextField(
        key: const Key('visibility-progress-notes'),
        controller: _notes,
        enabled: !widget.busy && !_saving,
        maxLength: 2000,
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: 'Dates, changes and notes',
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(_error!),
        ),
      FilledButton(
        key: const Key('visibility-save-progress'),
        onPressed: widget.busy || _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save progress'),
      ),
    ],
  );
}
