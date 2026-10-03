import 'dart:async';

import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_media_widgets.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final pending in [false, true]) {
    testWidgets(
      pending
          ? 'expired attachment cannot open after a late signed-link response'
          : 'removing a message closes its detached fullscreen photo only',
      (tester) async {
        final visible = ValueNotifier(true);
        final response = Completer<http.Response>();
        final client = SocialClient(
          baseUrl: 'https://fixture.test',
          headersBuilder: () => {'Authorization': 'Bearer fixture-account'},
          client: MockClient((_) async {
            if (pending) return response.future;
            return http.Response(
              '{"url":"https://fixture.test/photo.png"}',
              200,
            );
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: korlixBuildTheme('pure_black'),
            home: Scaffold(
              appBar: AppBar(title: const Text('Chat stays open')),
              body: ValueListenableBuilder<bool>(
                valueListenable: visible,
                builder: (context, present, _) => present
                    ? SocialAttachmentView(
                        client: client,
                        attachment: const {
                          'id': 'photo',
                          'kind': 'image',
                          'filename': 'Photo.png',
                          'size_bytes': 100,
                          'url': 'https://fixture.test/thumbnail.png',
                        },
                      )
                    : const Text('Message dumped'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Failed fixture images show a retry button over the photo gesture.
        tester
            .widget<GestureDetector>(
              find
                  .descendant(
                    of: find.byType(SocialAttachmentView),
                    matching: find.byType(GestureDetector),
                  )
                  .first,
            )
            .onTap!();
        await tester.pumpAndSettle();
        if (!pending) expect(find.text('Photo'), findsOneWidget);
        visible.value = false;
        await tester.pumpAndSettle();
        if (pending) {
          response.complete(
            http.Response('{"url":"https://fixture.test/photo.png"}', 200),
          );
          await tester.pumpAndSettle();
        }
        expect(find.text('Photo'), findsNothing);
        expect(find.text('Chat stays open'), findsOneWidget);
        expect(find.text('Message dumped'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        visible.dispose();
        client.dispose();
      },
    );
  }
}
