import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'korlix_app_feedback_dialog.dart';
import 'korlix_store_review.dart';

/// Identifies a quiet return to the main screen, including modal routes. Route
/// changes are also exposed so an unlaunched native request can be canceled.
class KorlixReviewRouteObserver extends NavigatorObserver with ChangeNotifier {
  final List<Route<dynamic>> _routes = [];
  bool get atHome => _routes.length == 1 && _routes.single.isCurrent;
  void _changed() => notifyListeners();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _changed();
  }
}

/// Web-only invitation. Both paths are offered before any opinion is provided.
/// Native builds use the store's own review UI instead of this dialog.
Future<void> showKorlixReviewInvitation(
  BuildContext context, {
  required String baseUrl,
  required Map<String, String> Function() headersBuilder,
  required Listenable sessionChanges,
}) async {
  bool current = true;
  void changed() => current = false;
  sessionChanges.addListener(changed);
  try {
    final feedback = await showDialog<bool>(
      context: context,
      builder: (_) => KorlixReviewInvitation(
        sessionChanges: sessionChanges,
        isSessionCurrent: () => current,
      ),
    );
    if (feedback == true && current && context.mounted) {
      await showKorlixAppFeedbackDialog(
        context,
        baseUrl: baseUrl,
        headersBuilder: headersBuilder,
        sessionChanges: sessionChanges,
      );
    }
  } finally {
    sessionChanges.removeListener(changed);
  }
}

class KorlixReviewInvitation extends StatefulWidget {
  const KorlixReviewInvitation({
    super.key,
    required this.sessionChanges,
    this.openStore,
    this.isSessionCurrent,
  });
  final Listenable sessionChanges;
  final Future<bool> Function()? openStore;
  final bool Function()? isSessionCurrent;
  @override
  State<KorlixReviewInvitation> createState() => _KorlixReviewInvitationState();
}

class _KorlixReviewInvitationState extends State<KorlixReviewInvitation> {
  bool _opening = false;
  bool _current = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _current = widget.isSessionCurrent?.call() ?? true;
    widget.sessionChanges.addListener(_sessionChanged);
    if (!_current) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sessionChanged());
    }
  }

  void _sessionChanged() {
    _current = false;
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  @override
  void dispose() {
    widget.sessionChanges.removeListener(_sessionChanged);
    super.dispose();
  }

  Future<void> _openStore() async {
    if (_opening || !_current || !(widget.isSessionCurrent?.call() ?? true))
      return;
    final route = ModalRoute.of(context);
    setState(() {
      _opening = true;
      _error = null;
    });
    bool opened = false;
    try {
      opened =
          await (widget.openStore?.call() ??
              launchUrl(
                Uri.parse(korlixGooglePlayListingUrl),
                mode: LaunchMode.externalApplication,
                webOnlyWindowName: '_blank',
              ));
    } catch (_) {
      /* An unavailable store never submits private feedback. */
    }
    if (!mounted || !_current || route?.isCurrent != true) return;
    if (opened) {
      Navigator.of(context).pop(false);
    } else {
      setState(() {
        _opening = false;
        _error = 'Google Play could not open. You can try again later.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.favorite_border, color: Color(0xFF69D9E8), size: 36),
    title: const Text('Share your KORLIX experience'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Your experience helps us improve. Send the KORLIX team '
          'private feedback, or leave an honest review on Google Play.',
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('korlix-review-private-feedback'),
            onPressed: _opening ? null : () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.feedback_outlined),
            label: const Text('Send private feedback'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('korlix-review-google-play'),
            onPressed: _opening ? null : _openStore,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Review on Google Play'),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Not now'),
      ),
    ],
  );
}
