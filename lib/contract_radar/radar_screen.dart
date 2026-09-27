import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'radar_client.dart';

const _navy = Color(0xFF082C41),
    _cyan = Color(0xFF007BA8),
    _muted = Color(0xFF526C7C),
    _line = Color(0xFFDCE7EC);
const _profileLabels = {
  'businessName': 'Business name',
  'services': 'Services or products',
  'location': 'Service area',
  'capacity': 'Team, capacity and experience',
  'certifications': 'Credentials you currently hold',
  'naics': 'NAICS codes, if known',
};
const _requiredProfileErrors = {
  'businessName': 'Enter your business name.',
  'services': 'Describe the services or products you offer.',
  'location': 'Enter where you can work, such as a city or country.',
};
const _stages = {
  'saved': 'Saved',
  'reviewing': 'Reviewing',
  'preparing': 'Preparing',
  'submitted': 'Submitted',
  'won': 'Won',
  'closed': 'Closed',
};
Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : {};
List<Map<String, dynamic>> _rows(dynamic v) =>
    v is List ? v.whereType<Map>().map(_map).toList() : [];
String _s(dynamic v) => v?.toString() ?? '';

class ContractRadarScreen extends StatefulWidget {
  const ContractRadarScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    this.openLink,
    this.copyText,
    this.disposeClient = true,
  });
  final RadarClient client;
  final Future<bool> Function() ensureConsent;
  final Future<bool> Function(Uri)? openLink;
  final Future<void> Function(String)? copyText;
  final bool disposeClient;
  @override
  State<ContractRadarScreen> createState() => _ContractRadarScreenState();
}

