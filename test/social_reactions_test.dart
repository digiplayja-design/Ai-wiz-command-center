import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_media_widgets.dart';
import 'package:ai_wiz_command_center/social/social_reaction_picker.dart';
import 'package:ai_wiz_command_center/social/social_threads.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'social_test.dart' as social;
import 'agent_studio_test.dart' as fixtures;

class ReactionsStore {
  final uploads = <Map<String, String>>[], sends = <SocialMap>[];
  final revision = ValueNotifier(0);
  String token = 'Bearer first';
  bool failSend = false;
  late final client = SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': token},
    sessionChanges: revision,
    client: MockClient((r) async {
      final action = r.url.path.split('/').last;
      if (action == 'attachment_upload') {
        uploads.add(r.url.queryParameters);
        return http.Response(
          jsonEncode({
            'attachment': {'id': r.url.queryParameters['id'], 'kind': 'image'},
          }),
          200,
        );
      }
      if (action.endsWith('messages')) {
        return http.Response(
          jsonEncode({
            'peer': social.peer,
            'group': social.peer,
            'items': [
              {
                'id': 'first',
                'seq': 1,
                'body': 'Hello there',
                'sender': 'peer',
                'created_at': '2026-10-10T10:00:00Z',
              },
            ],
          }),
          200,
        );
      }
      if (action.endsWith('send')) {
        sends.add(socialMap(jsonDecode(r.body)));
        if (failSend) {
          failSend = false;
          return http.Response('{"error":"Please retry"}', 503);
        }
      }
      return http.Response('{}', 200);
    }),
  );
  void dispose() {
    client.dispose();
    revision.dispose();
  }
}

Future<SocialAttachmentDraft> reactionDraft(String kind) async {
  final data = await rootBundle.load(
    'assets/social_reactions/hey.${kind == 'gif' ? 'gif' : 'png'}',
  );
  return SocialAttachmentDraft(
    bytes: data.buffer.asUint8List(),
    filename: kind == 'gif' ? 'Hey.gif' : 'Hey.png',
    kind: kind,
  );
}

Future<void> settleAssets(WidgetTester t) async {
  // Give the real asset loader/codec a chance to complete between fake frames.
  for (var i = 0; i < 3; i++) {
    await t.pump();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
  }
  await t.pumpAndSettle();
}

