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
import 'package:ai_wiz_command_center/payroll/payroll_client.dart';
import 'package:ai_wiz_command_center/payroll/payroll_screen.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

final account = <String, dynamic>{
  'id': 'workspace-1',
  'business_id': 'business-1',
  'legal_name': 'Atlas Design LLC',
  'status': 'draft',
  'terms_accepted': false,
  'country': 'US',
};
final configuration = <String, dynamic>{
  'ready': false,
  'environment': 'unconfigured',
  'message':
      'Payroll provider activation is pending. You can prepare your workspace; payments and tax filings are unavailable until activation.',
};
http.Response response(Map<String, dynamic> data, [int status = 200]) =>
    http.Response(
      jsonEncode(data),
      status,
      headers: {'content-type': 'application/json'},
    );
PayrollClient clientFor(
  Future<http.Response> Function(http.Request) handler, {
  Map<String, String> Function()? headers,
  Listenable? changes,
}) => PayrollClient(
  baseUrl: 'https://fixture.test',
  headersBuilder: headers ?? () => {'Authorization': 'Bearer account-one'},
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
      final icon = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (icon.existsSync()) {
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(ByteData.sublistView(icon.readAsBytesSync())),
            ))
            .load();
      }
    }
  });
  test(
    'account changes invalidate in-flight requests and prevent later access',
    () async {
      String token = 'Bearer account-one';
      final changes = ValueNotifier(0), pending = Completer<http.Response>();
      int requests = 0;
      final client = clientFor(
        (_) {
          requests++;
          return pending.future;
        },
        headers: () => {'Authorization': token},
        changes: changes,
      );
      final task = client.get('workspaces');
      final check = expectLater(task, throwsA(isA<PayrollException>()));
      token = 'Bearer account-two';
      changes.value++;
      pending.complete(
        response({
          'accounts': [account],
        }),
      );
      await check;
      expect(client.available, false);
      await expectLater(
        client.get('workspaces'),
        throwsA(isA<PayrollException>()),
      );
      expect(requests, 1);
      client.dispose();
      changes.dispose();
    },
  );
  test(
    'Enterprise denial invalidates client even when response is not JSON',
    () async {
      final client = clientFor(
        (_) async => http.Response('Access denied', 403),
      );
      await expectLater(
        client.get('workspaces'),
        throwsA(isA<PayrollException>()),
      );
      expect(client.available, false);
      client.dispose();
    },
  );
  test(
    'secure session URLs reject untrusted origins, credentials and wrong environments',
    () {
      for (final url in [
        'http://flows.gusto.com/flows/x',
        'https://flows.gusto.com.evil.test/flows/x',
        'https://user@flows.gusto.com/flows/x',
        'javascript:alert(1)',
        'https://flows.gusto-demo.com/flows/x',
      ]) {
        expect(
          () => payrollFlowUri({'url': url, 'environment': 'production'}),
          throwsA(isA<PayrollException>()),
        );
      }
      expect(
        payrollFlowUri({
          'url': 'https://flows.gusto.com/flows/test',
          'environment': 'production',
        }).host,
        'flows.gusto.com',
      );
    },
  );
  test('paid add-on denial preserves Enterprise workspace access', () async {
    final client = clientFor(
      (_) async => response({
        'error': 'An active Payroll paid add-on is required for this business.',
      }, 402),
    );
    await expectLater(
      client.post('workspaces/workspace-1/refresh', {}),
      throwsA(isA<PayrollException>().having((e) => e.status, 'status', 402)),
    );
    expect(client.available, true);
    client.dispose();
  });
  testWidgets(
    'requesting activation saves an estimate without unlocking payroll, and can be withdrawn',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      Map<String, dynamic> activation = {};
      final client = clientFor((r) async {
        if (r.method == 'POST') {
          requests.add(r);
          activation = r.url.path.endsWith('/withdraw')
              ? {'status': 'withdrawn', 'estimated_employees': 8}
              : {'status': 'requested', 'estimated_employees': 8};
        }
        final current = {
          ...account,
          'addon': {
            'active': false,
            'status': 'inactive',
            'activation_request': activation,
          },
        };
        return response(
          r.url.path.endsWith('/workspaces')
              ? {
                  'accounts': [current],
                  'businesses': [
                    {'id': 'business-1', 'name': 'Atlas Design LLC'},
                  ],
                  'provider': {'ready': true, 'environment': 'production'},
                }
              : {'account': current, 'audit': []},
        );
      });
      await tester.pumpWidget(MaterialApp(home: PayrollScreen(client: client)));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Connect payroll provider'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Request activation'));
      await tester.tap(find.text('Request activation'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Submit request'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), '8');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit request'));
      await tester.pumpAndSettle();
      expect(jsonDecode(requests.single.body), {
        'confirmed': true,
        'estimated_employees': 8,
      });
      expect(find.text('Activation requested'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Connect payroll provider'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Withdraw request'));
      await tester.tap(find.text('Withdraw request'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm withdrawal'));
      await tester.pumpAndSettle();
      expect(requests.last.url.path, endsWith('/activation-request/withdraw'));
      expect(jsonDecode(requests.last.body), {'confirmed': true});
      expect(find.text('Activation requested'), findsNothing);
      expect(find.text('Request activation'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('non-Enterprise account sees only locked screen', (tester) async {
    final client = clientFor(
      (_) async => response({'error': 'Enterprise business required'}, 403),
    );
    await tester.pumpWidget(MaterialApp(home: PayrollScreen(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('Enterprise business access required'), findsOneWidget);
    expect(find.text('New payroll workspace'), findsNothing);
    expect(find.text('Run payroll'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final size in [const Size(390, 844), const Size(1366, 1100)]) {
    testWidgets('payroll layout and activation lock at ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = clientFor(
        (r) async => response(
          r.url.path.endsWith('/workspace-1')
              ? {
                  'account': account,
                  'audit': [
                    {
                      'action': 'workspace_created',
                      'created_at': '2026-09-30T00:00:00Z',
                    },
                  ],
                }
              : {
                  'accounts': [account],
                  'businesses': [
                    {'id': 'business-1', 'name': 'Atlas Design LLC'},
                  ],
                  'provider': configuration,
                },
        ),
      );
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
            child: PayrollScreen(client: client),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Prepare now. Activate payroll next.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final connect = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Connect payroll provider'),
      );
      expect(connect.onPressed, isNull);
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      if (Platform.environment['PAYROLL_SCREENSHOTS'] != null) {
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '${Platform.environment['PAYROLL_SCREENSHOTS']}/payroll-${size.width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'workspace creation requires US authorization and sends only reviewed fields',
    (tester) async {
      final requests = <http.Request>[];
      final client = clientFor((r) async {
        requests.add(r);
        if (r.method == 'POST') return response({'account': account}, 201);
        return response({
          'accounts': [],
          'businesses': [
            {'id': 'business-1', 'name': 'Atlas Design LLC'},
          ],
          'provider': configuration,
        });
      });
      await tester.pumpWidget(MaterialApp(home: PayrollScreen(client: client)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New payroll workspace'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create workspace'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create workspace'));
      await tester.pumpAndSettle();
      final body = jsonDecode(
        requests.singleWhere((r) => r.method == 'POST').body,
      );
      expect(body, {
        'business_id': 'business-1',
        'legal_name': 'Atlas Design LLC',
        'country': 'US',
        'confirmed': true,
      });
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('account switch clears private data and closes open dialogs', (
    tester,
  ) async {
    String token = 'Bearer first';
    final changes = ValueNotifier(0);
    final client = clientFor(
      (_) async => response({
        'accounts': [],
        'businesses': [
          {'id': 'business-1', 'name': 'Atlas Design LLC'},
        ],
        'provider': configuration,
      }),
      headers: () => {'Authorization': token},
      changes: changes,
    );
    await tester.pumpWidget(MaterialApp(home: PayrollScreen(client: client)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New payroll workspace'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    token = 'Bearer next';
    changes.value++;
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Atlas Design LLC'), findsNothing);
    expect(find.text('Enterprise business access required'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    changes.dispose();
  });
}
