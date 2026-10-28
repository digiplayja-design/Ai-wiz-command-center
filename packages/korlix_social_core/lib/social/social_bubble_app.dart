import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/korlix_token_store.dart';
import '../theme/korlix_theme.dart';
import 'social_client.dart';
import 'social_appearance.dart';
import 'social_floating_chat.dart';
import 'social_native_bridge.dart';
import 'social_push_platform.dart';
import 'social_screen.dart';

const _bubbleBackend = String.fromEnvironment(
  'AI_WIZARD_BACKEND_URL',
  defaultValue: 'https://chee-chai-chee-backend.onrender.com',
);

/// Runs in BubbleActivity's separate engine. Do not initialize the main app,
/// register its alerts, rotate refresh tokens, or start any call/audio service.
void runSocialBubble({bool messengerMode = false}) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SocialBubbleApp(messengerMode: messengerMode));
}

class SocialBubbleSession extends ChangeNotifier {
  SocialBubbleSession({
    required this.owner,
    this.deviceHeaders = const {},
    Future<KorlixStoredTokens?> Function()? readTokens,
    DateTime Function()? now,
  }) : _readTokens = readTokens ?? KorlixTokenStore.instance.readOnly,
       _now = now ?? DateTime.now;

  final String owner;
  final Map<String, String> deviceHeaders;
  final Future<KorlixStoredTokens?> Function() _readTokens;
  final DateTime Function() _now;
  String _token = '', _session = '';
  bool _invalid = false;
  bool get valid => !_invalid;
  Map<String, String> get headers => _invalid || _token.isEmpty
      ? {}
      : {...deviceHeaders, 'Authorization': 'Bearer $_token'};

  void invalidate() {
    if (_invalid) return;
    _invalid = true;
    _token = '';
    notifyListeners();
  }

  Never _deny() {
    invalidate();
    throw const SocialException(
      'Open KORLIX to sign in, then reopen this floating chat.',
      401,
    );
  }

  /// JWT checks here only prevent stale local routing; the backend remains
  /// responsible for signature verification and conversation authorization.
  Future<String> authorize() async {
    if (_invalid) _deny();
    KorlixStoredTokens? tokens;
    try {
      tokens = await _readTokens();
    } catch (_) {
      _deny();
    }
    if (_invalid || tokens == null) _deny();
    final token = tokens.accessToken;
    SocialMap payload;
    try {
      final parts = token.split('.');
      if (parts.length != 3) _deny();
      payload = socialMap(
        jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        ),
      );
    } catch (_) {
      _deny();
    }
    final session = payload['session_id'], expiry = payload['exp'];
    if (session is! String ||
        session.isEmpty ||
        expiry is! num ||
        !expiry.isFinite ||
        expiry <= _now().millisecondsSinceEpoch / 1000 ||
        socialPushOwner({'Authorization': 'Bearer $token'}) != owner ||
        (_session.isNotEmpty && _session != session)) {
      _deny();
    }
    if (_invalid) _deny();
    _session = session;
    _token = token;
    return token;
  }
}

/// No request can reuse credentials captured when the activity was launched.
/// Also recheck after reading the response, so logout cannot reveal late data.
class SocialBubbleHttpClient extends http.BaseClient {
  SocialBubbleHttpClient({
    required this.session,
    required String baseUrl,
    http.Client? inner,
  }) : _origin = Uri.parse(baseUrl),
       _inner = inner ?? http.Client();

  final SocialBubbleSession session;
  final Uri _origin;
  final http.Client _inner;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed ||
        request.url.origin != _origin.origin ||
        !request.url.path.startsWith('/api/social/')) {
      throw const SocialException('This floating chat is unavailable.', 401);
    }
    final token = await session.authorize();
    if (_closed) {
      throw const SocialException('This floating chat is closed.', 401);
    }
    for (final key in request.headers.keys.toList(growable: false)) {
      if (key.toLowerCase() == 'authorization') request.headers.remove(key);
    }
    request.headers.addAll(session.deviceHeaders);
    request.headers['Authorization'] = 'Bearer $token';
    // A redirect must never move this credential outside the checked endpoint.
    request.followRedirects = false;
    final response = await _inner.send(request);
    final bytes = await response.stream.toBytes();
    if (_closed) {
      throw const SocialException('This floating chat is closed.', 401);
    }
    await session.authorize();
    if (response.statusCode == 401) session.invalidate();
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      headers: response.headers,
      contentLength: bytes.length,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _inner.close();
    super.close();
  }
}

class SocialBubbleApp extends StatefulWidget {
  const SocialBubbleApp({super.key, this.messengerMode = false});
  final bool messengerMode;

  @override
  State<SocialBubbleApp> createState() => _SocialBubbleAppState();
}

