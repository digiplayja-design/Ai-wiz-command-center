import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_brain/brain_projection_navigation.dart';

const _renderer = 'https://api.example.com/brain-projection/earth.html';
const _document =
    'file:///android_asset/flutter_assets/assets/web/projection.html';

void main() {
  test('provider link families accept only maps views and legal pages', () {
    for (final url in [
      'https://www.google.com/maps',
      'https://www.google.com:443/maps/',
      'https://maps.google.com/maps?ll=40.7,-74&z=16&t=k&hl=en&gl=US&mapclient=apiv3',
      'https://www.google.com/maps/@?api=1&map_action=map&center=-33.7%2C150.3&zoom=12&basemap=terrain&layer=none',
      'https://maps.google.com/help/terms_maps/',
      'https://www.google.com/intl/en_US/help/terms_maps.html',
      'https://www.google.com/intl/en/help/legalnotices_maps/',
      'https://policies.google.com/terms?hl=en-US',
      'https://policies.google.com/privacy#infocollect',
    ]) {
      expect(projectionProviderLink(url), isNotNull, reason: url);
    }
  });

  test('provider link policy rejects unsafe or unrelated destinations', () {
    for (final url in [
      'http://www.google.com/maps',
      'javascript:alert(1)',
      'file:///maps',
      '//www.google.com/maps',
      'https://www.google.com.evil.example/maps',
      'https://wwwgoogle.com/maps',
      'https://www.google.com./maps',
      'https://google.com/maps',
      'https://maps.googleapis.com/maps',
      'https://evil.example@www.google.com/maps',
      'https://@www.google.com/maps',
      'https://www.google.com@evil.example/maps',
      'https://www.google.com:444/maps',
      'https://www.google.com:80/maps',
      'https://www.g%6fogle.com/maps',
      'https://www.google.com\\@evil.example/maps',
      ' https://www.google.com/maps',
      'https://www.google.com/maps\n',
      'https://www.google.com/maps\u0000',
      'https://www.google.com/maps\u00a0',
      'https://www.google.com/maps?hl=en%0d%0a',
      'https://www.google.com/maps?hl=en%20US',
      'https://www.google.com/maps?hl=en%255c',
      'https://www.google.com/maps?hl=en%ZZ',
      'https://www.google.com/%6daps',
      'https://www.google.com/url/../maps',
      'https://www.google.com/maps/../url',
      'https://www.google.com/maps/%2e%2e/url',
      'https://www.google.com/maps%2fsearch',
      'https://www.google.com/url?q=https://evil.example',
      'https://www.google.com/search?q=anything',
      'https://www.google.com/maps/search/?api=1&query=anything',
      'https://www.google.com/maps/dir/?api=1',
      'https://www.google.com/maps/api/js',
      'https://www.google.com/maps/embed',
      'https://www.google.com/accounts',
      'https://accounts.google.com/ServiceLogin',
      'https://policies.google.com/maps',
      'https://www.google.com/privacy',
      'https://www.google.com/maps?url=https://evil.example',
      'https://policies.google.com/privacy?continue=https://evil.example',
      'https://www.google.com/maps?hl=en&hl=de',
      'https://www.google.com/maps?center=91,0',
      'https://www.google.com/maps?center=0,-181',
      'https://www.google.com/maps?center=NaN,0',
      'https://www.google.com/maps?zoom=22',
      'https://www.google.com/maps?zoom=1.5',
      'https://www.google.com/maps/@?api=1&map_action=pano',
      'https://www.google.com/maps#https://evil.example',
      'https://policies.google.com/privacy#https://evil.example',
      'https://policies.google.com/privacy?hl=${'a' * 2048}',
    ]) {
      expect(projectionProviderLink(url), isNull, reason: url);
      expect(
        projectionNavigationPolicy(url: url, isMainFrame: true),
        ProjectionNavigation.block,
        reason: url,
      );
    }
  });

  test('provider popups are handled before Android/WK frame routing', () {
    for (final isMainFrame in [true, false]) {
      expect(
        projectionNavigationPolicy(
          url: 'https://policies.google.com/terms',
          isMainFrame: isMainFrame,
          rendererUrl: _renderer,
          bundledDocumentUrl: _document,
        ),
        ProjectionNavigation.external,
      );
      expect(
        projectionNavigationPolicy(
          url: 'https://maps.google.com/maps?ll=40.7,-74&z=16',
          isMainFrame: isMainFrame,
        ),
        ProjectionNavigation.external,
      );
    }
  });

  test('only the bundled asset can load as the local main document', () {
    final ios =
        'file:///app/Runner.app/Frameworks/App.framework/flutter_assets/assets/web/projection.html';
    expect(isBundledProjectionDocument(_document), isTrue);
    expect(isBundledProjectionDocument(ios), isTrue);
    expect(
      projectionNavigationPolicy(url: _document, isMainFrame: true),
      ProjectionNavigation.allow,
    );
    for (final url in [
      _renderer,
      'about:blank',
      'https://maps.google.com/maps/api/js',
      'file:///other/assets/web/projection.html',
      'file:///other/flutter_assets/assets/web/projection.html',
      'file://remote/flutter_assets/assets/web/projection.html',
      'file:///android_asset/other/../flutter_assets/assets/web/projection.html',
      'file:///android_asset/%66lutter_assets/assets/web/projection.html',
      '$_document?nonce=other',
      '$_document#other',
    ]) {
      expect(
        projectionNavigationPolicy(
          url: url,
          isMainFrame: true,
          rendererUrl: _renderer,
          bundledDocumentUrl: _document,
        ),
        ProjectionNavigation.block,
        reason: url,
      );
      expect(
        isBundledProjectionDocument(url, expectedUrl: _document),
        isFalse,
        reason: 'Only the pinned document receives the nonce: $url',
      );
    }
  });

  test('only exact configured renderer and CSP Google subframes may load', () {
    for (final url in [
      _renderer,
      'about:blank',
      'https://www.google.com/maps/embed?fixture=1',
      'https://maps.google.com/maps/api/js',
      'https://maps.google.com:443/maps/api/js',
      'https://nested.maps.google.com/frame',
    ]) {
      expect(
        projectionNavigationPolicy(
          url: url,
          isMainFrame: false,
          rendererUrl: _renderer,
        ),
        ProjectionNavigation.allow,
        reason: url,
      );
    }
    for (final url in [
      _document,
      'https://api.example.com/brain-projection/earth.html?other=1',
      'https://api.example.com/brain-projection/earth.html#other',
      'https://other.example.com/brain-projection/earth.html',
      'https://api.example.com/other',
      'about:srcdoc',
      'http://www.google.com/frame',
      'https://google.com/frame',
      'https://maps.google.com.evil.example/frame',
      'https://evilgoogle.com/frame',
      'https://maps.google.com./frame',
      'https://-maps.google.com/frame',
      'https://maps..google.com/frame',
      'https://@maps.google.com/frame',
      'https://maps.google.com:8443/frame',
      'https://maps.google.com/frame%0a',
      'https://maps.google.com/${'x' * 4096}',
    ]) {
      expect(
        projectionNavigationPolicy(
          url: url,
          isMainFrame: false,
          rendererUrl: _renderer,
        ),
        ProjectionNavigation.block,
        reason: url,
      );
    }
  });

  test(
    'external launcher suppresses concurrent and rapid duplicate callbacks',
    () async {
      var now = DateTime.utc(2026, 11, 8);
      final completion = Completer<bool>();
      final opened = <Uri>[];
      final launcher = ProjectionProviderLinkLauncher(
        now: () => now,
        launch: (uri) {
          opened.add(uri);
          return opened.length == 1 ? completion.future : Future.value(true);
        },
      );
      const terms = 'https://policies.google.com/terms';
      final first = launcher.open(terms);
      now = now.add(const Duration(seconds: 3));
      expect(await launcher.open(terms), isNull, reason: 'Still in flight');
      completion.complete(true);
      expect(await first, isTrue);
      expect(await launcher.open(terms), isTrue);
      expect(await launcher.open(terms), isNull, reason: 'Duplicate callback');
      expect(
        await launcher.open('https://policies.google.com/privacy'),
        isNull,
        reason: 'Rapid taps cannot launch several external applications',
      );
      now = now.add(const Duration(seconds: 2));
      expect(await launcher.open(terms), isTrue);
      expect(opened, hasLength(3));
      launcher.dispose();
      now = now.add(const Duration(seconds: 3));
      expect(await launcher.open(terms), isNull);
      expect(opened, hasLength(3));
    },
  );

  test(
    'external launcher revalidates input and handles platform failure',
    () async {
      var now = DateTime.utc(2026, 11, 8);
      var calls = 0;
      final launcher = ProjectionProviderLinkLauncher(
        now: () => now,
        launch: (_) async {
          calls++;
          if (calls == 1) throw StateError('No external handler');
          return false;
        },
      );
      expect(await launcher.open('https://evil.example/'), isNull);
      expect(calls, 0);
      expect(await launcher.open('https://policies.google.com/terms'), isFalse);
      now = now.add(const Duration(seconds: 2));
      expect(
        await launcher.open('https://policies.google.com/privacy'),
        isFalse,
      );
      expect(calls, 2);
    },
  );
}
