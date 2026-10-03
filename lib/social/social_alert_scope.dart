import 'package:flutter/material.dart';

import 'social_notifications.dart';

/// Shares the single app-wide receiver with Social routes.
class SocialAlertScope extends InheritedWidget {
  const SocialAlertScope({
    super.key,
    required this.notifications,
    required this.routeObserver,
    required super.child,
  });

  final SocialNotifications notifications;
  final RouteObserver<ModalRoute<dynamic>> routeObserver;

  static SocialAlertScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SocialAlertScope>();

  @override
  bool updateShouldNotify(SocialAlertScope oldWidget) =>
      notifications != oldWidget.notifications ||
      routeObserver != oldWidget.routeObserver;
}
