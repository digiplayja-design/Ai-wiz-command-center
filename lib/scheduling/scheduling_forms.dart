import 'package:flutter/material.dart';
import 'scheduling_client.dart';

const scheduleDays = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];
String scheduleClock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
String scheduleDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String scheduleWindows(dynamic windows) => (windows as List? ?? [])
    .map((w) => '${scheduleClock(w[0] as int)}–${scheduleClock(w[1] as int)}')
    .join(', ');
List<List<int>> parseScheduleWindows(String value) {
  if (value.trim().isEmpty) return [];
  final result = <List<int>>[];
  int end = 0;
  for (final part in value.split(',')) {
    final match = RegExp(
      r'^\s*(\d{1,2}):(\d{2})\s*[-–]\s*(\d{1,2}):(\d{2})\s*$',
    ).firstMatch(part);
    if (match == null) {
      throw const FormatException(
        'Use hours such as 09:00–12:00, 13:00–17:00. Leave closed days blank.',
      );
    }
    final h1 = int.parse(match[1]!),
        m1 = int.parse(match[2]!),
        h2 = int.parse(match[3]!),
        m2 = int.parse(match[4]!);
    final start = h1 * 60 + m1, next = h2 * 60 + m2;
    if (h1 > 23 ||
        h2 > 24 ||
        m1 > 59 ||
        m2 > 59 ||
        start < end ||
        next <= start ||
        next > 1440 ||
        start % 5 != 0 ||
        next % 5 != 0) {
      throw const FormatException(
        'Hours must be ordered, non-overlapping, and in five-minute steps.',
      );
    }
    result.add([start, next]);
    end = next;
  }
  if (result.length > 8) {
    throw const FormatException('Use at most eight time windows per day.');
  }
  return result;
}

