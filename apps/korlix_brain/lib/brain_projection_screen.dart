import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'brain_api.dart';
import 'brain_projection.dart';
import 'brain_projection_navigation.dart';

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
  };

  Map<String, dynamic>? accept(String raw) {
    if (raw.length > 16000) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map || value['nonce'] != nonce) return null;
      final id = value['id'];
      final action = value['action'];
      if (id is! String ||
          !RegExp(r'^\d{1,10}$').hasMatch(id) ||
          !actions.contains(action) ||
          _seen.contains(id) ||
          (_pending.length >= 8 &&
              action != 'stopVoice' &&
              action != 'pauseVoice' &&
              action != 'close')) {
        return null;
      }
      final payload = value['payload'];
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
  const BrainProjectionScreen({super.key, required this.projection});
  final BrainProjection projection;

  @override
  State<BrainProjectionScreen> createState() => _BrainProjectionScreenState();
}

class _BrainProjectionScreenState extends State<BrainProjectionScreen> {
  late final WebViewController _web;
  late final BrainProjectionBridge _bridge;
  late final ProjectionProviderLinkLauncher _providerLinks;
  bool _ready = false;
  String? _error;
  String? _bundledDocumentUrl;

  @override
  void initState() {
    super.initState();
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
              _ready = false;
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
            _ready = true;
            unawaited(
              _web
                  .runJavaScript(
                    'window.KorlixProjectionConnect?.(${jsonEncode({'nonce': _bridge.nonce, 'snapshot': widget.projection.snapshot})});',
                  )
                  .catchError((Object _) {}),
            );
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
    if (mounted && _ready) {
      unawaited(
        _send({'type': 'snapshot', 'state': widget.projection.snapshot}),
      );
    }
  }

  Future<void> _send(Map<String, dynamic> message) async {
    if (!mounted || !_ready) return;
    try {
      await _web.runJavaScript(
        'window.KorlixProjectionReceive?.(${jsonEncode(message)});',
      );
    } catch (_) {
      // The native route may close while a queued map result is completing.
    }
  }

  Future<void> _message(String raw) async {
    if (!mounted || !_ready || !widget.projection.isOpen) return;
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

  @override
  void dispose() {
    _ready = false;
    _providerLinks.dispose();
    widget.projection.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff0b0815),
    body: SafeArea(
      child: _error == null
          ? WebViewWidget(controller: _web)
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: widget.projection.close,
                      child: const Text('Close projection'),
                    ),
                    TextButton(
                      onPressed: () =>
                          widget.projection.dispatch('stopVoice', {}),
                      child: const Text('Stop conversation'),
                    ),
                  ],
                ),
              ),
            ),
    ),
  );
}
