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
    _setPhase(KorlixZoomConnectionPhase.loadingStatus);

    try {
      _status = await _client.getStatus();

      _errorMessage = null;

      _setPhase(
        _status!.connected
            ? KorlixZoomConnectionPhase.connected
            : KorlixZoomConnectionPhase.disconnected,
      );
    } catch (error) {
      _setError(error);
    }
  }

  Future<Uri> beginAuthorization({Uri? returnTo}) async {
    _setPhase(KorlixZoomConnectionPhase.connecting);

    try {
      final KorlixZoomAuthorizationStart start = await _client
          .beginAuthorization(returnTo: returnTo);

      _errorMessage = null;

      _setPhase(
        _status?.connected == true
            ? KorlixZoomConnectionPhase.connected
            : KorlixZoomConnectionPhase.disconnected,
      );

      return start.authorizationUri;
    } catch (error) {
      _setError(error);
      rethrow;
    }
  }

  Future<void> loadUpcomingMeetings() async {
    _setPhase(KorlixZoomConnectionPhase.loadingMeetings);

    try {
      _meetings = await _client.listUpcomingMeetings();

      _errorMessage = null;

      _setPhase(KorlixZoomConnectionPhase.connected);
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> disconnect() async {
    _setPhase(KorlixZoomConnectionPhase.disconnecting);

    try {
      await _client.disconnect();

      _status = const KorlixZoomConnectionStatus(
        connected: false,
        requiresReauthorization: false,
        accessTokenExpired: false,
      );

      _meetings = const <KorlixZoomMeetingSummary>[];

      _errorMessage = null;

      _setPhase(KorlixZoomConnectionPhase.disconnected);
    } catch (error) {
      _setError(error);
    }
  }

  void clearError() {
    _errorMessage = null;

    _setPhase(
      _status?.connected == true
          ? KorlixZoomConnectionPhase.connected
          : KorlixZoomConnectionPhase.disconnected,
    );
  }

  void _setError(Object error) {
    _errorMessage = error is KorlixZoomApiException
        ? error.message
        : 'The Zoom connection '
              'request could not '
              'be completed.';

    _setPhase(KorlixZoomConnectionPhase.error);
  }

  void _setPhase(KorlixZoomConnectionPhase value) {
    _phase = value;
    notifyListeners();
  }
}
