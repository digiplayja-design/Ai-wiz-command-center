import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:korlix_brain/brain_projection.dart';
import 'package:korlix_brain/brain_projection_screen.dart';
import 'package:webview_flutter/webview_flutter.dart';

Finder control(String action) => find.byKey(ValueKey('projection-native-$action'));

Future<Map<String, dynamic>> inspect(WebViewController web, String expression) async {
  Object? result = await web.runJavaScriptReturningResult('JSON.stringify($expression)');
  for (var index = 0; index < 3 && result is String; index++) {
    result = jsonDecode(result);
  }
  return Map<String, dynamic>.from(result as Map);
}

Future<void> until(WidgetTester tester, Future<bool> Function() condition,
    String description) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      if (await condition()) return;
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw TestFailure('$description did not complete. Last error: $lastError');
}

const geometry = r'''(() => {
  const input=document.getElementById('destination-input');
  const frame=document.querySelector('#map-container iframe');
  const rect=node=>{const r=node.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height};};
  return {layout:document.body.dataset.layout,nativeControls:document.body.dataset.nativeControls,
    window:[innerWidth,innerHeight],body:rect(document.body),shell:rect(document.querySelector('.projection-shell')),
    dockDisplay:getComputedStyle(document.querySelector('.voice-dock')).display,
    input:rect(input),inputFocused:document.activeElement===input,
    draft:input.value,selected:document.getElementById('place-label').textContent,
    frame:frame?rect(frame):null,
    identity:!window.runtimeIdentity?null:{input:input===window.runtimeIdentity.input,
      frame:frame===window.runtimeIdentity.frame,providerWindow:frame?.contentWindow===window.runtimeIdentity.providerWindow},
    phase:document.body.dataset.voice};
})()''';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('actual native Projection keeps controls, state and WKWebView through layout changes',
      (tester) async {
    // Only account/provider/voice responses are fixtures. The shipped native
    // screen, native orientation channel, WKWebView and bundled document run.
    // This does not exercise physical-device speech recognition or live maps.
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    late BrainProjection projection;
    WebViewController? controller;
    var webCreations = 0, starts = 0, pauses = 0, resumes = 0, stops = 0;
    var voiceEpoch = 0;
    Completer<void>? resumeGate;
    void phase(String value) => projection.receiveVoice({
      'type': 'voice', 'phase': value, 'paused': value == 'paused',
      'message': value == 'listening' ? 'Rici is listening' : value,
    });
    projection = BrainProjection(
      backendUrl: 'https://projection-fixture.invalid',
      request: (method, path, body) async {
        if (path.endsWith('/config')) {
          return {
            'rendererUrl': 'https://projection-fixture.invalid/brain-projection/earth.html',
            'mapAvailable': true, 'geocodingAvailable': true,
            'answersAvailable': false, 'directionsAvailable': false,
          };
        }
        return {'candidates': [{
          'id': 'native-runtime-place', 'label': 'Native runtime property',
          'address': '32 Pine Avenue, Example City',
          'latitude': 40.71, 'longitude': -74.0, 'provider': 'fixture',
        }]};
      },
      onOpen: () {}, onClose: () {}, onSave: (_, _) async => false,
      onStartVoice: () async { starts++; ++voiceEpoch; phase('listening'); },
      onPauseVoice: () async { pauses++; ++voiceEpoch; phase('paused'); },
      onResumeVoice: () async {
        resumes++;
        final epoch = ++voiceEpoch;
        phase('connecting');
        if (resumeGate != null) await resumeGate.future;
        if (epoch == voiceEpoch) phase('listening');
      },
      onStopVoice: () async { stops++; ++voiceEpoch; phase('complete'); },
    );
    addTearDown(projection.dispose);
    phase('listening');
    projection.open();
    await projection.search('32 Pine Avenue, Example City');
    projection.select('native-runtime-place');
    await tester.pumpWidget(MaterialApp(home: ListenableBuilder(
      listenable: projection,
      builder: (context, _) => projection.isOpen
          ? BrainProjectionScreen(
              key: const ValueKey('runtime-projection'),
              projection: projection,
              onWebViewCreated: (value) { controller = value; webCreations++; },
            )
          : const Scaffold(body: Center(child: Text('Returned to conversation'))),
    )));
    for (final name in ['back', 'pause', 'resume', 'stop']) {
      expect(control(name), findsOneWidget);
    }
    final web = controller!;
    final webElement = tester.element(find.byKey(const ValueKey('brain-projection-webview')));
    await until(tester, () async => (await inspect(web, geometry))['nativeControls'] == 'true',
        'The real bundled page/native bridge');
    expect(projection.snapshot['layoutPreference'], 'auto');
    if (Platform.isIOS) expect(find.byType(UiKitView), findsOneWidget);
    final platformElement = Platform.isIOS ? tester.element(find.byType(UiKitView)) : null;
    await web.runJavaScript(r'''
      const input=document.getElementById('destination-input');
      input.value='An unfinished native address';
      input.setSelectionRange(5,12);
      const frame=document.querySelector('#map-container iframe');
      window.runtimeIdentity={input,frame,providerWindow:frame?.contentWindow};
    ''');
    final observations = <String, Object?>{};
    binding.reportData ??= {};
    binding.reportData!['projectionRuntime'] = observations;
    observations['runtime'] = Platform.isIOS ? 'actual iOS WKWebView' : Platform.operatingSystem;
    observations['fixtureLimits'] = 'Native view and HTML are real; account/provider/voice responses are fixtures. No physical ASR or live maps.';

    Future<void> capture(String name) async {
      final measured = await inspect(web, geometry);
      final controls = <String, Object?>{};
      final window = tester.view.physicalSize / tester.view.devicePixelRatio;
      final keyboard = tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
      for (final action in ['back', 'pause', 'resume', 'stop']) {
        final rect = tester.getRect(control(action));
        expect(rect.width, greaterThanOrEqualTo(44), reason: '$name/$action width');
        expect(rect.height, greaterThanOrEqualTo(44), reason: '$name/$action height');
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(window.width + 1));
        expect(rect.bottom, lessThanOrEqualTo(window.height - keyboard + 1));
        controls[action] = {'x': rect.left, 'y': rect.top, 'width': rect.width, 'height': rect.height,
          'enabled': tester.widget<OutlinedButton>(control(action)).onPressed != null};
      }
      measured['nativeControlsGeometry'] = controls;
      measured['nativeWindow'] = [window.width, window.height];
      measured['keyboardInset'] = keyboard;
      measured['webViewCreations'] = webCreations;
      measured['sameWebViewElement'] = identical(webElement,
          tester.element(find.byKey(const ValueKey('brain-projection-webview'))));
      if (platformElement != null) {
        measured['sameUiKitViewElement'] = identical(platformElement,
            tester.element(find.byType(UiKitView)));
      }
      expect(measured['dockDisplay'], 'none');
      expect(measured['draft'], 'An unfinished native address');
      expect((measured['identity'] as Map).values.every((value) => value == true), isTrue);
      expect(webCreations, 1);
      expect(measured['sameWebViewElement'], isTrue);
      if (platformElement != null) expect(measured['sameUiKitViewElement'], isTrue);
      observations[name] = measured;
      await binding.takeScreenshot('projection-native-$name');
    }

    await capture('portrait');
    // Flutter test pointer events cannot tap native platform-view contents.
    // The pinned WK plugin calls WKWebView.evaluateJavaScript directly, whose
    // synchronous client-initiated focus can present the software keyboard.
    // This exercises real WebKit focus/keyboard layout, not a native finger tap.
    // CI disables the simulator's hardware keyboard; no inset is fabricated.
    observations['keyboardTrigger'] = 'WKWebView.evaluateJavaScript element.focus()';
    await web.runJavaScript(r'''(() => {
      const input=document.getElementById('destination-input');
      input.scrollIntoView({block:'center'});
      input.focus();
    })();''');
    await until(tester, () async => tester.view.viewInsets.bottom > 0, 'WKWebView software keyboard');
    expect((await inspect(web, geometry))['inputFocused'], isTrue);
    await capture('keyboard');
    await tester.tap(control('pause'));
    await tester.pump();
    expect(pauses, 1);
    expect(tester.widget<OutlinedButton>(control('resume')).onPressed, isNotNull);
    await web.runJavaScript('document.activeElement?.blur();');
    await until(tester, () async => tester.view.viewInsets.bottom == 0, 'Keyboard dismissal');
    await tester.tap(control('resume'));
    await tester.pump();
    expect(resumes, 1);

    final selectedBefore = Map<String, dynamic>.from(projection.snapshot['selectedPlace'] as Map);
    final cameraBefore = Map<String, dynamic>.from(projection.snapshot['camera'] as Map);
    await projection.voiceTurn('runtime-landscape-1', 'Show projection mode in landscape format', null);
    await until(tester, () async => (await inspect(web, geometry))['layout'] == 'landscape',
        'Spoken landscape format through the native controller');
    await tester.pump(const Duration(milliseconds: 500));
    expect(projection.snapshot['selectedPlace'], selectedBefore);
    expect(projection.snapshot['camera'], cameraBefore);
    expect(starts, 0);
    expect(stops, 0);
    await capture('landscape');

    await tester.tap(control('pause'));
    await until(tester, () async => (await inspect(web, geometry))['phase'] == 'paused', 'Native pause');
    await capture('paused');
    resumeGate = Completer<void>();
    await tester.tap(control('resume'));
    await tester.pump();
    expect(tester.widget<OutlinedButton>(control('stop')).onPressed, isNotNull);
    await tester.tap(control('stop'));
    await tester.pump();
    resumeGate.complete();
    await until(tester, () async => (await inspect(web, geometry))['phase'] == 'complete', 'Stop superseding pending resume');
    expect(stops, 1);
    expect(projection.isOpen, isTrue);
    await capture('stopped');

    await tester.tap(control('layout-auto'));
    await tester.pump();
    expect(projection.snapshot['layoutPreference'], 'auto');
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    await until(tester, () async => (await inspect(web, geometry))['layout'] == 'portrait',
        'Auto layout following a native portrait window');
    await SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft]);
    await until(tester, () async => (await inspect(web, geometry))['layout'] == 'landscape',
        'Auto layout following a native landscape window');
    await capture('auto-landscape');
    await tester.tap(control('layout-landscape'));
    await until(tester, () async => (await inspect(web, geometry))['layout'] == 'landscape', 'Visible landscape control');
    expect(webCreations, 1);

    // Exercise the native fallback after the real document's connect hook is
    // unavailable. Essential actions must not depend on working page scripts.
    await tester.tap(control('start'));
    await tester.pump();
    await web.runJavaScript('window.KorlixProjectionConnect = null;');
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await until(tester, () async => find.text('Retry projection').evaluate().isNotEmpty,
        'Native page failure fallback');
    for (final action in ['back', 'pause', 'resume', 'stop']) {
      expect(control(action), findsOneWidget);
    }
    await tester.tap(control('stop'));
    await tester.pump();
    expect(stops, 2);
    await binding.takeScreenshot('projection-native-page-error');
    await tester.tap(control('back'));
    await tester.pump();
    expect(find.text('Returned to conversation'), findsOneWidget);
    expect(stops, 2, reason: 'Back is separate from stopping voice');
    observations['outcome'] = {'passed': true, 'webViewCreations': webCreations,
      'starts': starts, 'pauses': pauses, 'resumes': resumes, 'stops': stops};
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
  });
}
