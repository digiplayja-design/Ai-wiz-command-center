import 'dart:async';

import 'package:ai_wiz_command_center/reviews/korlix_store_review.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('korlix/store_review');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      'passes a neutral review request to $platform without member data',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
        expect(await requestKorlixStoreReview(), isTrue);
        expect(calls.single.method, 'requestReview');
        expect(calls.single.arguments, isNull);
      },
    );
  }

  test('unsupported platforms never call the native channel', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return true;
    });
    for (final platform in [
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.fuchsia,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(await requestKorlixStoreReview(), isFalse);
    }
    expect(calls, 0);
  });

  test(
    'older native builds return unavailable without opening a link',
    () async {
      messenger.setMockMethodCallHandler(channel, null);
      expect(await requestKorlixStoreReview(), isFalse);
    },
  );

  test(
    'native rejection, null and malformed replies never claim success',
    () async {
      for (final reply in <Object?>[false, null, 'true']) {
        messenger.setMockMethodCallHandler(channel, (_) async => reply);
        expect(await requestKorlixStoreReview(), isFalse);
      }
    },
  );

  test(
    'native exceptions are silent and do not poison the next request',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'STORE_UNAVAILABLE');
      });
      expect(await requestKorlixStoreReview(), isFalse);
      messenger.setMockMethodCallHandler(channel, (_) async => true);
      expect(await requestKorlixStoreReview(), isTrue);
    },
  );

  test('concurrent requests cannot launch duplicate store prompts', () async {
    final response = Completer<bool>();
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) {
      calls++;
      return response.future;
    });
    final first = requestKorlixStoreReview();
    expect(await requestKorlixStoreReview(), isFalse);
    response.complete(true);
    expect(await first, isTrue);
    expect(calls, 1);
  });

  testWidgets('an unconfirmed native timeout is not recorded as success', (
    tester,
  ) async {
    final response = Completer<bool>();
    try {
      messenger.setMockMethodCallHandler(channel, (_) => response.future);
      bool? accepted;
      unawaited(requestKorlixStoreReview().then((value) => accepted = value));
      await tester.pump();
      await tester.pump(const Duration(minutes: 2));
      expect(accepted, isFalse);
      response.complete(true);
      await tester.pump();
      expect(accepted, isFalse);
    } finally {
      if (!response.isCompleted) response.complete(false);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test(
    'unsafe navigation can cancel Android preparation without member data',
    () async {
      MethodCall? request;
      messenger.setMockMethodCallHandler(channel, (call) async {
        request = call;
        return null;
      });
      await cancelKorlixStoreReviewRequest();
      expect(request?.method, 'cancelPendingReview');
      expect(request?.arguments, isNull);
    },
  );

  test(
    'cancellation on unavailable or non-Android platforms is harmless',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'STORE_UNAVAILABLE');
      });
      await cancelKorlixStoreReviewRequest();
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return null;
      });
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await cancelKorlixStoreReviewRequest();
      expect(calls, 0);
    },
  );
}
