import 'package:flutter/material.dart';

import 'social_client.dart';

const socialMessageEmojis = <String, String>{
  '👍': 'Thumbs up',
  '🙂': 'Smile',
  '😂': 'Laugh',
  '😢': 'Cry',
  '❤️': 'Love',
  '🎉': 'Celebrate',
  '😀': 'Happy',
  '😊': 'Blush',
  '🤣': 'Laughing hard',
  '😭': 'Sobbing',
  '😍': 'Love eyes',
  '🥰': 'Loved',
  '😘': 'Kiss',
  '😎': 'Cool',
  '🤩': 'Star struck',
  '🤔': 'Thinking',
  '🙃': 'Upside down',
  '😉': 'Wink',
  '😅': 'Relieved',
  '😮': 'Surprised',
  '😴': 'Sleepy',
  '🥳': 'Party',
  '🤗': 'Hug',
  '🫡': 'Salute',
  '🤝': 'Handshake',
  '👎': 'Thumbs down',
  '👏': 'Clap',
  '🙌': 'Cheers',
  '🙏': 'Thank you',
  '💪': 'Strong',
  '👋': 'Wave',
  '✌️': 'Peace',
  '👌': 'Okay',
  '🩵': 'Blue heart',
  '💜': 'Purple heart',
  '💚': 'Green heart',
  '💛': 'Yellow heart',
  '💯': 'Hundred',
  '🔥': 'Fire',
  '✨': 'Sparkles',
  '✅': 'Done',
  '😡': 'Angry',
  '😱': 'Shocked',
  '🤯': 'Mind blown',
  '🥹': 'Touched',
  '👍🏻': 'Thumbs up light',
  '👍🏼': 'Thumbs up medium light',
  '👍🏽': 'Thumbs up medium',
  '👍🏾': 'Thumbs up medium dark',
  '👍🏿': 'Thumbs up dark',
  '👏🏻': 'Clap light',
  '👏🏼': 'Clap medium light',
  '👏🏽': 'Clap medium',
  '👏🏾': 'Clap medium dark',
  '👏🏿': 'Clap dark',
  '🙏🏻': 'Thank you light',
  '🙏🏼': 'Thank you medium light',
  '🙏🏽': 'Thank you medium',
  '🙏🏾': 'Thank you medium dark',
  '🙏🏿': 'Thank you dark',
};

class SocialQuickReactions extends StatelessWidget {
  const SocialQuickReactions({
    super.key,
    required this.onPick,
    required this.onMore,
  });
  final ValueChanged<String> onPick;
  final VoidCallback onMore;
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    children: [
      for (final entry in socialMessageEmojis.entries.take(6))
        IconButton(
          tooltip: 'React ${entry.value}',
          onPressed: () => onPick(entry.key),
          icon: Text(entry.key, style: const TextStyle(fontSize: 25)),
        ),
      IconButton(
        tooltip: 'More reactions',
        onPressed: onMore,
        icon: const Icon(Icons.add_reaction_outlined),
      ),
    ],
  );
}

class SocialMessageReactions extends StatelessWidget {
  const SocialMessageReactions({
    super.key,
    required this.reactions,
    required this.onPick,
  });
  final dynamic reactions;
  final ValueChanged<String>? onPick;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      for (final r in socialItems(reactions))
        if (socialMessageEmojis.containsKey(r['emoji']) &&
            socialCallCount(r['count']) > 0)
          InputChip(
            key: ValueKey('reaction-count-${r['emoji']}'),
            label: Text('${r['emoji']} ${r['count']}'),
            selected: r['mine'] == true,
            tooltip:
                '${socialMessageEmojis[r['emoji']]} · ${r['count']}${r['mine'] == true ? ' · You reacted; tap to remove' : ' · Tap to react'}',
            onPressed: onPick == null
                ? null
                : () => onPick!(r['emoji'] as String),
          ),
    ],
  );
}

class SocialMessageReactionSheet extends StatefulWidget {
  const SocialMessageReactionSheet({
    super.key,
    required this.client,
    this.selected,
  });
  final SocialClient client;
  final String? selected;
  @override
  State<SocialMessageReactionSheet> createState() =>
      _SocialMessageReactionSheetState();
}

class _SocialMessageReactionSheetState
    extends State<SocialMessageReactionSheet> {
  String _query = '';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.client,
    builder: (context, _) {
      final entries = socialMessageEmojis.entries
          .where(
            (e) =>
                e.value.toLowerCase().contains(_query.toLowerCase().trim()) ||
                e.key == _query,
          )
          .toList();
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .55,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'React to message',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close reactions',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (!widget.client.available)
                  const Text('Your session changed. Reopen the conversation.')
                else ...[
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search reactions…',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: entries.isEmpty
                        ? const Center(child: Text('No matching reactions.'))
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 64,
                                  mainAxisExtent: 56,
                                ),
                            itemCount: entries.length,
                            itemBuilder: (context, i) {
                              final entry = entries[i];
                              return Semantics(
                                selected: widget.selected == entry.key,
                                child: IconButton(
                                  tooltip: entry.value,
                                  onPressed: () =>
                                      Navigator.pop(context, entry.key),
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        widget.selected == entry.key
                                        ? Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                        : null,
                                  ),
                                  icon: Text(
                                    entry.key,
                                    style: const TextStyle(fontSize: 29),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  if (widget.selected != null)
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context, ''),
                      icon: const Icon(Icons.remove_circle_outline),
                      label: const Text('Remove my reaction'),
                    ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
