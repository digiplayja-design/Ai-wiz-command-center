import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'brain_api.dart';
import 'brain_projection.dart';
import 'brain_projection_navigation.dart';
import 'brain_projection_presentation.dart';

/// The remote Earth iframe gets no account bridge. Only this bundled document
/// receives the unpredictable per-view nonce, which is never posted to frames.
class BrainProjectionBridge {
  BrainProjectionBridge(this.nonce);
  final String nonce;
  final Set<String> _seen = {};
  final Set<String> _pending = {};

  static const actions = {
    'close',
    'room',
    'search',
    'directions',
    'select',
    'camera',
    'ask',
    'savePlace',
    'startVoice',
    'stopVoice',
    'pauseVoice',
    'resumeVoice',
    'openSource',
    'rendererReady',
    'cameraStatus',
  };

  Map<String, dynamic>? accept(String raw) {
    if (raw.length > 16000) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map || value['nonce'] != nonce) return null;
      final id = value['id'];
      final action = value['action'];
      final payload = value['payload'];
      if (id is! String ||
          !RegExp(r'^\d{1,10}$').hasMatch(id) ||
          !actions.contains(action) ||
          _seen.contains(id) ||
          (_pending.length >= 8 &&
              action != 'stopVoice' &&
              action != 'pauseVoice' &&
              action != 'close' &&
              !(action == 'camera' &&
                  payload is Map &&
                  payload['operation'] == 'stopCamera'))) {
        return null;
      }
      if (payload != null && payload is! Map) return null;
      _seen.add(id);
      _pending.add(id);
      // IDs are monotonic in the bundled page. Keep a bounded replay window.
      if (_seen.length > 2048) _seen.remove(_seen.first);
      return {
        'id': id,
        'action': action,
        'payload': payload == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(payload),
      };
    } catch (_) {
      return null;
    }
  }

  void complete(String id) => _pending.remove(id);
}

class BrainProjectionScreen extends StatefulWidget {
  const BrainProjectionScreen({
    super.key,
    required this.projection,
    this.onWebViewCreated,
  });
  final BrainProjection projection;
  @visibleForTesting
  final ValueChanged<WebViewController>? onWebViewCreated;

  @override
  State<BrainProjectionScreen> createState() => _BrainProjectionScreenState();
}

