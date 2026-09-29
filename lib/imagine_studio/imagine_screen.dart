import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/korlix_theme.dart';
import '../theme/korlix_action_button.dart';
import '../korlix_image_saver.dart';
import '../input_tools/voice_composer.dart';
import 'imagine_catalog.dart';
import 'imagine_client.dart';
import 'imagine_art.dart';
import 'imagine_idea_builder.dart';
import 'imagine_canvas_guide.dart';

class ImagineStudioScreen extends StatefulWidget {
  const ImagineStudioScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    required this.onRefine,
    this.language = 'en',
    this.allowVoice = false,
    this.saveImage,
  });
  final ImagineClient client;
  final Future<bool> Function() ensureConsent;
  final Future<void> Function(ImagineResult) onRefine;
  final String language;
  final bool allowVoice;
  final Future<void> Function(Uint8List, String)? saveImage;
  @override
  State<ImagineStudioScreen> createState() => _ImagineStudioScreenState();
}

class _ImagineStudioScreenState extends State<ImagineStudioScreen> {
  late final TextEditingController _prompt, _lettering, _avoid;
  String _style = 'auto',
      _size = '1024x1024',
      _lighting = 'auto',
      _palette = 'auto',
      _composition = 'auto';
  String? _selectedId, _localError;
  int _tab = 0;
  bool _consenting = false, _saving = false, _dictating = false;
  ImagineClient get c => widget.client;
  KorlixSkinPalette get s => korlixSkinOf(context);
  bool get locked => c.busy || _consenting || _dictating || !c.available;
  ImagineBrief get brief => ImagineBrief(
    prompt: _prompt.text,
    style: _style,
    size: _size,
    lighting: _lighting,
    palette: _palette,
    composition: _composition,
    lettering: _lettering.text,
    avoid: _avoid.text,
  );
  ImagineResult? get selected => c.results.isEmpty
      ? null
      : c.results.firstWhere(
          (x) => x.id == _selectedId,
          orElse: () => c.results.first,
        );
  @override
  void initState() {
    super.initState();
    _prompt = TextEditingController();
    _lettering = TextEditingController();
    _avoid = TextEditingController();
    _setBrief(c.draft);
    c.addListener(_accountChanged);
    unawaited(c.loadBriefs());
  }

  void _accountChanged() {
    if (!c.available) {
      _prompt.clear();
      _lettering.clear();
      _avoid.clear();
      _selectedId = null;
    }
  }

  @override
  void dispose() {
    if (c.available) c.draft = brief;
    c.removeListener(_accountChanged);
    _prompt.dispose();
    _lettering.dispose();
    _avoid.dispose();
    super.dispose();
  }

  void _setBrief(ImagineBrief b) {
    _prompt.text = b.prompt;
    _lettering.text = b.lettering;
    _avoid.text = b.avoid;
    _style = b.style;
    _size = b.size;
    _lighting = b.lighting;
    _palette = b.palette;
    _composition = b.composition;
    _localError = null;
  }

  void notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _dictate() async {
    if (locked || !widget.allowVoice) return;
    setState(() => _dictating = true);
    try {
      final draft = await Navigator.of(context).push<KorlixVoiceDraft>(
        MaterialPageRoute(
          builder: (_) => KorlixVoiceComposer(
            initialText: _prompt.text,
            language: widget.language,
            sessionChanges: c,
            isSessionCurrent: () => c.available,
            showLiveConvo: false,
          ),
        ),
      );
      if (!mounted || !c.available || draft == null) return;
      setState(() {
        _prompt.text = draft.text;
        _localError = null;
      });
    } finally {
      if (mounted) setState(() => _dictating = false);
    }
  }