Future<void> picker(
  WidgetTester t,
  ReactionsStore store, {
  String kind = 'sticker',
  double width = 390,
  double scale = 1,
  Future<SocialAttachmentDraft?> Function(String)? upload,
}) async {
  t.view.physicalSize = Size(width, 840);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      theme: korlixBuildTheme('pure_black'),
      builder: (context, child) =>
          RepaintBoundary(key: fixtures.captureKey, child: child!),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: SocialReactionSheet(
              client: store.client,
              initialKind: kind,
              uploadPicker: upload,
            ),
          ),
        ),
      ),
    ),
  );
  // Asset decoding uses real engine work outside the widget test's fake clock.
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await settleAssets(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
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

  test(
    'all original reactions have decodable transparent stickers and animated GIFs',
    () async {
      final catalog = await loadSocialReactions();
      expect(catalog.length, 24);
      expect(catalog.map((r) => r.id).toSet().length, catalog.length);
      for (final reaction in catalog) {
        final png = await rootBundle.load(reaction.asset('sticker'));
        final still = await ui.instantiateImageCodec(png.buffer.asUint8List());
        expect(still.frameCount, 1);
        final frame = await still.getNextFrame();
        final rgba = await frame.image.toByteData();
        expect(rgba!.getUint8(3), 0);
        frame.image.dispose();
        still.dispose();
        final data = await rootBundle.load(reaction.asset('gif'));
        final gif = await ui.instantiateImageCodec(data.buffer.asUint8List());
        expect(gif.frameCount, 16);
        expect(gif.repetitionCount, -1);
        final first = await gif.getNextFrame();
        expect(first.duration, const Duration(milliseconds: 100));
        first.image.dispose();
        gif.dispose();
      }
    },
  );

  testWidgets(
    'search and categories find stickers and selection only creates a preview',
    (t) async {
      final s = ReactionsStore();
      addTearDown(s.dispose);
      await picker(t, s);
      await fixtures.capture(t, 'social-sticker-picker');
      await t.enterText(find.byType(TextField), 'thanks');
      await settleAssets(t);
      expect(find.byKey(const ValueKey('reaction-thank-you')), findsOneWidget);
      expect(find.byKey(const ValueKey('reaction-hey')), findsNothing);
      await t.tap(find.byKey(const ValueKey('reaction-thank-you')));
      await settleAssets(t);
      expect(find.text('Use sticker'), findsOneWidget);
      expect(s.uploads, isEmpty);
      expect(s.sends, isEmpty);
      await t.tap(find.text('Choose another'));
      await settleAssets(t);
      await t.enterText(find.byType(TextField), 'zzzz');
      await settleAssets(t);
      expect(find.textContaining('No matching reactions'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'GIF preview starts paused for reduced motion and fits a narrow screen with large text',
    (t) async {
      final s = ReactionsStore();
      addTearDown(s.dispose);
      await picker(t, s, kind: 'gif', width: 320, scale: 1.5);
      await t.tap(find.byKey(const ValueKey('reaction-hey')));
      await settleAssets(t);
      expect(find.byTooltip('Play GIF'), findsOneWidget);
      expect(find.text('Use GIF'), findsOneWidget);
      await t.tap(find.byTooltip('Play GIF'));
      await t.pump(const Duration(milliseconds: 250));
      expect(find.byTooltip('Pause GIF'), findsOneWidget);
      await t.tap(find.byTooltip('Pause GIF'));
      await settleAssets(t);
      expect(find.byTooltip('Play GIF'), findsOneWidget);
      expect(t.takeException(), isNull);
      await fixtures.capture(t, 'social-gif-preview');
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'late uploaded reaction is discarded when the signed-in account changes',
    (t) async {
      final s = ReactionsStore();
      addTearDown(s.dispose);
      final pending = Completer<SocialAttachmentDraft?>();
      await picker(t, s, upload: (_) => pending.future);
      await t.tap(find.text('Upload sticker'));
      await t.pump();
      s.token = 'Bearer second';
      s.revision.value++;
      pending.complete(await reactionDraft('sticker'));
      await settleAssets(t);
      expect(find.text('Use sticker'), findsNothing);
      expect(s.uploads, isEmpty);
      expect(find.textContaining('Your session changed.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );

  for (final group in [false, true]) {
    for (final kind in ['gif', 'sticker']) {
      testWidgets(
        '${group ? 'group' : 'direct'} $kind preserves reply and draft, needs Send, and retries the same upload once',
        (t) async {
          final s = ReactionsStore()..failSend = true;
          addTearDown(s.dispose);
          await social.mount(
            t,
            SocialChatScreen(
              client: s.client,
              me: social.me,
              peer: social.peer,
              groupChat: group,
              attachmentPicker: reactionDraft,
            ),
            width: 390,
          );
          await t.enterText(find.byType(TextField), 'My caption');
          await t.tap(find.byKey(const ValueKey('reply-first')));
          await settleAssets(t);
          await t.tap(find.text(kind == 'gif' ? 'GIF' : 'Stickers'));
          await t.pump();
          await t.pump(const Duration(milliseconds: 300));
          expect(s.uploads, isEmpty);
          expect(find.text('My caption'), findsOneWidget);
          await t.tap(find.byTooltip('Send message'));
          await t.pump();
          await t.pump(const Duration(milliseconds: 300));
          expect(s.uploads.length, 1);
          expect(s.uploads.single['kind'], kind);
          expect(s.uploads.single[group ? 'group' : 'peer'], social.peer['id']);
          expect(find.text('My caption'), findsOneWidget);
          await t.tap(find.byTooltip('Send message'));
          await settleAssets(t);
          expect(s.uploads.length, 1);
          expect(s.sends.length, 2);
          expect(s.sends[0], s.sends[1]);
          expect(s.sends.last['reply_to'], 'first');
          expect(find.text('My caption'), findsNothing);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
