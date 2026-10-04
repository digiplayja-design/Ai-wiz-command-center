import 'korlix_portal_launch_stub.dart'
    if (dart.library.js_interop) 'korlix_portal_launch_web.dart'
    as platform;

/// A navigation hint, never an authorization grant. The portal API verifies
/// membership or the signed-in account's invitation before returning content.
class KorlixPortalLaunch {
  const KorlixPortalLaunch(this.portalId, this.inviteToken);
  final String portalId;
  final String? inviteToken;

  static KorlixPortalLaunch? parse(Uri uri) {
    final ids = uri.queryParametersAll['app_portal'];
    if (ids == null || ids.length != 1) return null;
    final id = ids.single;
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(id)) {
      return null;
    }
    final fragment = _fragmentParameters(uri);
    final codes = [
      ...?uri.queryParametersAll['invite'],
      ...?fragment['invite'],
    ];
    if (codes.length > 1) return null;
    final code = codes.isEmpty ? null : codes.single;
    if (code != null && !RegExp(r'^[A-Za-z0-9_-]{20,160}$').hasMatch(code)) {
      return null;
    }
    return KorlixPortalLaunch(id.toLowerCase(), code);
  }

  static Map<String, List<String>> _fragmentParameters(Uri uri) {
    if (!uri.fragment.startsWith('invite=') &&
        !uri.fragment.startsWith('?invite=')) {
      return const {};
    }
    try {
      return Uri(
        query: uri.fragment.replaceFirst(RegExp(r'^\?'), ''),
      ).queryParametersAll;
    } on FormatException {
      return const {};
    }
  }

  static Uri withoutCredentials(Uri uri) {
    if (!uri.queryParametersAll.containsKey('app_portal')) return uri;
    final query = Map<String, List<String>>.from(uri.queryParametersAll)
      ..remove('app_portal')
      ..remove('invite');
    final fragment = _fragmentParameters(uri);
    final rest = Map<String, List<String>>.from(fragment)..remove('invite');
    return uri.replace(
      query: query.isEmpty ? '' : Uri(queryParameters: query).query,
      fragment: fragment.containsKey('invite')
          ? (rest.isEmpty ? '' : Uri(queryParameters: rest).query)
          : uri.fragment,
    );
  }
}

KorlixPortalLaunch? captureKorlixPortalLaunch() {
  final uri = Uri.base;
  final launch = KorlixPortalLaunch.parse(uri);
  final clean = KorlixPortalLaunch.withoutCredentials(uri);
  if (clean != uri) platform.replacePortalLaunchUri(clean);
  return launch;
}
