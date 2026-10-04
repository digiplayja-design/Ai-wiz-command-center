import 'package:flutter/material.dart';

import 'social_notifications.dart';
import 'social_call_session.dart';

/// Shares the single app-wide receiver with Social routes.
class SocialAlertScope extends InheritedWidget {
  const SocialAlertScope({
    super.key,
    required this.notifications,
    required this.routeObserver,
    required super.child,
    this.calls,
  });

  final SocialNotifications notifications;
  final RouteObserver<ModalRoute<dynamic>> routeObserver;
  final SocialCallSession? calls;

  static SocialAlertScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SocialAlertScope>();

  @override
  bool updateShouldNotify(SocialAlertScope oldWidget) =>
      notifications != oldWidget.notifications ||
      routeObserver != oldWidget.routeObserver;
}
