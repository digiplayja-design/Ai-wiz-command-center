import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/korlix_action_button.dart';
import 'agent_studio_design.dart';
import 'korlix_live_convo_agent.dart';

const agentCapabilityLabels = <String, String>{
  'general_chat': 'Conversation',
  'live_docs': 'Documents',
  'file_analysis': 'File analysis',
  'image_generation': 'Image creation',
  'image_improvement': 'Image editing',
  'camera': 'Camera',
  'memory': 'Memory',
  'agent_training': 'Training',
  'agent_email': 'Email',
};

List<String> agentStartingTasks(KorlixLiveConvoAgent a) => switch (a.id) {
  'doc_wizard' => [
    'Draft a professional report',
    'Summarize a document',
    'Plan a spreadsheet',
  ],
  'language_teacher' => [
    'Practice a conversation',
    'Build a weekly lesson plan',
    'Explain my corrections',
  ],
  'my_assistant' => [
    'Organize my priorities',
    'Prepare a meeting brief',
    'Write a follow-up',
  ],
  'graphic_designer' => [
    'Develop a visual direction',
    'Write a design brief',
    'Explore a brand concept',
  ],
  _ =>
    a.toolIds.contains('agent_email')
        ? [
            'Draft a customer reply',
            'Plan a follow-up sequence',
            'Review an email for clarity',
          ]
        : [
            'Create an action plan',
            'Compare my options',
            'Review and improve a draft',
          ],
};

bool agentMatchesCapability(KorlixLiveConvoAgent a, String capability) =>
    capability == 'Any capability' ||
    a.toolIds.any((id) => agentCapabilityLabels[id] == capability);

/// A preparation surface: copying a brief never starts a model run or a send.
class AgentStudioProfile extends StatefulWidget {
  const AgentStudioProfile({
    super.key,
    required this.agent,
    required this.onAction,
  });
  final KorlixLiveConvoAgent agent;
  final ValueChanged<String> onAction;
  @override
  State<AgentStudioProfile> createState() => _AgentStudioProfileState();
}

class _AgentStudioProfileState extends State<AgentStudioProfile> {
  final _brief = TextEditingController();
  bool _copied = false;
  @override
  void dispose() {
    _brief.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.agent, p = AgentStudioColors(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Agent profile',
                      style: TextStyle(color: p.muted),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close profile',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                children: [
                  Text(
                    a.name,
                    style: TextStyle(
                      color: p.text,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    a.description,
                    style: TextStyle(color: p.muted, height: 1.5),
                  ),
                  const SizedBox(height: 22),
                  AgentStudioPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MISSION',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.8,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          a.mission,
                          style: TextStyle(color: p.text, height: 1.6),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            for (final id in a.toolIds)
                              AgentStudioPill(
                                agentCapabilityLabels[id] ??
                                    id.replaceAll('_', ' '),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AgentStudioPill(
                        a.memorySummary,
                        icon: Icons.psychology_outlined,
                        color: p.muted,
                      ),
                      AgentStudioPill(
                        a.hasPublishedTraining
                            ? 'Published training · v${a.version}'
                            : 'Default instructions',
                        color: p.muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'Give this agent a clear brief',
                    style: TextStyle(
                      color: p.text,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Choose a starting point, add your context, and copy it into your conversation.',
                    style: TextStyle(color: p.muted, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final task in agentStartingTasks(a))
                        ActionChip(
                          label: Text(task),
                          onPressed: () => setState(() {
                            _brief.text =
                                '$task.\n\nContext: \nDesired outcome: \nConstraints: ';
                            _copied = false;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _brief,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 6000,
                    onChanged: (_) => setState(() => _copied = false),
                    decoration: const InputDecoration(
                      labelText: 'Task brief',
                      hintText: 'What should this agent help you accomplish?',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      KorlixActionButton(
                        label: _copied ? 'Brief copied' : 'Copy brief',
                        icon: _copied ? Icons.check : Icons.copy_rounded,
                        onPressed: _brief.text.trim().isEmpty
                            ? null
                            : () async {
                                await Clipboard.setData(
                                  ClipboardData(text: _brief.text.trim()),
                                );
                                if (mounted) setState(() => _copied = true);
                              },
                      ),
                      KorlixActionButton(
                        label: 'Use agent',
                        icon: Icons.graphic_eq_rounded,
                        onPressed: () => widget.onAction('use'),
                      ),
                      KorlixActionButton(
                        label: 'Plan a workflow',
                        icon: Icons.account_tree_outlined,
                        onPressed: () => widget.onAction('workflow'),
                      ),
                      KorlixActionButton(
                        label: 'Manage brain',
                        icon: Icons.psychology_outlined,
                        onPressed: () => widget.onAction('brain'),
                      ),
                      if (a.isCustom && a.toolIds.contains('agent_email'))
                        KorlixActionButton(
                          label: 'Agent Email',
                          icon: Icons.alternate_email_rounded,
                          onPressed: () => widget.onAction('email'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
