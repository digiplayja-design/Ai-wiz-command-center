import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_screen.dart';
import 'social_test.dart' as fixtures;

void main() {
  for (final messenger in [true, false]) {
    testWidgets(
      'visible status control confirms online/offline in ${messenger ? 'Messenger' : 'Social'}',
      (tester) async {
        var visible = false, fail = false;
        Completer<http.Response>? gate;
        final writes = <Map<String, dynamic>>[];
        final client = SocialClient(
          baseUrl: 'https://fixture.test',
          headersBuilder: () => {'Authorization': 'Bearer local'},
          client: MockClient((r) async {
            final action = r.url.pathSegments.last;
            if (action == 'bootstrap')
              return http.Response(
                jsonEncode({
                  'profile': {...fixtures.me, 'show_online': visible},
                  'categories': fixtures.categories,
                }),
                200,
              );
            if (action == 'presence') {
              final data = jsonDecode(r.body) as Map<String, dynamic>;
              if (data.containsKey('show_online')) {
                writes.add(data);
                if (gate != null) return gate!.future;
                if (fail) return http.Response('{}', 503);
                visible = data['show_online'] == true;
              }
              return http.Response(
                jsonEncode({
                  'ok': true,
                  'show_online': visible,
                  'online': visible,
                }),
                200,
              );
            }
            return http.Response('{"items":[]}', 200);
          }),
        );
        await fixtures.mount(
          tester,
          SocialScreen(client: client, messengerMode: messenger),
          width: 320,
          scale: 1.4,
        );
        expect(find.text('You: Offline'), findsOneWidget);
        await tester.tap(find.byKey(const Key('social-presence-button')));
        await tester.pumpAndSettle();
        gate = Completer<http.Response>();
        await tester.tap(find.text('Go online'));
        await tester.pumpAndSettle();
        expect(find.text('Updating status…'), findsOneWidget);
        expect(find.text('You: Online'), findsNothing);
        gate!.complete(
          http.Response('{"ok":true,"show_online":true,"online":true}', 200),
        );
        visible = true;
        gate = null;
        await tester.pumpAndSettle();
        expect(find.text('You: Online'), findsOneWidget);
        fail = true;
        await tester.tap(find.byKey(const Key('social-presence-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Appear offline'));
        await tester.pumpAndSettle();
        expect(find.text('You: Offline'), findsNothing);
        expect(find.textContaining('could not confirm'), findsOneWidget);
        fail = false;
        await tester.tap(find.byKey(const Key('social-presence-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Appear offline'));
        await tester.pumpAndSettle();
        expect(find.text('You: Offline'), findsOneWidget);
        expect(writes.map((x) => x['show_online']), [true, false, false]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
