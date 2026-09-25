import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_client.dart';
import 'package:ai_wiz_command_center/funnel_studio/funnel_screen.dart';
import 'funnel_studio_test.dart' as studio;
import 'funnel_images_test.dart' as images;

http.Response reply(Map<String, dynamic> d, [int status = 200]) =>
    http.Response(
      jsonEncode(d),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
Map<String, dynamic> row(String name) => {...studio.fixture(), 'name': name};
Map<String, dynamic> list(String name) => {
  'funnels': [row(name)],
  'ai_ready': true,
};
FunnelClient client(FutureOr<http.Response> Function(http.Request) fn) =>
    FunnelClient(
      backendBaseUrl: 'https://example.com',
      headersBuilder: () => {},
      client: MockClient((r) async => fn(r)),
    );
Future<void> app(WidgetTester t, FunnelClient c, {bool settle = true}) async {
  await t.pumpWidget(MaterialApp(home: FunnelScreen(client: c)));
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump();
  }
}

Future<void> tap(WidgetTester t, String text, {bool settle = true}) async {
  final f = find.text(text);
  await t.ensureVisible(f);
  await t.tap(f);
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump();
  }
}

Future<void> deny(FunnelClient c) =>
    expectLater(c.request('GET', '/denied'), throwsA(isA<FunnelException>()));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'K196 a denied workspace cannot be restored by an old list response',
    (t) async {
      final pending = Completer<http.Response>();
      final c = client(
        (r) => r.url.path.endsWith('/denied')
            ? reply({'error': 'Enterprise required'}, 403)
            : pending.future,
      );
      await app(t, c, settle: false);
      await deny(c);
      await t.pump();
      pending.complete(reply(list('Private old workspace')));
      await t.pumpAndSettle();
      expect(find.text('Enterprise access required'), findsOneWidget);
      expect(find.text('Private old workspace'), findsNothing);
      expect(find.text('Open studio'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'K196 replacement client ignores late data and access failures from the previous client',
    (t) async {
      final pending = Completer<http.Response>();
      final old = client(
        (r) => r.url.path.endsWith('/denied')
            ? reply({'error': 'Expired'}, 401)
            : pending.future,
      );
      await app(t, old, settle: false);
      final fresh = client((r) => reply(list('Current workspace')));
      await app(t, fresh);
      pending.complete(reply(list('Old workspace')));
      await t.pumpAndSettle();
      await deny(old);
      await t.pumpAndSettle();
      expect(find.text('Current workspace'), findsOneWidget);
      expect(find.text('Old workspace'), findsNothing);
      expect(find.text('Enterprise access required'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  for (final action in ['Review & publish', 'Pause page']) {
    testWidgets(
      'K196 $action confirmation closes on client replacement without writing',
      (t) async {
        final writes = <http.Request>[];
        final old = client((r) {
          if (r.method != 'GET') writes.add(r);
          return reply({
            'funnels': [
              {...row('Original'), 'state': 'published'},
            ],
            'ai_ready': true,
          });
        });
        await app(t, old);
        await tap(t, 'Open studio');
        await tap(t, action);
        expect(find.byType(AlertDialog), findsOneWidget);
        await app(
          t,
          client((r) {
            if (r.method != 'GET') writes.add(r);
            return reply(list('Replacement'));
          }),
        );
        expect(find.byType(AlertDialog), findsNothing);
        expect(writes, isEmpty);
        expect(find.text('Replacement'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'K196 access loss closes publish confirmation and preserves other listeners',
    (t) async {
      var external = 0, posts = 0;
      final c = client((r) {
        if (r.method == 'POST') posts++;
        return r.url.path.endsWith('/denied')
            ? reply({'error': 'Expired'}, 403)
            : reply(list('Private source'));
      });
      c.onAccessDenied = () => external++;
      await app(t, c);
      await tap(t, 'Open studio');
      await tap(t, 'Review & publish');
      await deny(c);
      await t.pumpAndSettle();
      expect(external, 1);
      expect(posts, 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Enterprise access required'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'K196 late save cannot replace current data or clear the newer loading state',
    (t) async {
      final save = Completer<http.Response>(),
          newList = Completer<http.Response>();
      final old = client(
        (r) => r.method == 'PUT' ? save.future : reply(list('Old page')),
      );
      await app(t, old);
      await tap(t, 'Open studio');
      final brand = find.byKey(const ValueKey('1:brand'));
      await t.ensureVisible(brand);
      await t.enterText(brand, 'Changed old brand');
      await t.pump();
      await tap(t, 'Save draft', settle: false);
      await app(t, client((r) => newList.future), settle: false);
      save.complete(
        reply({
          'funnel': {...row('Late saved page'), 'version': 2},
        }),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Late saved page'), findsNothing);
      newList.complete(reply(list('New page')));
      await t.pumpAndSettle();
      expect(find.text('New page'), findsOneWidget);
      expect(find.text('Draft saved.'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('K196 late generation cannot replace the new workspace draft', (
    t,
  ) async {
    final generated = Completer<http.Response>();
    final old = client(
      (r) => r.url.path.endsWith('/generate')
          ? generated.future
          : reply(list('Old page')),
    );
    await app(t, old);
    await tap(t, 'Open studio');
    await tap(t, 'Ask NOVA');
    await t.enterText(
      find.widgetWithText(TextField, 'Your brief'),
      'Draft a local offer',
    );
    await tap(t, 'Generate draft', settle: false);
    await app(t, client((r) => reply(list('New page'))));
    generated.complete(
      reply({
        'document': {
          ...studio.fixture()['draft'],
          'headline': 'Late generated headline',
        },
      }),
    );
    await t.pumpAndSettle();
    await tap(t, 'Open studio');
    expect(find.text('Late generated headline'), findsNothing);
    expect(find.text('UNSAVED EDITS'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'K196 a create request finishing after scope replacement does not open its old draft',
    (t) async {
      final created = Completer<http.Response>();
      final old = client(
        (r) => r.method == 'POST' ? created.future : reply(list('Original')),
      );
      await app(t, old);
      await tap(t, 'Open studio');
      await tap(t, 'Duplicate draft');
      await tap(t, 'Create draft', settle: false);
      await app(t, client((r) => reply(list('New workspace'))));
      created.complete(reply({'funnel': row('Late duplicate')}));
      await t.pumpAndSettle();
      expect(find.text('New workspace'), findsOneWidget);
      expect(find.text('Late duplicate'), findsNothing);
      expect(find.text('Duplicate your draft'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('K196 a missing saved funnel returns to the current list', (
    t,
  ) async {
    var n = 0;
    await app(
      t,
      client(
        (r) => reply(
          ++n == 1 ? list('Removed page') : {'funnels': [], 'ai_ready': true},
        ),
      ),
    );
    await tap(t, 'Open studio');
    await tap(t, 'Reload saved');
    expect(find.text('Review & publish'), findsNothing);
    expect(
      find.text('This funnel is no longer available. Choose a saved funnel.'),
      findsOneWidget,
    );
    expect(find.textContaining('Bad state'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'K196 leaving a borrowed client does not dispose its other consumers',
    (t) async {
      var notifications = 0;
      final c = client(
        (r) => r.url.path.endsWith('/denied')
            ? reply({'error': 'Expired'}, 401)
            : reply(list('Page')),
      );
      c.addAccessDeniedListener(() => notifications++);
      await app(t, c);
      await t.pumpWidget(const SizedBox());
      await deny(c);
      expect(notifications, 1);
      c.dispose();
    },
  );
  testWidgets(
    'K196 obsolete image selection closes its nested delete confirmation without deleting',
    (t) async {
      final png = await t.runAsync(
        () => File('assets/branding/korlix_full_logo.png').readAsBytes(),
      );
      var deletes = 0;
      final c = client((r) {
        if (r.method == 'DELETE') deletes++;
        if (r.url.path.endsWith('/images')) {
          return reply({
            'images': [images.asset],
            'used_bytes': 1000,
          });
        }
        if (r.url.path.endsWith('/images/${images.imageId}')) {
          return reply({'content': base64Encode(png!)});
        }
        return reply(list('Original workspace'));
      });
      await app(t, c);
      await tap(t, 'Open studio');
      await tap(t, 'Choose logo');
      await tap(t, 'Delete');
      expect(find.text('Delete unused image?'), findsOneWidget);
      await app(t, client((r) => reply(list('Replacement workspace'))));
      expect(find.text('Delete unused image?'), findsNothing);
      expect(find.text('KORLIX logo.png'), findsNothing);
      expect(find.text('Replacement workspace'), findsOneWidget);
      expect(deletes, 0);
      expect(t.takeException(), isNull);
    },
  );
}
