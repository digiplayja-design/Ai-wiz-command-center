import 'dart:async';

import 'package:ai_wiz_command_center/ads/korlix_ad_consent.dart';
import 'package:flutter_test/flutter_test.dart';

class _ConsentGateway implements KorlixAdConsentGateway {
  final List<String> calls = [];
  bool allowed = false;
  bool privacyRequired = false;
  bool updateFails = false;
  bool permissionFails = false;
  bool privacyRequirementFails = false;
  bool initializationFails = false;
  bool formFails = false;
  bool privacyFormFails = false;
  Completer<void>? update;
  Completer<void>? form;
  Completer<void>? privacyForm;

  @override
  Future<void> requestConsentInfoUpdate() async {
    calls.add('update');
    if (updateFails) throw StateError('update unavailable');
    await update?.future;
  }

  @override
  Future<void> loadAndShowConsentFormIfRequired() async {
    calls.add('consent form');
    if (formFails) throw StateError('form unavailable');
    await form?.future;
  }

  @override
  Future<bool> canRequestAds() async {
    calls.add('permission');
    if (permissionFails) throw StateError('permission unavailable');
    return allowed;
  }

  @override
  Future<bool> isPrivacyOptionsRequired() async {
    calls.add('privacy requirement');
    if (privacyRequirementFails) throw StateError('requirement unavailable');
    return privacyRequired;
  }

  @override
  Future<void> showPrivacyOptionsForm() async {
    calls.add('privacy form');
    if (privacyFormFails) throw StateError('privacy form unavailable');
    await privacyForm?.future;
  }

  @override
  Future<void> initializeAds() async {
    calls.add('initialize');
    if (initializationFails) throw StateError('SDK unavailable');
  }
}

