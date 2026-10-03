import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/korlix_action_button.dart';
import '../theme/korlix_theme.dart';
import '../input_tools/voice_composer.dart';
import '../imagine_studio/imagine_client.dart';
import 'logo_client.dart';
import 'logo_model.dart';
import 'logo_render.dart';
import 'logo_export.dart';
import 'logo_io.dart';
import 'logo_export_options.dart';
import 'logo_preview_board.dart';

class LogoStudioScreen extends StatefulWidget {
  const LogoStudioScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    this.allowVoice = false,
    this.language = 'en',
    this.io,
  });
  final LogoClient client;
  final Future<bool> Function() ensureConsent;
  final bool allowVoice;
  final String language;
  final LogoIo? io;
  @override
  State<LogoStudioScreen> createState() => _LogoStudioScreenState();
}

class _LogoStudioScreenState extends State<LogoStudioScreen> {
  final _name = TextEditingController(),
      _tagline = TextEditingController(),
      _idea = TextEditingController(),
      _hex = TextEditingController(),
      _accent = TextEditingController();
  late final io = widget.io ?? LogoIo();
  final scroll = ScrollController();
  int tab = 0, palette = 0;
  String industry = 'Technology', style = 'Modern';
  LogoDesign _briefBase = const LogoDesign();
  String? _selectedAiId;
  LogoInk ink = LogoInk.color;
  int exportPreset = 0;
  String? error, notice;
  bool ready = false, exporting = false, consenting = false, importing = false;
  LogoSurface surface = LogoSurface.light;
  LogoClient get c => widget.client;
  KorlixSkinPalette get skin => korlixSkinOf(context);
  bool get busy => exporting || consenting || importing || c.images.busy;
  @override
  void initState() {
    super.initState();
    c.addListener(_session);
    for (final controller in [_name, _tagline, _idea]) {
      controller.addListener(_refreshBrief);
    }
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await ensureLogoFonts();
    } catch (_) {
      if (mounted && c.available) {
        setState(() {
          ready = true;
          error =
              'Preview fonts could not load. Reopen Logo Studio to restore the matching fonts and exports.';
        });
      }
      return;
    }
    try {
      if (mounted) setState(() => ready = true);
      await c.load();
    } catch (_) {
      if (mounted && c.available) {
        setState(
          () => error =
              'Saved projects could not be loaded. You can still create a logo or import a backup.',
        );
      }
    }
  }

  void _refreshBrief() {
    if (mounted && tab == 0) setState(() {});
  }

  void _session() {
    if (!c.available) {
      _name.clear();
      _tagline.clear();
      _idea.clear();
      _hex.clear();
      _accent.clear();
      _selectedAiId = null;
      _briefBase = const LogoDesign();
      error = notice = null;
    } else if (tab == 2) {
      _sync(c.design);
    }
  }

  void _sync(LogoDesign d) {
    _briefBase = d;
    palette = logoPalettes.indexWhere(
      (p) =>
          p.primary == d.primary &&
          p.secondary == d.secondary &&
          p.paper == d.paper,
    );
    for (final entry in [
      (_name, d.name),
      (_tagline, d.tagline),
      (_idea, d.idea),
      (_hex, d.primary),
      (_accent, d.secondary),
    ]) {
      if (entry.$1.text != entry.$2) entry.$1.text = entry.$2;
    }
    industry = d.industry;
    style = d.style;
  }

  @override
  void dispose() {
    c.removeListener(_session);
    scroll.dispose();
    for (final controller in [_name, _tagline, _idea, _hex, _accent]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _say(String text) {
    if (mounted && c.available) setState(() => notice = text);
  }

  void _error(Object e) {
    if (!mounted || !c.available) return;
    final message = e is ImagineException
        ? e.message
        : e is FormatException
        ? e.message
        : e is TimeoutException
        ? 'This took longer than expected. Your design is still here. Please try again.'
        : 'That action could not finish. Please try again.';
    setState(() => error = message);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) scroll.jumpTo(0);
    });
  }

  void _go(int next) {
    if (busy || !c.available) return;
    if ([1, 2, 3].contains(next) && c.design.error != null) {
      _say('Add your brand name, then choose Create my logos.');
      return;
    }
    if (next == 0 || next == 2) _sync(c.design);
    setState(() {
      tab = next;
      error = notice = null;
    });
    _scrollTop();
  }

  LogoDesign get brief => _briefBase.copy(
    name: _name.text.trim(),
    tagline: _tagline.text.trim(),
    industry: industry,
    style: style,
    idea: _idea.text.trim(),
  );

  ImagineResult? get _selectedAi {
    final results = c.images.results;
    if (results.isEmpty) return null;
    return results.firstWhere(
      (result) => result.id == _selectedAiId,
      orElse: () => results.first,
    );
  }

  void _applyPalette(int index) {
    final p = logoPalettes[index];
    palette = index;
    _briefBase = _briefBase.copy(
      primary: p.primary,
      secondary: p.secondary,
      paper: p.paper,
    );
  }

  void _applyPreset(String id) {
    if (busy) return;
    final preset = switch (id) {
      'cafe' => (
        'Food & drink',
        'Organic',
        1,
        'Warm hospitality, fresh ingredients, and a welcoming neighborhood café.',
      ),
      'wellness' => (
        'Beauty & wellness',
        'Elegant',
        3,
        'Calm, thoughtful care with a soft botanical symbol and a confident premium feel.',
      ),
      'craft' => (
        'Retail & fashion',
        'Bold',
        4,
        'Independent craft and bold personality, with a memorable symbol that works on packaging.',
      ),
      _ => (
        'Technology',
        'Modern',
        0,
        'Forward motion, clarity, and a distinctive geometric symbol for a digital-first brand.',
      ),
    };
    setState(() {
      industry = preset.$1;
      style = preset.$2;
      _applyPalette(preset.$3);
      _idea.text = preset.$4;
    });
  }

  void _shortlist(LogoDesign design) {
    try {
      c.toggleShortlist(design);
    } catch (e) {
      _error(e);
    }
  }

  void _generate() {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      c.generate(brief);
      _go(1);
    } catch (e) {
      _error(e);
    }
  }

  void _choose(LogoDesign d) {
    c.choose(d);
    _sync(d);
    _go(2);
  }

  Future<void> _voice() async {
    if (busy || !widget.allowVoice) return;
    final result = await Navigator.of(context).push<KorlixVoiceDraft>(
      MaterialPageRoute(
        builder: (_) => KorlixVoiceComposer(
          initialText: _idea.text,
          language: widget.language,
          sessionChanges: c,
          isSessionCurrent: () => c.available,
          showLiveConvo: false,
        ),
      ),
    );
    if (mounted && c.available && result != null) {
      setState(() => _idea.text = cleanLogoText(result.text, 700));
    }
  }

  Future<void> _ai() async {
    if (busy || !c.available) return;
    if (c.design.error != null) {
      _error(ImagineException(c.design.error!));
      return;
    }
    setState(() {
      consenting = true;
      error = notice = null;
    });
    try {
      if (!await widget.ensureConsent() || !mounted || !c.available) return;
      await c.images.create(c.design.aiBrief, language: widget.language);
      if (mounted && c.available && c.images.results.isNotEmpty) {
        setState(() => _selectedAiId = c.images.results.first.id);
      }
    } catch (e) {
      _error(c.images.error == null ? e : ImagineException(c.images.error!));
    } finally {
      if (mounted) setState(() => consenting = false);
    }
  }

  Future<void> _save({bool asCopy = false}) async {
    try {
      await c.save(asCopy: asCopy);
      _say(
        'Project saved in this account on this device. Export a project backup to keep another copy.',
      );
    } catch (e) {
      _error(e);
    }
  }

  Future<void> _import() async {
    if (busy) return;
    setState(() => importing = true);
    try {
      final source = await io.importProject();
      if (source == null || !mounted || !c.available) return;
      c.import(source);
      _sync(c.design);
      setState(() => tab = 2);
      _scrollTop();
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> _export(BuildContext buttonContext, String kind) async {
    if (busy || !c.available) return;
    if (c.design.error != null) {
      _error(ImagineException(c.design.error!));
      return;
    }
    final box = buttonContext.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size, d = c.design;
    final ai = _selectedAi;
    final preset = logoExportPresets[exportPreset];
    final exportSurface = surface, exportInk = ink;
    var filename = d.filename;
    setState(() {
      exporting = true;
      error = notice = null;
    });
    void guard() {
      if (!mounted || !c.available) {
        throw const ImagineException('Your session changed.');
      }
    }

    try {
      late Uint8List bytes;
      late String extension, mime;
      switch (kind) {
        case 'kit':
          bytes = await logoBrandKit(d, checkCurrent: guard);
          extension = 'brand-kit.zip';
          mime = 'application/zip';
        case 'svg':
          bytes = Uint8List.fromList(
            utf8.encode(
              await logoSvg(
                d,
                surface: exportSurface,
                ink: exportInk,
                width: preset.width,
                height: preset.height,
                iconOnly: preset.iconOnly,
              ),
            ),
          );
          filename =
              '${d.filename}-${preset.id}-${exportSurface.name}-${exportInk.name}';
          extension = 'svg';
          mime = 'image/svg+xml';
        case 'pdf':
          bytes = await logoBrandGuide(d);
          extension = 'brand-guide.pdf';
          mime = 'application/pdf';
        case 'project':
          bytes = Uint8List.fromList(
            utf8.encode(const JsonEncoder.withIndent('  ').convert(d.json)),
          );
          extension = 'korlix-logo.json';
          mime = 'application/json';
        case 'ai':
          if (ai == null) return;
          await validateLogoArtwork(ai.bytes);
          guard();
          bytes = ai.bytes;
          filename = LogoDesign(
            name: ai.brief.lettering.split('\n').first,
          ).filename;
          extension = 'ai-concept.png';
          mime = 'image/png';
        default:
          bytes = await logoPng(
            d,
            surface: exportSurface,
            ink: exportInk,
            width: preset.width,
            height: preset.height,
            iconOnly: preset.iconOnly,
          );
          filename =
              '${d.filename}-${preset.id}-${exportSurface.name}-${exportInk.name}';
          extension = 'png';
          mime = 'image/png';
      }
      guard();
      await io.save(bytes, '$filename.$extension', mime, origin);
      guard();
      _say(
        'Your ${kind == 'kit' ? 'brand kit' : 'file'} is ready. Save it using your browser or device options.',
      );
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Widget _action(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    String? subtitle,
  }) => KorlixActionButton(
    label: label,
    icon: icon,
    onPressed: onPressed,
    subtitle: subtitle,
    tile: true,
    expand: true,
    accent: skin.primary,
  );
  Widget _download(
    String label,
    IconData icon,
    String kind, {
    String? subtitle,
  }) => Builder(
    builder: (context) => _action(
      label,
      icon,
      busy ? null : () => _export(context, kind),
      subtitle: subtitle,
    ),
  );
  Widget _pair(Widget first, Widget second) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    ),
  );
  Widget _panel(Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(skin.panel, skin.primary, skin.isLight ? .03 : .07)!,
          skin.panelDeep,
        ],
      ),
      borderRadius: BorderRadius.circular(25),
      border: Border.all(color: skin.border),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: skin.isLight ? .05 : .2),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
  Widget _heading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 29,
            height: 1.12,
            fontWeight: FontWeight.w800,
            color: skin.text,
            letterSpacing: -.7,
          ),
        ),
        const SizedBox(height: 10),
        Text(subtitle, style: TextStyle(color: skin.mutedText, height: 1.5)),
      ],
    ),
  );
  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    ),
  );
  Widget _choices(
    List<String> values,
    String selected,
    ValueChanged<String> change,
  ) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final value in values)
        ChoiceChip(
          label: Text(value),
          selected: value == selected,
          onSelected: busy ? null : (_) => change(value),
        ),
    ],
  );
  Widget _paletteChoices({bool editing = false}) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (var i = 0; i < logoPalettes.length; i++)
        ChoiceChip(
          avatar: CircleAvatar(
            backgroundColor: logoColor(logoPalettes[i].primary),
            child: const SizedBox(),
          ),
          label: Text(logoPalettes[i].name),
          selected: editing
              ? c.design.primary == logoPalettes[i].primary &&
                    c.design.secondary == logoPalettes[i].secondary &&
                    c.design.paper == logoPalettes[i].paper
              : palette == i,
          onSelected: busy
              ? null
              : (_) {
                  if (editing) {
                    final p = logoPalettes[i];
                    c.update(
                      c.design.copy(
                        primary: p.primary,
                        secondary: p.secondary,
                        paper: p.paper,
                      ),
                    );
                  } else {
                    setState(() => _applyPalette(i));
                  }
                },
        ),
    ],
  );
  Widget _canvas(
    LogoDesign d, {
    LogoSurface? backdrop,
    bool icon = false,
    Key? key,
    LogoInk previewInk = LogoInk.color,
    double aspectRatio = 1.5,
  }) => ClipRRect(
    borderRadius: BorderRadius.circular(18),
    child: LogoCanvas(
      key: key,
      design: d,
      ink: previewInk,
      aspectRatio: aspectRatio,
      surface: backdrop ?? surface,
      iconOnly: icon,
    ),
  );

  Widget _presetCards() => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final preset in const [
          (
            'cafe',
            'Café & food',
            Icons.local_cafe_outlined,
            Color(0xFF16604B),
            Color(0xFFE8F4EB),
          ),
          (
            'wellness',
            'Beauty & care',
            Icons.spa_outlined,
            Color(0xFF79339D),
            Color(0xFFF7EBFF),
          ),
          (
            'tech',
            'Tech & ideas',
            Icons.bolt_rounded,
            Color(0xFF1852B1),
            Color(0xFFEAF1FF),
          ),
          (
            'craft',
            'Made with soul',
            Icons.palette_outlined,
            Color(0xFF9D3623),
            Color(0xFFFFEFE7),
          ),
        ])
          SizedBox(
            width: (constraints.maxWidth - 10) / 2,
            child: Material(
              color: preset.$5,
              borderRadius: BorderRadius.circular(15),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('logo-preset-${preset.$1}'),
                onTap: busy ? null : () => _applyPreset(preset.$1),
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(preset.$3, color: preset.$4),
                      const SizedBox(height: 9),
                      Text(
                        preset.$2,
                        style: TextStyle(
                          color: preset.$4,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _shortlistPanel() => _panel(
    Column(
      key: const Key('logo-shortlist'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Your shortlist · ${c.shortlist.length}/3',
          'Compare your favorites on the same background, then choose one to refine.',
        ),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 12,
            runSpacing: 16,
            children: [
              for (var i = 0; i < c.shortlist.length; i++)
                SizedBox(
                  width: constraints.maxWidth < 520
                      ? constraints.maxWidth
                      : (constraints.maxWidth - (c.shortlist.length - 1) * 12) /
                            c.shortlist.length,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _canvas(c.shortlist[i], backdrop: LogoSurface.light),
                      const SizedBox(height: 8),
                      Text(
                        '${c.shortlist[i].layout} · ${c.shortlist[i].mark}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Wrap(
                        spacing: 4,
                        children: [
                          TextButton.icon(
                            key: ValueKey('logo-compare-$i'),
                            onPressed: busy
                                ? null
                                : () => _choose(c.shortlist[i]),
                            icon: const Icon(Icons.tune_rounded),
                            label: const Text('Customize'),
                          ),
                          IconButton(
                            tooltip: 'Remove comparison ${i + 1}',
                            onPressed: busy
                                ? null
                                : () => _shortlist(c.shortlist[i]),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _exportConfigurator() {
    final preset = logoExportPresets[exportPreset];
    final backdropLuminance = logoColor(
      surface == LogoSurface.dark ? '111927' : c.design.paper,
    ).computeLuminance();
    final inkContrast = ink == LogoInk.white
        ? 1.05 / (backdropLuminance + .05)
        : (backdropLuminance + .05) / .05;
    final lowContrast =
        surface != LogoSurface.transparent &&
        ink != LogoInk.color &&
        inkContrast < 4.5;
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(
            'Choose your finish.',
            'The preview matches your PNG and SVG download settings.',
          ),
          _canvas(
            c.design,
            key: const Key('logo-export-preview'),
            previewInk: ink,
            icon: preset.iconOnly,
            aspectRatio: preset.width / preset.height,
          ),
          _label('Background'),
          _choices(
            ['Light', 'Dark', 'Transparent'],
            ['Light', 'Dark', 'Transparent'][surface.index],
            (v) => setState(
              () => surface = LogoSurface
                  .values[['Light', 'Dark', 'Transparent'].indexOf(v)],
            ),
          ),
          _label('Ink'),
          _choices(
            ['Color', 'Black', 'White'],
            ['Color', 'Black', 'White'][ink.index],
            (v) => setState(
              () =>
                  ink = LogoInk.values[['Color', 'Black', 'White'].indexOf(v)],
            ),
          ),
          _label('Size & layout'),
          DropdownButtonFormField<String>(
            key: const Key('logo-export-preset'),
            initialValue: preset.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Export size'),
            items: [
              for (final option in logoExportPresets)
                DropdownMenuItem(value: option.id, child: Text(option.label)),
            ],
            onChanged: busy
                ? null
                : (value) {
                    if (value != null) {
                      setState(
                        () => exportPreset = logoExportPresets.indexWhere(
                          (p) => p.id == value,
                        ),
                      );
                    }
                  },
          ),
          const SizedBox(height: 12),
          Text(
            '${preset.width} × ${preset.height} pixels · ${preset.iconOnly ? 'Symbol only' : 'Complete logo'}',
            style: TextStyle(color: skin.mutedText, height: 1.4),
          ),
          if (lowContrast)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'This ink blends into the selected background. Choose a more contrasting ink or a Transparent background for a clearer logo.',
                style: TextStyle(color: skin.text, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _start() => [
    _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/branding/korlix_mini_mark.png',
                width: 30,
                height: 30,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'KORLIX / LOGO STUDIO',
                  style: TextStyle(
                    color: skin.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _heading(
            'Big ideas.\nA signature to match.',
            'Tell us about your brand. We’ll build six editable directions, ready for your finishing touch.',
          ),
          Transform.rotate(
            angle: -.018,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: skin.primary.withValues(alpha: .12),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: _canvas(
                logoDirections(
                  brief.copy(
                    name: _name.text.trim().isEmpty
                        ? 'YOUR BRAND'
                        : _name.text.trim(),
                  ),
                ).first,
                key: const Key('logo-live-preview'),
                backdrop: LogoSurface.light,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'LIVE PREVIEW  ·  EDITABLE SVG  ·  TRANSPARENT PNG',
            style: TextStyle(
              color: skin.mutedText,
              fontSize: 10,
              letterSpacing: .6,
            ),
          ),
        ],
      ),
    ),
    _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('A little inspiration'),
          _presetCards(),
          const SizedBox(height: 24),
          _heading(
            'First, your brand.',
            'A name and a little direction are all you need.',
          ),
          TextField(
            key: const Key('logo-brand-name'),
            controller: _name,
            maxLength: 50,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Business or brand name',
              hintText: 'e.g. Da Final Stop',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('logo-tagline'),
            controller: _tagline,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Tagline (optional)',
              hintText: 'A few words that make you memorable',
            ),
          ),
          _label('What do you do?'),
          DropdownButtonFormField<String>(
            key: ValueKey('logo-industry-$industry'),
            initialValue: industry,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Industry'),
            items: [
              for (final v in logoIndustries)
                DropdownMenuItem(value: v, child: Text(v)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => industry = v);
            },
          ),
          _label('Your personality'),
          _choices(logoStyles, style, (v) => setState(() => style = v)),
          _label('A color direction'),
          _paletteChoices(),
          const SizedBox(height: 20),
          TextField(
            key: const Key('logo-idea'),
            controller: _idea,
            maxLength: 700,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Ideas for AI exploration (optional)',
              hintText: 'A rising sun, warm hospitality, a neighborhood café…',
              alignLabelWithHint: true,
            ),
          ),
          if (widget.allowVoice)
            TextButton.icon(
              onPressed: busy ? null : _voice,
              icon: const Icon(Icons.mic_none_rounded),
              label: const Text('Tell K-Nova your idea'),
            ),
          const SizedBox(height: 16),
          KorlixActionButton(
            key: const Key('logo-generate'),
            label: 'Create my logos',
            icon: Icons.auto_awesome_rounded,
            subtitle: 'Six editable directions · no AI credit used',
            expand: true,
            onPressed: ready && !busy ? _generate : null,
          ),
        ],
      ),
    ),
  ];

  List<Widget> _ideas() => [
    _heading(
      'Meet your possibilities.',
      'Choose a direction. Every symbol, color, and line of text can be changed.',
    ),
    if (c.shortlist.isNotEmpty) _shortlistPanel(),
    if (c.concepts.isNotEmpty)
      LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var i = 0; i < c.concepts.length; i++)
              SizedBox(
                width: (constraints.maxWidth - 12) / 2,
                child: Material(
                  color: skin.panel,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey('logo-concept-$i'),
                    onTap: busy ? null : () => _choose(c.concepts[i]),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _canvas(c.concepts[i], backdrop: LogoSurface.light),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            logoDirectionNames[i],
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 4,
                            children: [
                              Text(
                                'Customize',
                                style: TextStyle(
                                  color: skin.primary,
                                  fontSize: 12,
                                ),
                              ),
                              IconButton(
                                key: ValueKey('logo-shortlist-$i'),
                                tooltip: c.isShortlisted(c.concepts[i])
                                    ? 'Remove from shortlist'
                                    : 'Shortlist to compare',
                                onPressed: busy
                                    ? null
                                    : () => _shortlist(c.concepts[i]),
                                icon: Icon(
                                  c.isShortlisted(c.concepts[i])
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                ),
                                color: c.isShortlisted(c.concepts[i])
                                    ? const Color(0xFFBC2861)
                                    : skin.mutedText,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    const SizedBox(height: 18),
    _pair(
      _action(
        'More directions',
        Icons.refresh_rounded,
        busy ? null : () => c.generate(c.design, preserveSelection: true),
      ),
      _action('Edit selected', Icons.tune_rounded, busy ? null : () => _go(2)),
    ),
    const SizedBox(height: 24),
    _aiPanel(),
  ];

  Widget _aiPanel() {
    final selected = _selectedAi;
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(
            'Take a creative detour.',
            'Ask AI for a custom visual concept using your brand brief. AI artwork downloads as PNG; the editable logos and SVG kit remain separate.',
          ),
          Text(
            '1 generation credit per completed AI concept. Review lettering before using it.',
            style: TextStyle(color: skin.mutedText, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 16),
          KorlixActionButton(
            label: c.images.busy
                ? 'Creating · ${c.images.elapsed}s'
                : 'Explore with AI',
            icon: Icons.auto_awesome_rounded,
            expand: true,
            onPressed: busy ? null : _ai,
          ),
          if (c.images.busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
          if (selected != null) ...[
            const SizedBox(height: 22),
            Text(
              'Your AI explorations',
              style: TextStyle(
                color: skin.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select an artwork to preview and download. Up to six recent concepts stay here during this session.',
              style: TextStyle(color: skin.mutedText, height: 1.4),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < c.images.results.length; i++)
                    SizedBox(
                      width:
                          (constraints.maxWidth -
                              (constraints.maxWidth >= 500 ? 20 : 10)) /
                          (constraints.maxWidth >= 500 ? 3 : 2),
                      child: Semantics(
                        selected: selected.id == c.images.results[i].id,
                        child: Material(
                          color: skin.panelDeep,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: selected.id == c.images.results[i].id
                                  ? skin.primary
                                  : skin.border,
                              width: selected.id == c.images.results[i].id
                                  ? 3
                                  : 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: ValueKey('logo-ai-result-$i'),
                            onTap: busy
                                ? null
                                : () => setState(
                                    () =>
                                        _selectedAiId = c.images.results[i].id,
                                  ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AspectRatio(
                                  aspectRatio: 1,
                                  child: Image.memory(
                                    c.images.results[i].bytes,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) =>
                                        const Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    '${i + 1} · ${c.images.results[i].brief.lettering.split('\n').first}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'AI concept: ${selected.brief.lettering.split('\n').first}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 440),
                child: Image.memory(
                  selected.bytes,
                  key: ValueKey('logo-ai-preview-${selected.id}'),
                  gaplessPlayback: true,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'This artwork could not be displayed. Try another concept.',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _download(
              'Download AI concept',
              Icons.download_rounded,
              'ai',
              subtitle: '${selected.width} × ${selected.height} PNG artwork',
            ),
            const SizedBox(height: 10),
            Text(
              'Download to keep this artwork before closing the studio. Each file uses the selected concept’s brand name.',
              style: TextStyle(
                color: skin.mutedText,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _editor() => [
    _heading(
      'Make it unmistakably yours.',
      'Fine-tune your chosen direction. Your preview updates instantly.',
    ),
    _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _canvas(c.design),
          const SizedBox(height: 16),
          _choices(
            ['Light', 'Dark', 'Transparent'],
            ['Light', 'Dark', 'Transparent'][surface.index],
            (v) => setState(
              () => surface = LogoSurface
                  .values[['Light', 'Dark', 'Transparent'].indexOf(v)],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            children: [
              TextButton.icon(
                onPressed: busy || !c.canUndo ? null : c.undo,
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Undo'),
              ),
              TextButton.icon(
                onPressed: busy || !c.canRedo ? null : c.redo,
                icon: const Icon(Icons.redo_rounded),
                label: const Text('Redo'),
              ),
            ],
          ),
        ],
      ),
    ),
    _panel(LogoPreviewBoard(design: c.design)),
    _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('logo-edit-name'),
            controller: _name,
            maxLength: 50,
            onChanged: (v) => c.update(c.design.copy(name: v)),
            decoration: const InputDecoration(labelText: 'Brand name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _tagline,
            maxLength: 80,
            onChanged: (v) => c.update(c.design.copy(tagline: v)),
            decoration: const InputDecoration(labelText: 'Tagline'),
          ),
          _label('Composition'),
          _choices(
            logoLayouts,
            c.design.layout,
            (v) => c.update(c.design.copy(layout: v)),
          ),
          _label('Symbol'),
          _choices(
            logoMarks,
            c.design.mark,
            (v) => c.update(c.design.copy(mark: v)),
          ),
          _label('Typography'),
          _choices(
            logoTypefaces,
            c.design.typeface,
            (v) => c.update(c.design.copy(typeface: v)),
          ),
          _label('Letter spacing'),
          Slider(
            value: c.design.tracking,
            min: 0,
            max: 8,
            divisions: 16,
            label: c.design.tracking.toStringAsFixed(1),
            onChanged: busy
                ? null
                : (v) => c.update(c.design.copy(tracking: v)),
          ),
          _label('Symbol size'),
          Slider(
            value: c.design.symbolScale,
            min: .65,
            max: 1.25,
            divisions: 12,
            label: '${(c.design.symbolScale * 100).round()}%',
            onChanged: busy
                ? null
                : (v) => c.update(c.design.copy(symbolScale: v)),
          ),
          _label('Color palette'),
          _paletteChoices(editing: true),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('logo-primary-hex'),
                  controller: _hex,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Primary hex',
                    prefixText: '#',
                  ),
                  onChanged: (v) {
                    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(v)) {
                      c.update(c.design.copy(primary: v.toUpperCase()));
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('logo-accent-hex'),
                  controller: _accent,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Accent hex',
                    prefixText: '#',
                  ),
                  onChanged: (v) {
                    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(v)) {
                      c.update(c.design.copy(secondary: v.toUpperCase()));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            c.currentProjectId == null
                ? 'New project · not saved yet'
                : c.hasUnsavedChanges
                ? 'Unsaved changes'
                : 'Saved on this device',
            style: TextStyle(color: skin.mutedText, fontSize: 12),
          ),
          const SizedBox(height: 12),
          _pair(
            _action(
              c.saving
                  ? 'Saving…'
                  : c.currentProjectId == null
                  ? 'Save project'
                  : 'Save changes',
              Icons.bookmark_add_outlined,
              busy || c.saving ? null : _save,
            ),
            _action(
              'Get my brand kit',
              Icons.inventory_2_outlined,
              busy ? null : () => _go(3),
            ),
          ),
          if (c.currentProjectId != null)
            TextButton.icon(
              key: const Key('logo-save-copy'),
              onPressed: busy || c.saving ? null : () => _save(asCopy: true),
              icon: const Icon(Icons.copy_all_rounded),
              label: const Text('Save a copy'),
            ),
        ],
      ),
    ),
  ];

  List<Widget> _kit() => [
    _heading(
      'Your brand, ready to go.',
      'A coordinated collection for your website, profiles, presentations, and next big idea.',
    ),
    _exportConfigurator(),
    _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'THE COMPLETE BRAND KIT',
            style: TextStyle(
              color: skin.primary,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '• Editable SVG in color, black, and white\n• 2400 px PNGs: transparent, light, and dark\n• Profile icon, avatar, and social cover\n• PDF brand guide with colors and typography\n• Editable project backup and matching fonts',
            style: TextStyle(height: 1.8),
          ),
          const SizedBox(height: 20),
          _download(
            'Download brand kit',
            Icons.folder_zip_outlined,
            'kit',
            subtitle: 'Everything in one ZIP',
          ),
        ],
      ),
    ),
    _pair(
      _download(
        'Download PNG',
        Icons.image_outlined,
        'png',
        subtitle:
            '${logoExportPresets[exportPreset].width} × ${logoExportPresets[exportPreset].height} · ${surface.name}',
      ),
      _download(
        'Download SVG',
        Icons.polyline_outlined,
        'svg',
        subtitle: '${ink.name} vector · ${surface.name}',
      ),
    ),
    const SizedBox(height: 14),
    _pair(
      _download('Brand guide', Icons.picture_as_pdf_outlined, 'pdf'),
      _download('Project backup', Icons.save_outlined, 'project'),
    ),
    const SizedBox(height: 20),
    Text(
      'PNG and SVG use your export settings above. Transparent previews show a checkerboard; the downloaded file has no checkerboard. The complete ZIP includes all standard variants. SVG retains editable text; some editors may need the bundled Roboto fonts. AI artwork downloads separately from Ideas.',
      style: TextStyle(color: skin.mutedText, height: 1.5, fontSize: 12),
    ),
  ];

  List<Widget> _saved() => [
    _heading(
      'Keep your best ideas.',
      'Projects are saved in this account on this device. Export a backup to edit on another device.',
    ),
    _pair(
      _action(
        'Import project',
        Icons.file_upload_outlined,
        busy ? null : _import,
      ),
      _action(
        'New brand',
        Icons.add_rounded,
        busy
            ? null
            : () {
                c.newBrand();
                _selectedAiId = null;
                _sync(c.design);
                setState(() {
                  tab = 0;
                  palette = 0;
                  surface = LogoSurface.light;
                  ink = LogoInk.color;
                  exportPreset = 0;
                  error = notice = null;
                });
                _scrollTop();
              },
      ),
    ),
    const SizedBox(height: 20),
    if (!c.loaded)
      const Text(
        'Saved projects are not available yet. Reopen the studio to try again.',
      ),
    if (c.loaded && c.projects.isEmpty)
      _panel(
        const Text(
          'Your saved logos will live here. Open a design and choose Save project.',
        ),
      ),
    for (final project in c.projects)
      _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _canvas(
              LogoDesign.fromJson(Map<String, dynamic>.from(project['design'])),
              backdrop: LogoSurface.light,
            ),
            const SizedBox(height: 12),
            Text(
              '${project['design']['name']}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            Wrap(
              spacing: 12,
              children: [
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () {
                          try {
                            c.openProject('${project['id']}');
                            _sync(c.design);
                            _go(2);
                          } catch (e) {
                            _error(e);
                          }
                        },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Open project'),
                ),
                TextButton.icon(
                  onPressed: busy || c.saving
                      ? null
                      : () async {
                          try {
                            await c.delete('${project['id']}');
                            _say('Saved project removed from this device.');
                          } catch (e) {
                            _error(e);
                          }
                        },
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete saved copy'),
                ),
              ],
            ),
          ],
        ),
      ),
  ];

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('Logo Studio'),
        actions: [
          if (c.available && c.design.error == null)
            IconButton(
              tooltip: 'Save logo project',
              onPressed: busy || c.saving ? null : _save,
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: !c.available
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Your session changed. Reopen Logo Studio after signing in.',
                  ),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 940),
                  child: ListView(
                    key: ValueKey('logo-tab-$tab'),
                    controller: scroll,
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (error != null)
                        _panel(
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              error!,
                              style: TextStyle(color: skin.danger),
                            ),
                          ),
                        ),
                      if (notice != null)
                        _panel(
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              notice!,
                              style: TextStyle(color: skin.primary),
                            ),
                          ),
                        ),
                      if (exporting)
                        _panel(
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Preparing your files…'),
                              SizedBox(height: 12),
                              LinearProgressIndicator(),
                            ],
                          ),
                        ),
                      if (ready)
                        ...switch (tab) {
                          0 => _start(),
                          1 => _ideas(),
                          2 => _editor(),
                          3 => _kit(),
                          _ => _saved(),
                        }
                      else
                        const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
      ),
      bottomNavigationBar: !c.available
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: busy ? null : _go,
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.edit_note_rounded),
                  label: 'Start',
                  tooltip: 'Brand brief',
                ),
                NavigationDestination(
                  icon: Icon(Icons.auto_awesome_mosaic_outlined),
                  label: 'Ideas',
                  tooltip: 'Logo directions',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune_rounded),
                  label: 'Edit',
                  tooltip: 'Edit logo',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  label: 'Kit',
                  tooltip: 'Brand kit',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bookmarks_outlined),
                  label: 'Saved',
                  tooltip: 'Saved projects',
                ),
              ],
            ),
    ),
  );
}
