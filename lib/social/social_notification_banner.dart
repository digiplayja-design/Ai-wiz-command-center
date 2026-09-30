import 'package:flutter/material.dart';

import '../theme/korlix_theme.dart';
import 'social_notifications.dart';

class SocialNotificationBanner extends StatelessWidget {
  const SocialNotificationBanner({
    super.key,
    required this.notifications,
    required this.onOpen,
  });
  final SocialNotifications notifications;
  final Future<void> Function(SocialUnreadConversation) onOpen;

  Future<void> _open(BuildContext context) async {
    if (!notifications.available || notifications.conversations.isEmpty) return;
    if (notifications.conversations.length == 1) {
      await onOpen(notifications.conversations.single);
      return;
    }
    final selected = await showModalBottomSheet<SocialUnreadConversation>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .6,
          child: AnimatedBuilder(
            animation: notifications,
            builder: (context, _) => Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'KORLIX Social messages',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                  ),
                ),
                Expanded(
                  child: notifications.conversations.isEmpty
                      ? const Center(child: Text('No unread messages.'))
                      : ListView(
                          children: [
                            for (final item in notifications.conversations)
                              ListTile(
                                leading: Icon(
                                  item.group
                                      ? Icons.groups_rounded
                                      : Icons.person_rounded,
                                ),
                                title: Text(item.name),
                                subtitle: Text(
                                  item.group
                                      ? 'Group message'
                                      : 'Private message',
                                ),
                                trailing: _UnreadBadge(label: '${item.unread}'),
                                onTap: () => Navigator.pop(context, item),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // A sign-out clears the list while the sheet is open. Never route using
    // a notification that belonged to the previous account.
    if (selected != null &&
        notifications.available &&
        notifications.conversations.contains(selected)) {
      await onOpen(selected);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: notifications,
    builder: (context, _) {
      final count = notifications.totalUnread;
      if (count == 0) return const SizedBox.shrink();
      final skin = korlixSkinOf(context);
      final summary = notifications.conversations.length == 1
          ? '${notifications.conversations.single.name} · Tap to read'
          : '${notifications.conversations.length} conversations · Tap to read';
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Semantics(
          liveRegion: true,
          child: Material(
            color: skin.primary.withValues(alpha: .12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: skin.primary.withValues(alpha: .55)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _open(context),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.mark_chat_unread_rounded, color: skin.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'KORLIX Social',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '${notifications.countLabel} unread ${count == 1 ? 'message' : 'messages'}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _UnreadBadge(
                      label: count > 99 ? '99+' : notifications.countLabel,
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFC62828),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    ),
  );
}
