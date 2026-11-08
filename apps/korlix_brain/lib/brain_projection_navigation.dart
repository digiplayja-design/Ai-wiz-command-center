/// Navigation decisions for the separate Projection WebView. Provider pages
/// never become the local document that receives the native session nonce.
enum ProjectionNavigation { allow, block, external }

bool _cleanUrl(String value, {int maximum = 4096}) =>
    value.isNotEmpty &&
    value.length <= maximum &&
    !value.codeUnits.any((c) => c <= 0x20 || c >= 0x7f || c == 0x5c) &&
    !RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(value);

Uri? _httpsUrl(String value) {
  if (!_cleanUrl(value) || !value.startsWith('https://')) return null;
  try {
    // URI parsers can normalize encoded controls, credentials or host spelling.
    // Reject those inputs before comparing canonical host/path values.
    if (!_cleanUrl(Uri.decodeComponent(value))) return null;
    final authority = value.substring(8).split(RegExp(r'[/#?]')).first;
    if (authority.contains('@') || authority.contains('%')) return null;
    final uri = Uri.parse(value);
    if (uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      return null;
    }
    return uri;
  } on FormatException {
    return null;
  }
}

final _locale = RegExp(r'^[a-zA-Z]{2,3}(?:[-_][a-zA-Z0-9]{2,8}){0,2}$');

bool _number(String value, double min, double max, {bool integer = false}) {
  if (!RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(value)) return false;
  final number = double.tryParse(value);
  return number != null &&
      number.isFinite &&
      number >= min &&
      number <= max &&
      (!integer || number == number.roundToDouble());
}

bool _coordinates(String value) {
  final parts = value.split(',');
  return parts.length == 2 &&
      _number(parts[0], -90, 90) &&
      _number(parts[1], -180, 180);
}

bool _allowedQuery(Uri uri, {required bool map}) {
  for (final entry in uri.queryParametersAll.entries) {
    if (entry.value.length != 1) return false;
    final value = entry.value.single;
    final allowed = switch (entry.key) {
      'hl' => _locale.hasMatch(value),
      'gl' => RegExp(r'^[a-zA-Z]{2}$').hasMatch(value),
      'api' when map => value == '1',
      'map_action' when map => value == 'map',
      'll' || 'sll' || 'center' when map => _coordinates(value),
      'z' when map => _number(value, 0, 23),
      'zoom' when map => _number(value, 0, 21, integer: true),
      't' when map => const {'m', 'k', 'h', 'p'}.contains(value),
      'basemap' when map => const {
        'roadmap',
        'satellite',
        'terrain',
      }.contains(value),
      'layer' when map => const {
        'none',
        'transit',
        'traffic',
        'bicycling',
      }.contains(value),
      'mapclient' when map => value == 'apiv3',
      _ => false,
    };
    if (!allowed) return false;
  }
  return true;
}

/// Only documented map-view and legal destinations may leave the WebView.
/// Search, directions, account, service and redirect endpoints are not links
/// in this policy. The Google Maps URLs guide defines /maps/@ map views;
/// /maps and the ll/z/mapclient parameters accommodate provider logo links.
Uri? projectionProviderLink(String value) {
  if (value.length > 2048) return null;
  final uri = _httpsUrl(value);
  if (uri == null ||
      !const {
        'www.google.com',
        'maps.google.com',
        'policies.google.com',
      }.contains(uri.host)) {
    return null;
  }
  final rawPath = value
      .substring(8)
      .replaceFirst(RegExp(r'^[^/?#]*'), '')
      .split(RegExp(r'[?#]'))
      .first;
  // Do not let encoded separators or normalized dot segments widen a family.
  if (rawPath != uri.path || rawPath.contains('%')) return null;
  final map =
      uri.host != 'policies.google.com' &&
      const {'/maps', '/maps/', '/maps/@', '/maps/@/'}.contains(uri.path);
  final legal = uri.host == 'policies.google.com'
      ? const {'/terms', '/terms/', '/privacy', '/privacy/'}.contains(uri.path)
      : RegExp(
          r'^/(?:intl/[a-zA-Z]{2,3}(?:[-_][a-zA-Z0-9]{2,8}){0,2}/)?help/(?:terms_maps|legalnotices_maps)(?:\.html)?/?$',
        ).hasMatch(uri.path);
  if ((!map && !legal) || !_allowedQuery(uri, map: map)) return null;
  if (uri.hasFragment &&
      (map || !RegExp(r'^[a-zA-Z0-9_-]{0,80}$').hasMatch(uri.fragment))) {
    return null;
  }
  return uri;
}

bool isBundledProjectionDocument(String value, {String? expectedUrl}) {
  if (!_cleanUrl(value) || !value.startsWith('file:///')) return false;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.host.isNotEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasQuery ||
      uri.hasFragment ||
      !uri.path.endsWith('/flutter_assets/assets/web/projection.html') ||
      RegExp(
        r'/(?:\.|\.\.)(?:/|$)|%(?:2e|2f|5c)',
        caseSensitive: false,
      ).hasMatch(value)) {
    return false;
  }
  return expectedUrl == null || value == expectedUrl;
}

ProjectionNavigation projectionNavigationPolicy({
  required String url,
  required bool isMainFrame,
  String? rendererUrl,
  String? bundledDocumentUrl,
}) {
  // Android reports provider popups as main-frame requests. WKWebView can
  // report target=_blank as a nil-target/non-main-frame request. Check first.
  if (projectionProviderLink(url) != null) return ProjectionNavigation.external;
  if (isMainFrame) {
    return isBundledProjectionDocument(url, expectedUrl: bundledDocumentUrl)
        ? ProjectionNavigation.allow
        : ProjectionNavigation.block;
  }
  if (url == 'about:blank') return ProjectionNavigation.allow;
  final uri = _httpsUrl(url);
  if (uri == null) return ProjectionNavigation.block;
  if (url == rendererUrl &&
      uri.path == '/brain-projection/earth.html' &&
      !uri.hasQuery &&
      !uri.hasFragment) {
    return ProjectionNavigation.allow;
  }
  // Matches the hosted renderer's frame-src https://*.google.com CSP. This is
  // a subframe permission only, never permission to replace the local root.
  final googleSubframe =
      uri.host.endsWith('.google.com') &&
      uri.host
          .split('.')
          .every(
            (label) =>
                RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$')
                    .hasMatch(label),
          );
  return googleSubframe
      ? ProjectionNavigation.allow
      : ProjectionNavigation.block;
}

/// Coalesces duplicate platform popup callbacks and rapid repeated taps.
/// A blocked/duplicate request returns null; an actual failed launch is false.
class ProjectionProviderLinkLauncher {
  ProjectionProviderLinkLauncher({
    required Future<bool> Function(Uri) launch,
    DateTime Function()? now,
  }) : _launch = launch,
       _now = now ?? DateTime.now;

  final Future<bool> Function(Uri) _launch;
  final DateTime Function() _now;
  DateTime? _lastAttempt;
  bool _pending = false;
  bool _disposed = false;

  Future<bool?> open(String value) async {
    final uri = projectionProviderLink(value);
    final now = _now();
    if (_disposed ||
        uri == null ||
        _pending ||
        (_lastAttempt != null &&
            now.difference(_lastAttempt!) < const Duration(seconds: 2))) {
      return null;
    }
    _pending = true;
    _lastAttempt = now;
    try {
      return await _launch(uri);
    } catch (_) {
      return false;
    } finally {
      _pending = false;
    }
  }

  void dispose() => _disposed = true;
}
