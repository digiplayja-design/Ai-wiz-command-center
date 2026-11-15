import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_controller.dart';
import 'models.dart';
import 'services/korlix_api.dart';
import 'services/purchases.dart';
import 'services/vanity_sync.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final results = await Future.wait([
      rootBundle.loadString('assets/catalog.json'),
      rootBundle.loadString('assets/service-config.json'),
    ]);
    final local = PreferenceStore(await SharedPreferences.getInstance());
    final api = KorlixApi(
      config: ServiceConfig.fromJson(object(jsonDecode(results[1]))),
      secureStorage: SecureSessionStore(),
      localStorage: local,
      platform: Platform.isIOS
          ? 'ios'
          : Platform.isAndroid
          ? 'android'
          : 'unsupported',
    );
    final controller = EshaController(
      catalog: Catalog.fromJson(object(jsonDecode(results[0]))),
      api: api,
      sync: VanitySync(gateway: api, storage: local),
      purchases: EshaPurchases(api),
    );
    runApp(EshaApp(controller: controller));
    await controller.initialize();
  } catch (_) {
    runApp(
      MaterialApp(
        theme: eshaTheme,
        home: const Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'Esha could not load its app settings. Please close and reopen the app. Your saved account collection has not been changed.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