class _SocialBubbleAppState extends State<SocialBubbleApp>
    with WidgetsBindingObserver {
  SocialFloatingTarget? _target;
  SocialBubbleSession? _session;
  SocialBubbleHttpClient? _transport;
  SocialClient? _client;
  SocialMap? _profile;
  String? _error;
  int _revision = 0;
  bool _foreground = true, _checking = false;
  Timer? _check;
  StreamSubscription<SocialMap>? _events;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _events = SocialNativeBridge.events.listen((event) {
      if (event['type'] == 'closed' || event['type'] == 'ownerChanged') {
        _session?.invalidate();
        if (_session == null && mounted) {
          setState(() => _error = 'Open KORLIX to reopen this conversation.');
        }
      } else if (event['type'] == 'open') {
        unawaited(_open(SocialFloatingTarget.parse(event)));
      }
    });
    unawaited(_launch());
    _check = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_foreground) unawaited(_validateSession());
    });
  }

  Future<void> _launch() async {
    final target = await SocialFloatingChat.launchTarget();
    if (mounted) await _open(target);
  }

  Future<void> _validateSession() async {
    final session = _session;
    if (_checking || session == null || !session.valid) return;
    _checking = true;
    try {
      await session.authorize();
    } catch (_) {
      // The session listener clears the conversation before exposing an error.
    } finally {
      _checking = false;
    }
  }

  void _sessionChanged() {
    if (_session?.valid != false || !mounted) return;
    _client?.invalidateSession();
    setState(() {
      _profile = null;
      _error = 'Open KORLIX to sign in, then reopen this floating chat.';
    });
  }

  Future<void> _open(SocialFloatingTarget? target) async {
    final revision = ++_revision;
    _clearClient();
    setState(() {
      _target = target;
      _profile = null;
      _error = target == null
          ? 'Open KORLIX and choose a chat to keep floating.'
          : null;
    });
    if (target == null) return;
    final deviceHeaders = <String, String>{};
    if (widget.messengerMode) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        if (!mounted || revision != _revision) return;
        final deviceId = prefs.getString('korlix_messenger_device_id');
        if (deviceId == null || deviceId.isEmpty) {
          setState(
            () => _error =
                'Open Messenger and sign in before using a floating chat.',
          );
          return;
        }
        deviceHeaders.addAll({
          'X-Korlix-App': 'korlix_messenger',
          'X-Korlix-Device-Id': deviceId,
          'X-Korlix-Platform': 'android',
        });
      } catch (_) {
        if (mounted && revision == _revision) {
          setState(
            () => _error =
                'Open Messenger and sign in before using a floating chat.',
          );
        }
        return;
      }
    }
    final session = SocialBubbleSession(
      owner: target.owner,
      readTokens: widget.messengerMode
          ? KorlixTokenStore(namespace: 'korlix_messenger').readOnly
          : null,
      deviceHeaders: deviceHeaders,
    );
    _session = session;
    session.addListener(_sessionChanged);
    try {
      await session.authorize();
      if (!mounted || revision != _revision) return;
      final transport = SocialBubbleHttpClient(
        session: session,
        baseUrl: widget.messengerMode
            ? const String.fromEnvironment(
                'KORLIX_BACKEND_URL',
                defaultValue: _bubbleBackend,
              )
            : _bubbleBackend,
      );
      _transport = transport;
      final client = SocialClient(
        baseUrl: widget.messengerMode
            ? const String.fromEnvironment(
                'KORLIX_BACKEND_URL',
                defaultValue: _bubbleBackend,
              )
            : _bubbleBackend,
        headersBuilder: () => session.headers,
        sessionChanges: session,
        client: transport,
      );
      _client = client;
      final response = await client.get('bootstrap');
      if (!mounted || revision != _revision || !session.valid) return;
      final profile = socialMap(response['profile']);
      if (profile['id'] is! String || (profile['id'] as String).isEmpty) {
        setState(
          () => _error = 'Open KORLIX to finish setting up KORLIX Social.',
        );
        return;
      }
      setState(() => _profile = profile);
    } catch (error) {
      if (!mounted || revision != _revision) return;
      setState(
        () => _error = error is SocialException
            ? error.message
            : 'Open KORLIX to sign in and reopen this floating chat.',
      );
    }
  }

  void _clearClient() {
    _session?.removeListener(_sessionChanged);
    _client?.invalidateSession();
    _client?.dispose();
    _client = null;
    _transport?.close();
    _transport = null;
    _session?.invalidate();
    _session?.dispose();
    _session = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_validateSession());
  }

  @override
  void dispose() {
    _revision++;
    WidgetsBinding.instance.removeObserver(this);
    _check?.cancel();
    unawaited(_events?.cancel());
    _clearClient();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: korlixBuildTheme(
      widget.messengerMode ? messengerDefaultAppearance.themeId : 'korlix_blue',
    ),
    builder: (_, child) => SocialAppearance(
      defaultChoice: widget.messengerMode ? messengerDefaultAppearance : null,
      child: child!,
    ),
    home: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      key: const ValueKey('bubble-open-korlix'),
                      onPressed: () => SocialFloatingChat.openMain(_target),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Open full Messenger'),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('bubble-close'),
                    tooltip: 'Close floating chat',
                    onPressed: () {
                      _session?.invalidate();
                      unawaited(SocialFloatingChat.close());
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    )
                  : _profile == null || _client == null || _target == null
                  ? const Center(child: CircularProgressIndicator())
                  : SocialScreen(
                      key: ValueKey('floating-messenger:$_revision'),
                      client: _client!,
                      ownsClient: false,
                      messengerMode: widget.messengerMode,
                      bubbleMode: true,
                      initialConversation: {
                        'id': _target!.id,
                        'name': 'Conversation',
                      },
                      initialGroupChat: _target!.kind == 'group',
                      onOpenAccount: () => SocialFloatingChat.openMain(_target),
                      onOpenMain: (peer, group) => SocialFloatingChat.openMain(
                        SocialFloatingTarget(
                          owner: _target!.owner,
                          kind: group ? 'group' : 'peer',
                          id: '${peer['id']}',
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
