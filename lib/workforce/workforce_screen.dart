import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'workforce_client.dart';
import 'workforce_forms.dart';
import 'workforce_style.dart';
import 'workforce_automations.dart';

class WorkforceScreen extends StatefulWidget {
  const WorkforceScreen({super.key, required this.client});
  final WorkforceClient client;
  @override
  State<WorkforceScreen> createState() => _WorkforceScreenState();
}

class _WorkforceScreenState extends State<WorkforceScreen>
    with WidgetsBindingObserver {
  WfJson? _data;
  List<WfJson> _workspaces = [];
  String? _org, _error;
  bool _loading = true,
      _busy = false,
      _canCreate = false,
      _signedOut = false,
      _visible = true;
  int _generation = 0, _tab = 0, _dialogs = 0;
  Timer? _poll, _tick;
  DateTime? _receivedAt;
  DateTimeRange? _range;
  String _search = '', _filter = 'all';
  final _requests = <String, String>{};
  WfJson get _member => wfMap(_data?['member']);
  WfJson get _policy => wfMap(_data?['policy']);
  String get _uid => _member['user_id'] ?? '';
  bool get _admin => ['owner', 'manager'].contains(_member['role']);
  bool get _owner => _member['role'] == 'owner';
  List<WfJson> _rows(String k) => wfRows(_data?[k]);
  WfJson? get _active {
    for (final s in _rows('shifts')) {
      if (s['user_id'] == _uid && s['state'] != 'ended') return s;
    }
    return null;
  }

  Map<String, String>? get _query => _range == null
      ? null
      : {'from': _ymd(_range!.start), 'to': _ymd(_range!.end)};
  String _ymd(DateTime d) => d.toIso8601String().substring(0, 10);
  String _name(dynamic uid) =>
      _rows(
        'members',
      ).where((m) => m['user_id'] == uid).firstOrNull?['display_name'] ??
      'Team member';
  String _when(dynamic value) {
    final d = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (d == null) return '—';
    return '${d.month}/${d.day} · ${TimeOfDay.fromDateTime(d).format(context)}';
  }

  num _seconds(WfJson s) {
    final elapsed = _receivedAt == null
        ? 0
        : DateTime.now().difference(_receivedAt!).inSeconds.clamp(0, 864000);
    return (s['worked_seconds'] as num? ?? 0) +
        (s['state'] == 'working' ? elapsed : 0);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.onSignedOut = _onSignedOut;
    _loadWorkspaces();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_visible && !_busy && _dialogs == 0 && !_signedOut) {
        _refresh(quiet: true);
      }
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _visible && _active != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _generation++;
    _poll?.cancel();
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.client.onSignedOut = null;
    widget.client.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    if (_visible && !_signedOut && !_busy) _refresh(quiet: true);
  }

  void _onSignedOut() {
    if (!mounted) return;
    _generation++;
    setState(() {
      _signedOut = true;
      _data = null;
      _workspaces = [];
      _org = null;
      _loading = false;
      _error = 'Your session expired. Sign in again to view Workforce.';
    });
    final route = ModalRoute.of(context);
    Navigator.of(context).popUntil((r) => r == route);
  }

  Future<void> _loadWorkspaces() async {
    final g = ++_generation;
    if (mounted) setState(() => _loading = true);
    try {
      final result = await widget.client.request('GET', '/workspaces');
      if (!mounted || g != _generation || _signedOut) return;
      setState(() {
        _workspaces = wfRows(result['workspaces']);
        _canCreate = result['can_create'] == true;
        _error = null;
        _org = _workspaces.any((w) => w['id'] == _org)
            ? _org
            : _workspaces.firstOrNull?['id'];
        _loading = false;
      });
      if (_org != null) await _refresh();
    } catch (e) {
      if (mounted && g == _generation) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _refresh({bool quiet = false}) async {
    if (_org == null || _signedOut) return;
    final g = ++_generation, org = _org!;
    if (!quiet) setState(() => _loading = true);
    try {
      final result = await widget.client.request('GET', '/$org', query: _query);
      if (!mounted || g != _generation || org != _org || _signedOut) return;
      setState(() {
        _data = result;
        _receivedAt = DateTime.now();
        _loading = false;
        _error = null;
        if (!_admin && _tab == 0) _tab = 1;
      });
    } catch (e) {
      if (mounted && g == _generation) {
        setState(() {
          _loading = false;
          _error = e.toString();
          if (e is WorkforceException && e.status == 403) _data = null;
        });
      }
    }
  }

  void _toast(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> _action(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<WfJson> _command(String action, WfJson payload) async =>
      widget.client.request(
        'POST',
        '/$_org/commands',
        body: {'action': action, 'payload': payload},
      );
  Future<bool> _dialog(Widget child) async {
    _dialogs++;
    try {
      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => Theme(data: WfStyle.theme, child: child),
          ) ??
          false;
    } finally {
      _dialogs--;
    }
  }

  Future<void> _form(
    String title,
    String description,
    List<WfField> fields,
    Future<void> Function(WfJson) submit, {
    String button = 'Save',
    bool dictation = false,
  }) async {
    final saved = await _dialog(
      WorkforceForm(
        title: title,
        description: description,
        fields: fields,
        submit: submit,
        button: button,
        dictation: dictation,
      ),
    );
    if (saved) await _refresh(quiet: true);
  }

  Future<void> _create() async {
    await _form(
      'Create your workspace',
      'Your Enterprise plan covers this employer workspace and invited team members.',
      [
        const WfField('name', 'Company or team name'),
        const WfField('display_name', 'Your name'),
        const WfField(
          'timezone',
          'Workspace timezone (IANA)',
          value: 'America/New_York',
        ),
      ],
      (p) async {
        final result = await widget.client.request(
          'POST',
          '/workspaces',
          body: p,
        );
        _org = result['id'];
        await _loadWorkspaces();
      },
      button: 'Create workspace',
    );
  }

  Future<void> _join() async {
    await _form(
      'Join your employer',
      'Sign in with the verified email address your employer invited. Invitation codes expire after seven days.',
      [const WfField('token', 'Invitation code')],
      (p) async {
        final r = await widget.client.request(
          'POST',
          '/accept-invite',
          body: p,
        );
        _org = r['id'];
        await _loadWorkspaces();
      },
      button: 'Join workspace',
    );
  }

  Future<void> _invite() async {
    String? code;
    await _form(
      'Invite a team member',
      'Create an invitation for a verified email address. Share the code with this person; it can only be used once.',
      [
        const WfField('display_name', 'Full name'),
        const WfField('email', 'Email address'),
        const WfField(
          'role',
          'Access',
          value: 'employee',
          choices: {
            'employee': 'Employee — own workday',
            'manager': 'Manager — team and approvals',
          },
        ),
      ],
      (p) async {
        code = (await _command('invite', p))['invitation_code'];
      },
      button: 'Create invitation',
    );
    if (code != null && mounted) {
      await _showText(
        'Invitation ready',
        'Share this code with the employee. They can open Utility to Workforce to Join workspace.\n\n$code\n\nThis invitation has not been emailed automatically.',
      );
    }
  }

  Future<void> _punch(String action) async {
    final s = _active;
    final request = _requests.putIfAbsent(action, wfId);
    final version = s?['version'] ?? 1;
    Future<void> submit(WfJson evidence) async {
      await widget.client.request(
        'POST',
        '/$_org/punch',
        body: {
          ...evidence,
          'action': action,
          'request_id': request,
          'version': version,
          'client_time': DateTime.now().toUtc().toIso8601String(),
        },
      );
      _requests.remove(action);
    }

    if (action == 'clock_in' || action == 'clock_out') {
      final ok = await _dialog(
        WorkforcePunchDialog(
          clockOut: action == 'clock_out',
          policy: s == null ? _policy : wfMap(s['policy_snapshot']),
          submit: submit,
        ),
      );
      if (ok) {
        await _refresh(quiet: true);
        _toast(
          action == 'clock_in'
              ? 'You’re clocked in.'
              : 'Your clock-out is recorded.',
        );
      }
    } else {
      await _action(() async {
        await submit({});
        await _refresh(quiet: true);
      });
    }
  }

  Future<void> _update() async {
    final s =
        _active ??
        _rows('shifts').where((s) => s['user_id'] == _uid).firstOrNull;
    if (s == null) return;
    final unit = wfMap(s['policy_snapshot'])['output_unit'] ?? 'tasks',
        request = wfId();
    await _form(
      'Your work update',
      'Record what you completed since your last update. Only add new completed units; do not repeat the day’s total.',
      [
        const WfField('summary', 'What did you accomplish?', lines: 3),
        WfField('quantity', 'New $unit completed', type: 'int', value: 0),
        const WfField('project', 'Project or customer', required: false),
        const WfField(
          'blockers',
          'Blockers or support needed',
          lines: 2,
          required: false,
        ),
      ],
      (p) async {
        await _command('update', {
          ...p,
          'request_id': request,
          'shift_id': s['id'],
        });
      },
      button: 'Save work update',
      dictation: true,
    );
  }

  Future<void> _correction([WfJson? s]) async {
    String local(dynamic v, DateTime fallback) =>
        (DateTime.tryParse(v?.toString() ?? '') ?? fallback)
            .toLocal()
            .toIso8601String()
            .substring(0, 16);
    await _form(
      'Request a time correction',
      'Your manager reviews the request. Original attendance stamps remain in the audit history. Dates below use this device’s local time.',
      [
        WfField(
          'proposed_start',
          'Correct clock-in',
          type: 'datetime',
          value: local(
            s?['approved_start'] ?? s?['clock_in'],
            DateTime.now().subtract(const Duration(hours: 8)),
          ),
        ),
        WfField(
          'proposed_end',
          'Correct clock-out',
          type: 'datetime',
          value: local(s?['approved_end'] ?? s?['clock_out'], DateTime.now()),
        ),
        WfField(
          'break_minutes',
          'Total break minutes',
          type: 'int',
          value: ((s?['break_seconds'] as num? ?? 0) / 60).round(),
        ),
        const WfField('reason', 'Reason for correction', lines: 3),
      ],
      (p) async {
        await _command('correction', {...p, 'shift_id': s?['id']});
      },
      button: 'Submit for review',
    );
  }

  Future<void> _review(WfJson c) async {
    await _form(
      'Review ${_name(c['user_id'])}’s request',
      'Requested: ${_when(c['proposed_start'])} to ${_when(c['proposed_end'])}\nBreak: ${c['break_minutes']} minutes\nReason: ${c['reason']}',
      [
        const WfField(
          'decision',
          'Decision',
          value: 'approved',
          choices: {
            'approved': 'Approve correction',
            'rejected': 'Reject correction',
          },
        ),
        const WfField('review_note', 'Review note', lines: 3),
      ],
      (p) async {
        await _command('review_correction', {...p, 'id': c['id']});
      },
      button: 'Record decision',
    );
  }

  Future<void> _editMember(WfJson m) async {
    await _form(
      'Manage ${m['display_name']}',
      'Access changes take effect on the next request. Close an active shift before removing access.',
      [
        WfField(
          'role',
          'Role',
          value: m['role'],
          choices: const {'employee': 'Employee', 'manager': 'Manager'},
        ),
        WfField('team', 'Team', value: m['team'], required: false),
        WfField(
          'active',
          'Active workspace access',
          type: 'bool',
          value: m['active'],
        ),
      ],
      (p) async {
        await _command('member', {
          ...p,
          'user_id': m['user_id'],
          'version': m['version'],
          'policy_override': m['policy_override'],
        });
      },
    );
  }

  Future<void> _policyForm({WfJson? member}) async {
    final p = member == null
        ? wfMap(_data?['organization']['policy'])
        : wfMap(member['policy_override'] ?? _data?['organization']['policy']);
    await _form(
      member == null
          ? 'Workforce policies'
          : 'Policy for ${member['display_name']}',
      'Choose what your team records. Changes apply to the next shift. Current shifts retain their original settings.',
      [
        WfField(
          'require_selfie',
          'Require attendance photo at clock-in and clock-out',
          type: 'bool',
          value: p['require_selfie'],
        ),
        WfField(
          'require_location',
          'Require location at clock-in and clock-out',
          type: 'bool',
          value: p['require_location'],
        ),
        WfField(
          'hourly_updates',
          'Require regular work updates',
          type: 'bool',
          value: p['hourly_updates'],
        ),
        WfField(
          'interval_minutes',
          'Update interval (15–240 minutes)',
          type: 'int',
          value: p['interval_minutes'],
        ),
        WfField(
          'grace_minutes',
          'Reminder grace period (0–60 minutes)',
          type: 'int',
          value: p['grace_minutes'],
        ),
        WfField(
          'retention_days',
          'Photo and location retention (7–90 days)',
          type: 'int',
          value: p['retention_days'],
        ),
        WfField('worksite', 'Worksite name', value: p['worksite']),
        WfField(
          'latitude',
          'Worksite latitude (optional)',
          type: 'number',
          value: p['latitude'],
          required: false,
        ),
        WfField(
          'longitude',
          'Worksite longitude (optional)',
          type: 'number',
          value: p['longitude'],
          required: false,
        ),
        WfField(
          'radius_m',
          'Worksite radius (50–5000 metres)',
          type: 'int',
          value: p['radius_m'],
        ),
        WfField(
          'daily_goal',
          'Daily output goal',
          type: 'int',
          value: p['daily_goal'],
        ),
        WfField('output_unit', 'Output unit', value: p['output_unit']),
      ],
      (p) async {
        if (member == null) {
          await _command('policy', {
            'policy': p,
            'version': _data!['organization']['version'],
          });
        } else {
          await _command('member', {...member, 'policy_override': p});
        }
      },
    );
  }

  Future<void> _schedule() async {
    final people = {
      for (final m in _rows('members').where((m) => m['active'] == true))
        m['user_id'].toString(): m['display_name'].toString(),
    };
    if (people.isEmpty) return;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await _form(
      'Schedule a shift',
      'Assign a shift up to 24 hours. Dates below use this device’s local time; employees see them in their local time.',
      [
        WfField(
          'user_id',
          'Team member',
          value: people.keys.first,
          choices: people,
        ),
        WfField(
          'starts_at',
          'Starts',
          type: 'datetime',
          value: DateTime(
            tomorrow.year,
            tomorrow.month,
            tomorrow.day,
            9,
          ).toIso8601String().substring(0, 16),
        ),
        WfField(
          'ends_at',
          'Ends',
          type: 'datetime',
          value: DateTime(
            tomorrow.year,
            tomorrow.month,
            tomorrow.day,
            17,
          ).toIso8601String().substring(0, 16),
        ),
        WfField('worksite', 'Worksite', value: _policy['worksite']),
        const WfField('notes', 'Shift notes', lines: 2, required: false),
      ],
      (p) async {
        await _command('schedule', p);
      },
      button: 'Schedule shift',
    );
  }

  Future<void> _dateRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _range,
      helpText: 'REPORT DATES · MAXIMUM 31 DAYS',
    );
    if (r == null || !mounted) return;
    if (r.end.difference(r.start).inDays > 30) {
      _toast('Choose up to 31 days.');
      return;
    }
    setState(() => _range = r);
    await _refresh();
  }

  Future<void> _showText(String title, String text) async {
    await _dialog(
      Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                SelectableText(text, style: const TextStyle(height: 1.6)),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: text));
                        _toast('Copied.');
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                    ),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _brief() async => _action(() async {
    final r = await widget.client.request('GET', '/$_org/brief', query: _query);
    if (mounted) await _showText('Team brief', r['text']);
  });
  Future<void> _emailDraft() async {
    await _action(() async {
      final r = await widget.client.request('GET', '/$_org/email-recipients');
      final people = wfRows(r['recipients']);
      if (people.isEmpty) {
        _toast('Add an approved recipient in NOVA Email Center first.');
        return;
      }
      final brief = await widget.client.request(
        'GET',
        '/$_org/brief',
        query: _query,
      );
      if (!mounted) return;
      final req = wfId();
      await _form(
        'Prepare NOVA email',
        'Review the report below. This creates a draft in NOVA Email Center; it does not send it.\n\n${brief['text']}',
        [
          WfField(
            'recipient_id',
            'Approved recipient',
            value: people.first['id'],
            choices: {
              for (final p in people)
                p['id'].toString(): '${p['displayName'] ?? ''} · ${p['email']}',
            },
          ),
          const WfField(
            'confirmed',
            'I reviewed the report and recipient',
            type: 'bool',
            value: false,
          ),
        ],
        (p) async {
          await widget.client.request(
            'POST',
            '/$_org/email-draft',
            body: {...p, ...?_query, 'request_id': req},
          );
          _toast('Draft created in NOVA Email Center.');
        },
        button: 'Create email draft',
      );
    });
  }

  Future<void> _export() async => _action(() async {
    final bytes = await widget.client.bytes('/$_org/export', query: _query);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            mimeType: 'text/csv',
            name: 'korlix-timesheets.csv',
          ),
        ],
        fileNameOverrides: ['korlix-timesheets.csv'],
        sharePositionOrigin: const Rect.fromLTWH(20, 80, 100, 40),
      ),
    );
  });
  Future<void> _photo(WfJson e) async => _action(() async {
    final bytes = await widget.client.bytes('/$_org/photos/${e['id']}');
    if (!mounted) return;
    await _dialog(
      Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Attendance photo · ${_name(e['user_id'])}'),
              const SizedBox(height: 12),
              Flexible(child: Image.memory(bytes, fit: BoxFit.contain)),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  });

  Widget _card(
    Widget child, {
    EdgeInsets padding = const EdgeInsets.all(24),
    Color? border,
  }) => Material(
    color: WfStyle.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: border ?? WfStyle.line),
    ),
    child: Padding(padding: padding, child: child),
  );
  Widget _title(String title, String description, {Widget? trailing}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.7,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(color: WfStyle.muted, fontSize: 13),
                ),
              ],
            ),
            ?trailing,
          ],
        ),
      );
  Widget _empty(String title, String detail, IconData icon) => _card(
    Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(icon, size: 40, color: WfStyle.cyan),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: WfStyle.muted, height: 1.5),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _button(
    String label,
    IconData icon,
    VoidCallback? action, {
    bool primary = false,
  }) => primary
      ? FilledButton.icon(
          onPressed: _busy ? null : action,
          icon: Icon(icon, size: 18),
          label: Text(label),
        )
      : OutlinedButton.icon(
          onPressed: _busy ? null : action,
          icon: Icon(icon, size: 18),
          label: Text(label),
        );
  Widget _avatar(String name) => CircleAvatar(
    radius: 20,
    backgroundColor: WfStyle.cyan.withValues(alpha: .12),
    child: Text(
      name
          .split(' ')
          .where((e) => e.isNotEmpty)
          .take(2)
          .map((e) => e.characters.first)
          .join()
          .toUpperCase(),
      style: const TextStyle(
        color: WfStyle.cyan,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
  List<(String, IconData)> get _tabs => [
    ('Overview', Icons.space_dashboard_outlined),
    ('My day', Icons.fingerprint),
    ('Work log', Icons.task_alt),
    ('Timesheets', Icons.receipt_long_outlined),
    ('Schedule', Icons.calendar_month_outlined),
    ('Policies', Icons.tune),
    ('Automations', Icons.auto_awesome_outlined),
  ];
  Widget _nav(bool rail) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (rail) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 30, 20, 34),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/meeting_copilot/korlix_logo.jpeg',
                  width: 42,
                  height: 42,
                  errorBuilder: (_, e, s) =>
                      const Icon(Icons.hub_outlined, color: WfStyle.cyan),
                ),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'KORLIX',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    'WORKFORCE',
                    style: TextStyle(
                      color: WfStyle.muted,
                      fontSize: 9,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: Text(
            'WORKSPACE',
            style: TextStyle(
              color: WfStyle.muted,
              fontSize: 10,
              letterSpacing: 2,
            ),
          ),
        ),
      ],
      for (var i = 0; i < _tabs.length; i++)
        if ((_admin || i != 0) && (_admin || i != 5) && (_owner || i != 6))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Material(
              color: _tab == i
                  ? WfStyle.cyan.withValues(alpha: .1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                dense: true,
                leading: Icon(
                  _tabs[i].$2,
                  color: _tab == i ? WfStyle.cyan : WfStyle.muted,
                  size: 20,
                ),
                title: Text(
                  _tabs[i].$1,
                  style: TextStyle(
                    color: _tab == i ? WfStyle.cyan : WfStyle.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  setState(() => _tab = i);
                  if (!rail) Navigator.pop(context);
                },
              ),
            ),
          ),
    ],
  );
  @override
  Widget build(BuildContext context) => Theme(
    data: WfStyle.theme,
    child: Builder(
      builder: (context) => LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 1080;
          return Scaffold(
            appBar: wide
                ? null
                : AppBar(
                    title: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Image.asset(
                            'assets/meeting_copilot/korlix_logo.jpeg',
                            height: 30,
                            width: 30,
                          ),
                        ),
                        const SizedBox(width: 9),
                        const Expanded(
                          child: Text(
                            'KORLIX Workforce',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      IconButton(
                        onPressed: _loading ? null : _loadWorkspaces,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
            drawer: wide || _data == null
                ? null
                : Drawer(
                    backgroundColor: WfStyle.sidebar,
                    child: SafeArea(
                      child: Column(
                        children: [
                          Expanded(child: _nav(false)),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              Navigator.of(context).maybePop();
                            },
                            icon: const Icon(Icons.arrow_back, size: 16),
                            label: const Text('Back to KORLIX'),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
            body: SafeArea(
              child: Row(
                children: [
                  if (wide && _data != null)
                    Container(
                      width: 224,
                      decoration: const BoxDecoration(
                        color: WfStyle.sidebar,
                        border: Border(right: BorderSide(color: WfStyle.line)),
                      ),
                      child: Column(
                        children: [
                          _nav(true),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: _card(
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  WfBadge('ENTERPRISE'),
                                  SizedBox(height: 10),
                                  Text(
                                    'Time with purpose.',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'A clear view of your people, time and progress.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: WfStyle.muted,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(14),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(Icons.arrow_back, size: 16),
                            label: const Text('Back to KORLIX'),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        if (_loading || _busy)
                          const LinearProgressIndicator(minHeight: 2),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.all(c.maxWidth < 600 ? 16 : 32),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1440,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_data != null) _header(),
                                    if (_error != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 20,
                                        ),
                                        child: _card(
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.info_outline,
                                                color: WfStyle.gold,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  _error!,
                                                  style: const TextStyle(
                                                    color: WfStyle.gold,
                                                  ),
                                                ),
                                              ),
                                              TextButton(
                                                onPressed: _signedOut
                                                    ? () => Navigator.maybePop(
                                                        context,
                                                      )
                                                    : _loadWorkspaces,
                                                child: Text(
                                                  _signedOut ? 'Back' : 'Retry',
                                                ),
                                              ),
                                            ],
                                          ),
                                          border: WfStyle.gold.withValues(
                                            alpha: .4,
                                          ),
                                        ),
                                      ),
                                    if (_data == null &&
                                        !_loading &&
                                        !_signedOut)
                                      _welcome(),
                                    if (_data != null) ...[
                                      if (_data!['active_plan'] != true)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 18,
                                          ),
                                          child: _card(
                                            const Text(
                                              'The employer’s Enterprise plan is inactive. You can view history, request corrections and clock out. Ask the owner to renew access.',
                                              style: TextStyle(
                                                color: WfStyle.gold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      switch (_tab) {
                                        0 => _overview(),
                                        1 => _myDay(),
                                        2 => _workLog(),
                                        3 => _timesheets(),
                                        4 => _scheduleView(),
                                        6 =>
                                          _owner
                                              ? WorkforceAutomations(
                                                  key: ValueKey(_org),
                                                  client: widget.client,
                                                  orgId: _org!,
                                                  members: _rows('members'),
                                                  timezone:
                                                      _data!['organization']['timezone']
                                                          .toString(),
                                                )
                                              : _myDay(),
                                        _ => _policies(),
                                      },
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
  Widget _header() => LayoutBuilder(
    builder: (context, c) {
      if (c.maxWidth >= 600) return _wideHeader();
      return Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _org,
                    key: ValueKey(_org),
                    isExpanded: true,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      isDense: true,
                    ),
                    items: _workspaces
                        .map(
                          (w) => DropdownMenuItem<String>(
                            value: w['id'],
                            child: Text(
                              w['name'],
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _org = v;
                        _data = null;
                        _range = null;
                        _requests.clear();
                      });
                      _refresh();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                WfBadge(wfLabel(_member['role']), color: WfStyle.violet),
                PopupMenuButton<String>(
                  tooltip: 'Workspace options',
                  onSelected: (v) {
                    if (v == 'dates') _dateRange();
                    if (v == 'join') _join();
                    if (v == 'create') _create();
                    if (v == 'today') {
                      setState(() => _range = null);
                      _refresh();
                    }
                    if (v == 'correction') _correction();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'dates',
                      child: Text('Choose report dates'),
                    ),
                    const PopupMenuItem(
                      value: 'today',
                      child: Text('Show today'),
                    ),
                    const PopupMenuItem(
                      value: 'correction',
                      child: Text('Request a time correction'),
                    ),
                    const PopupMenuItem(
                      value: 'join',
                      child: Text('Join workspace'),
                    ),
                    if (_canCreate)
                      const PopupMenuItem(
                        value: 'create',
                        child: Text('Create workspace'),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${_data!['from']}${_data!['to'] == _data!['from'] ? '' : ' to ${_data!['to']}'} · ${_data!['organization']['timezone']}',
              style: const TextStyle(color: WfStyle.muted, fontSize: 11),
            ),
          ],
        ),
      );
    },
  );
  Widget _wideHeader() => Padding(
    padding: const EdgeInsets.only(bottom: 32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 310),
              child: DropdownButtonFormField<String>(
                initialValue: _org,
                key: ValueKey(_org),
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Workspace',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                items: _workspaces
                    .map(
                      (w) => DropdownMenuItem<String>(
                        value: w['id'],
                        child: Text(w['name'], overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _org = v;
                    _data = null;
                    _range = null;
                    _requests.clear();
                  });
                  _refresh();
                },
              ),
            ),
            WfBadge(wfLabel(_member['role']), color: WfStyle.violet),
            _button(
              _range == null
                  ? 'Today · ${_data!['from']}'
                  : '${_ymd(_range!.start)} to ${_ymd(_range!.end)}',
              Icons.date_range,
              _dateRange,
            ),
            if (_range != null)
              TextButton(
                onPressed: () {
                  setState(() => _range = null);
                  _refresh();
                },
                child: const Text('Today'),
              ),
            IconButton(
              onPressed: _loading ? null : () => _refresh(),
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh workspace',
            ),
            PopupMenuButton<String>(
              tooltip: 'Workspace options',
              onSelected: (v) {
                if (v == 'join') _join();
                if (v == 'create') _create();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'join',
                  child: Text('Join another workspace'),
                ),
                if (_canCreate)
                  const PopupMenuItem(
                    value: 'create',
                    child: Text('Create workspace'),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Report dates: ${_data!['organization']['timezone']}  ·  Individual timestamps: device local time${_receivedAt == null ? '' : '  ·  Synced ${TimeOfDay.fromDateTime(_receivedAt!).format(context)}'}',
          style: const TextStyle(color: WfStyle.muted, fontSize: 11),
        ),
      ],
    ),
  );
  Widget _welcome() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.asset(
            'assets/meeting_copilot/korlix_logo.jpeg',
            height: 76,
            width: 76,
          ),
        ),
        const SizedBox(height: 24),
        const WfBadge('KORLIX ENTERPRISE'),
        const SizedBox(height: 20),
        const Text(
          'Every workday.\nClearly connected.',
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Bring attendance, daily progress and team accountability into one shared workspace.',
          style: TextStyle(color: WfStyle.muted, fontSize: 16, height: 1.6),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (_canCreate)
              _button(
                'Create employer workspace',
                Icons.add,
                _create,
                primary: true,
              ),
            _button(
              'Join your employer',
              Icons.group_add_outlined,
              _join,
              primary: !_canCreate,
            ),
          ],
        ),
        if (!_canCreate)
          const Padding(
            padding: EdgeInsets.only(top: 18),
            child: Text(
              'Employers need Enterprise. Invited employees can join using their existing KORLIX account.',
              style: TextStyle(color: WfStyle.muted),
            ),
          ),
        const SizedBox(height: 28),
        const Wrap(
          spacing: 20,
          runSpacing: 16,
          children: [
            WfBadge('Clock in & out'),
            WfBadge('Optional attendance evidence'),
            WfBadge('Hourly work updates'),
            WfBadge('Manager approvals'),
          ],
        ),
      ],
    ),
  );
  Widget _metrics() {
    final m = wfMap(_data!['metrics']);
    final output = wfMap(
      m['output'],
    ).entries.map((e) => '${e.value} ${e.key}').join(' · ');
    final items = [
      ('Working now', '${m['working']}', Icons.groups_2_outlined, WfStyle.cyan),
      ('On a break', '${m['on_break']}', Icons.coffee_outlined, WfStyle.violet),
      (
        'Reported output',
        output.isEmpty ? '0' : output,
        Icons.trending_up,
        WfStyle.cyan,
      ),
      (
        'Updates overdue',
        '${m['updates_due']}',
        Icons.pending_actions,
        WfStyle.gold,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900
            ? 4
            : c.maxWidth >= 450
            ? 2
            : 1;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: items
              .map(
                (e) => SizedBox(
                  width: (c.maxWidth - 14 * (cols - 1)) / cols,
                  child: _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(e.$3, color: e.$4, size: 20),
                            const Spacer(),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: e.$4,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Text(
                          e.$2,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          e.$1,
                          style: const TextStyle(
                            color: WfStyle.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _overview() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(
        'Your team, in rhythm.',
        'Attendance and progress at a glance.',
        trailing: _owner
            ? _button('Invite employee', Icons.add, _invite, primary: true)
            : null,
      ),
      _metrics(),
      const SizedBox(height: 24),
      LayoutBuilder(
        builder: (context, c) {
          final main = _team();
          final side = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _novaCard(),
              const SizedBox(height: 18),
              _policySummary(),
            ],
          );
          if (c.maxWidth < 1000) {
            return Column(children: [main, const SizedBox(height: 20), side]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: main),
              const SizedBox(width: 20),
              Expanded(flex: 3, child: side),
            ],
          );
        },
      ),
    ],
  );
  Widget _team() {
    final members = _rows('members').where((m) {
      final active = _rows('shifts')
          .where((s) => s['user_id'] == m['user_id'] && s['state'] != 'ended')
          .firstOrNull;
      return ('${m['display_name']} ${m['email']} ${m['team']}')
              .toLowerCase()
              .contains(_search.toLowerCase()) &&
          (_filter == 'all' ||
              _filter == 'inactive' && m['active'] != true ||
              _filter == (active?['state'] ?? 'off')) &&
          (_filter == 'inactive' || m['active'] == true);
    }).toList();
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Team activity',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
              ),
              WfBadge(
                '${_rows('members').where((m) => m['active'] == true).length} people',
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: const InputDecoration(
              hintText: 'Search name, email or team',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                const {
                      'all': 'Everyone',
                      'working': 'Working',
                      'break': 'On break',
                      'off': 'Off shift',
                      'inactive': 'Inactive',
                    }.entries
                    .map(
                      (e) => ChoiceChip(
                        label: Text(e.value),
                        selected: _filter == e.key,
                        onSelected: (_) => setState(() => _filter = e.key),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 18),
          if (members.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No team members match these filters.',
                style: TextStyle(color: WfStyle.muted),
              ),
            ),
          for (final m in members) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: _teamRow(m),
            ),
          ],
        ],
      ),
    );
  }

  Widget _teamRow(WfJson m) {
    final shifts = _rows(
          'shifts',
        ).where((s) => s['user_id'] == m['user_id']).toList(),
        active = shifts.where((s) => s['state'] != 'ended').firstOrNull;
    final last = _rows(
      'updates',
    ).where((u) => u['user_id'] == m['user_id']).firstOrNull;
    final status = m['active'] != true
        ? 'Inactive'
        : active == null
        ? 'Off shift'
        : active['state'] == 'break'
        ? 'On break'
        : 'Working';
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _avatar(m['display_name']),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m['display_name'],
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    m['team'] == '' ? wfLabel(m['role']) : m['team'],
                    style: const TextStyle(color: WfStyle.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (_owner && m['role'] != 'owner')
              PopupMenuButton<String>(
                tooltip: 'Manage employee',
                onSelected: (v) =>
                    v == 'access' ? _editMember(m) : _policyForm(member: m),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'access',
                    child: Text('Role and access'),
                  ),
                  const PopupMenuItem(
                    value: 'policy',
                    child: Text('Individual policy'),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            WfBadge(
              status,
              color: active?['state'] == 'working'
                  ? WfStyle.cyan
                  : WfStyle.violet,
            ),
            Text(
              '${(_rows('report_shifts').where((s) => s['user_id'] == m['user_id']).fold<num>(0, (n, s) => n + _seconds(s)) / 3600).toStringAsFixed(1)} shift hours',
              style: const TextStyle(fontSize: 12, color: WfStyle.muted),
            ),
            if (active?['update_due'] == true)
              const WfBadge('Update overdue', color: WfStyle.gold),
          ],
        ),
        if (last != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              last['summary'],
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: WfStyle.muted,
                height: 1.4,
              ),
            ),
          ),
      ],
    );
    return info;
  }

  Widget _novaCard() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.auto_awesome, color: WfStyle.violet, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'NOVA team brief',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'Turn recorded hours, work updates and blockers into a clear team report.',
          style: TextStyle(color: WfStyle.muted, height: 1.5, fontSize: 13),
        ),
        const SizedBox(height: 18),
        _button('View team brief', Icons.notes, _brief, primary: true),
        if (_owner) ...[
          const SizedBox(height: 10),
          _button('Prepare email draft', Icons.mail_outline, _emailDraft),
        ],
        const SizedBox(height: 16),
        const Text(
          'Email drafts open in NOVA Email Center for review. Automated outbound calls are not enabled in this release.',
          style: TextStyle(color: WfStyle.muted, height: 1.5, fontSize: 11),
        ),
      ],
    ),
    border: WfStyle.violet.withValues(alpha: .35),
  );
  Widget _policySummary() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Attendance policy',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        for (final item in [
          ('require_selfie', 'Attendance photo', Icons.camera_alt_outlined),
          ('require_location', 'Location stamp', Icons.location_on_outlined),
          ('hourly_updates', 'Work updates', Icons.fact_check_outlined),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Icon(item.$3, size: 18, color: WfStyle.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(item.$2, style: const TextStyle(fontSize: 12)),
                ),
                WfBadge(
                  _data!['organization']['policy'][item.$1] == true
                      ? 'Required'
                      : 'Optional',
                  color: _data!['organization']['policy'][item.$1] == true
                      ? WfStyle.cyan
                      : WfStyle.muted,
                ),
              ],
            ),
          ),
        if (_admin)
          TextButton(
            onPressed: () => _policyForm(),
            child: const Text('Manage policies'),
          ),
      ],
    ),
  );
  Widget _myDay() {
    final active = _active,
        own = _rows('shifts').where((s) => s['user_id'] == _uid).toList(),
        pol = active == null ? _policy : wfMap(active['policy_snapshot']);
    final unit = pol['output_unit'] ?? 'tasks';
    final quantity = _rows('period_updates')
        .where((u) => u['user_id'] == _uid && u['output_unit'] == unit)
        .fold<num>(0, (n, u) => n + (u['quantity'] as num));
    final goal = (pol['daily_goal'] as num? ?? 10);
    final workCard = _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              WfBadge(
                active == null
                    ? 'Off shift'
                    : active['state'] == 'break'
                    ? 'On a break'
                    : 'Clocked in',
                color: active?['state'] == 'break'
                    ? WfStyle.violet
                    : WfStyle.cyan,
              ),
              Text(
                pol['worksite'] ?? 'Worksite',
                style: const TextStyle(color: WfStyle.muted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 30),
          const Text(
            'YOUR CURRENT SHIFT',
            style: TextStyle(
              fontSize: 11,
              color: WfStyle.muted,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              wfDuration(active == null ? 0 : _seconds(active)),
              style: const TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.w300,
                letterSpacing: -1.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            active == null
                ? 'Ready when your workday begins.'
                : 'Started ${_when(active['clock_in'])} · Breaks ${(active['break_seconds'] as num? ?? 0) ~/ 60} min',
            style: const TextStyle(color: WfStyle.muted, fontSize: 12),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (active == null)
                _button(
                  'Clock in',
                  Icons.login,
                  _data!['active_plan'] == true
                      ? () => _punch('clock_in')
                      : null,
                  primary: true,
                ),
              if (active != null) ...[
                _button(
                  active['state'] == 'break' ? 'Resume work' : 'Start break',
                  active['state'] == 'break'
                      ? Icons.play_arrow
                      : Icons.coffee_outlined,
                  _data!['active_plan'] == true
                      ? () => _punch(
                          active['state'] == 'break'
                              ? 'end_break'
                              : 'start_break',
                        )
                      : null,
                ),
                _button(
                  'Clock out',
                  Icons.logout,
                  () => _punch('clock_out'),
                  primary: true,
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Time is confirmed by the server. Breaks are excluded from working time.',
            style: TextStyle(color: WfStyle.muted, fontSize: 11),
          ),
        ],
      ),
      border: active != null ? WfStyle.cyan.withValues(alpha: .4) : null,
    );
    final progress = _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Progress you can see',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          Text(
            '$quantity / $goal',
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
          ),
          Text(
            '$unit reported · selected dates',
            style: const TextStyle(color: WfStyle.muted, fontSize: 12),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (quantity / goal).clamp(0, 1).toDouble(),
              minHeight: 8,
              backgroundColor: WfStyle.raised,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Daily goal: $goal $unit. Report completed work in your updates.',
            style: const TextStyle(
              color: WfStyle.muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          _button(
            'Add work update',
            Icons.add_task,
            own.isNotEmpty && _data!['active_plan'] == true ? _update : null,
            primary: true,
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          'Make today count.',
          'Welcome, ${_member['display_name'] ?? 'team member'}.',
          trailing: MediaQuery.sizeOf(context).width < 600
              ? null
              : _button(
                  'Request correction',
                  Icons.edit_calendar_outlined,
                  () => _correction(),
                ),
        ),
        if (active != null &&
            pol['hourly_updates'] == true &&
            active['state'] == 'break')
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Your update reminder is paused while you’re on a break.',
              style: TextStyle(color: WfStyle.violet),
            ),
          ),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth < 850
              ? Column(
                  children: [workCard, const SizedBox(height: 20), progress],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: workCard),
                    const SizedBox(width: 20),
                    Expanded(flex: 4, child: progress),
                  ],
                ),
        ),
        if (active?['update_due'] == true)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _card(
              Row(
                children: [
                  const Icon(Icons.pending_actions, color: WfStyle.gold),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Your work update is due. Share what you completed and any blockers.',
                    ),
                  ),
                  TextButton(
                    onPressed: _update,
                    child: const Text('Add update'),
                  ),
                ],
              ),
              border: WfStyle.gold,
            ),
          ),
        const SizedBox(height: 24),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your workday timeline',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (_rows('events').where((e) => e['user_id'] == _uid).isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Your attendance events will appear here.',
                    style: TextStyle(color: WfStyle.muted),
                  ),
                ),
              for (final e in _rows(
                'events',
              ).where((e) => e['user_id'] == _uid).take(20))
                _eventRow(e),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'What is captured?',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                'Photo: ${pol['require_selfie'] == true ? 'required' : 'not required'} · Location: ${pol['require_location'] == true ? 'required' : 'not required'} · Work updates: ${pol['hourly_updates'] == true ? 'every ${pol['interval_minutes']} working minutes' : 'optional'}',
                style: const TextStyle(color: WfStyle.muted, height: 1.5),
              ),
              const SizedBox(height: 8),
              Text(
                'Attendance evidence is available to you and workspace managers for ${pol['retention_days']} days. You can request a correction if something is wrong.',
                style: const TextStyle(
                  color: WfStyle.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _eventRow(WfJson e) {
    final loc = wfMap(e['location']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: WfStyle.raised,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              e['action'] == 'clock_out'
                  ? Icons.logout
                  : e['action'] == 'clock_in'
                  ? Icons.login
                  : Icons.coffee_outlined,
              size: 18,
              color: WfStyle.cyan,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wfLabel(e['action']),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  _when(e['recorded_at']),
                  style: const TextStyle(color: WfStyle.muted, fontSize: 12),
                ),
                if ((e['flags'] as List? ?? []).isNotEmpty)
                  Text(
                    (e['flags'] as List).join(' · '),
                    style: const TextStyle(color: WfStyle.gold, fontSize: 11),
                  ),
                if (e['exception_reason']?.toString().isNotEmpty == true)
                  Text(
                    e['exception_reason'],
                    style: const TextStyle(color: WfStyle.muted, fontSize: 12),
                  ),
                if (loc.isNotEmpty)
                  Text(
                    '${loc['latitude']}, ${loc['longitude']} · ±${(loc['accuracy'] as num? ?? 0).round()} m',
                    style: const TextStyle(color: WfStyle.muted, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (e['has_photo'] == true)
            IconButton(
              onPressed: () => _photo(e),
              icon: const Icon(Icons.photo_outlined, size: 20),
              tooltip: 'View attendance photo',
            ),
        ],
      ),
    );
  }

  Widget _workLog() {
    final rows = _rows('period_updates');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          'Work that moves forward.',
          'Completed work, blockers and project progress.',
          trailing: _active != null
              ? _button('Add update', Icons.add, _update, primary: true)
              : null,
        ),
        if (rows.isEmpty)
          _empty(
            'A clear record of progress',
            'Work updates will appear here as your team submits them.',
            Icons.task_alt,
          ),
        for (final u in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _avatar(_name(u['user_id'])),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _name(u['user_id']),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _when(u['created_at']),
                              style: const TextStyle(
                                color: WfStyle.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      WfBadge('+${u['quantity']} ${u['output_unit']}'),
                      if (u['project'] != '')
                        WfBadge(u['project'], color: WfStyle.violet),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    u['summary'],
                    style: const TextStyle(height: 1.6),
                  ),
                  if (u['blockers'] != '')
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        'Support needed: ${u['blockers']}',
                        style: const TextStyle(
                          color: WfStyle.gold,
                          height: 1.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Work quantities are employee-reported. They are not an automatic performance rating.',
            style: TextStyle(color: WfStyle.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _timesheets() {
    final shifts = _rows('report_shifts'), corrections = _rows('corrections');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          'Time, with a clear history.',
          'Full shifts overlapping the selected report dates.',
          trailing: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _button('Export CSV', Icons.download_outlined, _export),
              _button(
                'Missing punch',
                Icons.edit_calendar,
                () => _correction(),
              ),
            ],
          ),
        ),
        if (corrections.isNotEmpty) ...[
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Correction requests',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                for (final c in corrections)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _name(c['user_id']),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            WfBadge(
                              wfLabel(c['status']),
                              color: c['status'] == 'pending'
                                  ? WfStyle.gold
                                  : WfStyle.cyan,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_when(c['proposed_start'])} to ${_when(c['proposed_end'])} · ${c['break_minutes']} min break',
                          style: const TextStyle(
                            color: WfStyle.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(c['reason'], style: const TextStyle(fontSize: 13)),
                        if (c['review_note'] != null)
                          Text(
                            'Review: ${c['review_note']}',
                            style: const TextStyle(
                              color: WfStyle.muted,
                              fontSize: 12,
                            ),
                          ),
                        if (_admin &&
                            c['status'] == 'pending' &&
                            c['user_id'] != _uid)
                          TextButton(
                            onPressed: () => _review(c),
                            child: const Text('Review correction'),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (shifts.isEmpty)
          _empty(
            'No shifts for these dates',
            'Choose another date range or begin a new workday.',
            Icons.receipt_long,
          ),
        for (final s in shifts)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _name(s['user_id']),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      WfBadge(
                        wfLabel(s['review_status']),
                        color: s['review_status'] == 'needs_review'
                            ? WfStyle.gold
                            : WfStyle.cyan,
                      ),
                      if (s['approved_start'] != null)
                        const WfBadge('Corrected', color: WfStyle.violet),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 32,
                    runSpacing: 16,
                    children: [
                      _detail(
                        'CLOCK IN',
                        _when(s['approved_start'] ?? s['clock_in']),
                      ),
                      _detail(
                        'CLOCK OUT',
                        s['clock_out'] == null
                            ? wfLabel(s['state'])
                            : _when(s['approved_end'] ?? s['clock_out']),
                      ),
                      _detail('WORKED', wfDuration(_seconds(s))),
                      _detail(
                        'BREAK',
                        '${(s['break_seconds'] as num? ?? 0) ~/ 60} min',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      if (s['user_id'] == _uid)
                        _button(
                          'Request correction',
                          Icons.edit_outlined,
                          () => _correction(s),
                        ),
                      if (_admin &&
                          s['user_id'] != _uid &&
                          s['state'] == 'ended' &&
                          s['review_status'] != 'approved')
                        _button(
                          'Approve timesheet',
                          Icons.check_circle_outline,
                          () => _action(() async {
                            await _command('approve_shift', {
                              'id': s['id'],
                              'version': s['version'],
                            });
                            await _refresh(quiet: true);
                          }),
                        ),
                    ],
                  ),
                  if (_rows('events').any((e) => e['shift_id'] == s['id']))
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        'Attendance evidence',
                        style: TextStyle(fontSize: 13),
                      ),
                      children: _rows('events')
                          .where((e) => e['shift_id'] == s['id'])
                          .map(_eventRow)
                          .toList(),
                    ),
                ],
              ),
            ),
          ),
        const Text(
          'Exports include full overlapping shifts and approval status. Review corrections and payroll rules before payroll processing.',
          style: TextStyle(color: WfStyle.muted, fontSize: 12, height: 1.5),
        ),
      ],
    );
  }

  Widget _detail(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: WfStyle.muted,
          fontSize: 10,
          letterSpacing: 1.2,
        ),
      ),
      const SizedBox(height: 7),
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ],
  );
  Widget _scheduleView() {
    final shifts = _rows('schedule');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          'A plan for every shift.',
          'Selected dates and the following seven days.',
          trailing: _admin
              ? _button('Schedule shift', Icons.add, _schedule, primary: true)
              : null,
        ),
        if (shifts.isEmpty)
          _empty(
            'Your schedule starts here',
            'Assigned shifts appear here with their worksite and notes.',
            Icons.calendar_month,
          ),
        for (final s in shifts)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _avatar(_name(s['user_id'])),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _name(s['user_id']),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (_admin)
                        IconButton(
                          tooltip: 'Cancel scheduled shift',
                          onPressed: () => _form(
                            'Cancel this scheduled shift?',
                            '${_name(s['user_id'])} · ${_when(s['starts_at'])}\nThis removes the planned shift. Attendance records remain available.',
                            [],
                            (p) async {
                              await _command('cancel_schedule', {
                                'id': s['id'],
                                'version': s['version'],
                              });
                            },
                            button: 'Cancel scheduled shift',
                          ),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${_when(s['starts_at'])} to ${_when(s['ends_at'])}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  WfBadge(s['worksite'], color: WfStyle.violet),
                  if (s['notes'] != '')
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        s['notes'],
                        style: const TextStyle(
                          color: WfStyle.muted,
                          height: 1.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _policies() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(
        'The right rules for your team.',
        'Capture requirements, work updates and access.',
        trailing: _button(
          'Edit policy',
          Icons.tune,
          () => _policyForm(),
          primary: true,
        ),
      ),
      _policySummary(),
      const SizedBox(height: 20),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Thoughtful defaults',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Text(
              'Work updates: ${_data!['organization']['policy']['interval_minutes']} working minutes, with ${_data!['organization']['policy']['grace_minutes']} minutes of grace.\nEvidence retention: ${_data!['organization']['policy']['retention_days']} days.\nWorksite: ${_data!['organization']['policy']['worksite']}.\nDaily goal: ${_data!['organization']['policy']['daily_goal']} ${_data!['organization']['policy']['output_unit']}.',
              style: const TextStyle(height: 1.9, color: WfStyle.muted),
            ),
            const SizedBox(height: 14),
            const Text(
              'Breaks pause update reminders. Missing evidence and off-site stamps are flagged for review. Employees can always record clock-out and request time corrections.',
              style: TextStyle(height: 1.6, fontSize: 13),
            ),
            const SizedBox(height: 14),
            const Text(
              'Owners can give individual employees a different policy from their Team activity menu.',
              style: TextStyle(color: WfStyle.muted, fontSize: 12),
            ),
          ],
        ),
      ),
      if (_owner) ...[
        const SizedBox(height: 20),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Pending invitations',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _invite,
                    icon: const Icon(Icons.add),
                    label: const Text('Invite'),
                  ),
                ],
              ),
              if (_rows('invites').isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No pending invitations.',
                    style: TextStyle(color: WfStyle.muted),
                  ),
                ),
              for (final i in _rows('invites'))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(i['display_name']),
                  subtitle: Text(
                    '${i['email']} · ${wfLabel(i['role'])}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: TextButton(
                    onPressed: () => _action(() async {
                      await _command('revoke_invite', {'id': i['id']});
                      await _refresh(quiet: true);
                    }),
                    child: const Text('Revoke'),
                  ),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 20),
      _button(
        'View audit history',
        Icons.history,
        () => _action(() async {
          final r = await widget.client.request('GET', '/$_org/audit');
          if (mounted) {
            await _showText(
              'Workspace audit history',
              wfRows(r['entries'])
                  .map(
                    (e) =>
                        '${_when(e['recorded_at'])} · ${wfLabel(e['action'])} · ${_name(e['actor_id'])}',
                  )
                  .join('\n'),
            );
          }
        }),
      ),
    ],
  );
}
