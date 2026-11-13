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
  const inputRect=input.getBoundingClientRect();
  return {layout:document.body.dataset.layout,nativeControls:document.body.dataset.nativeControls,
    entryActive:document.body.dataset.entryActive,
    readyState:document.readyState,captureFrame:window.runtimeCapture?.frame||0,
    window:[innerWidth,innerHeight],body:rect(document.body),shell:rect(document.querySelector('.projection-shell')),
    dockDisplay:getComputedStyle(document.querySelector('.voice-dock')).display,
    closeDisplay:getComputedStyle(document.getElementById('close-projection')).display,
    input:rect(input),inputFocused:document.activeElement===input,
    inputHit:document.elementFromPoint(inputRect.x+inputRect.width/2,inputRect.y+inputRect.height/2)===input,
    draft:input.value,selected:document.getElementById('place-label').textContent,
    frame:frame?rect(frame):null,framePresent:frame instanceof HTMLIFrameElement&&frame.isConnected,
    providerWindowPresent:!!frame?.contentWindow,
    identity:!window.runtimeIdentity?null:{input:input===window.runtimeIdentity.input,
      frame:frame===window.runtimeIdentity.frame,providerWindow:frame?.contentWindow===window.runtimeIdentity.providerWindow},
    phase:document.body.dataset.voice};
})()''';

Object? roundedGeometry(Object? value) {
  if (value is num) return (value * 4).round();
  if (value is List) return value.map(roundedGeometry).toList();
  if (value is Map) {
    return value.map((key, item) => MapEntry(key, roundedGeometry(item)));
  }
  return value;
}

Rect measuredRect(Map value) => Rect.fromLTWH(
    (value['x'] as num).toDouble(), (value['y'] as num).toDouble(),
    (value['width'] as num).toDouble(), (value['height'] as num).toDouble());

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    // Native view and keyboard updates must render between explicit test pumps.
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

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
    var projectionDisposed = false;
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
    void disposeProjection() {
      if (projectionDisposed) return;
      projectionDisposed = true;
      projection.dispose();
    }
    addTearDown(disposeProjection);
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
      if (!(frame instanceof HTMLIFrameElement) || !frame.isConnected) {
        throw new Error('Expected a connected provider iframe before recording its identity');
      }
      if (!frame.contentWindow) {
        throw new Error('Expected a provider browsing context before recording its identity');
      }
      window.runtimeIdentity={input,frame,providerWindow:frame.contentWindow};
    ''');
    final observations = <String, Object?>{};
    binding.reportData ??= {};
    binding.reportData!['projectionRuntime'] = observations;
    observations['runtime'] = Platform.isIOS ? 'actual iOS WKWebView' : Platform.operatingSystem;
    observations['fixtureLimits'] = 'Native view and HTML are real; account/provider/voice responses are fixtures. Provider frame/window existence, size and identity do not establish loaded imagery. No physical ASR or live maps.';
    observations['captureLimits'] = 'Captures wait for advancing WebKit animation frames and stable native/DOM geometry. The iOS integration screenshot draws the UIKit window hierarchy; this does not independently prove WebKit compositor freshness or capture an out-of-process keyboard. PNGs require visual review.';
    observations['outcome'] = {'scenarioCompleted': false};

    Future<Map<String, dynamic>> measureCapture(String name) async {
      final measured = await inspect(web, geometry);
      final controls = <String, Object?>{};
      final window = tester.view.physicalSize / tester.view.devicePixelRatio;
      final keyboard = tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
      for (final action in ['back', 'pause', 'resume', 'stop']) {
        final rect = tester.getRect(control(action));
        controls[action] = {'x': rect.left, 'y': rect.top, 'width': rect.width, 'height': rect.height,
          'enabled': tester.widget<OutlinedButton>(control(action)).onPressed != null};
      }
      final webBounds = tester.getRect(find.byKey(const ValueKey('brain-projection-webview')));
      measured['nativeWebView'] = {'x': webBounds.left, 'y': webBounds.top,
        'width': webBounds.width, 'height': webBounds.height};
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
      // Retain the last actual measurements even when stabilization or a later
      // invariant fails; failure artifacts must show the offending geometry.
      observations[name] = measured;
      return measured;
    }

    var captureToken = 0;
    Future<Map<String, dynamic>> stableCapture(String name) async {
      final token = ++captureToken;
      await web.runJavaScript('''(() => {
        const capture={token:$token,frame:0,active:true};
        window.runtimeCapture=capture;
        const tick=()=>{
          if(window.runtimeCapture!==capture||!capture.active)return;
          capture.frame++;
          requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      })();''');
      Map<String, dynamic>? latest;
      String? previous;
      var previousFrame = -1, stableSamples = 0;
      try {
        await until(tester, () async {
          final measured = await measureCapture(name);
          latest = measured;
          final body = measuredRect(measured['body'] as Map);
          final nativeWebView = measuredRect(measured['nativeWebView'] as Map);
          final viewportMatches = (body.width - nativeWebView.width).abs() <= 1 &&
              (body.height - nativeWebView.height).abs() <= 1;
          final frame = measured['captureFrame'] as int;
          final signature = jsonEncode(roundedGeometry({
            for (final key in ['layout', 'nativeControls', 'entryActive', 'body', 'shell', 'input', 'frame',
              'inputFocused', 'inputHit', 'dockDisplay', 'closeDisplay', 'phase',
              'nativeControlsGeometry', 'nativeWebView', 'nativeWindow', 'keyboardInset'])
              key: measured[key],
          }));
          final rendered = frame >= 2 && frame > previousFrame && measured['entryActive'] == 'false' &&
              measured['readyState'] == 'complete' && viewportMatches;
          stableSamples = rendered ? (signature == previous ? stableSamples + 1 : 1) : 0;
          previous = signature;
          previousFrame = frame;
          measured['captureSynchronization'] = {'webAnimationFrames': frame,
            'stableSamples': stableSamples, 'viewportMatches': viewportMatches};
          return stableSamples >= 3;
        }, '$name stable native/WebKit presentation');
        return latest!;
      } finally {
        await web.runJavaScript('if(window.runtimeCapture?.token===$token)window.runtimeCapture.active=false;');
      }
    }

    Future<void> capture(String name) async {
      final measured = await stableCapture(name);
      final window = measured['nativeWindow'] as List;
      final keyboard = measured['keyboardInset'] as num;
      for (final entry in (measured['nativeControlsGeometry'] as Map).entries) {
        final rect = measuredRect(entry.value as Map);
        expect(rect.width, greaterThanOrEqualTo(44), reason: '$name/${entry.key} width');
        expect(rect.height, greaterThanOrEqualTo(44), reason: '$name/${entry.key} height');
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo((window[0] as num) + 1));
        expect(rect.bottom, lessThanOrEqualTo((window[1] as num) - keyboard + 1));
      }
      expect(measured['dockDisplay'], 'none');
      expect(measured['closeDisplay'], 'none');
      if (name == 'keyboard') {
        expect(keyboard, greaterThan(0), reason: 'Real software keyboard inset');
        expect(measured['inputFocused'], isTrue);
        final input = measuredRect(measured['input'] as Map);
        expect(input.width, greaterThan(0));
        expect(input.height, greaterThan(0));
        for (final parent in ['body', 'shell']) {
          final bounds = measuredRect(measured[parent] as Map);
          expect(input.left, greaterThanOrEqualTo(bounds.left - 1), reason: 'Focused input inside $parent');
          expect(input.top, greaterThanOrEqualTo(bounds.top - 1), reason: 'Focused input inside $parent');
          expect(input.right, lessThanOrEqualTo(bounds.right + 1), reason: 'Focused input inside $parent');
          expect(input.bottom, lessThanOrEqualTo(bounds.bottom + 1), reason: 'Focused input inside $parent');
        }
        expect(measured['inputHit'], isTrue, reason: 'Focused input is not covered by another element');
      }
      expect(measured['draft'], 'An unfinished native address');
      expect(measured['framePresent'], isTrue, reason: '$name provider iframe exists');
      expect(measured['providerWindowPresent'], isTrue, reason: '$name provider browsing context exists');
      if (['portrait', 'landscape', 'auto-landscape'].contains(name)) {
        final frameBounds = measured['frame'] as Map;
        expect(frameBounds['width'] as num, greaterThan(0), reason: '$name provider frame width');
        expect(frameBounds['height'] as num, greaterThan(0), reason: '$name provider frame height');
      }
      expect((measured['identity'] as Map).values.every((value) => value == true), isTrue);
      expect(webCreations, 1);
      expect(measured['sameWebViewElement'], isTrue);
      if (platformElement != null) expect(measured['sameUiKitViewElement'], isTrue);
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
    await tester.pump();
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
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    disposeProjection();
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    await tester.pump();
    expect(tester.takeException(), isNull);
    // The driver exit status and CI conclusion own the overall test result.
    observations['outcome'] = {'scenarioCompleted': true, 'webViewCreations': webCreations,
      'starts': starts, 'pauses': pauses, 'resumes': resumes, 'stops': stops};
  });
}
