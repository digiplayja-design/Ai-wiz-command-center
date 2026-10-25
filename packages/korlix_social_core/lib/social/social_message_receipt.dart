import 'package:flutter/material.dart';

import '../theme/korlix_theme.dart';
import 'social_client.dart';
import 'social_design.dart';

class SocialMessageReceipt extends StatefulWidget {
  const SocialMessageReceipt({
    super.key,
    required this.messageId,
    required this.createdAt,
    required this.groupChat,
    this.readAt,
    this.readers = const [],
  });
  final String messageId;
  final dynamic createdAt, readAt;
  final bool groupChat;
  final List<SocialMap> readers;

  @override
  State<SocialMessageReceipt> createState() => _SocialMessageReceiptState();
}

class _SocialMessageReceiptState extends State<SocialMessageReceipt> {
  bool _expanded = false;

  String _time(dynamic value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return '';
    final locale = MaterialLocalizations.of(context);
    return '${locale.formatFullDate(date)} · '
        '${locale.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final read = widget.groupChat
        ? widget.readers.isNotEmpty
        : DateTime.tryParse('${widget.readAt}') != null;
    final label = read
        ? widget.groupChat
              ? 'Read by ${widget.readers.length}'
              : 'Read'
        : 'Sent';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              socialTime(widget.createdAt),
              style: TextStyle(fontSize: 10, color: skin.mutedText),
            ),
            Tooltip(
              message: read
                  ? 'Show read receipts'
                  : 'Sent. Waiting for a read receipt.',
              child: TextButton.icon(
                key: ValueKey('receipt-state-${widget.messageId}'),
                onPressed: read
                    ? () => setState(() => _expanded = !_expanded)
                    : null,
                style: TextButton.styleFrom(
                  foregroundColor: skin.primary,
                  disabledForegroundColor: skin.mutedText,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 32),
                  textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                icon: Icon(
                  read ? Icons.done_all_rounded : Icons.check_rounded,
                  size: 18,
                ),
                label: Text(label),
              ),
            ),
          ],
        ),
        if (_expanded && read)
          Padding(
            key: ValueKey('receipt-details-${widget.messageId}'),
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.groupChat
                  ? [
                      for (final reader in widget.readers)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${reader['name'] ?? 'Member'}'
                            '${reader['handle'] == null ? '' : ' · @${reader['handle']}'}'
                            '\n${_time(reader['read_at'])}',
                            style: TextStyle(
                              fontSize: 12,
                              color: skin.mutedText,
                              height: 1.5,
                            ),
                          ),
                        ),
                    ]
                  : [
                      Text(
                        'Read ${_time(widget.readAt)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: skin.mutedText,
                          height: 1.5,
                        ),
                      ),
                    ],
            ),
          ),
      ],
    );
  }
}
