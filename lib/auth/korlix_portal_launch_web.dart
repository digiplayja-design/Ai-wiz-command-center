import 'package:web/web.dart' as web;

void replacePortalLaunchUri(Uri uri) {
  // Remove the invitation from this tab's URL, without creating another
  // history entry or persisting it in browser storage.
  try {
    web.window.history.replaceState(null, '', uri.toString());
  } catch (_) {
    // Restricted browser history must not prevent account sign-in.
  }
}
