import 'package:flutter/material.dart';
import '../theme/korlix_theme.dart';
import 'social_client.dart';
import 'social_media_widgets.dart' show socialImageLabel;

class SocialMessageQuote extends StatelessWidget {
  const SocialMessageQuote({
    super.key,
    required this.message,
    required this.author,
    this.composing = false,
    this.onOpen,
    this.onCancel,
  });
  final SocialMap message;
  final String author;
  final bool composing;
  final VoidCallback? onOpen, onCancel;
  @override
  Widget build(BuildContext context) {
    final s = korlixSkinOf(context), deleted = message['deleted'] == true;
    final body = '${message['body'] ?? ''}';
    final attachment = socialMap(message['attachment']);
    final fallback = attachment['kind'] == 'image'
        ? socialImageLabel(attachment)
        : attachment['kind'] == 'voice'
        ? 'Voice note'
        : attachment.isNotEmpty
        ? 'Attachment'
        : '';
    final content = Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: s.primary.withValues(alpha: s.isLight ? .07 : .1),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: s.primary, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.reply_rounded, size: 19, color: s.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  composing ? 'Replying to $author' : author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: s.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  deleted
                      ? 'Message removed'
                      : body.isNotEmpty
                      ? body
                      : fallback,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: s.mutedText,
                    fontSize: 13,
                    height: 1.4,
                    fontStyle: deleted ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
          if (composing)
            IconButton(
              tooltip: 'Cancel reply',
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded, size: 20),
              visualDensity: VisualDensity.compact,
            )
          else if (onOpen != null)
            Icon(Icons.open_in_new_rounded, size: 15, color: s.mutedText),
        ],
      ),
    );
    if (composing || onOpen == null) return content;
    return Semantics(
      button: true,
      label: 'View original message from $author',
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: content,
      ),
    );
  }
}
