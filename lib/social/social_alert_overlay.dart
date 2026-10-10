import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'social_client.dart';
import 'social_notifications.dart';

/// App-wide Social alerts sit above the navigator without blocking the rest of
/// the app. Opening a call only opens its controls; it never answers the call.
class SocialAlertOverlay extends StatefulWidget {
  const SocialAlertOverlay({
    super.key,
    required this.notifications,
    required this.child,
    required this.onOpenMessage,
    required this.onOpenCall,
    required this.onDeclineCall,
    this.onOpenOnline,
    this.callActionBusy = false,
    this.callError,
  });

  final SocialNotifications notifications;
  final Widget child;
  final Future<void> Function(SocialUnreadConversation) onOpenMessage;
  final Future<void> Function(SocialMap) onOpenCall;
  final Future<void> Function(SocialMap) onDeclineCall;
  final Future<void> Function(SocialOnlineAlert)? onOpenOnline;
  final bool callActionBusy;
  final String? callError;

  @override
  State<SocialAlertOverlay> createState() => _SocialAlertOverlayState();
}

class _SocialAlertOverlayState extends State<SocialAlertOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  Timer? _messageTimer;
  int? _shakenMessageRevision, _shakenCallRevision;
  String? _visibleIdentity;
  int _alertGeneration = 0;
  bool _localBusy = false, _reduceMotion = false, _accessibleNavigation = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    widget.notifications.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    _reduceMotion =
        MediaQuery.disableAnimationsOf(context) || _accessibleNavigation;
    if (_reduceMotion) _shake.stop();
    _syncAlerts();
  }

  @override
  void didUpdateWidget(covariant SocialAlertOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notifications != widget.notifications) {
      oldWidget.notifications.removeListener(_changed);
      widget.notifications.addListener(_changed);
      _messageTimer?.cancel();
      _messageTimer = null;
      _shakenMessageRevision = _shakenCallRevision = null;
      _visibleIdentity = null;
      _alertGeneration++;
      _localBusy = false;
      _localError = null;
    }
    _syncAlerts();
  }

  void _changed() {
    if (!mounted) return;
    setState(_syncAlerts);
  }

  void _syncAlerts() {
    final notifications = widget.notifications;
    final call = notifications.callOpen ? null : notifications.incomingCall;
    final message = notifications.callOpen ? null : notifications.messageAlert;
    final online = notifications.callOpen ? null : notifications.onlineAlert;
    final identity = call != null
        ? 'call:${notifications.callRevision}:${call['id']}'
        : message != null
        ? 'message:${notifications.messageRevision}:${message.key}'
        : online != null
        ? 'online:${online.id}'
        : null;
    if (_visibleIdentity != identity) {
      _visibleIdentity = identity;
      _alertGeneration++;
      _localBusy = false;
      _localError = null;
      _messageTimer?.cancel();
      _messageTimer = null;
    }
    if (call != null) {
      _messageTimer?.cancel();
      _messageTimer = null;
      if (_shakenCallRevision != notifications.callRevision) {
        _shakenCallRevision = notifications.callRevision;
        _startShake();
      }
    } else if (message != null || online != null) {
      if (message != null &&
          _shakenMessageRevision != notifications.messageRevision) {
        _shakenMessageRevision = notifications.messageRevision;
        _startShake();
      }
      // A call gets priority. A waiting message receives a full reading window
      // when the call leaves, rather than expiring behind the call card.
      if (_accessibleNavigation) {
        _messageTimer?.cancel();
        _messageTimer = null;
      } else if (!_localBusy && _messageTimer == null) {
        final generation = _alertGeneration;
        _messageTimer = Timer(const Duration(seconds: 10), () {
          _messageTimer = null;
          if (mounted && generation == _alertGeneration) {
            if (message != null) {
              notifications.dismissMessage();
            } else {
              notifications.dismissOnline();
            }
          }
        });
      }
    } else {
      _messageTimer?.cancel();
      _messageTimer = null;
      _shake.stop();
    }
  }

  void _startShake() {
    if (!_reduceMotion) _shake.forward(from: 0);
  }

  Future<void> _run(
    Future<void> Function() action, {
    required bool call,
  }) async {
    if (_localBusy || call && widget.callActionBusy) return;
    final generation = _alertGeneration;
    _messageTimer?.cancel();
    _messageTimer = null;
    setState(() {
      _localBusy = true;
      _localError = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted && generation == _alertGeneration) {
        setState(() {
          _localError = call
              ? 'Could not update this call. Please try again.'
              : 'Could not open this message. Please try again.';
        });
      }
    } finally {
      if (mounted && generation == _alertGeneration) {
        setState(() {
          _localBusy = false;
          _syncAlerts();
        });
      }
    }
  }

  @override
  void dispose() {
    widget.notifications.removeListener(_changed);
    _messageTimer?.cancel();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifications = widget.notifications;
    final call = notifications.callOpen ? null : notifications.incomingCall;
    final message = notifications.callOpen ? null : notifications.messageAlert;
    final online = notifications.callOpen ? null : notifications.onlineAlert;
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _shake,
            child: widget.child,
            builder: (context, child) {
              final progress = _shake.value;
              final offset = _reduceMotion || !_shake.isAnimating
                  ? 0.0
                  : 5 * math.sin(progress * math.pi * 8) * (1 - progress);
              return Transform.translate(
                key: const ValueKey('social-alert-screen-motion'),
                offset: Offset(offset, 0),
                child: child,
              );
            },
          ),
          if (call != null || message != null || online != null)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(
                bottom: false,
                minimum: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 480,
                      maxHeight: math.max(
                        0,
                        constraints.maxHeight -
                            media.padding.top -
                            media.padding.bottom -
                            media.viewInsets.bottom -
                            24,
                      ),
                    ),
                    child: _alertCard(call, message, online),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _alertCard(
    SocialMap? call,
    SocialUnreadConversation? message,
    SocialOnlineAlert? online,
  ) {
    final isOnline = call == null && message == null && online != null;
    final isCall = call != null;
    final video = call?['mode'] == 'video';
    final title = isCall
        ? video
              ? 'Incoming video call'
              : 'Incoming phone call'
        : isOnline
        ? 'Connection online'
        : 'Incoming message';
    final name = isCall
        ? '${socialMap(call['peer'])['name'] ?? 'KORLIX Social member'}'
        : isOnline
        ? online.name
        : message!.name;
    final busy = _localBusy || isCall && widget.callActionBusy;
    final error = _localError ?? (isCall ? widget.callError : null);
    final accent = isCall ? const Color(0xFF55E2C2) : const Color(0xFFBDB0FF);
    return Semantics(
      key: const ValueKey('social-alert-live-region'),
      container: true,
      liveRegion: true,
      child: Material(
        key: const ValueKey('social-alert-card'),
        elevation: 12,
        shadowColor: Colors.black54,
        color: const Color(0xFF14203A),
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isCall
                  ? const [Color(0xFF103E40), Color(0xFF17243F)]
                  : const [Color(0xFF34215F), Color(0xFF162B4B)],
            ),
            border: Border.all(color: accent.withValues(alpha: .6)),
            borderRadius: BorderRadius.circular(22),
          ),
          child: SingleChildScrollView(
            key: const ValueKey('social-alert-scroll'),
            padding: const EdgeInsets.all(18),
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: Colors.white,
                fontSize: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isCall
                            ? video
                                  ? Icons.videocam_rounded
                                  : Icons.phone_in_talk_rounded
                            : isOnline
                            ? Icons.person_rounded
                            : Icons.mark_chat_unread_rounded,
                        color: accent,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'KORLIX Social',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isCall
                        ? 'View the call to answer.'
                        : isOnline
                        ? 'Is online now. Say hello when you’re ready.'
                        : message!.group
                        ? 'New message in your group.'
                        : 'You have a new private message.',
                    style: const TextStyle(color: Color(0xFFDAE4F6)),
                  ),
                  if (error != null && error.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      style: const TextStyle(color: Color(0xFFFFD7DA)),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _button(
                        label: isCall
                            ? 'View call'
                            : isOnline
                            ? 'Open chat'
                            : 'Open message',
                        icon: isCall ? Icons.call_rounded : Icons.chat_rounded,
                        color: isCall
                            ? const Color(0xFF087565)
                            : const Color(0xFF6840BB),
                        busy: busy,
                        onPressed: busy
                            ? null
                            : () => unawaited(
                                _run(
                                  () => isCall
                                      ? widget.onOpenCall(call)
                                      : isOnline
                                      ? (widget.onOpenOnline?.call(online) ??
                                            Future<void>.value())
                                      : widget.onOpenMessage(message!),
                                  call: isCall,
                                ),
                              ),
                      ),
                      _button(
                        label: isCall ? 'Decline' : 'Dismiss',
                        icon: isCall ? Icons.call_end_rounded : Icons.close,
                        color: isCall
                            ? const Color(0xFFAF2644)
                            : const Color(0xFF235688),
                        onPressed: busy
                            ? null
                            : isCall
                            ? () => unawaited(
                                _run(
                                  () => widget.onDeclineCall(call),
                                  call: true,
                                ),
                              )
                            : isOnline
                            ? widget.notifications.dismissOnline
                            : widget.notifications.dismissMessage,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _button({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    bool busy = false,
  }) => FilledButton.icon(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: color,
      disabledForegroundColor: const Color(0xFFDDE4F1),
      disabledBackgroundColor: const Color(0xFF35445E),
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
    ),
    icon: busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
              semanticsLabel: 'Updating notification',
            ),
          )
        : Icon(icon, size: 20),
    label: Text(label),
  );
}
