import 'package:flutter/material.dart';
import 'agent_studio_design.dart';
import 'korlix_live_convo_agent.dart';
import 'korlix_live_convo_agent_sheet.dart'
    show korlixLiveConvoAgentIcon, korlixLiveConvoAgentAccent;

class AgentStudioHub extends StatefulWidget {
  const AgentStudioHub({
    super.key,
    required this.agents,
    required this.selectedId,
    required this.activeId,
    required this.loading,
    required this.busy,
    required this.connected,
    required this.onSelect,
    required this.onAction,
    required this.onCreate,
    required this.onClose,
    required this.onRefresh,
    required this.workflows,
    required this.meetingCard,
    required this.modelProof,
    this.error,
    this.activity = 'ready',
    this.contactsEnabled = false,
  });
  final List<KorlixLiveConvoAgent> agents;
  final String selectedId, activeId, activity;
  final bool loading, busy, connected;
  final bool contactsEnabled;
  final String? error;
  final ValueChanged<String> onSelect;
  final void Function(String, KorlixLiveConvoAgent) onAction;
  final VoidCallback onCreate, onClose, onRefresh;
  final Widget workflows, meetingCard, modelProof;
  @override
  State<AgentStudioHub> createState() => _AgentStudioHubState();
}

class _AgentStudioHubState extends State<AgentStudioHub> {
  String _tab = 'Agents', _query = '', _filter = 'All agents';
  final _search = TextEditingController();
  final _pageScroll = ScrollController();
  @override
  void didUpdateWidget(covariant AgentStudioHub old) {
    super.didUpdateWidget(old);
    if (!old.busy && widget.busy && widget.activity == 'training') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageScroll.hasClients) _pageScroll.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _pageScroll.dispose();
    super.dispose();
  }

  KorlixLiveConvoAgent get _selected => widget.agents.firstWhere(
    (a) => a.id == widget.selectedId,
    orElse: () => KorlixLiveConvoAgent.fallbackForId('general'),
  );
  void _brain(KorlixLiveConvoAgent agent) {
    widget.onSelect(agent.id);
    setState(() => _tab = 'Brain Management');
  }

  Widget _action(
    String action,
    String label,
    IconData icon,
    KorlixLiveConvoAgent agent, {
    bool primary = false,
  }) {
    if (primary) {
      return FilledButton.icon(
        onPressed: widget.busy || widget.loading
            ? null
            : () => widget.onAction(action, agent),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: widget.busy || widget.loading
          ? null
          : () => widget.onAction(action, agent),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Widget _stat(String value, String label, AgentStudioColors p) => Padding(
    padding: const EdgeInsets.only(right: 28, bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 27,
            color: p.text,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
          ),
        ),
        Text(label, style: TextStyle(color: p.muted, fontSize: 12)),
      ],
    ),
  );
  Widget _hero(AgentStudioColors p) => LayoutBuilder(
    builder: (context, c) {
      final text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'KORLIX  /  AGENT STUDIO',
            style: TextStyle(
              color: p.cyan,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Your agents.\nWorking together.',
            style: TextStyle(
              color: p.text,
              fontSize: c.maxWidth > 650 ? 44 : 32,
              fontWeight: FontWeight.w700,
              height: 1.08,
              letterSpacing: -1.6,
            ),
          ),
          const SizedBox(height: 15),
          Text(
            'Shape their knowledge. Give work a direction.\nKeep every handoff in view.',
            style: TextStyle(color: p.muted, fontSize: 15, height: 1.6),
          ),
          const SizedBox(height: 22),
          Wrap(
            children: [
              _stat(
                '${widget.agents.where((a) => a.active).length}',
                'Available agents',
                p,
              ),
              _stat(
                '${widget.agents.fold<int>(0, (n, a) => n + a.memoryCount)}',
                'Saved memories',
                p,
              ),
              _stat(
                '${widget.agents.where((a) => a.hasPublishedTraining).length}',
                'Trained agents',
                p,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: widget.busy || widget.loading
                    ? null
                    : widget.onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create agent'),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() => _tab = 'Workflows'),
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Build a workflow'),
              ),
            ],
          ),
        ],
      );
      final brain = GestureDetector(
        onTap: () => _brain(_selected),
        child: AgentBrainHero(
          name: _selected.name,
          memories: _selected.memoryCount,
          version: _selected.version,
          activity: widget.activity,
          compact: c.maxWidth < 650,
        ),
      );
      return c.maxWidth > 720
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 6, child: text),
                const SizedBox(width: 30),
                Expanded(flex: 5, child: brain),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                text,
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _brain(_selected),
                    icon: const Icon(Icons.psychology_outlined, size: 18),
                    label: const Text('Explore this agent’s brain'),
                  ),
                ),
              ],
            );
    },
  );
  Widget _avatar(KorlixLiveConvoAgent a) {
    final c = korlixLiveConvoAgentAccent(a.accentHex);
    return Container(
      width: 57,
      height: 57,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        gradient: RadialGradient(
          center: const Alignment(-.6, -.8),
          radius: 1.4,
          colors: [
            Color.lerp(c, Colors.white, .6)!,
            c.withValues(alpha: .8),
            const Color(0xFF172B47),
          ],
        ),
        border: Border.all(color: c.withValues(alpha: .45)),
        boxShadow: [
          BoxShadow(
            color: c.withValues(alpha: .18),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Icon(
        korlixLiveConvoAgentIcon(a.iconName),
        color: const Color(0xFF0E2337),
        size: 28,
      ),
    );
  }

  Widget _card(KorlixLiveConvoAgent a, AgentStudioColors p) {
    final selected = a.id == widget.selectedId;
    return AgentStudioPanel(
      accent: selected ? p.cyan : null,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(a),
              const Spacer(),
              if (a.id == widget.activeId)
                const AgentStudioPill(
                  'In conversation',
                  icon: Icons.graphic_eq_rounded,
                ),
              PopupMenuButton<String>(
                tooltip: 'Options for ${a.name}',
                onSelected: (s) => widget.onAction(s, a),
                enabled: !widget.busy && !widget.loading,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'versions',
                    child: Text('Training history'),
                  ),
                  const PopupMenuItem(
                    value: 'vault',
                    child: Text('Open Brain Vault'),
                  ),
                  if (a.isCustom && a.toolIds.contains('agent_email'))
                    const PopupMenuItem(
                      value: 'email',
                      child: Text('Agent Email'),
                    ),
                  if (widget.contactsEnabled &&
                      a.toolIds.contains('agent_email'))
                    const PopupMenuItem(
                      value: 'contacts',
                      child: Text('Contacts CRM'),
                    ),
                  PopupMenuItem(
                    value: 'reset',
                    child: Text(
                      a.isCustom ? 'Delete agent' : 'Reset personal training',
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 19),
          Text(
            a.name,
            style: TextStyle(
              color: p.text,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            a.description,
            style: TextStyle(color: p.muted, height: 1.5, fontSize: 13),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 6,
            runSpacing: 7,
            children: [
              AgentStudioPill(
                a.isCustom ? 'Custom agent' : 'Specialist',
                color: p.muted,
              ),
              AgentStudioPill(
                '${a.memoryCount} memories',
                icon: Icons.psychology_alt_outlined,
              ),
              if (a.hasPublishedTraining)
                AgentStudioPill(
                  'Trained · v${a.version}',
                  color: p.dark
                      ? const Color(0xFF9EDDC2)
                      : const Color(0xFF246B50),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _action(
                'use',
                a.id == widget.activeId ? 'Reload agent' : 'Use agent',
                Icons.play_arrow_rounded,
                a,
                primary: true,
              ),
              OutlinedButton.icon(
                onPressed: widget.busy ? null : () => _brain(a),
                icon: const Icon(Icons.psychology_outlined, size: 18),
                label: const Text('Manage brain'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gallery(AgentStudioColors p) {
    final q = _query.toLowerCase().trim();
    final agents = widget.agents
        .where(
          (a) =>
              a.active &&
              (q.isEmpty ||
                  '${a.name} ${a.description} ${a.toolIds.join(' ')}'
                      .toLowerCase()
                      .contains(q)) &&
              (_filter == 'All agents' ||
                  (_filter == 'Custom' && a.isCustom) ||
                  (_filter == 'Trained' && a.hasPublishedTraining)),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hero(p),
        const SizedBox(height: 34),
        Row(
          children: [
            Expanded(
              child: Text(
                'Meet your team',
                style: TextStyle(
                  color: p.text,
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.6,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Refresh agents',
              onPressed: widget.busy ? null : widget.onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 13),
        TextField(
          controller: _search,
          onChanged: (s) => setState(() => _query = s),
          decoration: InputDecoration(
            hintText: 'Search agents, skills, or capabilities',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: 13),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final f in ['All agents', 'Custom', 'Trained'])
              ChoiceChip(
                label: Text(f),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (agents.isEmpty)
          AgentStudioPanel(
            child: Text(
              'No agents match this search. Try another name or capability.',
              style: TextStyle(color: p.muted),
            ),
          ),
        LayoutBuilder(
          builder: (context, c) {
            final columns = c.maxWidth > 1060
                ? 3
                : c.maxWidth > 700
                ? 2
                : 1;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final a in agents)
                  SizedBox(
                    width: (c.maxWidth - (columns - 1) * 16) / columns,
                    child: _card(a, p),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          title: const Text('Connected tools & runtime'),
          subtitle: const Text('Meeting Copilot and model details'),
          children: [
            widget.meetingCard,
            const SizedBox(height: 12),
            widget.modelProof,
          ],
        ),
      ],
    );
  }

  Widget _brainPage(AgentStudioColors p) {
    final a = _selected;
    final detail = AgentStudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Grow a more useful agent',
            style: TextStyle(
              color: p.text,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -.7,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Give ${a.name} the context, preferences, and instructions that make its work yours.',
            style: TextStyle(color: p.muted, height: 1.5),
          ),
          const SizedBox(height: 22),
          _brainAction(
            p,
            'memory',
            'Memory library',
            'Find, filter, add, and review approved knowledge.',
            Icons.psychology_alt_outlined,
            a,
          ),
          _brainAction(
            p,
            'train',
            'Training studio',
            'Write instructions or learn from a document.',
            Icons.school_outlined,
            a,
          ),
          _brainAction(
            p,
            'versions',
            'Version history',
            'Review previous training and restore a version.',
            Icons.history_rounded,
            a,
          ),
          _brainAction(
            p,
            'vault',
            'Brain Vault',
            'Protected backups, imports, and duplication.',
            Icons.lock_outline_rounded,
            a,
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'BRAIN MANAGEMENT',
          style: TextStyle(
            color: p.cyan,
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Knowledge, with a little dimension.',
          style: TextStyle(
            color: p.text,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          key: ValueKey(a.id),
          initialValue: a.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Agent brain'),
          items: widget.agents
              .where((a) => a.active)
              .map(
                (a) => DropdownMenuItem(
                  value: a.id,
                  child: Text(a.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: widget.busy
              ? null
              : (id) {
                  if (id != null) widget.onSelect(id);
                },
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, c) {
            final visual = AgentBrainHero(
              name: a.name,
              memories: a.memoryCount,
              version: a.version,
              activity: widget.activity,
            );
            return c.maxWidth > 760
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: visual),
                      const SizedBox(width: 20),
                      Expanded(child: detail),
                    ],
                  )
                : Column(
                    children: [visual, const SizedBox(height: 18), detail],
                  );
          },
        ),
        const SizedBox(height: 20),
        AgentStudioPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Brain readiness',
                style: TextStyle(
                  color: p.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  AgentStudioPill(
                    a.memoryEnabled ? 'Memory enabled' : 'Memory disabled',
                    icon: Icons.memory_rounded,
                  ),
                  AgentStudioPill(
                    a.hasPublishedTraining
                        ? 'Training published'
                        : 'Ready for first training',
                    icon: Icons.school_outlined,
                  ),
                  AgentStudioPill(
                    '${a.toolIds.length} capabilities',
                    icon: Icons.extension_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(a.mission, style: TextStyle(color: p.muted, height: 1.55)),
              const SizedBox(height: 16),
              Text(
                'Available capabilities',
                style: TextStyle(color: p.text, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final t in a.toolIds)
                    AgentStudioPill(t.replaceAll('_', ' '), color: p.muted),
                ],
              ),
              const SizedBox(height: 16),
              _action(
                'use',
                'Use this agent',
                Icons.play_arrow_rounded,
                a,
                primary: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _brainAction(
    AgentStudioColors p,
    String action,
    String title,
    String subtitle,
    IconData icon,
    KorlixLiveConvoAgent a,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: p.raised,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: p.cyan, size: 21),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: p.text,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: p.muted, fontSize: 12, height: 1.5),
      ),
      trailing: Icon(Icons.arrow_forward_rounded, color: p.muted, size: 18),
      onTap: widget.busy || widget.loading
          ? null
          : () => widget.onAction(action, a),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final p = AgentStudioColors(context), size = MediaQuery.sizeOf(context);
    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 1280,
            maxHeight: size.height * .96,
          ),
          decoration: BoxDecoration(
            color: p.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 10, 9),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: p.raised,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            Icons.hub_outlined,
                            color: p.cyan,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Agent Studio',
                            style: TextStyle(
                              color: p.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (size.width > 470)
                          AgentStudioPill(
                            widget.connected
                                ? 'Private workspace'
                                : 'Connecting',
                            icon: Icons.lock_outline_rounded,
                          ),
                        IconButton(
                          tooltip: 'Close Agent Hub',
                          onPressed: widget.busy ? null : widget.onClose,
                          icon: Icon(Icons.close_rounded, color: p.muted),
                        ),
                      ],
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        for (final entry in [
                          ('Agents', Icons.grid_view_rounded),
                          ('Brain Management', Icons.psychology_outlined),
                          ('Workflows', Icons.account_tree_outlined),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: TextButton.icon(
                              key: ValueKey('studio-tab-${entry.$1}'),
                              onPressed: () => setState(() => _tab = entry.$1),
                              style: TextButton.styleFrom(
                                foregroundColor: _tab == entry.$1
                                    ? p.cyan
                                    : p.muted,
                                backgroundColor: _tab == entry.$1
                                    ? p.raised
                                    : Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 15,
                                  vertical: 14,
                                ),
                              ),
                              icon: Icon(entry.$2, size: 18),
                              label: Text(
                                size.width < 600 &&
                                        entry.$1 == 'Brain Management'
                                    ? 'Brain'
                                    : entry.$1,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (widget.loading || widget.busy)
                    const LinearProgressIndicator(minHeight: 2),
                  if (widget.error?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: Color(0xFFDF7F83),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.error!,
                              style: TextStyle(color: p.text),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Retry loading agents',
                            onPressed: widget.busy ? null : widget.onRefresh,
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: _tab == 'Workflows'
                        ? widget.workflows
                        : ListView(
                            key: PageStorageKey(_tab),
                            controller: _pageScroll,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.fromLTRB(
                              size.width > 700 ? 30 : 18,
                              22,
                              size.width > 700 ? 30 : 18,
                              30 + MediaQuery.viewInsetsOf(context).bottom,
                            ),
                            children: [
                              _tab == 'Agents' ? _gallery(p) : _brainPage(p),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
