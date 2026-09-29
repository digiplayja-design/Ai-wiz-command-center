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

  void _session() {
    if (!c.available) {
      _name.clear();
      _tagline.clear();
      _idea.clear();
      _hex.clear();
      _accent.clear();
      error = notice = null;
    } else if (tab == 2) {
      _sync(c.design);
    }
  }

  void _sync(LogoDesign d) {
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
        : 'That action could not finish. Please try again.';
    setState(() => error = message);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  LogoDesign get brief {
    final p = logoPalettes[palette];
    return LogoDesign(
      name: _name.text.trim(),
      tagline: _tagline.text.trim(),
      industry: industry,
      style: style,
      idea: _idea.text.trim(),
      primary: p.primary,
      secondary: p.secondary,
      paper: p.paper,
    );
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
    } catch (e) {
      _error(e);
    } finally {
      if (mounted) setState(() => consenting = false);
    }
  }

  Future<void> _save() async {
    try {
      await c.save();
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
      if (scroll.hasClients) scroll.jumpTo(0);
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
    final ai = c.images.results.isEmpty ? null : c.images.results.first;
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
          bytes = Uint8List.fromList(utf8.encode(await logoSvg(d)));
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
          bytes = ai.bytes;
          extension = 'ai-concept.png';
          mime = 'image/png';
        default:
          bytes = await logoPng(d, surface: surface);
          extension = 'png';
          mime = 'image/png';
      }
      guard();
      await io.save(bytes, '${d.filename}.$extension', mime, origin);
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
                    c.design.secondary == logoPalettes[i].secondary
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
                    setState(() => palette = i);
                  }
                },
        ),
    ],
  );
  Widget _canvas(LogoDesign d, {LogoSurface? backdrop, bool icon = false}) =>
      ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: LogoCanvas(
          design: d,
          surface: backdrop ?? surface,
          iconOnly: icon,
        ),
      );

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
                const LogoDesign(
                  name: 'NORTHLINE',
                  tagline: 'BUILD WHAT’S NEXT',
                  primary: '155BE8',
                  secondary: '26B8D7',
                  paper: 'F4F6FB',
                ),
                backdrop: LogoSurface.light,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'SAMPLE DESIGN  ·  EDITABLE SVG  ·  TRANSPARENT PNG',
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
                          child: Text(
                            'Customize',
                            style: TextStyle(color: skin.primary, fontSize: 12),
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
        busy ? null : () => c.generate(c.design),
      ),
      _action('Edit selected', Icons.tune_rounded, busy ? null : () => _go(2)),
    ),
    const SizedBox(height: 24),
    _aiPanel(),
  ];

  Widget _aiPanel() => _panel(
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
        if (c.images.results.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'AI concept: ${c.images.results.first.brief.lettering.split('\n').first}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.memory(
              c.images.results.first.bytes,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'This artwork could not be displayed. Try another concept.',
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _download(
            'Download AI concept',
            Icons.download_rounded,
            'ai',
            subtitle: 'PNG artwork',
          ),
          const SizedBox(height: 10),
          Text(
            'Download to keep this artwork before closing the studio.',
            style: TextStyle(color: skin.mutedText, fontSize: 12),
          ),
        ],
      ],
    ),
  );

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
          _pair(
            _action(
              c.saving ? 'Saving…' : 'Save project',
              Icons.bookmark_add_outlined,
              busy || c.saving ? null : _save,
            ),
            _action(
              'Get my brand kit',
              Icons.inventory_2_outlined,
              busy ? null : () => _go(3),
            ),
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
    _canvas(c.design, backdrop: LogoSurface.light),
    const SizedBox(height: 12),
    _canvas(c.design, backdrop: LogoSurface.dark),
    const SizedBox(height: 18),
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
        subtitle: '${surface.name} background',
      ),
      _download(
        'Download SVG',
        Icons.polyline_outlined,
        'svg',
        subtitle: 'Transparent vector',
      ),
    ),
    const SizedBox(height: 14),
    _pair(
      _download('Brand guide', Icons.picture_as_pdf_outlined, 'pdf'),
      _download('Project backup', Icons.save_outlined, 'project'),
    ),
    const SizedBox(height: 20),
    Text(
      'Choose the PNG background in Edit. SVG retains editable text; some editors may need the bundled Roboto fonts. AI concept artwork is downloaded separately from Ideas.',
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
                c.choose(const LogoDesign());
                _sync(c.design);
                setState(() {
                  tab = 0;
                  palette = 0;
                });
                if (scroll.hasClients) scroll.jumpTo(0);
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
                      : () => _choose(
                          LogoDesign.fromJson(
                            Map<String, dynamic>.from(project['design']),
                          ),
                        ),
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
