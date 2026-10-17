import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sounds/korlix_sound_actions.dart';
import '../theme/korlix_theme.dart';

enum KorlixStarterTask {
  email(
    'Draft a business email',
    'Start with a helpful example',
    Icons.mail_outline_rounded,
    'Draft a friendly, professional follow-up email after a business meeting. '
        'Use placeholders for the recipient, agreed next steps, and dates.',
  ),
  writing(
    'Improve my writing',
    'Make your message clearer',
    Icons.edit_outlined,
    'Rewrite this example to make it clear and professional, keeping its meaning: '
        '"Thanks for talking with me today. I will send the details tomorrow. '
        'Let me know if there is anything else you need."',
  ),
  content(
    'Brainstorm content',
    'Find your next idea',
    Icons.lightbulb_outline_rounded,
    'Suggest five practical social media post ideas for a small business. '
        'Include an editable hook and a simple call to action for each.',
  );

  const KorlixStarterTask(this.title, this.subtitle, this.icon, this.prompt);
  final String title, subtitle, prompt;
  final IconData icon;
}

/// The parent supplies an existing account-scoped local-storage key. No prompt
/// is sent and no quota is consumed until the user edits/submits the composer.
class KorlixStarterTasks extends StatefulWidget {
  const KorlixStarterTasks({
    super.key,
    required this.storageKey,
    required this.onTask,
    required this.onExplore,
    required this.onViewPlans,
    this.tier,
    this.busy = false,
  });

  final String storageKey;
  final Future<bool> Function(KorlixStarterTask) onTask;
  final VoidCallback onExplore;
  final VoidCallback onViewPlans;
  final String? tier;
  final bool busy;

  @override
  State<KorlixStarterTasks> createState() => _KorlixStarterTasksState();
}

class _KorlixStarterTasksState extends State<KorlixStarterTasks> {
  bool _ready = false;
  bool _dismissed = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final storageKey = widget.storageKey;
    var dismissed = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      dismissed = prefs.getBool(storageKey) ?? false;
    } catch (_) {
      // Optional first-use guidance must not block the main tools.
    }
    if (mounted) {
      setState(() {
        _ready = true;
        _dismissed = dismissed;
      });
    }
  }

  Future<void> _dismiss() async {
    final storageKey = widget.storageKey;
    if (mounted) setState(() => _dismissed = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(storageKey, true);
    } catch (_) {
      // Keep it dismissed for this session if storage is unavailable.
    }
  }

  Future<void> _open(KorlixStarterTask task) async {
    if (_opening || widget.busy) return;
    setState(() => _opening = true);
    try {
      if (await widget.onTask(task) && mounted) await _dismiss();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _dismissed) return const SizedBox.shrink();
    final skin = korlixSkinOf(context);
    final basic = widget.tier?.trim().toLowerCase() == 'basic';
    final enabled = !_opening && !widget.busy;
    return Container(
      key: const Key('first-use-panel'),
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: skin.primary.withValues(alpha: .32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (basic) ...[
            Text(
              'BASIC · FREE',
              style: TextStyle(
                color: skin.primary,
                fontSize: 12,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'What would you like to do first?',
            style: TextStyle(
              color: skin.text,
              fontSize: 25,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a task. Make it your own.',
            style: TextStyle(color: skin.mutedText, height: 1.4),
          ),
          const SizedBox(height: 16),
          for (final task in KorlixStarterTask.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton(
                key: ValueKey('starter-${task.name}'),
                onPressed: korlixSoundAction(
                  enabled ? () => _open(task) : null,
                ),
                style: korlixSoundButtonStyle(
                  OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: skin.panelSoft,
                    side: BorderSide(color: skin.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(task.icon, color: skin.primary, size: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: TextStyle(
                              color: skin.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            task.subtitle,
                            style: TextStyle(
                              color: skin.mutedText,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded, color: skin.text),
                  ],
                ),
              ),
            ),
          TextButton(
            key: const Key('starter-explore'),
            onPressed: korlixSoundAction(
              enabled
                  ? () {
                      _dismiss();
                      widget.onExplore();
                    }
                  : null,
            ),
            child: const Text('Explore all tools'),
          ),
          if (basic) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: skin.secondary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: skin.secondary.withValues(alpha: .4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Need more room to create?',
                    style: TextStyle(
                      color: skin.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Explore Pro for higher daily limits and PDF exports.',
                    style: TextStyle(color: skin.mutedText, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    key: const Key('starter-view-plans'),
                    onPressed: korlixSoundAction(
                      enabled ? widget.onViewPlans : null,
                    ),
                    child: const Text('View plans'),
                  ),
                  TextButton(
                    key: const Key('starter-keep-basic'),
                    onPressed: korlixSoundAction(
                      enabled
                          ? () {
                              _dismiss();
                              widget.onExplore();
                            }
                          : null,
                    ),
                    child: const Text(
                      'Keep using Basic for free',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
