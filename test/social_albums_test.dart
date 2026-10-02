import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ai_wiz_command_center/social/social_albums.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';

void main() {
  testWidgets(
    'album creation starts with connections visibility and opens the saved collection',
    (t) async {
      final writes = <SocialMap>[];
      final client = SocialClient(
        baseUrl: 'https://fixture.test',
        headersBuilder: () => {'Authorization': 'Bearer fixture'},
        client: MockClient((r) async {
          final action = r.url.pathSegments.last;
          SocialMap data = {};
          if (r.method == 'POST') {
            data = socialMap(jsonDecode(r.body));
            writes.add({'action': action, ...data});
          }
          return http.Response(
            jsonEncode(
              action == 'albums'
                  ? {'items': []}
                  : action == 'album_create'
                  ? {
                      'album': {
                        'id': 'new',
                        'title': data['title'],
                        'visibility': data['visibility'],
                        'photo_count': 0,
                      },
                    }
                  : {
                      'album': {
                        'id': 'new',
                        'title': 'Family',
                        'visibility': 'connections',
                      },
                      'items': [],
                    },
            ),
            200,
          );
        }),
      );
      await t.pumpWidget(
        MaterialApp(
          home: SocialAlbumsScreen(
            client: client,
            profile: const {'id': 'me', 'name': 'Ricardo'},
            owned: true,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Create album'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Family');
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Create album'));
      await t.pumpAndSettle();
      expect(writes.single['visibility'], 'connections');
      expect(find.text('Add photos'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
      client.dispose();
    },
  );
  for (final width in [390.0, 1024.0]) {
    testWidgets('multi-photo upload preserves retry IDs and layout at $width', (
      t,
    ) async {
      await t.binding.setSurfaceSize(Size(width, 850));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final requests = <String>[], saved = <String>[];
      bool fail = true;
      final revision = ValueNotifier(0);
      String token = 'Bearer owner';
      final client = SocialClient(
        baseUrl: 'https://fixture.test',
        headersBuilder: () => {'Authorization': token},
        sessionChanges: revision,
        client: MockClient((r) async {
          final action = r.url.pathSegments.last;
          if (action == 'album_upload') {
            final id = r.url.queryParameters['photo']!;
            requests.add(id);
            if (requests.length == 2 && fail) {
              return http.Response('{"error":"Temporary interruption"}', 503);
            }
            saved.add(id);
            return http.Response('{"ok":true}', 200);
          }
          return http.Response(
            jsonEncode({
              'album': {
                'id': 'album',
                'title': 'Family',
                'visibility': 'connections',
              },
              'items': [
                for (final id in saved) {'id': id},
              ],
            }),
            200,
          );
        }),
      );
      await t.pumpWidget(
        MaterialApp(
          home: SocialAlbumScreen(
            client: client,
            album: const {
              'id': 'album',
              'title': 'Family',
              'visibility': 'connections',
            },
            owned: true,
            picker: () async => [
              XFile.fromData(Uint8List.fromList([1]), name: 'one.jpg'),
              XFile.fromData(Uint8List.fromList([2]), name: 'two.jpg'),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Add photos'));
      await t.pumpAndSettle();
      expect(find.text('1 of 2 photos saved'), findsOneWidget);
      expect(find.text('Retry failed photos'), findsOneWidget);
      fail = false;
      await t.tap(find.text('Retry failed photos'));
      await t.pumpAndSettle();
      expect(requests.length, 3);
      expect(requests[1], requests[2]);
      expect(find.text('2 of 2 photos saved'), findsOneWidget);
      expect(t.takeException(), isNull);
      token = 'Bearer different-account';
      revision.value++;
      await t.pumpAndSettle();
      expect(find.text('Sign in and reopen Social.'), findsOneWidget);
      expect(find.text('2 of 2 photos saved'), findsNothing);
      await t.pumpWidget(const SizedBox());
      client.dispose();
      revision.dispose();
    });
  }
  testWidgets('visitors cannot see upload or album management controls', (
    t,
  ) async {
    final client = SocialClient(
      baseUrl: 'https://fixture.test',
      headersBuilder: () => {'Authorization': 'Bearer viewer'},
      client: MockClient(
        (r) async => http.Response(
          '{"album":{"id":"a","title":"Shared","visibility":"members"},"items":[]}',
          200,
        ),
      ),
    );
    await t.pumpWidget(
      MaterialApp(
        home: SocialAlbumScreen(
          client: client,
          album: const {'id': 'a'},
          owned: false,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Add photos'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    await t.pumpWidget(const SizedBox());
    client.dispose();
  });
}
