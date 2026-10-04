import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/korlix_action_button.dart';
import '../theme/korlix_theme.dart';
import '../input_tools/voice_composer.dart';
import '../live_convo/agent_studio_client.dart' show agentStudioKey;
import 'email_artwork.dart';
import 'email_client.dart';
import 'email_io.dart';
import 'email_model.dart';

class EmailEnhancerScreen extends StatefulWidget {
  const EmailEnhancerScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    this.allowVoice = false,
    this.language = 'en',
    this.io,
  });
  final EmailEnhancerClient client;
  final Future<bool> Function() ensureConsent;
  final bool allowVoice;
  final String language;
  final EmailEnhancerIo? io;
  @override
  State<EmailEnhancerScreen> createState() => _EmailEnhancerScreenState();
}

class _EmailEnhancerScreenState extends State<EmailEnhancerScreen> {
  final source = TextEditingController(),
      contextNotes = TextEditingController(),
      recipient = TextEditingController(),
      goal = TextEditingController(),
      signature = TextEditingController(),
      subject = TextEditingController(),
      body = TextEditingController(),
      search = TextEditingController();
  final scroll = ScrollController();
  late final io = widget.io ?? EmailEnhancerIo();
  EmailEnhancerClient get c => widget.client;
  KorlixSkinPalette get skin => korlixSkinOf(context);
  String mode = 'Polish',
      tone = 'Professional',
      length = 'Keep similar',
      language = 'Original language',
      draftId = agentStudioKey();
  String? error, notice;
  bool working = false, loading = true, showOriginal = false, popping = false;
  int tab = 0;
  final versions = <EmailVersion>[];
  EmailVersion? selected;
  late String savedSnapshot;
  List<TextEditingController> get controllers => [
    source,
    contextNotes,
    recipient,
    goal,
    signature,
    subject,
    body,
  ];
  EmailBrief get brief => EmailBrief(
    source: source.text,
    context: contextNotes.text,
    recipient: recipient.text,
    goal: goal.text,
    signature: signature.text,
    mode: mode,
    tone: tone,
    length: length,
    language: language,
  );
  String get snapshot => jsonEncode({
    'brief': brief.json,
    'subject': subject.text,
    'body': body.text,
    'version': selected?.json,
  });
  bool get dirty => snapshot != savedSnapshot;
  @override
  void initState() {
    super.initState();
    savedSnapshot = snapshot;
    for (final x in controllers) {
      x.addListener(_changed);
    }
    search.addListener(_changed);
    c.addListener(_session);
    unawaited(_load());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      await c.load();
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _session() {
    if (!c.available) {
      for (final x in controllers) {
        x.clear();
      }
      versions.clear();
      selected = null;
      error = notice = null;
      savedSnapshot = snapshot;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_session);
    for (final x in [...controllers, search]) {
      x.dispose();
    }
    scroll.dispose();
    super.dispose();
  }

  void _fail(Object e) {
    if (!mounted || !c.available) return;
    setState(
      () => error = e is EmailEnhancerException
          ? e.message
          : 'That action could not finish. Your email is unchanged.',
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error!)));
  }

  void _say(String text) {
    if (mounted && c.available) {
      setState(() {
        notice = text;
        error = null;
      });
    }
  }

  Future<bool> _confirm(
    String title,
    String text, {
    String action = 'Continue',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<bool> _discard() async =>
      !dirty ||
      await _confirm(
        'Leave these changes?',
        'Save a draft or export your email to keep your latest edits.',
        action: 'Discard changes',
      );
  void _go(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => tab = index);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  void _sync(EmailBrief b) {
    source.text = b.source;
    contextNotes.text = b.context;
    recipient.text = b.recipient;
    goal.text = b.goal;
    signature.text = b.signature;
    mode = b.mode;
    tone = b.tone;
    length = b.length;
    language = b.language;
  }

  Future<void> _new([EmailBrief b = const EmailBrief()]) async {
    if (working || !await _discard() || !mounted || !c.available) return;
    setState(() {
      _sync(b);
      subject.clear();
      body.clear();
      selected = null;
      versions.clear();
      draftId = agentStudioKey();
      error = notice = null;
      showOriginal = false;
      if (b.source.isEmpty) savedSnapshot = snapshot;
    });
    _go(0);
  }

  Future<void> _enhance() async {
    if (working || !c.available) return;
    final input = brief;
    if (input.error != null) {
      _fail(EmailEnhancerException(input.error!));
      return;
    }
    if (selected != null &&
        (body.text != selected!.result.body ||
            !selected!.result.subjects.contains(subject.text)) &&
        !await _confirm(
          'Replace your edited email?',
          'The next enhancement uses your source text and settings. Save a draft first to keep your manual edits.',
          action: 'Enhance again',
        )) {
      return;
    }
    if (!mounted || !c.available) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      working = true;
      error = notice = null;
    });
    try {
      if (!await widget.ensureConsent() || !mounted) return;
      c.guard();
      final result = await c.enhance(input);
      if (!mounted || !c.available) return;
      setState(() {
        selected = EmailVersion(input, result);
        versions.insert(0, selected!);
        if (versions.length > 5) versions.removeLast();
        subject.text = result.subjects.first;
        body.text = result.body;
        showOriginal = false;
        notice = null;
      });
      _go(1);
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _save() async {
    if (working || !c.available) return;
    setState(() => working = true);
    final captured = snapshot;
    try {
      await c.save(
        EmailDraft(
          id: draftId,
          brief: brief,
          subject: subject.text,
          body: body.text,
          version: selected,
          savedAt: DateTime.now().toIso8601String(),
        ),
      );
      if (!mounted) return;
      savedSnapshot = captured;
      _say('Draft saved to this account on this device.');
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _openDraft(EmailDraft d) async {
    if (working || !await _discard() || !mounted || !c.available) return;
    setState(() {
      _sync(d.brief);
      subject.text = d.subject;
      body.text = d.body;
      selected = d.version;
      versions.clear();
      if (selected != null) versions.add(selected!);
      draftId = d.id;
      error = notice = null;
      showOriginal = false;
      savedSnapshot = snapshot;
    });
    _go(selected == null ? 0 : 1);
  }

  Future<void> _delete(EmailDraft d) async {
    if (working ||
        !await _confirm(
          'Delete this saved draft?',
          'This removes the saved copy from this account on this device.',
          action: 'Delete draft',
        ) ||
        !mounted ||
        !c.available) {
      return;
    }
    setState(() => working = true);
    try {
      await c.remove(d.id);
      _say('Saved draft deleted.');
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _voice() async {
    if (working || !c.available) return;
    if (!widget.allowVoice) {
      _say(
        'Rici dictation requires voice access on your plan. You can still type or import an email.',
      );
      return;
    }
    final target = mode == 'Reply' ? contextNotes : source;
    setState(() => working = true);
    try {
      final value = await Navigator.of(context).push<KorlixVoiceDraft>(
        MaterialPageRoute(
          builder: (_) => KorlixVoiceComposer(
            initialText: target.text,
            language: widget.language,
            sessionChanges: c,
            isSessionCurrent: () => c.available,
            showLiveConvo: false,
          ),
        ),
      );
      if (value != null && mounted && c.available) {
        final max = mode == 'Reply' ? 3000 : 12000;
        if (value.text.length > max) {
          throw EmailEnhancerException(
            'Keep this field under $max characters.',
          );
        }
        target.text = value.text;
      }
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _import() async {
    if (working) return;
    if (source.text.isNotEmpty &&
        !await _confirm(
          'Replace the source text?',
          'Your current source text will be replaced by the text file.',
          action: 'Choose file',
        )) {
      return;
    }
    if (!mounted || !c.available) return;
    setState(() => working = true);
    try {
      final text = await io.importText();
      if (text != null && mounted && c.available) source.text = text;
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _output(String action) async {
    if (working || !c.available) return;
    if (body.text.trim().isEmpty) {
      _say('Add an email body first.');
      return;
    }
    setState(() => working = true);
    try {
      c.guard();
      if (action == 'body' || action == 'email') {
        await io.copy(
          action == 'body' ? body.text : emailCopy(subject.text, body.text),
        );
        _say(
          action == 'body' ? 'Email body copied.' : 'Subject and email copied.',
        );
      } else {
        final box = context.findRenderObject() as RenderBox?;
        final rect = box == null
            ? const Rect.fromLTWH(0, 0, 1, 1)
            : box.localToGlobal(Offset.zero) & box.size;
        await io.export(
          action == 'eml'
              ? emailEml(subject.text, body.text)
              : emailCopy(subject.text, body.text),
          action,
          rect,
        );
        _say('Your export was opened for saving.');
      }
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _chooseVersion(EmailVersion v) async {
    if (working) return;
    if ((subject.text != selected?.result.subjects.first ||
            body.text != selected?.result.body) &&
        !await _confirm(
          'Switch to this version?',
          'Your current manual edits will be replaced. Save a draft first to keep them.',
          action: 'Switch version',
        )) {
      return;
    }
    if (!mounted || !c.available) return;
    setState(() {
      selected = v;
      subject.text = v.result.subjects.first;
      body.text = v.result.body;
    });
  }

  Widget _button(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    Key? key,
    bool active = false,
  }) => KorlixActionButton(
    key: key,
    label: label,
    icon: icon,
    onPressed: working ? null : onPressed,
    selected: active ? true : null,
    size: KorlixButtonSize.compact,
    accent: skin.secondary,
  );
  Widget _panel(List<Widget> children, {bool glow = false}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(skin.panel, skin.secondary, glow ? .08 : .025)!,
          skin.panelDeep,
        ],
      ),
      border: Border.all(
        color: glow ? skin.secondary.withValues(alpha: .42) : skin.border,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: skin.isLight ? .06 : .20),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
  Widget _heading(String n, String title, String description) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          n,
          style: TextStyle(
            color: skin.secondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          title,
          style: TextStyle(
            color: skin.text,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        Text(description, style: TextStyle(color: skin.mutedText, height: 1.5)),
      ],
    ),
  );
  Widget _field(
    TextEditingController ctrl,
    String label,
    int max, {
    String? hint,
    int min = 1,
    int lines = 1,
    Key? key,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      key: key,
      controller: ctrl,
      enabled: !working,
      maxLength: max,
      minLines: min,
      maxLines: lines,
      style: TextStyle(color: skin.text, fontSize: 15, height: 1.6),
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: true,
        filled: true,
        fillColor: skin.inputFill,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        counterStyle: TextStyle(color: skin.mutedText, fontSize: 11),
      ),
    ),
  );
  Widget _select(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> update,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      key: ValueKey('email-$label-$value'),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: skin.inputFill,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
      ),
      items: options
          .map(
            (x) => DropdownMenuItem(
              value: x,
              child: Text(x, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: working ? null : (x) => setState(() => update(x!)),
    ),
  );
  Widget _pair(Widget a, Widget b) => LayoutBuilder(
    builder: (_, box) => box.maxWidth < 420
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [a, const SizedBox(height: 10), b],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 14),
              Expanded(child: b),
            ],
          ),
  );
  Widget _hero() => LayoutBuilder(
    builder: (_, box) => Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(skin.panel, skin.secondary, skin.isLight ? .15 : .19)!,
            skin.panelDeep,
          ],
        ),
        border: Border.all(color: skin.secondary.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KORLIX  /  EMAIL STUDIO',
                  style: TextStyle(
                    color: skin.secondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your words.\nA stronger impression.',
                  style: TextStyle(
                    color: skin.text,
                    fontSize: box.maxWidth < 430 ? 26 : 36,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Make every email clearer, warmer and easier to act on.',
                  style: TextStyle(
                    color: skin.mutedText,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          if (box.maxWidth > 520) ...[
            const SizedBox(width: 16),
            const SizedBox(width: 150, height: 150, child: EmailArtwork()),
          ] else ...[
            const SizedBox(width: 6),
            const SizedBox(width: 65, height: 85, child: EmailArtwork()),
          ],
        ],
      ),
    ),
  );
  Widget _write() {
    final panels = <Widget>[
      _panel([
        _heading(
          '01  /  YOUR MESSAGE',
          'Start with your message',
          'Paste an email, write a few notes or dictate with Rici.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in emailModes)
              ChoiceChip(
                label: Text(m),
                selected: mode == m,
                onSelected: working ? null : (_) => setState(() => mode = m),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _field(
          source,
          mode == 'Reply'
              ? 'Incoming email'
              : mode == 'From notes'
              ? 'Your notes'
              : 'Original email',
          12000,
          hint: mode == 'Reply'
              ? 'Paste the message you received…'
              : mode == 'From notes'
              ? 'Who is it for? What should it say?'
              : 'Paste the email you want to improve…',
          min: 6,
          lines: 14,
          key: const Key('email-source'),
        ),
        if (mode == 'Reply')
          _field(
            contextNotes,
            'What should your reply say?',
            3000,
            hint:
                'Include the points you want to make and any questions to answer.',
            min: 3,
            lines: 6,
            key: const Key('email-reply-notes'),
          ),
        _pair(
          _button('Rici dictation', Icons.graphic_eq_rounded, _voice),
          _button('Import text', Icons.upload_file_rounded, _import),
        ),
        const SizedBox(height: 18),
        Text(
          'Need a starting point?',
          style: TextStyle(color: skin.mutedText, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: emailStarters.entries
              .map(
                (e) => ActionChip(
                  label: Text(e.key),
                  onPressed: working ? null : () => _new(e.value),
                ),
              )
              .toList(),
        ),
      ]),
      const SizedBox(height: 18),
      _panel([
        _heading(
          '02  /  MAKE IT YOURS',
          'Set the right impression',
          'Choose how it should sound and what it should achieve.',
        ),
        _pair(
          _select('Tone', tone, emailTones, (x) => tone = x),
          _select('Length', length, emailLengths, (x) => length = x),
        ),
        _select(
          'Output language',
          language,
          emailLanguages,
          (x) => language = x,
        ),
        _field(
          recipient,
          'Who is it for? (optional)',
          200,
          hint: 'e.g. Jordan, a new client',
        ),
        _field(
          goal,
          'What should happen next? (optional)',
          500,
          hint: 'e.g. Confirm a meeting or get a clear answer',
          min: 2,
          lines: 3,
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Signature & extra context'),
          subtitle: const Text('Add the details that make it yours'),
          children: [
            _field(
              signature,
              'Your signature (optional)',
              500,
              hint: 'Name, role and contact details',
              min: 2,
              lines: 4,
            ),
            if (mode != 'Reply')
              _field(
                contextNotes,
                'Extra context (optional)',
                3000,
                hint: 'Important background or details to retain',
                min: 3,
                lines: 6,
              ),
          ],
        ),
      ]),
    ];
    return LayoutBuilder(
      builder: (_, box) => box.maxWidth < 840
          ? Column(children: panels)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: panels[0]),
                const SizedBox(width: 20),
                Expanded(flex: 5, child: panels[2]),
              ],
            ),
    );
  }

  Widget _result() {
    final v = selected;
    if (v == null) {
      return _panel([
        const SizedBox(height: 10),
        const Center(
          child: SizedBox(width: 130, height: 130, child: EmailArtwork()),
        ),
        _heading(
          'READY WHEN YOU ARE',
          'A better email starts here',
          'Add your message, choose a tone and let Rici polish it.',
        ),
        _button('Write an email', Icons.edit_note_rounded, () => _go(0)),
      ]);
    }
    return Column(
      children: [
        _panel([
          _heading(
            '03  /  YOUR ENHANCED EMAIL',
            'Ready for your finishing touch',
            'Choose a subject line, then edit anything before you copy or export.',
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(v.brief.tone)),
              Chip(label: Text('${emailWordCount(body.text)} words')),
              Chip(
                label: Text(
                  '~${(emailWordCount(body.text) / 200 * 60).ceil()} sec read',
                ),
              ),
            ],
          ),
          if (versions.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: DropdownButtonFormField<int>(
                initialValue: versions.indexOf(v),
                key: ValueKey(
                  'email-versions-${versions.length}-${versions.indexOf(v)}',
                ),
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Recent versions (this session)',
                ),
                items: [
                  for (var i = 0; i < versions.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        'Version ${versions.length - i} · ${versions[i].brief.tone}',
                      ),
                    ),
                ],
                onChanged: working ? null : (i) => _chooseVersion(versions[i!]),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'SUBJECT IDEAS',
            style: TextStyle(
              color: skin.secondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < v.result.subjects.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: subject.text == v.result.subjects[i]
                    ? skin.secondary.withValues(alpha: .12)
                    : skin.inputFill,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  key: Key('email-subject-$i'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: working
                      ? null
                      : () =>
                            setState(() => subject.text = v.result.subjects[i]),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          subject.text == v.result.subjects[i]
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked,
                          size: 20,
                          color: skin.secondary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            v.result.subjects[i],
                            style: TextStyle(color: skin.text, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          _field(
            subject,
            'Edit subject',
            180,
            key: const Key('email-subject-edit'),
          ),
          _field(
            body,
            'Edit email',
            18000,
            min: 10,
            lines: 30,
            key: const Key('email-body'),
          ),
          _pair(
            _button(
              'Copy email',
              Icons.copy_all_rounded,
              () => _output('email'),
              key: const Key('email-copy'),
            ),
            _button(
              'Copy body',
              Icons.content_copy_rounded,
              () => _output('body'),
            ),
          ),
          const SizedBox(height: 12),
          _pair(
            _button(
              'Export .txt',
              Icons.download_rounded,
              () => _output('txt'),
            ),
            _button(
              'Export .eml',
              Icons.mark_email_read_outlined,
              () => _output('eml'),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Open .eml in a compatible email app as a draft. Add the recipient and review before sending.',
            style: TextStyle(color: skin.mutedText, fontSize: 12, height: 1.5),
          ),
        ], glow: true),
        const SizedBox(height: 18),
        _panel([
          _heading(
            'REVIEW & COMPARE',
            'See what changed',
            'Your source text stays available while you review.',
          ),
          for (final change in v.result.changes)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    color: skin.secondary,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      change,
                      style: TextStyle(color: skin.text, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          if (v.result.checks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'BEFORE YOU SEND',
              style: TextStyle(
                color: skin.premium,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            for (final check in v.result.checks)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '• $check',
                  style: TextStyle(color: skin.text, height: 1.5),
                ),
              ),
          ],
          const SizedBox(height: 8),
          _button(
            showOriginal ? 'Hide original' : 'Compare with original',
            Icons.compare_arrows_rounded,
            () => setState(() => showOriginal = !showOriginal),
            key: const Key('email-compare'),
            active: showOriginal,
          ),
          if (showOriginal) ...[
            const SizedBox(height: 16),
            _pair(
              _comparison('ORIGINAL', v.brief.source),
              _comparison('ENHANCED', body.text),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Check names, dates, amounts and any [placeholders]. Edit notes refer to the generated version.',
            style: TextStyle(color: skin.mutedText, fontSize: 12, height: 1.5),
          ),
        ]),
        const SizedBox(height: 18),
        _button('Refine tone or length', Icons.tune_rounded, () => _go(0)),
      ],
    );
  }

  Widget _comparison(String title, String value) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: skin.inputFill,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: skin.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: skin.secondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        SelectableText(
          value,
          style: TextStyle(color: skin.text, fontSize: 14, height: 1.6),
        ),
      ],
    ),
  );
  Widget _drafts() {
    final found = c.drafts
        .where(
          (d) => '${d.title} ${d.brief.source} ${d.body}'
              .toLowerCase()
              .contains(search.text.toLowerCase()),
        )
        .toList();
    return _panel([
      _heading(
        'YOUR DRAFT LIBRARY',
        'Pick up where you left off',
        'Up to 20 saved drafts for this account on this device. Use Export to keep a backup.',
      ),
      _field(
        search,
        'Search saved drafts',
        100,
        key: const Key('email-draft-search'),
      ),
      if (loading)
        const LinearProgressIndicator()
      else if (!c.loaded) ...[
        const Text('Saved drafts are unavailable.'),
        _button(
          'Try loading again',
          Icons.refresh_rounded,
          () => unawaited(_load()),
        ),
      ] else if (found.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 25),
          child: Text(
            search.text.isEmpty
                ? 'Your saved emails will appear here. Choose Save draft while writing or reviewing an email.'
                : 'No drafts match your search.',
            style: TextStyle(color: skin.mutedText, height: 1.5),
          ),
        )
      else
        for (final d in found)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: skin.inputFill,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: skin.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: skin.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${d.brief.mode} · ${d.brief.tone} · ${DateTime.tryParse(d.savedAt)?.toLocal().toString().split(' ').first ?? ''}',
                    style: TextStyle(color: skin.mutedText, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      _button(
                        'Open draft',
                        Icons.arrow_forward_rounded,
                        () => _openDraft(d),
                      ),
                      TextButton.icon(
                        onPressed: working ? null : () => _delete(d),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    ]);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: popping || !c.available || (!dirty && !working),
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      if (working) {
        _say('Wait for the current action to finish before leaving.');
        return;
      }
      if (await _discard() && mounted) {
        setState(() => popping = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    },
    child: Scaffold(
      backgroundColor: skin.backgroundBottom,
      appBar: AppBar(
        title: const Text('Email Enhancer'),
        backgroundColor: skin.backgroundBottom,
        actions: [
          IconButton(
            tooltip: 'New email',
            onPressed: working ? null : () => _new(),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: !c.available
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Your session changed. Sign in and reopen Email Enhancer.',
                  style: TextStyle(color: skin.text),
                ),
              ),
            )
          : SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
                    children: [
                      if (tab == 0) ...[_hero(), const SizedBox(height: 20)],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final entry in [
                            (0, 'Write', Icons.edit_note_rounded),
                            (1, 'Enhanced', Icons.auto_awesome_rounded),
                            (2, 'Drafts', Icons.folder_open_rounded),
                          ])
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: entry.$1 == 2 ? 0 : 8,
                                ),
                                child: Semantics(
                                  selected: tab == entry.$1,
                                  child: OutlinedButton(
                                    key: Key('email-tab-${entry.$1}'),
                                    onPressed: working
                                        ? null
                                        : () => _go(entry.$1),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 13,
                                        horizontal: 3,
                                      ),
                                      backgroundColor: tab == entry.$1
                                          ? skin.secondary.withValues(
                                              alpha: .14,
                                            )
                                          : skin.panel,
                                      side: BorderSide(
                                        color: tab == entry.$1
                                            ? skin.secondary
                                            : skin.border,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          entry.$3,
                                          color: tab == entry.$1
                                              ? skin.secondary
                                              : skin.mutedText,
                                          size: 20,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          entry.$2,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: skin.text,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
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
                      const SizedBox(height: 20),
                      if (error != null || notice != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: Semantics(
                            liveRegion: true,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color:
                                    (error != null ? skin.danger : skin.success)
                                        .withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color:
                                      (error != null
                                              ? skin.danger
                                              : skin.success)
                                          .withValues(alpha: .35),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    error != null
                                        ? Icons.info_outline_rounded
                                        : Icons.check_circle_outline_rounded,
                                    size: 20,
                                    color: error != null
                                        ? skin.danger
                                        : skin.success,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      error ?? notice!,
                                      style: TextStyle(
                                        color: skin.text,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Dismiss',
                                    onPressed: () => setState(() {
                                      error = notice = null;
                                    }),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (tab == 0)
                        _write()
                      else if (tab == 1)
                        _result()
                      else
                        _drafts(),
                    ],
                  ),
                ),
              ),
            ),
      bottomNavigationBar: !c.available || tab == 2
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                decoration: BoxDecoration(
                  color: skin.panelDeep,
                  border: Border(top: BorderSide(color: skin.border)),
                ),
                child: Align(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1044),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (working) ...[
                          const LinearProgressIndicator(minHeight: 2),
                          const SizedBox(height: 10),
                        ],
                        LayoutBuilder(
                          builder: (_, box) {
                            final primary = KorlixActionButton(
                              key: const Key('email-enhance'),
                              label: working
                                  ? 'Working…'
                                  : tab == 0
                                  ? 'Enhance my email'
                                  : 'Save draft',
                              icon: tab == 0
                                  ? Icons.auto_awesome_rounded
                                  : Icons.bookmark_add_outlined,
                              onPressed: working
                                  ? null
                                  : tab == 0
                                  ? _enhance
                                  : _save,
                              expand: true,
                              accent: skin.secondary,
                            );
                            final secondary = TextButton.icon(
                              key: const Key('email-save'),
                              onPressed: working || loading
                                  ? null
                                  : tab == 0
                                  ? _save
                                  : () => _go(0),
                              icon: Icon(
                                tab == 0
                                    ? Icons.bookmark_add_outlined
                                    : Icons.tune_rounded,
                              ),
                              label: Text(tab == 0 ? 'Save draft' : 'Refine'),
                            );
                            return box.maxWidth < 360 ||
                                    MediaQuery.textScalerOf(context).scale(1) >
                                        1.4
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [primary, secondary],
                                  )
                                : Row(
                                    children: [
                                      Expanded(child: primary),
                                      const SizedBox(width: 10),
                                      secondary,
                                    ],
                                  );
                          },
                        ),
                        const SizedBox(height: 7),
                        Text(
                          tab == 0
                              ? '1 credit per enhancement · Review before sending'
                              : 'Your edits stay yours · Export or save to keep them',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: skin.mutedText, fontSize: 11),
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
