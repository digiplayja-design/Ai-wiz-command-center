import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'social_client.dart';

const socialTextStyles = <String, String>{
  'bold': 'Bold',
  'italic': 'Italic',
  'strike': 'Strikethrough',
  'highlight': 'Highlight',
};

TextStyle _markedStyle(TextStyle? base, Set<String> marks) =>
    (base ?? const TextStyle()).copyWith(
      fontWeight: marks.contains('bold') ? FontWeight.bold : null,
      fontStyle: marks.contains('italic') ? FontStyle.italic : null,
      decoration: marks.contains('strike') ? TextDecoration.lineThrough : null,
      backgroundColor: marks.contains('highlight')
          ? const Color(0xffffdc73)
          : null,
      color: marks.contains('highlight') ? const Color(0xff17130a) : null,
    );

TextSpan _spans(String text, List<Set<String>> marks, TextStyle? style) {
  final spans = <TextSpan>[];
  var start = 0;
  for (var end = 1; end <= text.length; end++) {
    if (end < text.length && _sameMarks(marks[start], marks[end])) continue;
    spans.add(
      TextSpan(
        text: text.substring(start, end),
        style: _markedStyle(style, marks[start]),
      ),
    );
    start = end;
  }
  return TextSpan(style: style, children: spans);
}

bool _sameMarks(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

/// Plain text stays plain text. Styles are separate code-point ranges on the wire.
/// Editing, pasting and emoji insertion shift ranges along with their text.
class SocialTextController extends TextEditingController {
  List<Set<String>> _marks = [];

  @override
  set value(TextEditingValue next) {
    final previous = text;
    if (next.text != previous) {
      var prefix = 0;
      while (prefix < previous.length &&
          prefix < next.text.length &&
          previous.codeUnitAt(prefix) == next.text.codeUnitAt(prefix)) {
        prefix++;
      }
      if (prefix > 0 &&
          prefix < previous.length &&
          _lowSurrogate(previous.codeUnitAt(prefix))) {
        prefix--;
      }
      var suffix = 0;
      while (suffix < previous.length - prefix &&
          suffix < next.text.length - prefix &&
          previous.codeUnitAt(previous.length - suffix - 1) ==
              next.text.codeUnitAt(next.text.length - suffix - 1)) {
        suffix++;
      }
      if (suffix > 0 &&
          _lowSurrogate(previous.codeUnitAt(previous.length - suffix))) {
        suffix--;
      }
      final inserted = next.text.length - prefix - suffix;
      final inherit = prefix < previous.length - suffix
          ? _marks[prefix]
          : prefix > 0
          ? _marks[prefix - 1]
          : <String>{};
      _marks = [
        ..._marks.take(prefix),
        for (var i = 0; i < inserted; i++) Set<String>.from(inherit),
        ..._marks.skip(previous.length - suffix),
      ];
    }
    super.value = next;
  }

  bool toggle(String style, TextSelection range) {
    if (!socialTextStyles.containsKey(style) ||
        !range.isValid ||
        range.isCollapsed ||
        range.end > text.length) {
      return false;
    }
    final before = _marks.map((m) => Set<String>.from(m)).toList();
    final remove = _marks
        .sublist(range.start, range.end)
        .every((m) => m.contains(style));
    for (var i = range.start; i < range.end; i++) {
      if (remove) {
        _marks[i].remove(style);
      } else {
        _marks[i].add(style);
      }
    }
    if (formatting.length > 100) {
      _marks = before;
      return false;
    }
    notifyListeners();
    return true;
  }

  List<SocialMap> get formatting {
    final left = text.length - text.trimLeft().length;
    final right = text.trimRight().length;
    if (left >= right) return [];
    final result = <SocialMap>[];
    for (final style in socialTextStyles.keys) {
      int? start;
      for (var i = left; i <= right; i++) {
        final has = i < right && _marks[i].contains(style);
        if (has) {
          start ??= i;
        } else if (start != null) {
          result.add({
            'style': style,
            'start': text.substring(left, start).runes.length,
            'end': text.substring(left, i).runes.length,
          });
          start = null;
        }
      }
    }
    return result;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final span = _spans(text, _marks, style);
    // Preserve the IME's composing underline independently of saved styles.
    if (!withComposing ||
        !value.isComposingRangeValid ||
        value.composing.isCollapsed) {
      return span;
    }
    final children = <TextSpan>[];
    var offset = 0;
    for (final child in span.children!.cast<TextSpan>()) {
      final end = offset + child.text!.length;
      final cuts = <int>{
        offset,
        end,
        value.composing.start.clamp(offset, end),
        value.composing.end.clamp(offset, end),
      }.toList()..sort();
      for (var i = 0; i < cuts.length - 1; i++) {
        final composing =
            cuts[i] >= value.composing.start && cuts[i] < value.composing.end;
        children.add(
          TextSpan(
            text: text.substring(cuts[i], cuts[i + 1]),
            style: composing
                ? child.style!.copyWith(
                    decoration: TextDecoration.combine([
                      TextDecoration.underline,
                      if (child.style!.decoration != null)
                        child.style!.decoration!,
                    ]),
                  )
                : child.style,
          ),
        );
      }
      offset = end;
    }
    return TextSpan(style: style, children: children);
  }
}

bool _lowSurrogate(int unit) => unit >= 0xdc00 && unit <= 0xdfff;

TextSpan socialMessageSpan(String body, dynamic formatting, TextStyle style) {
  final marks = List.generate(body.length, (_) => <String>{});
  final offsets = <int>[0];
  for (final rune in body.runes) {
    offsets.add(offsets.last + (rune > 0xffff ? 2 : 1));
  }
  for (final range in socialItems(formatting).take(100)) {
    final start = range['start'], end = range['end'], mark = range['style'];
    if (start is! int ||
        end is! int ||
        start < 0 ||
        end <= start ||
        end >= offsets.length ||
        !socialTextStyles.containsKey(mark)) {
      continue;
    }
    for (var i = offsets[start]; i < offsets[end]; i++) {
      marks[i].add(mark as String);
    }
  }
  return _spans(body, marks, style);
}

String? socialDictionaryWord(String text) {
  final word = text.trim().replaceAll(
    RegExp(r'''^[^\p{L}\p{M}]+|[^\p{L}\p{M}]+$''', unicode: true),
    '',
  );
  return word.runes.length <= 80 &&
          RegExp(
            r"^[\p{L}\p{M}]+(?:['’\-][\p{L}\p{M}]+)*$",
            unicode: true,
          ).hasMatch(word)
      ? word
      : null;
}

Future<void> socialOpenDictionary(BuildContext context, String word) async {
  // A lookup is explicit and sends only the selected word to the dictionary.
  final uri = Uri.https('en.wiktionary.org', '/wiki/$word');
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    /* Present a usable error if a platform cannot open a browser. */
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open the dictionary. Please try again.'),
      ),
    );
  }
}

