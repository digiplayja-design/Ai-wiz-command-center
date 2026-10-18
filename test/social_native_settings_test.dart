import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_notification_settings.dart';
import 'package:ai_wiz_command_center/social/social_push_platform.dart';
import 'package:ai_wiz_command_center/theme/korlix_action_button.dart';

import 'social_test.dart' as social;

class SettingsNativePush extends SocialPushPlatform {
  SettingsNativePush({
    this.provider = 'apns',
    this.supported = true,
    this.permission = 'default',
    this.record,
  });

  @override
  final String provider;
  @override
  final bool supported;
  @override
  final String permission;
  SocialMap? record;
  String? owner;
  int permissionRequests = 0, disabled = 0;

  @override
  bool get isNative => true;
  @override
  bool get launchRequested => false;
  @override
  String action(String suffix) => 'native_push_$suffix';
  @override
  void onOpen(void Function()? callback) {}
  @override
  Future<void> syncOwner(String owner) async {
    this.owner = owner;
  }
  @override
  Future<SocialMap?> current(String owner) async => record;
  @override
  Future<SocialMap> subscribe(String owner, String publicKey) async {
    permissionRequests++;
    return record ??= nativeRecord(provider: provider);
  }
  @override
  Future<void> unsubscribe(String owner) async {
    disabled++;
    record = null;
  }
}

SocialMap nativeRecord({String provider = 'apns'}) => {
  'device': 'device-fixture',
  'binding': 'binding-current',
  'subscription': {
    'provider': provider,
    'token': 'fixture-token',
    if (provider == 'apns') ...{
      'app_id': 'com.korlixdeveloper.korlixai',
      'environment': 'production',
    },
  },
};

SocialMap nativeState({bool apns = true, List<SocialMap> saved = const []}) => {
  'enabled': true,
  'providers': {
    'fcm': {'enabled': true},
    'apns': {'enabled': apns, 'reason': 'iOS notification delivery is not configured yet.'},
  },
  'subscriptions': saved,
};

SocialClient settingsClient(
  SettingsNativePush push,
  SocialMap state,
  List<SocialMap> requests,
) {
  final payload = base64Url.encode(utf8.encode(jsonEncode({
    'iss': 'https://fixture.test/auth/v1', 'sub': 'member-fixture',
  }))).replaceAll('=', '');
  return SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': 'Bearer header.$payload.signature'},
    client: MockClient((request) async {
      expect(push.owner, isNotNull, reason: 'native owner must sync before state');
      requests.add({
        'action': request.url.pathSegments.last,
        'method': request.method,
        ...request.url.queryParameters,
        if (request.method == 'POST') ...socialMap(jsonDecode(request.body)),
      });
      return http.Response(jsonEncode(request.method == 'GET' ? state : {'ok': true}), 200);
    }),
  );
}

Future<void> reveal(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(find.text(label), 250);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('native settings load never requests permission and disable binds the device', (tester) async {
    final push = SettingsNativePush(record: nativeRecord());
    final requests = <SocialMap>[];
    final client = settingsClient(push, nativeState(saved: [{
      'device': 'device-fixture', 'binding': 'binding-current', 'provider': 'apns',
      'messages': true, 'calls': false, 'online': false,
    }]), requests);
    addTearDown(client.dispose);
    await social.mount(tester, SocialNotificationSettings(client: client, platform: push));
    expect(push.permissionRequests, 0);
    expect(requests.single['action'], 'native_push_state');
    expect(requests.single['provider'], 'apns');
    expect(find.text('Enabled on this device'), findsOneWidget);
    await reveal(tester, 'Turn off on this device');
    await tester.tap(find.text('Turn off on this device'));
    await tester.pumpAndSettle();
    expect(push.disabled, 1);
    expect(requests.last, {
      'action': 'native_push_unsubscribe', 'method': 'POST',
      'device': 'device-fixture', 'binding': 'binding-current',
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale native binding cannot enable the new account and explicit enable registers current binding', (tester) async {
    final push = SettingsNativePush(record: nativeRecord());
    final requests = <SocialMap>[];
    final client = settingsClient(push, nativeState(saved: [{
      'device': 'device-fixture', 'binding': 'binding-previous-account', 'provider': 'apns',
      'messages': false, 'calls': false, 'online': true,
    }]), requests);
    addTearDown(client.dispose);
    await social.mount(tester, SocialNotificationSettings(client: client, platform: push));
    expect(find.text('Off on this device'), findsOneWidget);
    expect(push.permissionRequests, 0);
    await reveal(tester, 'Enable device notifications');
    await tester.tap(find.text('Enable device notifications'));
    await tester.pumpAndSettle();
    expect(push.permissionRequests, 1);
    expect(requests.last['action'], 'native_push_subscribe');
    expect(requests.last['binding'], 'binding-current');
    expect(requests.last['messages'], true);
    expect(requests.last['calls'], true);
    expect(requests.last['online'], false);
    expect(socialMap(requests.last['subscription'])['environment'], 'production');
    expect(tester.takeException(), isNull);
  });

  testWidgets('enabled Android provider does not enable unavailable iOS provider', (tester) async {
    final push = SettingsNativePush();
    final requests = <SocialMap>[];
    final client = settingsClient(push, nativeState(apns: false), requests);
    addTearDown(client.dispose);
    await social.mount(tester, SocialNotificationSettings(client: client, platform: push));
    expect(find.text('iOS notification delivery is not configured yet.'), findsOneWidget);
    await reveal(tester, 'Enable device notifications');
    final button = tester.widget<KorlixActionButton>(find.byType(KorlixActionButton));
    expect(button.onPressed, isNull);
    expect(push.permissionRequests, 0);
    expect(requests.length, 1);
  });

  testWidgets('unconfigured native build shows setup status without browser installation advice', (tester) async {
    final push = SettingsNativePush(supported: false);
    final client = settingsClient(push, nativeState(), []);
    addTearDown(client.dispose);
    await social.mount(tester, SocialNotificationSettings(client: client, platform: push));
    expect(find.textContaining('not configured for this app version'), findsOneWidget);
    expect(find.textContaining('Home Screen'), findsNothing);
    await reveal(tester, 'Enable device notifications');
    expect(tester.widget<KorlixActionButton>(find.byType(KorlixActionButton)).onPressed, isNull);
    expect(push.permissionRequests, 0);
  });

  for (final provider in ['fcm', 'apns']) {
    testWidgets('$provider settings explain native permissions and fit a narrow large-text screen', (tester) async {
      final push = SettingsNativePush(provider: provider, permission: 'denied');
      final client = settingsClient(push, nativeState(), []);
      addTearDown(client.dispose);
      await social.mount(tester, SocialNotificationSettings(client: client, platform: push),
        width: 320, scale: 2, theme: 'korlix_blue');
      await tester.scrollUntilVisible(find.textContaining('Allow KORLIX notifications'), 300);
      await tester.pumpAndSettle();
      expect(find.textContaining('device Settings'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining(provider == 'fcm' ? 'Keep this chat floating' : 'KORLIX opens after you unlock'), 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(push.permissionRequests, 0);
      expect(find.textContaining('Picture-in-Picture'), findsNothing);
    });
  }
}
