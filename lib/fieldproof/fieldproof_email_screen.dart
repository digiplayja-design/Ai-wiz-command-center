import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../sounds/korlix_sound_actions.dart';
import '../sounds/korlix_sound_service.dart';
import 'fieldproof_client.dart';
import 'fieldproof_email.dart';
import 'fieldproof_saver.dart';

const _mailTeal = Color(0xFF087D91),
    _mailPurple = Color(0xFF7048B8),
    _mailAmber = Color(0xFF986000);

class FieldProofEmailScreen extends StatefulWidget {
  const FieldProofEmailScreen({
    super.key,
    required this.client,
    this.ownsClient = false,
    this.jobId,
    this.jobTitle,
    this.jobCompleted = false,
    this.saveFile,
  });
  final FieldProofEmailClient client;
  final bool ownsClient, jobCompleted;
  final String? jobId, jobTitle;
  final Future<void> Function(Uint8List bytes, String name, String mime)?
  saveFile;
  @override
  State<FieldProofEmailScreen> createState() => _FieldProofEmailScreenState();
}

class _FieldProofEmailScreenState extends State<FieldProofEmailScreen> {
  final _scroll = ScrollController();
  final _business = TextEditingController(),
      _supervisors = TextEditingController(),
      _timezone = TextEditingController(),
      _time = TextEditingController(),
      _limit = TextEditingController(),
      _delay = TextEditingController(),
      _customer = TextEditingController();
  Map<String, dynamic> _settings = fieldProofEmailDefaults(),
      _capabilities = {},
      _jobSettings = {},
      _savedJobSettings = {};
  List<Map<String, dynamic>> _deliveries = [];
  bool _loading = true,
      _busy = false,
      _locked = false,
      _needsRefresh = false,
      _activity = false,
      _dialogOpen = false;
  String? _error, _notice, _prepareKey;
  String _queueNotice = '';
  Map<String, dynamic> _savedSettings = {};
  bool get _isJob => widget.jobId != null;
  bool get _disabled => _loading || _busy || _locked || _needsRefresh;
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_lock);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.client.removeAccessDeniedListener(_lock);
    if (widget.ownsClient) widget.client.dispose();
    for (final c in [
      _business,
      _supervisors,
      _timezone,
      _time,
      _limit,
      _delay,
      _customer,
    ]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _lock() {
    if (!mounted) return;
    if (_dialogOpen) Navigator.of(context).pop(false);
    for (final c in [
      _business,
      _supervisors,
      _timezone,
      _time,
      _limit,
      _delay,
      _customer,
    ]) {
      c.clear();
    }
    setState(() {
      _locked = true;
      _settings = {};
      _savedSettings = {};
      _jobSettings = {};
      _savedJobSettings = {};
      _prepareKey = null;
      _queueNotice = '';
      _capabilities = {};
      _deliveries = [];
      _notice = null;
      _error = null;
    });
  }

  void _accept(Map<String, dynamic> state) {
    _deliveries = fpEmailRows(state['deliveries']);
    if (_isJob) {
      _jobSettings = fpEmailMap(state['job_settings']);
      _savedJobSettings = Map.of(_jobSettings);
      _customer.text = fpEmailText(_jobSettings['customer_email']);
    } else {
      _settings = {
        ...fieldProofEmailDefaults(),
        ...fpEmailMap(state['settings']),
      };
      _savedSettings = Map.of(_settings);
      _queueNotice = fpEmailText(state['queue_notice']);
      _capabilities = fpEmailMap(state['capabilities']);
      _business.text = fpEmailText(_settings['business_name']);
      _supervisors.text = (_settings['supervisor_emails'] as List? ?? []).join(
        '\n',
      );
      _timezone.text = fpEmailText(_settings['timezone']);
      _time.text = fpEmailText(_settings['summary_time']);
      _limit.text = fpEmailText(_settings['daily_limit']);
      _delay.text = fpEmailText(_settings['followup_days']);
    }
    _needsRefresh = false;
    _loading = false;
    _error = null;
  }

  void _showFeedbackAtTop() {
    if (!mounted || _locked) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_locked && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<void> _load() async {
    if (_busy || _locked) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final state = _isJob
          ? await widget.client.job(widget.jobId!)
          : await widget.client.load();
      if (!mounted || _locked) return;
      if (_isJob) {
        final global = await widget.client.load();
        if (!mounted || _locked) return;
        _settings = {
          ...fieldProofEmailDefaults(),
          ...fpEmailMap(global['settings']),
        };
        _capabilities = fpEmailMap(global['capabilities']);
        _queueNotice = fpEmailText(global['queue_notice']);
      }
      setState(() => _accept(state));
    } catch (e) {
      if (mounted && !_locked) {
        setState(() {
          _error = '$e';
          _needsRefresh = true;
          _loading = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String text, String action) async {
    _dialogOpen = true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    return result == true && mounted && !_locked;
  }

  Map<String, dynamic> _draft() => {
    ..._settings,
    'business_name': _business.text.trim(),
    'supervisor_emails': fieldProofSupervisorEmails(_supervisors.text),
    'timezone': _timezone.text.trim(),
    'summary_time': _time.text.trim(),
    'daily_limit': int.tryParse(_limit.text),
    'followup_days': int.tryParse(_delay.text),
  }..remove('version');
  Future<void> _save() async {
    if (_disabled) return;
    final draft = _draft();
    final validation = validateFieldProofEmailSettings(draft);
    if (validation != null) {
      setState(() {
        _error = validation;
        _notice = null;
      });
      _showFeedbackAtTop();
      return;
    }
    final automatic = [
      'customer_mode',
      'followup_mode',
      'supervisor_mode',
    ].any((key) => draft[key] == 'automatic');
    if (automatic && draft['paused'] != true) {
      final activatesAutomatic =
          ['customer_mode', 'followup_mode', 'supervisor_mode'].any(
            (key) =>
                draft[key] == 'automatic' && _savedSettings[key] != 'automatic',
          );
      final resumesAutomatic = _savedSettings['paused'] == true;
      final changesRecipients =
          draft['supervisor_mode'] == 'automatic' &&
          '${draft['supervisor_emails']}' !=
              '${_savedSettings['supervisor_emails']}';
      final addsPhotos =
          draft['customer_mode'] == 'automatic' &&
          draft['include_photos'] == true &&
          _savedSettings['include_photos'] != true;
      if ((activatesAutomatic ||
              resumesAutomatic ||
              changesRecipients ||
              addsPhotos) &&
          !await _confirm(
            'Confirm automatic email',
            'Customer reports: ${fieldProofEmailModes[draft['customer_mode']]}\n'
                'Customer follow-up: ${fieldProofEmailModes[draft['followup_mode']]} after ${draft['followup_days']} days\n'
                'Supervisor summaries: ${fieldProofEmailModes[draft['supervisor_mode']]}\n'
                'Supervisors: ${(draft['supervisor_emails'] as List).isEmpty ? 'None' : (draft['supervisor_emails'] as List).join(', ')}\n'
                'Schedule: ${_dayNames(draft['summary_days'])}, ${draft['summary_time']} (${draft['timezone']})\n'
                'Daily limit: ${draft['daily_limit']} emails\n'
                'Photos in customer PDF: ${draft['include_photos'] == true ? 'Yes' : 'No'}\n\n'
                'Automatic emails can be sent without another review. Customer emails require an enabled recipient on each job. These settings apply to future closeouts and summaries.',
            'Save and activate',
          )) {
        return;
      }
    }
    if (!mounted || _locked) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await widget.client.saveSettings(
        (_settings['version'] as int?) ?? 0,
        draft,
      );
      if (!mounted || _locked) return;
      setState(() {
        _accept(result);
        _notice = _settings['paused'] == true
            ? 'Automation is paused. Your settings are saved.'
            : 'Email settings saved.';
      });
      unawaited(kKorlixSounds.play(KorlixSound.success));
    } catch (e) {
      if (mounted && !_locked) {
        setState(() {
          _error = '$e';
          _needsRefresh = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _showFeedbackAtTop();
      }
    }
  }

  Future<void> _saveJob() async {
    if (_disabled) return;
    final email = _customer.text.trim().toLowerCase();
    final enabled = _jobSettings['enabled'] == true;
    if ((email.isNotEmpty && !fieldProofEmailAddressValid(email)) ||
        (enabled && email.isEmpty)) {
      setState(
        () => _error =
            'Enter a valid customer email address before enabling this job.',
      );
      _showFeedbackAtTop();
      return;
    }
    final changesRecipient =
        _savedJobSettings['enabled'] != true ||
        email != fpEmailText(_savedJobSettings['customer_email']);
    if (enabled &&
        changesRecipient &&
        _settings['paused'] != true &&
        (_settings['customer_mode'] == 'automatic' ||
            _settings['followup_mode'] == 'automatic') &&
        !await _confirm(
          'Confirm customer recipient',
          'Future customer emails for ${widget.jobTitle ?? 'this job'} may be sent automatically to $email using your saved email modes. Existing waiting messages are cancelled when the recipient changes.',
          'Save recipient',
        )) {
      return;
    }
    if (!mounted || _locked) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await widget.client.saveJob(
        widget.jobId!,
        (_jobSettings['version'] as int?) ?? 0,
        {'customer_email': email, 'enabled': enabled},
      );
      if (!mounted || _locked) return;
      setState(() {
        _accept(result);
        _notice = 'Customer email settings saved for this job.';
        _prepareKey = null;
      });
      unawaited(kKorlixSounds.play(KorlixSound.success));
    } catch (e) {
      if (mounted && !_locked) {
        setState(() {
          _error = '$e';
          _needsRefresh = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _showFeedbackAtTop();
      }
    }
  }

  Future<void> _prepare() async {
    if (_disabled) return;
    if (!await _confirm(
      'Prepare a report draft?',
      'Prepare the current completed job report for ${_customer.text.trim()}. You will review and approve the draft before it can be sent.',
      'Prepare draft',
    )) {
      return;
    }
    _prepareKey ??= fieldProofRequestKey();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.client.prepare(widget.jobId!, _prepareKey!);
      if (!mounted || _locked) return;
      final result = await widget.client.job(widget.jobId!);
      if (!mounted || _locked) return;
      setState(() {
        _accept(result);
        _activity = true;
        _notice =
            'Draft preparation requested. Refresh activity to see when it is ready.';
      });
    } catch (e) {
      if (mounted && !_locked) {
        setState(() {
          _error = '$e';
          _needsRefresh = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _showFeedbackAtTop();
      }
    }
  }

  Future<void> _openDelivery(Map<String, dynamic> delivery) async {
    if (_disabled) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _EmailDeliveryScreen(
          client: widget.client,
          id: fpEmailText(delivery['id']),
          saveFile: widget.saveFile,
        ),
      ),
    );
    if (mounted && !_locked) await _load();
  }

  static String _dayNames(Object? values) {
    const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return (values is List
            ? values
                  .whereType<int>()
                  .where((v) => v >= 0 && v <= 6)
                  .map((v) => names[v])
            : <String>[])
        .join(', ');
  }

  Widget _card(
    String title,
    IconData icon,
    Color color,
    List<Widget> children,
  ) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: color.withValues(alpha: .3)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
  Widget _text(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: const TextStyle(height: 1.45)),
  );
  Widget _field(
    TextEditingController controller,
    String label,
    String key, {
    String? hint,
    int lines = 1,
    TextInputType? type,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      key: Key(key),
      controller: controller,
      onChanged: (_) => setState(() {}),
      enabled: !_disabled,
      maxLines: lines,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        helperMaxLines: 5,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Widget _mode(String key, String label, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$key-${_settings[key]}'),
      initialValue: fieldProofEmailModes.containsKey(_settings[key])
          ? _settings[key] as String
          : 'off',
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(Icons.tune, color: color),
      ),
      items: fieldProofEmailModes.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: _disabled ? null : (v) => setState(() => _settings[key] = v),
    ),
  );
  Widget _switch(String key, String title, String subtitle, Color color) =>
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        activeTrackColor: color,
        title: Text(title),
        subtitle: Text(subtitle),
        value: _settings[key] == true,
        onChanged: _disabled ? null : (v) => setState(() => _settings[key] = v),
      );
  Widget _button(
    String label,
    IconData icon,
    VoidCallback? action, {
    String? key,
    Color color = _mailTeal,
  }) => FilledButton.icon(
    key: key == null ? null : Key(key),
    onPressed: korlixSoundAction(action),
    style: korlixSoundButtonStyle(
      FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      ),
    ),
    icon: Icon(icon),
    label: Text(label, textAlign: TextAlign.center),
  );
  List<Widget> _globalSettings() => [
    _card('Your business identity', Icons.verified_user_outlined, _mailTeal, [
      _field(_business, 'Business name', 'fp-email-business'),
      _text(
        'From: ${fpEmailText(_capabilities['sender_label']).isEmpty ? 'KORLIX FieldProof' : _capabilities['sender_label']}\nReply-To: ${fpEmailText(_capabilities['reply_to']).isEmpty ? 'Verified account email required' : _capabilities['reply_to']}',
      ),
      _text(
        'Your verified account email receives replies. The sender is managed by KORLIX.',
      ),
      if (_capabilities['ready'] != true)
        _banner(
          fieldProofEmailReadinessMessage(fpEmailText(_capabilities['reason'])),
          warning: true,
        ),
    ]),
    _card(
      'Customer reports & follow-up',
      Icons.mark_email_read_outlined,
      _mailTeal,
      [
        _text(
          'Send a clear job report after closeout, then one optional courtesy follow-up. Add and enable the customer email inside each job.',
        ),
        _mode('customer_mode', 'Completed job reports', _mailTeal),
        _mode('followup_mode', 'One courtesy follow-up', _mailTeal),
        _field(
          _delay,
          'Follow-up delay in days',
          'fp-email-delay',
          hint: '1–30 days after closeout.',
          type: TextInputType.number,
        ),
        _switch(
          'include_photos',
          'Include report photos',
          'Attach up to 12 normalized photo previews in the customer PDF.',
          _mailTeal,
        ),
      ],
    ),
    _card('Supervisor summaries', Icons.groups_outlined, _mailPurple, [
      _text(
        'Summarize the previous local calendar day and highlight current overdue jobs and unresolved issues. Each supervisor receives a separate email.',
      ),
      _mode('supervisor_mode', 'Daily summary mode', _mailPurple),
      _field(
        _supervisors,
        'Supervisor email addresses',
        'fp-email-supervisors',
        hint: 'Up to five addresses, one per line or separated by commas.',
        lines: 3,
        type: TextInputType.multiline,
      ),
      _field(
        _timezone,
        'Time zone',
        'fp-email-timezone',
        hint:
            'IANA name, for example America/New_York, America/Jamaica, Europe/London or UTC.',
      ),
      _field(
        _time,
        'Summary time',
        'fp-email-time',
        hint: '24-hour local time, for example 17:00.',
        type: TextInputType.datetime,
      ),
      const Text('Send summaries on'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (int day = 0; day < 7; day++)
            FilterChip(
              key: Key('fp-email-day-$day'),
              label: Text(
                const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][day],
              ),
              selected: (_settings['summary_days'] as List? ?? []).contains(
                day,
              ),
              onSelected: _disabled
                  ? null
                  : (selected) => setState(() {
                      final days = List<int>.from(
                        _settings['summary_days'] as List? ?? [],
                      );
                      selected ? days.add(day) : days.remove(day);
                      days.sort();
                      _settings['summary_days'] = days;
                    }),
            ),
        ],
      ),
    ]),
    _card('You stay in control', Icons.settings_outlined, _mailAmber, [
      _switch(
        'paused',
        'Pause all automation',
        'Stops waiting emails. Resume applies to future events; cancelled messages are not replayed.',
        _mailAmber,
      ),
      _field(
        _limit,
        'Maximum emails per day',
        'fp-email-limit',
        hint:
            '1–${_capabilities['daily_limit_max'] ?? 100} emails across reports, follow-ups and summaries.',
        type: TextInputType.number,
      ),
      _text(
        'Off sends nothing. Review drafts requires approval for each email. Automatic sends after your setup is confirmed. Changing this setup cancels waiting emails. No historical backlog is emailed when you activate a mode.',
      ),
      _button(
        _busy ? 'Saving…' : 'Save email settings',
        Icons.save_outlined,
        _disabled ? null : _save,
        key: 'fp-email-save',
      ),
    ]),
  ];
  List<Widget> _jobFields() => [
    _card('Customer email for this job', Icons.person_outline, _mailTeal, [
      if (widget.jobTitle != null) _text(widget.jobTitle!),
      _field(
        _customer,
        'Customer email address',
        'fp-email-customer',
        type: TextInputType.emailAddress,
      ),
      SwitchListTile.adaptive(
        key: const Key('fp-email-job-enabled'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Enable customer emails for this job'),
        value: _jobSettings['enabled'] == true,
        onChanged: _disabled
            ? null
            : (v) => setState(() => _jobSettings['enabled'] = v),
      ),
      _text(
        'Reports: ${fieldProofEmailModes[_settings['customer_mode']] ?? 'Off'}\nFollow-up: ${fieldProofEmailModes[_settings['followup_mode']] ?? 'Off'}\nAutomation: ${_settings['paused'] == true ? 'Paused' : 'Not paused'}',
      ),
      _text(
        'Both an enabled recipient here and an active mode in Autonomous Email are required. Changing the recipient cancels waiting emails. Saving does not send a past job automatically.',
      ),
      _button(
        _busy ? 'Saving…' : 'Save customer email',
        Icons.save_outlined,
        _disabled ? null : _saveJob,
        key: 'fp-email-save-job',
      ),
    ]),
    if (widget.jobCompleted)
      _card(
        'Prepare a completed-job draft',
        Icons.description_outlined,
        _mailPurple,
        [
          _text(
            'Use the saved recipient and current completed job to prepare one report for review. This action does not send it.',
          ),
          _button(
            'Prepare report draft',
            Icons.edit_note,
            _disabled ||
                    _jobSettings['enabled'] != true ||
                    _savedJobSettings['enabled'] != true ||
                    _settings['customer_mode'] == 'off' ||
                    _settings['paused'] == true ||
                    _capabilities['ready'] != true ||
                    _customer.text.trim().toLowerCase() !=
                        fpEmailText(_savedJobSettings['customer_email'])
                ? null
                : _prepare,
            key: 'fp-email-prepare',
            color: _mailPurple,
          ),
        ],
      ),
  ];
  Widget _banner(String text, {bool warning = false}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: (warning ? _mailAmber : _mailTeal).withValues(alpha: .12),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Semantics(
      liveRegion: true,
      child: Text(text, style: const TextStyle(height: 1.45)),
    ),
  );
  List<Widget> _history() => [
    _text(
      'Recent email activity. Accepted means the email provider received the message; it does not confirm inbox delivery.',
    ),
    if (_deliveries.isEmpty)
      _card('No emails yet', Icons.inbox_outlined, _mailPurple, [
        _text(
          'After you enable a mode, new closeouts and scheduled summaries will appear here. Drafts wait for your approval.',
        ),
      ]),
    for (final delivery in _deliveries)
      _card(
        fieldProofEmailKind(fpEmailText(delivery['kind'])),
        Icons.mail_outline,
        _mailPurple,
        [
          Text(
            fieldProofEmailStatus(fpEmailText(delivery['state'])),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _text('To: ${delivery['recipient'] ?? ''}'),
          if (fpEmailText(delivery['subject']).isNotEmpty)
            _text(fpEmailText(delivery['subject'])),
          if (fpEmailText(delivery['scheduled_at']).isNotEmpty)
            _text('Scheduled: ${_formatDate(delivery['scheduled_at'])}'),
          _button(
            'View email',
            Icons.visibility_outlined,
            _disabled ? null : () => _openDelivery(delivery),
            color: _mailPurple,
          ),
        ],
      ),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_isJob ? 'Customer email' : 'Autonomous Email'),
      actions: [
        IconButton(
          tooltip: 'Reload saved settings',
          onPressed: _busy || _locked ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _locked
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Your account session changed. Sign in again and reopen FieldProof.',
              ),
            ),
          )
        : _loading
        ? const Center(child: CircularProgressIndicator())
        : Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 380 ? 12 : 24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(22),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF087D91), Color(0xFF5A43A7)],
                          ),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              color: Colors.white,
                              size: 32,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _isJob
                                  ? 'Keep your customer informed.'
                                  : 'The work is done. Keep everyone informed.',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Customer reports • Courtesy follow-up • Supervisor summaries',
                              style: TextStyle(
                                color: Colors.white,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_busy) const LinearProgressIndicator(),
                      if (_error != null) _banner(_error!, warning: true),
                      if (_needsRefresh)
                        _button(
                          'Reload saved settings',
                          Icons.refresh,
                          _busy ? null : _load,
                          key: 'fp-email-reload',
                        ),
                      if (_needsRefresh) const SizedBox(height: 16),
                      if (_queueNotice.isNotEmpty)
                        _banner(_queueNotice, warning: true),
                      if (_isJob && _capabilities['ready'] != true)
                        _banner(
                          fieldProofEmailReadinessMessage(
                            fpEmailText(_capabilities['reason']),
                          ),
                          warning: true,
                        ),
                      if (_notice != null) _banner(_notice!),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Setup'),
                            selected: !_activity,
                            onSelected: (_) =>
                                setState(() => _activity = false),
                          ),
                          ChoiceChip(
                            key: const Key('fp-email-activity'),
                            label: Text('Activity (${_deliveries.length})'),
                            selected: _activity,
                            onSelected: (_) => setState(() => _activity = true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      ...(_activity
                          ? _history()
                          : _isJob
                          ? _jobFields()
                          : _globalSettings()),
                    ],
                  ),
                ),
              ),
            ),
          ),
  );
}

