import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'social_client.dart';
import 'social_push_platform.dart';

SocialPushPlatform createSocialPushPlatform() => _BrowserPush();

class _BrowserPush extends SocialPushPlatform {
  JSFunction? _listener;
  static const _key = 'korlix-social-push-v1';
  String get _scope => Uri.base.resolve('social-push/').toString();
  @override
  bool get supported =>
      web.window.isSecureContext &&
      web.window.navigator.hasProperty('serviceWorker'.toJS).toDart &&
      web.window.hasProperty('PushManager'.toJS).toDart &&
      web.window.hasProperty('Notification'.toJS).toDart;
  @override
  String get permission =>
      supported ? web.Notification.permission : 'unsupported';
  @override
  bool get launchRequested => Uri.base.queryParameters['social'] == '1';
  @override
  void onOpen(void Function()? callback) {
    if (!supported) return;
    if (_listener != null) {
      web.window.navigator.serviceWorker.removeEventListener(
        'message',
        _listener,
      );
    }
    _listener = callback == null
        ? null
        : ((web.MessageEvent event) {
            final data = socialMap(event.data.dartify());
            if (data['type'] == 'korlix-social-open' &&
                data['binding'] != null &&
                data['binding'] == _saved()['binding']) {
              callback();
            }
          }).toJS;
    if (_listener != null) {
      web.window.navigator.serviceWorker.addEventListener('message', _listener);
    }
  }

  SocialMap _saved() {
    try {
      return socialMap(
        jsonDecode(web.window.localStorage.getItem(_key) ?? '{}'),
      );
    } catch (_) {
      return {};
    }
  }

  Future<web.ServiceWorkerRegistration?> _registration() =>
      web.window.navigator.serviceWorker.getRegistration(_scope).toDart;
  Future<void> _message(
    web.ServiceWorkerRegistration registration,
    SocialMap data,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (registration.active == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final worker = registration.active;
    if (worker == null) {
      throw const SocialException(
        'Notification setup is still loading. Try again.',
      );
    }
    final channel = web.MessageChannel(), done = Completer<void>();
    channel.port1.onmessage = ((web.MessageEvent event) {
      if (!done.isCompleted) done.complete();
    }).toJS;
    worker.postMessage(data.jsify(), [channel.port2].toJS);
    try {
      await done.future.timeout(const Duration(seconds: 10));
    } finally {
      channel.port1.close();
    }
  }

  @override
  Future<void> syncOwner(String owner) async {
    if (!supported) return;
    final saved = _saved();
    if (saved['owner'] == owner) return;
    // Clear the local binding first. A late subscribe response cannot restore
    // an old account after logout; the service worker refuses its pushes.
    web.window.localStorage.setItem(_key, jsonEncode({'owner': owner}));
    final registration = await _registration();
    if (registration != null) {
      await _message(registration, {'type': 'clear'});
      final subscription = await registration.pushManager
          .getSubscription()
          .toDart;
      await subscription?.unsubscribe().toDart;
    }
  }

  @override
  Future<SocialMap?> current(String owner) async {
    if (!supported || owner.isEmpty || _saved()['owner'] != owner) return null;
    final saved = _saved(), registration = await _registration();
    final subscription = await registration?.pushManager
        .getSubscription()
        .toDart;
    if (subscription == null ||
        saved['binding'] == null ||
        saved['device'] == null) {
      return null;
    }
    return {
      ...saved,
      'subscription': socialMap(subscription.toJSON().dartify()),
    };
  }

  @override
  Future<SocialMap> subscribe(String owner, String publicKey) async {
    if (!supported || owner.isEmpty) {
      throw const SocialException(
        'Sign in using a supported browser to enable notifications.',
      );
    }
    // Request permission before the first await, within the button gesture.
    final permissionRequest = web.Notification.requestPermission().toDart;
    final allowed = (await permissionRequest).toDart;
    if (allowed != 'granted') {
      throw const SocialException(
        'Notifications were not allowed. You can change this in your browser’s site settings.',
      );
    }
    if (_saved()['owner'] != owner) {
      throw const SocialException(
        'Your account changed. Reopen notification settings.',
      );
    }
    final registration = await web.window.navigator.serviceWorker
        .register(
          Uri.base.resolve('korlix_social_push_sw.js').toString().toJS,
          web.RegistrationOptions(scope: _scope),
        )
        .toDart;
    // Wait for activation before PushManager.subscribe, without waiting for a
    // document controller: this registration intentionally controls no pages.
    await _message(registration, {'type': 'clear'});
    final existing = await registration.pushManager.getSubscription().toDart;
    if (existing != null) await existing.unsubscribe().toDart;
    final subscription = await registration.pushManager
        .subscribe(
          web.PushSubscriptionOptionsInit(
            userVisibleOnly: true,
            applicationServerKey: base64Url
                .decode(base64Url.normalize(publicKey))
                .toJS,
          ),
        )
        .toDart;
    if (_saved()['owner'] != owner) {
      await subscription.unsubscribe().toDart;
      throw const SocialException(
        'Your account changed. Reopen notification settings.',
      );
    }
    final result = <String, dynamic>{
      'owner': owner,
      'device': socialId(),
      'binding': socialId(),
      'subscription': socialMap(subscription.toJSON().dartify()),
    };
    web.window.localStorage.setItem(
      _key,
      jsonEncode({
        'owner': owner,
        'device': result['device'],
        'binding': result['binding'],
      }),
    );
    await _message(registration, {
      'type': 'bind',
      'binding': result['binding'],
    });
    if (_saved()['owner'] != owner) {
      throw const SocialException(
        'Your account changed. Reopen notification settings.',
      );
    }
    return result;
  }

  @override
  Future<void> unsubscribe(String owner) async {
    if (!supported || _saved()['owner'] != owner) return;
    web.window.localStorage.setItem(_key, jsonEncode({'owner': owner}));
    final registration = await _registration();
    if (registration == null) return;
    await _message(registration, {'type': 'clear'});
    final subscription = await registration.pushManager
        .getSubscription()
        .toDart;
    await subscription?.unsubscribe().toDart;
  }
}
