import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_threads.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'social_test.dart' as social;
import 'agent_studio_test.dart' as fixtures;

class ReceiptStore {
  final messages = <SocialMap>[];
  final receipts = <String, SocialMap>{};
  final requests = <SocialMap>[];
  int readFailures = 0;
  Completer<http.Response>? pendingReceipts;
  late final client = SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': 'Bearer account-one'},
    client: MockClient((request) async {
      final action = request.url.path.split('/').last;
      final data = request.method == 'POST'
          ? socialMap(jsonDecode(request.body))
          : request.url.queryParameters;
      requests.add({'action': action, ...data});
      SocialMap result = {};
      if (action == 'messages' || action == 'group_messages') {
        result = {'items': messages, 'peer': social.peer};
      }
      if (action == 'message_receipts') {
        if (pendingReceipts != null) return pendingReceipts!.future;
        final ids = (jsonDecode('${data['ids']}') as List).cast<String>();
        result = {
          'items': [
            for (final id in ids)
              if (receipts[id] != null) {'id': id, ...receipts[id]!},
          ],
        };
      }
      if (action == 'read' || action == 'group_read') {
        if (readFailures-- > 0) {
          return http.Response('{"error":"Temporary problem"}', 503);
        }
        result = {'ok': true};
      }
      return http.Response(jsonEncode(result), 200);
    }),
  );

  SocialMap message(String id, int seq, {bool mine = false, String? body}) => {
    'id': id,
    'seq': seq,
    'sender': mine ? social.me['id'] : social.peer['id'],
    'author': mine ? social.me : social.peer,
    'body': body ?? 'Message $id',
    'created_at': '2026-10-12T20:00:00Z',
    'deleted': false,
    'read_at': null,
  };
  List<SocialMap> get reads => requests
      .where((r) => ['read', 'group_read'].contains(r['action']))
      .toList();
  Set<String> get acknowledged => {
    for (final r in reads) ...List<String>.from(r['ids'] as List),
  };
}

