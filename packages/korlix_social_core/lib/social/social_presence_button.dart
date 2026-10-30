import 'package:flutter/material.dart';

/// Your visibility control, separate from the directory's Online-only filter.
class SocialPresenceButton extends StatelessWidget {
  const SocialPresenceButton({
    super.key,
    required this.visible,
    required this.online,
    required this.busy,
    required this.onSelected,
    required this.onRetry,
    this.failed = false,
  });
  final bool visible, busy;
  final bool failed;
  final bool? online;
  final ValueChanged<bool> onSelected;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final label = busy
        ? 'Updating status…'
        : !visible
        ? 'You: Offline'
        : online == true
        ? 'You: Online'
        : failed
        ? 'You: Status unavailable'
        : 'You: Connecting…';
    final color = !busy && visible && online == true
        ? Colors.green
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Flexible(
          child: PopupMenuButton<String>(
            key: const Key('social-presence-button'),
            tooltip: 'Change your online status',
            enabled: !busy,
            onSelected: (value) =>
                value == 'retry' ? onRetry() : onSelected(value == 'online'),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'online', child: Text('Go online')),
              const PopupMenuItem(
                value: 'offline',
                child: Text('Appear offline'),
              ),
              if (visible && online != true)
                const PopupMenuItem(
                  value: 'retry',
                  child: Text('Retry connection'),
                ),
            ],
            child: Semantics(
              button: true,
              enabled: !busy,
              label: label,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      busy ? Icons.sync : Icons.circle,
                      size: 12,
                      color: color,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
