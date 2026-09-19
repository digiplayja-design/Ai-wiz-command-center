import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'korlix_meeting_copilot_route.dart';

const String kKorlixMeetingCopilotPendingRouteKey =
    'korlix.pending.protected.route.v1';

String _normalizeKorlixMeetingRouteCandidate(String raw) {
  var value = raw.trim();

  if (value.startsWith('#')) {
    value = value.substring(1);
  }

  final queryIndex = value.indexOf('?');

  if (queryIndex >= 0) {
    value = value.substring(0, queryIndex);
  }

  final secondHashIndex = value.indexOf('#');

  if (secondHashIndex >= 0) {
    value = value.substring(secondHashIndex + 1);
  }

  try {
    value = Uri.decodeComponent(value);
  } on FormatException {
    return '';
  }

  if (value.isEmpty) {
    return '';
  }

  if (!value.startsWith('/')) {
    value = '/$value';
  }

  while (value.length > 1 && value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }

  return value;
}

bool korlixIsAllowedPendingMeetingRoute(String? value) {
  if (value == null) {
    return false;
  }

  return _normalizeKorlixMeetingRouteCandidate(value) ==
      KorlixMeetingCopilotRoute.routeName;
}

String? korlixMeetingCopilotRouteFromUri(Uri uri) {
  final fragment = _normalizeKorlixMeetingRouteCandidate(uri.fragment);

  if (fragment == KorlixMeetingCopilotRoute.routeName) {
    return KorlixMeetingCopilotRoute.routeName;
  }

  final path = _normalizeKorlixMeetingRouteCandidate(uri.path);

  if (path == KorlixMeetingCopilotRoute.routeName ||
      path.endsWith(KorlixMeetingCopilotRoute.routeName)) {
    return KorlixMeetingCopilotRoute.routeName;
  }

  return null;
}

Future<void> korlixRememberPendingMeetingCopilotRoute() async {
  final preferences = await SharedPreferences.getInstance();

  await preferences.setString(
    kKorlixMeetingCopilotPendingRouteKey,
    KorlixMeetingCopilotRoute.routeName,
  );
}

class KorlixMeetingCopilotAuthObserver extends NavigatorObserver {
  dynamic _authSubscription;
  bool _initialized = false;
  bool _restoreInFlight = false;
  String? currentRouteName;

  void _record(Route<dynamic>? route) {
    currentRouteName = route?.settings.name;
  }

  void _ensureInitialized() {
    if (_initialized) {
      return;
    }

    _initialized = true;
    Future<void>.microtask(_initialize);
  }

  Future<void> _initialize() async {
    await _rememberBrowserRequest();

    for (var attempt = 0; attempt < 20; attempt += 1) {
      try {
        _authSubscription ??= Supabase.instance.client.auth.onAuthStateChange
            .listen((state) {
              final dynamic authState = state;

              if (authState.session != null) {
                _queueRestore();
              }
            });

        break;
      } catch (error) {
        if (attempt == 19) {
          debugPrint(
            'KORLIX Meeting Copilot auth listener unavailable: $error',
          );
          break;
        }

        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }

    await _restoreIfAuthorized();
  }

  Future<void> _rememberBrowserRequest() async {
    final requestedRoute = korlixMeetingCopilotRouteFromUri(Uri.base);

    if (requestedRoute == null) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();

    await preferences.setString(
      kKorlixMeetingCopilotPendingRouteKey,
      requestedRoute,
    );
  }

  void _queueRestore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreIfAuthorized();
    });
  }

  Future<void> _restoreIfAuthorized() async {
    if (_restoreInFlight) {
      return;
    }

    dynamic session;

    try {
      session = Supabase.instance.client.auth.currentSession;
    } catch (error) {
      debugPrint('KORLIX Meeting Copilot session check unavailable: $error');
      return;
    }

    if (session == null) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    final pendingRoute = preferences.getString(
      kKorlixMeetingCopilotPendingRouteKey,
    );

    if (!korlixIsAllowedPendingMeetingRoute(pendingRoute)) {
      if (pendingRoute != null) {
        await preferences.remove(kKorlixMeetingCopilotPendingRouteKey);
      }

      return;
    }

    if (currentRouteName == KorlixMeetingCopilotRoute.routeName) {
      await preferences.remove(kKorlixMeetingCopilotPendingRouteKey);
      return;
    }

    final currentNavigator = navigator;

    if (currentNavigator == null) {
      _queueRestore();
      return;
    }

    _restoreInFlight = true;

    await preferences.remove(kKorlixMeetingCopilotPendingRouteKey);

    currentNavigator
        .pushNamed<void>(KorlixMeetingCopilotRoute.routeName)
        .whenComplete(() {
          _restoreInFlight = false;
        });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _record(route);
    _ensureInitialized();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _record(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _record(newRoute);
    _ensureInitialized();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _record(previousRoute);
  }
}

final KorlixMeetingCopilotAuthObserver kKorlixMeetingCopilotAuthObserver =
    KorlixMeetingCopilotAuthObserver();
