import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:korlix_receipt_core/privacy/korlix_third_party_ai_consent.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'brain_api.dart';
import 'brain_auth.dart';
import 'brain_repository.dart';
import 'brain_voice.dart';

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
  late final WebViewController _web;
  final _speech = SpeechToText();
  final _inFlight = <String>{};
  bool _disposed = false, _pickerBusy = false, _dictating = false;
  String? _pageError;
  int _voiceIntent = 0, _dictationGeneration = 0;
  bool _voiceStarting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = BrainApi(widget.auth);
    _repository = BrainRepository(_api);
    _voice = BrainVoice(_api, _emit);
    _web = WebViewController()
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
            return uri?.scheme == 'file' &&
                    uri!.path.endsWith('/flutter_assets/assets/web/index.html')
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
      )
      ..loadFlutterAsset('assets/web/index.html');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _voiceIntent++;
      _emit({'type': 'background'});
      unawaited(_stopDictation());
      // This first native build intentionally ends the microphone when the app
      // backgrounds until platform call/foreground-service integration is tested.
      unawaited(
        _voice.stop(
          message: 'Conversation stopped while the app was in the background. Tap Start conversation to reconnect.',
        ),
      );
    }
  }

  void _emit(Map<String, dynamic> event) {
    if (_disposed || !mounted) return;
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
      if (_inFlight.length > 12) {
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
          'error': error is BrainApiException || error is BrainAuthException
              ? error.toString()
              : 'Could not complete this action. Check your connection and try again.',
        });
      }
    } finally {
      if (id != null) _inFlight.remove(id);
    }
  }

  Future<Object?> _dispatch(String action, Map<String, dynamic> data) async {
    if (widget.auth.session == null) {
      throw const BrainApiException('Please sign in again.');
    }
    switch (action) {
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
        if (_voiceStarting) return {'canceled': true};
        if (_voice.active) return null;
        final intent = ++_voiceIntent;
        _voiceStarting = true;
        try {
          await _stopDictation();
          if (!mounted ||
              !await _consent('Talk to Rici', {
                KorlixThirdPartyAiDataCategory.voiceAudioAndTranscripts,
                KorlixThirdPartyAiDataCategory.agentTrainingAndMemory,
              }) ||
              !mounted ||
              intent != _voiceIntent) {
            return {'canceled': true};
          }
          await _voice.start();
          return null;
        } finally {
          _voiceStarting = false;
        }
      case 'stopVoice':
        _voiceIntent++;
        await _voice.stop();
        return null;
      case 'dictate':
        await _dictate(_kind(data));
        return null;
      case 'stopDictation':
        await _stopDictation();
        return null;
      case 'pickFile':
        return _pickFile(_kind(data));
      case 'account':
        await _account();
        return null;
      case 'report':
        return _report(_text(data, 'text', max: 20000));
      default:
        throw const BrainApiException('This app action is not supported.');
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
    await _voice.stop();
    final generation = ++_dictationGeneration;
    if (!mounted || _disposed) return;
    final available = await _speech.initialize(
      onError: (_) {
        if (_disposed || generation != _dictationGeneration) return;
        _dictating = false;
        _emit({
          'type': 'dictationStatus',
          'message': 'Dictation stopped. Check microphone and speech permissions, or type instead.',
        });
      },
      onStatus: (status) {
        if (_disposed || generation != _dictationGeneration) return;
        if (status == 'done' || status == 'notListening') {
          _dictating = false;
          _emit({
            'type': 'dictationStatus',
            'status': 'notListening',
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
    if (!mounted || _disposed || generation != _dictationGeneration) return;
    _dictating = true;
    await _speech.listen(
      onResult: (result) {
        if (_disposed || generation != _dictationGeneration) return;
        _emit({
          'type': 'dictation',
          'kind': kind,
          'text': result.recognizedWords,
          'final': result.finalResult,
        });
      },
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
      'message': 'Listening… tap Stop dictation when finished.',
    });
  }

  Future<void> _stopDictation() async {
    _dictationGeneration++;
    _dictating = false;
    await _speech.cancel();
  }

  Future<Map<String, dynamic>> _pickFile(String kind) async {
    if (_pickerBusy) {
      throw const BrainApiException(
        'Please finish the current file import first.',
      );
    }
    _pickerBusy = true;
    final revision = widget.auth.revision;
    try {
      await _stopDictation();
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'txt',
          'md',
          'doc',
          'docx',
          'csv',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'rtf',
          'png',
          'jpg',
          'jpeg',
          'webp',
        ],
        allowMultiple: false,
        withData: true,
      );
      if (result == null) return {'canceled': true};
      if (!mounted || revision != widget.auth.revision) {
        throw const BrainApiException(
          'Your account changed. Choose the file again.',
        );
      }
      final file = result.files.single;
      if (file.size > 10 * 1024 * 1024 ||
          file.bytes == null ||
          file.bytes!.isEmpty) {
        throw const BrainApiException(
          'Choose a nonempty document smaller than 10 MB.',
        );
      }
      if (!await _consent('Analyze a Brain document', {
        KorlixThirdPartyAiDataCategory.filesAndDocuments,
        KorlixThirdPartyAiDataCategory.agentTrainingAndMemory,
      })) {
        return {'canceled': true};
      }
      if (!mounted || revision != widget.auth.revision) {
        throw const BrainApiException('Your account changed.');
      }
      final analysis = await _api.analyze(kind, file.name, file.bytes!);
      if (!mounted) return {'canceled': true};
      String text;
      if (kind == 'training') {
        text = analysis['trainingDraft']?.toString() ?? '';
      } else {
        final suggestions = (analysis['suggestions'] as List? ?? [])
            .whereType<Map>()
            .map((m) => m['content']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
        if (suggestions.isEmpty) {
          throw const BrainApiException(
            'No durable memories were found. Try another file or type a memory.',
          );
        }
        final selected = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Choose a memory to review'),
            children: [
              for (final suggestion in suggestions)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, suggestion),
                  child: Text(suggestion),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
        if (selected == null) return {'canceled': true};
        text = selected;
      }
      if (text.trim().isEmpty) {
        throw const BrainApiException(
          'No draft was returned. Try another document.',
        );
      }
      return {'text': text, 'filename': file.name};
    } finally {
      _pickerBusy = false;
    }
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
    _voiceIntent++;
    await _voice.stop();
    await _stopDictation();
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('KORLIX Brain'),
              subtitle: Text(
                '${widget.auth.session?.email ?? 'Your account'}\nVersion 1.0.0 · Build 1',
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Memory and behaviors are shared with your KORLIX general voice agent. Changes apply across your KORLIX apps.',
              ),
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
    if (action == 'signout') {
      await _voice.stop();
      await _stopDictation();
      await widget.auth.signOut();
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete your shared KORLIX account?'),
          content: const Text(
            'This requests deletion of your account and data across KORLIX apps, including AI, Messenger and Brain. It is not limited to this app. Store subscriptions must also be canceled in Apple or Google settings.',
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
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_speech.cancel());
    unawaited(_voice.stop().whenComplete(_api.dispose));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _emit({'type': 'back'});
    },
    child: Scaffold(
      body: SafeArea(
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
    ),
  );
}
