import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ai_wiz_command_center/directory/directory_client.dart';
import 'package:ai_wiz_command_center/directory/directory_screen.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _token(String user) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'https://fixture.test', 'sub': user, 'session_id': 'session-$user'}))).replaceAll('=', '')}.signature';

class _DirectoryStore {
  final revision = ValueNotifier(0);
  final mutations = <DirJson>[];
  String user = 'owner';
  DirJson? business;
  int submitFailures = 0;
  bool failRefreshAfterSubmit = false;
  Completer<void>? createGate, submitGate;

  DirJson existing({String state = 'draft'}) => {
    'id': 'fixture-business',
    'version': 7,
    'owner_name': 'Avery Lane',
    'state': state,
    'verification_state': 'none',
    'draft': {
      'name': 'Fixture Shop',
      'category': 'Other',
      'description': 'Fresh bread and friendly service in Kingston.',
      'phone': '+1 876 555 0123',
      'email': '',
      'city': 'Kingston',
      'country': 'Jamaica',
      'photos': <String>[],
    },
  };

  http.Response _response(DirJson data, [int status = 200]) => http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  late final client = DirectoryClient(
    backendBaseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': 'Bearer ${_token(user)}'},
    sessionChanges: revision,
    client: MockClient((request) async {
      final path = request.url.path.replaceFirst('/api/directory', '');
      if (request.method == 'GET' && path == '/me') {
        if (failRefreshAfterSubmit && business?['state'] == 'pending') {
          return _response({
            'error': 'Refresh is temporarily unavailable.',
          }, 503);
        }
        return _response({
          'businesses': [if (business != null) business],
          'isAdmin': false,
          'paymentsReady': false,
          'categories': ['Other'],
        });
      }
      if (request.method == 'GET' && path == '/owner/fixture-business') {
        return _response({
          'business': business,
          'assets': [],
          'membership': null,
        });
      }
      final body = dirMap(jsonDecode(request.body));
      mutations.add({'path': path, ...body});
      if (request.method == 'POST' && path == '/owner') {
        await createGate?.future;
        business = {
          ...existing(),
          'version': 1,
          'owner_name': body['owner_name'],
          'draft': body['details'],
        };
        return _response(business!);
      }
      if (request.method == 'POST' &&
          path == '/owner/fixture-business/action') {
        if (body['action'] == 'submit') {
          await submitGate?.future;
          if (submitFailures > 0) {
            submitFailures--;
            return _response({
              'error': 'Submission interrupted. Please retry.',
            }, 503);
          }
          expect(body['consent'], isTrue);
          expect(body['version'], business!['version']);
          business = {
            ...business!,
            'owner_name': body['owner_name'],
            'draft': body['details'],
            'state': 'pending',
            'version': (business!['version'] as int) + 1,
          };
          return _response(business!);
        }
        if (body['action'] == 'save') {
          expect(body['version'], business!['version']);
          business = {
            ...business!,
            'owner_name': body['owner_name'],
            'draft': body['details'],
            'version': (business!['version'] as int) + 1,
          };
          return _response(business!);
        }
      }
      fail('Unexpected directory request: ${request.method} $path');
    }),
  );

  Iterable<DirJson> get creates =>
      mutations.where((call) => call['path'] == '/owner');
  Iterable<DirJson> get submissions =>
      mutations.where((call) => call['action'] == 'submit');