String _formatDate(Object? value) {
  final parsed = DateTime.tryParse(fpEmailText(value));
  if (parsed == null) return fpEmailText(value);
  return '${parsed.toLocal().toString().substring(0, 16)} (device time)';
}

class _EmailDeliveryScreen extends StatefulWidget {
  const _EmailDeliveryScreen({
    required this.client,
    required this.id,
    this.saveFile,
  });
  final FieldProofEmailClient client;
  final String id;
  final Future<void> Function(Uint8List, String, String)? saveFile;
  @override
  State<_EmailDeliveryScreen> createState() => _EmailDeliveryScreenState();
}

class _EmailDeliveryScreenState extends State<_EmailDeliveryScreen> {
  final _scroll = ScrollController();
  Map<String, dynamic> _delivery = {};
  bool _busy = false,
      _locked = false,
      _needsRefresh = false,
      _dialogOpen = false;
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
    _scroll.dispose();
    super.dispose();
  }

  void _lock() {
    if (!mounted) return;
    if (_dialogOpen) Navigator.of(context).pop(false);
    setState(() {
      _locked = true;
      _delivery = {};
      _error = _notice = null;
    });
  }

  Future<void> _load() async {
    if (_busy || _locked) return;
    setState(() => _busy = true);
    try {
      final result = await widget.client.delivery(widget.id);
      if (mounted && !_locked) {
        setState(() {
          _delivery = result;
          _error = null;
          _needsRefresh = false;
        });
      }
    } catch (e) {
      if (mounted && !_locked) {
        setState(() {
          _error = '$e';
          _needsRefresh = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(String action) async {
    if (_busy || _locked || _needsRefresh) return;
    _dialogOpen = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          action == 'approve'
              ? 'Approve this email?'
              : action == 'retry'
              ? 'Retry this email?'
              : 'Cancel this email?',
        ),
        content: SingleChildScrollView(
          child: Text(
            action == 'cancel'
                ? 'Cancel this waiting email to ${_delivery['recipient']}?'
                : 'To: ${_delivery['recipient']}\nSubject: ${_delivery['subject']}\n\n${action == 'retry' ? 'Retry the same prepared message. The server will verify it is still safe to retry.' : 'Approval queues this exact draft for sending after current recipient and account checks.'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              action == 'approve'
                  ? 'Approve email'
                  : action == 'retry'
                  ? 'Retry email'
                  : 'Cancel email',
            ),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (confirmed != true || !mounted || _locked) return;
    setState(() {
      _busy = true;
      _error = _notice = null;
    });
    try {
      await widget.client.action(
        widget.id,
        action,
        _delivery['version'] as int,
      );
      if (!mounted || _locked) return;
      final result = await widget.client.delivery(widget.id);
      if (mounted && !_locked) {
        setState(() {
          _delivery = result;
          _notice = action == 'cancel'
              ? 'Email cancelled.'
              : 'Request accepted. Current status is shown below.';
        });
      }
    } catch (e) {
      if (mounted && !_locked) {
        setState(() {
          _error = '$e';
          _needsRefresh = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    if (_busy || _locked || _needsRefresh) return;
    setState(() {
      _busy = true;
      _error = _notice = null;
    });
    try {
      final bytes = await widget.client.report(widget.id);
      if (!mounted || _locked) return;
      await (widget.saveFile ?? saveFieldProofFile)(
        bytes,
        'KORLIX-FieldProof-${widget.id}.pdf',
        'application/pdf',
      );
      if (mounted && !_locked) {
        setState(
          () => _notice = 'PDF ready. Check your downloads or share options.',
        );
      }
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_busy && !_locked && !_needsRefresh;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Email preview'),
        actions: [
          IconButton(
            tooltip: 'Refresh email status',
            onPressed: _busy || _locked ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _locked
          ? const Center(child: Text('Sign in again and reopen FieldProof.'))
          : Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 850),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_busy) const LinearProgressIndicator(),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(_error!),
                          ),
                        if (_notice != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(_notice!),
                            ),
                          ),
                        if (_delivery.isNotEmpty) ...[
                          Text(
                            fieldProofEmailStatus(
                              fpEmailText(_delivery['state']),
                            ),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Provider acceptance does not confirm inbox delivery.',
                          ),
                          const SizedBox(height: 20),
                          SelectableText(
                            'To: ${_delivery['recipient']}\nSubject: ${_delivery['subject'] ?? 'Preparing…'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (fpEmailText(_delivery['code']).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                fieldProofEmailIssueMessage(
                                  fpEmailText(_delivery['code']),
                                ),
                              ),
                            ),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: SelectableText(
                                fpEmailText(_delivery['text']).isEmpty
                                    ? 'The email preview will appear after preparation finishes.'
                                    : fpEmailText(_delivery['text']),
                                style: const TextStyle(height: 1.6),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 10,
                            runSpacing: 12,
                            children: [
                              if (_delivery['has_report'] == true)
                                OutlinedButton.icon(
                                  onPressed: enabled
                                      ? korlixSoundAction(_download)
                                      : null,
                                  icon: const Icon(Icons.download_outlined),
                                  label: const Text('Download prepared PDF'),
                                ),
                              if (_delivery['can_approve'] == true)
                                FilledButton.icon(
                                  key: const Key('fp-email-approve'),
                                  onPressed: enabled
                                      ? korlixSoundAction(
                                          () => _action('approve'),
                                        )
                                      : null,
                                  icon: const Icon(Icons.send_outlined),
                                  label: const Text('Approve & queue email'),
                                ),
                              if (_delivery['can_retry'] == true)
                                FilledButton.icon(
                                  onPressed: enabled
                                      ? korlixSoundAction(
                                          () => _action('retry'),
                                        )
                                      : null,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry same email'),
                                ),
                              if (_delivery['can_cancel'] == true)
                                OutlinedButton.icon(
                                  onPressed: enabled
                                      ? korlixSoundAction(
                                          () => _action('cancel'),
                                        )
                                      : null,
                                  icon: const Icon(Icons.close),
                                  label: const Text('Cancel email'),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
