import 'dart:async';
import 'package:flutter/material.dart';
import 'korlix_theme.dart';
import 'korlix_screen_skin.dart';
import 'korlix_appearance_preferences.dart';
import 'korlix_appearance_preview.dart';
import 'korlix_look_catalog.dart';
import 'korlix_look_library.dart';
import 'korlix_screensaver_settings.dart';
import '../characters/button_climbers_settings.dart';
export 'korlix_appearance_preview.dart';
export 'korlix_look_catalog.dart' show korlixLookTemplates;

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

class KorlixAppearancePicker extends StatefulWidget {
  const KorlixAppearancePicker({
    super.key,
    required this.current,
    this.initialTab = 0,
    this.library,
  });
  final KorlixAppearanceChoice current;
  final int initialTab;
  final KorlixLookLibrary? library;
  @override
  State<KorlixAppearancePicker> createState() => _KorlixAppearancePickerState();
}

class _KorlixAppearancePickerState extends State<KorlixAppearancePicker> {
  late String _theme, _skin;
  late int _tab;
  late final KorlixLookLibrary _library;
  bool _loaded = false, _chat = false;
  String _filter = 'All', _query = '';
  String? _notice;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  KorlixAppearanceChoice get _choice => KorlixAppearanceChoice(_theme, _skin);
  bool get _changed =>
      _theme != widget.current.themeId || _skin != widget.current.skinId;