  Future<void> _buildIdea() async {
    if (locked) return;
    final previous = _prompt.text;
    final idea = await showDialog<String>(
      context: context,
      builder: (_) => AnimatedBuilder(
        animation: c,
        builder: (context, _) => c.available
            ? ImagineIdeaBuilder(initialText: previous)
            : AlertDialog(
                title: const Text('Your session changed'),
                content: const Text('Close this window and sign in again.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
      ),
    );
    if (idea == null || !mounted || !c.available || locked) return;
    setState(() {
      _prompt.text = idea;
      _localError = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Your idea is ready to edit. Choose Create when ready.',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (mounted && c.available && !locked) {
              setState(() => _prompt.text = previous);
            }
          },
        ),
      ),
    );
  }

  Future<void> _create() async {
    if (locked) return;
    final b = brief;
    if (b.error != null) {
      setState(() => _localError = b.error);
      notice(b.error!);
      return;
    }
    setState(() => _consenting = true);
    try {
      if (!await widget.ensureConsent() || !mounted || !c.available) return;
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _localError = null);
      final result = await c.create(b, language: widget.language);
      if (mounted && c.available && result != null) {
        setState(() {
          _selectedId = result.id;
          _tab = 1;
        });
      }
    } catch (e) {
      if (mounted && c.available) {
        setState(() => _localError = c.error ?? '$e');
        notice(_localError!);
      }
    } finally {
      if (mounted) setState(() => _consenting = false);
    }
  }

  Future<void> _save(ImagineResult r) async {
    if (_saving || !c.available) return;
    setState(() => _saving = true);
    try {
      final filename =
          'korlix-imagine-${r.createdAt.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '')}.png';
      if (widget.saveImage != null) {
        await widget.saveImage!(r.bytes, filename);
      } else {
        await saveKorlixGeneratedImage(
          bytes: r.bytes,
          filename: filename,
          mimeType: 'image/png',
        );
      }
      if (c.available) {
        notice('Save or share your PNG using your device’s options.');
      }
    } catch (_) {
      notice('The download could not open. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveBrief() async {
    if (brief.error != null) {
      setState(() => _localError = brief.error);
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AnimatedBuilder(
        animation: c,
        builder: (context, _) => c.available
            ? const _ImagineBriefNameDialog()
            : AlertDialog(
                title: const Text('Your session changed'),
                content: const Text('Close this window and sign in again.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
      ),
    );
    if (name == null || !mounted || !c.available) return;
    try {
      await c.saveBrief(name, brief);
      notice('Creative brief saved.');
    } catch (e) {
      notice('$e');
    }
  }

  void _starter(ImagineStarter starter) {
    final previous = brief;
    setState(() => _setBrief(starter.brief));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${starter.title} is ready to customize.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (mounted && c.available && !locked) {
              setState(() => _setBrief(previous));
            }
          },
        ),
      ),
    );
  }

  Future<void> _zoom(ImagineResult r) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AnimatedBuilder(
        animation: c,
        builder: (_, _) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Your creation'),
              leading: IconButton(
                tooltip: 'Close preview',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            body: c.available
                ? InteractiveViewer(
                    minScale: .5,
                    maxScale: 6,
                    child: Center(
                      child: Image.memory(
                        r.bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Text('This preview could not be displayed.'),
                      ),
                    ),
                  )
                : const Center(child: Text('Your session changed.')),
          ),
        ),
      ),
    );
  }

  Widget panel(Widget child, {EdgeInsets padding = const EdgeInsets.all(22)}) =>
      Container(
        padding: padding,
        decoration: BoxDecoration(
          color: s.panelDeep,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: s.border.withValues(alpha: .6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: s.isLight ? .04 : .18),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(color: Colors.transparent, child: child),
      );
  Widget heading(String title, {String? subtitle, Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: s.text,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: s.mutedText,
                    height: 1.45,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
  Widget _hero() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: LinearGradient(
        colors: [Color.lerp(s.panel, s.secondary, .13)!, s.panelDeep],
      ),
      border: Border.all(color: s.secondary.withValues(alpha: .35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'KORLIX  /  CREATIVE STUDIO',
          style: TextStyle(
            color: s.primary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth > 600;
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your imagination.\nBeautifully made.',
                        style: TextStyle(
                          fontSize: wide ? 38 : 25,
                          height: 1.12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.9,
                          color: s.text,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Start with a thought. Shape the look.\nMake it yours.',
                        style: TextStyle(
                          color: s.mutedText,
                          height: 1.5,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                if (box.maxWidth > 260 &&
                    MediaQuery.textScalerOf(context).scale(1) < 1.3) ...[
                  const SizedBox(width: 20),
                  Transform.rotate(
                    angle: -.06,
                    child: Container(
                      width: wide ? 230 : 84,
                      height: wide ? 174 : 135,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(23),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .25),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: s.secondary.withValues(alpha: .2),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: const ImagineArtwork(),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    ),
  );
  Widget _styles() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'Choose the feeling',
        subtitle: 'Swipe through visual styles. Your words stay in control.',
      ),
      SizedBox(
        height: 154 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 2),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: imagineStyles.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final choice = imagineStyles[i], active = _style == choice.id;
            return SizedBox(
              width: 145,
              child: Semantics(
                selected: active,
                button: true,
                child: Material(
                  color: active
                      ? Color.lerp(s.panel, s.secondary, .15)
                      : s.panel,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    key: ValueKey('imagine-style-${choice.id}'),
                    onTap: locked
                        ? null
                        : () => setState(() => _style = choice.id),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(
                              s.panel,
                              s.secondary,
                              active ? .23 : .05,
                            )!,
                            s.panelDeep,
                          ],
                        ),
                        border: Border.all(
                          color: active ? s.secondary : s.border,
                          width: active ? 1.8 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: s.secondary.withValues(
                                    alpha: active ? .17 : .07,
                                  ),
                                  border: Border.all(
                                    color: s.secondary.withValues(
                                      alpha: active ? .5 : .18,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withValues(
                                        alpha: .06,
                                      ),
                                      offset: const Offset(-1, -1),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  choice.icon,
                                  color: active ? s.secondary : s.mutedText,
                                  size: 23,
                                ),
                              ),
                              const Spacer(),
                              if (active)
                                Icon(
                                  Icons.check_circle_rounded,
                                  color: s.secondary,
                                  size: 18,
                                ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            choice.label,
                            style: TextStyle(
                              color: s.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            choice.hint,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: s.mutedText,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
  Widget _format() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading('Frame your idea'),
      ImagineCanvasGuide(brief: brief),
      const SizedBox(height: 14),
      LayoutBuilder(
        builder: (context, box) => Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final choice in imagineSizes)
              SizedBox(
                width: box.maxWidth >= 390
                    ? (box.maxWidth - 20) / 3
                    : (box.maxWidth - 10) / 2,
                child: KorlixActionButton(
                  label: choice.label,
                  subtitle: choice.hint,
                  icon: choice.icon,
                  tile: true,
                  selected: _size == choice.id,
                  onPressed: locked
                      ? null
                      : () => setState(() => _size = choice.id),
                ),
              ),
          ],
        ),
      ),
    ],
  );
  Widget _select(
    String title,
    String value,
    Map<String, String> options,
    ValueChanged<String> set,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$title-$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: title,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    items: [
      for (final x in options.entries)
        DropdownMenuItem(
          value: x.key,
          child: Text(x.value, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: locked
        ? null
        : (v) {
            if (v != null) setState(() => set(v));
          },
  );
  Widget _direction() => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 12),
      leading: Icon(Icons.tune_rounded, color: s.primary),
      title: const Text(
        'Art direction',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: const Text('Light, color, composition & lettering'),
      children: [
        _select('Lighting', _lighting, imagineLighting, (v) => _lighting = v),
        const SizedBox(height: 16),
        _select(
          'Color palette',
          _palette,
          imaginePalettes,
          (v) => _palette = v,
        ),
        const SizedBox(height: 16),
        _select(
          'Composition',
          _composition,
          imagineComposition,
          (v) => _composition = v,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _lettering,
          enabled: !locked,
          maxLength: 300,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Exact words in the image',
            hintText: 'Optional: a title, a short message, a name',
            helperText: 'Check spelling before creating.',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _avoid,
          enabled: !locked,
          maxLength: 600,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Details to avoid',
            hintText: 'Optional: colors, objects or visual details',
          ),
        ),
      ],
    ),
  );
  Widget _editor() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          'Describe your picture',
          subtitle:
              'Who or what is in the scene? Where is it? How should it feel?',
        ),
        TextField(
          key: const Key('imagine-prompt'),
          controller: _prompt,
          enabled: !locked,
          minLines: 4,
          maxLines: 8,
          maxLength: 8000,
          style: TextStyle(color: s.text, fontSize: 16, height: 1.5),
          onChanged: (_) => setState(() => _localError = null),
          decoration: InputDecoration(
            hintText:
                'A luminous glass sculpture above a calm ocean at sunrise…',
            filled: true,
            fillColor: s.inputFill,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            KorlixActionButton(
              key: const Key('imagine-build-idea'),
              label: 'Build my idea',
              icon: Icons.auto_fix_high_rounded,
              size: KorlixButtonSize.compact,
              accent: s.secondary,
              onPressed: locked ? null : _buildIdea,
            ),
            TextButton.icon(
              onPressed: locked
                  ? null
                  : () => _starter(
                      imagineStarters[math.Random().nextInt(
                        imagineStarters.length,
                      )],
                    ),
              icon: const Icon(Icons.casino_outlined, size: 18),
              label: const Text('Surprise me'),
            ),
            if (widget.allowVoice)
              TextButton.icon(
                onPressed: locked ? null : _dictate,
                icon: const Icon(Icons.mic_none_rounded, size: 18),
                label: const Text('Speak your idea'),
              ),

            TextButton.icon(
              onPressed: locked || c.savingBrief ? null : _saveBrief,
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: const Text('Save brief'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _styles(),
        const SizedBox(height: 24),
        _format(),
        const SizedBox(height: 14),
        _direction(),
        if (_localError != null || c.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _localError ?? c.error!,
                style: TextStyle(color: s.danger, height: 1.5),
              ),
            ),
          ),
        const SizedBox(height: 16),
        const SizedBox(height: 12),
        Text(
          'Nothing is generated until you tap Create. You can adjust the result in Picture Studio afterward.',
          style: TextStyle(color: s.mutedText, fontSize: 12, height: 1.5),
        ),
      ],
    ),
  );
  Widget _createDock() => Container(
    decoration: BoxDecoration(
      color: s.panelDeep,
      border: Border(top: BorderSide(color: s.border)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .12),
          blurRadius: 20,
          offset: const Offset(0, -4),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Align(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${brief.sizeLabel} · ${brief.styleLabel}',
                style: TextStyle(color: s.mutedText, fontSize: 11),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 7),
              KorlixActionButton(
                key: const Key('imagine-create'),
                label: c.busy
                    ? 'Creating your picture…'
                    : _consenting
                    ? 'Preparing…'
                    : 'Create picture',
                subtitle: '1 image · 1 credit · High-quality PNG',
                icon: Icons.auto_awesome_rounded,
                accent: s.secondary,
                tile:
                    MediaQuery.sizeOf(context).width < 360 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3,
                size:
                    MediaQuery.sizeOf(context).width < 360 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.3
                    ? KorlixButtonSize.regular
                    : KorlixButtonSize.hero,
                expand: true,
                busy: locked,
                onPressed: locked ? null : _create,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _progress() => panel(
    Row(
      children: [
        SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(strokeWidth: 2, color: s.secondary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your idea is taking shape',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              Text(
                '${c.elapsed}s elapsed · Detailed images can take a few minutes. Keep the app open.',
                style: TextStyle(color: s.mutedText, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    ),
    padding: const EdgeInsets.all(18),
  );
  Widget _emptyPreview() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: const AspectRatio(aspectRatio: 1.15, child: ImagineArtwork()),
        ),
        const SizedBox(height: 20),
        heading(
          'A canvas for your next idea',
          subtitle:
              'Your generated picture will appear here. Try a prompt starter or write something entirely your own.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _tag('9 visual styles', Icons.palette_outlined),
            _tag('3 canvas sizes', Icons.crop_rounded),
            _tag('Made from your words', Icons.auto_awesome_outlined),
          ],
        ),
      ],
    ),
  );
  Widget _tag(String text, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: s.panel,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: s.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: s.primary),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: s.mutedText, fontSize: 11)),
      ],
    ),
  );
  Widget _preview(ImagineResult r) => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          'Made from your imagination',
          subtitle: '${r.width} × ${r.height} · PNG · ${r.brief.styleLabel}',
        ),
        Material(
          color: s.inputFill,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _zoom(r),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 570),
              child: Center(
                child: Image.memory(
                  r.bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(30),
                    child: Text(
                      'Preview unavailable. You can still download the PNG.',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            KorlixActionButton(
              label: _saving ? 'Opening download…' : 'Download PNG',
              icon: Icons.download_rounded,
              accent: s.primary,
              onPressed: _saving ? null : () => _save(r),
            ),
            KorlixActionButton(
              label: 'Zoom',
              icon: Icons.zoom_in_rounded,
              onPressed: () => _zoom(r),
            ),
            KorlixActionButton(
              label: 'Refine picture',
              icon: Icons.auto_fix_high_rounded,
              onPressed: locked ? null : () => widget.onRefine(r),
            ),
            KorlixActionButton(
              label: 'Reuse settings',
              icon: Icons.refresh_rounded,
              onPressed: locked
                  ? null
                  : () {
                      setState(() {
                        _setBrief(r.brief);
                        _tab = 0;
                      });
                      notice(
                        'Settings copied. Edit your description, then create a new image.',
                      );
                    },
            ),
          ],
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'Creative brief',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                r.brief.compiledPrompt,
                style: TextStyle(color: s.mutedText, height: 1.5),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: r.brief.compiledPrompt),
                  );
                  notice('Creative brief copied.');
                },
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('Copy brief'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  Widget _starters() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'A little inspiration',
        subtitle: 'Prompt starters to customize. Artwork is decorative.',
      ),
      LayoutBuilder(
        builder: (context, box) {
          final count = box.maxWidth > 950
              ? 3
              : box.maxWidth > 570
              ? 2
              : 1;
          final width = (box.maxWidth - (count - 1) * 14) / count;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final item in imagineStarters)
                SizedBox(
                  width: width,
                  child: Material(
                    color: s.panelDeep,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: locked ? null : () => _starter(item),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AspectRatio(
                            aspectRatio: 2.3,
                            child: ImagineArtwork(variant: item.art),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        style: TextStyle(
                                          color: s.text,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.note,
                                        style: TextStyle(
                                          color: s.mutedText,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.north_east_rounded,
                                  color: s.primary,
                                  size: 19,
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
          );
        },
      ),
    ],
  );
  Widget _createTab() => Column(
    children: [
      _hero(),
      const SizedBox(height: 24),
      LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < 980) {
            return Column(
              children: [
                _editor(),
                const SizedBox(height: 22),
                selected == null ? _emptyPreview() : _preview(selected!),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: _editor()),
              const SizedBox(width: 24),
              Expanded(
                flex: 5,
                child: selected == null ? _emptyPreview() : _preview(selected!),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 32),
      _starters(),
    ],
  );
  Widget _gallery() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'Recent creations',
        subtitle:
            'Your 6 most recent pictures, kept while the app is open. Download the ones you want to keep.',
      ),
      if (c.results.isEmpty)
        _emptyPreview()
      else ...[
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: c.results.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final r = c.results[i];
              return Semantics(
                label: 'Creation ${i + 1}',
                selected: selected?.id == r.id,
                button: true,
                child: InkWell(
                  onTap: () => setState(() => _selectedId = r.id),
                  child: Container(
                    width: 105,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: selected?.id == r.id ? s.secondary : s.border,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.memory(
                        r.bytes,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.image_not_supported_outlined),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        _preview(selected!),
      ],
    ],
  );
  Widget _briefs() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'Your creative briefs',
        subtitle:
            'Reusable prompts and settings saved on this device for your account. Images are not stored here.',
      ),
      if (c.recipes.isEmpty)
        panel(
          Column(
            children: [
              Icon(Icons.bookmarks_outlined, size: 45, color: s.secondary),
              const SizedBox(height: 14),
              const Text(
                'Keep a good idea close',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Build your picture, then tap Save brief to use its words and settings again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: s.mutedText, height: 1.5),
              ),
            ],
          ),
        )
      else
        for (final recipe in c.recipes)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${recipe['name']}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete brief',
                        onPressed: c.savingBrief
                            ? null
                            : () async {
                                try {
                                  await c.deleteBrief('${recipe['id']}');
                                } catch (e) {
                                  notice('$e');
                                }
                              },
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                  Text(
                    '${recipe['brief']['prompt']}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: s.mutedText, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  KorlixActionButton(
                    label: 'Use this brief',
                    icon: Icons.north_east_rounded,
                    onPressed: locked
                        ? null
                        : () => setState(() {
                            _setBrief(
                              ImagineBrief.fromJson(
                                Map<String, dynamic>.from(recipe['brief']),
                              ),
                            );
                            _tab = 0;
                          }),
                  ),
                ],
              ),
            ),
          ),
    ],
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => Scaffold(
      backgroundColor: s.backgroundBottom,
      appBar: AppBar(
        title: const Text('Imagine a Picture'),
        centerTitle: false,
      ),
      bottomNavigationBar:
          c.available &&
              _tab == 0 &&
              MediaQuery.viewInsetsOf(context).bottom == 0
          ? _createDock()
          : null,
      body: !c.available
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(c.error ?? 'Sign in again to open the studio.'),
              ),
            )
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                key: ValueKey('imagine-tab-$_tab'),
                padding: EdgeInsets.all(
                  MediaQuery.sizeOf(context).width < 400 ? 16 : 24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1220),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final item in [
                              (0, 'Create', Icons.auto_awesome_outlined),
                              (1, 'Gallery', Icons.collections_outlined),
                              (2, 'Saved briefs', Icons.bookmarks_outlined),
                            ])
                              KorlixActionButton(
                                label: item.$2,
                                icon: item.$3,
                                selected: _tab == item.$1,
                                onPressed: () => setState(() => _tab = item.$1),
                                size: KorlixButtonSize.compact,
                              ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        if (c.busy) ...[
                          _progress(),
                          const SizedBox(height: 20),
                        ],
                        if (_tab == 0)
                          _createTab()
                        else if (_tab == 1)
                          _gallery()
                        else
                          _briefs(),
                        const SizedBox(height: 35),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    ),
  );
}

class _ImagineBriefNameDialog extends StatefulWidget {
  const _ImagineBriefNameDialog();
  @override
  State<_ImagineBriefNameDialog> createState() =>
      _ImagineBriefNameDialogState();
}

class _ImagineBriefNameDialogState extends State<_ImagineBriefNameDialog> {
  final field = TextEditingController();
  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save a creative brief'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Keep these words and settings on this device for your account.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: field,
          maxLength: 60,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Brief name',
            hintText: 'My product photography',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, field.text),
        child: const Text('Save brief'),
      ),
    ],
  );
}
