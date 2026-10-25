import 'dart:async';

import 'social_push_platform.dart';
import 'social_client.dart';
import 'social_native_bridge.dart';

SocialPushPlatform createSocialPushPlatform() => NativeSocialPushPlatform();

class NativeSocialPushPlatform extends SocialPushPlatform {
  SocialMap _capabilities = {};
  String _owner = '';
  StreamSubscription<SocialMap>? _events;
  void Function()? _onOpen;
  Future<void> _sync = Future<void>.value();

  @override
  bool get isNative => true;
  @override
  String get provider => '${_capabilities['provider'] ?? ''}';
  @override
  String action(String suffix) => 'native_push_$suffix';
  @override
  bool get supported => SocialNativeBridge.mobile && _capabilities['push'] == true;
  @override
  String get permission => '${_capabilities['permission'] ?? 'default'}';
  @override
  bool get launchRequested => false;

  @override
  void onOpen(void Function()? callback) {
    _onOpen = callback;
    if (callback == null) {
      unawaited(_events?.cancel());
      _events = null;
    } else {
      _events ??= SocialNativeBridge.events.listen((event) {
        if (event['owner'] == _owner &&
            ['open', 'reply'].contains(event['type'])) {
          _onOpen?.call();
        }
      });
    }
  }

  @override
  Future<void> syncOwner(String owner) {
    _owner = owner;
    final operation = _sync.then((_) async {
      // Logout must reach native even if the same account signs in immediately:
      // it rotates the epoch that invalidates old bubbles and pending intents.
      await SocialNativeBridge.invoke<bool>('activate', {'owner': owner});
      final state = await SocialNativeBridge.invoke<Map>('capabilities');
      if (_owner == owner) _capabilities = socialMap(state);
    });
    _sync = operation.catchError((Object _) {});
    return operation;
  }

  @override
  Future<SocialMap?> takeAction() async {
    if (_owner.isEmpty) return null;
    final owner = _owner;
    final value = await SocialNativeBridge.invoke<Map>('takeEvent', {'owner': owner});
    final action = socialMap(value);
    return _owner == owner && action['owner'] == owner ? action : null;
  }

  @override
  Future<SocialMap?> current(String owner) async {
    if (owner.isEmpty || owner != _owner) return null;
    final result = await SocialNativeBridge.invoke<Map>('current', {'owner': owner});
    return _owner == owner && result != null ? socialMap(result) : null;
  }

  @override
  Future<SocialMap> subscribe(String owner, String publicKey) async {
    if (!supported || owner.isEmpty || owner != _owner) {
      throw const SocialException('Mobile notifications are not configured in this build yet.');
    }
    final result = await SocialNativeBridge.invoke<Map>('subscribe', {'owner': owner});
    if (_owner != owner || result == null) {
      throw const SocialException('Notifications were not enabled. Check notification permission and try again.');
    }
    final state = await SocialNativeBridge.invoke<Map>('capabilities');
    if (_owner != owner) throw const SocialException('Your account changed. Reopen Social.');
    _capabilities = socialMap(state);
    return socialMap(result);
  }

  @override
  Future<void> unsubscribe(String owner) async {
    if (owner != _owner) return;
    await SocialNativeBridge.invoke<Map>('unsubscribe', {'owner': owner});
  }
}
