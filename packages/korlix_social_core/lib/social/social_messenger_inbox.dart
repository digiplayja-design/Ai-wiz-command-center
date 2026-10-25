import 'package:flutter/material.dart';

import '../theme/korlix_theme.dart';
import 'social_client.dart';
import 'social_design.dart';

String messengerMessageTime(dynamic value, {DateTime? now}) {
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return '';
  final current = (now ?? DateTime.now()).toLocal();
  final age = current.difference(date);
  if (age.inMinutes < 1) return 'Now';
  if (age.inMinutes < 60) return '${age.inMinutes}m';
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(date.year, date.month, date.day);
  if (day == today) return '${age.inHours}h';
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return 'Yesterday';
  }
  return '${date.month}/${date.day}${date.year == current.year ? '' : '/${date.year}'}';
}

String messengerMessagePreview(SocialMap peer) {
  final raw = '${peer['last_message'] ?? ''}'.trim();
  if (raw.isEmpty) return 'Start a conversation';
  final kind = peer['last_message_kind'];
  var preview = raw;
  if (kind == 'voice') {
    final seconds = socialCallCount(peer['last_message_duration_ms']) ~/ 1000;
    preview = seconds == 0
        ? 'Voice message'
        : 'Voice message · ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
  if (kind == 'image' && raw == 'Photo') preview = 'Sent a photo';
  return '${peer['last_message_mine'] == true ? 'You: ' : ''}$preview';
}

class MessengerConversationTile extends StatelessWidget {
  const MessengerConversationTile({
    super.key,
    required this.peer,
    required this.onTap,
  });
  final SocialMap peer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = socialCallCount(peer['unread']);
    final time = messengerMessageTime(peer['last_message_at']);
    final skin = korlixSkinOf(context);
    final icon = switch (peer['last_message_kind']) {
      'voice' => Icons.mic_none_rounded,
      'image' => Icons.image_outlined,
      'file' => Icons.attach_file_rounded,
      _ => null,
    };
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final metadata = <Widget>[
      if (time.isNotEmpty)
        Text(time, style: TextStyle(fontSize: 11, color: skin.mutedText)),
      if (unread > 0)
        Semantics(
          label: '$unread unread messages',
          child: ExcludeSemantics(
            child: Badge(
              backgroundColor: skin.primary,
              textColor: skin.textOnAccent,
              label: Text(unread > 99 ? '99+' : '$unread'),
            ),
          ),
        ),
      if (time.isEmpty && unread == 0) const Icon(Icons.chevron_right_rounded),
    ];
    return SocialPanel(
      padding: EdgeInsets.zero,
      child: InkWell(
        key: ValueKey('messenger-conversation-${peer['id']}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              SocialAvatar(member: peer, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${peer['name'] ?? peer['handle'] ?? 'KORLIX member'}',
                      maxLines: largeText ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: unread > 0
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 16, color: skin.primary),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            messengerMessagePreview(peer),
                            maxLines: largeText ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: unread > 0
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: unread > 0 ? skin.text : skin.mutedText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (largeText) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, runSpacing: 4, children: metadata),
                    ],
                  ],
                ),
              ),
              if (!largeText) ...[
                const SizedBox(width: 12),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  spacing: 4,
                  children: metadata,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