class _BrainProjectionScreenState extends State<BrainProjectionScreen>
    with WidgetsBindingObserver {
  late final WebViewController _web;
  late final BrainProjectionBridge _bridge;
  late final ProjectionProviderLinkLauncher _providerLinks;
  late final BrainProjectionOrientation _orientation;
  bool _ready = false;
  bool _appActive = true;
  bool _viewportSendScheduled = false;
  Map<String, dynamic> _viewport = {};
  String _voiceAction = '';
  int _voiceActionEpoch = 0;
  String? _error;
  String? _bundledDocumentUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appActive = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _orientation = BrainProjectionOrientation();
    unawaited(_orientation.update(
      projectionLayoutPreference(widget.projection.snapshot['layoutPreference']),
    ));
    final random = Random.secure();
    _bridge = BrainProjectionBridge(
      base64Url.encode(List.generate(32, (_) => random.nextInt(256))),
    );
    _providerLinks = ProjectionProviderLinkLauncher(
      launch: (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
    );
    widget.projection.addListener(_changed);
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xff0b0815))
      ..addJavaScriptChannel(
        'Projection',
        onMessageReceived: (message) => unawaited(_message(message.message)),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final config = widget.projection.snapshot['config'] as Map;
            final action = projectionNavigationPolicy(
              url: request.url,
              isMainFrame: request.isMainFrame,
              rendererUrl: config['rendererUrl'] as String?,
              bundledDocumentUrl: _bundledDocumentUrl,
            );
            if (action == ProjectionNavigation.external) {
              unawaited(_openProviderLink(request.url));
              return NavigationDecision.prevent;
            }
            return action == ProjectionNavigation.allow
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onPageStarted: (url) {
            if (isBundledProjectionDocument(
              url,
              expectedUrl: _bundledDocumentUrl,
            )) {
              if (mounted) setState(() => _ready = false);
            }
          },
          onPageFinished: (url) {
            if (!mounted ||
                !isBundledProjectionDocument(
                  url,
                  expectedUrl: _bundledDocumentUrl,
                )) {
              return;
            }
            _bundledDocumentUrl ??= url;
            setState(() => _ready = true);
            unawaited(_connect());
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(
                () => _error = 'The projection view could not load. Your conversation is still available.',
              );
            }
          },
        ),
      )
      ..loadFlutterAsset('assets/web/projection.html');
    widget.onWebViewCreated?.call(_web);
  }

  Map<String, dynamic> get _presentation => {
    'nativeControls': true,
    'viewport': _viewport,
  };

  Future<void> _connect() async {
    if (!mounted || !_ready || !_appActive) return;
    try {
      final connection = jsonEncode({
        'nonce': _bridge.nonce,
        'snapshot': widget.projection.snapshot,
        'presentation': _presentation,
      });
      await _web.runJavaScript(
        'if (typeof window.KorlixProjectionConnect !== "function") '
        '{ throw new Error("Projection did not initialize"); } '
        'window.KorlixProjectionConnect($connection);',
      );
    } catch (_) {
      if (mounted && _appActive) {
        setState(() => _error =
            'The projection view could not load. Your conversation controls are still available.');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive && mounted) {
      // The same document/nonce survives app switching. Refresh native state,
      // never restart the microphone or recreate the provider frame.
      unawaited(_connect());
    }
  }

  void _recordViewport(BoxConstraints constraints, Size window, String preference) {
    if (!constraints.maxWidth.isFinite || !constraints.maxHeight.isFinite) {
      return;
    }
    final next = projectionNativeViewport(
      window: window,
      viewport: Size(constraints.maxWidth, constraints.maxHeight),
      preference: preference,
    );
    if (_viewport['width'] == next['width'] &&
        _viewport['height'] == next['height'] &&
        _viewport['landscape'] == next['landscape']) return;
    _viewport = next;
    if (_viewportSendScheduled) return;
    _viewportSendScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportSendScheduled = false;
      if (mounted) {
        unawaited(_send({'type': 'presentation', 'presentation': _presentation}));
      }
    });
  }

  Future<void> _openProviderLink(String url) async {
    final opened = await _providerLinks.open(url);
    if (opened == false && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This Google Maps link could not open.')),
      );
    }
  }

  void _changed() {
    if (mounted) {
      setState(() {});
      unawaited(_orientation.update(
        projectionLayoutPreference(widget.projection.snapshot['layoutPreference']),
      ));
      unawaited(
        _send({'type': 'snapshot', 'state': widget.projection.snapshot}),
      );
    }
  }

  Future<void> _send(Map<String, dynamic> message) async {
    if (!mounted || !_ready || !_appActive) return;
    try {
      await _web.runJavaScript(
        'window.KorlixProjectionReceive?.(${jsonEncode(message)});',
      );
    } catch (_) {
      // The native route may close while a queued map result is completing.
    }
  }

  Future<void> _message(String raw) async {
    if (!mounted || !_ready || !_appActive || !widget.projection.isOpen) return;
    final message = _bridge.accept(raw);
    if (message == null) return;
    final id = message['id'] as String;
    try {
      final payload = message['payload'] as Map<String, dynamic>;
      Object? data;
      if (message['action'] == 'openSource') {
        final url = payload['url'];
        if (url is! String || !widget.projection.mayOpenSource(url)) {
          throw const BrainApiException(
            'Choose a source attached to the current answer.',
          );
        }
        final opened = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        if (!opened) {
          throw const BrainApiException(
            'The source could not open on this device.',
          );
        }
        data = {'opened': true};
      } else {
        data = await widget.projection.dispatch(
          message['action'] as String,
          payload,
        );
      }
      await _send({'type': 'reply', 'id': id, 'data': data});
    } on BrainApiException catch (error) {
      await _send({'type': 'reply', 'id': id, 'error': error.message});
    } catch (_) {
      await _send({
        'type': 'reply',
        'id': id,
        'error': 'This Projection request could not finish. Please try again.',
      });
    } finally {
      _bridge.complete(id);
    }
  }

  Future<void> _nativeVoiceAction(String action) async {
    if (!mounted || _voiceAction == 'stop') return;
    final epoch = ++_voiceActionEpoch;
    setState(() => _voiceAction = action);
    try {
      await widget.projection.dispatch('${action}Voice', {});
    } catch (error) {
      if (mounted && epoch == _voiceActionEpoch) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          error is BrainApiException ? error.message
              : 'The conversation action could not finish. Please try again.',
        )));
      }
    } finally {
      if (mounted && epoch == _voiceActionEpoch) {
        setState(() => _voiceAction = '');
      }
    }
  }

  Future<void> _nativeLayout(String preference) async {
    try {
      await widget.projection.dispatch('layout', {'preference': preference});
    } on BrainApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    }
  }

  Future<void> _retry() async {
    setState(() { _error = null; _ready = false; });
    try {
      await _web.loadFlutterAsset('assets/web/projection.html');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'The projection view could not load. Please try again.');
      }
    }
  }

  @override
  void dispose() {
    _ready = false;
    ++_voiceActionEpoch;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_orientation.restore());
    _providerLinks.dispose();
    widget.projection.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.projection.snapshot;
    final preference = projectionLayoutPreference(snapshot['layoutPreference']);
    final window = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: const Color(0xff0b0815),
      body: SafeArea(
        child: BrainProjectionPresentation(
          voice: Map<String, dynamic>.from(snapshot['voice'] as Map),
          layoutPreference: preference,
          voiceAction: _voiceAction,
          onClose: widget.projection.close,
          onVoiceAction: (action) => unawaited(_nativeVoiceAction(action)),
          onLayout: (layout) => unawaited(_nativeLayout(layout)),
          child: LayoutBuilder(builder: (context, constraints) {
            _recordViewport(constraints, window, preference);
            return Stack(fit: StackFit.expand, children: [
              WebViewWidget(
                key: const ValueKey('brain-projection-webview'),
                controller: _web,
              ),
              if (!_ready && _error == null)
                const IgnorePointer(child: Center(child: CircularProgressIndicator())),
              if (_error != null)
                ColoredBox(
                  color: const Color(0xff0b0815),
                  child: Center(child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: () => unawaited(_retry()),
                          child: const Text('Retry projection')),
                    ]),
                  )),
                ),
            ]);
          }),
        ),
      ),
    );
  }
}
