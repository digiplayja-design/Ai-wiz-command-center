import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:korlix_social_core/social/social_client.dart';
import 'package:korlix_social_core/social/social_message_share.dart';
import 'package:korlix_social_core/social/social_media_widgets.dart';
import 'package:korlix_social_core/social/social_threads.dart';
import 'package:korlix_social_core/social/social_video_attachment.dart';

import 'social_test.dart' as social;

class ShareClient extends SocialClient {
  ShareClient()
    : super(
        baseUrl: 'https://fixture.test',
        headersBuilder: () => {'Authorization': 'Bearer account'},
      );
  final requested = <String>[];
  @override
  Future<SocialMap> get(String action, [SocialMap data = const {}]) async {
    requested.add('$action:${data['id']}');
    return {'url': 'https://private.fixture.test/temporary-secret'};
  }
}

void main() {
  test(
    'sharing a video exports bytes and never exposes its private link',
    () async {
      final client = ShareClient();
      ShareParams? shared;
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final sharer = SocialMessageSharer(
        transportBuilder: () =>
            MockClient((request) async => http.Response.bytes(bytes, 200)),
        present: (params) async {
          shared = params;
        },
      );
      await sharer.share(
        client: client,
        message: {
          'body': 'A video for you',
          'attachment': {
            'id': 'video-one',
            'kind': 'file',
            'content_type': 'video/mp4',
            'filename': 'Clip.mp4',
          },
        },
        origin: const Rect.fromLTWH(0, 0, 100, 50),
        stillAvailable: () => true,
      );
      expect(client.requested, ['attachment_link:video-one']);
      expect(shared!.text, 'A video for you');
      expect(shared!.uri, isNull);
      expect(shared!.fileNameOverrides, ['Clip.mp4']);
      expect(await shared!.files!.single.readAsBytes(), bytes);
      client.dispose();
    },
  );
  test('removed messages cannot reach the OS share sheet', () async {
    final client = ShareClient();
    final sharer = SocialMessageSharer(
      present: (_) async {
        fail('Do not share removed content');
      },
    );
    await expectLater(
      sharer.share(
        client: client,
        message: {'body': 'Removed'},
        origin: Rect.zero,
        stillAvailable: () => false,
      ),
      throwsA(isA<SocialException>()),
    );
    expect(client.requested, isEmpty);
    client.dispose();
  });
  test(
    'access lost while downloading prevents sharing attachment bytes',
    () async {
      final client = ShareClient();
      var available = true;
      final sharer = SocialMessageSharer(
        transportBuilder: () => MockClient((_) async {
          available = false;
          return http.Response('private', 200);
        }),
        present: (_) async {
          fail('Do not share after access is lost');
        },
      );
      await expectLater(
        sharer.share(
          client: client,
          message: {
            'attachment': {'id': 'a'},
          },
          origin: Rect.zero,
          stillAvailable: () => available,
        ),
        throwsA(isA<SocialException>()),
      );
      client.dispose();
    },
  );
  testWidgets('messages expose Share and the composer accepts videos', (
    t,
  ) async {
    final store = social.Store();
    store.messages.add({
      'id': 'm1',
      'seq': 1,
      'sender': 'me',
      'body': 'Share this message',
      'deleted': false,
      'created_at': '2026-10-28T12:00:00Z',
    });
    ShareParams? shared;
    String? picked;
    await t.pumpWidget(
      MaterialApp(
        home: SocialChatScreen(
          client: store.client,
          me: social.me,
          peer: social.peer,
          messageSharer: SocialMessageSharer(
            present: (params) async {
              shared = params;
            },
          ),
          attachmentPicker: (kind) async {
            picked = kind;
            return null;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('share-m1')));
    await t.pumpAndSettle();
    expect(shared!.text, 'Share this message');
    await t.ensureVisible(find.text('Video'));
    await t.tap(find.text('Video'));
    await t.pumpAndSettle();
    expect(picked, 'video');
    await t.pumpWidget(const SizedBox());
    store.client.dispose();
  });
  testWidgets('private video is not fetched or played until Play', (t) async {
    final client = ShareClient();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SocialAttachmentView(
            client: client,
            attachment: {
              'id': 'v',
              'kind': 'file',
              'content_type': 'video/mp4',
              'filename': 'Video.mp4',
              'size_bytes': 4,
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(SocialVideoAttachment), findsOneWidget);
    expect(find.text('Play video'), findsOneWidget);
    expect(client.requested, isEmpty);
    await t.pumpWidget(const SizedBox());
    client.dispose();
  });
}
