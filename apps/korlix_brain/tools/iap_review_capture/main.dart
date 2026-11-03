// Isolated UI capture only. Never sign or upload this entry point.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../lib/brain_api.dart';
import '../../lib/brain_app.dart';
import '../../lib/brain_auth.dart';
import '../../lib/brain_billing.dart';
import '../../lib/brain_billing_screen.dart';

// These display fixtures match the user-approved USD App Store catalog.
// They are not StoreKit responses and are never used for a purchase.
class _CaptureBilling extends BrainBilling {
  _CaptureBilling()
    : super(
        BrainApi(BrainAuthController(backendUrl: 'http://localhost:18082')),
        platform: TargetPlatform.iOS,
      ) {
    enabled = true;
    final catalog = [
      ProductDetails(
        id: monthly,
        title: 'Brain+Voice Monthly',
        description: 'One month with 60 Live Conversation minutes.',
        price: r'$34.99',
        rawPrice: 34.99,
        currencyCode: 'USD',
      ),
      for (final entry in [(1, 30.0), (2, 55.0), (3, 80.0)])
        ProductDetails(
          id: gas(entry.$1),
          title: '${entry.$1 * 60} extra minutes',
          description: 'One-time AI GAS top-up.',
          price: '\$${entry.$2.toStringAsFixed(2)}',
          rawPrice: entry.$2,
          currencyCode: 'USD',
        ),
    ];
    products.addEntries(catalog.map((p) => MapEntry(p.id, p)));
  }

  Never _captureOnly() =>
      throw StateError('This isolated UI capture cannot transact or connect.');

  @override
  Future<void> initialize() async => _captureOnly();
  @override
  Future<void> refresh() async => _captureOnly();
  @override
  Future<void> buy(String id) async => _captureOnly();
  @override
  Future<void> restore() async => _captureOnly();
}

Future<void> _markReady(String stage) =>
    File('${Directory.systemTemp.path}/brain-iap-$stage-ready.json')
        .writeAsString(jsonEncode({
          'stage': stage,
          'screen': 'production BrainBillingScreen',
          'catalog': 'approved USD display fixtures',
          'transactions': 'not performed',
        }))
        .then((_) {});

Future<void> main() async {
  if (!kDebugMode || !Platform.isIOS) {
    throw StateError('Capture is restricted to debug iOS simulators.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  final navigator = GlobalKey<NavigatorState>();
  final screen = GlobalKey();
  final billing = _CaptureBilling();
  runApp(MaterialApp(
    title: 'KORLIX Brain+Voice',
    navigatorKey: navigator,
    debugShowCheckedModeBanner: false,
    // Exact production BrainApp theme; production source is unchanged.
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: brainPurple,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffa273ed),
        brightness: Brightness.dark,
        primary: brainGold,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
      useMaterial3: true,
    ),
    home: const Scaffold(body: SizedBox.shrink()),
  ));
  await WidgetsBinding.instance.endOfFrame;
  unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
    builder: (_) => BrainBillingScreen(key: screen, billing: billing),
  )));
  await Future<void>.delayed(const Duration(seconds: 2));
  await WidgetsBinding.instance.endOfFrame;
  await _markReady('top');

  // The runner requests an ordinary scroll after it has saved the first image.
  final next = File('${Directory.systemTemp.path}/brain-iap-scroll-next');
  Timer.periodic(const Duration(milliseconds: 500), (timer) async {
    if (!next.existsSync()) return;
    timer.cancel();
    ScrollableState? target;
    void visit(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        target ??= element.state as ScrollableState;
      }
      element.visitChildElements(visit);
    }
    visit(screen.currentContext! as Element);
    if (target == null) throw StateError('Billing scroll view was not found.');
    target!.position.jumpTo(target!.position.maxScrollExtent);
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(seconds: 1));
    await _markReady('bottom');
  });
}
