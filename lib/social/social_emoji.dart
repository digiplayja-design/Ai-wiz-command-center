import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'social_design.dart';

const _groups = <String, List<(String, String)>>{
  'Faces': [
    ('😀', 'Smile'),
    ('😃', 'Happy'),
    ('😊', 'Blush'),
    ('😁', 'Grin'),
    ('😂', 'Laugh'),
    ('🤣', 'Laughing'),
    ('🥹', 'Touched'),
    ('😍', 'Love eyes'),
    ('🥰', 'Loved'),
    ('😘', 'Kiss'),
    ('😎', 'Cool'),
    ('🤩', 'Star struck'),
    ('🤔', 'Thinking'),
    ('🙃', 'Upside down'),
    ('😉', 'Wink'),
    ('😅', 'Relieved'),
    ('😢', 'Sad'),
    ('😭', 'Crying'),
    ('😮', 'Surprised'),
    ('😴', 'Sleepy'),
    ('🥳', 'Celebrate'),
    ('🤗', 'Hug'),
    ('🫡', 'Salute'),
    ('🤝', 'Handshake'),
  ],
  'Reactions': [
    ('👍', 'Thumbs up'),
    ('👍🏽', 'Thumbs up medium'),
    ('👍🏿', 'Thumbs up dark'),
    ('👎', 'Thumbs down'),
    ('👏', 'Clap'),
    ('👏🏽', 'Clap medium'),
    ('🙌', 'Cheers'),
    ('🙏', 'Thank you'),
    ('🙏🏽', 'Thank you medium'),
    ('💪', 'Strong'),
    ('👋', 'Wave'),
    ('👋🏽', 'Wave medium'),
    ('✌️', 'Peace'),
    ('👌', 'Okay'),
    ('❤️', 'Red heart'),
    ('🩵', 'Blue heart'),
    ('💜', 'Purple heart'),
    ('💚', 'Green heart'),
    ('💛', 'Yellow heart'),
    ('💯', 'Hundred'),
    ('🔥', 'Fire'),
    ('✨', 'Sparkles'),
    ('🎉', 'Party'),
    ('✅', 'Done'),
  ],
  'Life': [
    ('🌍', 'World'),
    ('☀️', 'Sun'),
    ('🌈', 'Rainbow'),
    ('🌻', 'Flower'),
    ('🐶', 'Dog'),
    ('🐱', 'Cat'),
    ('🍕', 'Pizza'),
    ('☕', 'Coffee'),
    ('🎂', 'Birthday'),
    ('🥂', 'Toast'),
    ('⚽', 'Football soccer'),
    ('🏀', 'Basketball'),
    ('🏏', 'Cricket'),
    ('🎾', 'Tennis'),
    ('🏆', 'Trophy'),
    ('🎵', 'Music'),
    ('🎬', 'Film'),
    ('🎮', 'Gaming'),
    ('📚', 'Books'),
    ('💼', 'Business'),
    ('💡', 'Idea'),
    ('🚀', 'Rocket'),
    ('📈', 'Growth'),
    ('🏡', 'Home'),
  ],
};

Future<void> socialChooseEmoji(
  BuildContext context,
  TextEditingController controller,
) async {
  final emoji = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _EmojiSheet(),
  );
  if (emoji == null || !context.mounted) return;
  final selection = controller.selection;
  final start = selection.isValid
      ? selection.start.clamp(0, controller.text.length)
      : controller.text.length;
  final end = selection.isValid
      ? selection.end.clamp(start, controller.text.length)
      : start;
  final text = controller.text.replaceRange(start, end, emoji);
  if (text.runes.length > 2000) {
    if (context.mounted) {
      socialNotice(context, 'Keep the message within 2,000 characters.');
    }
    return;
  }
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: start + emoji.length),
  );
}

class _EmojiSheet extends StatefulWidget {
  const _EmojiSheet();
  @override
  State<_EmojiSheet> createState() => _EmojiSheetState();
}

class _EmojiSheetState extends State<_EmojiSheet> {
  String _group = 'Faces', _query = '';
  @override
  Widget build(BuildContext context) {
    final entries = _query.isEmpty
        ? _groups[_group]!
        : _groups.values
              .expand((x) => x)
              .where((x) => x.$2.toLowerCase().contains(_query.toLowerCase()))
              .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .57,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              const Text(
                'Say it with an emoji',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search emojis',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final group in _groups.keys)
                    ChoiceChip(
                      label: Text(group),
                      selected: _group == group,
                      onSelected: (_) => setState(() => _group = group),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: entries.isEmpty
                    ? const Center(child: Text('Try another emoji name.'))
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 64,
                              mainAxisExtent: 56,
                            ),
                        itemCount: entries.length,
                        itemBuilder: (_, i) => Semantics(
                          label: entries[i].$2,
                          child: Tooltip(
                            message: entries[i].$2,
                            child: TextButton(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                Navigator.pop(context, entries[i].$1);
                              },
                              child: Text(
                                entries[i].$1,
                                style: const TextStyle(fontSize: 28),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
