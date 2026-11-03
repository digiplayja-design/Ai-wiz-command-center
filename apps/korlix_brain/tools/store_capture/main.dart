// Screenshot-only entry point. Never use this target for an uploaded app.
// The production BrainApp and BrainWorkspace widgets/assets are unchanged.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:korlix_receipt_core/auth/korlix_session_refresh.dart';

import '../../lib/brain_app.dart';
import '../../lib/brain_auth.dart';

const _capturePort = 18082;
const _agentPath = '/api/live-convo/agents/general';
final _observed = <String>{};

String _fixtureToken() {
  String part(Map<String, Object> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  // Deliberately unsigned and valid only in the in-process localhost fixture.
  return '${part({'alg': 'none', 'typ': 'JWT'})}.'
      '${part({
        'iss': 'https://store-capture.invalid',
        'sub': '00000000-0000-4000-8000-000000000001',
        'session_id': '00000000-0000-4000-8000-000000000002',
        'exp': 4102444800,
      })}.offline-fixture';
}

class _CaptureAuth extends BrainAuthController {
  _CaptureAuth() : super(backendUrl: 'http://localhost:$_capturePort');

  @override
  Future<void> initialize() async {
    if (ready) return;
    session = KorlixAuthSession(
      accessToken: _fixtureToken(),
      email: 'preview@example.invalid',
    );
    ready = true;
    notifyListeners();
  }

  @override
  Future<void> resume() async {}
}

Future<void> _respond(HttpRequest request) async {
  final path = request.uri.path;
  Object payload;
  if (request.method != 'GET') {
    request.response.statusCode = HttpStatus.methodNotAllowed;
    payload = {'error': 'The store capture fixture is read-only.'};
  } else if (path == _agentPath) {
    _observed.add(path);
    payload = {
      'agent': {
        'name': 'Rici',
        'trainingInstructions': '',
        'persistenceConfigured': true,
      },
    };
  } else if (path == '$_agentPath/memories') {
    _observed.add(path);
    payload = {'memories': <Object>[]};
  } else if (path == '/api/brain/billing/status') {
    // Do not query the App Store or suggest a verified purchase in a capture.
    payload = {'enabled': false, 'balance': null};
  } else {
    request.response.statusCode = HttpStatus.notFound;
    payload = {'error': 'No such screenshot fixture route.'};
  }
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(payload));
  await request.response.close();
  if (_observed.length == 2) {
    await File('${Directory.systemTemp.path}/brain-store-capture-ready.json')
        .writeAsString(jsonEncode({
          'renderer': 'production BrainApp / BrainWorkspace / WKWebView',
          'accountData': 'fictional, empty account',
          'network': 'localhost fixture only',
          'purchaseTesting': 'not performed',
        }));
  }
}

Future<void> main() async {
  if (!kDebugMode || !Platform.isIOS) {
    throw StateError('Store capture is restricted to debug iOS simulators.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _capturePort);
  server.listen(_respond);
  runApp(BrainApp(auth: _CaptureAuth()));
}
