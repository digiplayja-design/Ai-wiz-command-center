import 'dart:async';

import 'package:ai_wiz_command_center/workforce/workforce_forms.dart';
import 'package:ai_wiz_command_center/workforce/workforce_location.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

class FakeLocationGateway extends WorkforceLocationGateway {
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requestedPermission = LocationPermission.whileInUse;
  int serviceChecks = 0, permissionChecks = 0, permissionRequests = 0;
  int cancellations = 0;
  final positions = <Object>[];
  final settings = <LocationSettings>[];

  @override
  Future<bool> isServiceEnabled() async {
    serviceChecks++;
    return enabled;
  }

  @override
  Future<LocationPermission> checkPermission() async {
    permissionChecks++;
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    return requestedPermission;
  }

  @override
  Stream<Position> positionStream(LocationSettings value) {
    settings.add(value);
    final next = positions.removeAt(0);
    var cancelled = false;
    late StreamController<Position> controller;
    controller = StreamController<Position>(
      onListen: () async {
        try {
          final position = next is Future<Position> ? await next : next;
          if (cancelled) return;
          if (position is Position) {
            controller.add(position);
          } else {
            controller.addError(position);
          }
        } catch (error, stack) {
          if (!cancelled) controller.addError(error, stack);
        }
      },
      // Return a Future created in this test's zone. A synchronous void
      // callback uses Dart's cached null Future, whose completion can belong
      // to an earlier real-clock test and stall a later fake-clock capture.
      onCancel: () async {
        cancelled = true;
        cancellations++;
      },
    );
    return controller.stream;
  }
}