class _ContractRadarScreenState extends State<ContractRadarScreen> {
  final _editors = {
    for (final k in _profileLabels.keys) k: TextEditingController(),
  };
  final _profileAnchors = {for (final k in _profileLabels.keys) k: GlobalKey()};
  final _profileFocus = {for (final k in _profileLabels.keys) k: FocusNode()};
  bool _profileAttempted = false, _savingProfile = false;
  String? _profileSaveError;
  final _profileSaveFeedbackAnchor = GlobalKey();
  final _focus = TextEditingController(), _filter = TextEditingController();
  final _scroll = ScrollController();
  Map<String, dynamic>? _profile, _job, _search;
  Map<String, dynamic>? _editorDraft;
  String? _editorDraftFor;
  BuildContext? _dialogContext;
  List<Map<String, dynamic>> _saved = [];
  String? _selectedId, _error, _notice, _requestKey, _signature;
  String _stageFilter = 'all';
  bool _loading = true,
      _busy = false,
      _locked = false,
      _refreshing = false,
      _polling = false,
      _profileDirty = false,
      _loadedProfile = false;
  int _tab = 0;
  Timer? _timer;
  bool get _running => _job?['state'] == 'running';
  bool get _working => _busy || _running || _refreshing;
  Map<String, dynamic>? get _selected =>
      _saved.where((x) => x['id'] == _selectedId).firstOrNull;
  @override
  void initState() {
    super.initState();
    widget.client.onAccessDenied = _lock;
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _editors.values) {
      c.dispose();
    }
    for (final node in _profileFocus.values) {
      node.dispose();
    }
    _focus.dispose();
    _filter.dispose();
    _scroll.dispose();
    widget.client.onAccessDenied = null;
    if (widget.disposeClient) widget.client.dispose();
    super.dispose();
  }

  void _lock() {
    if (!mounted) return;
    _timer?.cancel();
    final dialog = _dialogContext;
    if (dialog != null && dialog.mounted) {
      final route = ModalRoute.of(dialog);
      if (route != null) Navigator.of(dialog).removeRoute(route);
    }
    _dialogContext = null;
    setState(() {
      _locked = true;
      _profile = null;
      _saved = [];
      _job = null;
      _search = null;
      _selectedId = null;
      _error = null;
      _notice = null;
      _requestKey = null;
      _signature = null;
      _editorDraft = null;
      _editorDraftFor = null;
      _profileSaveError = null;
      _profileAttempted = false;
      for (final c in _editors.values) {
        c.clear();
      }
      _focus.clear();
      _filter.clear();
    });
  }

  void _go(int tab) {
    setState(() => _tab = tab);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _load() async {
    if (_locked || _refreshing) return;
    _refreshing = true;
    try {
      final d = await widget.client.load();
      if (!mounted || _locked) return;
      setState(() {
        _profile = d['profile'] == null ? null : _map(d['profile']);
        _saved = _rows(d['opportunities']);
        if (!_loadedProfile) {
          final p = _map(_profile?['data']);
          for (final e in _editors.entries) {
            e.value.text = _s(p[e.key]);
          }
          _loadedProfile = true;
          if (_profile == null) _tab = 2;
        }
        final jobs = _rows(d['jobs']);
        _job =
            jobs.where((j) => j['state'] == 'running').firstOrNull ??
            jobs.firstOrNull;
        _search = jobs
            .where((j) => j['kind'] == 'discover' && j['state'] == 'completed')
            .firstOrNull;
        if (_selected == null) _selectedId = null;
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
    if (mounted && !_locked && _running) {
      _timer = Timer(const Duration(seconds: 3), () => unawaited(_poll()));
    }
  }

  Future<void> _poll() async {
    if (_polling || _locked || !_running) return;
    _polling = true;
    try {
      final j = await widget.client.job(_s(_job?['id']));
      if (!mounted || _locked) return;
      setState(() => _job = j);
      if (j['state'] != 'running') {
        _requestKey = null;
        _signature = null;
        await _load();
        if (!mounted || _locked) return;
        setState(() {
          _notice = j['state'] == 'completed'
              ? (j['kind'] == 'discover'
                    ? 'Your source-linked search is ready.'
                    : 'Your bid review and working draft are saved.')
              : _s(j['error']);
        });
      } else {
        setState(() => _error = null);
      }
    } catch (e) {
      if (mounted && !_locked) {
        setState(
          () => _error =
              '$e Your request remains saved; refresh to check progress.',
        );
      }
    } finally {
      _polling = false;
      _schedule();
    }
  }

  Future<void> _act(Future<void> Function() action, {String? success}) async {
    if (_working || _locked) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      if (!mounted || _locked) return;
      await _load();
      if (mounted && !_locked && success != null) {
        setState(() => _notice = success);
      }
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_working || _locked) return;
    final p = {for (final e in _editors.entries) e.key: e.value.text.trim()};
    final missing = _requiredProfileErrors.keys
        .where((k) => p[k]!.isEmpty)
        .firstOrNull;
    if (missing != null) {
      setState(() {
        _profileAttempted = true;
        _error = null;
        _profileSaveError = 'Complete the required fields marked above.';
      });
      _profileFeedback('Please complete the highlighted field.');
      _profileFocus[missing]!.requestFocus();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _locked) return;
      final field = _profileAnchors[missing]?.currentContext;
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
      _busy = true;
      _savingProfile = true;
      _error = null;
      _notice = null;
      _profileSaveError = null;
    });
    try {
      final saved = await widget.client.saveProfile(p);
      if (!mounted || _locked) return;
      setState(() {
        _profile = saved;
        _loadedProfile = true;
        _profileDirty = false;
        _profileAttempted = false;
        _notice = 'Business profile saved. Your radar is ready.';
      });
      _go(0);
      _profileFeedback('Business profile saved. Your radar is ready.');
    } catch (e) {
      if (!mounted || _locked) return;
      setState(() => _profileSaveError = e.toString());
      _profileFeedback(e.toString());
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _locked) return;
      final feedback = _profileSaveFeedbackAnchor.currentContext;
      if (feedback != null && feedback.mounted) {
        await Scrollable.ensureVisible(
          feedback,
          alignment: 0.2,
          duration: const Duration(milliseconds: 250),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _savingProfile = false;
        });
      }
    }
  }

  void _profileFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
      );
  }

  Future<void> _start(String kind, {String? opportunityId}) async {
    if (_working || _locked) return;
    if (_profile == null || _profileDirty) {
      setState(() => _error = 'Save your business profile before asking Nova.');
      _go(2);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      if (!await widget.ensureConsent() || !mounted || _locked) return;
      final sig = '$kind|$opportunityId|${_focus.text.trim()}';
      if (sig != _signature) {
        _signature = sig;
        _requestKey = radarRequestKey();
      }
      final j = await widget.client.start({
        'request_key': _requestKey,
        'kind': kind,
        'query': kind == 'discover' ? _focus.text.trim() : '',
        'opportunity_id': opportunityId,
        'consent': true,
      });
      if (!mounted || _locked) return;
      setState(() => _job = j);
      if (_running) {
        _schedule();
      } else {
        _requestKey = null;
        _signature = null;
        await _load();
      }
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveFound(int index) async {
    final searchId = _s(_search?['id']);
    await _act(() async {
      final o = await widget.client.saveOpportunity({
        'request_key': radarRequestKey(),
        'job_id': searchId,
        'index': index,
      });
      if (mounted && !_locked) setState(() => _selectedId = _s(o['id']));
    }, success: 'Opportunity saved to your pipeline.');
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
  Future<void> _remove(Map<String, dynamic> o) async {
    if (_working) return;
    if (await _confirm(
          'Remove this opportunity?',
          'This removes the saved opportunity and its reviews. Your business profile stays available.',
        ) &&
        mounted &&
        !_locked) {
      await _act(
        () => widget.client.remove(_s(o['id'])),
        success: 'Opportunity removed.',
      );
    }
  }

  Future<void> _clear() async {
    if (_working) return;
    if (await _confirm(
          'Clear Contract Radar?',
          'Remove your business profile, saved opportunities and search/review history from Contract Radar.',
        ) &&
        mounted &&
        !_locked) {
      await _act(() async {
        await widget.client.clear();
        if (mounted && !_locked) {
          _loadedProfile = false;
          _profileDirty = false;
          _profileAttempted = false;
          _profileSaveError = null;
        }
      }, success: 'Your Contract Radar records have been removed.');
    }
  }

  Future<void> _open(String value) async {
    try {
      final u = Uri.tryParse(value);
      if (u == null ||
          u.scheme != 'https' ||
          u.userInfo.isNotEmpty ||
          u.host.isEmpty) {
        throw const RadarException('This source link is unavailable.');
      }
      final ok = widget.openLink != null
          ? await widget.openLink!(u)
          : await launchUrl(u, mode: LaunchMode.externalApplication);
      if (!ok) {
        throw const RadarException(
          'The source could not be opened. Try again in your browser.',
        );
      }
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = e.toString());
    }
  }

  Future<void> _editOpportunity({Map<String, dynamic>? current}) async {
    if (_working || _locked) return;
    final draftFor = current?['id']?.toString() ?? 'new';
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) {
        _dialogContext = c;
        return _OpportunityEditor(
          current: current,
          initial: _editorDraftFor == draftFor ? _editorDraft : null,
        );
      },
    );
    _dialogContext = null;
    if (data == null || !mounted || _locked) return;
    _editorDraft = data;
    _editorDraftFor = draftFor;
    await _act(
      () async {
        if (current == null) {
          final o = await widget.client.saveOpportunity({
            'request_key': radarRequestKey(),
            ...data,
          });
          if (mounted && !_locked) setState(() => _selectedId = _s(o['id']));
        } else {
          await widget.client.updateOpportunity(_s(current['id']), data);
        }
        if (mounted && !_locked) {
          _editorDraft = null;
          _editorDraftFor = null;
        }
      },
      success: current == null
          ? 'RFP saved. Ask Nova for a bid-readiness review.'
          : 'Changes saved. Review again if you changed the RFP text.',
    );
    if (mounted && !_locked && _error == null) _go(1);
  }

  Future<void> _copy(Map<String, dynamic> o) async {
    final r = _map(o['review']), d = _map(o['data']);
    final content = [
      'KORLIX CONTRACT RADAR — WORKING DRAFT',
      _s(d['title']),
      'Source: ${_s(d['sourceUrl'])}',
      _s(r['summary']),
      'REQUIREMENTS',
      ..._rows(r['requirements']).map(
        (x) =>
            '${_s(x['status']).toUpperCase()}: ${_s(x['requirement'])}\nNotice evidence: ${_s(x['evidence'])}',
      ),
      'QUESTIONS',
      ...((r['questions'] as List?) ?? []).map(_s),
      'NEXT STEPS',
      ...((r['nextSteps'] as List?) ?? []).map(_s),
      'PROPOSAL DRAFT',
      _s(r['draft']),
    ].join('\n\n');
    try {
      if (widget.copyText != null) {
        await widget.copyText!(content);
      } else {
        await Clipboard.setData(ClipboardData(text: content));
      }
      if (mounted && !_locked) {
        setState(
          () => _notice =
              'Review and draft copied. Check every fact before submitting.',
        );
      }
    } catch (e) {
      if (mounted && !_locked) {
        setState(
          () => _error =
              'Copy was unavailable. Select the draft text and copy it manually.',
        );
      }
    }
  }

  Widget _card(Widget child, {Color color = Colors.white}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _line),
    ),
    child: child,
  );
  Widget _heading(String title, {String? subtitle}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: _navy,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(subtitle, style: const TextStyle(color: _muted, height: 1.4)),
        ],
      ],
    ),
  );
  Widget _tag(String label, {bool accent = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: accent ? const Color(0xFFE6F6FC) : const Color(0xFFF0F4F6),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        color: accent ? _cyan : _muted,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
  String _type(dynamic v) => switch (v) {
    'sources_sought' => 'Market research',
    'presolicitation' => 'Upcoming solicitation',
    'solicitation' => 'Solicitation',
    _ => 'Imported RFP',
  };
  String _deadline(Map<String, dynamic> d) {
    final s = _s(d['deadline']);
    if (s.isEmpty) return 'Deadline: check source';
    final expired =
        s.compareTo(DateTime.now().toUtc().toIso8601String().substring(0, 10)) <
        0;
    return '${expired ? 'Listed deadline passed' : 'Listed deadline'}: $s';
  }

  Widget _opportunityCard(
    Map<String, dynamic> d, {
    int? resultIndex,
    Map<String, dynamic>? saved,
  }) {
    final alreadySaved = _saved.any(
      (o) => _map(o['data'])['sourceUrl'] == d['sourceUrl'],
    );
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _tag(_type(d['noticeType']), accent: true),
              if (saved != null) _tag(_stages[saved['stage']] ?? 'Saved'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _s(d['title']),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            [
              _s(d['agency']),
              _s(d['location']),
            ].where((s) => s.isNotEmpty).join(' · '),
            style: const TextStyle(color: _muted),
          ),
          const SizedBox(height: 10),
          Text(
            _s(d['summary']),
            maxLines: saved == null ? 5 : 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(height: 1.5),
          ),
          if (_s(d['matchReason']).isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Why it surfaced: ${d['matchReason']}',
              style: const TextStyle(color: _cyan),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            _deadline(d),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            d['source'] == 'official_search'
                ? 'Search-derived lead · verify notice and amendments'
                : 'Imported information · verify with the buyer',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_s(d['sourceUrl']).isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _open(_s(d['sourceUrl'])),
                  icon: const Icon(Icons.open_in_new, size: 17),
                  label: const Text('Open source'),
                ),
              if (resultIndex != null)
                FilledButton.icon(
                  onPressed: _working || alreadySaved
                      ? null
                      : () => _saveFound(resultIndex),
                  icon: Icon(
                    alreadySaved
                        ? Icons.bookmark_added
                        : Icons.bookmark_add_outlined,
                    size: 18,
                  ),
                  label: Text(alreadySaved ? 'Saved' : 'Save opportunity'),
                ),
              if (saved != null)
                FilledButton(
                  onPressed: () =>
                      setState(() => _selectedId = _s(saved['id'])),
                  child: const Text('Open workspace'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _discover() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading(
              'Find your next opportunity',
              subtitle: _profile == null
                  ? 'Start with a short business profile so Nova knows what to look for.'
                  : 'Searching for ${_s(_map(_profile?['data'])['businessName'])} · ${_s(_map(_profile?['data'])['location'])}',
            ),
            if (_profile == null)
              FilledButton(
                onPressed: () => _go(2),
                child: const Text('Set up my business'),
              )
            else ...[
              TextField(
                key: const Key('radar-search-focus'),
                controller: _focus,
                enabled: !_working,
                maxLength: 800,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Optional search focus',
                  hintText:
                      'For example: school cleaning contracts or meter installation',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    key: const Key('radar-discover'),
                    onPressed: _working ? null : () => _start('discover'),
                    icon: const Icon(Icons.radar),
                    label: const Text('Find opportunities'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _working ? null : () => _editOpportunity(),
                    icon: const Icon(Icons.add),
                    label: const Text('Paste an RFP'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              'Official-source web search: SAM.gov and NYC City Record. Coverage is selective; always check the original notice. Corporate and other RFPs can be pasted for review.',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 6),
            const Text(
              '1 credit per successful search or review · Ultra Premium / Enterprise. Searches with no confirmed results use no credit.',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      if (_search != null) ...[
        _heading(
          'Your latest search',
          subtitle: _s(_map(_search?['result'])['message']),
        ),
        Text(
          'Searched: ${_s(_map(_search?['result'])['searchedAt']).replaceFirst('T', ' ')}',
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        ..._rows(_map(_search?['result'])['opportunities']).asMap().entries.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _opportunityCard(e.value, resultIndex: e.key),
          ),
        ),
        if (_rows(_map(_search?['result'])['opportunities']).isEmpty)
          _card(
            const Text(
              'Try a broader service description or another service area. You can also paste a notice you already found.',
            ),
          ),
      ] else
        _card(
          const Column(
            children: [
              Icon(Icons.travel_explore, size: 48, color: _cyan),
              SizedBox(height: 12),
              Text(
                'Real sources. A clearer next step.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'Nova surfaces relevant notices, explains why they may fit, and helps you prepare. Your saved pipeline begins with your first opportunity.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, height: 1.5),
              ),
            ],
          ),
        ),
    ],
  );
  Widget _profileForm() => Column(
    children: [
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading(
              'Your business profile',
              subtitle:
                  'Complete the three required fields (*). Everything else is optional.',
            ),
            ..._editors.entries.map(
              (e) => Padding(
                key: _profileAnchors[e.key],
                padding: const EdgeInsets.only(bottom: 14),
                child: TextField(
                  key: Key('radar-profile-${e.key}'),
                  controller: e.value,
                  focusNode: _profileFocus[e.key],
                  enabled: !_working,
                  onChanged: (_) => setState(() => _profileDirty = true),
                  maxLength: switch (e.key) {
                    'businessName' => 120,
                    'services' => 2400,
                    'location' => 200,
                    'naics' => 150,
                    _ => 1000,
                  },
                  minLines: e.key == 'services' ? 3 : 1,
                  maxLines:
                      ['services', 'capacity', 'certifications'].contains(e.key)
                      ? 5
                      : 2,
                  decoration: InputDecoration(
                    labelText:
                        '${_profileLabels[e.key]}${_requiredProfileErrors.containsKey(e.key) ? ' *' : ' (optional)'}',
                    errorText: _profileAttempted && e.value.text.trim().isEmpty
                        ? _requiredProfileErrors[e.key]
                        : null,
                    errorMaxLines: 3,
                    alignLabelWithHint: true,
                    hintText: switch (e.key) {
                      'location' => 'City, state, country, or nationwide',
                      'services' => 'Describe the work you want to win',
                      'certifications' =>
                        'Only list credentials you actually hold',
                      _ => null,
                    },
                  ),
                ),
              ),
            ),
            const Text(
              'Credentials are self-reported. Nova cannot certify eligibility. Search uses your services, service area, NAICS codes and search focus; bid reviews also use the rest of this profile and your RFP text.',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 16),
            if (_profileSaveError != null) ...[
              Container(
                key: _profileSaveFeedbackAnchor,
                child: Text(
                  _profileSaveError!,
                  key: const Key('radar-profile-save-error'),
                  style: const TextStyle(color: Color(0xFFB3261E), height: 1.4),
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              key: const Key('radar-save-profile'),
              onPressed: _working ? null : _saveProfile,
              icon: _savingProfile
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(
                _savingProfile
                    ? 'Saving profile…'
                    : _profileDirty
                    ? 'Save profile changes'
                    : 'Save business profile',
              ),
            ),
          ],
        ),
      ),
      if (_profile != null) ...[
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: _working ? null : _clear,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear my Contract Radar data'),
        ),
      ],
    ],
  );
  Widget _savedList() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Your opportunity pipeline',
        subtitle: '${_saved.length}/100 saved · stages are updated by you',
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _working ? null : () => _editOpportunity(),
            icon: const Icon(Icons.add),
            label: const Text('Paste an RFP'),
          ),
          if (_selected != null)
            TextButton(
              onPressed: () => setState(() => _selectedId = null),
              child: const Text('All saved opportunities'),
            ),
        ],
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _filter,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          hintText: 'Search saved opportunities',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 5,
        runSpacing: 5,
        children: {'all': 'All', ..._stages}.entries
            .map(
              (e) => ChoiceChip(
                label: Text(e.value),
                selected: _stageFilter == e.key,
                onSelected: (_) => setState(() => _stageFilter = e.key),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 16),
      if (_saved.isEmpty)
        _card(
          const Text(
            'Save a discovery result or paste an RFP to start your pipeline.',
          ),
        ),
      ..._saved
          .where(
            (o) =>
                (_stageFilter == 'all' || o['stage'] == _stageFilter) &&
                ('${_map(o['data'])['title']} ${_map(o['data'])['agency']}')
                    .toLowerCase()
                    .contains(_filter.text.toLowerCase()),
          )
          .map(
            (o) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _opportunityCard(_map(o['data']), saved: o),
            ),
          ),
    ],
  );
  Widget _bullets(String title, dynamic values) {
    final rows = values is List ? values : [];
    if (rows.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...rows.map(
            (v) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('• ${_s(v)}', style: const TextStyle(height: 1.5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(Map<String, dynamic> o) {
    final d = _map(o['data']), r = _map(o['review']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _selectedId = null),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back to pipeline'),
        ),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heading(
                _s(d['title']),
                subtitle: [
                  _s(d['agency']),
                  _s(d['location']),
                ].where((s) => s.isNotEmpty).join(' · '),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _tag(_type(d['noticeType']), accent: true),
                  _tag(_deadline(d)),
                ],
              ),
              const SizedBox(height: 14),
              Text(_s(d['summary']), style: const TextStyle(height: 1.5)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('stage-${o['id']}-${o['stage']}'),
                initialValue: _s(o['stage']),
                decoration: const InputDecoration(labelText: 'Pipeline stage'),
                items: _stages.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: _working
                    ? null
                    : (v) => _act(
                        () => widget.client.updateOpportunity(_s(o['id']), {
                          'stage': v,
                        }),
                      ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Changing a stage only updates your tracker. KORLIX does not submit bids or contact buyers.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_s(d['sourceUrl']).isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => _open(_s(d['sourceUrl'])),
                      icon: const Icon(Icons.open_in_new, size: 17),
                      label: const Text('Open source'),
                    ),
                  OutlinedButton.icon(
                    key: const Key('radar-edit-rfp'),
                    onPressed: _working
                        ? null
                        : () => _editOpportunity(current: o),
                    icon: const Icon(Icons.edit_note),
                    label: const Text('RFP text & notes'),
                  ),
                  FilledButton.icon(
                    key: const Key('radar-review'),
                    onPressed: _working
                        ? null
                        : () => _start('review', opportunityId: _s(o['id'])),
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(
                      r.isEmpty ? 'Review with Nova' : 'Review again',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _s(d['noticeText']).isEmpty
                    ? 'Add the full RFP text for a detailed requirements review. Without it, Nova can only assess the search summary.'
                    : 'Full notice text provided by you. Confirm it includes current amendments.',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              if (_s(o['notes']).isNotEmpty) ...[
                const Divider(height: 30),
                const Text(
                  'Your notes',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(_s(o['notes'])),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Remove opportunity',
                  onPressed: _working ? null : () => _remove(o),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ],
          ),
        ),
        if (r.isNotEmpty) ...[
          const SizedBox(height: 20),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heading(
                  'Nova’s bid-readiness review',
                  subtitle:
                      'Guidance based on your supplied information. Check the original requirements before committing.',
                ),
                _tag(switch (r['fit']) {
                  'potential_fit' => 'Potential fit',
                  'unlikely_fit' => 'Potential mismatch',
                  _ => 'Needs review',
                }, accent: true),
                const SizedBox(height: 12),
                if (r['limitedToSummary'] == true) ...[
                  const Text(
                    'Summary-only review — full RFP requirements may be missing.',
                    style: TextStyle(fontWeight: FontWeight.w700, color: _cyan),
                  ),
                  const SizedBox(height: 10),
                ],
                SelectableText(
                  _s(r['summary']),
                  style: const TextStyle(height: 1.5),
                ),
                Text(
                  'Profile snapshot: ${_s(r['profileUpdatedAt'])}',
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
                _bullets('Why Nova reached this view', r['reasons']),
                if (_rows(r['requirements']).isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Requirements checklist',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  ..._rows(r['requirements']).map(
                    (x) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _card(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _tag(switch (x['status']) {
                              'provided' => 'In your profile · self-reported',
                              'missing' => 'Missing from your profile',
                              _ => 'Verify requirement',
                            }),
                            const SizedBox(height: 8),
                            Text(
                              _s(x['requirement']),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_s(x['evidence']).isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Notice: “${x['evidence']}”',
                                style: const TextStyle(color: _muted),
                              ),
                            ],
                            if (_s(x['profileEvidence']).isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Your profile: “${x['profileEvidence']}”',
                                style: const TextStyle(color: _muted),
                              ),
                            ],
                          ],
                        ),
                        color: const Color(0xFFF7FAFB),
                      ),
                    ),
                  ),
                ],
                _bullets('Risks and missing information', r['risks']),
                _bullets('Questions for the buyer', r['questions']),
                _bullets('Next steps', r['nextSteps']),
                const Divider(height: 35),
                _heading(
                  'Your working proposal draft',
                  subtitle:
                      'Replace every placeholder and verify all facts, pricing, deadlines and eligibility.',
                ),
                SelectableText(
                  _s(r['draft']),
                  style: const TextStyle(height: 1.6),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  key: const Key('radar-copy-draft'),
                  onPressed: () => _copy(o),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy review & draft'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: _cyan,
            brightness: Brightness.light,
          ).copyWith(
            primary: _cyan,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: _navy,
          ),
      scaffoldBackgroundColor: const Color(0xFFF4F8FA),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: _navy,
        displayColor: _navy,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF7FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
              title: Row(
                children: [
                  Image.asset(
                    'assets/branding/korlix_mini_mark.png',
                    width: 32,
                    height: 32,
                    errorBuilder: (_, _, _) => const Icon(Icons.radar),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Contract Radar',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Refresh radar',
                  onPressed: _busy || _refreshing || _locked ? null : _load,
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
                        icon: Icon(Icons.radar),
                        label: 'Discover',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.bookmarks_outlined),
                        label: 'Pipeline',
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
                        padding: EdgeInsets.all(30),
                        child: Text(
                          'Your session changed. Close this screen, sign in, and reopen Contract Radar.',
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
                            width: 205,
                            child: Material(
                              color: _navy,
                              child: Column(
                                children: [
                                  const SizedBox(height: 32),
                                  Image.asset(
                                    'assets/branding/korlix_mini_mark.png',
                                    width: 62,
                                    height: 62,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'KORLIX',
                                    style: TextStyle(
                                      color: Colors.cyanAccent,
                                      fontSize: 20,
                                      letterSpacing: 3,
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                  ...[
                                    (Icons.radar, 'Discover', 0),
                                    (Icons.bookmarks_outlined, 'Pipeline', 1),
                                    (Icons.business_outlined, 'Business', 2),
                                  ].map(
                                    (v) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      child: ListTile(
                                        selected: _tab == v.$3,
                                        selectedTileColor: const Color(
                                          0xFF075473,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        leading: Icon(
                                          v.$1,
                                          color: Colors.white,
                                        ),
                                        title: Text(
                                          v.$2,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        onTap: () => _go(v.$3),
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Text(
                                      'Discover. Prepare.\nPursue with confidence.',
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
                            padding: EdgeInsets.all(desktop ? 28 : 16),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1150,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Your next contract starts here.',
                                      style: TextStyle(
                                        fontSize: desktop ? 30 : 25,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Find relevant opportunities. Understand the requirements. Build a stronger response.',
                                      style: TextStyle(
                                        color: _muted,
                                        height: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    if (_error != null) ...[
                                      _card(
                                        Text(
                                          _error!,
                                          style: const TextStyle(
                                            color: Color(0xFF9A2929),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                    ],
                                    if (_notice != null) ...[
                                      _card(
                                        Text(
                                          _notice!,
                                          style: const TextStyle(color: _cyan),
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                    ],
                                    if (_profileDirty && _tab != 2) ...[
                                      _card(
                                        Row(
                                          children: [
                                            const Expanded(
                                              child: Text(
                                                'You have unsaved business profile changes.',
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () => _go(2),
                                              child: const Text('Save profile'),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                    ],
                                    if (_running || _busy) ...[
                                      _card(
                                        Row(
                                          children: [
                                            const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Text(
                                                _running
                                                    ? (_job?['kind'] ==
                                                              'discover'
                                                          ? 'Nova is searching official notices… You can return later; your request is saved.'
                                                          : 'Nova is preparing your bid review and draft… You can return later; your request is saved.')
                                                    : 'Saving your changes…',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                    ] else if (_job?['state'] == 'failed') ...[
                                      _card(Text(_s(_job?['error']))),
                                      const SizedBox(height: 14),
                                    ],
                                    if (_tab == 0)
                                      _discover()
                                    else if (_tab == 2)
                                      _profileForm()
                                    else if (_selected != null)
                                      _detail(_selected!)
                                    else
                                      _savedList(),
                                    const SizedBox(height: 28),
                                    const Text(
                                      'Private to your account. AI reviews are working guidance; buyer notices and amendments control the actual requirements.',
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

class _OpportunityEditor extends StatefulWidget {
  const _OpportunityEditor({this.current, this.initial});
  final Map<String, dynamic>? current;
  final Map<String, dynamic>? initial;
  @override
  State<_OpportunityEditor> createState() => _OpportunityEditorState();
}

class _OpportunityEditorState extends State<_OpportunityEditor> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  bool get editing => widget.current != null;
  @override
  void initState() {
    super.initState();
    final d = _map(widget.current?['data']);
    _fields = {
      for (final k in [
        'title',
        'agency',
        'location',
        'sourceUrl',
        'deadline',
        'noticeText',
        'notes',
      ])
        k: TextEditingController(
          text: _s(
            widget.initial?[k] ??
                (k == 'notes' ? (widget.current?['notes']) : d[k]),
          ),
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(editing ? 'RFP text & notes' : 'Paste an opportunity'),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!editing)
                ...['title', 'agency', 'location', 'sourceUrl', 'deadline'].map(
                  (k) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      key: Key('radar-import-$k'),
                      controller: _fields[k],
                      maxLength: k == 'sourceUrl' ? 2000 : 200,
                      decoration: InputDecoration(
                        labelText: switch (k) {
                          'title' => 'Opportunity title',
                          'agency' => 'Buyer / agency',
                          'location' => 'Location',
                          'sourceUrl' => 'Original notice link (HTTPS)',
                          'deadline' => 'Response deadline (YYYY-MM-DD)',
                          _ => k,
                        },
                      ),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (k == 'title' && value.isEmpty) {
                          return 'Add a title.';
                        }
                        if (k == 'sourceUrl' && value.isNotEmpty) {
                          final u = Uri.tryParse(value);
                          if (u == null ||
                              u.scheme != 'https' ||
                              !u.host.contains('.') ||
                              u.userInfo.isNotEmpty) {
                            return 'Use a public HTTPS source link.';
                          }
                        }
                        if (k == 'deadline' && value.isNotEmpty) {
                          final date = DateTime.tryParse(value);
                          if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
                              date == null ||
                              date.toIso8601String().substring(0, 10) !=
                                  value) {
                            return 'Use a valid date: YYYY-MM-DD.';
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                ),
              TextFormField(
                key: const Key('radar-notice-text'),
                controller: _fields['noticeText'],
                minLines: 7,
                maxLines: 14,
                maxLength: 18000,
                decoration: const InputDecoration(
                  labelText: 'RFP / solicitation text',
                  alignLabelWithHint: true,
                  hintText:
                      'Paste the scope, deliverables, qualifications and submission requirements. Include relevant amendments.',
                ),
                validator: (v) => !editing && (v ?? '').trim().isEmpty
                    ? 'Paste the opportunity text.'
                    : null,
              ),
              if (editing) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fields['notes'],
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    labelText: 'Your private notes',
                  ),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                'Pasting a link does not import its contents. Only the text you provide is reviewed. AI sharing is requested when you ask Nova.',
                style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('radar-save-rfp'),
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(context, {
            for (final e in _fields.entries)
              if ((editing && ['noticeText', 'notes'].contains(e.key)) ||
                  (!editing && e.key != 'notes'))
                e.key: e.value.text.trim(),
          });
        },
        child: const Text('Save opportunity'),
      ),
    ],
  );
}
