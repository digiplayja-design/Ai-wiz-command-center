import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

import 'magic_client.dart';
import 'magic_orbits.dart';
import 'magic_theme.dart';
import 'reveal_clip.dart';

class MagicResult extends StatefulWidget {
  const MagicResult({
    super.key,
    required this.client,
    required this.initialJob,
    this.motion = 'Cosmic orbits',
    this.autoReport = false,
  });
  final MagicClient client;
  final Map<String, dynamic> initialJob;
  final String motion;
  final bool autoReport;
  @override
  State<MagicResult> createState() => _MagicResultState();
}

class _MagicResultState extends State<MagicResult> with WidgetsBindingObserver {
  late Map<String, dynamic> _job = widget.initialJob;
  Uint8List? _image;
  String? _error;
  Timer? _poll;
  bool _checking = false, _exporting = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.addListener(_account);
    unawaited(_refresh());
    if (widget.autoReport) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_report());
      });
    }
  }

  void _account() {
    if (!widget.client.valid) {
      _poll?.cancel();
      if (mounted) setState(() => _image = null);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_checking || !widget.client.valid) return;
    _checking = true;
    _poll?.cancel();
    try {
      final next = await widget.client.job(_job['id'] as String);
      Uint8List? finalImage = _image;
      if (next['state'] == 'ready' && finalImage == null) {
        finalImage = await widget.client.image(next['id'] as String);
      }
      if (mounted && widget.client.valid) {
        setState(() {
          _job = next;
          _image = finalImage;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Connection interrupted. Your job is saved. Tap Refresh to check it.',
        );
      }
    } finally {
      _checking = false;
      if (mounted &&
          widget.client.valid &&
          !['ready', 'failed', 'deleted'].contains(_job['state'])) {
        _poll = Timer(const Duration(seconds: 4), () => unawaited(_refresh()));
      }
    }
  }

  Rect _origin() {
    final box = context.findRenderObject() as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _export({bool save = false, bool clip = false}) async {
    if (_exporting || _image == null) return;
    setState(() => _exporting = true);
    try {
      final bytes = clip ? await makeRevealClip(_image!) : _image!;
      if (!mounted || !widget.client.valid) return;
      final name = clip ? 'korlix-magic-reveal.gif' : 'korlix-magic.png';
      if (save) {
        await FilePicker.platform.saveFile(
          dialogTitle: 'Save your magic photo',
          fileName: name,
          bytes: bytes,
          type: FileType.image,
        );
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                bytes,
                mimeType: clip ? 'image/gif' : 'image/png',
                name: name,
              ),
            ],
            fileNameOverrides: [name],
            sharePositionOrigin: _origin(),
            text: clip ? 'Made with Korlix Magic Camera' : null,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        _notice('Could not open the save or share sheet. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _report() async {
    String details = '';
    String reason = 'Offensive or hateful';
    bool sending = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          scrollable: true,
          title: const Text('Report this generation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The generated photo and its prompt will be shared privately with Korlix’s review team.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: reason,
                isExpanded: true,
                items:
                    const [
                          'Offensive or hateful',
                          'Sexual content',
                          'Violence or harm',
                          'Distorted face or body',
                          'Other',
                        ]
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                onChanged: sending ? null : (v) => reason = v!,
              ),
              const SizedBox(height: 14),
              TextFormField(
                onChanged: (value) => details = value,
                maxLength: 2000,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Tell us more (optional)',
                ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      update(() => sending = true);
                      try {
                        await widget.client.report(
                          _job['id'] as String,
                          reason,
                          details,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          _notice(
                            'Report received. Thank you for helping improve Magic Camera.',
                          );
                        }
                      } catch (_) {
                        if (ctx.mounted) {
                          update(
                            () => error =
                                'The report was not sent. Please try again.',
                          );
                        }
                      } finally {
                        if (ctx.mounted) update(() => sending = false);
                      }
                    },
              child: Text(sending ? 'Sending…' : 'Send report'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this magic photo?'),
        content: const Text(
          'This removes it from your private gallery. Deleting a completed result does not restore a generation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await widget.client.delete(_job['id'] as String);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        _notice('Deletion is pending. Please refresh and try again.');
      }
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.client.removeListener(_account);
    _image = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.client.valid) {
      return const Scaffold(
        body: Center(child: Text('Sign in again to view your photos.')),
      );
    }
    final ready = _job['state'] == 'ready',
        failed = _job['state'] == 'failed' || _job['state'] == 'deleted';
    return Scaffold(
      appBar: AppBar(
        title: Text(ready ? 'Your magic moment' : 'A little magic in motion'),
        actions: [
          if (ready)
            IconButton(
              tooltip: 'Delete photo',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          IconButton(
            tooltip: 'Refresh generation',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(onPressed: _refresh, child: const Text('Refresh')),
              ],
            ),
          Expanded(
            child: ready && _image != null
                ? SingleChildScrollView(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 900),
                              builder: (context, value, child) => ClipPath(
                                clipper: _RevealClipper(value),
                                child: child,
                              ),
                              child: Image.memory(
                                _image!,
                                key: const Key('magic-final-image'),
                                fit: BoxFit.contain,
                                semanticLabel: 'Your AI-generated magic photo',
                              ),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'A little imagination. Unmistakably your moment.',
                            style: TextStyle(color: magicMuted),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed: _exporting
                                    ? null
                                    : () => _export(save: true),
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('Save'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _exporting ? null : () => _export(),
                                icon: const Icon(Icons.ios_share),
                                label: const Text('Share'),
                              ),
                              OutlinedButton.icon(
                                key: const Key('magic-report'),
                                onPressed: _report,
                                icon: const Icon(Icons.flag_outlined),
                                label: const Text('Report'),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _exporting
                              ? null
                              : () => _export(clip: true),
                          icon: const Icon(Icons.motion_photos_on_outlined),
                          label: Text(
                            _exporting ? 'Preparing…' : 'Share magic reveal',
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 24),
                          child: Text(
                            'AI-generated • Review details before sharing',
                            style: TextStyle(color: magicMuted, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  )
                : failed
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.auto_awesome_outlined,
                            size: 48,
                            color: magicOrange,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _job['error']?.toString() ??
                                'This photo is no longer in your gallery.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Choose another moment'),
                          ),
                        ],
                      ),
                    ),
                  )
                : MagicOrbits(
                    style: widget.motion,
                    label: _job['state'] == 'queued'
                        ? 'Your moment is in the stars'
                        : 'Your magic is taking shape',
                    detail: 'You can leave this screen after upload. Your finished photo will be waiting in your private gallery.',
                  ),
          ),
        ],
      ),
    );
  }
}

class _RevealClipper extends CustomClipper<Path> {
  _RevealClipper(this.progress);
  final double progress;
  @override
  Path getClip(Size size) => Path()
    ..addOval(
      Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: size.longestSide * .75 * progress,
      ),
    );
  @override
  bool shouldReclip(_RevealClipper old) => old.progress != progress;
}
