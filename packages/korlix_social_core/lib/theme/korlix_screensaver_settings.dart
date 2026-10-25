import 'dart:async';
import 'package:flutter/material.dart';
import 'korlix_screensaver_controller.dart';

class KorlixScreensaverSettings extends StatefulWidget {
  const KorlixScreensaverSettings({super.key, this.controller});
  final KorlixScreensaverController? controller;
  @override
  State<KorlixScreensaverSettings> createState() =>
      _KorlixScreensaverSettingsState();
}

class _KorlixScreensaverSettingsState extends State<KorlixScreensaverSettings> {
  KorlixScreensaverController get _controller =>
      widget.controller ?? kKorlixScreensaver;
  String? _notice;
  @override
  void initState() {
    super.initState();
    unawaited(_controller.restore());
  }

  Future<void> _toggle(bool enabled) async {
    setState(() => _notice = null);
    if (!await _controller.setEnabled(enabled) && mounted) {
      setState(
        () => _notice =
            'Changed for this visit. Device storage could not save this setting.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile.adaptive(
              key: const Key('smoke-screensaver-toggle'),
              title: const Text('Smoke screensaver'),
              subtitle: const Text(
                'Smoke rises over your current screen after 30 seconds of inactivity. Tap anywhere to clear.',
              ),
              value: _controller.enabled,
              onChanged: (enabled) => unawaited(_toggle(enabled)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('preview-smoke-screensaver'),
                onPressed: _controller.preview,
                icon: const Icon(Icons.cloud_outlined, size: 18),
                label: const Text('Preview smoke'),
              ),
            ),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _notice!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
