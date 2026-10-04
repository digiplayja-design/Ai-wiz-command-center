import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/contacts_crm/contacts_client.dart';
import 'package:ai_wiz_command_center/contacts_crm/contacts_style.dart';
import 'package:ai_wiz_command_center/contacts_crm/crm_directory_screen.dart';
import 'package:ai_wiz_command_center/contacts_crm/contacts_screen.dart';
import 'contacts_screen_test.dart' as fixtures;

class Fixture {
  bool failSave = false;
  final calls = <({String method, String path, CrmJson body})>[];
  CrmJson settings = {
    'version': 1,
    'enabled': false,
    'filters': {
      'q': '',
      'category': '',
      'city': '',
      'country': '',
      'verified_only': false,
    },
    'imported_total': 0,
  };
  late final client = ContactsClient(
    backendBaseUrl: 'https://fixture.invalid',
    headersBuilder: () => {},
    client: MockClient((r) async {
      final body = r.body.isEmpty
          ? <String, dynamic>{}
          : crmMap(jsonDecode(r.body));
      calls.add((method: r.method, path: r.url.path, body: body));
      if (r.url.path.endsWith('/preview'))
        return reply({
          'businesses': [
            {
              'id': 'b',
              'name': 'Kingston Plumbing',
              'category': 'Construction & Trades',
              'city': 'Kingston',
              'country': 'Jamaica',
              'email': 'public@example.test',
              'verified': true,
            },
          ],
          'available_in_batch': 1,
          'more_available': false,
          'preview_only': true,
        });
      if (r.method == 'PUT') {
        if (failSave)
          return http.Response(
            jsonEncode({'error': 'Directory settings changed. Refresh first.'}),
            409,
          );
        settings = {
          ...settings,
          'version': (settings['version'] as int) + 1,
          'filters': body['filters'],
          'enabled': false,
        };
        return reply({'settings': settings});
      }
      if (r.url.path.endsWith('/actions')) {
        if (body['action'] == 'run') {
          settings = {...settings, 'imported_total': 1};
          return reply({'imported': 1, 'skipped': 0});
        }
        settings = {
          ...settings,
          'version': (settings['version'] as int) + 1,
          'enabled': body['enabled'],
        };
        return reply({'settings': settings});
      }
      return reply({
        'settings': settings,
        'categories': ['Construction & Trades', 'Food & Drink'],
      });
    }),
  );
  http.Response reply(CrmJson v) => http.Response(jsonEncode(v), 200);
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'First enable saves default filters after confirmation, then uses the returned version',
    (t) async {
      final f = Fixture();
      f.settings['version'] = 0;
      await t.pumpWidget(
        MaterialApp(home: CrmDirectoryScreen(client: f.client)),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<OutlinedButton>(find.byKey(const Key('directory-toggle')))
            .onPressed,
        isNotNull,
      );
      await tap(t, find.byKey(const Key('directory-toggle')));
      await tap(t, find.text('Cancel'));
      expect(f.calls.where((c) => c.method != 'GET'), isEmpty);
      await tap(t, find.byKey(const Key('directory-toggle')));
      await tap(t, find.text('Enable auto-pull').last);
      final writes = f.calls.where((c) => c.method != 'GET').toList();
      expect(writes.length, 2);
      expect(writes[0].method, 'PUT');
      expect(writes[0].body['version'], 0);
      expect(writes[0].body['filters']['city'], '');
      expect(writes[1].body['version'], 1);
      expect(writes[1].body['enabled'], true);
      expect(f.settings['enabled'], true);
      await t.pumpWidget(const SizedBox());
      f.client.dispose();
    },
  );
  testWidgets(
    'Changed filters are saved on enable, and Pause works without saving or discarding edits',
    (t) async {
      final f = Fixture();
      f.settings['enabled'] = true;
      await t.pumpWidget(
        MaterialApp(home: CrmDirectoryScreen(client: f.client)),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('directory-city')), 'Kingston');
      await tap(t, find.byKey(const Key('directory-toggle')));
      expect(f.settings['enabled'], false);
      expect(f.calls.where((c) => c.method == 'PUT'), isEmpty);
      expect(
        t
            .widget<TextField>(find.byKey(const Key('directory-city')))
            .controller!
            .text,
        'Kingston',
      );
      await tap(t, find.byKey(const Key('directory-toggle')));
      await tap(t, find.text('Enable auto-pull').last);
      expect(f.settings['enabled'], true);
      expect(f.settings['filters']['city'], 'Kingston');
      expect(f.calls.last.body['version'], 3);
      await t.pumpWidget(const SizedBox());
      f.client.dispose();
    },
  );
  testWidgets('A failed save cannot enable or run imports', (t) async {
    final f = Fixture();
    f.settings['version'] = 0;
    f.failSave = true;
    await t.pumpWidget(MaterialApp(home: CrmDirectoryScreen(client: f.client)));
    await t.pumpAndSettle();
    await tap(t, find.byKey(const Key('directory-toggle')));
    await tap(t, find.text('Enable auto-pull').last);
    expect(f.calls.where((c) => c.path.endsWith('/actions')), isEmpty);
    expect(find.textContaining('Directory settings changed'), findsOneWidget);
    expect(
      t
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Refresh import status',
            ),
          )
          .onPressed,
      isNotNull,
    );
    await t.pumpWidget(const SizedBox());
    f.client.dispose();
  });
  for (final width in [390.0, 1024.0])
    testWidgets('Listing filters, preview and controls fit width $width', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = Fixture();
      await t.pumpWidget(
        MaterialApp(
          theme: CrmStyle.theme,
          home: CrmDirectoryScreen(client: f.client),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.enterText(find.byKey(const Key('directory-city')), 'Kingston');
      await t.enterText(find.byKey(const Key('directory-country')), 'Jamaica');
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('directory-pull-now')))
            .onPressed,
        isNotNull,
      );
      await tap(t, find.byKey(const Key('directory-preview')));
      expect(f.calls.last.body['filters']['city'], 'Kingston');
      expect(f.calls.where((c) => c.path.endsWith('/actions')), isEmpty);
      expect(find.text('Kingston Plumbing'), findsOneWidget);
      expect(t.takeException(), isNull);
      await tap(t, find.byKey(const Key('directory-save')));
      expect(f.settings['enabled'], false);
      expect(f.settings['filters']['country'], 'Jamaica');
      await t.pumpWidget(const SizedBox());
      f.client.dispose();
    });
  testWidgets(
    'Auto-pull and immediate import require confirmation and pin saved version',
    (t) async {
      t.view.physicalSize = const Size(1000, 1500);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final f = Fixture();
      await t.pumpWidget(
        MaterialApp(
          theme: CrmStyle.theme,
          home: CrmDirectoryScreen(client: f.client),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, find.byKey(const Key('directory-toggle')));
      await tap(t, find.text('Cancel'));
      expect(f.calls.where((c) => c.path.endsWith('/actions')), isEmpty);
      await tap(t, find.byKey(const Key('directory-toggle')));
      await tap(t, find.text('Enable auto-pull').last);
      final enable = f.calls.last.body;
      expect(enable, {
        'action': 'toggle',
        'version': 1,
        'enabled': true,
        'confirmed': true,
      });
      await tap(t, find.byKey(const Key('directory-pull-now')));
      await tap(t, find.text('Import leads'));
      final run = f.calls.firstWhere((c) => c.body['action'] == 'run').body;
      expect(run, {'action': 'run', 'version': 2, 'confirmed': true});
      expect(find.textContaining('1 leads added'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      f.client.dispose();
    },
  );
  testWidgets(
    'CRM opens directory imports and returns to the imported-source filter',
    (t) async {
      t.view.physicalSize = const Size(1024, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final queries = <String>[];
      final client = fixtures.api((r) {
        if (r.url.path.endsWith('/directory-sync'))
          return fixtures.result({
            'settings': {'version': 0, 'enabled': false, 'filters': {}},
            'categories': ['Food & Drink'],
          });
        if (r.url.path == '/api/contacts')
          queries.add(r.url.queryParameters['source'] ?? '');
        return fixtures.normal(r);
      });
      await t.pumpWidget(MaterialApp(home: ContactsScreen(client: client)));
      await t.pumpAndSettle();
      await tap(t, find.byKey(const Key('crm-directory-sync')));
      expect(find.text('CRM · Auto-pull listings'), findsOneWidget);
      await tap(t, find.text('View imported contacts'));
      expect(queries.last, 'directory');
      expect(t.takeException(), isNull);
    },
  );
}
