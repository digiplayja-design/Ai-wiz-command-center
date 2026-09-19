import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/meeting_copilot/k135z_audio_level.dart';
import 'k135z_capture_controller_test.dart' show CaptureFixture;

Map<String,dynamic> sample(CaptureFixture f, {int level = 65}) => {
  'schemaVersion':1,'context':f.row['snapshot']['context'],'active':true,
  'available':true,'received':true,'packets':50,'ageMs':10,'level':level,'peak':80,
};

void main() {
  test('Start does not manufacture audio; real samples expire and silence stays at zero', () async {
    final f = CaptureFixture();
    try {
      await f.c.refreshAudio(); expect(f.calls, isEmpty);
      await f.start(); expect(f.c.audioReceived, isFalse); expect(f.c.audioLevel, 0);
      await f.c.refreshAudio(); expect(f.c.audioReceived, isTrue); expect(f.c.audioLevel, .65);
      f.now = 3000; expect(f.c.audioRecent, isFalse); expect(f.c.audioLevel, 0);
      expect(f.c.audioMessage, contains('No recent audio'));
      f.audioOverride = sample(f, level:0); await f.c.refreshAudio();
      expect(f.c.audioMessage, contains('currently quiet')); expect(f.c.audioLevel, 0);
    } finally { f.c.dispose(); }
  });
  test('Pause, Stop, consent loss, expiry and backgrounding clear the meter', () async {
    for (final action in ['pause','stop','revoke','expire','suspend']) {
      final f = CaptureFixture();
      try {
        await f.start(); await f.c.refreshAudio(); expect(f.c.audioLevel, greaterThan(0));
        switch (action) {
          case 'pause': await f.c.pause();
          case 'stop': await f.c.stop();
          case 'revoke': await f.c.setConsent(false);
          case 'expire': f.now = 30001; await f.c.tick();
          case 'suspend': f.c.suspend();
        }
        expect(f.c.audioLevel, 0); expect(f.c.audioReceived, isFalse);
      } finally { f.c.dispose(); }
    }
  });
  test('Late audio after Pause, replacement Start, and backgrounding cannot revive old levels', () async {
    for (final background in [false,true]) {
      final f = CaptureFixture();
      try {
        await f.start(); f.audioHold = Completer<void>();
        final pending = f.c.refreshAudio(); await Future<void>.delayed(Duration.zero);
        if (background) { f.c.suspend(); } else {
          await f.c.pause(); await f.c.setConsent(true); await f.c.start();
        }
        f.audioHold!.complete(); await pending;
        expect(f.c.audioReceived, isFalse); expect(f.c.audioLevel, 0);
      } finally { f.c.dispose(); }
    }
  });
  test('Foreign context, impossible levels and contradictory activity cannot light the meter', () async {
    final f = CaptureFixture();
    try {
      await f.start();
      for (final invalid in [
        {...sample(f), 'context':{...f.row['snapshot']['context'],'agentId':'other'}},
        {...sample(f), 'level':101}, {...sample(f), 'active':false},
        {...sample(f), 'received':false}, {...sample(f), 'ageMs':null},
      ]) {
        f.audioOverride = invalid; await f.c.refreshAudio();
        expect(f.c.audioReceived, isFalse); expect(f.c.audioMessage, contains('unavailable'));
      }
    } finally { f.c.dispose(); }
  });
  test('Meter errors do not end valid listening or automatically retry failed endpoint', () async {
    final f = CaptureFixture();
    try {
      await f.start(); f.audioCode = 503; await f.c.refreshAudio();
      expect(f.c.statusLabel, 'Listening'); expect(f.c.consent, isTrue);
      final before = f.calls.where((x)=>x=='audio-level').length;
      f.now=1000; await f.c.tick();
      expect(f.calls.where((x)=>x=='audio-level').length,before);
      f.audioCode=200; await f.c.refreshAudio(); expect(f.c.audioReceived,isTrue);
    } finally { f.c.dispose(); }
  });
  test('Scope and account errors are specific and never issue the capture command', () async {
    for (final item in {'ZOOM_RTMS_SCOPE_REQUIRED':'meeting:update:participant_rtms_app_status',
      'ZOOM_RTMS_ACCOUNT_REJECTED':'2310','ZOOM_RTMS_WEBHOOK_PENDING':'confirmation has not arrived'}.entries) {
      final f = CaptureFixture();
      try {
        f.consentCode=403; f.consentError=item.key; await f.start();
        expect(f.c.listeningMessage,contains(item.value)); expect(f.calls.contains('start'),isFalse);
        expect(f.c.audioLevel,0);
      } finally { f.c.dispose(); }
    }
  });
  testWidgets('Meter shows actual server level and touch button acknowledges a pending check', (tester) async {
    final f = CaptureFixture();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ListenableBuilder(listenable:f.c,
      builder:(_,_)=>K135zAudioLevel(capture:f.c)))));
    expect(find.text('0%'),findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('k135z-check-audio'))).onPressed,isNull);
    await f.start(); await tester.pump(); f.audioHold=Completer<void>();
    await tester.tap(find.byKey(const Key('k135z-check-audio'))); await tester.pump();
    expect(find.text('Checking…'),findsOneWidget); expect(find.text('0%'),findsOneWidget);
    f.audioHold!.complete(); await tester.pump(); await tester.pump(const Duration(milliseconds:700));
    expect(find.text('65%'),findsOneWidget); expect(find.text('Meeting audio is reaching KORLIX.'),findsOneWidget);
    await f.c.pause(); await tester.pump(); expect(find.text('0%'),findsOneWidget);
    await tester.pumpWidget(const SizedBox()); f.c.dispose();
  });
}