void main() {
  late _ConsentGateway gateway;
  late KorlixAdConsent consent;

  setUp(() {
    gateway = _ConsentGateway();
    consent = KorlixAdConsent(
      gateway: gateway,
      supported: true,
      requestTimeout: const Duration(seconds: 1),
    );
  });

  tearDown(() => consent.dispose());

  test('unsupported platforms never invoke consent or the ads SDK', () async {
    final unsupported = KorlixAdConsent(gateway: gateway, supported: false);
    addTearDown(unsupported.dispose);
    expect(await unsupported.prepareAds(), isFalse);
    expect(await unsupported.showPrivacyOptions(), isFalse);
    expect(unsupported.privacyOptionsRequired, isFalse);
    expect(gateway.calls, isEmpty);
  });

  test('unknown or declined authorization never initializes ads', () async {
    expect(await consent.prepareAds(), isFalse);
    expect(gateway.calls.take(3), ['update', 'consent form', 'permission']);
    expect(gateway.calls, isNot(contains('initialize')));
  });

  test(
    'concurrent banners share update, required form and SDK startup',
    () async {
      gateway.allowed = true;
      final ready = await Future.wait([
        consent.prepareAds(),
        consent.prepareAds(),
        consent.prepareAds(),
      ]);
      expect(ready, everyElement(isTrue));
      for (final call in ['update', 'consent form', 'initialize']) {
        expect(gateway.calls.where((value) => value == call), hasLength(1));
      }
      expect(
        gateway.calls.indexOf('initialize'),
        greaterThan(gateway.calls.indexOf('permission')),
      );
    },
  );

  test('each new app session requests updated information', () async {
    await consent.prepareAds();
    final nextSession = KorlixAdConsent(gateway: gateway, supported: true);
    addTearDown(nextSession.dispose);
    await nextSession.prepareAds();
    expect(gateway.calls.where((value) => value == 'update'), hasLength(2));
  });

  test('each later ad request rechecks UMP authorization', () async {
    gateway.allowed = true;
    expect(await consent.prepareAds(), isTrue);
    gateway.allowed = false;
    expect(await consent.prepareAds(), isFalse);
    expect(consent.adsReady, isFalse);
  });

  test('update error fails closed unless UMP permits stored consent', () async {
    gateway.updateFails = true;
    expect(await consent.prepareAds(), isFalse);
    expect(gateway.calls, isNot(contains('consent form')));
    expect(gateway.calls, isNot(contains('initialize')));
    gateway.allowed = true;
    expect(await consent.prepareAds(), isTrue);
  });

  test('required form error still delegates authorization to UMP', () async {
    gateway.formFails = true;
    gateway.allowed = true;
    expect(await consent.prepareAds(), isTrue);
  });

  test('permission read failure cannot reuse previous authorization', () async {
    gateway.allowed = true;
    expect(await consent.prepareAds(), isTrue);
    gateway.permissionFails = true;
    expect(await consent.prepareAds(), isFalse);
  });

  testWidgets('slow update is bounded and its late result cannot open a form', (
    tester,
  ) async {
    gateway.update = Completer<void>();
    bool? ready;
    final preparing = consent.prepareAds().then((value) => ready = value);
    await tester.pump(const Duration(seconds: 2));
    await preparing;
    expect(ready, isFalse);
    gateway.update!.complete();
    await tester.pump();
    expect(gateway.calls, isNot(contains('consent form')));
    expect(gateway.calls, isNot(contains('initialize')));
  });

  testWidgets('a pending user decision is never timed out', (tester) async {
    gateway.allowed = true;
    gateway.form = Completer<void>();
    bool completed = false;
    final preparing = consent.prepareAds().then((_) => completed = true);
    await tester.pump();
    await tester.pump(const Duration(minutes: 5));
    expect(completed, isFalse);
    expect(gateway.calls, isNot(contains('initialize')));
    gateway.form!.complete();
    await tester.pump();
    await preparing;
    expect(consent.adsReady, isTrue);
  });

  test(
    'privacy options revoke existing readiness and publish the new choice',
    () async {
      gateway.allowed = true;
      gateway.privacyRequired = true;
      gateway.privacyForm = Completer<void>();
      await consent.prepareAds();
      final readinessChanges = <bool>[];
      consent.addListener(() => readinessChanges.add(consent.adsReady));
      final showing = consent.showPrivacyOptions();
      expect(consent.adsReady, isFalse);
      expect(consent.privacyOptionsShowing, isTrue);
      final duplicate = consent.showPrivacyOptions();
      gateway.allowed = false;
      gateway.privacyForm!.complete();
      expect(await showing, isTrue);
      expect(await duplicate, isTrue);
      expect(consent.adsReady, isFalse);
      expect(consent.privacyOptionsShowing, isFalse);
      expect(readinessChanges, isNotEmpty);
      expect(readinessChanges, everyElement(isFalse));
      expect(
        gateway.calls.where((value) => value == 'privacy form'),
        hasLength(1),
      );
      expect(
        gateway.calls.where((value) => value == 'initialize'),
        hasLength(1),
      );
    },
  );

  test(
    'required privacy entry survives transient requirement read failures',
    () async {
      gateway.privacyRequired = true;
      await consent.prepareAds();
      expect(consent.privacyOptionsRequired, isTrue);
      gateway.privacyRequirementFails = true;
      await consent.prepareAds();
      expect(consent.privacyOptionsRequired, isTrue);
    },
  );

  test(
    'privacy errors return a safe failure and recheck current permission',
    () async {
      gateway.allowed = true;
      gateway.privacyRequired = true;
      await consent.prepareAds();
      gateway.privacyFormFails = true;
      gateway.allowed = false;
      expect(await consent.showPrivacyOptions(), isFalse);
      expect(consent.adsReady, isFalse);
      expect(consent.privacyOptionsShowing, isFalse);
    },
  );

  test('SDK failure stays closed and is not initialized repeatedly', () async {
    gateway.allowed = true;
    gateway.initializationFails = true;
    expect(await consent.prepareAds(), isFalse);
    expect(await consent.prepareAds(), isFalse);
    expect(gateway.calls.where((value) => value == 'initialize'), hasLength(1));
  });
}
