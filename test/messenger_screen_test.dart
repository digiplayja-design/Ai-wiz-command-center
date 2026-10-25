import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/social/social_screen.dart';
import 'package:ai_wiz_command_center/social/social_threads.dart';
import 'package:korlix_social_core/social/social_messenger_inbox.dart';
import 'social_test.dart' as fixtures;

List<Map<String, dynamic>> sampleConversations() {
  final now = DateTime.now().toUtc();
  return [
    for (final (id, name, body, age, unread, color, kind, mine) in [
      (
        'peer',
        'Jordan Rivera',
        'Are we still meeting at 6?',
        0,
        3,
        'violet',
        'text',
        false,
      ),
      ('maya', 'Maya Chen', 'Voice note', 2, 1, 'coral', 'voice', false),
      ('ethan', 'Ethan Brooks', 'Photo', 12, 2, 'blue', 'image', false),
      (
        'sofia',
        'Sofia Grant',
        'That sounds perfect!',
        38,
        0,
        'gold',
        'text',
        true,
      ),
      (
        'daniel',
        'Daniel Lewis',
        'Thanks! I received it.',
        60,
        0,
        'mint',
        'text',
        false,
      ),
      (
        'ava',
        'Ava Mitchell',
        'See you tomorrow',
        180,
        0,
        'violet',
        'text',
        false,
      ),
      ('noah', 'Noah Williams', 'Talk soon!', 1440, 0, 'blue', 'text', true),
    ])
      {
        'id': id,
        'name': name,
        'handle': id,
        'color': color,
        'connection': 'accepted',
        'unread': unread,
        'online': unread > 0,
        'last_message': body,
        'last_message_at': now
            .subtract(Duration(minutes: age))
            .toIso8601String(),
        'last_message_kind': kind,
        'last_message_mine': mine,
        if (kind == 'voice') 'last_message_duration_ms': 18000,
      },
  ];
}

Future<void> loadPreviewFonts(WidgetTester tester) async {
  if (Platform.environment['KORLIX_CAPTURE_MESSENGER'] != '1') return;
  final sdk = Platform.environment['KORLIX_FLUTTER_ROOT']!;
  await tester.runAsync(() async {
    for (final (family, file) in [
      ('Roboto', 'Roboto-Regular.ttf'),
      ('Ahem', 'Roboto-Regular.ttf'),
      ('MaterialIcons', 'MaterialIcons-Regular.otf'),
    ]) {
      final data = await File(
        '$sdk/bin/cache/artifacts/material_fonts/$file',
      ).readAsBytes();
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(data)))).load();
    }
  });
}

