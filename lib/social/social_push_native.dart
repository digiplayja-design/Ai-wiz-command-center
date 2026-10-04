import 'social_push_platform.dart';
import 'social_client.dart';

SocialPushPlatform createSocialPushPlatform() => _UnavailablePush();

class _UnavailablePush extends SocialPushPlatform {
  @override
  bool get supported => false;
  @override
  String get permission => 'unsupported';
  @override
  bool get launchRequested => false;
  @override
  void onOpen(void Function()? callback) {}
  @override
  Future<void> syncOwner(String owner) async {}
  @override
  Future<SocialMap?> current(String owner) async => null;
  @override
  Future<SocialMap> subscribe(String owner, String publicKey) async =>
      throw const SocialException(
        'Background notifications are not available in this build.',
      );
  @override
  Future<void> unsubscribe(String owner) async {}
}
