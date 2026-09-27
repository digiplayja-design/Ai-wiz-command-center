import 'package:flutter/material.dart';
import 'korlix_theme.dart';

Future<String?> showKorlixThemePicker(
  BuildContext context, {
  required String currentId,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => KorlixThemePicker(currentId: currentId),
);

class KorlixThemePicker extends StatefulWidget {
  const KorlixThemePicker({super.key, required this.currentId});
  final String currentId;
  @override
  State<KorlixThemePicker> createState() => _KorlixThemePickerState();
}

class _KorlixThemePickerState extends State<KorlixThemePicker> {
  late String _preview;
  @override
  void initState() {
    super.initState();
    _preview = korlixNormalizeSkinId(widget.currentId);
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinPaletteFor(_preview);
    return Theme(
      data: korlixBuildTheme(_preview),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .9,
            child: Material(
              color: skin.backgroundMid,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Make KORLIX yours',
                            style: TextStyle(
                              color: skin.text,
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close theme preview',
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.close, color: skin.text),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Preview a palette, then apply it. Your conversation stays right where you left it.',
                        style: TextStyle(color: skin.mutedText, height: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 620 ? 2 : 1;
                          final width =
                              (constraints.maxWidth - (columns - 1) * 16) /
                              columns;
                          return Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: korlixThemeIds
                                .map(
                                  (id) => SizedBox(
                                    width: width,
                                    child: KorlixThemePreview(
                                      skin: korlixSkinPaletteFor(id),
                                      selected: _preview == id,
                                      onSelect: () =>
                                          setState(() => _preview = id),
                                    ),
                                  ),
                                )
                                .toList(),
                          );
                        },
                      ),
                    ),
                  ),
                  Material(
                    color: skin.panel,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final label = Text(
                              skin.label,
                              style: TextStyle(
                                color: skin.text,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                            final apply = FilledButton.icon(
                              key: const Key('apply-theme'),
                              onPressed: () => Navigator.pop(context, _preview),
                              icon: const Icon(Icons.check),
                              label: const Text('Apply theme'),
                            );
                            if (constraints.maxWidth < 500) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  label,
                                  const SizedBox(height: 10),
                                  apply,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: label),
                                const SizedBox(width: 12),
                                apply,
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class KorlixThemePreview extends StatelessWidget {
  const KorlixThemePreview({
    super.key,
    required this.skin,
    required this.selected,
    required this.onSelect,
  });
  final KorlixSkinPalette skin;
  final bool selected;
  final VoidCallback onSelect;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: 'Preview ${skin.label}, ${skin.isLight ? 'light' : 'dark'} theme',
    child: Material(
      color: skin.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? skin.primary : skin.border.withValues(alpha: .5),
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('theme-preview-${skin.id}'),
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      skin.label,
                      style: TextStyle(
                        color: skin.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.check_circle
                        : (skin.isLight
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined),
                    color: skin.primary,
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                korlixThemeDescription(skin.id),
                style: TextStyle(
                  color: skin.mutedText,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: skin.panelDeep,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, color: skin.primary, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Chat preview',
                          style: TextStyle(color: skin.mutedText, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: skin.panelSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Let’s create something.',
                          style: TextStyle(color: skin.text, fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'A little more clarity. A lot more you.',
                      style: TextStyle(
                        color: skin.text,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: skin.inputFill,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: skin.border),
                            ),
                            child: Text(
                              'Ask anything…',
                              style: TextStyle(
                                color: skin.hintText,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: skin.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.arrow_upward,
                            color: skin.textOnAccent,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ...[skin.primary, skin.secondary, skin.panelSoft].map(
                    (color) => Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: skin.border.withValues(alpha: .45),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selected
                          ? 'Selected preview'
                          : (skin.isLight ? 'Light palette' : 'Dark palette'),
                      textAlign: TextAlign.right,
                      style: TextStyle(color: skin.mutedText, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class KorlixThemeShortcuts extends StatelessWidget {
  const KorlixThemeShortcuts({
    super.key,
    required this.selectedId,
    required this.onSelect,
    required this.onPreview,
    this.onSkins,
  });
  final String selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onPreview;
  final VoidCallback? onSkins;
  @override
  Widget build(BuildContext context) {
    final active = korlixSkinPaletteFor(selectedId);
    return Material(
      color: active.panel.withValues(alpha: .94),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: active.border.withValues(alpha: .3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              children:
                  [
                    'pure_white',
                    'pure_black',
                    'korlix_blue',
                    'pink_white',
                    'matrix_green',
                    'ultra_gold',
                  ].map((id) {
                    final skin = korlixSkinPaletteFor(id);
                    final selected = skin.id == active.id;
                    return Tooltip(
                      message: skin.label,
                      child: Semantics(
                        button: true,
                        selected: selected,
                        label: 'Apply ${skin.label} theme',
                        child: InkWell(
                          onTap: () => onSelect(id),
                          customBorder: const CircleBorder(),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: Container(
                                width: 34,
                                height: 34,
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selected
                                        ? active.text
                                        : active.border.withValues(alpha: .45),
                                    width: selected ? 2 : 1,
                                  ),
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: skin.primary,
                                  ),
                                  child: selected
                                      ? Icon(
                                          Icons.check,
                                          size: 18,
                                          color: skin.textOnAccent,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
            TextButton.icon(
              onPressed: onPreview,
              icon: const Icon(Icons.palette_outlined, size: 17),
              label: Text(
                '${active.label} · 12 color themes',
                textAlign: TextAlign.center,
                style: TextStyle(color: active.text, fontSize: 12),
              ),
            ),
            if (onSkins != null)
              TextButton.icon(
                onPressed: onSkins,
                icon: const Icon(Icons.layers_outlined, size: 18),
                label: const Text('Screen skins & templates'),
              ),
          ],
        ),
      ),
    );
  }
}
