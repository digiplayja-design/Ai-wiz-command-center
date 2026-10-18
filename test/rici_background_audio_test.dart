import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/social/social_call_background.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('korlix/social_call_background');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('Rici identifies its notification and releases the native lease', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    final background = SocialCallBackground(kind: 'rici');
    expect(await background.start('rici-test'), true);
    expect(calls.first.arguments, {'id': 'rici-test', 'kind': 'rici'});
    await background.stop();
    expect(background.ready, false);
    expect(calls.last.method, 'stop');
  });

  test('late native startup cannot revive voice stopped during permission setup', () async {
    final gate = Completer<bool>();
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'start' ? gate.future : true;
    });
    final background = SocialCallBackground(kind: 'rici');
    final start = background.start('rici-cancelled');
    await Future<void>.delayed(Duration.zero);
    await background.stop();
    expect(await start, false);
    gate.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(background.ready, false);
    expect(calls.where((c) => c.method == 'stop'), isNotEmpty);
  });
}
