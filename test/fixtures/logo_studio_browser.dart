import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/imagine_studio/imagine_client.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_client.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_model.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_render.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_screen.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

// Runs the production screen and real file exports with in-memory projects and
// a local image fixture. No login, real API request, or credit consumption.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final store = _Store();
  final client = LogoClient(
    headers: const {'Authorization': 'logo-browser-fixture'},
    store: store,
    images: ImagineClient(
      baseUrl: 'https://fixture.invalid',
      headersBuilder: () => {'Authorization': 'logo-browser-fixture'},
      store: store,
      client: MockClient((request) async {
        if (request.url.path == '/api/logo/jobs') {
          return http.Response(
            jsonEncode({
              'jobId': 'logo_fixture',
              'status': 'processing',
              'stage': 'planning',
            }),
            202,
          );
        }
        if (request.url.path != '/api/logo/jobs/logo_fixture') {
          throw StateError('Unexpected request');
        }
        final png = await logoPng(
          const LogoDesign(name: 'Poppy & Pine', mark: 'Leaf'),
          width: 512,
          height: 512,
        );
        return http.Response(
          jsonEncode({
            'jobId': 'logo_fixture',
            'status': 'completed',
            'stage': 'completed',
            'result': {
              'imageDataUrl': 'data:image/png;base64,${base64Encode(png)}',
              'generationId': 'fixture-concept',
            },
          }),
          200,
        );
      }),
    ),
  );
  runApp(
    MaterialApp(
      theme: korlixBuildTheme(
        Uri.base.queryParameters['theme'] ?? 'korlix_blue',
      ),
      home: LogoStudioScreen(client: client, ensureConsent: () async => true),
    ),
  );
}

class _Store implements ImagineRecipeStore {
  final data = <String, List<String>>{};
  @override
  Future<List<String>> read(String key) async => data[key] ?? [];
  @override
  Future<void> write(String key, List<String> value) async {
    data[key] = value;
  }
}
