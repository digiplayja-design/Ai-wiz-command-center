import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/scheduling/scheduling_client.dart';
import 'package:ai_wiz_command_center/scheduling/scheduling_screen.dart';
import 'package:ai_wiz_command_center/scheduling/scheduling_forms.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

final profile = <String, dynamic>{
  'display_name': 'Atlas Design',
  'timezone': 'America/New_York',
  'revision': 1,
  'weekly': List.generate(
    7,
    (day) => {
      'day': day,
      'windows': day > 0 && day < 6
          ? [
              [540, 1020],
            ]
          : [],
    },
  ),
  'overrides': [],
};
final event = <String, dynamic>{
  'id': 'event-one',
  'title': 'Let’s talk about your next project',
  'description':
      'A focused 30-minute conversation to turn your ideas into a clear next step.',
  'kind': 'one_to_one',
  'duration_minutes': 30,
  'interval_minutes': 30,
  'buffer_before': 0,
  'buffer_after': 15,
  'notice_minutes': 240,
  'horizon_days': 60,
  'daily_limit': 8,
  'capacity': 1,
  'cancel_notice_minutes': 60,
  'location_kind': 'video',
  'location_detail': 'https://meet.example.test/room',
  'questions': [],
  'color': '#72D6EB',
  'state': 'draft',
  'revision': 1,
  'url': 'https://fixture.test/book/atlas-discovery',
};
Map<String, dynamic> dashboard({List<Map<String, dynamic>>? events}) => {
  'profile': profile,
  'events': events ?? [event],
  'bookings': [],
  'blocks': [],
  'timezones': ['UTC', 'America/New_York'],
  'booking_limit': 500,
  'history_days': 90,
};
http.Response response(dynamic data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json'},
);
SchedulingClient clientFor(
  Future<http.Response> Function(http.Request) handler, {
  Map<String, String> Function()? headers,
  Listenable? changes,
}) => SchedulingClient(
  baseUrl: 'https://fixture.test',
  headersBuilder: headers ?? () => {'Authorization': 'Bearer first'},
  sessionChanges: changes,
  client: MockClient(handler),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fieldproof/Roboto-Bold.ttf'));
    await fonts.load();
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root != null) {
      final icons = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (icons.existsSync()) {
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(ByteData.sublistView(icons.readAsBytesSync())),
            ))
            .load();
      }
    }
  });
  test('split shifts validate ordering, bounds and five-minute steps', () {
    expect(parseScheduleWindows('09:00–12:00, 13:00-17:00'), [
      [540, 720],
      [780, 1020],
    ]);
    expect(parseScheduleWindows(''), []);
    for (final s in [
      '09:00-10:00,09:30-11:00',
      '24:00-25:00',
      '09:03-10:00',
      'noon',
    ]) {
      expect(() => parseScheduleWindows(s), throwsFormatException);
    }
  });
  test('session changes invalidate delayed private data', () async {
    String token = 'Bearer first';
    final changes = ValueNotifier(0), pending = Completer<http.Response>();
    final client = clientFor(
      (_) => pending.future,
      headers: () => {'Authorization': token},
      changes: changes,
    );
    final check = expectLater(
      client.get(''),
      throwsA(isA<SchedulingException>()),
    );
    token = 'Bearer second';
    changes.value++;
    pending.complete(response(dashboard()));
    await check;
    expect(client.available, false);
    client.dispose();
    changes.dispose();
  });
  test('403 revokes client even if the error body is not JSON', () async {
    final client = clientFor((_) async => http.Response('Forbidden', 403));
    await expectLater(client.get(''), throwsA(isA<SchedulingException>()));
    expect(client.available, false);
    client.dispose();
  });
  testWidgets('unverified hosts see only the access screen', (tester) async {
    final client = clientFor(
      (_) async => response({'error': 'Verified account required'}, 401),
    );
    await tester.pumpWidget(
      MaterialApp(home: SchedulingScreen(client: client)),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Sign in with an active, verified'),
      findsOneWidget,
    );
    expect(find.text('Create booking page'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final size in [const Size(390, 844), const Size(1366, 1100)]) {
    testWidgets(
      'host dashboard, event types and availability fit ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = clientFor((_) async => response(dashboard()));
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: korlixBuildTheme('korlix_blue').copyWith(
              textTheme: korlixBuildTheme(
                'korlix_blue',
              ).textTheme.apply(fontFamily: 'Roboto'),
            ),
            home: RepaintBoundary(
              key: key,
              child: SchedulingScreen(client: client),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (Platform.environment['SCHEDULING_SCREENSHOTS'] != null) {
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File(
              '${Platform.environment['SCHEDULING_SCREENSHOTS']}/scheduling-${size.width.toInt()}.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        for (final name in ['Event types', 'Availability', 'Bookings']) {
          await tester.ensureVisible(find.widgetWithText(ChoiceChip, name));
          await tester.tap(find.widgetWithText(ChoiceChip, name));
          await tester.pumpAndSettle();
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -700),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'publishing requires review and sends the current event revision',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sent = <http.Request>[];
      final client = clientFor((r) async {
        if (r.method == 'POST') sent.add(r);
        return response(dashboard());
      });
      await tester.pumpWidget(
        MaterialApp(home: SchedulingScreen(client: client)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Event types'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Publish'));
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      expect(find.textContaining('Enabled Google and Microsoft calendars'), findsOneWidget);
      await tester.tap(find.text('Publish page'));
      await tester.pumpAndSettle();
      expect(jsonDecode(sent.single.body), {
        'revision': 1,
        'state': 'published',
        'confirmed': true,
      });
      expect(sent.single.url.path, endsWith('/events/event-one/state'));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('email automation is opt-in and requires an explicit save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sent = <http.Request>[];
    final client = clientFor((r) async {
      if (r.method == 'POST') sent.add(r);
      return response({
        ...dashboard(),
        'capabilities': {'automatic_email': true},
      });
    });
    await tester.pumpWidget(
      MaterialApp(home: SchedulingScreen(client: client)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Availability'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Email settings'));
    await tester.tap(find.text('Email settings'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      false,
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);
    await tester.tap(find.text('Save email settings'));
    await tester.pumpAndSettle();
    expect(jsonDecode(sent.single.body), {
      'enabled': true,
      'reminder_minutes': 60,
      'confirmed': true,
      'revision': 1,
    });
    expect(sent.single.url.path, endsWith('/notifications'));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('creating an event saves a draft without publishing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sent = <http.Request>[];
    final client = clientFor((r) async {
      if (r.method == 'POST') sent.add(r);
      return response(dashboard(events: []));
    });
    await tester.pumpWidget(
      MaterialApp(home: SchedulingScreen(client: client)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create booking page'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Meeting title'),
      'Project discovery',
    );
    await tester.tap(find.text('Create draft'));
    await tester.pumpAndSettle();
    expect(sent.length, 1);
    expect(sent.single.url.path, endsWith('/events'));
    final body = jsonDecode(sent.single.body);
    expect(body['title'], 'Project discovery');
    expect(body['revision'], 0);
    expect(body.containsKey('state'), false);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'account switch clears host details and dismisses editing dialogs',
    (tester) async {
      String token = 'Bearer first';
      final changes = ValueNotifier(0);
      final client = clientFor(
        (_) async => response(dashboard()),
        headers: () => {'Authorization': token},
        changes: changes,
      );
      await tester.pumpWidget(
        MaterialApp(home: SchedulingScreen(client: client)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('My availability'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      token = 'Bearer second';
      changes.value++;
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Atlas Design'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      changes.dispose();
    },
  );
}
