import 'package:flutter/material.dart';
import 'korlix_theme.dart';
import 'korlix_theme_picker.dart';
import 'korlix_screen_skin.dart';
import 'korlix_appearance_preferences.dart';

Future<KorlixAppearanceChoice?> showKorlixAppearancePicker(
  BuildContext context, {
  int initialTab = 0,
}) => showModalBottomSheet<KorlixAppearanceChoice>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => KorlixAppearancePicker(
    current: kKorlixAppearancePreferences.current,
    initialTab: initialTab,
  ),
);

const korlixLookTemplates = [
  ('Pure & Simple', 'pure_white', 'classic'),
  ('Ice Glass', 'pure_white', 'glass'),
  ('Midnight Fracture', 'korlix_blue', 'glass_break'),
  ('Bubblegum', 'pink_white', 'bubbles'),
  ('Ocean Glass', 'ocean_blue', 'glass'),
  ('Mint Bubbles', 'mint_cloud', 'bubbles'),
  ('Northern Lights', 'matrix_green', 'aurora'),
  ('Golden Prism', 'ultra_gold', 'prism'),
];

class KorlixAppearancePicker extends StatefulWidget {
  const KorlixAppearancePicker({
    super.key,
    required this.current,
    this.initialTab = 0,
  });
  final KorlixAppearanceChoice current;
  final int initialTab;
  @override
  State<KorlixAppearancePicker> createState() => _KorlixAppearancePickerState();
}

class _KorlixAppearancePickerState extends State<KorlixAppearancePicker> {
  late String _theme, _skin;
  late int _tab;
  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    _theme = widget.current.themeId;
    _skin = widget.current.skinId;
    _tab = widget.initialTab.clamp(0, 2);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _selectTab(int value) {
    setState(() => _tab = value);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final palette = korlixSkinPaletteFor(_theme);
    return Theme(
      data: korlixBuildTheme(_theme),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .94,
            child: Material(
              color: palette.backgroundMid,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 10, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Style your screen',
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close appearance preview',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Choose colors, add a wrapper, or start from a template.',
                        style: TextStyle(color: palette.mutedText, height: 1.4),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final (index, label, icon) in [
                          (0, 'Color themes', Icons.palette_outlined),
                          (1, 'Screen skins', Icons.layers_outlined),
                          (2, 'Templates', Icons.dashboard_customize_outlined),
                        ])
                          ChoiceChip(
                            key: ValueKey('appearance-tab-$index'),
                            avatar: Icon(
                              _tab == index ? Icons.check : icon,
                              size: 17,
                            ),
                            showCheckmark: false,
                            label: Text(label),
                            selected: _tab == index,
                            onSelected: (_) => _selectTab(index),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          KorlixAppearancePreview(
                            palette: palette,
                            skinId: _skin,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            switch (_tab) {
                              0 => '12 color themes · Your skin stays selected',
                              1 => '6 screen skins · Keep your current colors',
                              _ =>
                                'Ready-made looks · Sets both colors and skin',
                            },
                            style: TextStyle(
                              color: palette.mutedText,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final columns = constraints.maxWidth >= 650
                                  ? 2
                                  : 1;
                              final width =
                                  (constraints.maxWidth - (columns - 1) * 16) /
                                  columns;
                              final children = <Widget>[];
                              if (_tab == 0) {
                                for (final id in korlixThemeIds) {
                                  children.add(
                                    SizedBox(
                                      width: width,
                                      child: KorlixThemePreview(
                                        skin: korlixSkinPaletteFor(id),
                                        selected: _theme == id,
                                        onSelect: () =>
                                            setState(() => _theme = id),
                                      ),
                                    ),
                                  );
                                }
                              } else if (_tab == 1) {
                                for (final id in korlixScreenSkinIds) {
                                  children.add(
                                    SizedBox(
                                      width: width,
                                      child: _lookCard(
                                        keyId: 'skin-$id',
                                        title: korlixScreenSkinLabel(id),
                                        description:
                                            korlixScreenSkinDescription(id),
                                        palette: palette,
                                        skinId: id,
                                        selected: _skin == id,
                                        onTap: () => setState(() => _skin = id),
                                      ),
                                    ),
                                  );
                                }
                              } else {
                                for (final template in korlixLookTemplates) {
                                  final colors = korlixSkinPaletteFor(
                                    template.$2,
                                  );
                                  children.add(
                                    SizedBox(
                                      width: width,
                                      child: _lookCard(
                                        keyId: 'template-${template.$1}',
                                        title: template.$1,
                                        description:
                                            '${colors.label} + ${korlixScreenSkinLabel(template.$3)}',
                                        palette: colors,
                                        skinId: template.$3,
                                        selected:
                                            _theme == template.$2 &&
                                            _skin == template.$3,
                                        onTap: () => setState(() {
                                          _theme = template.$2;
                                          _skin = template.$3;
                                        }),
                                      ),
                                    ),
                                  );
                                }
                              }
                              return Wrap(
                                spacing: 16,
                                runSpacing: 16,
                                children: children,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  Material(
                    color: palette.panel,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final label = Text(
                              '${palette.label} · ${korlixScreenSkinLabel(_skin)}',
                              key: const Key('appearance-selection'),
                              style: TextStyle(
                                color: palette.text,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                            final apply = FilledButton.icon(
                              key: const Key('apply-appearance'),
                              onPressed: () => Navigator.pop(
                                context,
                                KorlixAppearanceChoice(_theme, _skin),
                              ),
                              icon: const Icon(Icons.check),
                              label: const Text('Apply look'),
                            );
                            return constraints.maxWidth < 550
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      label,
                                      const SizedBox(height: 8),
                                      apply,
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(child: label),
                                      const SizedBox(width: 16),
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

  Widget _lookCard({
    required String keyId,
    required String title,
    required String description,
    required KorlixSkinPalette palette,
    required String skinId,
    required bool selected,
    required VoidCallback onTap,
  }) => Semantics(
    button: true,
    selected: selected,
    label: 'Preview $title',
    child: Material(
      color: palette.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected
              ? palette.primary
              : palette.border.withValues(alpha: .5),
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey(keyId),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KorlixAppearancePreview(
                palette: palette,
                skinId: skinId,
                compact: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    color: palette.primary,
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                description,
                style: TextStyle(
                  color: palette.mutedText,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class KorlixAppearancePreview extends StatelessWidget {
  const KorlixAppearancePreview({
    super.key,
    required this.palette,
    required this.skinId,
    this.compact = false,
  });
  final KorlixSkinPalette palette;
  final String skinId;
  final bool compact;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: compact ? 160 : 205,
        child: KorlixScreenBackdrop(
          palette: palette,
          skinId: skinId,
          child: Center(
            child: FractionallySizedBox(
              widthFactor: .72,
              child: KorlixSkinFrame(
                palette: palette,
                skinId: skinId,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: palette.panel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: palette.border.withValues(alpha: .5),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            color: palette.primary,
                            size: 17,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'KORLIX',
                              textScaler: TextScaler.noScaling,
                              style: TextStyle(
                                color: palette.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: palette.mutedText.withValues(alpha: .4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 7),
                      FractionallySizedBox(
                        widthFactor: .65,
                        child: Container(
                          height: 5,
                          color: palette.mutedText.withValues(alpha: .23),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 25,
                              decoration: BoxDecoration(
                                color: palette.inputFill,
                                border: Border.all(color: palette.border),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: palette.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.arrow_upward,
                              size: 15,
                              color: palette.textOnAccent,
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
      ),
    ),
  );
}