Widget socialTextSelectionMenu(
  BuildContext context,
  EditableTextState editor, {
  SocialTextController? controller,
  VoidCallback? onReact,
  Widget? header,
}) {
  final value = editor.textEditingValue;
  final selection = value.selection;
  final selected = selection.isValid ? selection.textInside(value.text) : '';
  final word = socialDictionaryWord(selected);
  final buttons = <ContextMenuButtonItem>[
    if (onReact != null)
      ContextMenuButtonItem(
        label: 'React',
        onPressed: () {
          editor.hideToolbar();
          onReact();
        },
      ),
    ...editor.contextMenuButtonItems,
    if (word != null)
      ContextMenuButtonItem(
        label: 'Dictionary',
        onPressed: () {
          editor.hideToolbar();
          socialOpenDictionary(context, word);
        },
      ),
    if (controller != null && selected.isNotEmpty)
      for (final entry in socialTextStyles.entries)
        ContextMenuButtonItem(
          label: entry.value,
          onPressed: () {
            editor.hideToolbar();
            if (!controller.toggle(entry.key, selection)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Select some text, or use fewer text styles.'),
                ),
              );
            }
          },
        ),
  ];
  if (header != null || controller != null) {
    final media = MediaQuery.of(context);
    final availableHeight = media.size.height - media.viewInsets.bottom;
    return CustomSingleChildLayout(
      delegate: _SocialSelectionMenuLayout(
        editor.contextMenuAnchors,
        availableHeight,
      ),
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(80, availableHeight - 24),
          ),
          child: SizedBox(
            width: (media.size.width - 24).clamp(0.0, 360.0),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?header,
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        for (final item in buttons)
                          TextButton(
                            onPressed: item.onPressed,
                            child: Text(
                              AdaptiveTextSelectionToolbar.getButtonLabel(
                                context,
                                item,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editor.contextMenuAnchors,
    buttonItems: buttons,
  );
}

class _SocialSelectionMenuLayout extends SingleChildLayoutDelegate {
  _SocialSelectionMenuLayout(this.anchors, this.availableHeight);
  final TextSelectionToolbarAnchors anchors;
  final double availableHeight;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();
  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final above = anchors.primaryAnchor.dy - childSize.height - 10;
    final below = (anchors.secondaryAnchor ?? anchors.primaryAnchor).dy + 10;
    return Offset(
      (anchors.primaryAnchor.dx - childSize.width / 2).clamp(
        8.0,
        math.max(8.0, size.width - childSize.width - 8),
      ),
      (above >= 8 ? above : below).clamp(
        8.0,
        math.max(8.0, availableHeight - childSize.height - 8),
      ),
    );
  }

  @override
  bool shouldRelayout(covariant _SocialSelectionMenuLayout oldDelegate) =>
      oldDelegate.anchors != anchors ||
      oldDelegate.availableHeight != availableHeight;
}
