import 'package:ai_wiz_command_center/live_convo/korlix_live_convo_agent_client.dart';
import 'package:ai_wiz_command_center/support/korlix_automated_support_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SupportFixture {
  bool accountCurrent = true;
  bool missing = false;
  final calls = <Map<String, dynamic>>[];
  final profiles = <Map<String, dynamic>>[
    {'id': 'a', 'displayName': 'KORLIX AI', 'fromEmail': 'support@example.test',
      'replyTo': 'replies@example.test', 'mode': 'draft', 'ready': true, 'dailyCap': 100},
    {'id': 'b', 'displayName': 'Receipt Wiz', 'fromEmail': 'receipts@example.test',
      'replyTo': 'receipt-replies@example.test', 'mode': 'paused', 'ready': false, 'dailyCap': 40},
  ];
  Map<String, dynamic> supportCase = {
    'id': 'case-a', 'profileId': 'a', 'subject': 'Feature will not load',
    'details': 'It is not loading.', 'reporterEmail': 'customer@example.test', 'reporterVerified': true,
    'state': 'new', 'automationPaused': false, 'platform': 'android',
    'createdAt': '2026-11-10T02:04:25Z', 'updatedAt': '2026-11-10T02:04:25Z',
  };
  final messages = <Map<String, dynamic>>[];

  void assertAccount() {
    if (!accountCurrent) throw const KorlixLiveConvoAgentClientException(
      'Account changed', statusCode: 401,
    );
  }
  Future<Map<String, dynamic>> request({required String method, required String path, Map<String, dynamic>? body}) async {
    assertAccount();
    calls.add({'method': method, 'path': path, 'body': body});
    if (missing) throw const KorlixLiveConvoAgentClientException('Unavailable', statusCode: 404);
    if (path.endsWith('/profiles')) return {'ok': true, 'profiles': profiles};
    if (path.endsWith('/profiles/a')) { profiles[0]['mode'] = body!['mode']; return {'ok': true}; }
    if (path.contains('/cases?')) {
      final query = Uri.parse(path).queryParameters;
      return {'ok': true, 'cases': query['profileId'] == 'a' ? [supportCase] : []};
    }
    if (path.endsWith('/replies')) {
      messages.add({'id': 'reply', 'direction': 'outbound', 'status': 'pending', 'text': body!['text']});
      return {'ok': true, 'case': supportCase, 'message': messages.last};
    }
    if (path.endsWith('/cases/case-a')) {
      if (method == 'PATCH') supportCase = {...supportCase, ...?body};
      return {'ok': true, 'case': supportCase, 'messages': messages};
    }
    throw StateError('Unexpected request $path');
  }

  Future<void> mount(WidgetTester tester, {double width = 390}) async {
    tester.view.physicalSize = Size(width, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body:
      KorlixAutomatedSupportPanel(request: request, assertCurrentAccount: assertAccount))));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('support addresses stay separate and automatic mode needs readiness', (tester) async {
    final f = _SupportFixture();
    await f.mount(tester, width: 320);
    expect(find.text('Feature will not load'), findsOneWidget);
    expect(find.text('support@example.test'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Receipt Wiz · receipts@example.test').last);
    await tester.pumpAndSettle();
    expect(find.text('Feature will not load'), findsNothing);
    expect(find.text('receipts@example.test'), findsOneWidget);
    expect(find.text('Complete address setup before enabling automatic replies.'), findsOneWidget);
    final mode = tester.widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>)).last;
    expect(mode.items!.firstWhere((i) => i.value == 'automatic').enabled, isFalse);
    expect(f.calls.where((c) => c['method'] != 'GET'), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('missing support setup never displays invented cases', (tester) async {
    final f = _SupportFixture()..missing = true;
    await f.mount(tester);
    expect(find.text('Automated support is awaiting setup for this workspace.'), findsOneWidget);
    expect(find.text('Feature will not load'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('account changes remove loaded support data', (tester) async {
    final f = _SupportFixture();
    await f.mount(tester);
    expect(find.text('Feature will not load'), findsOneWidget);
    f.accountCurrent = false;
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Feature will not load'), findsNothing);
    expect(find.text('support@example.test'), findsNothing);
    expect(find.text('Your account changed. Close and reopen Email Center.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a reply is reviewed and addressed by its case, with no client recipient field', (tester) async {
    final f = _SupportFixture();
    await f.mount(tester);
    await tester.ensureVisible(find.text('Feature will not load'));
    await tester.tap(find.text('Feature will not load'));
    await tester.pumpAndSettle();
    final field = find.byType(TextField).last;
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Which feature were you trying to open?');
    await tester.ensureVisible(find.text('Review reply'));
    await tester.tap(find.text('Review reply'));
    await tester.pumpAndSettle();
    expect(f.calls.where((c) => c['method'] == 'POST'), isEmpty);
    expect(find.textContaining('To: customer@example.test'), findsOneWidget);
    await tester.tap(find.text('Queue reply'));
    await tester.pumpAndSettle();
    final reply = f.calls.singleWhere((c) => c['method'] == 'POST');
    expect(reply['path'], '/api/automated-support/cases/case-a/replies');
    expect(reply['body'], {'text': 'Which feature were you trying to open?', 'confirmed': true});
    expect(find.text('pending'), findsNothing); // Status is displayed with its sender label.
    expect(find.textContaining('KORLIX support · pending'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
