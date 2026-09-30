import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'scheduling_client.dart';
import 'scheduling_forms.dart';
import '../bookkeeping/bookkeeping_file_save.dart';

class SchedulingScreen extends StatefulWidget {
  const SchedulingScreen({
    super.key,
    required this.client,
    this.openFunnels,
    this.openContacts,
    this.disposeClient = true,
  });
  final SchedulingClient client;
  final Future<void> Function()? openFunnels, openContacts;
  final bool disposeClient;
  @override
  State<SchedulingScreen> createState() => _SchedulingScreenState();
}

class _SchedulingScreenState extends State<SchedulingScreen>
    with WidgetsBindingObserver {
  SchedulingMap _data = {};
  bool _loading = true, _busy = false;
  String? _error;
  int _tab = 0, _generation = 0;
  String _search = '', _filter = 'Upcoming';
  Timer? _timer;
  ModalRoute<dynamic>? _route;
  final _exportKey = GlobalKey();
  SchedulingMap get _profile => schedulingMap(_data['profile']);
  bool get _emailReady =>
      schedulingMap(_data['capabilities'])['automatic_email'] == true;
  bool get _emailEnabled => _profile['notifications_enabled'] == true;
  List<SchedulingMap> get _events => schedulingItems(_data['events']);
  List<SchedulingMap> get _bookings => schedulingItems(_data['bookings']);
  List<String> get _zones =>
      (_data['timezones'] as List? ?? ['UTC', 'America/New_York'])
          .map((z) => '$z')
          .toList();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.addListener(_access);
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!_busy && !_loading && widget.client.available) {
        unawaited(_load(quiet: true));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_busy &&
        widget.client.available) {
      unawaited(_load(quiet: true));
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.client.removeListener(_access);
    if (widget.disposeClient) widget.client.dispose();
    super.dispose();
  }

  void _access() {
    if (!mounted || widget.client.available) return;
    _generation++;
    setState(() {
      _data = {};
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _route != null) {
        Navigator.of(context).popUntil((r) => r == _route || r.isFirst);
      }
    });
  }

  Future<void> _load({bool quiet = false}) async {
    final operation = ++_generation;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await widget.client.get('');
      if (mounted && operation == _generation) setState(() => _data = data);
    } catch (e) {
      if (mounted && operation == _generation) setState(() => _error = '$e');
    } finally {
      if (mounted && operation == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      widget.client.guard();
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notice(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _copy(String text, String notice) async {
    widget.client.guard();
    await Clipboard.setData(ClipboardData(text: text));
    _notice(notice);
  }

  Future<bool> _confirm(
    String title,
    String message, {
    String label = 'Confirm',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Keep unchanged'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(label),
            ),
          ],
        ),
      ) ==
      true;
  Future<void> _editAvailability() async {
    final result = await editScheduleProfile(context, _profile, _zones);
    if (result != null && mounted) {
      await _run(() async {
        await widget.client.post('profile', result);
        await _load(quiet: true);
        _notice('Availability saved.');
      });
    }
  }

  Future<void> _emailSettings() async {
    var enabled = _emailEnabled;
    var reminder = (_profile['reminder_minutes'] as num?)?.toInt() ?? 60;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Booking emails'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Send appointment confirmations, reschedules and cancellations to you and your guests. Guests can receive one reminder before their appointment. These messages do not subscribe anyone to marketing.',
                  ),
                  const SizedBox(height: 16),
                  if (!_emailReady)
                    const Text(
                      'Email delivery is not configured yet. You can keep booking emails off.',
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Send booking emails'),
                    value: enabled,
                    onChanged: _emailReady
                        ? (v) => update(() => enabled = v)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: reminder,
                    decoration: const InputDecoration(
                      labelText: 'Guest reminder',
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('No reminder')),
                      DropdownMenuItem(
                        value: 15,
                        child: Text('15 minutes before'),
                      ),
                      DropdownMenuItem(
                        value: 30,
                        child: Text('30 minutes before'),
                      ),
                      DropdownMenuItem(value: 60, child: Text('1 hour before')),
                      DropdownMenuItem(
                        value: 1440,
                        child: Text('1 day before'),
                      ),
                    ],
                    onChanged: enabled
                        ? (v) => update(() => reminder = v!)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Applies to future booking activity. Up to 100 email updates per host per day; delivery may be delayed. Turning this off stops queued updates, but cannot recall an email already submitted. Check individual bookings for submission status.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Save email settings'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      await _run(() async {
        await widget.client.post('notifications', {
          'enabled': enabled,
          'reminder_minutes': reminder,
          'confirmed': true,
          'revision': _profile['revision'],
        });
        await _load(quiet: true);
        _notice('Booking email settings saved.');
      });
    }
  }

  Future<void> _editEvent([SchedulingMap event = const {}]) async {
    if (_profile.isEmpty) {
      await _editAvailability();
      if (_profile.isEmpty) return;
    }
    if (!mounted) return;
    final result = await editScheduleEvent(context, event);
    if (result != null && mounted) {
      await _run(() async {
        await widget.client.post(
          event.isEmpty ? 'events' : 'events/${event['id']}',
          result,
        );
        await _load(quiet: true);
        _notice(
          event.isEmpty
              ? 'Draft created. Publish it when you are ready.'
              : 'Event type updated.',
        );
      });
    }
  }

  Future<void> _eventState(SchedulingMap e, String state) async {
    final title = state == 'published'
        ? 'Publish this booking page?'
        : state == 'paused'
        ? 'Pause new bookings?'
        : 'Archive this event type?';
    final message = state == 'published'
        ? 'Guests with the link can book from your available hours. KORLIX checks its own bookings and your time blocks. Add outside appointments as time blocks until calendar sync is available. Booking emails follow your email settings. Text notifications are not connected.'
        : 'The public link will stop accepting new bookings. Existing appointments stay in your schedule.';
    if (await _confirm(
          title,
          message,
          label: state == 'published' ? 'Publish page' : 'Confirm',
        ) &&
        mounted) {
      await _run(() async {
        await widget.client.post('events/${e['id']}/state', {
          'revision': e['revision'],
          'state': state,
          'confirmed': true,
        });
        await _load(quiet: true);
      });
    }
  }

  Future<void> _preview(SchedulingMap event) async {
    final uri = Uri.tryParse('${event['url']}');
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      throw const SchedulingException('The booking link is unavailable.');
    }
    widget.client.guard();
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw const SchedulingException(
        'Your browser could not open this booking page.',
      );
    }
  }

  Future<void> _saveExport(String filename, String text, String mime) async {
    widget.client.guard();
    final box = _exportKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);
    await saveBookkeepingFile(
      Uint8List.fromList(utf8.encode(text)),
      filename,
      mime,
      origin,
    );
  }

  Future<void> _blockTime() async {
    final now = DateTime.now();
    DateTime start = DateTime(now.year, now.month, now.day, now.hour + 1),
        end = start.add(const Duration(hours: 1));
    final label = TextEditingController(text: 'Unavailable');
    String? error;
    final result = await showDialog<SchedulingMap>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) {
          Future<void> pick(bool first) async {
            final value = first ? start : end;
            final date = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: now.subtract(const Duration(days: 1)),
              lastDate: now.add(const Duration(days: 366)),
            );
            if (date == null || !context.mounted) return;
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(value),
            );
            if (time == null || !context.mounted) return;
            update(() {
              final next = DateTime(
                date.year,
                date.month,
                date.day,
                time.hour,
                time.minute,
              );
              if (first) {
                start = next;
                if (!end.isAfter(start)) {
                  end = start.add(const Duration(hours: 1));
                }
              } else {
                end = next;
              }
            });
          }

          return AlertDialog(
            title: const Text('Block unavailable time'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Use this for appointments outside KORLIX. Times below use this device’s time zone (${now.timeZoneName}).',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: label,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Private label',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Start'),
                    subtitle: Text(_time(start.toIso8601String())),
                    trailing: const Icon(Icons.edit_calendar),
                    onTap: () => pick(true),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('End'),
                    subtitle: Text(_time(end.toIso8601String())),
                    trailing: const Icon(Icons.edit_calendar),
                    onTap: () => pick(false),
                  ),
                  const Text(
                    'Existing appointments stay booked. A time block prevents new bookings in this period.',
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (!end.isAfter(start) || label.text.trim().isEmpty) {
                    update(
                      () => error =
                          'Enter a label and an end time after the start.',
                    );
                    return;
                  }
                  Navigator.pop(dialog, <String, dynamic>{
                    'label': label.text.trim(),
                    'starts_at': start.toUtc().toIso8601String(),
                    'ends_at': end.toUtc().toIso8601String(),
                  });
                },
                child: const Text('Block time'),
              ),
            ],
          );
        },
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), label.dispose);
    if (result != null && mounted) {
      await _run(() async {
        await widget.client.post('blocks', result);
        await _load(quiet: true);
      });
    }
  }

  String _time(dynamic value) {
    final d = DateTime.tryParse('$value')?.toLocal();
    if (d == null) return 'Unavailable';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} ${d.timeZoneName}';
  }

  Future<void> _bookingState(SchedulingMap b, String state) async {
    final label = state == 'canceled'
        ? 'Cancel appointment'
        : state == 'completed'
        ? 'Mark completed'
        : 'Mark no-show';
    if (await _confirm(
          '$label?',
          'This updates the booking in KORLIX. Cancellations queue an email update when booking emails are enabled. Completion and no-show changes do not send emails.',
          label: label,
        ) &&
        mounted) {
      await _run(() async {
        await widget.client.post('bookings/${b['id']}/state', {
          'revision': b['revision'],
          'state': state,
          'confirmed': true,
        });
        await _load(quiet: true);
      });
    }
  }

  Future<void> _bookingDetails(SchedulingMap b) async {
    final snapshot = schedulingMap(b['snapshot']);
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('${snapshot['title']}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${b['guest_name']}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                SelectableText('${b['guest_email']}'),
                const SizedBox(height: 12),
                Text(_time(b['starts_at'])),
                Text('${snapshot['duration_minutes']} minutes · ${b['state']}'),
                Text('Guest time zone: ${b['guest_timezone']}'),
                const SizedBox(height: 16),
                Text('${snapshot['location_detail'] ?? ''}'),
                for (final q in schedulingItems(snapshot['questions'])) ...[
                  const SizedBox(height: 16),
                  Text(
                    '${q['label']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text('${schedulingMap(b['answers'])[q['id']] ?? '—'}'),
                ],
                const SizedBox(height: 20),
                for (final n in schedulingItems(b['notifications']))
                  Text("Guest email · ${n['kind']}: ${n['state']}"),
                if (schedulingItems(b['notifications']).isEmpty)
                  const Text('No guest email update scheduled.'),
                const SizedBox(height: 10),
                const Text(
                  'Guest contact details are self-reported. An accepted email status means submission to the email provider; it does not confirm inbox delivery.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _panel(Widget child, {Color? color}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: Theme.of(context).dividerColor.withValues(alpha: .35),
      ),
    ),
    child: child,
  );
  Widget _heading(String title, String description) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(description),
      ],
    ),
  );
  Widget _stat(String value, String label, IconData icon) => SizedBox(
    width: 220,
    child: _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 18),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(label),
        ],
      ),
    ),
  );
  Widget _overview() {
    final upcoming = _bookings
        .where(
          (b) =>
              b['state'] == 'confirmed' &&
              (DateTime.tryParse(
                    '${b['starts_at']}',
                  )?.isAfter(DateTime.now()) ??
                  false),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Your time, working for you.',
          'A clear view of your booking pages and upcoming conversations.',
        ),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _stat(
              '${upcoming.length}',
              'Upcoming appointments',
              Icons.event_available,
            ),
            _stat(
              '${_events.where((e) => e['state'] == 'published').length}',
              'Live booking pages',
              Icons.link,
            ),
            _stat(
              '${_bookings.where((b) => b['state'] == 'completed').length}',
              'Marked completed',
              Icons.task_alt,
            ),
            _stat(
              '${_bookings.where((b) => b['state'] == 'no_show').length}',
              'Marked no-show',
              Icons.person_off_outlined,
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Counts reflect up to 500 bookings, including the last 90 days and upcoming appointments.',
        ),
        const SizedBox(height: 24),
        if (_profile.isEmpty)
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Make room for your next opportunity.',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Set your host name, time zone and weekly hours. Then create a meeting type and publish its booking link.',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _editAvailability,
                  icon: const Icon(Icons.schedule),
                  label: const Text('Set my availability'),
                ),
              ],
            ),
          )
        else ...[
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Next on your calendar',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                if (upcoming.isEmpty)
                  const Text(
                    'Your next appointment will appear here. Share a live booking page to get started.',
                  )
                else
                  for (final b in upcoming.take(4))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: Text('${schedulingMap(b['snapshot'])['title']}'),
                      subtitle: Text(
                        '${b['guest_name']} · ${_time(b['starts_at'])}',
                      ),
                      onTap: () => _bookingDetails(b),
                    ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() => _tab = 3),
                  child: const Text('View bookings →'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Make your link work everywhere.',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Use a booking page in your email signature, KORLIX Social, website or Funnel Studio. Each published event gets its own link.',
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _tab = 1),
                      icon: const Icon(Icons.link),
                      label: const Text('My booking pages'),
                    ),
                    if (widget.openFunnels != null)
                      OutlinedButton.icon(
                        onPressed: widget.openFunnels,
                        icon: const Icon(Icons.filter_alt_outlined),
                        label: const Text('Open Funnel Studio'),
                      ),
                    if (widget.openContacts != null)
                      OutlinedButton.icon(
                        onPressed: widget.openContacts,
                        icon: const Icon(Icons.contacts_outlined),
                        label: const Text('Open Contacts CRM'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        _limitsNotice(),
      ],
    );
  }

  Widget _limitsNotice() => _panel(
    const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Know what is connected',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 8),
        Text(
          'Booking conflicts are checked against KORLIX appointments and your unavailable time blocks. Google/Microsoft calendar sync, text messages, team scheduling and payments are not connected in this release. Add outside appointments as time blocks. Booking emails and reminders are optional in Availability.',
        ),
      ],
    ),
  );
  Widget _eventCard(SchedulingMap e) {
    final color = Color(
      int.parse(
        '${e['color'] ?? '#72D6EB'}'.replaceFirst('#', 'ff'),
        radix: 16,
      ),
    );
    final published = e['state'] == 'published';
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  '${e['title']}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: 10),
              Chip(label: Text('${e['state']}')),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${e['duration_minutes']} min · ${e['kind'] == 'group' ? 'Group · ${e['capacity']} seats' : 'One-to-one'} · ${e['location_kind']}',
          ),
          if ('${e['description']}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${e['description']}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _editEvent(e),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
              if (published) ...[
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => _copy('${e['url']}', 'Booking link copied.'),
                        ),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy link'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(() => _preview(e)),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open page'),
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => _copy(
                            '<a href="${e['url']}" target="_blank" rel="noopener">Book a time</a>',
                            'Website button HTML copied.',
                          ),
                        ),
                  child: const Text('Website button'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _eventState(e, 'paused'),
                  child: const Text('Pause'),
                ),
              ] else if (e['state'] != 'archived')
                FilledButton.icon(
                  onPressed: _busy ? null : () => _eventState(e, 'published'),
                  icon: const Icon(Icons.public),
                  label: const Text('Publish'),
                ),
              if (e['state'] != 'archived')
                TextButton(
                  onPressed: _busy ? null : () => _eventState(e, 'archived'),
                  child: const Text('Archive'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _eventTypes() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Meetings worth making time for.',
        'Create one-to-one meetings and group sessions. Set your rules once, then share a booking link.',
      ),
      FilledButton.icon(
        onPressed: _busy ? null : () => _editEvent(),
        icon: const Icon(Icons.add),
        label: const Text('New event type'),
      ),
      const SizedBox(height: 24),
      if (_events.isEmpty)
        _panel(
          const Text(
            'No event types yet. Create your first meeting, review its settings, then publish it.',
          ),
        ),
      for (final e in _events) ...[_eventCard(e), const SizedBox(height: 18)],
    ],
  );
  Widget _availability() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        'Availability that respects your day.',
        'Set weekly hours, split shifts, date overrides and time blocks.',
      ),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _editAvailability,
            icon: const Icon(Icons.edit_calendar),
            label: Text(
              _profile.isEmpty ? 'Set my availability' : 'Edit availability',
            ),
          ),
          if (_profile.isNotEmpty)
            OutlinedButton.icon(
              onPressed: _busy ? null : _blockTime,
              icon: const Icon(Icons.block),
              label: const Text('Block time'),
            ),
        ],
      ),
      const SizedBox(height: 24),
      if (_profile.isNotEmpty) ...[
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _emailEnabled && _emailReady
                    ? 'Booking emails are on'
                    : 'Booking emails are off',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Keep guests informed with confirmations, change notices and a reminder.',
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _busy ? null : _emailSettings,
                icon: const Icon(Icons.mark_email_read_outlined),
                label: const Text('Email settings'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_profile['display_name']}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text('Availability time zone: ${_profile['timezone']}'),
              const SizedBox(height: 20),
              for (final day in [1, 2, 3, 4, 5, 6, 0])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 6,
                    children: [
                      SizedBox(
                        width: 105,
                        child: Text(
                          scheduleDays[day],
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        scheduleWindows(
                              schedulingItems(_profile['weekly'])
                                  .where((w) => w['day'] == day)
                                  .firstOrNull?['windows'],
                            ).isEmpty
                            ? 'Unavailable'
                            : scheduleWindows(
                                schedulingItems(_profile['weekly'])
                                    .where((w) => w['day'] == day)
                                    .firstOrNull?['windows'],
                              ),
                      ),
                    ],
                  ),
                ),
              if (schedulingItems(_profile['overrides']).isNotEmpty) ...[
                const Divider(),
                const Text('Date overrides'),
                for (final o in schedulingItems(_profile['overrides']))
                  Text(
                    '${o['date']} · ${scheduleWindows(o['windows']).isEmpty ? 'Closed' : scheduleWindows(o['windows'])}',
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Unavailable time blocks',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (schedulingItems(_data['blocks']).isEmpty)
          const Text(
            'Add appointments from other calendars here to keep those times unavailable.',
          ),
        for (final b in schedulingItems(_data['blocks']))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${b['label']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text('${_time(b['starts_at'])}\n${_time(b['ends_at'])}'),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (await _confirm(
                                  'Remove this time block?',
                                  'The time may become available for new bookings.',
                                ) &&
                                mounted) {
                              await _run(() async {
                                await widget.client.post(
                                  'blocks/${b['id']}/remove',
                                  {'confirmed': true},
                                );
                                await _load(quiet: true);
                              });
                            }
                          },
                    child: const Text('Remove block'),
                  ),
                ],
              ),
            ),
          ),
      ],
      const SizedBox(height: 24),
      _limitsNotice(),
    ],
  );
  Widget _bookingList() {
    final now = DateTime.now();
    final rows = _bookings.where((b) {
      final future =
          DateTime.tryParse('${b['starts_at']}')?.isAfter(now) ?? false;
      final match =
          _filter == 'All' ||
          (_filter == 'Upcoming' && b['state'] == 'confirmed' && future) ||
          (_filter == 'Past' && !future) ||
          (_filter == 'Canceled' && b['state'] == 'canceled');
      return match &&
          '${b['guest_name']} ${b['guest_email']} ${schedulingMap(b['snapshot'])['title']}'
              .toLowerCase()
              .contains(_search.toLowerCase());
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Every appointment, in one place.',
          'Times use this device’s time zone (${DateTime.now().timeZoneName}). Results include up to ${_data['booking_limit'] ?? 500} bookings with the last ${_data['history_days'] ?? 90} days of history.',
        ),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Search guest or meeting',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                initialValue: _filter,
                decoration: const InputDecoration(
                  labelText: 'Show',
                  border: OutlineInputBorder(),
                ),
                items: ['Upcoming', 'Past', 'Canceled', 'All']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _filter = v!),
              ),
            ),
            OutlinedButton.icon(
              key: _exportKey,
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final d = await widget.client.get('export');
                      await _saveExport(
                        '${d['filename']}',
                        '${d['csv']}',
                        'text/csv',
                      );
                    }),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export CSV'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (rows.isEmpty) _panel(const Text('No bookings match this view.')),
        for (final b in rows) ...[
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 14,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${schedulingMap(b['snapshot'])['title']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Chip(label: Text('${b['state']}')),
                  ],
                ),
                const SizedBox(height: 8),
                Text('${b['guest_name']} · ${b['guest_email']}'),
                Text(_time(b['starts_at'])),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton(
                      onPressed: () => _bookingDetails(b),
                      child: const Text('View details'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                              final d = await widget.client.get(
                                'bookings/${b['id']}/calendar',
                              );
                              await _saveExport(
                                '${d['filename']}',
                                '${d['calendar']}',
                                'text/calendar',
                              );
                            }),
                      icon: const Icon(Icons.calendar_month),
                      label: const Text('Calendar file'),
                    ),
                    if (b['state'] == 'confirmed') ...[
                      if (DateTime.tryParse(
                            '${b['starts_at']}',
                          )?.isBefore(now) ??
                          false) ...[
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _bookingState(b, 'completed'),
                          child: const Text('Completed'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _bookingState(b, 'no_show'),
                          child: const Text('No-show'),
                        ),
                      ],
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _bookingState(b, 'canceled'),
                        child: const Text('Cancel appointment'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final denied = !widget.client.available;
    return Scaffold(
      appBar: AppBar(
        title: const Text('KORLIX Scheduling'),
        actions: [
          IconButton(
            tooltip: 'Refresh schedule',
            onPressed: _busy || denied ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: denied
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Sign in with an active, verified KORLIX account and reopen Scheduling.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _loading && _data.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _panel(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: const [
                                Chip(
                                  avatar: Icon(
                                    Icons.auto_awesome_outlined,
                                    size: 16,
                                  ),
                                  label: Text('KORLIX SCHEDULING'),
                                ),
                                Chip(label: Text('ONE-TO-ONE + GROUPS')),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Less back-and-forth.\nMore meaningful meetings.',
                              style: Theme.of(context).textTheme.headlineLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -.8,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Beautiful booking pages. Thoughtful availability. Your next connection, made simple.',
                            ),
                            const SizedBox(height: 22),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                FilledButton.icon(
                                  onPressed: _busy ? null : () => _editEvent(),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Create booking page'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _busy ? null : _editAvailability,
                                  icon: const Icon(Icons.schedule),
                                  label: const Text('My availability'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final item in [
                              (0, 'Overview', Icons.space_dashboard_outlined),
                              (1, 'Event types', Icons.link),
                              (2, 'Availability', Icons.schedule),
                              (3, 'Bookings', Icons.event_note),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: ChoiceChip(
                                  selected: _tab == item.$1,
                                  onSelected: (_) =>
                                      setState(() => _tab = item.$1),
                                  avatar: Icon(item.$3, size: 18),
                                  label: Text(item.$2),
                                  showCheckmark: false,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (_busy || _loading) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 20),
                      ],
                      if (_error != null) ...[
                        _panel(
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      switch (_tab) {
                        0 => _overview(),
                        1 => _eventTypes(),
                        2 => _availability(),
                        _ => _bookingList(),
                      },
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
