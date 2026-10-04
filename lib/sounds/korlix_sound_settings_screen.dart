import 'dart:async';

import 'package:flutter/material.dart';

import 'korlix_sound_service.dart';

/// Device-local controls for the shared foreground sound system.
class KorlixSoundSettingsScreen extends StatefulWidget {
  const KorlixSoundSettingsScreen({super.key, this.service});

  final KorlixSoundService? service;

  @override
  State<KorlixSoundSettingsScreen> createState() =>
      _KorlixSoundSettingsScreenState();
}

class _KorlixSoundSettingsScreenState extends State<KorlixSoundSettingsScreen> {
  late KorlixSoundService _service;
  final _scroll = ScrollController();
  double? _volumeDraft;
  bool _previewing = false;

  static const _cyan = Color(0xff008eab);
  static const _violet = Color(0xff8056d9);
  static const _green = Color(0xff168565);
  static const _amber = Color(0xffb77305);

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? kKorlixSounds;
    _service.addListener(_changed);
    unawaited(_service.restore());
  }

  @override
  void didUpdateWidget(covariant KorlixSoundSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service == widget.service) return;
    _service.removeListener(_changed);
    _service = widget.service ?? kKorlixSounds;
    _service.addListener(_changed);
    _volumeDraft = null;
    unawaited(_service.restore());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _save(KorlixSoundSettings settings) async {
    final saved = await _service.update(settings);
    if (!mounted || saved) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _service.storageError ??
                'Sound changes could not be saved on this device.',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
  }

  Future<void> _preview(KorlixSound sound) async {
    if (_previewing) return;
    // Keep activation directly on the tap stack for browsers such as Safari.
    final service = _service;
    final activation = service.activate();
    setState(() => _previewing = true);
    try {
      final activated = await activation;
      if (!mounted || !identical(service, _service)) return;
      if (activated) await service.preview(sound);
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  String _time(int minute) =>
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);

  Future<void> _pickTime({required bool start}) async {
    final value = start
        ? _service.settings.quietStartMinute
        : _service.settings.quietEndMinute;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: value ~/ 60, minute: value % 60),
      helpText: start ? 'Quiet hours start' : 'Quiet hours end',
    );
    if (!mounted || picked == null) return;
    final minute = picked.hour * 60 + picked.minute;
    await _save(
      start
          ? _service.settings.copyWith(quietStartMinute: minute)
          : _service.settings.copyWith(quietEndMinute: minute),
    );
  }

  Widget _panel({required Color accent, required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withValues(alpha: .065), scheme.surface),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: .3)),
      ),
      child: child,
    );
  }

  Widget _heading(String title, String subtitle, {IconData? icon}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (icon != null) ...[Icon(icon, size: 28), const SizedBox(height: 10)],
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
    ],
  );

  Widget _switch({
    required String id,
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color accent,
    bool enabled = true,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(description),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Semantics(
        label: title,
        child: Switch(
          key: ValueKey('sound-switch-$id'),
          value: value,
          activeTrackColor: accent,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    ],
  );

  Widget _category({
    required String id,
    required String title,
    required String description,
    required IconData icon,
    required Color accent,
    required bool value,
    required ValueChanged<bool> onChanged,
    required KorlixSound sound,
  }) {
    final settings = _service.settings;
    return _panel(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 26),
          ),
          const SizedBox(height: 14),
          _switch(
            id: id,
            title: title,
            description: description,
            value: value,
            onChanged: onChanged,
            accent: accent,
            enabled: settings.enabled,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: ValueKey('sound-preview-$id'),
            onPressed: settings.enabled && settings.volume > 0 && !_previewing
                ? () => _preview(sound)
                : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text('Preview $title'),
          ),
        ],
      ),
    );
  }

  Widget _packChoice(
    KorlixSoundPack pack,
    String title,
    String subtitle,
    Color color,
    IconData icon,
  ) {
    final selected = _service.settings.pack == pack;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: color.withValues(alpha: selected ? .15 : .05),
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: color.withValues(alpha: selected ? .85 : .25),
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('sound-pack-${pack.name}'),
          onTap: () => _save(_service.settings.copyWith(pack: pack)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, color: color),
                    if (selected)
                      Icon(Icons.check_circle_rounded, color: color),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _service.settings;
    final scheme = Theme.of(context).colorScheme;
    final volume = _volumeDraft ?? settings.volume;
    final status = _service.blocked
        ? 'Audio could not start. Tap Enable sounds and check your browser and device sound settings.'
        : _service.ready
        ? 'Audio is ready for this session.'
        : 'Tap Enable sounds to let Korlix play audio in this session.';
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sounds & alerts',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        top: false,
        child: Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xff123b70), Color(0xff633caa)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.graphic_eq_rounded,
                            color: Color(0xff76ebef),
                            size: 36,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Make Korlix sound like you.',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Gentle clicks, familiar chimes and a ring when someone calls.',
                            style: TextStyle(color: Color(0xffe4eaff)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_service.storageError != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: _panel(
                          accent: scheme.error,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _service.storageError!,
                                key: const ValueKey('sound-storage-error'),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                key: const ValueKey('sound-retry-save'),
                                onPressed: () => _save(_service.settings),
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Try saving again'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    _panel(
                      accent: _cyan,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _switch(
                            id: 'enabled',
                            title: 'App sounds',
                            description: settings.enabled
                                ? 'Your sound preferences are on.'
                                : 'All app sound effects are muted.',
                            value: settings.enabled,
                            onChanged: (value) =>
                                _save(settings.copyWith(enabled: value)),
                            accent: _cyan,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            status,
                            key: const ValueKey('sound-audio-status'),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            key: const ValueKey('sound-enable'),
                            style: FilledButton.styleFrom(
                              backgroundColor: _cyan,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: settings.enabled && !_previewing
                                ? () => _preview(KorlixSound.bell)
                                : null,
                            icon: const Icon(Icons.volume_up_rounded),
                            label: Text(
                              _previewing
                                  ? 'Starting sound…'
                                  : _service.ready && !_service.blocked
                                  ? 'Test sound'
                                  : 'Enable sounds',
                            ),
                          ),
                          if (settings.quietHours) ...[
                            const SizedBox(height: 12),
                            const Text(
                              'Quiet hours also silence previews during your quiet schedule.',
                            ),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            'Volume · ${(volume * 100).round()}%',
                            key: const ValueKey('sound-volume-label'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Slider(
                            key: const ValueKey('sound-volume'),
                            value: volume,
                            divisions: 20,
                            label: '${(volume * 100).round()}%',
                            activeColor: _cyan,
                            semanticFormatterCallback: (value) =>
                                '${(value * 100).round()} percent',
                            onChanged: settings.enabled
                                ? (value) =>
                                      setState(() => _volumeDraft = value)
                                : null,
                            onChangeEnd: settings.enabled
                                ? (value) {
                                    setState(() => _volumeDraft = null);
                                    unawaited(
                                      _save(
                                        _service.settings.copyWith(
                                          volume: value,
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                          ),
                          const Text(
                            'Your device volume and browser audio rules still apply.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _heading(
                      'Choose your sound pack',
                      'One style for all your app sounds. Use the previews below to listen.',
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns =
                            constraints.maxWidth >= 660 &&
                                MediaQuery.textScalerOf(context).scale(16) <= 22
                            ? 3
                            : 1;
                        final width =
                            (constraints.maxWidth - 12 * (columns - 1)) /
                            columns;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: width,
                              child: _packChoice(
                                KorlixSoundPack.signature,
                                'Korlix Signature',
                                'Bright and futuristic',
                                _cyan,
                                Icons.auto_awesome_rounded,
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: _packChoice(
                                KorlixSoundPack.classic,
                                'Classic',
                                'Clear and familiar',
                                _violet,
                                Icons.music_note_rounded,
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: _packChoice(
                                KorlixSoundPack.soft,
                                'Soft',
                                'Warm and gentle',
                                _green,
                                Icons.spa_rounded,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    _heading(
                      'What would you like to hear?',
                      'Choose each sound separately. Previews let you try a category even when its switch is off.',
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns =
                            constraints.maxWidth >= 700 &&
                                MediaQuery.textScalerOf(context).scale(16) <= 22
                            ? 2
                            : 1;
                        final width =
                            (constraints.maxWidth - 14 * (columns - 1)) /
                            columns;
                        final categories = [
                          _category(
                            id: 'clicks',
                            title: 'Clicks',
                            description:
                                'A soft tap when you use app controls.',
                            icon: Icons.touch_app_rounded,
                            accent: _cyan,
                            value: settings.clicks,
                            onChanged: (value) =>
                                _save(settings.copyWith(clicks: value)),
                            sound: KorlixSound.click,
                          ),
                          _category(
                            id: 'messages',
                            title: 'Messages',
                            description:
                                'A chime for new Korlix Social messages.',
                            icon: Icons.chat_bubble_outline_rounded,
                            accent: _violet,
                            value: settings.messages,
                            onChanged: (value) =>
                                _save(settings.copyWith(messages: value)),
                            sound: KorlixSound.message,
                          ),
                          _category(
                            id: 'calls',
                            title: 'Incoming calls',
                            description: 'A ringtone for Korlix Social calls.',
                            icon: Icons.ring_volume_rounded,
                            accent: _green,
                            value: settings.calls,
                            onChanged: (value) =>
                                _save(settings.copyWith(calls: value)),
                            sound: KorlixSound.ringtone,
                          ),
                          _category(
                            id: 'bells',
                            title: 'Bells & updates',
                            description:
                                'Bells, task confirmations and alerts.',
                            icon: Icons.notifications_active_outlined,
                            accent: _amber,
                            value: settings.bells,
                            onChanged: (value) =>
                                _save(settings.copyWith(bells: value)),
                            sound: KorlixSound.bell,
                          ),
                        ];
                        return Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: [
                            for (final category in categories)
                              SizedBox(width: width, child: category),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    _panel(
                      accent: _violet,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _switch(
                            id: 'quiet',
                            title: 'Quiet hours',
                            description:
                                'Silence all app effects, including call ringing and previews, on a schedule.',
                            value: settings.quietHours,
                            onChanged: (value) =>
                                _save(settings.copyWith(quietHours: value)),
                            accent: _violet,
                          ),
                          const SizedBox(height: 18),
                          _switch(
                            id: 'welcome',
                            title: 'Rici welcome voice',
                            description:
                                'A spoken introduction after you sign in. Uses your volume and quiet hours. No AI GAS is used.',
                            value: settings.welcomeVoice,
                            onChanged: (value) =>
                                _save(settings.copyWith(welcomeVoice: value)),
                            accent: _cyan,
                          ),
                          if (settings.quietHours) ...[
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                OutlinedButton.icon(
                                  key: const ValueKey('sound-quiet-start'),
                                  onPressed: () => _pickTime(start: true),
                                  icon: const Icon(Icons.bedtime_outlined),
                                  label: Text(
                                    'From ${_time(settings.quietStartMinute)}',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  key: const ValueKey('sound-quiet-end'),
                                  onPressed: () => _pickTime(start: false),
                                  icon: const Icon(Icons.wb_sunny_outlined),
                                  label: Text(
                                    'Until ${_time(settings.quietEndMinute)}',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              settings.quietStartMinute ==
                                      settings.quietEndMinute
                                  ? 'Matching start and end times mute sounds all day.'
                                  : 'Uses the local time on this device. An end time earlier than the start continues into the next day.',
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Saved on this device. Sounds play while Korlix is open and active; these settings do not enable closed-app or locked-screen notifications. Sound effects use no AI GAS.',
                      key: const ValueKey('sound-device-note'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
