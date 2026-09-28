import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../bookkeeping/bookkeeping_file_save.dart';
import 'agent_studio_client.dart';
import 'agent_studio_design.dart';
import 'korlix_live_convo_agent.dart';

String workflowStatus(String s) => switch (s) {
  'review' => 'Needs review',
  'running' => 'Agent working',
  'ready' => 'Ready to run',
  'completed' => 'Completed',
  'paused' => 'Paused',
  'cancelled' => 'Cancelled',
  'failed' => 'Needs retry',
  _ => s,
};

class AgentStudioWorkflows extends StatefulWidget {
  const AgentStudioWorkflows({
    super.key,
    required this.client,
    required this.agents,
    this.leadAgent,
    this.onLeadConsumed,
  });
  final KorlixLiveConvoAgent? leadAgent;
  final VoidCallback? onLeadConsumed;
  final AgentStudioClient client;
  final List<KorlixLiveConvoAgent> agents;
  @override
  State<AgentStudioWorkflows> createState() => _AgentStudioWorkflowsState();
}

class _AgentStudioWorkflowsState extends State<AgentStudioWorkflows> {
  List<Map<String, dynamic>> _workflows = [];
  Map<String, dynamic>? _selected;
  Map<String, dynamic>? _pendingCreate;
  String? _error, _runKey, _keyScope;
  String _filter = 'All', _query = '';
  bool _busy = false, _loading = true, _polling = false, _locked = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
    if (widget.leadAgent != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final a = widget.leadAgent!;
        widget.onLeadConsumed?.call();
        unawaited(
          _create({
            'title': '${a.name} workflow',
            'new_plan': true,
            'objective': '',
            'priority': 'normal',
            'use_memory': false,
            'steps': [
              {
                'agent_id': a.id,
                'title': 'Prepare the deliverable',
                'instruction':
                    'Use the objective and provided context to prepare a complete written deliverable. Identify assumptions and any missing information.',
              },
              {
                'agent_id': 'general',
                'title': 'Review and refine',
                'instruction':
                    'Review the approved deliverable for accuracy, clarity, and completeness. Provide an improved final version and remaining questions.',
              },
            ],
          }),
        );
      });
    }
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!widget.client.current) {
        _lock();
        return;
      }
      if (_selected?['state'] == 'running' && !_busy && !_polling) {
        unawaited(_load(silent: true));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _lock() {
    if (mounted && !_locked) {
      setState(() {
        _locked = true;
        _workflows = [];
        _selected = null;
        _error = 'Your account changed. Close and reopen Agent Studio.';
      });
    }
  }

  void _setError(Object e) {
    if (e is AgentStudioException && e.status == 401) {
      _lock();
      return;
    }
    if (mounted) setState(() => _error = e.toString());
  }

  Future<void> _load({bool silent = false}) async {
    if (_polling || _locked) return;
    _polling = true;
    final id = _selected?['id'];
    if (!silent) setState(() => _loading = true);
    try {
      final list = await widget.client.list();
      final detail = id == null ? null : await widget.client.get(id);
      if (!mounted || _locked) return;
      setState(() {
        _workflows = list;
        if (id == _selected?['id'] &&
            detail != null &&
            detail['revision'] >= (_selected?['revision'] ?? 0)) {
          _selected = detail;
        }
        _error = null;
      });
    } catch (e) {
      _setError(e);
    } finally {
      _polling = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(String id) async {
    if (_busy || _locked) return;
    setState(() => _busy = true);
    try {
      final w = await widget.client.get(id);
      if (mounted && !_locked) {
        setState(() {
          _selected = w;
          _error = null;
        });
      }
    } catch (e) {
      _setError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String label) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep workflow'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(label),
            ),
          ],
        ),
      ) ==
      true;
  Future<void> _action(String action) async {
    if (_busy || _locked || _selected == null) return;
    final w = Map<String, dynamic>.from(_selected!);
    String? feedback;
    if (action == 'cancel' &&
        !await _confirm(
          'Cancel this workflow?',
          'Saved results remain available. Any running result will be discarded and its generation credit returned.',
          'Cancel workflow',
        )) {
      return;
    }
    if (!mounted) return;
    if (action == 'delete' &&
        !await _confirm(
          'Delete this workflow?',
          'This removes the workflow, saved results, and activity history.',
          'Delete workflow',
        )) {
      return;
    }
    if (!mounted) return;
    if (action == 'revise') {
      final controller = TextEditingController();
      feedback = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Request changes'),
          content: TextField(
            controller: controller,
            maxLength: 2000,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'What should this agent improve?',
              alignLabelWithHint: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(c, controller.text.trim());
                }
              },
              child: const Text('Save feedback'),
            ),
          ],
        ),
      );
      // Dialog's route may still be animating as its result is delivered.
      Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
      if (feedback == null || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      Map<String, dynamic> result;
      if (action == 'run') {
        final scope = '${w['id']}:${w['revision']}';
        if (scope != _keyScope) {
          _keyScope = scope;
          _runKey = agentStudioKey();
        }
        result = await widget.client.run(w, _runKey!);
      } else {
        result = await widget.client.act(w, action, feedback: feedback);
      }
      if (!mounted || _locked) return;
      setState(() => _selected = result['deleted'] == true ? null : result);
      await _load(silent: true);
    } catch (e) {
      _setError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create([Map<String, dynamic>? recipe]) async {
    if (_busy || _locked) return;
    final plan = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _WorkflowComposer(agents: widget.agents, recipe: recipe),
    );
    if (plan == null || !mounted) return;
    _pendingCreate = plan;
    await _savePendingPlan();
  }

  Future<void> _savePendingPlan() async {
    if (_busy || _locked || _pendingCreate == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final w = await widget.client.create(_pendingCreate!);
      if (mounted && !_locked) {
        setState(() {
          _selected = w;
          _pendingCreate = null;
        });
      }
      await _load(silent: true);
    } catch (e) {
      _setError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _name(String id) =>
      widget.agents.where((a) => a.id == id).firstOrNull?.name ??
      id.replaceAll('_', ' ');
  String _date(Object? value) {
    final d = DateTime.tryParse('$value')?.toLocal();
    if (d == null) return '';
    return '${d.month}/${d.day} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Color _statusColor(String s, AgentStudioColors p) => switch (s) {
    'review' => p.dark ? const Color(0xFFFFCE84) : const Color(0xFF885B08),
    'completed' => p.dark ? const Color(0xFF8BE1B7) : const Color(0xFF25714C),
    'failed' => p.dark ? const Color(0xFFFFADB4) : const Color(0xFFA03442),
    _ => p.cyan,
  };
  Future<void> _export() async {
    final w = _selected;
    if (w == null) return;
    final steps = (w['steps'] as List)
        .map((s) => Map<String, dynamic>.from(s))
        .toList();
    final text =
        '${w['title']}\nKORLIX Agent Studio\nStatus: ${workflowStatus(w['state'])}\n\n${w['objective']}\n\n${steps.asMap().entries.map((e) => 'STEP ${e.key + 1}: ${e.value['title']}\nAgent: ${_name(e.value['agent_id'])}\nStatus: ${e.value['status']}\n${e.value['output'] ?? 'No result yet.'}\n').join('\n')}\nAI-generated written work. Approval is user-reported. No external actions were executed.\n';
    try {
      widget.client.guard();
      final box = context.findRenderObject() as RenderBox?;
      await saveBookkeepingFile(
        Uint8List.fromList(utf8.encode(text)),
        'KORLIX-Workflow-${w['id']}.txt',
        'text/plain',
        box == null
            ? const Rect.fromLTWH(0, 0, 100, 100)
            : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (e) {
      _setError(e);
    }
  }

  Widget _button(
    String action,
    String label,
    IconData icon, {
    bool primary = false,
  }) => primary
      ? FilledButton.icon(
          onPressed: _busy ? null : () => _action(action),
          icon: Icon(icon, size: 18),
          label: Text(label),
        )
      : OutlinedButton.icon(
          onPressed: _busy ? null : () => _action(action),
          icon: Icon(icon, size: 18),
          label: Text(label),
        );
  Widget _list(AgentStudioColors p) {
    final items = _workflows
        .where(
          (w) =>
              (_filter == 'All' ||
                  (_filter == 'Needs review' && w['state'] == 'review') ||
                  (_filter == 'Active' &&
                      !['completed', 'cancelled'].contains(w['state'])) ||
                  (_filter == 'Completed' && w['state'] == 'completed')) &&
              '${w['title']}'.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AgentStudioPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AgentStudioPill(
                'ORCHESTRATION',
                icon: Icons.account_tree_outlined,
                color: p.cyan,
              ),
              const SizedBox(height: 15),
              Text(
                'One goal. The right agents.',
                style: TextStyle(
                  color: p.text,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Build a sequence for planning, writing, analysis, and review. Approve each result before it becomes the next agent’s context.',
                style: TextStyle(color: p.muted, height: 1.55, fontSize: 14),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy || widget.agents.isEmpty
                    ? null
                    : () => _create(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New workflow'),
              ),
              const SizedBox(height: 10),
              Text(
                'Each run uses 1 generation credit. Workflows produce written results; connected actions remain in their own tools.',
                style: TextStyle(color: p.muted, fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        Row(
          children: [
            Expanded(
              child: Text(
                'Your workflows',
                style: TextStyle(
                  color: p.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Refresh workflows',
              onPressed: _busy ? null : () => _load(),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: (s) => setState(() => _query = s),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Search workflows',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final f in ['All', 'Active', 'Needs review', 'Completed'])
              ChoiceChip(
                label: Text(f),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (items.isEmpty && !_loading)
          AgentStudioPanel(
            child: Column(
              children: [
                Icon(Icons.route_outlined, size: 42, color: p.cyan),
                const SizedBox(height: 15),
                Text(
                  _workflows.isEmpty
                      ? 'Your next big idea starts here.'
                      : 'No matching workflows.',
                  style: TextStyle(color: p.text, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose a template or build your own sequence.',
                  style: TextStyle(color: p.muted),
                ),
              ],
            ),
          ),
        for (final w in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AgentStudioPanel(
              padding: const EdgeInsets.all(16),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: _busy ? null : () => _open(w['id']),
                title: Text(
                  w['title'],
                  style: TextStyle(color: p.text, fontWeight: FontWeight.w700),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AgentStudioPill(
                        workflowStatus(w['state']),
                        color: _statusColor(w['state'], p),
                      ),
                      AgentStudioPill(
                        '${w['cursor']} / ${w['step_count']} approved',
                        color: p.muted,
                      ),
                      if (w['priority'] != 'normal')
                        AgentStudioPill(
                          '${w['priority']} priority',
                          color: p.muted,
                        ),
                    ],
                  ),
                ),
                trailing: Icon(Icons.arrow_forward_rounded, color: p.cyan),
              ),
            ),
          ),
      ],
    );
  }

  Widget _detail(AgentStudioColors p) {
    final w = _selected!,
        steps = (w['steps'] as List)
            .map((s) => Map<String, dynamic>.from(s))
            .toList(),
        cursor = w['cursor'] as int,
        state = w['state'] as String;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : () => setState(() => _selected = null),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('All workflows'),
          ),
        ),
        const SizedBox(height: 10),
        AgentStudioPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AgentStudioPill(
                    workflowStatus(state),
                    color: _statusColor(state, p),
                    icon: state == 'running'
                        ? Icons.graphic_eq_rounded
                        : Icons.route_rounded,
                  ),
                  AgentStudioPill('${w['priority']} priority', color: p.muted),
                ],
              ),
              const SizedBox(height: 15),
              Text(
                w['title'],
                style: TextStyle(
                  color: p.text,
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.7,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                w['objective'],
                style: TextStyle(color: p.muted, height: 1.6),
              ),
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: cursor / steps.length,
                borderRadius: BorderRadius.circular(6),
                minHeight: 6,
              ),
              const SizedBox(height: 8),
              Text(
                '$cursor of ${steps.length} steps approved',
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (['ready', 'failed'].contains(state))
                    _button(
                      'run',
                      state == 'failed'
                          ? 'Retry step · 1 credit'
                          : 'Run next step · 1 credit',
                      Icons.play_arrow_rounded,
                      primary: true,
                    ),
                  if (state == 'review') ...[
                    _button(
                      'approve',
                      cursor == steps.length - 1
                          ? 'Approve & finish'
                          : 'Approve & hand off',
                      Icons.check_rounded,
                      primary: true,
                    ),
                    _button(
                      'revise',
                      'Request changes',
                      Icons.edit_note_rounded,
                    ),
                  ],
                  if (['ready', 'review', 'failed'].contains(state))
                    _button('pause', 'Pause', Icons.pause_rounded),
                  if (state == 'paused')
                    _button(
                      'resume',
                      'Resume',
                      Icons.play_arrow_rounded,
                      primary: true,
                    ),
                  if (!['completed', 'cancelled'].contains(state))
                    _button(
                      'cancel',
                      'Cancel workflow',
                      Icons.stop_circle_outlined,
                    ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _create(w),
                    icon: const Icon(Icons.copy_all_rounded, size: 18),
                    label: const Text('Reuse sequence'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _export,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Export results'),
                  ),
                  if (['completed', 'cancelled'].contains(state))
                    _button('delete', 'Delete', Icons.delete_outline_rounded),
                ],
              ),
              if (state == 'running') ...[
                const SizedBox(height: 15),
                const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 10),
                Text(
                  'The assigned agent is working. You can leave this view and return to the saved result.',
                  style: TextStyle(color: p.muted, fontSize: 12, height: 1.5),
                ),
              ],
              if (state == 'review') ...[
                const SizedBox(height: 14),
                Text(
                  'Review the result below. Approval shares this result with later steps. The next step runs when you choose Run next step.',
                  style: TextStyle(color: p.muted, fontSize: 12, height: 1.5),
                ),
              ],
              if (state == 'failed') ...[
                const SizedBox(height: 14),
                Text(
                  'This step did not finish. Its generation credit was returned. Retry when ready.',
                  style: TextStyle(color: p.muted, fontSize: 12, height: 1.5),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                w['use_memory'] == true
                    ? 'Agent memory: enabled · sensitive records excluded'
                    : 'Agent memory: off · published training still applies',
                style: TextStyle(color: p.muted, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'The handoff sequence',
          style: TextStyle(
            color: p.text,
            fontWeight: FontWeight.w700,
            fontSize: 21,
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AgentStudioPanel(
              accent: i == cursor ? p.cyan : null,
              padding: const EdgeInsets.all(15),
              child: ExpansionTile(
                key: ValueKey('${w['id']}:$i:${steps[i]['status']}'),
                initiallyExpanded:
                    i == cursor ||
                    state == 'completed' && i == steps.length - 1,
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 12, bottom: 8),
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: p.raised,
                  child: steps[i]['status'] == 'approved'
                      ? Icon(Icons.check_rounded, color: p.cyan, size: 19)
                      : Text(
                          '${i + 1}',
                          style: TextStyle(color: p.cyan, fontSize: 13),
                        ),
                ),
                title: Text(
                  steps[i]['title'],
                  style: TextStyle(color: p.text, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${_name(steps[i]['agent_id'])} · ${steps[i]['status']}',
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        steps[i]['instruction'],
                        style: TextStyle(color: p.muted, height: 1.5),
                      ),
                      if (steps[i]['feedback'] != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Requested changes: ${steps[i]['feedback']}',
                          style: TextStyle(color: p.cyan, height: 1.5),
                        ),
                      ],
                      if (steps[i]['output'] != null) ...[
                        const SizedBox(height: 18),
                        const Divider(),
                        const SizedBox(height: 12),
                        SelectableText(
                          steps[i]['output'],
                          style: TextStyle(
                            color: p.text,
                            height: 1.65,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            AgentStudioPill(
                              'Training v${steps[i]['agent_version'] ?? 0}',
                              color: p.muted,
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                try {
                                  widget.client.guard();
                                  await Clipboard.setData(
                                    ClipboardData(text: steps[i]['output']),
                                  );
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Result copied'),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  _setError(e);
                                }
                              },
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('Copy result'),
                            ),
                          ],
                        ),
                      ],
                      if (steps[i]['output'] == null) ...[
                        const SizedBox(height: 12),
                        Text(
                          i > cursor
                              ? 'Waiting for earlier steps to be approved.'
                              : 'No result yet.',
                          style: TextStyle(color: p.muted, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        AgentStudioPanel(
          padding: const EdgeInsets.all(16),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Activity history'),
            subtitle: Text('Created ${_date(w['created_at'])}'),
            children: [
              for (final e in (w['events'] as List).reversed.take(30))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.commit_rounded, color: p.cyan),
                  title: Text('${e['type']}'.replaceAll('_', ' ')),
                  subtitle: Text(
                    '${e['step'] != null ? 'Step ${(e['step'] as int) + 1} · ' : ''}${_date(e['at'])}',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AgentStudioColors(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        30 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [
        if (_loading || _busy) ...[
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 12),
        ],
        if (_error != null) ...[
          AgentStudioPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_error!, style: TextStyle(color: p.text)),
                if (!_locked && _pendingCreate != null)
                  FilledButton(
                    onPressed: _busy ? null : _savePendingPlan,
                    child: const Text('Retry saving workflow'),
                  ),
                if (!_locked)
                  TextButton(
                    onPressed: () => _load(),
                    child: const Text('Refresh status'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (!_locked)
          if (_selected == null) _list(p) else _detail(p),
      ],
    );
  }
}

class _StepDraft {
  _StepDraft({required this.agent, String title = '', String instruction = ''})
    : title = TextEditingController(text: title),
      instruction = TextEditingController(text: instruction);
  String agent;
  final TextEditingController title, instruction;
  void dispose() {
    title.dispose();
    instruction.dispose();
  }
}

class _WorkflowComposer extends StatefulWidget {
  const _WorkflowComposer({required this.agents, this.recipe});
  final List<KorlixLiveConvoAgent> agents;
  final Map<String, dynamic>? recipe;
  @override
  State<_WorkflowComposer> createState() => _WorkflowComposerState();
}

class _WorkflowComposerState extends State<_WorkflowComposer> {
  final _title = TextEditingController(), _objective = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  String? _validation;
  final List<_StepDraft> _steps = [];
  String _priority = 'normal', _template = 'Plan · create · review';
  bool _memory = false;
  String _agent(String id) =>
      widget.agents.any((a) => a.id == id) ? id : widget.agents.first.id;
  @override
  void initState() {
    super.initState();
    final r = widget.recipe;
    if (r != null) {
      final reusedTitle = r['new_plan'] == true
          ? '${r['title']}'
          : '${r['title']} — new run';
      _title.text = reusedTitle.length > 120
          ? reusedTitle.substring(0, 120)
          : reusedTitle;
      _objective.text = r['objective'];
      _priority = r['priority'];
      _memory = r['use_memory'] == true;
      for (final s in r['steps']) {
        _steps.add(
          _StepDraft(
            agent: _agent(s['agent_id']),
            title: s['title'],
            instruction: s['instruction'],
          ),
        );
      }
    } else {
      _applyTemplate(_template);
    }
  }

  void _applyTemplate(String value) {
    for (final s in _steps) {
      s.dispose();
    }
    _steps.clear();
    _template = value;
    final recipes = <String, List<List<String>>>{
      'Plan · create · review': [
        [
          'my_assistant',
          'Plan the work',
          'Turn the objective into a practical outline with assumptions and needed inputs.',
        ],
        [
          'doc_wizard',
          'Create a draft',
          'Use the approved plan to write a complete, useful draft.',
        ],
        [
          'general',
          'Review & refine',
          'Review the approved draft for completeness and unsupported claims. Return a refined final version and open questions.',
        ],
      ],
      'Creative brief': [
        [
          'my_assistant',
          'Define the brief',
          'Build a clear creative brief: audience, objective, message, and constraints.',
        ],
        [
          'graphic_designer',
          'Develop direction',
          'Propose a detailed visual direction and image prompts based on the approved brief.',
        ],
        [
          'general',
          'Quality review',
          'Check alignment with the brief and produce the final creative recommendations.',
        ],
      ],
      'Learning session': [
        [
          'language_teacher',
          'Design a lesson',
          'Create a lesson plan tailored to the learning objective.',
        ],
        [
          'language_teacher',
          'Practice & feedback',
          'Use the approved plan to create exercises, examples, and an answer guide.',
        ],
      ],
      'Blank sequence': [
        ['general', '', ''],
      ],
    };
    for (final r in recipes[value]!) {
      _steps.add(
        _StepDraft(agent: _agent(r[0]), title: r[1], instruction: r[2]),
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _title.dispose();
    _objective.dispose();
    for (final s in _steps) {
      s.dispose();
    }
    super.dispose();
  }

  String? _required(String? s) =>
      s?.trim().isNotEmpty == true ? null : 'Enter a value.';
  void _save() {
    final fields = [
      _title.text,
      _objective.text,
      for (final s in _steps) ...[s.title.text, s.instruction.text],
    ];
    if (fields.any((s) => s.trim().isEmpty)) {
      setState(
        () => _validation =
            'Add a workflow name, objective, and instructions for every step.',
      );
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, {
      'id': agentStudioKey(),
      'title': _title.text.trim(),
      'objective': _objective.text.trim(),
      'priority': _priority,
      'use_memory': _memory,
      'steps': _steps
          .map(
            (s) => {
              'agent_id': s.agent,
              'title': s.title.text.trim(),
              'instruction': s.instruction.text.trim(),
            },
          )
          .toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = AgentStudioColors(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 880,
        maxHeight: MediaQuery.sizeOf(context).height * .94,
      ),
      child: Form(
        key: _form,
        child: ListView(
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            22,
            22,
            22,
            26 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Design a workflow',
                    style: TextStyle(
                      color: p.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 25,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close workflow builder',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            if (_validation != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _validation!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              'Assign up to eight steps. Each approved result becomes context for the next agent.',
              style: TextStyle(color: p.muted, height: 1.5),
            ),
            const SizedBox(height: 20),
            if (widget.recipe == null) ...[
              DropdownButtonFormField<String>(
                initialValue: _template,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Start with a template',
                ),
                items: [
                  for (final t in [
                    'Plan · create · review',
                    'Creative brief',
                    'Learning session',
                    'Blank sequence',
                  ])
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (s) {
                  if (s != null) setState(() => _applyTemplate(s));
                },
              ),
              const SizedBox(height: 18),
            ],
            TextFormField(
              controller: _title,
              maxLength: 120,
              validator: _required,
              decoration: const InputDecoration(
                labelText: 'Workflow name',
                hintText: 'e.g. Launch our new product',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _objective,
              maxLength: 6000,
              maxLines: 4,
              validator: _required,
              decoration: const InputDecoration(
                labelText: 'What should the team achieve?',
                alignLabelWithHint: true,
                hintText:
                    'Describe the outcome, audience, facts, and constraints.',
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: [
                for (final s in ['normal', 'high', 'low'])
                  DropdownMenuItem(
                    value: s,
                    child: Text('${s[0].toUpperCase()}${s.substring(1)}'),
                  ),
              ],
              onChanged: (s) => setState(() => _priority = s!),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _memory,
              onChanged: (v) => setState(() => _memory = v),
              title: const Text('Use approved agent memories'),
              subtitle: const Text(
                'Each agent uses its own non-sensitive records. Memory-derived information may appear in results you approve for handoff. Published training always applies.',
              ),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < _steps.length; i++)
              Padding(
                key: ObjectKey(_steps[i]),
                padding: const EdgeInsets.only(bottom: 16),
                child: AgentStudioPanel(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'STEP ${i + 1}',
                              style: TextStyle(
                                color: p.cyan,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Move step ${i + 1} up',
                            onPressed: i == 0
                                ? null
                                : () => setState(() {
                                    final s = _steps.removeAt(i);
                                    _steps.insert(i - 1, s);
                                  }),
                            icon: const Icon(
                              Icons.arrow_upward_rounded,
                              size: 18,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Move step ${i + 1} down',
                            onPressed: i == _steps.length - 1
                                ? null
                                : () => setState(() {
                                    final s = _steps.removeAt(i);
                                    _steps.insert(i + 1, s);
                                  }),
                            icon: const Icon(
                              Icons.arrow_downward_rounded,
                              size: 18,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove step ${i + 1}',
                            onPressed: _steps.length == 1
                                ? null
                                : () => setState(() {
                                    final s = _steps.removeAt(i);
                                    Future<void>.delayed(
                                      const Duration(seconds: 1),
                                      s.dispose,
                                    );
                                  }),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _steps[i].agent,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Assigned agent',
                        ),
                        items: widget.agents
                            .map(
                              (a) => DropdownMenuItem(
                                value: a.id,
                                child: Text(
                                  a.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (s) {
                          if (s != null) _steps[i].agent = s;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _steps[i].title,
                        maxLength: 100,
                        validator: _required,
                        decoration: const InputDecoration(
                          labelText: 'Step title',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _steps[i].instruction,
                        maxLength: 2000,
                        maxLines: 3,
                        validator: _required,
                        decoration: const InputDecoration(
                          labelText: 'Instructions for this agent',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _steps.length >= 8
                  ? null
                  : () => setState(
                      () => _steps.add(_StepDraft(agent: _agent('general'))),
                    ),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add step'),
            ),
            const SizedBox(height: 16),
            Text(
              'Creating is free. Each step run uses 1 generation credit. Results are saved for your review; no emails or external actions are sent by this workflow.',
              style: TextStyle(color: p.muted, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Create workflow'),
            ),
          ],
        ),
      ),
    );
  }
}
