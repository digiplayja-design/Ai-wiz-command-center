import 'dart:convert';
import 'social_client.dart';

/// Only an account identifier is persisted; never an auth token or session ID.
String socialPushOwner(Map<String, String> headers) {
  try {
    final auth = headers.entries
        .firstWhere((e) => e.key.toLowerCase() == 'authorization')
        .value;
    final payload = socialMap(
      jsonDecode(
        utf8.decode(
          base64Url.decode(
            base64Url.normalize(auth.split(' ').last.split('.')[1]),
          ),
        ),
      ),
    );
    if (payload['sub'] is String && payload['iss'] is String) {
      return jsonEncode([payload['iss'], payload['sub']]);
    }
  } catch (_) {}
  return '';
}

abstract class SocialPushPlatform {
  bool get supported;
  String get permission;
  bool get launchRequested;
  void onOpen(void Function()? callback);
  Future<void> syncOwner(String owner);
  Future<SocialMap?> current(String owner);

  /// Must be called directly from the Enable tap to preserve user activation.
  Future<SocialMap> subscribe(String owner, String publicKey);
  Future<void> unsubscribe(String owner);
}
