import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// One foreground location capture. Never reads a cached or background position.
class WorkforceLocationService {
  const WorkforceLocationService({
    this.gateway = const WorkforceLocationGateway(),
    this.isWeb = kIsWeb,
  });

  final WorkforceLocationGateway gateway;
  final bool isWeb;

  Future<Map<String, dynamic>> capture({
    void Function(String message)? onProgress,
    WorkforceLocationCancellation? cancellation,
  }) async {
    try {
      cancellation?.throwIfCancelled();
      // Browser permission queries are not consistently supported. A direct
      // geolocation request prompts for permission and reports denial itself.
      if (!isWeb) {
        final enabled = await gateway.isServiceEnabled();
        cancellation?.throwIfCancelled();
        if (!enabled) {
          throw const WorkforceLocationException(
            'Location services are turned off. Turn on your device’s location '
            'services, then tap Capture current location again.',
          );
        }
        var permission = await gateway.checkPermission();
        cancellation?.throwIfCancelled();
        if (permission == LocationPermission.denied) {
          permission = await gateway.requestPermission();
          cancellation?.throwIfCancelled();
        }
        if (permission == LocationPermission.deniedForever) {
          throw const WorkforceLocationException(
            'Location permission is blocked. Open your device Settings, allow '
            'KORLIX to use location while the app is open, then try again.',
          );
        }
        if (permission == LocationPermission.denied) {
          throw const PermissionDeniedException('Location permission denied');
        }
      }
      Position position;
      try {
        position = await _position(LocationAccuracy.high, 20, cancellation);
      } on TimeoutException {
        cancellation?.throwIfCancelled();
        onProgress?.call('GPS is taking longer. Trying another location fix…');
        position = await _position(LocationAccuracy.medium, 15, cancellation);
      } on PositionUpdateException {
        cancellation?.throwIfCancelled();
        onProgress?.call('Trying another way to get your current location…');
        position = await _position(LocationAccuracy.medium, 15, cancellation);
      }
      final age = DateTime.now().toUtc().difference(position.timestamp.toUtc());
      if (!position.latitude.isFinite ||
          position.latitude < -90 ||
          position.latitude > 90 ||
          !position.longitude.isFinite ||
          position.longitude < -180 ||
          position.longitude > 180 ||
          !position.accuracy.isFinite ||
          position.accuracy < 0 ||
          position.accuracy > 100000 ||
          age.abs() > const Duration(minutes: 3)) {
        throw const WorkforceLocationException(
          'Your device did not return a fresh, usable location. Move near a '
          'window or outdoors, keep this screen open, and try again.',
        );
      }
      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'captured_at': position.timestamp.toUtc().toIso8601String(),
      };
    } on WorkforceLocationCancelled {
      rethrow;
    } on WorkforceLocationException {
      rethrow;
    } on PermissionDeniedException {
      throw WorkforceLocationException(
        isWeb
            ? 'Location access is blocked. Allow location for this website in '
                  'your browser’s site settings and enable location for your '
                  'browser in device Settings. Then try again. If you opened '
                  'KORLIX inside another app, open it directly in Safari or Chrome.'
            : 'Location access was not allowed. Allow KORLIX to use location '
                  'while the app is open, then try again.',
      );
    } on LocationServiceDisabledException {
      throw const WorkforceLocationException(
        'Location services are turned off or unavailable. Enable location '
        'services on your device, then try again.',
      );
    } on TimeoutException {
      throw const WorkforceLocationException(
        'Your device could not find your location in time. Move near a window '
        'or outdoors, keep this screen open, and try again.',
      );
    } on UnsupportedError {
      throw const WorkforceLocationException(
        'This browser or device does not support location capture here. Open '
        'KORLIX directly in an up-to-date Safari or Chrome browser using HTTPS.',
      );
    } catch (_) {
      throw const WorkforceLocationException(
        'Your device could not provide a location. Check that location services '
        'are on and permission is allowed, then try again. If it is still '
        'unavailable, enter an exception for your manager to review.',
      );
    }
  }

  Future<Position> _position(
    LocationAccuracy accuracy,
    int seconds,
    WorkforceLocationCancellation? cancellation,
  ) async {
    cancellation?.throwIfCancelled();
    final result = Completer<Position>();
    StreamSubscription<Position>? subscription;
    void fail(Object error) {
      if (!result.isCompleted) result.completeError(error);
    }

    void cancel() => fail(const WorkforceLocationCancelled());
    final timer = Timer(
      Duration(seconds: seconds),
      () => fail(TimeoutException('Location capture timed out')),
    );
    cancellation?._onCancel = cancel;
    try {
      // Use a cancellable watch rather than getCurrentPosition: the locked web
      // plugin sends microseconds to an API expecting milliseconds. Our own
      // timer bounds this attempt, and cancelling the subscription clears the
      // browser watch after a fix, denial, timeout, or closing the dialog.
      subscription = gateway
          .positionStream(
            LocationSettings(
              accuracy: accuracy,
              timeLimit: Duration(seconds: seconds),
            ),
          )
          .listen(
            (position) {
              if (!result.isCompleted) result.complete(position);
            },
            onError: (Object error, StackTrace stack) => fail(error),
            onDone: () =>
                fail(const PositionUpdateException('No location fix')),
          );
      return await result.future;
    } finally {
      timer.cancel();
      if (cancellation?._onCancel == cancel) cancellation?._onCancel = null;
      await subscription?.cancel();
    }
  }
}

/// Stops an in-flight location watch when its attendance dialog is closed.
class WorkforceLocationCancellation {
  bool _cancelled = false;
  void Function()? _onCancel;

  void cancel() {
    _cancelled = true;
    _onCancel?.call();
  }

  void throwIfCancelled() {
    if (_cancelled) throw const WorkforceLocationCancelled();
  }
}

class WorkforceLocationCancelled implements Exception {
  const WorkforceLocationCancelled();
}

class WorkforceLocationGateway {
  const WorkforceLocationGateway();

  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();
  Stream<Position> positionStream(LocationSettings settings) =>
      Geolocator.getPositionStream(locationSettings: settings);
}

class WorkforceLocationException implements Exception {
  const WorkforceLocationException(this.message);
  final String message;
  @override
  String toString() => message;
}