void main() {
  test(
    'inbox timestamps and attachment previews use available message data',
    () {
      final now = DateTime(2026, 10, 25, 12);
      expect(messengerMessageTime('invalid', now: now), '');
      expect(messengerMessageTime(now.toIso8601String(), now: now), 'Now');
      expect(
        messengerMessageTime(
          now.subtract(const Duration(minutes: 2)).toIso8601String(),
          now: now,
        ),
        '2m',
      );
      expect(
        messengerMessageTime('2026-10-24T23:00:00', now: now),
        'Yesterday',
      );
      expect(
        messengerMessageTime('2025-10-24T12:00:00', now: now),
        '10/24/2025',
      );
      expect(
        messengerMessagePreview({
          'last_message': 'Voice note',
          'last_message_kind': 'voice',
          'last_message_duration_ms': 18000,
        }),
        'Voice message · 0:18',
      );
      expect(
        messengerMessagePreview({
          'last_message': 'Hello',
          'last_message_mine': true,
        }),
        'You: Hello',
      );
      expect(messengerMessagePreview({}), 'Start a conversation');
    },
  );
  testWidgets(
    'Messenger opens existing conversations and keeps the Social wall off its tabs',
    (tester) async {
      final store = fixtures.Store()..accepted = true;
      await fixtures.mount(
        tester,
        SocialScreen(client: store.client, messengerMode: true),
      );
      expect(find.text('Messenger'), findsOneWidget);
      expect(find.text('Chats'), findsNWidgets(2));
      expect(find.text('Groups'), findsOneWidget);
      expect(find.text('People'), findsOneWidget);
      expect(find.text('Wall'), findsNothing);
      expect(find.text('Forums'), findsNothing);
      expect(store.calls.where((r) => r['action'] == 'wall'), isEmpty);
      expect(
        store.calls
            .where((r) => r['action'] == 'messenger_inbox')
            .first['filter'],
        'all',
      );
      final row = find.byKey(const ValueKey('messenger-conversation-peer'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(SocialChatScreen), findsOneWidget);
      expect(
        store.calls.where((r) => r['action'] == 'messages').last['peer'],
        'peer',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      store.revision.dispose();
    },
  );

  testWidgets('Hub still opens its existing Social wall by default', (
    tester,
  ) async {
    final store = fixtures.Store();
    await fixtures.mount(tester, SocialScreen(client: store.client));
    expect(find.text('Wall'), findsOneWidget);
    expect(store.calls.where((r) => r['action'] == 'wall'), isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    store.revision.dispose();
  });

  testWidgets(
    'Messenger routes People and Groups and clears old content after a session change',
    (tester) async {
      final store = fixtures.Store()..accepted = true;
      await fixtures.mount(
        tester,
        SocialScreen(client: store.client, messengerMode: true),
      );
      await tester.tap(find.text('People'));
      await tester.pumpAndSettle();
      expect(store.calls.where((r) => r['action'] == 'members'), isNotEmpty);
      await tester.tap(find.text('Groups'));
      await tester.pumpAndSettle();
      expect(store.calls.where((r) => r['action'] == 'groups'), isNotEmpty);
      store.token = 'Bearer another-account';
      store.revision.value++;
      await tester.pumpAndSettle();
      expect(find.text('Sign in to join the conversation.'), findsOneWidget);
      expect(find.text('Jordan Rivera'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      store.revision.dispose();
    },
  );

  testWidgets(
    'Messenger fits a narrow phone with enlarged text and exposes account help',
    (tester) async {
      final store = fixtures.Store()..accepted = true;
      var accountOpened = false;
      await fixtures.mount(
        tester,
        SocialScreen(
          client: store.client,
          messengerMode: true,
          onOpenAccount: () => accountOpened = true,
        ),
        width: 320,
        height: 740,
        scale: 1.5,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Account & help'));
      expect(accountOpened, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      store.revision.dispose();
    },
  );

  testWidgets('capture Messenger inbox with synthetic fixture data', (
    tester,
  ) async {
    final store = fixtures.Store()..accepted = true;
    if (Platform.environment['KORLIX_CAPTURE_MESSENGER'] == '1') {
      final sdk = Platform.environment['KORLIX_FLUTTER_ROOT']!;
      await tester.runAsync(() async {
        for (final (family, file) in [
          ('Roboto', 'Roboto-Regular.ttf'),
          ('Ahem', 'Roboto-Regular.ttf'),
          ('MaterialIcons', 'MaterialIcons-Regular.otf'),
        ]) {
          final data = await File(
            '$sdk/bin/cache/artifacts/material_fonts/$file',
          ).readAsBytes();
          await (FontLoader(
            family,
          )..addFont(Future.value(ByteData.sublistView(data)))).load();
        }
      });
    }
    final key = GlobalKey();
    await fixtures.mount(
      tester,
      RepaintBoundary(
        key: key,
        child: SocialScreen(client: store.client, messengerMode: true),
      ),
      width: 430,
      height: 932,
      theme: 'lavender_mist',
    );
    expect(tester.takeException(), isNull);
    if (Platform.environment['KORLIX_CAPTURE_MESSENGER'] == '1') {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          'docs/evidence/korlix-messenger-20261024/messenger-inbox.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
    store.revision.dispose();
  });

  testWidgets(
    'multiple chats expose server unread/search filters and request routing',
    (tester) async {
      final store = fixtures.Store()
        ..accepted = true
        ..inboxItems = sampleConversations();
      await fixtures.mount(
        tester,
        SocialScreen(client: store.client, messengerMode: true),
        height: 1000,
      );
      expect(find.text('Voice message · 0:18'), findsOneWidget);
      expect(find.text('Sent a photo'), findsOneWidget);
      await tester.tap(find.text('Unread'));
      await tester.pumpAndSettle();
      expect(
        store.calls
            .where((r) => r['action'] == 'messenger_inbox')
            .last['filter'],
        'unread',
      );
      expect(find.text('Sofia Grant'), findsNothing);
      expect(find.text('Jordan Rivera'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Maya');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Jordan Rivera'), findsNothing);
      expect(find.text('Maya Chen'), findsOneWidget);
      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();
      expect(
        store.calls.where((r) => r['action'] == 'connections').last['state'],
        'pending',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      store.revision.dispose();
    },
  );

  testWidgets('unread inbox explains when there are no unread conversations', (
    tester,
  ) async {
    final store = fixtures.Store()
      ..accepted = true
      ..inboxItems = [];
    await fixtures.mount(
      tester,
      SocialScreen(client: store.client, messengerMode: true),
    );
    await tester.tap(find.text('Unread'));
    await tester.pumpAndSettle();
    expect(find.text('You’re all caught up.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    store.revision.dispose();
  });

  testWidgets(
    'conversation previews remain usable at 320px with doubled text',
    (tester) async {
      final store = fixtures.Store()
        ..accepted = true
        ..inboxItems = sampleConversations();
      await fixtures.mount(
        tester,
        SocialScreen(client: store.client, messengerMode: true),
        width: 320,
        height: 900,
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).first, const Offset(0, -550));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.revision.dispose();
    },
  );

  testWidgets('capture implemented multi-conversation Messenger inbox', (
    tester,
  ) async {
    final store = fixtures.Store()
      ..accepted = true
      ..inboxItems = sampleConversations();
    await loadPreviewFonts(tester);
    final key = GlobalKey();
    await fixtures.mount(
      tester,
      RepaintBoundary(
        key: key,
        child: SocialScreen(client: store.client, messengerMode: true),
      ),
      width: 430,
      height: 932,
      theme: 'lavender_mist',
    );
    expect(tester.takeException(), isNull);
    if (Platform.environment['KORLIX_CAPTURE_MESSENGER'] == '1') {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          'docs/evidence/korlix-messenger-20261024/messenger-conversations.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
    store.revision.dispose();
  });
}
