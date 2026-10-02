import 'dart:convert';
import 'package:flutter/material.dart';
import 'fieldproof_client.dart';
import 'fieldproof_report.dart';

const fpPriorities = {
  'low': 'Low',
  'normal': 'Normal',
  'high': 'High',
  'urgent': 'Urgent',
};
const fpStages = {
  'planned': 'Planned',
  'in_progress': 'In progress',
  'blocked': 'Blocked',
  'ready': 'Ready for review',
};
const fpVoiceFields = {
  'title': 120,
  'customer': 160,
  'site': 350,
  'workOrder': 100,
  'technician': 120,
  'performedOn': 10,
  'assetId': 120,
  'oldAssetId': 120,
  'summary': 4000,
  'exceptions': 2000,
  'materials': 2000,
  'billingNotes': 2000,
  'hours': 20,
  'priority': 10,
  'stage': 20,
  'dueOn': 10,
};
String fpToday() => DateTime.now().toString().substring(0, 10);
Map<String, dynamic> fpClone(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
bool fpOverdue(Map<String, dynamic> job) {
  final due = fpText(fpMap(job['data'])['dueOn']);
  return job['state'] == 'active' &&
      due.isNotEmpty &&
      due.compareTo(fpToday()) < 0;
}

bool fpNeedsAttention(Map<String, dynamic> job) {
  final d = fpMap(job['data']);
  return job['state'] == 'active' &&
      (fpOverdue(job) ||
          d['stage'] == 'blocked' ||
          d['priority'] == 'urgent' ||
          fpRows(
            d['issues'],
          ).any((x) => x['blocking'] == true && x['resolved'] != true));
}

Map<String, dynamic> fpNewDraft(
  String template,
  Map<String, dynamic> defaults,
) => {
  'template': template,
  for (final field in fpVoiceFields.keys) field: '',
  'performedOn': fpToday(),
  'hours': null,
  'priority': 'normal',
  'stage': 'planned',
  'checks': fpRows(
    defaults['checks'],
  ).map((x) => {...x, 'done': false}).toList(),
  'requiredTags': List<String>.from(defaults['requiredTags'] as List? ?? []),
  'requiresApproval': defaults['requiresApproval'] == true,
  'readings': <Map<String, dynamic>>[],
  'issues': <Map<String, dynamic>>[],
};
Map<String, dynamic> fpRepeatDraft(Map<String, dynamic> data) {
  final title = fpText(data['title']);
  return {
    ...fpClone(data),
    'title':
        '${title.length > 100 ? title.substring(0, 100) : title} — follow-up',
    'workOrder': '',
    'performedOn': fpToday(),
    'dueOn': '',
    'priority': 'normal',
    'stage': 'planned',
    'summary': '',
    'exceptions': '',
    'hours': null,
    'materials': '',
    'billingNotes': '',
    'checks': fpRows(data['checks']).map((x) => {...x, 'done': false}).toList(),
    'readings': <Map<String, dynamic>>[],
    'issues': <Map<String, dynamic>>[],
  };
}

class FieldProofRecordsEditor extends StatelessWidget {
  const FieldProofRecordsEditor({
    super.key,
    required this.readings,
    required this.issues,
    required this.onChanged,
    this.enabled = true,
    this.onDialogChanged,
  });
  final List<Map<String, dynamic>> readings, issues;
  final Future<void> Function(
    List<Map<String, dynamic>>,
    List<Map<String, dynamic>>,
  )
  onChanged;
  final bool enabled;
  final ValueChanged<bool>? onDialogChanged;
  Future<void> _edit(
    BuildContext context,
    bool reading, [
    Map<String, dynamic>? row,
  ]) async {
    onDialogChanged?.call(true);
    try {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _RecordDialog(reading: reading, initial: row),
      );
      if (result == null || !context.mounted) return;
      final list = [...(reading ? readings : issues)];
      final index = list.indexWhere((x) => x['id'] == result['id']);
      if (index < 0) {
        list.add(result);
      } else {
        list[index] = result;
      }
      await onChanged(reading ? list : readings, reading ? issues : list);
    } finally {
      onDialogChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Readings & measurements',
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text('Record values exactly as measured, with units and context.'),
      for (final row in readings)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row['label']}: ${row['value']} ${row['unit'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (fpText(row['note']).isNotEmpty) Text(fpText(row['note'])),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: enabled
                          ? () => _edit(context, true, row)
                          : null,
                      child: const Text('Edit reading'),
                    ),
                    TextButton(
                      onPressed: enabled
                          ? () => onChanged(
                              readings
                                  .where((x) => x['id'] != row['id'])
                                  .toList(),
                              issues,
                            )
                          : null,
                      child: const Text('Remove reading'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      OutlinedButton.icon(
        key: const Key('fp-add-reading'),
        onPressed: enabled && readings.length < 20
            ? () => _edit(context, true)
            : null,
        icon: const Icon(Icons.speed_outlined),
        label: const Text('Add reading'),
      ),
      const SizedBox(height: 24),
      const Text(
        'Punch list & follow-up',
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text(
        'Blocking items must be resolved before closeout. Assigning a name here does not notify anyone.',
      ),
      for (final row in issues)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(fpText(row['label'])),
                  value: row['resolved'] == true,
                  onChanged: enabled
                      ? (v) => onChanged(
                          readings,
                          issues
                              .map(
                                (x) => x['id'] == row['id']
                                    ? {...x, 'resolved': v == true}
                                    : x,
                              )
                              .toList(),
                        )
                      : null,
                  subtitle: Text(
                    [
                      fpPriorities[row['priority']] ?? 'Normal',
                      if (row['blocking'] == true) 'Blocks closeout',
                      if (fpText(row['assignee']).isNotEmpty)
                        'Owner: ${row['assignee']}',
                      if (fpText(row['dueOn']).isNotEmpty)
                        'Due: ${row['dueOn']}',
                    ].join(' · '),
                  ),
                ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: enabled
                          ? () => _edit(context, false, row)
                          : null,
                      child: const Text('Edit item'),
                    ),
                    TextButton(
                      onPressed: enabled
                          ? () => onChanged(
                              readings,
                              issues
                                  .where((x) => x['id'] != row['id'])
                                  .toList(),
                            )
                          : null,
                      child: const Text('Remove item'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      OutlinedButton.icon(
        key: const Key('fp-add-issue'),
        onPressed: enabled && issues.length < 16
            ? () => _edit(context, false)
            : null,
        icon: const Icon(Icons.playlist_add_check),
        label: const Text('Add follow-up item'),
      ),
    ],
  );
}

class _RecordDialog extends StatefulWidget {
  const _RecordDialog({required this.reading, this.initial});
  final bool reading;
  final Map<String, dynamic>? initial;
  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  final _form = GlobalKey<FormState>();
  late Map<String, TextEditingController> _c;
  late String _priority;
  late bool _blocking;
  @override
  void initState() {
    super.initState();
    _c = {
      for (final k in ['label', 'value', 'unit', 'note', 'assignee', 'dueOn'])
        k: TextEditingController(text: fpText(widget.initial?[k])),
    };
    _priority = widget.initial?['priority'] as String? ?? 'normal';
    _blocking = widget.initial?['blocking'] == true;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, {
      'id': widget.initial?['id'] ?? fieldProofRequestKey(),
      'label': _c['label']!.text.trim(),
      if (widget.reading) ...{
        'value': _c['value']!.text.trim(),
        'unit': _c['unit']!.text.trim(),
        'note': _c['note']!.text.trim(),
      } else ...{
        'assignee': _c['assignee']!.text.trim(),
        'dueOn': _c['dueOn']!.text.trim(),
        'priority': _priority,
        'blocking': _blocking,
        'resolved': widget.initial?['resolved'] == true,
      },
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.reading ? 'Record a reading' : 'Add a follow-up item'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry
                  in (widget.reading
                          ? {
                              'label': 'Reading label',
                              'value': 'Exact value',
                              'unit': 'Unit (optional)',
                              'note': 'Note (optional)',
                            }
                          : {
                              'label': 'Follow-up item',
                              'assignee': 'Responsible person (optional)',
                              'dueOn': 'Due date (YYYY-MM-DD)',
                            })
                      .entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    key: Key('fp-record-${entry.key}'),
                    controller: _c[entry.key],
                    maxLength: switch (entry.key) {
                      'label' => widget.reading ? 100 : 200,
                      'value' => 160,
                      'unit' => 40,
                      'note' => 350,
                      'dueOn' => 10,
                      _ => 100,
                    },
                    decoration: InputDecoration(labelText: entry.value),
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (['label', 'value'].contains(entry.key) && s.isEmpty) {
                        return 'Enter ${entry.value.toLowerCase()}.';
                      }
                      if (entry.key == 'dueOn' &&
                          s.isNotEmpty &&
                          (DateTime.tryParse(s)?.toString().substring(0, 10) !=
                                  s ||
                              !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s))) {
                        return 'Use a valid YYYY-MM-DD date.';
                      }
                      return null;
                    },
                  ),
                ),
              if (!widget.reading) ...[
                DropdownButtonFormField<String>(
                  initialValue: _priority,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: fpPriorities.entries
                      .map(
                        (x) => DropdownMenuItem(
                          value: x.key,
                          child: Text(x.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _priority = v ?? 'normal'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Must resolve before closeout'),
                  value: _blocking,
                  onChanged: (v) => setState(() => _blocking = v == true),
                ),
              ],
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
        key: const Key('fp-record-save'),
        onPressed: _save,
        child: const Text('Use entry'),
      ),
    ],
  );
}