Future<SchedulingMap?> editScheduleProfile(
  BuildContext context,
  SchedulingMap current,
  List<String> zones,
) async {
  final name = TextEditingController(text: '${current['display_name'] ?? ''}');
  String zone = '${current['timezone'] ?? 'America/New_York'}';
  final weekly = schedulingItems(current['weekly']);
  final hours = List.generate(
    7,
    (day) => TextEditingController(
      text: weekly.isEmpty
          ? (day >= 1 && day <= 5 ? '09:00–17:00' : '')
          : scheduleWindows(
              weekly.where((w) => w['day'] == day).firstOrNull?['windows'],
            ),
    ),
  );
  final overrides = schedulingItems(current['overrides'])
      .map(
        (o) => <String, dynamic>{
          'date': o['date'],
          'controller': TextEditingController(
            text: scheduleWindows(o['windows']),
          ),
        },
      )
      .toList();
  final removed = <TextEditingController>[];
  String? error;
  final result = await showDialog<SchedulingMap>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(
          current.isEmpty ? 'Set your availability' : 'Edit availability',
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'These hours apply to all your event types. Existing appointments keep their original time.',
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: name,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Public host name',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: zone,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Your availability time zone',
                  ),
                  items:
                      [
                            ...{zone, ...zones},
                          ]
                          .map(
                            (z) => DropdownMenuItem(
                              value: z,
                              child: Text(
                                z.replaceAll('_', ' '),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (v) => update(() => zone = v!),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Weekly hours · 24-hour time',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Example: 09:00–12:00, 13:00–17:00. Leave a day blank when you are unavailable.',
                ),
                for (int day = 0; day < 7; day++)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(
                      controller: hours[day],
                      decoration: InputDecoration(
                        labelText: scheduleDays[day],
                        hintText: 'Closed',
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                const Text(
                  'Date overrides',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text(
                  'Use an override for holidays or different hours on one date. Leave its hours blank to close the day.',
                ),
                for (final o in overrides)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller:
                                o['controller'] as TextEditingController,
                            decoration: InputDecoration(
                              labelText: '${o['date']}',
                              hintText: 'Closed all day',
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove date override',
                          onPressed: () => update(() {
                            removed.add(
                              o['controller'] as TextEditingController,
                            );
                            overrides.remove(o);
                          }),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                TextButton.icon(
                  onPressed: overrides.length >= 60
                      ? null
                      : () async {
                          final now = DateTime.now();
                          final d = await showDatePicker(
                            context: context,
                            initialDate: now,
                            firstDate: now.subtract(const Duration(days: 1)),
                            lastDate: now.add(const Duration(days: 366)),
                          );
                          if (d != null && context.mounted) {
                            final date = scheduleDate(d);
                            if (!overrides.any((o) => o['date'] == date)) {
                              update(
                                () => overrides.add({
                                  'date': date,
                                  'controller': TextEditingController(),
                                }),
                              );
                            }
                          }
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('Add date override'),
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              try {
                if (name.text.trim().isEmpty) {
                  throw const FormatException(
                    'Enter the name guests should see.',
                  );
                }
                final result = <String, dynamic>{
                  'revision': current['revision'] ?? 0,
                  'display_name': name.text.trim(),
                  'timezone': zone,
                  'weekly': List.generate(
                    7,
                    (day) => {
                      'day': day,
                      'windows': parseScheduleWindows(hours[day].text),
                    },
                  ),
                  'overrides': overrides
                      .map(
                        (o) => {
                          'date': o['date'],
                          'windows': parseScheduleWindows(
                            (o['controller'] as TextEditingController).text,
                          ),
                        },
                      )
                      .toList(),
                };
                Navigator.pop(dialog, result);
              } on FormatException catch (e) {
                update(() => error = e.message);
              }
            },
            child: const Text('Save availability'),
          ),
        ],
      ),
    ),
  );
  Future<void>.delayed(const Duration(seconds: 1), () {
    name.dispose();
    for (final c in hours) {
      c.dispose();
    }
    for (final o in overrides) {
      (o['controller'] as TextEditingController).dispose();
    }
    for (final c in removed) {
      c.dispose();
    }
  });
  return result;
}

Future<SchedulingMap?> editScheduleEvent(
  BuildContext context, [
  SchedulingMap current = const {},
  List<SchedulingMap> teams = const [],
  List<SchedulingMap> connections = const [],
]) async {
  final defaults = <String, dynamic>{
    'title': '',
    'description': '',
    'duration_minutes': 30,
    'interval_minutes': 30,
    'buffer_before': 0,
    'buffer_after': 15,
    'notice_minutes': 240,
    'horizon_days': 60,
    'daily_limit': 8,
    'capacity': 1,
    'cancel_notice_minutes': 60,
    'location_detail': '',
    'price': ((current['price_cents'] as num? ?? 0) / 100).toStringAsFixed(2),
    'refund_policy': 'Contact your host to request a refund.',
  };
  final fields = {
    for (final key in defaults.keys)
      key: TextEditingController(text: '${current[key] ?? defaults[key]}'),
  };
  String kind = '${current['kind'] ?? 'one_to_one'}',
      location = '${current['location_kind'] ?? 'video'}',
      color = '${current['color'] ?? '#72D6EB'}';
  final ownTeams = teams.where((t) => t['is_owner'] == true).toList();
  String routing = '${current['routing_mode'] ?? 'single'}';
  String teamId = ownTeams.any((t) => t['id'] == current['team_id'])
      ? '${current['team_id']}'
      : '';
  final selectedHosts = Set<String>.from(
    (current['host_ids'] as List? ?? []).map((x) => '$x'),
  );
  final merchantReady = connections.any(
    (c) =>
        c['provider'] == 'stripe' &&
        c['state'] == 'connected' &&
        c['enabled'] == true &&
        c['charges_enabled'] == true,
  );
  final questions = schedulingItems(current['questions'])
      .map(
        (q) => <String, dynamic>{
          ...q,
          'labelController': TextEditingController(text: '${q['label']}'),
          'optionsController': TextEditingController(
            text: (q['options'] as List? ?? []).join('\n'),
          ),
        },
      )
      .toList();
  final disposed = <TextEditingController>[];
  String? error;
  Widget input(
    String key,
    String label, {
    int lines = 1,
    String? helper,
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: TextField(
      controller: fields[key],
      maxLines: lines,
      keyboardType: number
          ? TextInputType.numberWithOptions(decimal: key == 'price')
          : null,
      decoration: InputDecoration(labelText: label, helperText: helper),
    ),
  );
  final result = await showDialog<SchedulingMap>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(
          current.isEmpty ? 'Create an event type' : 'Edit event type',
        ),
        content: SizedBox(
          width: 660,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Build the meeting guests can book. New event types stay private until you publish them.',
                ),
                input('title', 'Meeting title'),
                input('description', 'What is this meeting about?', lines: 3),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Meeting type'),
                  items: const [
                    DropdownMenuItem(
                      value: 'one_to_one',
                      child: Text('One-to-one'),
                    ),
                    DropdownMenuItem(
                      value: 'group',
                      child: Text('Group session'),
                    ),
                  ],
                  onChanged: (v) => update(() => kind = v!),
                ),
                input(
                  'duration_minutes',
                  'Duration (minutes)',
                  helper: '5–480 minutes, in five-minute steps',
                  number: true,
                ),
                if (kind == 'group')
                  input(
                    'capacity',
                    'Guests per session',
                    helper: 'Up to 100 guests; each books one seat',
                    number: true,
                  ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: location,
                  decoration: const InputDecoration(labelText: 'Location'),
                  items: const [
                    DropdownMenuItem(
                      value: 'video',
                      child: Text('Video meeting link'),
                    ),
                    DropdownMenuItem(value: 'phone', child: Text('Phone call')),
                    DropdownMenuItem(
                      value: 'in_person',
                      child: Text('In person'),
                    ),
                    DropdownMenuItem(
                      value: 'custom',
                      child: Text('Other / instructions'),
                    ),
                  ],
                  onChanged: (v) => update(() => location = v!),
                ),
                input(
                  'location_detail',
                  location == 'video'
                      ? 'Your HTTPS meeting link'
                      : 'Location details or instructions',
                  helper:
                      'Shown after booking. Video links are supplied by you.',
                ),
                const SizedBox(height: 20),
                Text(
                  'Protect your time',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                input(
                  'interval_minutes',
                  'Start-time spacing (minutes)',
                  helper: '5–120 minutes, in five-minute steps',
                  number: true,
                ),
                input(
                  'buffer_before',
                  'Buffer before each meeting (minutes)',
                  number: true,
                ),
                input(
                  'buffer_after',
                  'Buffer after each meeting (minutes)',
                  number: true,
                ),
                input(
                  'notice_minutes',
                  'Minimum booking notice (minutes)',
                  helper: '240 = 4 hours; 1440 = 1 day',
                  number: true,
                ),
                input(
                  'horizon_days',
                  'How far ahead can guests book? (days)',
                  helper: '1–365 days',
                  number: true,
                ),
                input(
                  'daily_limit',
                  'Maximum sessions per day',
                  helper: 'All KORLIX event types count toward this limit',
                  number: true,
                ),
                input(
                  'cancel_notice_minutes',
                  'Close online changes before start (minutes)',
                  helper: '60 = 1 hour; 0 allows changes until the start',
                  number: true,
                ),
                const SizedBox(height: 24),
                Text(
                  'Hosts and routing',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: routing,
                  decoration: const InputDecoration(
                    labelText: 'Assign appointments',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'single', child: Text('Only me')),
                    DropdownMenuItem(
                      value: 'round_robin',
                      child: Text('Round-robin · one available host'),
                    ),
                    DropdownMenuItem(
                      value: 'collective',
                      child: Text('Collective · all selected hosts'),
                    ),
                  ],
                  onChanged: (v) => update(() => routing = v!),
                ),
                if (routing != 'single') ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Team routing uses one-to-one event types. The event owner’s hours define the page’s booking hours; selected hosts must also be available.',
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey(teamId),
                    initialValue: teamId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Your team'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Choose a team'),
                      ),
                      for (final t in ownTeams)
                        DropdownMenuItem(
                          value: '${t['id']}',
                          child: Text(
                            '${t['name']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => update(() {
                      teamId = v!;
                      selectedHosts.clear();
                    }),
                  ),
                  for (final t in ownTeams.where((t) => t['id'] == teamId))
                    for (final m in schedulingItems(
                      t['members'],
                    ).where((m) => m['active'] == true))
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${m['name']}'),
                        subtitle: Text('${m['timezone']}'),
                        value: selectedHosts.contains(m['user_id']),
                        onChanged: (v) => update(() {
                          if (v == true) {
                            selectedHosts.add('${m['user_id']}');
                          } else {
                            selectedHosts.remove(m['user_id']);
                          }
                        }),
                      ),
                  if (ownTeams.isEmpty)
                    const Text(
                      'Create a team in the Teams tab and invite your hosts first.',
                    ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Booking payments',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                input(
                  'price',
                  'Price in USD',
                  number: true,
                  helper: '0.00 for free; paid bookings start at 0.50',
                ),
                input(
                  'refund_policy',
                  'Refund policy shown to guests',
                  lines: 3,
                ),
                const SizedBox(height: 10),
                Text(
                  merchantReady
                      ? 'Paid bookings reserve a slot during Stripe checkout and confirm only after verified payment. Guests pay your Stripe account. Cancellations do not automatically refund paid appointments; use the full refund action when appropriate.'
                      : 'Connect your Stripe business account in Connections before charging for bookings.',
                ),
                const SizedBox(height: 24),
                Text(
                  'Booking questions',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'Ask only what you need for the meeting. Avoid sensitive information.',
                ),
                for (final q in questions)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller:
                              q['labelController'] as TextEditingController,
                          maxLength: 200,
                          decoration: const InputDecoration(
                            labelText: 'Question',
                          ),
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: '${q['kind']}',
                          items: const [
                            DropdownMenuItem(
                              value: 'text',
                              child: Text('Written answer'),
                            ),
                            DropdownMenuItem(
                              value: 'choice',
                              child: Text('Choose one'),
                            ),
                          ],
                          onChanged: (v) => update(() => q['kind'] = v),
                        ),
                        if (q['kind'] == 'choice')
                          TextField(
                            controller:
                                q['optionsController'] as TextEditingController,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Choices · one per line',
                              helperText: '2–12 choices',
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: q['required'] == true,
                                onChanged: (v) =>
                                    update(() => q['required'] = v == true),
                                title: const Text('Required'),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove question',
                              onPressed: () => update(() {
                                disposed.addAll([
                                  q['labelController'] as TextEditingController,
                                  q['optionsController']
                                      as TextEditingController,
                                ]);
                                questions.remove(q);
                              }),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                TextButton.icon(
                  onPressed: questions.length >= 6
                      ? null
                      : () => update(
                          () => questions.add({
                            'id': 'q${DateTime.now().microsecondsSinceEpoch}',
                            'kind': 'text',
                            'required': false,
                            'labelController': TextEditingController(),
                            'optionsController': TextEditingController(),
                          }),
                        ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add a question'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: color,
                  decoration: const InputDecoration(labelText: 'Event accent'),
                  items: [
                    if (![
                      '#72D6EB',
                      '#B8A5F5',
                      '#9CD7B6',
                      '#EDC780',
                    ].contains(color))
                      DropdownMenuItem(
                        value: color,
                        child: const Text('Current color'),
                      ),
                    const DropdownMenuItem(
                      value: '#72D6EB',
                      child: Text('KORLIX cyan'),
                    ),
                    DropdownMenuItem(value: '#B8A5F5', child: Text('Lavender')),
                    DropdownMenuItem(value: '#9CD7B6', child: Text('Mint')),
                    DropdownMenuItem(value: '#EDC780', child: Text('Gold')),
                  ],
                  onChanged: (v) => update(() => color = v!),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              try {
                if (fields['title']!.text.trim().isEmpty) {
                  throw const FormatException('Enter a meeting title.');
                }
                final data = <String, dynamic>{
                  'revision': current['revision'] ?? 0,
                  'title': fields['title']!.text.trim(),
                  'description': fields['description']!.text.trim(),
                  'kind': kind,
                  'location_kind': location,
                  'location_detail': fields['location_detail']!.text.trim(),
                  'color': color,
                };
                for (final key in [
                  'duration_minutes',
                  'interval_minutes',
                  'buffer_before',
                  'buffer_after',
                  'notice_minutes',
                  'horizon_days',
                  'daily_limit',
                  'capacity',
                  'cancel_notice_minutes',
                ]) {
                  final n = int.tryParse(fields[key]!.text);
                  if (n == null) {
                    throw const FormatException(
                      'Enter whole numbers for meeting settings.',
                    );
                  }
                  data[key] = key == 'capacity' && kind == 'one_to_one' ? 1 : n;
                }
                if (routing != 'single' &&
                    (kind != 'one_to_one' ||
                        teamId.isEmpty ||
                        selectedHosts.isEmpty)) {
                  throw const FormatException(
                    'Choose a one-to-one event, your team, and at least one active host.',
                  );
                }
                final priceText = fields['price']!.text.trim();
                if (!RegExp(r'^\d{1,5}(\.\d{1,2})?$').hasMatch(priceText)) {
                  throw const FormatException(
                    'Enter a USD price with up to two decimal places.',
                  );
                }
                final parts = priceText.split('.');
                final cents =
                    int.parse(parts[0]) * 100 +
                    (parts.length == 2
                        ? int.parse(parts[1].padRight(2, '0'))
                        : 0);
                if (cents > 1000000 || (cents > 0 && cents < 50)) {
                  throw const FormatException(
                    r'Use a price from $0.50 to $10,000, or 0 for free.',
                  );
                }
                if (cents > 0 && !merchantReady) {
                  throw const FormatException(
                    'Connect your Stripe business account first.',
                  );
                }
                if (fields['refund_policy']!.text.trim().isEmpty ||
                    fields['refund_policy']!.text.length > 1000) {
                  throw const FormatException(
                    'Enter a refund policy of up to 1,000 characters.',
                  );
                }
                data.addAll({
                  'routing_mode': routing,
                  'team_id': routing == 'single' ? null : teamId,
                  'host_ids': routing == 'single'
                      ? <String>[]
                      : selectedHosts.toList(),
                  'price_cents': cents,
                  'currency': 'usd',
                  'refund_policy': fields['refund_policy']!.text.trim(),
                });
                data['questions'] = questions
                    .map(
                      (q) => {
                        'id': q['id'],
                        'label': (q['labelController'] as TextEditingController)
                            .text
                            .trim(),
                        'kind': q['kind'],
                        'required': q['required'] == true,
                        'options': q['kind'] == 'choice'
                            ? (q['optionsController'] as TextEditingController)
                                  .text
                                  .split('\n')
                                  .map((s) => s.trim())
                                  .where((s) => s.isNotEmpty)
                                  .toList()
                            : <String>[],
                      },
                    )
                    .toList();
                Navigator.pop(dialog, data);
              } on FormatException catch (e) {
                update(() => error = e.message);
              }
            },
            child: Text(current.isEmpty ? 'Create draft' : 'Save changes'),
          ),
        ],
      ),
    ),
  );
  Future<void>.delayed(const Duration(seconds: 1), () {
    for (final c in fields.values) {
      c.dispose();
    }
    for (final q in questions) {
      (q['labelController'] as TextEditingController).dispose();
      (q['optionsController'] as TextEditingController).dispose();
    }
    for (final c in disposed) {
      c.dispose();
    }
  });
  return result;
}
