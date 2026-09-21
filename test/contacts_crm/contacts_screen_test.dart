import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/contacts_crm/contacts_client.dart';
import 'package:ai_wiz_command_center/contacts_crm/contacts_screen.dart';
import 'package:ai_wiz_command_center/contacts_crm/contact_editor.dart';
import 'package:ai_wiz_command_center/contacts_crm/contacts_style.dart';

const sample = {
  'id': '00000000-0000-4000-8000-000000000002',
  'name': 'Jordan Lee',
  'email': 'jordan@example.com',
  'phone': '+1 415 555 0123',
  'company': 'Northstar Studio',
  'category': 'customer',
  'source': 'spreadsheet',
  'favorite': true,
  'tags': ['VIP', 'Design partner'],
  'version': 4,
  'email_permission': 'transactional',
  'call_permission': 'allowed',
  'do_not_contact': false,
  'follow_up_on': '2026-09-24',
  'notes':
      'Discuss the fall launch and a new studio partnership. Prefers a short email before a call.',
};
final fixtures = <Map<String, dynamic>>[
  sample,
  {
    ...sample,
    'id': '2',
    'name': 'Alex Rivera',
    'category': 'friend',
    'company': 'Rivera Ventures',
    'email': 'alex@example.com',
    'favorite': false,
    'source': 'phone',
    'follow_up_on': null,
  },
  {
    ...sample,
    'id': '3',
    'name': 'Morgan Brooks',
    'category': 'family',
    'company': '',
    'email': 'morgan@example.com',
    'source': 'manual',
    'tags': [],
    'favorite': false,
    'follow_up_on': null,
  },
  {
    ...sample,
    'id': '4',
    'name': 'Priya Shah',
    'category': 'partner',
    'company': 'Orbit Creative',
    'email': 'priya@example.com',
    'source': 'email',
    'favorite': true,
    'follow_up_on': '2026-09-23',
  },
  {
    ...sample,
    'id': '5',
    'name': 'Emma Wilson',
    'category': 'lead',
    'company': 'Evergreen Labs',
    'email': 'emma@example.com',
    'source': 'spreadsheet',
    'favorite': false,
    'email_permission': 'none',
    'call_permission': 'none',
    'follow_up_on': '2026-09-25',
  },
  {
    ...sample,
    'id': '6',
    'name': 'Noah Chen',
    'category': 'customer',
    'company': 'Forma Architecture',
    'email': 'noah@example.com',
    'source': 'email',
    'favorite': false,
    'follow_up_on': '2026-09-28',
  },
  {
    ...sample,
    'id': '7',
    'name': 'Sofia Martinez',
    'category': 'vendor',
    'company': 'Framework Supply',
    'email': 'sofia@example.com',
    'source': 'manual',
    'favorite': false,
    'follow_up_on': null,
  },
  {
    ...sample,
    'id': '8',
    'name': 'Chris Taylor',
    'category': 'unknown',
    'company': '',
    'email': null,
    'phone': null,
    'source': 'facebook',
    'favorite': false,
    'email_permission': 'none',
    'call_permission': 'none',
    'follow_up_on': null,
  },
];
http.Response result(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json'},
);
ContactsClient api(FutureOr<http.Response> Function(http.Request) handle) =>
    ContactsClient(
      backendBaseUrl: 'https://test.invalid',
      headersBuilder: () => {'Authorization': 'Bearer test'},
      client: MockClient((r) async => await handle(r)),
    );
Future<http.Response> normal(http.Request req) async {
  if (req.url.path.endsWith('/capabilities')) {
    return result({'emailAgentId': 'nova'});
  }
  if (req.url.path.endsWith('/counts')) {
    return result({
      'total': 8,
      'categories': {
        'customer': 2,
        'friend': 1,
        'family': 1,
        'lead': 1,
        'partner': 1,
        'vendor': 1,
        'unknown': 1,
      },
    });
  }
  final q = req.url.queryParameters,
      rows = fixtures
          .where(
            (c) =>
                (q['category'] ?? '').isEmpty || c['category'] == q['category'],
          )
          .where(
            (c) =>
                (q['q'] ?? '').isEmpty ||
                c['name'].toString().toLowerCase().contains(
                  q['q']!.toLowerCase(),
                ),
          )
          .toList();
  return result({'contacts': rows, 'count': rows.length});
}