  @override
  void initState() {
    super.initState();
    _theme = widget.current.themeId;
    _skin = widget.current.skinId;
    _tab = widget.initialTab.clamp(0, 2);
    _library = widget.library ?? KorlixLookLibrary();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    await _library.restore();
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _selectTab(int value) {
    setState(() {
      _tab = value;
      _filter = 'All';
      _query = '';
      _search.clear();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _select(KorlixAppearanceChoice choice) {
    setState(() {
      _theme = choice.themeId;
      _skin = choice.skinId;
    });
  }

  Future<void> _save(KorlixAppearanceChoice choice) async {
    final saving = _library.toggle(choice);
    setState(() => _notice = null);
    if (!await saving && mounted) {
      setState(
        () => _notice =
            'Favorites updated for this visit. Device storage could not save them.',
      );
    }
  }

  bool _matches(String title, String description, KorlixSkinPalette palette) {
    if (_filter == 'Light' && !palette.isLight) return false;
    if (_filter == 'Dark' && palette.isLight) return false;
    return '$title $description'.toLowerCase().contains(
      _query.trim().toLowerCase(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = korlixSkinPaletteFor(_theme);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final availableHeight = MediaQuery.sizeOf(context).height - keyboard;
    final short =
        availableHeight < 500 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;
    return Theme(
      data: korlixBuildTheme(_theme),
      child: Builder(
        builder: (context) => Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: SizedBox(
                height: availableHeight * .96,
                child: Material(
                  color: palette.backgroundMid,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 10, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Make it yours',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.text,
                                      fontSize: short ? 20 : 24,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -.7,
                                    ),
                                  ),
                                  if (!short)
                                    Text(
                                      'Skins, colors & ready-made looks',
                                      style: TextStyle(
                                        color: palette.mutedText,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
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
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            for (final (index, label, icon) in [
                              (0, 'Colors', Icons.palette_outlined),
                              (1, 'Skins', Icons.layers_outlined),
                              (
                                2,
                                'Templates',
                                Icons.dashboard_customize_outlined,
                              ),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  key: ValueKey('appearance-tab-$index'),
                                  avatar: Icon(
                                    icon,
                                    size: 17,
                                    color: _tab == index
                                        ? palette.textOnAccent
                                        : palette.primary,
                                  ),
                                  selectedColor: palette.primary,
                                  labelStyle: TextStyle(
                                    color: _tab == index
                                        ? palette.textOnAccent
                                        : palette.text,
                                  ),
                                  showCheckmark: false,
                                  label: Text(label),
                                  selected: _tab == index,
                                  onSelected: (_) => _selectTab(index),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Scrollbar(
                          controller: _scroll,
                          child: SingleChildScrollView(
                            key: const Key('appearance-gallery'),
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _hero(palette),
                                const SizedBox(height: 12),
                                const KorlixScreensaverSettings(),
                                const SizedBox(height: 12),
                                const KorlixClimbersSettings(),
                                const SizedBox(height: 22),
                                Text(
                                  switch (_tab) {
                                    0 => 'Find your color',
                                    1 => 'Choose your finish',
                                    _ => 'A complete look, in one tap',
                                  },
                                  style: TextStyle(
                                    color: palette.text,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  switch (_tab) {
                                    0 =>
                                      '${korlixThemeIds.length} palettes · Keep your selected skin',
                                    1 =>
                                      '${korlixScreenSkinIds.length} finishes · Keep your selected colors',
                                    _ =>
                                      '${korlixLookTemplates.length} curated looks · Colors and skin together',
                                  },
                                  style: TextStyle(
                                    color: palette.mutedText,
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  key: const Key('appearance-search'),
                                  controller: _search,
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) =>
                                      FocusScope.of(context).unfocus(),
                                  onChanged: (value) =>
                                      setState(() => _query = value),
                                  decoration: InputDecoration(
                                    hintText: _tab == 1
                                        ? 'Find a skin…'
                                        : 'Find a look or color…',
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      size: 20,
                                    ),
                                    suffixIcon: _query.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Clear appearance search',
                                            onPressed: () {
                                              _search.clear();
                                              setState(() => _query = '');
                                            },
                                            icon: const Icon(
                                              Icons.close,
                                              size: 18,
                                            ),
                                          ),
                                  ),
                                ),
                                if (_tab != 1)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        for (final filter in [
                                          'All',
                                          'Light',
                                          'Dark',
                                          if (_tab == 2) 'Saved',
                                        ])
                                          ChoiceChip(
                                            key: ValueKey(
                                              'appearance-filter-$filter',
                                            ),
                                            label: Text(filter),
                                            selected: _filter == filter,
                                            selectedColor: palette.primary,
                                            labelStyle: TextStyle(
                                              color: _filter == filter
                                                  ? palette.textOnAccent
                                                  : palette.text,
                                            ),
                                            showCheckmark: false,
                                            avatar: filter == 'Saved'
                                                ? Icon(
                                                    Icons.bookmark_border,
                                                    size: 16,
                                                    color: _filter == filter
                                                        ? palette.textOnAccent
                                                        : palette.primary,
                                                  )
                                                : null,
                                            onSelected: (_) => setState(
                                              () => _filter = filter,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                _gallery(palette),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _footer(palette, context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hero(KorlixSkinPalette palette) => Container(
    key: const Key('appearance-live-preview'),
    decoration: BoxDecoration(
      color: palette.panel,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: palette.border.withValues(alpha: .25)),
    ),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 0, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _changed ? 'PREVIEW YOUR LOOK' : 'YOUR CURRENT LOOK',
                  style: TextStyle(
                    color: palette.mutedText,
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final (chat, label) in [(false, 'Home'), (true, 'Chat')])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Tooltip(
                    message: '$label preview',
                    child: IconButton(
                      key: ValueKey('appearance-preview-$label'),
                      isSelected: _chat == chat,
                      onPressed: () => setState(() => _chat = chat),
                      style: IconButton.styleFrom(
                        backgroundColor: _chat == chat
                            ? palette.panelSoft
                            : null,
                        side: BorderSide(
                          color: _chat == chat
                              ? palette.primary.withValues(alpha: .5)
                              : Colors.transparent,
                        ),
                      ),
                      icon: Icon(
                        chat ? Icons.chat_bubble_outline : Icons.home_outlined,
                        size: 19,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        KorlixAppearancePreview(palette: palette, skinId: _skin, chat: _chat),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 0, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      korlixLookName(_choice),
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${palette.label} / ${korlixScreenSkinLabel(_skin)}',
                      style: TextStyle(color: palette.mutedText, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('save-appearance'),
                tooltip: _library.contains(_choice)
                    ? 'Remove saved look'
                    : 'Save this look',
                onPressed: _loaded ? () => unawaited(_save(_choice)) : null,
                icon: Icon(
                  _library.contains(_choice)
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                  color: palette.primary,
                ),
              ),
            ],
          ),
        ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              _notice!,
              style: TextStyle(color: palette.mutedText, fontSize: 12),
            ),
          ),
      ],
    ),
  );

  Widget _gallery(KorlixSkinPalette active) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = constraints.maxWidth >= 300 && scale < 1.4 ? 2 : 1;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      final cards = <Widget>[];
      void add({
        required String key,
        required String title,
        required String description,
        required String theme,
        required String skin,
        bool? selected,
        bool save = false,
      }) {
        final palette = korlixSkinPaletteFor(theme);
        if (!_matches(
          title,
          '$description ${palette.label} ${korlixScreenSkinLabel(skin)}',
          palette,
        )) {
          return;
        }
        final choice = KorlixAppearanceChoice(theme, skin);
        cards.add(
          SizedBox(
            width: width,
            child: _LookCard(
              keyId: key,
              title: title,
              description: description,
              palette: palette,
              skinId: skin,
              selected: selected ?? (_theme == theme && _skin == skin),
              saved: _library.contains(choice),
              onSave: save && _loaded ? () => unawaited(_save(choice)) : null,
              onTap: () => _select(choice),
            ),
          ),
        );
      }

      if (_tab == 0) {
        for (final id in korlixThemeIds) {
          final palette = korlixSkinPaletteFor(id);
          add(
            key: 'theme-preview-$id',
            title: palette.label,
            description: palette.isLight ? 'Light palette' : 'Dark palette',
            theme: id,
            skin: _skin,
            selected: _theme == id,
          );
        }
      } else if (_tab == 1) {
        for (final id in korlixScreenSkinIds) {
          add(
            key: 'skin-$id',
            title: korlixScreenSkinLabel(id),
            description: korlixScreenSkinDescription(id),
            theme: _theme,
            skin: id,
            selected: _skin == id,
          );
        }
      } else if (_filter == 'Saved') {
        for (final choice in _library.items) {
          final name = korlixLookName(choice);
          add(
            key: 'saved-${choice.themeId}-${choice.skinId}',
            title: name == 'Your custom mix'
                ? '${korlixSkinPaletteFor(choice.themeId).label} · ${korlixScreenSkinLabel(choice.skinId)}'
                : name,
            description: 'Saved on this device',
            theme: choice.themeId,
            skin: choice.skinId,
            save: true,
          );
        }
      } else {
        for (final look in korlixLookTemplates) {
          add(
            key: 'template-${look.name}',
            title: look.name,
            description: look.description,
            theme: look.themeId,
            skin: look.skinId,
            save: true,
          );
        }
      }
      if (cards.isEmpty) {
        return Container(
          key: const Key('appearance-empty'),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: active.panel,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Icon(
                _filter == 'Saved' ? Icons.bookmark_border : Icons.search,
                size: 30,
                color: active.primary,
              ),
              const SizedBox(height: 12),
              Text(
                _filter == 'Saved' && _query.isEmpty
                    ? 'Your favorite looks belong here'
                    : 'No looks match yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: active.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _filter == 'Saved' && _query.isEmpty
                    ? 'Tap the bookmark on any look, or save your own color and skin mix.'
                    : 'Try another word or clear the filters.',
                textAlign: TextAlign.center,
                style: TextStyle(color: active.mutedText, height: 1.5),
              ),
              TextButton(
                onPressed: () {
                  _search.clear();
                  setState(() {
                    _query = '';
                    _filter = 'All';
                  });
                },
                child: const Text('Browse all looks'),
              ),
            ],
          ),
        );
      }
      return Wrap(spacing: 12, runSpacing: 12, children: cards);
    },
  );

  Widget _footer(KorlixSkinPalette palette, BuildContext context) => Material(
    color: palette.panel,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final summary = Row(
              children: [
                Expanded(
                  child: Text(
                    '${palette.label} · ${korlixScreenSkinLabel(_skin)}',
                    key: const Key('appearance-selection'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('show-appearance-preview'),
                  tooltip: 'View full preview',
                  onPressed: () {
                    if (_scroll.hasClients) {
                      if (MediaQuery.disableAnimationsOf(context)) {
                        _scroll.jumpTo(0);
                      } else {
                        unawaited(
                          _scroll.animateTo(
                            0,
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOut,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.visibility_outlined, size: 20),
                ),
              ],
            );
            final actions = Row(
              children: [
                if (constraints.maxWidth < 330 ||
                    MediaQuery.textScalerOf(context).scale(14) > 18)
                  IconButton(
                    key: const Key('reset-appearance'),
                    tooltip: 'Reset preview',
                    onPressed: _changed ? () => _select(widget.current) : null,
                    icon: const Icon(Icons.restart_alt),
                  )
                else
                  TextButton(
                    key: const Key('reset-appearance'),
                    onPressed: _changed ? () => _select(widget.current) : null,
                    child: const Text('Reset preview'),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('apply-appearance'),
                    onPressed: () => Navigator.pop(context, _choice),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Apply look'),
                  ),
                ),
              ],
            );
            if (constraints.maxWidth < 600) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [summary, const SizedBox(height: 6), actions],
              );
            }
            return Row(
              children: [
                Expanded(child: summary),
                const SizedBox(width: 16),
                SizedBox(width: 340, child: actions),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _LookCard extends StatelessWidget {
  const _LookCard({
    required this.keyId,
    required this.title,
    required this.description,
    required this.palette,
    required this.skinId,
    required this.selected,
    required this.saved,
    required this.onTap,
    this.onSave,
  });
  final String keyId, title, description, skinId;
  final KorlixSkinPalette palette;
  final bool selected, saved;
  final VoidCallback onTap;
  final VoidCallback? onSave;
  @override
  Widget build(BuildContext context) => Material(
    color: palette.panel,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(19),
      side: BorderSide(
        color: selected
            ? palette.primary
            : palette.border.withValues(alpha: .28),
        width: selected ? 2 : 1,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          selected: selected,
          label: 'Preview $title',
          child: InkWell(
            key: ValueKey(keyId),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KorlixAppearancePreview(
                    palette: palette,
                    skinId: skinId,
                    compact: true,
                  ),
                  const SizedBox(height: 11),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (selected)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.check_circle,
                            size: 17,
                            color: palette.primary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 4, 4),
          child: Row(
            children: [
              for (final color in [
                palette.primary,
                palette.secondary,
                palette.backgroundMid,
              ])
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: palette.border.withValues(alpha: .4),
                    ),
                  ),
                ),
              const Spacer(),
              if (onSave != null)
                IconButton(
                  tooltip: saved ? 'Unsave $title' : 'Save $title',
                  onPressed: onSave,
                  icon: Icon(
                    saved ? Icons.bookmark : Icons.bookmark_border,
                    size: 19,
                    color: palette.primary,
                  ),
                )
              else
                const SizedBox(height: 28),
            ],
          ),
        ),
      ],
    ),
  );
}
