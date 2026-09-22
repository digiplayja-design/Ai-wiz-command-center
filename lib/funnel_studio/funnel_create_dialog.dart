import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';
import 'funnel_library.dart';

class FunnelCreateDialog extends StatefulWidget {
  const FunnelCreateDialog({super.key, required this.create, this.source});
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) create;
  final Map<String, dynamic>? source;

  @override
  State<FunnelCreateDialog> createState() => _FunnelCreateDialogState();
}

class _FunnelCreateDialogState extends State<FunnelCreateDialog> {
  final _name = TextEditingController(), _slug = TextEditingController();
  final _form = GlobalKey<FormState>();
  FunnelPreset _preset = funnelPresets.first;
  String _category = 'All', _search = '';
  String? _error;
  bool _details = false, _busy = false, _manualSlug = false;

  bool get _duplicate => widget.source != null;
  Map<String, dynamic> get _document => _duplicate
      ? Map<String, dynamic>.from(widget.source!['draft'] as Map)
      : _preset.document();

  @override
  void initState() {
    super.initState();
    if (_duplicate) {
      _details = true;
      final name = '${widget.source!['name']}';
      _name.text = '${name.substring(0, math.min(95, name.length))} copy';
      final slug = '${widget.source!['slug']}';
      _slug.text = '${slug.substring(0, math.min(55, slug.length))}-copy';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    super.dispose();
  }

  Color _accent(String value) => switch (value) {
    'violet' => WfStyle.violet,
    'gold' => WfStyle.gold,
    _ => WfStyle.cyan,
  };

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.create(
        funnelCreatePayload(_name.text, _slug.text, _document),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
      if (e is FunnelException && (e.status == 401 || e.status == 403)) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final mobile = size.width < 600;
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        insetPadding: EdgeInsets.all(mobile ? 10 : 28),
        child: SizedBox(
          width: 1120,
          height: math.min(880, size.height - (mobile ? 28 : 72)),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.all(mobile ? 18 : 26),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/meeting_copilot/korlix_logo.jpeg',
                        width: 42,
                        height: 42,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _duplicate
                                ? 'Duplicate your draft'
                                : 'Find your starting point',
                            style: TextStyle(
                              fontSize: mobile ? 20 : 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _duplicate
                                ? 'A fresh page. Your original stays as it is.'
                                : _details
                                ? '02 / PERSONALIZE YOUR DRAFT'
                                : '01 / EXPLORE THE TEMPLATE LIBRARY',
                            style: const TextStyle(
                              color: WfStyle.muted,
                              fontSize: 11,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: AbsorbPointer(
                  absorbing: _busy,
                  child: _details ? _setup() : _gallery(),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      key: const ValueKey('create-error'),
                      style: const TextStyle(
                        color: WfStyle.danger,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              const Divider(height: 1),
              Padding(
                padding: EdgeInsets.all(mobile ? 16 : 22),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 12,
                  overflowSpacing: 8,
                  children: [
                    if (_details && !_duplicate)
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _details = false),
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: const Text('Templates'),
                      )
                    else
                      TextButton(
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : _details
                          ? _submit
                          : () => setState(() {
                              if (_name.text.isEmpty) {
                                _name.text = _preset.name;
                                _slug.text = funnelSlugSuggestion(_name.text);
                              }
                              _details = true;
                            }),
                      icon: Icon(
                        _details ? Icons.add : Icons.arrow_forward,
                        size: 18,
                      ),
                      label: Text(
                        _busy
                            ? 'Creating…'
                            : _details
                            ? 'Create draft'
                            : 'Use template',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gallery() {
    final matches = funnelPresets
        .where(
          (p) =>
              (_category == 'All' || p.category == _category) &&
              '${p.name} ${p.category} ${p.description}'.toLowerCase().contains(
                _search.toLowerCase().trim(),
              ),
        )
        .toList();
    return SingleChildScrollView(
      key: const ValueKey('template-gallery'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Thoughtful starting points for your next opportunity.',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose a style, make the copy yours, then review before publishing.',
            style: TextStyle(color: WfStyle.muted, height: 1.5),
          ),
          const SizedBox(height: 20),
          TextField(
            key: const ValueKey('template-search'),
            decoration: const InputDecoration(
              hintText: 'Search templates',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in [
                'All',
                'Services',
                'Products',
                'Events',
                'Learning',
              ])
                ChoiceChip(
                  label: Text(c),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${matches.length} templates · Selected: ${_preset.name}',
            style: const TextStyle(color: WfStyle.muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (matches.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'No matching templates. Try another search or category.',
              ),
            ),
          LayoutBuilder(
            builder: (context, box) {
              final cols = box.maxWidth >= 950
                  ? 3
                  : box.maxWidth >= 600
                  ? 2
                  : 1;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final p in matches)
                    SizedBox(
                      width: (box.maxWidth - 16 * (cols - 1)) / cols,
                      child: _presetCard(p),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _presetCard(FunnelPreset p) {
    final selected = p.id == _preset.id, accent = _accent(p.accent);
    return Semantics(
      selected: selected,
      button: true,
      label: 'Select ${p.name}',
      child: Material(
        color: selected
            ? accent.withValues(alpha: .09)
            : const Color(0xFF0A2031),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? accent : WfStyle.line,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('preset-${p.id}'),
          onTap: () => setState(() => _preset = p),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 142,
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF102E3D),
                        accent.withValues(alpha: .2),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: p.layout == 'consultation'
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      Text(
                        p.category.toUpperCase(),
                        style: TextStyle(
                          color: accent,
                          fontSize: 9,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Text(
                          p.headline,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: p.layout == 'consultation'
                              ? TextAlign.start
                              : TextAlign.center,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          p.cta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF081926),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: selected ? accent : WfStyle.muted,
                      size: 21,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  p.description,
                  style: const TextStyle(
                    color: WfStyle.muted,
                    height: 1.5,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _setup() => SingleChildScrollView(
    key: const ValueKey('template-details'),
    padding: const EdgeInsets.all(24),
    child: LayoutBuilder(
      builder: (context, box) {
        final fields = Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _duplicate
                    ? 'Give this version its own identity.'
                    : 'Make it yours.',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _duplicate
                    ? 'Copies the saved page content only. Leads, campaigns, follow-ups, and publishing status stay with the original.'
                    : '${_preset.name} · All text and colors can be edited in the studio.',
                style: const TextStyle(color: WfStyle.muted, height: 1.5),
              ),
              const SizedBox(height: 24),
              TextFormField(
                key: const ValueKey('create-name'),
                controller: _name,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Funnel name'),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? 'Add a name for this funnel.'
                    : null,
                onChanged: (v) {
                  if (!_manualSlug) _slug.text = funnelSlugSuggestion(v);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('create-slug'),
                controller: _slug,
                maxLength: 60,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Public address',
                  prefixText: '/f/',
                  helperText:
                      '3–60 lowercase letters, numbers, or hyphens. This address cannot be changed later.',
                  helperMaxLines: 3,
                ),
                onChanged: (_) => _manualSlug = true,
                validator: (v) =>
                    !RegExp(
                      r'^[a-z0-9][a-z0-9-]{2,59}$',
                    ).hasMatch((v ?? '').trim())
                    ? 'Use 3–60 lowercase letters, numbers, or hyphens.'
                    : null,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: WfStyle.cyan.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Your new page starts as a private draft. Add your business details and privacy policy before publishing.',
                  style: TextStyle(color: WfStyle.cyan, height: 1.5),
                ),
              ),
            ],
          ),
        );
        final preview = Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF12313E),
                _accent('${_document['accent']}').withValues(alpha: .12),
              ],
            ),
            border: Border.all(color: WfStyle.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _duplicate ? 'SAVED CONTENT' : 'YOUR STARTING COPY',
                style: TextStyle(
                  color: _accent('${_document['accent']}'),
                  fontSize: 11,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                '${_document['headline']}',
                style: const TextStyle(
                  fontSize: 28,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '${_document['subheadline']}',
                style: const TextStyle(color: WfStyle.muted, height: 1.6),
              ),
              const SizedBox(height: 24),
              for (final benefit in (_document['benefits'] as List))
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: _accent('${_document['accent']}'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$benefit',
                          style: const TextStyle(height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                '${_document['cta']}',
                style: TextStyle(
                  color: _accent('${_document['accent']}'),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
        if (box.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [fields, const SizedBox(height: 24), preview],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: fields),
            const SizedBox(width: 32),
            Expanded(child: preview),
          ],
        );
      },
    ),
  );
}
