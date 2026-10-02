import 'package:flutter/material.dart';
import 'workforce_client.dart';
import 'workforce_style.dart';

const wfIndustries = {
  'general': 'General business',
  'construction': 'Construction & trades',
  'field_service': 'Field services',
  'retail': 'Retail',
  'hospitality': 'Hospitality & food',
  'healthcare': 'Care & support services',
  'logistics': 'Logistics & delivery',
  'professional': 'Professional services',
  'technology': 'Technology & remote teams',
  'education': 'Education & training',
  'nonprofit': 'Nonprofit & volunteers',
  'events': 'Events & creative teams',
};
const wfWorkModes = {
  'onsite': 'On site',
  'field': 'Field based',
  'remote': 'Remote',
  'hybrid': 'Hybrid',
};
const wfMemberKinds = {
  'employee': 'Employee',
  'contractor': 'Contractor',
  'freelancer': 'Freelancer',
  'volunteer': 'Volunteer',
  'partner': 'Partner',
};
const wfTaskPriorities = {
  'low': 'Low',
  'normal': 'Normal',
  'high': 'High',
  'urgent': 'Urgent',
};
const wfTaskStates = {
  'todo': 'To do',
  'in_progress': 'In progress',
  'blocked': 'Blocked',
  'done': 'Done',
  'cancelled': 'Cancelled',
};
String wfLocalInput(dynamic value) =>
    DateTime.tryParse(
      value?.toString() ?? '',
    )?.toLocal().toIso8601String().substring(0, 16) ??
    '';

class WorkforceTaskBoard extends StatefulWidget {
  const WorkforceTaskBoard({
    super.key,
    required this.tasks,
    required this.members,
    required this.userId,
    required this.canManage,
    required this.canWrite,
    required this.onCreate,
    required this.onEdit,
    required this.onProgress,
    this.truncated = false,
  });
  final List<WfJson> tasks, members;
  final String userId;
  final bool canManage, canWrite, truncated;
  final VoidCallback onCreate;
  final void Function(WfJson) onEdit, onProgress;
  @override
  State<WorkforceTaskBoard> createState() => _WorkforceTaskBoardState();
}

class _WorkforceTaskBoardState extends State<WorkforceTaskBoard> {
  String _query = '', _status = 'open';
  bool _mine = false;
  String _name(dynamic id) =>
      widget.members
          .where((m) => m['user_id'] == id)
          .firstOrNull?['display_name']
          ?.toString() ??
      'Team member';
  bool _overdue(WfJson t) =>
      !['done', 'cancelled'].contains(t['status']) &&
      (DateTime.tryParse(
            t['due_at']?.toString() ?? '',
          )?.isBefore(DateTime.now()) ??
          false);
  @override
  Widget build(BuildContext context) {
    final tasks = widget.tasks
        .where(
          (t) =>
              (!_mine || t['assignee_id'] == widget.userId) &&
              (_status == 'all' ||
                  _status == 'open' &&
                      !['done', 'cancelled'].contains(t['status']) ||
                  t['status'] == _status) &&
              [
                'title',
                'details',
                'project',
                'worksite',
              ].any((k) => '${t[k] ?? ''}'.toLowerCase().contains(_query)),
        )
        .toList();
    tasks.sort((a, b) {
      final ac = ['done', 'cancelled'].contains(a['status']),
          bc = ['done', 'cancelled'].contains(b['status']);
      if (ac != bc) return ac ? 1 : -1;
      final priority = {'urgent': 0, 'high': 1, 'normal': 2, 'low': 3};
      final rank =
          (priority[a['priority']] ?? 2) - (priority[b['priority']] ?? 2);
      if (rank != 0) return rank;
      return '${a['due_at'] ?? '9999'}'.compareTo('${b['due_at'] ?? '9999'}');
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Work board', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text(
          'Plan work across projects, sites and teams. Tasks do not require an active shift.',
          style: TextStyle(color: WfStyle.muted),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: widget.canWrite ? widget.onCreate : null,
              icon: const Icon(Icons.add_task),
              label: Text(widget.canManage ? 'Assign task' : 'Add my task'),
            ),
            if (widget.canManage)
              FilterChip(
                label: const Text('Assigned to me'),
                selected: _mine,
                onSelected: (v) => setState(() => _mine = v),
              ),
            for (final e in {
              'open': 'Open',
              'all': 'All',
              ...wfTaskStates,
            }.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _status == e.key,
                onSelected: (_) => setState(() => _status = e.key),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          decoration: const InputDecoration(
            labelText: 'Search tasks, projects or sites',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        if (widget.truncated)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Showing the 500 most recently updated tasks. Older tasks are not included in these filters.',
              style: TextStyle(color: WfStyle.gold),
            ),
          ),
        if (tasks.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No matching tasks. Add an assignment to get started.',
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth >= 1100
                ? (box.maxWidth - 24) / 3
                : box.maxWidth >= 700
                ? (box.maxWidth - 12) / 2
                : box.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final t in tasks)
                  SizedBox(width: width, child: _taskCard(t)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _taskCard(WfJson t) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              WfBadge(
                wfTaskStates[t['status']] ?? 'To do',
                color: t['status'] == 'blocked' ? WfStyle.gold : WfStyle.cyan,
              ),
              WfBadge(
                wfTaskPriorities[t['priority']] ?? 'Normal',
                color: t['priority'] == 'urgent'
                    ? WfStyle.danger
                    : WfStyle.violet,
              ),
              if (_overdue(t)) const WfBadge('Overdue', color: WfStyle.danger),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${t['title']}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '${_name(t['assignee_id'])}${t['project'] != '' && t['project'] != null ? ' · ${t['project']}' : ''}${t['worksite'] != '' && t['worksite'] != null ? ' · ${t['worksite']}' : ''}',
            style: const TextStyle(color: WfStyle.muted),
          ),
          if (t['due_at'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Due ${wfLocalInput(t['due_at']).replaceFirst('T', ' ')} · device local time',
              ),
            ),
          if ('${t['details'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(t['details']),
            ),
          if ('${t['progress_note'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Latest progress: ${t['progress_note']}'),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (widget.canWrite &&
                  (widget.canManage || t['status'] != 'cancelled'))
                OutlinedButton.icon(
                  onPressed: () => widget.onProgress(t),
                  icon: const Icon(Icons.update),
                  label: const Text('Update progress'),
                ),
              if (widget.canManage && widget.canWrite)
                TextButton.icon(
                  onPressed: () => widget.onEdit(t),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit assignment'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