Position fix({
  double accuracy = 12,
  DateTime? timestamp,
  double latitude = 40.7,
}) => Position(
  latitude: latitude,
  longitude: -73.9,
  timestamp: timestamp ?? DateTime.now().toUtc(),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  test(
    'Web captures without relying on browser permission-query APIs',
    () async {
      final gateway = FakeLocationGateway()
        ..enabled = false
        ..permission = LocationPermission.deniedForever
        ..positions.add(fix());
      final result = await WorkforceLocationService(
        gateway: gateway,
        isWeb: true,
      ).capture();
      expect(result['latitude'], 40.7);
      expect(gateway.serviceChecks, 0);
      expect(gateway.permissionChecks, 0);
      expect(gateway.permissionRequests, 0);
      expect(gateway.settings.single.accuracy, LocationAccuracy.high);
    },
  );

  test('Timestamp remains the actual device fix time', () async {
    final captured = DateTime.now().toUtc().subtract(
      const Duration(seconds: 40),
    );
    final gateway = FakeLocationGateway()
      ..positions.add(fix(timestamp: captured));
    final result = await WorkforceLocationService(gateway: gateway).capture();
    expect(result['captured_at'], captured.toIso8601String());
  });

  test('GPS timeout retries once with a bounded current fix', () async {
    final gateway = FakeLocationGateway()
      ..positions.addAll([TimeoutException('GPS timeout'), fix(accuracy: 150)]);
    final messages = <String>[];
    final result = await WorkforceLocationService(
      gateway: gateway,
      isWeb: true,
    ).capture(onProgress: messages.add);
    expect(result['accuracy'], 150);
    expect(gateway.settings.map((s) => s.accuracy), [
      LocationAccuracy.high,
      LocationAccuracy.medium,
    ]);
    expect(gateway.settings.map((s) => s.timeLimit), [
      const Duration(seconds: 20),
      const Duration(seconds: 15),
    ]);
    expect(messages.single, contains('Trying another location fix'));
  });

  test(
    'Provider unavailable retries once instead of discarding the capture',
    () async {
      final gateway = FakeLocationGateway()
        ..positions.addAll([PositionUpdateException('unavailable'), fix()]);
      final result = await WorkforceLocationService(gateway: gateway).capture();
      expect(result['accuracy'], 12);
      expect(gateway.settings.length, 2);
    },
  );

  test('Permission denial does not retry or fabricate coordinates', () async {
    final gateway = FakeLocationGateway()
      ..positions.add(PermissionDeniedException('denied'));
    await expectLater(
      WorkforceLocationService(gateway: gateway, isWeb: true).capture(),
      throwsA(
        isA<WorkforceLocationException>().having(
          (e) => e.message,
          'recovery',
          contains('browser’s site settings'),
        ),
      ),
    );
    expect(gateway.settings.length, 1);
  });

  test(
    'Both GPS attempts timing out explains retry and releases the request',
    () async {
      final gateway = FakeLocationGateway()
        ..positions.addAll([
          TimeoutException('first'),
          TimeoutException('second'),
        ]);
      await expectLater(
        WorkforceLocationService(gateway: gateway, isWeb: true).capture(),
        throwsA(
          isA<WorkforceLocationException>().having(
            (e) => e.message,
            'timeout recovery',
            contains('in time'),
          ),
        ),
      );
      expect(gateway.settings.length, 2);
    },
  );

  test(
    'Native service disabled is explained before requesting permissions',
    () async {
      final gateway = FakeLocationGateway()..enabled = false;
      await expectLater(
        WorkforceLocationService(gateway: gateway, isWeb: false).capture(),
        throwsA(
          isA<WorkforceLocationException>().having(
            (e) => e.message,
            'disabled service',
            contains('turned off'),
          ),
        ),
      );
      expect(gateway.permissionChecks, 0);
      expect(gateway.settings, isEmpty);
    },
  );

  test('Native permission can be granted from the first capture', () async {
    final gateway = FakeLocationGateway()
      ..permission = LocationPermission.denied
      ..positions.add(fix());
    await WorkforceLocationService(gateway: gateway, isWeb: false).capture();
    expect(gateway.permissionRequests, 1);
    expect(gateway.settings.length, 1);
  });

  test(
    'Permanently denied native permission directs to app settings',
    () async {
      final gateway = FakeLocationGateway()
        ..permission = LocationPermission.deniedForever;
      await expectLater(
        WorkforceLocationService(gateway: gateway, isWeb: false).capture(),
        throwsA(
          isA<WorkforceLocationException>().having(
            (e) => e.message,
            'settings recovery',
            contains('device Settings'),
          ),
        ),
      );
      expect(gateway.permissionRequests, 0);
      expect(gateway.settings, isEmpty);
    },
  );

  for (final entry in <String, Position>{
    'stale': fix(
      timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
    ),
    'future': fix(timestamp: DateTime.now().add(const Duration(minutes: 10))),
    'invalid coordinates': fix(latitude: double.nan),
    'invalid accuracy': fix(accuracy: -1),
  }.entries) {
    test(
      'Rejects ${entry.key} fixes without replacing their timestamp',
      () async {
        final gateway = FakeLocationGateway()..positions.add(entry.value);
        await expectLater(
          WorkforceLocationService(gateway: gateway, isWeb: true).capture(),
          throwsA(isA<WorkforceLocationException>()),
        );
      },
    );
  }

  Future<void> showPunch(
    WidgetTester tester,
    FakeLocationGateway gateway,
    Future<void> Function(Map<String, dynamic>) submit, {
    bool clockOut = false,
  }) async {
    tester.view.physicalSize = const Size(768, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkforcePunchDialog(
            clockOut: clockOut,
            policy: const {'require_location': true},
            locationService: WorkforceLocationService(
              gateway: gateway,
              isWeb: true,
            ),
            submit: submit,
          ),
        ),
      ),
    );
  }

  test('A silent browser watch times out and is cancelled before retry', () {
    fakeAsync((async) {
      final silent = Completer<Position>();
      final gateway = FakeLocationGateway()
        ..positions.addAll([silent.future, fix()]);
      Map<String, dynamic>? result;
      Object? failure;
      WorkforceLocationService(
        gateway: gateway,
        isWeb: true,
      ).capture().then<void>(
        (value) {
          result = value;
        },
        onError: (Object error) {
          failure = error;
        },
      );
      async.flushMicrotasks();
      expect(gateway.settings.length, 1);
      expect(result, isNull);
      async.elapse(const Duration(seconds: 19));
      expect(gateway.cancellations, 0);
      expect(gateway.settings.length, 1);
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(failure, isNull);
      expect(
        result,
        isNotNull,
        reason: 'Capture must complete after its bounded retry',
      );
      expect(result!['latitude'], 40.7);
      expect(gateway.settings.length, 2);
      expect(gateway.cancellations, 2);
      expect(async.pendingTimers, isEmpty);
      silent.complete(fix(latitude: 42));
      async.flushMicrotasks();
      expect(result!['latitude'], 40.7);
      expect(gateway.settings.length, 2);
    });
  });

  testWidgets(
    'Closing the attendance dialog cancels capture with no later retry',
    (tester) async {
      final silent = Completer<Position>();
      final gateway = FakeLocationGateway()..positions.add(silent.future);
      await showPunch(tester, gateway, (_) async {});
      await tester.tap(find.text('Capture current location'));
      await tester.pump();
      expect(gateway.settings.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 50));
      expect(gateway.cancellations, 1);
      expect(gateway.settings.length, 1);
      silent.complete(fix());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Capture progress is visible and successful fix is submitted', (
    tester,
  ) async {
    final pending = Completer<Position>();
    final gateway = FakeLocationGateway()..positions.add(pending.future);
    Map<String, dynamic>? saved;
    await showPunch(tester, gateway, (value) async {
      saved = value;
    });
    await tester.tap(find.text('Capture current location'));
    await tester.pump();
    expect(find.text('Finding location…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    pending.complete(fix());
    await tester.pumpAndSettle();
    expect(find.text('Refresh location'), findsOneWidget);
    await tester.tap(find.text('Confirm clock-in'));
    await tester.pumpAndSettle();
    expect(saved!['location']['latitude'], 40.7);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Denied capture shows actionable guidance and can be retried', (
    tester,
  ) async {
    final gateway = FakeLocationGateway()
      ..positions.addAll([PermissionDeniedException('denied'), fix()]);
    await showPunch(tester, gateway, (_) async {});
    await tester.tap(find.text('Capture current location'));
    await tester.pumpAndSettle();
    expect(find.textContaining('browser’s site settings'), findsOneWidget);
    await tester.tap(find.text('Capture current location'));
    await tester.pumpAndSettle();
    expect(find.textContaining('browser’s site settings'), findsNothing);
    expect(find.text('Refresh location'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Approximate capture keeps the exception requirement for clock-in',
    (tester) async {
      final gateway = FakeLocationGateway()..positions.add(fix(accuracy: 200));
      Map<String, dynamic>? saved;
      await showPunch(tester, gateway, (value) async {
        saved = value;
      });
      await tester.tap(find.text('Capture current location'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('This location is approximate'),
        findsOneWidget,
      );
      await tester.tap(find.text('Confirm clock-in'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await tester.enterText(
        find.byType(TextField),
        'GPS signal unavailable indoors',
      );
      await tester.tap(find.text('Confirm clock-in'));
      await tester.pumpAndSettle();
      expect(saved!['location']['accuracy'], 200);
      expect(saved!['exception_reason'], 'GPS signal unavailable indoors');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Missing capture still allows clock-out for manager review', (
    tester,
  ) async {
    final gateway = FakeLocationGateway()
      ..positions.add(PermissionDeniedException('denied'));
    Map<String, dynamic>? saved;
    await showPunch(tester, gateway, (value) async {
      saved = value;
    }, clockOut: true);
    await tester.tap(find.text('Capture current location'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm clock-out'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!['location'], isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
