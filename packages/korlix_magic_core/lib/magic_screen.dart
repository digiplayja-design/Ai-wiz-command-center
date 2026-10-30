import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'magic_client.dart';
import 'magic_capture.dart';
import 'magic_result.dart';
import 'magic_theme.dart';

class MagicScreen extends StatefulWidget {
  const MagicScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    this.onAccount,
    this.onUpgrade,
    this.standalone = false,
  });
  final MagicClient client;
  final Future<bool> Function() ensureConsent;
  final VoidCallback? onAccount;
  final FutureOr<void> Function()? onUpgrade;
  final bool standalone;
  @override
  State<MagicScreen> createState() => _MagicScreenState();
}

class _MagicScreenState extends State<MagicScreen> with WidgetsBindingObserver {
  final _prompt = TextEditingController(), _speech = SpeechToText();
  List<Map<String, dynamic>> _presets = [], _jobs = [], _saved = [];
  Map<String, dynamic> _plan = {};
  String _preset = 'executive',
      _style = 'all',
      _intensity = 'natural',
      _accent = 'orange and electric blue',
      _category = 'Business',
      _motion = 'Cosmic orbits';
  String? _error;
  bool _loading = true,
      _available = false,
      _preserve = true,
      _listening = false,
      _starting = false,
      _haptics = true;
  int _tab = 0, _timer = 0, _galleryVersion = 0;
  int? _nextOffset;
  bool _loadingMore = false;
  String get _prefsKey => 'magic_camera_${widget.client.accountScope}';
  Map<String, dynamic> get _options => {
    'preset': _preset,
    'prompt': _prompt.text.trim(),
    'style': _style,
    'intensity': _intensity,
    'accent': _accent,
    'preserveFace': _preserve,
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.addListener(_account);
    unawaited(_initialize());
  }

  void _account() {
    if (!widget.client.valid && mounted) {
      _speech.stop();
      setState(() {
        _jobs = [];
        _saved = [];
        _prompt.clear();
      });
    }
  }

