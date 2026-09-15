import 'package:flutter/foundation.dart';

import 'korlix_zoom_connection_client.dart';

enum KorlixZoomConnectionPhase {
  idle,
  loadingStatus,
  disconnected,
  connecting,
  connected,
  loadingMeetings,
  disconnecting,
  error,
}

class KorlixZoomConnectionController extends ChangeNotifier {
  KorlixZoomConnectionController({required KorlixZoomConnectionClient client})
    : _client = client;

  final KorlixZoomConnectionClient _client;
  KorlixZoomConnectionPhase _phase = KorlixZoomConnectionPhase.idle;
  KorlixZoomConnectionStatus? _status;
  List<KorlixZoomMeetingSummary> _meetings = const <KorlixZoomMeetingSummary>[];
  String? _errorMessage;
  int _operationRevision = 0;
  bool _disposed = false;

  KorlixZoomConnectionPhase get phase => _phase;
  KorlixZoomConnectionStatus? get status => _status;
  List<KorlixZoomMeetingSummary> get meetings => _meetings;
  String? get errorMessage => _errorMessage;
  bool get isBusy => <KorlixZoomConnectionPhase>{
    KorlixZoomConnectionPhase.loadingStatus,
    KorlixZoomConnectionPhase.connecting,
    KorlixZoomConnectionPhase.loadingMeetings,
    KorlixZoomConnectionPhase.disconnecting,
  }.contains(_phase);

  Future<void> refreshStatus() async {
    final int operation = _begin(KorlixZoomConnectionPhase.loadingStatus);
    try {
      final KorlixZoomConnectionStatus status = await _client.getStatus();
      if (!_current(operation)) {
        return;
      }
      _status = status;
      if (!status.connected) {
        _meetings = const <KorlixZoomMeetingSummary>[];
      }
      _errorMessage = null;
      _setPhase(
        status.connected
            ? KorlixZoomConnectionPhase.connected
            : KorlixZoomConnectionPhase.disconnected,
      );
    } catch (error) {
      _setErrorIfCurrent(operation, error);
    }
  }

  Future<Uri> beginAuthorization({Uri? returnTo}) async {
    final int operation = _begin(KorlixZoomConnectionPhase.connecting);
    try {
      final KorlixZoomAuthorizationStart start = await _client
          .beginAuthorization(returnTo: returnTo);
      if (!_current(operation)) {
        throw const KorlixZoomApiException(
          statusCode: 409,
          code: 'K135Z_STALE_AUTHORIZATION_RESULT',
          message: 'A newer Zoom operation replaced this authorization result.',
        );
      }
      _errorMessage = null;
      _setPhase(
        _status?.connected == true
            ? KorlixZoomConnectionPhase.connected
            : KorlixZoomConnectionPhase.disconnected,
      );
      return start.authorizationUri;
    } catch (error) {
      _setErrorIfCurrent(operation, error);
      rethrow;
    }
  }

  Future<void> loadUpcomingMeetings() async {
    if (_status?.connected != true) {
      _setError(
        const KorlixZoomApiException(
          statusCode: 409,
          code: 'K135Z_ZOOM_NOT_CONNECTED',
          message:
              'A verified Zoom connection is required before loading meetings.',
        ),
      );
      return;
    }
    final int operation = _begin(KorlixZoomConnectionPhase.loadingMeetings);
    try {
      final List<KorlixZoomMeetingSummary> meetings = await _client
          .listUpcomingMeetings();
      if (!_current(operation)) {
        return;
      }
      _meetings = List<KorlixZoomMeetingSummary>.unmodifiable(meetings);
      _errorMessage = null;
      _setPhase(KorlixZoomConnectionPhase.connected);
    } catch (error) {
      _setErrorIfCurrent(operation, error);
    }
  }

  Future<void> disconnect() async {
    final int operation = _begin(KorlixZoomConnectionPhase.disconnecting);
    try {
      final bool acknowledged = await _client.disconnect();
      if (!_current(operation)) {
        return;
      }
      if (!acknowledged) {
        throw const KorlixZoomApiException(
          statusCode: 502,
          code: 'K135Z_ZOOM_DISCONNECT_NOT_ACKNOWLEDGED',
          message:
              'The backend did not confirm that the Zoom connection was removed.',
        );
      }
      _status = const KorlixZoomConnectionStatus(
        connected: false,
        requiresReauthorization: false,
        accessTokenExpired: false,
      );
      _meetings = const <KorlixZoomMeetingSummary>[];
      _errorMessage = null;
      _setPhase(KorlixZoomConnectionPhase.disconnected);
    } catch (error) {
      _setErrorIfCurrent(operation, error);
    }
  }

  void clearError() {
    if (_disposed) {
      return;
    }
    _errorMessage = null;
    _setPhase(
      _status?.connected == true
          ? KorlixZoomConnectionPhase.connected
          : KorlixZoomConnectionPhase.disconnected,
    );
  }

  int _begin(KorlixZoomConnectionPhase phase) {
    _operationRevision += 1;
    _setPhase(phase);
    return _operationRevision;
  }

  bool _current(int operation) => !_disposed && operation == _operationRevision;

  void _setErrorIfCurrent(int operation, Object error) {
    if (_current(operation)) {
      _setError(error);
    }
  }

  void _setError(Object error) {
    _errorMessage = error is KorlixZoomApiException
        ? error.message
        : 'The Zoom connection request could not be completed.';
    _setPhase(KorlixZoomConnectionPhase.error);
  }

  void _setPhase(KorlixZoomConnectionPhase value) {
    if (_disposed) {
      return;
    }
    _phase = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _operationRevision += 1;
    super.dispose();
  }
}