  void dispose() {
    client.dispose();
    revision.dispose();
  }
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

final _captureKey = GlobalKey();

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['DIRECTORY_SCREENSHOTS'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final image =
        await (_captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _mount(
  WidgetTester tester,
  _DirectoryStore store, {
  Size size = const Size(1100, 1000),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(store.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: korlixBuildTheme('pure_white'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: RepaintBoundary(key: _captureKey, child: child!),
      ),
      home: DirectoryScreen(client: store.client),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openForm(WidgetTester tester) async {
  await tester.tap(find.text('Add business — free'));
  await _pump(tester);
  expect(find.text('Add your business — free'), findsOneWidget);
}

Future<void> _field(WidgetTester tester, String field, String value) async {
  final input = find.byKey(ValueKey('directory-field-$field'));
  await tester.ensureVisible(input);
  await tester.enterText(input, value);
  await tester.pump();
}

Future<void> _fillRequired(WidgetTester tester) async {
  await _field(tester, 'name', 'Fixture Shop');
  await _field(tester, 'owner_name', 'Avery Lane');
  await _field(tester, 'phone', '+1 876 555 0123');
  await _field(tester, 'city', 'Kingston');
  await _field(
    tester,
    'description',
    'Fresh bread and friendly service in Kingston.',
  );
}

Future<void> _consent(WidgetTester tester) async {
  final consent = find.descendant(
    of: find.byKey(const ValueKey('directory-public-consent')),
    matching: find.byType(Checkbox),
  );
  await tester.ensureVisible(consent);
  await tester.tap(consent);
  await _pump(tester);
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('directory-submit-free')));
  await _pump(tester);
}

Finder _confirmation(String message) => find.descendant(
  of: find.byKey(const ValueKey('directory-save-confirmation')),
  matching: find.text(message),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))).load();
    final flutter = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (flutter != null) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  testWidgets(
    'free listing saves and submits without payment or verification',
    (tester) async {
      final store = _DirectoryStore();
      await _mount(tester, store);
      await _openForm(tester);
      await _fillRequired(tester);
      await _consent(tester);
      await _submit(tester);
      await tester.pumpAndSettle();

      expect(store.creates, hasLength(1));
      expect(store.submissions, hasLength(1));
      expect(store.business!['state'], 'pending');
      expect(store.business!['verification_state'], 'none');
      expect(find.text('Add your business — free'), findsNothing);
      expect(
        _confirmation('Free listing submitted for review.'),
        findsOneWidget,
      );
      expect(find.textContaining('Awaiting listing review'), findsWidgets);
      expect(
        find.textContaining('Optional badge: Not requested'),
        findsWidgets,
      );
      expect(
        store.mutations.any(
          (call) => '${call['action']}'.contains('verification'),
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing required information stays in form without any request',
    (tester) async {
      final store = _DirectoryStore();
      await _mount(tester, store);
      await _openForm(tester);
      await _field(tester, 'name', 'My unfinished shop');
      await _consent(tester);
      await _submit(tester);

      expect(store.mutations, isEmpty);
      expect(find.text('Add your business — free'), findsOneWidget);
      expect(find.text('My unfinished shop'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('public consent is required before submitting a complete form', (
    tester,
  ) async {
    final store = _DirectoryStore();
    await _mount(tester, store);
    await _openForm(tester);
    await _fillRequired(tester);
    await _submit(tester);

    expect(store.mutations, isEmpty);
    expect(find.text('Add your business — free'), findsOneWidget);
    expect(find.text('Fixture Shop'), findsOneWidget);
    await _consent(tester);
    await _submit(tester);
    await tester.pumpAndSettle();
    expect(store.submissions, hasLength(1));
  });

  testWidgets('save draft remains separate from publishing consent', (
    tester,
  ) async {
    final store = _DirectoryStore();
    await _mount(tester, store);
    await _openForm(tester);
    await _fillRequired(tester);
    await tester.tap(find.byKey(const ValueKey('directory-save-draft')));
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(store.creates, hasLength(1));
    expect(store.submissions, isEmpty);
    expect(store.business!['state'], 'draft');
    expect(find.text('Add your business — free'), findsNothing);
    expect(find.text('Free listing submitted for review.'), findsNothing);
  });

  testWidgets(
    'failed submit preserves the saved business and retries without duplicate creation',
    (tester) async {
      final store = _DirectoryStore()..submitFailures = 1;
      await _mount(tester, store);
      await _openForm(tester);
      await _fillRequired(tester);
      await _consent(tester);
      await _submit(tester);
      await tester.pumpAndSettle();

      expect(store.creates, hasLength(1));
      expect(store.submissions, hasLength(1));
      expect(
        find.textContaining(
          'Submission interrupted. Please retry.',
          findRichText: true,
        ),
        findsWidgets,
      );
      expect(find.text('Add your business — free'), findsNothing);
      final edit = find.text('Edit draft');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await _pump(tester);
      expect(find.text('Edit business listing'), findsOneWidget);
      final name = tester.widget<TextFormField>(
        find.byKey(const ValueKey('directory-field-name')),
      );
      expect(name.controller!.text, 'Fixture Shop');

      await _consent(tester);
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(store.creates, hasLength(1));
      expect(store.submissions, hasLength(2));
      expect(
        store.business!['draft']['description'],
        'Fresh bread and friendly service in Kingston.',
      );
      expect(
        _confirmation('Free listing submitted for review.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'an accepted submission stays confirmed when the following refresh fails',
    (tester) async {
      final store = _DirectoryStore()..failRefreshAfterSubmit = true;
      await _mount(tester, store);
      await _openForm(tester);
      await _fillRequired(tester);
      await _consent(tester);
      await _submit(tester);
      await tester.pumpAndSettle();

      expect(store.submissions, hasLength(1));
      expect(
        _confirmation('Free listing submitted for review.'),
        findsOneWidget,
      );
      expect(find.textContaining('Awaiting listing review'), findsWidgets);
      expect(find.byKey(const ValueKey('directory-submit-free')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a double tap submits one business once', (tester) async {
    final gate = Completer<void>();
    final store = _DirectoryStore()..createGate = gate;
    await _mount(tester, store);
    await _openForm(tester);
    await _fillRequired(tester);
    await _consent(tester);
    final submit = find.byKey(const ValueKey('directory-submit-free'));
    final submitAction = tester.widget<FilledButton>(submit).onPressed!;
    submitAction();
    submitAction();
    await _pump(tester);
    expect(store.creates, hasLength(1));
    gate.complete();
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(store.creates, hasLength(1));
    expect(store.submissions, hasLength(1));
    expect(_confirmation('Free listing submitted for review.'), findsOneWidget);
  });

  testWidgets(
    'account changes clear the form and ignore a late creation response',
    (tester) async {
      final gate = Completer<void>();
      final store = _DirectoryStore()..createGate = gate;
      await _mount(tester, store);
      await _openForm(tester);
      await _fillRequired(tester);
      await _consent(tester);
      await _submit(tester);
      expect(store.creates, hasLength(1));

      store.user = 'different-owner';
      store.revision.value++;
      await _pump(tester);
      gate.complete();
      await _pump(tester);
      await tester.pumpAndSettle();

      expect(store.submissions, isEmpty);
      expect(
        find.text('Sign in again to manage your businesses.'),
        findsOneWidget,
      );
      expect(find.text('Fixture Shop'), findsNothing);
      expect(find.text('Free listing submitted for review.'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a returning pending owner sees listing review separately from the optional badge',
    (tester) async {
      final store = _DirectoryStore();
      store.business = store.existing(state: 'pending');
      await _mount(tester, store);

      expect(find.textContaining('Awaiting listing review'), findsWidgets);
      expect(
        find.textContaining('Optional badge: Not requested'),
        findsWidgets,
      );
      expect(find.textContaining('Verification: none'), findsNothing);
      expect(store.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an existing draft submits directly after public consent', (
    tester,
  ) async {
    final store = _DirectoryStore();
    store.business = store.existing();
    await _mount(tester, store);
    await tester.tap(find.text('Fixture Shop'));
    await tester.pumpAndSettle();
    final submit = find.text('Submit free listing');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await _pump(tester);

    expect(find.text('Submit this free listing?'), findsOneWidget);
    expect(store.mutations, isEmpty);
    await tester.tap(find.text('Confirm'));
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(store.creates, isEmpty);
    expect(store.submissions, hasLength(1));
    expect(store.submissions.single['version'], 7);
    expect(store.submissions.single['consent'], isTrue);
    expect(_confirmation('Free listing submitted for review.'), findsOneWidget);
  });

  testWidgets(
    'editing a public business sends updates for review and keeps its published version',
    (tester) async {
      final store = _DirectoryStore();
      store.business = store.existing(state: 'published');
      final published = dirClone(dirMap(store.business!['draft']));
      store.business!['published'] = published;
      await _mount(tester, store);
      await tester.tap(find.text('Fixture Shop'));
      await tester.pumpAndSettle();
      final edit = find.text('Edit draft');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await _pump(tester);
      await _field(
        tester,
        'description',
        'Updated opening hours and new delivery service.',
      );
      await _consent(tester);
      await _submit(tester);
      await tester.pumpAndSettle();

      expect(store.creates, isEmpty);
      expect(store.submissions, hasLength(1));
      expect(
        store.submissions.single['details']['description'],
        'Updated opening hours and new delivery service.',
      );
      expect(store.submissions.single.containsKey('published'), isFalse);
      expect(store.business!['published'], published);
      expect(store.business!['state'], 'pending');
      expect(find.textContaining('Updates awaiting review'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320px form keeps validation and submission actions reachable at 2x text',
    (tester) async {
      final store = _DirectoryStore();
      await _mount(tester, store, size: const Size(320, 844), textScale: 2);
      await _openForm(tester);
      await _field(tester, 'name', 'Fixture Shop');
      await _submit(tester);

      expect(store.mutations, isEmpty);
      expect(
        find.byKey(const ValueKey('directory-submit-free')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('directory-save-draft')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Cancel').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'directory-validation-320-large-text');

      await _fillRequired(tester);
      await _consent(tester);
      expect(
        find.byKey(const ValueKey('directory-submit-free')).hitTestable(),
        findsOneWidget,
      );
      await _capture(tester, 'directory-submit-320-large-text');
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(store.submissions, hasLength(1));
      expect(
        _confirmation('Free listing submitted for review.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