  Future<void> _initialize() async {
    final json = await rootBundle.loadString(
      'packages/korlix_magic_core/assets/presets.json',
    );
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _presets = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
      _style = prefs.getString('${_prefsKey}_style') ?? 'all';
      try {
        _saved = (jsonDecode(
          prefs.getString('${_prefsKey}_looks') ?? '[]',
        ) as List).cast<Map<String, dynamic>>();
      } catch (_) {
        _saved = [];
      }
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final version = ++_galleryVersion;
    try {
      final data = await widget.client.snapshot();
      if (mounted && widget.client.valid && version == _galleryVersion) {
        setState(() {
          _plan = Map<String, dynamic>.from(data['plan'] as Map);
          _jobs = (data['jobs'] as List).cast<Map<String, dynamic>>();
          _nextOffset = data['next_offset'] as int?;
          _available = data['available'] == true;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load your allowance and gallery. Check your connection and refresh.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final offset = _nextOffset, version = _galleryVersion;
    if (offset == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final data = await widget.client.snapshot(offset: offset);
      if (!mounted || !widget.client.valid || version != _galleryVersion) {
        return;
      }
      setState(() {
        final known = _jobs.map((j) => j['id']).toSet();
        _jobs = [
          ..._jobs,
          ...(data['jobs'] as List).cast<Map<String, dynamic>>().where(
            (j) => known.add(j['id']),
          ),
        ];
        _nextOffset = data['next_offset'] as int?;
      });
    } catch (_) {
      _notice('Older photos could not be loaded. Please try again.');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _dictate() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final ready = await _speech.initialize(
      onStatus: (s) {
        if (mounted && s != 'listening') setState(() => _listening = false);
      },
    );
    if (!ready) {
      _notice(
        'Enable microphone and speech recognition in device settings to dictate your idea.',
      );
      return;
    }
    if (!mounted) return;
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        if (mounted) _prompt.text = r.recognizedWords;
      },
    );
  }

  void _notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _saveLook() async {
    if (_preset == 'custom' && _prompt.text.trim().isEmpty) {
      _notice('Describe your custom look first.');
      return;
    }
    String lookName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save your signature look'),
        content: TextFormField(
          onChanged: (value) => lookName = value,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Look name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, lookName.trim()),
            child: const Text('Save look'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted || !widget.client.valid) {
      return;
    }
    final next = [
      {'name': name, ..._options},
      ..._saved,
    ].take(30).toList();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString('${_prefsKey}_looks', jsonEncode(next))) {
        throw StateError('save');
      }
      if (mounted) setState(() => _saved = next);
      _notice('Saved to My looks on this device.');
    } catch (_) {
      _notice('Your look could not be saved. Please try again.');
    }
  }

  Future<void> _rememberStyle() async {
    final prefs = await SharedPreferences.getInstance();
    _notice(
      await prefs.setString('${_prefsKey}_style', _style)
          ? 'Clothing preference saved. You can change it for any photo.'
          : 'Preference could not be saved.',
    );
  }

  Future<void> _start() async {
    if (_starting) return;
    if (_preset == 'custom' && _prompt.text.trim().isEmpty) {
      _notice('Tell us your idea before opening the camera.');
      return;
    }
    setState(() => _starting = true);
    try {
      await _speech.stop();
      if (!mounted || !widget.client.valid) return;
      if (!await widget.ensureConsent() || !mounted || !widget.client.valid) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MagicCapture(
            client: widget.client,
            options: Map.of(_options),
            motion: _motion,
            timer: _timer,
            haptics: _haptics,
          ),
        ),
      );
      await _refresh();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _choose(Map<String, dynamic> p) {
    setState(() {
      _preset = p['preset']?.toString() ?? p['id'].toString();
      if (p.containsKey('style')) {
        _prompt.text = p['prompt'] as String;
        _style = p['style'] as String;
        _intensity = p['intensity'] as String;
        _accent = p['accent'] as String;
        _preserve = p['preserveFace'] as bool;
      }
      _tab = 0;
    });
  }

  IconData _icon(String c) => switch (c) {
    'Business' => Icons.business_center_outlined,
    'Party' => Icons.celebration_outlined,
    'Fashion' => Icons.diamond_outlined,
    'Travel' => Icons.public,
    'Fantasy' => Icons.auto_awesome_outlined,
    _ => Icons.wb_sunny_outlined,
  };
  Widget _section(String eyebrow, String title) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: magicBlue,
            fontWeight: FontWeight.w700,
            fontSize: 11,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          title,
          style: const TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            letterSpacing: -.4,
          ),
        ),
      ],
    ),
  );
  Widget _select(
    String label,
    String value,
    Map<String, String> items,
    ValueChanged<String> change,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: items.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: (v) => setState(() => change(v!)),
    ),
  );
  Widget _looks() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _section('01 / DREAM IT', 'Pick your kind of magic'),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children:
              [
                    'All',
                    'Business',
                    'Party',
                    'Fashion',
                    'Travel',
                    'Fantasy',
                    'Light & color',
                  ]
                  .map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(c),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                    ),
                  )
                  .toList(),
        ),
      ),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, c) {
          final count = c.maxWidth > 800
              ? 5
              : c.maxWidth > 500
              ? 3
              : 2;
          final filtered = _presets
              .where((p) => _category == 'All' || p['category'] == _category)
              .toList();
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: count,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 132,
            ),
            itemBuilder: (context, i) {
              final p = filtered[i], selected = p['id'] == _preset;
              return Semantics(
                selected: selected,
                button: true,
                child: InkWell(
                  onTap: () => _choose(p),
                  borderRadius: BorderRadius.circular(22),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: selected
                            ? [const Color(0xFF57351F), const Color(0xFF162D4A)]
                            : [magicPanel, const Color(0xFF111B2C)],
                      ),
                      border: Border.all(
                        color: selected ? magicOrange : const Color(0xFF26344B),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _icon(p['category'] as String),
                              color: i.isEven ? magicOrange : magicBlue,
                              size: 27,
                            ),
                            const Spacer(),
                            if (selected)
                              const Icon(
                                Icons.check_circle,
                                color: magicOrange,
                                size: 19,
                              ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          p['name'] as String,
                          maxLines: 2,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          p['category'] as String,
                          style: const TextStyle(
                            color: magicMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          OutlinedButton.icon(
            onPressed: () => setState(() => _preset = 'custom'),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Create my own'),
          ),
          OutlinedButton.icon(
            onPressed: _presets.isEmpty
                ? null
                : () {
                    _choose(_presets[Random().nextInt(_presets.length)]);
                    _notice(
                      'A surprise look is selected. Take one photo when you’re ready.',
                    );
                  },
            icon: const Icon(Icons.casino_outlined),
            label: const Text('Surprise me'),
          ),
        ],
      ),
    ],
  );
  Widget _compose() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [Color(0xFF142D4F), Color(0xFF152039), Color(0xFF31241E)],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'KORLIX MAGIC CAMERA',
                    style: TextStyle(
                      color: magicOrange,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Imagine it.\nBecome the moment.',
                    style: TextStyle(
                      fontSize: 31,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 13),
                  Text(
                    widget.standalone &&
                            _plan['name'] == 'free' &&
                            (_plan['remaining'] as num? ?? 0) > 0
                        ? 'Your first 2 magic photos are on us.'
                        : 'A new look. The same unmistakable you.',
                    style: const TextStyle(color: magicMuted, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const MagicMark(size: 76),
          ],
        ),
      ),
      _looks(),
      _section(
        '02 / MAKE IT YOURS',
        _preset == 'custom'
            ? 'What are you imagining?'
            : 'Add your own little twist',
      ),
      TextField(
        controller: _prompt,
        maxLength: 3000,
        minLines: 3,
        maxLines: 6,
        decoration: InputDecoration(
          hintText: _preset == 'custom'
              ? 'A velvet suit, a rooftop in Paris, soft sunset light…'
              : 'Optional: “Make the background blue and keep my glasses.”',
          suffixIcon: IconButton(
            tooltip: _listening ? 'Stop dictation' : 'Dictate your idea',
            onPressed: _dictate,
            icon: Icon(
              _listening ? Icons.stop_circle_outlined : Icons.mic_none,
            ),
          ),
        ),
      ),
      const Text(
        'Each preset already includes detailed lighting, outfit and identity instructions.',
        style: TextStyle(color: magicMuted, height: 1.5),
      ),
      const SizedBox(height: 20),
      _select('Clothing collection (optional)', _style, {
        'all': 'Show everything',
        'mens': "Men’s styles",
        'womens': "Women’s styles",
        'unisex': 'Unisex styles',
      }, (v) => _style = v),
      const Text(
        'Choose a look for anyone in the photo. We do not guess or collect your gender.',
        style: TextStyle(color: magicMuted, fontSize: 12),
      ),
      TextButton(
        onPressed: _rememberStyle,
        child: const Text('Remember this clothing preference'),
      ),
      _select('Magic intensity', _intensity, {
        'natural': 'Natural · a believable new look',
        'cinematic': 'Cinematic · a little movie magic',
        'fantasy': 'Fantasy · let imagination lead',
      }, (v) => _intensity = v),
      _select('Accent color', _accent, {
        'orange and electric blue': 'Korlix orange + electric blue',
        'orange': 'Orange',
        'electric blue': 'Electric blue',
        'lavender': 'Lavender',
        'emerald': 'Emerald',
        'rose': 'Rose',
        'neutral': 'Neutral',
      }, (v) => _accent = v),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Preserve my face'),
        subtitle: const Text(
          'Prioritizes your features. AI edits can still change details; review your result.',
        ),
        value: _preserve,
        onChanged: (v) => setState(() => _preserve = v),
      ),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Set the magic mood'),
        children: [
          _select('Animation', _motion, {
            'Cosmic orbits': 'Cosmic orbits',
            'Stardust': 'Stardust',
            'Portal': 'Portal',
          }, (v) => _motion = v),
          _select('Party booth timer', '$_timer', {
            '0': 'No countdown',
            '3': '3 seconds',
            '10': '10 seconds · gather the crew',
          }, (v) => _timer = int.parse(v)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Countdown haptics'),
            value: _haptics,
            onChanged: (v) => setState(() => _haptics = v),
          ),
        ],
      ),
      TextButton.icon(
        onPressed: _saveLook,
        icon: const Icon(Icons.bookmark_add_outlined),
        label: const Text('Save as my signature look'),
      ),
      const SizedBox(height: 18),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const Key('open-magic-camera'),
          onPressed: _plan['can_generate'] == true && _available && !_starting
              ? _start
              : null,
          icon: const Icon(Icons.camera_alt_outlined),
          label: Text(_starting ? 'Opening…' : 'Open magic camera'),
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        'Choose your look first. Aim with the live viewfinder. After the shutter, only your magic photo appears.',
        textAlign: TextAlign.center,
        style: TextStyle(color: magicMuted, height: 1.5, fontSize: 12),
      ),
    ],
  );
  Widget _savedLooks() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _section('YOUR SIGNATURE', 'My looks'),
      if (_saved.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Text(
            'Found a look you love? Save it from the camera tab and use it again.',
          ),
        ),
      for (final p in _saved)
        Card(
          color: magicPanel,
          child: ListTile(
            leading: const Icon(Icons.bookmark, color: magicOrange),
            title: Text(p['name'] as String),
            subtitle: Text(
              p['prompt'] as String,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.arrow_forward_rounded),
            onTap: () => _choose(p),
          ),
        ),
    ],
  );
  List<Widget> _gallery() => [
    _section('ONLY THE MAGIC', 'Your private gallery'),
    const Text(
      'Your completed photos stay here even when your allowance is used.',
      style: TextStyle(color: magicMuted),
    ),
    const SizedBox(height: 20),
    if (_jobs.isEmpty)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 45),
        child: Text('Your first magic moment is waiting to happen.'),
      ),
    for (final job in _jobs)
      Padding(
        key: ValueKey<String>(job['id'] as String),
        padding: const EdgeInsets.only(bottom: 15),
        child: Card(
          color: magicPanel,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              if (job['state'] == 'ready')
                _GalleryImage(
                  client: widget.client,
                  id: job['id'] as String,
                  onTap: () => _openResult(job),
                ),
              ListTile(
                leading: Icon(
                  job['state'] == 'ready'
                      ? Icons.auto_awesome
                      : job['state'] == 'failed'
                      ? Icons.info_outline
                      : Icons.blur_circular,
                  color: magicOrange,
                ),
                title: Text(_name(job)),
                subtitle: Text(
                  job['state'] == 'ready'
                      ? 'Saved privately'
                      : job['state'] == 'failed'
                      ? 'Could not complete · no credit used'
                      : 'Magic in progress · tap to check',
                ),
                onTap: () => _openResult(job),
                trailing: job['state'] == 'ready'
                    ? TextButton.icon(
                        onPressed: () => _openResult(job, report: true),
                        icon: const Icon(Icons.flag_outlined, size: 18),
                        label: const Text('Report'),
                      )
                    : const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    if (_nextOffset != null)
      OutlinedButton.icon(
        onPressed: _loadingMore ? null : _loadMore,
        icon: const Icon(Icons.expand_more),
        label: Text(
          _loadingMore ? 'Loading older photos…' : 'Load older photos',
        ),
      ),
  ];
  String _name(Map<String, dynamic> job) {
    final id = (job['options'] as Map?)?['preset'];
    for (final p in _presets) {
      if (p['id'] == id) return p['name'] as String;
    }
    return 'Your custom magic';
  }

  Future<void> _openResult(
    Map<String, dynamic> job, {
    bool report = false,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MagicResult(
          client: widget.client,
          initialJob: job,
          motion: _motion,
          autoReport: report,
        ),
      ),
    );
    await _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.client.removeListener(_account);
    _prompt.dispose();
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.client.valid) {
      return const Scaffold(
        body: Center(
          child: Text('Sign in to your Korlix account to use Magic Camera.'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MagicMark(size: 36),
            SizedBox(width: 10),
            Text(
              'Magic Camera',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh account and gallery',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          if (widget.onAccount != null)
            IconButton(
              tooltip: 'Your account',
              onPressed: widget.onAccount,
              icon: const Icon(Icons.person_outline),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 32),
              children: [
                if (_loading) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: magicOrange),
                    ),
                  ),
                if (!_loading && _error == null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 18),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: magicPanel,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome,
                          size: 18,
                          color: magicOrange,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _plan['name'] == 'free'
                                ? '${_plan['remaining']} of 2 free magic photos left'
                                : _plan['name'] == 'locked'
                                ? 'Magic Camera is included with Pro and Ultra'
                                : '${_plan['name'].toString().toUpperCase()} · ${_plan['remaining']} photos left this month${_plan['daily_remaining'] != null ? ' · ${_plan['daily_remaining']} today' : ''}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (widget.onUpgrade != null)
                          TextButton(
                            onPressed: () async {
                              await widget.onUpgrade?.call();
                              await _refresh();
                            },
                            child: Text(
                              _plan['included'] == true ? 'Plan' : 'Upgrade',
                            ),
                          ),
                      ],
                    ),
                  ),
                if (!_available && !_loading && _error == null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Magic rendering is being connected. You can explore looks while it is getting ready.',
                      style: TextStyle(color: magicMuted),
                    ),
                  ),
                if (_tab == 0)
                  _compose()
                else if (_tab == 1)
                  _savedLooks()
                else
                  ..._gallery(),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (v) {
          setState(() => _tab = v);
          if (v == 2) unawaited(_refresh());
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Make magic',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline),
            label: 'My looks',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            label: 'Gallery',
          ),
        ],
      ),
    );
  }
}

class _GalleryImage extends StatefulWidget {
  const _GalleryImage({
    required this.client,
    required this.id,
    required this.onTap,
  });
  final MagicClient client;
  final String id;
  final VoidCallback onTap;
  @override
  State<_GalleryImage> createState() => _GalleryImageState();
}

class _GalleryImageState extends State<_GalleryImage> {
  late final Future<Uint8List> _bytes = widget.client.image(
    widget.id,
    preview: true,
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, s) => s.hasData
        ? InkWell(
            onTap: widget.onTap,
            child: Image.memory(
              s.data!,
              height: 260,
              width: double.infinity,
              fit: BoxFit.cover,
              semanticLabel: 'Saved magic photo',
              cacheWidth: 640,
            ),
          )
        : SizedBox(
            height: 120,
            child: Center(
              child: Text(
                s.hasError
                    ? 'Tap below to load this photo'
                    : 'Loading magic photo…',
                style: const TextStyle(color: magicMuted),
              ),
            ),
          ),
  );
}
