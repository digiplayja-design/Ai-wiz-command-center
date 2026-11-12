import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appBuildName, appBuildNumber;
import 'package:korlix_receipt_core/privacy/korlix_third_party_ai_consent.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'brain_api.dart';
import 'brain_documents.dart';
import 'brain_documents_screen.dart';
import 'brain_camera_ask.dart';
import 'brain_camera_ask_screen.dart';
import 'brain_directions.dart';
import 'brain_auth.dart';
import 'brain_repository.dart';
import 'brain_voice.dart';
import 'brain_model.dart';
import 'brain_transcripts.dart';
import 'brain_pronunciation.dart';
import 'brain_welcome.dart';
import 'brain_billing.dart';
import 'brain_billing_screen.dart';
import 'brain_projection.dart';
import 'brain_projection_screen.dart';

class BrainWorkspace extends StatefulWidget {
  const BrainWorkspace({super.key, required this.auth});
  final BrainAuthController auth;
  @override
  State<BrainWorkspace> createState() => _BrainWorkspaceState();
}

class _BrainWorkspaceState extends State<BrainWorkspace>
    with WidgetsBindingObserver {
  late final BrainApi _api;
  late final BrainRepository _repository;
  late final BrainVoice _voice;
  late final BrainProjection _projection;
  late final BrainWelcome _welcome;
  late final BrainBilling _billing;
  late final WebViewController _web;
  final _speech = SpeechToText();
  final _inFlight = <String>{};
  bool _disposed = false, _pickerBusy = false, _dictating = false;
  int _voiceStartRequest = 0;
  bool _captureStarting = false;
  String? _pageError;
  BrainTranscripts? _transcripts;

  BrainTranscripts get _transcriptStore {
    final session = widget.auth.session;
    if (session == null) {
      throw const BrainTranscriptException('Please sign in again.');
    }
    final owner = brainTranscriptOwner(session.accessToken);
    return _transcripts ??= BrainTranscripts(
      owner: owner,
      isCurrent: () {
        if (_disposed || !mounted || widget.auth.session == null) return false;
        try {
          return brainTranscriptOwner(widget.auth.session!.accessToken) ==
              owner;
        } catch (_) {
          return false;
        }
      },
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = BrainApi(widget.auth);
    _billing = BrainBilling(_api);
    unawaited(_billing.initialize().catchError((Object _) {}));
    _repository = BrainRepository(_api);
    _projection = BrainProjection(
      backendUrl: widget.auth.backendUrl,
      request: _projectionRequest,
      onOpen: () {
        if (!_disposed && mounted) setState(() {});
        unawaited(_welcome.stop().catchError((Object _) {}));
      },
      onClose: () {
        if (!_disposed && mounted) setState(() {});
      },
      onStartVoice: () async {
        if (!_voice.active) await _dispatch('startVoice', {'mode': 'live'});
      },
      onStopVoice: () async {
        await _dispatch('stopVoice', {});
      },
      onPauseVoice: () => _dispatch('pauseVoice', {}).then((_) {}),
      onResumeVoice: () => _dispatch('resumeVoice', {}).then((_) {}),
      onDirections: (query) => unawaited(_openDirections(query).catchError((Object _) {
        _emit({'type': 'notice', 'message': 'Directions could not open. Please try again.'});
      })),
      onSave: _saveProjectionPlace,
    );
    _voice = BrainVoice(
      _api,
      _emit,
      onProjection: _projection.voiceTurn,
      recognizesProjection: _projection.recognizesVoiceControl,
      onSaved: (result) async {
        // A confirmed write must remain visible even if the subsequent refresh fails.
        final memory = Map<String, dynamic>.from(result['memory'] as Map);
        _repository.acceptVoiceMemory(memory);
        _emit({'type': 'brainSnapshot', 'snapshot': _repository.snapshot});
      },
    );
    _welcome = BrainWelcome(
      canPlay: () =>
          !_disposed &&
          mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          !_voice.active &&
          !_dictating &&
          !_captureStarting &&
          !_pickerBusy,
      onEvent: _emit,
    );
    final params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          )
        : const PlatformWebViewControllerCreationParams();
    _web = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xff100b1b))
      ..addJavaScriptChannel(
        'Korlix',
        onMessageReceived: (message) => unawaited(_message(message.message)),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            // No remote page may inherit the authenticated native command bridge.
            return uri?.scheme == 'file' && uri!.path.contains('/assets/web/')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(
                () => _pageError = 'The app screen could not load. Tap Retry.',
              );
            }
          },
        ),
      );
    if (_web.platform is AndroidWebViewController) {
      unawaited(
        (_web.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false)
            .then((_) => _web.loadFlutterAsset('assets/web/index.html')),
      );
    } else {
      unawaited(_web.loadFlutterAsset('assets/web/index.html'));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_welcome.stop(dismiss: false).catchError((Object _) {}));
    } else {
      unawaited(_voice.refreshUsage());
    }
    _emit({
      'type': 'appLifecycle',
      'active': state == AppLifecycleState.resumed,
    });
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_stopDictation());
    }
    if (state == AppLifecycleState.detached) {
      unawaited(_voice.stop(reason: 'app_detached'));
    }
  }

  void _emit(Map<String, dynamic> event) {
    if (_disposed || !mounted) return;
    if (event['type'] == 'transcript') {
      if (event['role'] == 'rici' && event['text'] is String) {
        event = {...event, 'text': brainDisplaySpeech(event['text'] as String)};
      }
      try {
        final item = _transcriptStore.receive(
          event['role'] as String,
          event['text'] as String,
        );
        if (item != null) event = {...event, ...item.toJson()};
      } on BrainTranscriptException {
        // A local archive/account error must not interrupt working live audio.
      }
    }
    _projection.receiveVoice(event);
    unawaited(
      _web
          .runJavaScript('window.KorlixBrainReceive?.(${jsonEncode(event)});')
          .catchError((Object _) {}),
    );
  }

  String _text(
    Map<String, dynamic> data,
    String key, {
    int max = 12000,
    bool empty = false,
  }) {
    final value = data[key];
    if (value is! String ||
        value.length > max ||
        (!empty && value.trim().isEmpty)) {
      throw const BrainApiException(
        'This action is incomplete. Please review it again.',
      );
    }
    return value;
  }

  Future<void> _message(String message) async {
    if (_disposed || message.length > 75000) return;
    String? id;
    try {
      final value = jsonDecode(message);
      if (value is! Map ||
          value['id'] is! String ||
          value['action'] is! String) {
        return;
      }
      id = value['id'] as String;
      if (!RegExp(r'^\d{1,10}$').hasMatch(id) || !_inFlight.add(id)) return;
      if (_inFlight.length > 12 &&
          value['action'] != 'stopVoice' &&
          value['action'] != 'pauseVoice' &&
          value['action'] != 'stopWelcome') {
        throw const BrainApiException(
          'Please wait for the current actions to finish.',
        );
      }
      final data = Map<String, dynamic>.from(value['payload'] as Map? ?? {});
      final result = await _dispatch(value['action'] as String, data);
      _emit({'type': 'reply', 'id': id, 'data': result});
    } catch (error) {
      if (id != null) {
        _emit({
          'type': 'reply',
          'id': id,
          'error':
              error is BrainApiException ||
                  error is BrainAuthException ||
                  error is BrainTranscriptException
              ? error.toString()
              : 'Could not complete this action. Check your connection and try again.',
        });
      }
    } finally {
      if (id != null) _inFlight.remove(id);
    }
  }

  Future<Object?> _dispatch(String action, Map<String, dynamic> data) async {
    // Welcome controls are local, available even when account syncing fails.
    if (action == 'welcomeState') {
      return {
        'native': _welcome.nativePlayback,
        'automatic': _welcome.automaticPending,
        'foreground':
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      };
    }
    if (action == 'playWelcome') {
      final token = data['token'];
      if (token is! int || token < 1) {
        throw const BrainApiException('Please replay the welcome.');
      }
      return _welcome.play(token, automatic: data['automatic'] == true);
    }
    if (action == 'stopWelcome') {
      await _welcome.stop(dismiss: data['dismiss'] != false);
      return null;
    }
    if (action == 'welcomeHeard') {
      _welcome.heard();
      return null;
    }
    // Stop is local hardware control. It must remain available while another
    // command or consent dialog is pending, even if the account expires.
    if (action == 'stopVoice') {
      ++_voiceStartRequest;
      _captureStarting = false;
      _projection.cancelPending();
      await _voice.stop();
      return null;
    }
    if (action == 'pauseVoice') {
      ++_voiceStartRequest;
      _captureStarting = false;
      _projection.cancelPending();
      await _voice.pause();
      return {'active': _voice.active, 'paused': _voice.paused};
    }
    if (widget.auth.session == null) {
      throw const BrainApiException('Please sign in again.');
    }
    switch (action) {
      case 'resumeVoice':
        final request = ++_voiceStartRequest;
        _captureStarting = true;
        try {
          await _welcome.stop();
          await _stopDictation();
          if (await _consent('Resume Rici', {
            KorlixThirdPartyAiDataCategory.voiceAudioAndTranscripts,
            KorlixThirdPartyAiDataCategory.agentTrainingAndMemory,
          }) && !_disposed && mounted && request == _voiceStartRequest) {
            await _voice.resume();
          }
          return {'active': _voice.active, 'paused': _voice.paused};
        } finally {
          if (request == _voiceStartRequest) _captureStarting = false;
        }
      case 'cameraAsk':
        return _openCameraAsk();
      case 'openDocuments':
        return _openDocuments('both');
      case 'directions':
        await _openDirections('');
        return null;
      case 'openProjection':
        _projection.open();
        return {'open': true};
      case 'listSavedTranscripts':
        return _transcriptStore.listSaved();
      case 'saveTranscript':
        return _transcriptStore.save(_text(data, 'messageId', max: 32));
      case 'shareTranscript':
        final item = await _transcriptStore.get(
          _text(data, 'messageId', max: 32),
        );
        if (!mounted || _disposed) return null;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) {
          throw const BrainTranscriptException(
            'Open this message again to share it.',
          );
        }
        final result = await SharePlus.instance.share(
          ShareParams(
            text: item.shareText,
            subject:
                'KORLIX Brain+Voice · ${item.role == 'you' ? 'You' : 'Rici'}',
            sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
          ),
        );
        return {'shared': result.status == ShareResultStatus.success};
      case 'deleteTranscript':
        final store = _transcriptStore;
        final item = await store.get(_text(data, 'messageId', max: 32));
        if (!mounted || _disposed) return {'deleted': false};
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete this transcript message?'),
            content: const Text(
              'Removes this message and its saved copy from this device. Brain memories and copies you already shared are unchanged.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete message'),
              ),
            ],
          ),
        );
        if (confirmed == true) await store.delete(item.id);
        return {'deleted': confirmed == true};
      case 'load':
        return _repository.load();
      case 'saveMemory':
        return _repository.saveMemory(
          _text(data, 'text', max: 4000),
          _text(data, 'source', max: 500),
        );
      case 'saveTraining':
        return _repository.saveTraining(
          _text(data, 'text'),
          _text(data, 'expected', empty: true),
        );
      case 'deleteMemory':
        return _repository.deleteMemory(
          _text(data, 'key', max: 100),
          _text(data, 'text', max: 4000),
        );
      case 'deleteBehavior':
        if (data['key'] is! int) {
          throw const BrainApiException('Choose the behavior again.');
        }
        return _repository.deleteBehavior(
          data['key'] as int,
          _text(data, 'expected', empty: true),
        );
      case 'undo':
        return _repository.undo();
      case 'startVoice':
        final modeValue = data['mode'] ?? 'live';
        if (modeValue != 'live' && modeValue != 'deep') {
          throw const BrainApiException(
            'Choose Live Conversation or Deep Think.',
          );
        }
        final startRequest = ++_voiceStartRequest;
        _captureStarting = true;
        try {
          await _welcome.stop();
          await _stopDictation();
          if (await _consent('Talk to Rici', {
            KorlixThirdPartyAiDataCategory.voiceAudioAndTranscripts,
            KorlixThirdPartyAiDataCategory.agentTrainingAndMemory,
          })) {
            if (!_disposed &&
                mounted &&
                startRequest == _voiceStartRequest &&
                widget.auth.session != null) {
              await _voice.start(
                mode: modeValue == 'deep'
                    ? BrainVoiceMode.deep
                    : BrainVoiceMode.live,
              );
            }
          }
          return {'active': _voice.active};
        } finally {
          if (startRequest == _voiceStartRequest) _captureStarting = false;
        }
      case 'dictate':
        _captureStarting = true;
        try {
          await _welcome.stop();
          await _dictate(_kind(data));
          return null;
        } finally {
          _captureStarting = false;
        }
      case 'stopDictation':
        await _stopDictation();
        return null;
      case 'pickFile':
        await _welcome.stop();
        return _openDocuments(_kind(data));
      case 'account':
        await _welcome.stop();
        await _account();
        return null;
      case 'billing':
        await _openBilling();
        return null;
      case 'report':
        return _report(_text(data, 'text', max: 20000));
      default:
        throw const BrainApiException('This app action is not supported.');
    }
  }

  Future<bool> _saveProjectionPlace(String text, bool fromVoice) async {
    if (_disposed || !mounted || widget.auth.session == null) return false;
    final revision = widget.auth.revision;
    // Speaking an explicit place-save command is the confirmation. A typed
    // place note uses the existing review-before-save interaction.
    if (!fromVoice) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save this place in My Brain?'),
          content: SingleChildScrollView(child: Text(text)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save place note'),
            ),
          ],
        ),
      );
      if (approved != true) return false;
    }
    if (_disposed || !mounted || revision != widget.auth.revision) return false;
    final snapshot = await _repository.saveMemory(
      text,
      fromVoice ? 'voice' : 'projection',
    );
    _emit({'type': 'brainSnapshot', 'snapshot': snapshot});
    return true;
  }

  Future<Map<String, dynamic>> _projectionRequest(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    if (path != '/api/brain-projection/answer') {
      return _api.json(method, path, body);
    }
    // Sourced reasoning has the same longer budget as Deep Think. Stop stays
    // local and can invalidate its result while the request is outstanding.
    final response = await _api.send(
      method,
      path,
      body: body,
      timeout: const Duration(seconds: 175),
    );
    try {
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const BrainApiException(
        'The place answer could not be read. Please try again.',
      );
    }
  }

  String _kind(Map<String, dynamic> data) {
    final kind = data['kind'];
    if (kind != 'memory' && kind != 'training') {
      throw const BrainApiException('Choose memory or training.');
    }
    return kind as String;
  }

  Future<bool> _consent(
    String feature,
    Set<KorlixThirdPartyAiDataCategory> categories,
  ) => KorlixThirdPartyAiConsent.ensure(
    context: context,
    featureName: feature,
    providers: {KorlixThirdPartyAiProvider.openAi},
    dataCategories: categories,
  );

  Future<void> _dictate(String kind) async {
    if (_dictating) {
      await _stopDictation();
      return;
    }
    await _voice.stop(reason: 'dictation_started');
    if (!mounted || _disposed) return;
    final available = await _speech.initialize(
      onError: (_) {
        _dictating = false;
        _emit({
          'type': 'dictationStatus',
          'active': false,
          'message': 'Dictation stopped. Check microphone and speech permissions, or type instead.',
        });
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _dictating = false;
          _emit({
            'type': 'dictationStatus',
            'active': false,
            'message': 'Dictation stopped. Review your text before saving.',
          });
        }
      },
    );
    if (!available) {
      throw const BrainApiException(
        'Enable microphone and speech recognition in your device settings, or type instead.',
      );
    }
    if (!mounted || _disposed) return;
    _dictating = true;
    await _speech.listen(
      onResult: (result) => _emit({
        'type': 'dictation',
        'kind': kind,
        'text': result.recognizedWords,
        'final': result.finalResult,
      }),
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 5),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
    );
    _emit({
      'type': 'dictationStatus',
      'active': _dictating,
      'message': 'Listening… tap Stop dictation when finished.',
    });
  }

  Future<void> _stopDictation() async {
    final wasDictating = _dictating;
    _dictating = false;
    await _speech.stop();
    if (wasDictating) {
      _emit({
        'type': 'dictationStatus',
        'active': false,
        'message': 'Dictation stopped. Review your text before saving.',
      });
    }
  }

  Future<void> _pauseForFeature() async {
    ++_voiceStartRequest;
    _captureStarting = false;
    await _welcome.stop();
    await _stopDictation();
    if (_voice.active) await _voice.pause();
  }

  Future<Map<String, dynamic>> _openDocuments(String kind) async {
    if (_pickerBusy) throw const BrainApiException('Finish the open tool first.');
    _pickerBusy = true;
    final revision = widget.auth.revision;
    try {
      await _pauseForFeature();
      if (!mounted || _disposed || revision != widget.auth.revision) return {'canceled':true};
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BrainDocumentScreen(
        repository: _repository,
        initialDestination: kind == 'memory' ? BrainDocumentDestination.memory
            : kind == 'training' ? BrainDocumentDestination.training : BrainDocumentDestination.both,
        requestConsent: () => _consent('Analyze a Brain document', {
          KorlixThirdPartyAiDataCategory.filesAndDocuments,
          KorlixThirdPartyAiDataCategory.agentTrainingAndMemory,
        }),
        onSaved: (snapshot) => _emit({'type':'brainSnapshot','snapshot':snapshot}),
      )));
      return {'imported':true};
    } finally { _pickerBusy = false; }
  }

  Future<Object?> _openCameraAsk() async {
    if (_pickerBusy) throw const BrainApiException('Finish the open tool first.');
    _pickerBusy = true;
    final revision = widget.auth.revision;
    try {
      await _pauseForFeature();
      if (!mounted || _disposed || revision != widget.auth.revision) return null;
      final client = BrainCameraAskClient(_api);
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BrainCameraAskScreen(
        client: client,
        ensureConsent: (context) => KorlixThirdPartyAiConsent.ensure(
          context: context, featureName: 'Camera Ask',
          providers: {KorlixThirdPartyAiProvider.openAi},
          dataCategories: {KorlixThirdPartyAiDataCategory.imagesAndPhotos,
            KorlixThirdPartyAiDataCategory.typedTextAndPrompts},
        ),
      )));
      return null;
    } finally { _pickerBusy = false; }
  }

  Future<void> _openDirections(String query) async {
    if (_pickerBusy || !mounted || _disposed || widget.auth.session == null) return;
    _pickerBusy = true;
    final revision = widget.auth.revision;
    try {
      await _pauseForFeature();
      if (!mounted || _disposed || revision != widget.auth.revision) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BrainDirectionsScreen(
        api: _api, initialDestination: query, beforeOpen: _pauseForFeature,
      )));
    } finally { _pickerBusy = false; }
  }

  Future<Map<String, dynamic>> _report(String text) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Report Rici’s response'),
        children: [
          for (final reason in [
            'Offensive or hateful',
            'Unsafe or harmful',
            'Sexual content',
            'Incorrect or misleading',
            'Other',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, reason),
              child: Text(reason),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (reason == null) return {'submitted': false};
    final response = await _api.json('POST', '/api/report-output', {
      'contentType': 'text',
      'appArea': 'korlix_brain_voice',
      'reason': reason,
      'details': '',
      'outputSummary': text.length > 2500 ? text.substring(0, 2500) : text,
      'prompt': '',
      'platform': widget.auth.platform,
    });
    if (response['ok'] != true || response['reportId'] is! String) {
      throw const BrainApiException(
        'We could not confirm that the report was received. Please contact support@korlixdeveloper.com before sending it again.',
      );
    }
    return {'submitted': true};
  }

  Future<void> _account() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('KORLIX Brain+Voice'),
              subtitle: Text(
                '${widget.auth.session?.email ?? 'Your account'}\n'
                '${appBuildName == null ? 'Version information unavailable' : 'Version $appBuildName'}'
                '${appBuildNumber == null ? '' : ' · Build $appBuildNumber'}',
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Memory and behaviors are shared with your KORLIX general voice agent. Changes apply across your KORLIX apps.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.bolt),
              title: const Text('Plan & AI GAS'),
              subtitle: const Text('Live minutes, top-ups and store purchases'),
              onTap: () => Navigator.pop(context, 'billing'),
            ),
            ListTile(
              title: const Text('Privacy policy'),
              onTap: () => Navigator.pop(context, 'privacy'),
            ),
            ListTile(
              title: const Text('Terms'),
              onTap: () => Navigator.pop(context, 'terms'),
            ),
            ListTile(
              title: const Text('Contact support'),
              onTap: () => Navigator.pop(context, 'support'),
            ),
            ListTile(
              title: const Text('Sign out'),
              onTap: () => Navigator.pop(context, 'signout'),
            ),
            ListTile(
              title: const Text('Request account deletion'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'billing') {
      await _openBilling();
    } else if (action == 'signout') {
      await _voice.stop(reason: 'account_changed');
      await _stopDictation();
      await widget.auth.signOut();
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete your shared KORLIX account?'),
          content: const Text(
            'This requests deletion of your account and data across KORLIX apps, including AI, Messenger and Brain+Voice. It is not limited to this app. Store subscriptions must also be canceled in Apple or Google settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Request deletion'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await _transcriptStore.clear();
        await widget.auth.requestAccountDeletion();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your account deletion request was submitted.'),
            ),
          );
        }
      }
    } else if (action != null) {
      final url = switch (action) {
        'privacy' => 'https://www.korlixdeveloper.com/privacy-policy.html',
        'terms' => 'https://www.korlixdeveloper.com/terms.html',
        _ => 'mailto:support@korlixdeveloper.com',
      };
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _projection.dispose();
    _billing.dispose();
    unawaited(_welcome.dispose().catchError((Object _) {}));
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_speech.cancel());
    unawaited(_voice.stop(reason: 'workspace_disposed').whenComplete(_api.dispose));
    super.dispose();
  }

  Future<void> _openBilling() async {
    ++_voiceStartRequest;
    _captureStarting = false;
    await _welcome.stop();
    await _stopDictation();
    await _voice.stop(reason: 'billing_opened');
    if (!mounted || _disposed) return;
    unawaited(_billing.refresh());
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BrainBillingScreen(billing: _billing),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_projection.isOpen,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _projection.isOpen) _projection.close();
    },
    child: Scaffold(
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: _projection.isOpen,
              child: _pageError == null
                  ? WebViewWidget(controller: _web)
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_pageError!),
                          FilledButton(
                            onPressed: () {
                              setState(() => _pageError = null);
                              unawaited(
                                _web.loadFlutterAsset('assets/web/index.html'),
                              );
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
            ),
            if (_projection.isOpen)
              Positioned.fill(
                child: BrainProjectionScreen(projection: _projection),
              ),
          ],
        ),
      ),
    ),
  );
}
