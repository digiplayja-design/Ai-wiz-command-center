import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import 'social_client.dart';

/// Shares selected content through the OS chooser. Private storage links never
/// leave the app; attachments are fetched after a fresh access check.
class SocialMessageSharer {
  SocialMessageSharer({this.transportBuilder, this.present});
  final http.Client Function()? transportBuilder;
  final Future<void> Function(ShareParams params)? present;

  Future<void> share({
    required SocialClient client,
    required SocialMap message,
    required Rect origin,
    required bool Function() stillAvailable,
  }) async {
    final attachment = socialMap(message['attachment']);
    final files = <XFile>[];
    void check() {
      if (!client.available || !stillAvailable()) {
        throw const SocialException('This message is no longer available.');
      }
    }

    check();
    if (attachment.isNotEmpty) {
      final link = await client.get('attachment_link', {
        'id': attachment['id'],
      });
      check();
      final url = Uri.tryParse('${link['url']}');
      if (url == null || url.scheme != 'https' || !url.hasAuthority) {
        throw const SocialException('This attachment could not be shared.');
      }
      final transport = transportBuilder?.call() ?? http.Client();
      try {
        final response = await transport
            .send(http.Request('GET', url))
            .timeout(const Duration(seconds: 20));
        const limit = 20 * 1024 * 1024;
        if (response.statusCode != 200 ||
            (response.contentLength ?? 0) > limit) {
          throw const SocialException(
            'This attachment could not be downloaded.',
          );
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 20),
        )) {
          check();
          if (bytes.length + chunk.length > limit) {
            throw const SocialException(
              'This attachment is too large to share.',
            );
          }
          bytes.add(chunk);
        }
        check();
        if (bytes.isEmpty)
          throw const SocialException('This attachment is empty.');
        files.add(
          XFile.fromData(
            bytes.takeBytes(),
            mimeType:
                '${attachment['content_type'] ?? 'application/octet-stream'}',
            name: '${attachment['filename'] ?? 'Attachment'}',
          ),
        );
      } finally {
        transport.close();
      }
    }
    check();
    final body = '${message['body'] ?? ''}'.trim();
    if (body.isEmpty && files.isEmpty) return;
    final params = ShareParams(
      text: body.isEmpty ? null : body,
      files: files.isEmpty ? null : files,
      fileNameOverrides: files.isEmpty
          ? null
          : ['${attachment['filename'] ?? 'Attachment'}'],
      sharePositionOrigin: origin,
    );
    if (present != null) {
      await present!(params);
    } else {
      await SharePlus.instance.share(params);
    }
  }
}