Future<void> settleReceipts(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Future<void> mount(
  WidgetTester tester,
  ReceiptStore store, {
  bool group = false,
  double scale = 1,
}) async {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await social.mount(
    tester,
    SocialChatScreen(
      client: store.client,
      me: social.me,
      peer: social.peer,
      groupChat: group,
    ),
    width: 390,
    height: 844,
    scale: scale,
    theme: 'korlix_blue',
  );
  await settleReceipts(tester);
}

Future<void> finish(WidgetTester tester, ReceiptStore store) async {
  await tester.pumpWidget(const SizedBox());
  store.client.dispose();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['AGENT_STUDIO_SCREENSHOTS'] == null) return;
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))).load();
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  testWidgets(
    'recipient acknowledges displayed messages and sender sees a read time on refresh',
    (tester) async {
      final store = ReceiptStore();
      store.messages.addAll([
        store.message('incoming', 1),
        store.message('sent', 2, mine: true),
      ]);
      await mount(tester, store);
      expect(store.acknowledged, {'incoming'});
      expect(find.text('Sent'), findsOneWidget);
      store.receipts['sent'] = {
        'read_at': '2026-10-12T20:01:00Z',
        'read_count': 1,
      };
      await tester.pump(const Duration(seconds: 4));
      await settleReceipts(tester);
      expect(find.text('Read'), findsOneWidget);
      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('receipt-state-sent')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('receipt-details-sent')),
        findsOneWidget,
      );
      expect(find.textContaining('October'), findsOneWidget);
      expect(store.reads.length, 1);
      expect(tester.takeException(), isNull);
      await fixtures.capture(tester, 'social-direct-read-receipt');
      await finish(tester, store);
    },
  );

  testWidgets(
    'loaded messages outside the viewport stay unread until scrolled into view',
    (tester) async {
      final store = ReceiptStore();
      for (var i = 0; i < 20; i++) {
        store.messages.add(
          store.message(
            'incoming-$i',
            i + 1,
            body: 'Message $i.\n${'More conversation.\n' * 5}',
          ),
        );
      }
      await mount(tester, store);
      expect(store.acknowledged, contains('incoming-19'));
      expect(store.acknowledged, isNot(contains('incoming-0')));
      final list = tester.widget<ListView>(find.byType(ListView));
      list.controller!.jumpTo(0);
      await tester.pump();
      await settleReceipts(tester);
      expect(store.acknowledged, contains('incoming-0'));
      expect(store.acknowledged.length, lessThan(20));
      await finish(tester, store);
    },
  );

  testWidgets(
    'background and covered conversations cannot acknowledge new messages',
    (tester) async {
      final store = ReceiptStore();
      store.messages.add(store.message('first', 1));
      await mount(tester, store);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      store.messages.add(store.message('background', 2));
      await tester.pump(const Duration(seconds: 5));
      expect(store.acknowledged, {'first'});
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await settleReceipts(tester);
      expect(store.acknowledged, contains('background'));
      final navigator = Navigator.of(
        tester.element(find.byType(SocialChatScreen)),
      );
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Another screen')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      store.messages.add(store.message('covered', 3));
      await tester.pump(const Duration(seconds: 5));
      expect(store.acknowledged, isNot(contains('covered')));
      navigator.pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await settleReceipts(tester);
      expect(store.acknowledged, contains('covered'));
      await finish(tester, store);
    },
  );

  testWidgets(
    'a failed acknowledgement retries and successful IDs are not sent repeatedly',
    (tester) async {
      final store = ReceiptStore()..readFailures = 1;
      store.messages.add(store.message('retry', 1));
      await mount(tester, store);
      expect(store.reads.length, 1);
      await tester.pump(const Duration(seconds: 4));
      await settleReceipts(tester);
      expect(store.reads.length, 2);
      await tester.pump(const Duration(seconds: 4));
      await settleReceipts(tester);
      expect(store.reads.length, 2);
      await finish(tester, store);
    },
  );

  testWidgets(
    'group receipts show reader names and first read times with large text',
    (tester) async {
      final store = ReceiptStore();
      store.messages.add(store.message('group-sent', 1, mine: true));
      store.receipts['group-sent'] = {
        'read_count': 2,
        'readers': [
          {
            'id': 'bruno',
            'name': 'Bruno',
            'handle': 'bruno',
            'read_at': '2026-10-12T20:01:00Z',
          },
          {
            'id': 'chris',
            'name': 'Chris',
            'handle': 'chris',
            'read_at': '2026-10-12T20:02:00Z',
          },
        ],
      };
      await mount(tester, store, group: true, scale: 2);
      expect(find.text('Read by 2'), findsOneWidget);
      final button = find.byKey(const ValueKey('receipt-state-group-sent'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.textContaining('Bruno · @bruno'), findsOneWidget);
      expect(find.textContaining('Chris · @chris'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.textContaining('Chris · @chris'));
      await tester.pumpAndSettle();
      await fixtures.capture(tester, 'social-group-read-receipts-large-text');
      store.client.invalidateSession();
      await tester.pumpAndSettle();
      expect(find.textContaining('Bruno · @bruno'), findsNothing);
      expect(find.text('Read by 2'), findsNothing);
      await finish(tester, store);
    },
  );

  testWidgets(
    'late receipt responses cannot restore another session’s message details',
    (tester) async {
      final store = ReceiptStore()
        ..pendingReceipts = Completer<http.Response>();
      store.messages.add(store.message('sent', 1, mine: true));
      await mount(tester, store);
      expect(
        store.requests.any((r) => r['action'] == 'message_receipts'),
        isTrue,
      );
      store.client.invalidateSession();
      store.pendingReceipts!.complete(
        http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'sent',
                'read_at': '2026-10-12T20:01:00Z',
                'read_count': 1,
              },
            ],
          }),
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Message sent'), findsNothing);
      expect(find.text('Read'), findsNothing);
      expect(tester.takeException(), isNull);
      await finish(tester, store);
    },
  );
}