void viewport(WidgetTester tester, double width, {double height = 1100}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> capture(WidgetTester tester, String name) async {
  if (const bool.fromEnvironment('CRM_CAPTURE')) {
    await expectLater(
      find.byKey(const Key('capture')),
      matchesGoldenFile('/tmp/korlix-crm-$name.png'),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const font = String.fromEnvironment('CRM_FONT');
    if (font.isNotEmpty) {
      final loader = FontLoader('Roboto')
        ..addFont(
          Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
        );
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '${File(font).parent.path}/MaterialIcons-Regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        );
      await icons.load();
    }
  });
  testWidgets('Enterprise denial hides contacts and actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ContactsScreen(
          client: api((_) => result({'error': 'Enterprise required'}, 403)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Contacts CRM requires Enterprise.'), findsOneWidget);
    expect(find.byKey(const Key('new-contact')), findsNothing);
    expect(find.text('Jordan Lee'), findsNothing);
  });
  for (final width in [390.0, 1024.0, 1440.0]) {
    testWidgets('Workspace, editor and import fit width $width', (
      tester,
    ) async {
      viewport(tester, width);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: ContactsScreen(client: api(normal)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Total contacts'), findsOneWidget);
      await capture(tester, 'preview-${width.toInt()}');
      await tester.tap(find.byKey(const Key('new-contact')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (width == 1440) await capture(tester, 'editor-preview');
      await tester.tap(find.text('Save contact'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('edit-name')), 'Taylor Reed');
      await tester.tap(find.byKey(const Key('editor-tab-1')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('editor-tab-2')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-contacts')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Choose file'), findsOneWidget);
      if (width == 1440) await capture(tester, 'import-preview');
    });
  }
  testWidgets('Search, category and smart views request filtered data', (
    tester,
  ) async {
    viewport(tester, 390);
    final seen = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ContactsScreen(
          client: api((r) {
            seen.add(r.url);
            return normal(r);
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('contact-search')), 'Jordan');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(seen.any((u) => u.queryParameters['q'] == 'Jordan'), isTrue);
    expect(find.text('Alex Rivera'), findsNothing);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Customer 2'));
    await tester.tap(find.text('Customer 2'));
    await tester.pumpAndSettle();
    expect(
      seen.any((u) => u.queryParameters['category'] == 'customer'),
      isTrue,
    );
    expect(find.text('Alex Rivera'), findsNothing);
    await tester.tap(find.byTooltip('Open workspace navigation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(
      seen.any((u) => u.queryParameters['segment'] == 'favorites'),
      isTrue,
    );
  });
  testWidgets(
    'Profile opens on mobile, with reachable editing and Nova permissions',
    (tester) async {
      viewport(tester, 390, height: 844);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: ContactsScreen(client: api(normal)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'phone-preview');
      await tester.tap(find.text('Jordan Lee'));
      await tester.pumpAndSettle();
      expect(find.text('CONTACT STUDIO'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'mobile-studio-preview');
      final edit = find.text('Edit contact');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edit-name')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Bulk categorization updates selected record with its version', (
    tester,
  ) async {
    final writes = <http.Request>[];
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ContactsScreen(
          client: api((r) {
            if (r.method == 'PUT') {
              writes.add(r);
              return result({'contact': jsonDecode(r.body)});
            }
            return normal(r);
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final selection = find.descendant(
      of: find.byKey(ValueKey('contact-row-${sample['id']}')),
      matching: find.byType(Checkbox),
    );
    await tester.ensureVisible(selection);
    await tester.tap(selection);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Set status'));
    await tester.tap(find.text('Set status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Partner').last);
    await tester.pumpAndSettle();
    expect(writes.length, 1);
    expect(writes.single.url.path.endsWith('/${sample['id']}'), isTrue);
    final body = jsonDecode(writes.single.body);
    expect(body['category'], 'partner');
    expect(body['version'], 4);
    expect(body['email_permission'], 'transactional');
  });
  testWidgets('Ctrl K focuses search; compact rows keep controls usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ContactsScreen(client: api(normal)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('contact-search')))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await tester.tap(find.byTooltip('Compact spacing'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Comfortable spacing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Editor saves changes across sections without losing record identity',
    (tester) async {
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: CrmStyle.theme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ContactEditor(
                    contact: sample,
                    initialSection: 1,
                    onSave: (c) async {
                      saved = c;
                    },
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('edit-notes')),
        'Follow up about the launch.',
      );
      await tester.tap(find.byKey(const Key('editor-tab-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save contact'));
      await tester.pumpAndSettle();
      expect(saved?['notes'], 'Follow up about the launch.');
      expect(saved?['id'], sample['id']);
      expect(saved?['version'], 4);
      expect(saved?['name'], 'Jordan Lee');
    },
  );
  testWidgets(
    'Email import previews and imports only explicitly selected contacts',
    (tester) async {
      Map<String, dynamic>? imported;
      viewport(tester, 1024);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ContactsScreen(
            client: api((r) {
              if (r.url.path.endsWith('/imports/email-preview')) {
                return result({
                  'contacts': [
                    {
                      ...sample,
                      'email_permission': 'none',
                      'call_permission': 'none',
                    },
                    {
                      ...fixtures[1],
                      'email_permission': 'none',
                      'call_permission': 'none',
                    },
                  ],
                  'duplicates': 1,
                  'errors': [],
                });
              }
              if (r.url.path.endsWith('/imports') && r.method == 'POST') {
                imported = jsonDecode(r.body);
                return result({'imported': 1, 'duplicates': 0});
              }
              return normal(r);
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import-contacts')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Email').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use Nova Email contacts'));
      await tester.pumpAndSettle();
      expect(find.text('2 ready'), findsOneWidget);
      expect(find.text('1 duplicates'), findsOneWidget);
      final tile = find.widgetWithText(CheckboxListTile, 'Alex Rivera');
      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import 1 contacts'));
      await tester.pumpAndSettle();
      expect(imported?['confirmed'], true);
      expect((imported?['contacts'] as List).length, 1);
      expect(imported?['contacts'][0]['name'], 'Jordan Lee');
      expect(imported?['contacts'][0]['email_permission'], 'none');
    },
  );
  testWidgets('Access revocation clears previously loaded contacts', (
    tester,
  ) async {
    var allowed = true;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ContactsScreen(
          client: api(
            (r) => allowed
                ? normal(r)
                : result({'error': 'Enterprise required'}, 403),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Jordan Lee'), findsOneWidget);
    allowed = false;
    await tester.tap(find.byTooltip('Refresh contacts'));
    await tester.pumpAndSettle();
    expect(find.text('Jordan Lee'), findsNothing);
    expect(find.text('Contacts CRM requires Enterprise.'), findsOneWidget);
  });
}
