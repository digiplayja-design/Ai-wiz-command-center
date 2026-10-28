import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_wiz_command_center/social/social_appearance.dart';
import 'package:ai_wiz_command_center/social/social_screen.dart';
import 'package:ai_wiz_command_center/social/social_threads.dart';
import 'package:ai_wiz_command_center/social/social_online_settings.dart';
import 'package:ai_wiz_command_center/theme/korlix_appearance_preferences.dart';
import 'package:ai_wiz_command_center/theme/korlix_theme.dart';

import 'agent_studio_test.dart' as shots;
import 'social_test.dart' as fixtures;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fieldproof/Roboto-Bold.ttf')))
        .load();
    final sdk = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (sdk != null) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });

  test(
    'Social saves separately, restores the last rapid selection, and can follow the app',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        KorlixAppearancePreferences.storageKey,
        'app-look-untouched',
      );
      final store = SocialAppearancePreferences();
      await Future.wait([
        store.apply(KorlixAppearanceChoice('mint_cloud', 'glass')),
        store.apply(KorlixAppearanceChoice('pure_white', 'bubbles')),
      ]);
      final restored = SocialAppearancePreferences();
      await restored.restore();
      expect(restored.choice!.themeId, 'pure_white');
      expect(restored.choice!.skinId, 'bubbles');
      expect(
        prefs.getString(KorlixAppearancePreferences.storageKey),
        'app-look-untouched',
      );
      await restored.apply(null);
      final follow = SocialAppearancePreferences();
      await follow.restore();
      expect(follow.choice, isNull);
      store.dispose();
      restored.dispose();
      follow.dispose();
    },
  );

  test(
    'late restore cannot overwrite a new selection and storage failure is reported',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        SocialAppearancePreferences.storageKey,
        jsonEncode({'theme': 'pure_white', 'skin': 'linen'}),
      );
      final gate = Completer<SharedPreferences>();
      final store = SocialAppearancePreferences(load: () => gate.future);
      final restoring = store.restore();
      final saving = store.apply(KorlixAppearanceChoice('ocean_blue', 'orbit'));
      gate.complete(prefs);
      await restoring;
      await saving;
      expect(store.choice!.themeId, 'ocean_blue');
      final failing = SocialAppearancePreferences(
        load: () => Future.error(StateError('storage unavailable')),
      );
      expect(
        await failing.apply(KorlixAppearanceChoice('mint_cloud', 'glass')),
        isFalse,
      );
      expect(failing.choice!.skinId, 'glass');
      store.dispose();
      failing.dispose();
    },
  );

  testWidgets(
    'preview can be cancelled, applied, and reset to the app without changing the app palette',
    (t) async {
      final store = SocialAppearancePreferences();
      final data = fixtures.Store();
      final appTheme = kKorlixThemeNotifier.value;
      await fixtures.mount(
        t,
        SocialAppearance(
          preferences: store,
          child: SocialScreen(client: data.client),
        ),
      );
      await t.tap(find.byKey(const Key('social-appearance-button')));
      await t.pumpAndSettle();
      expect(find.text('Style your Social'), findsOneWidget);
      final color = find.byKey(const Key('theme-preview-mint_cloud'));
      await t.ensureVisible(color);
      await t.tap(color);
      await t.pumpAndSettle();
      expect(store.choice, isNull);
      await t.tap(find.byTooltip('Close appearance preview'));
      await t.pumpAndSettle();
      expect(store.choice, isNull);
      await t.tap(find.byKey(const Key('social-appearance-button')));
      await t.pumpAndSettle();
      await t.ensureVisible(color);
      await t.tap(color);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('appearance-tab-1')));
      await t.pumpAndSettle();
      final skin = find.byKey(const Key('skin-bubbles'));
      await t.ensureVisible(skin);
      await t.tap(skin);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('apply-appearance')));
      await t.pumpAndSettle();
      expect(store.choice!.themeId, 'mint_cloud');
      expect(store.choice!.skinId, 'bubbles');
      expect(kKorlixThemeNotifier.value, appTheme);
      expect(
        korlixSkinOf(t.element(find.byType(SocialScreen))).id,
        'mint_cloud',
      );
      await t.tap(find.byKey(const Key('social-appearance-button')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('social-use-app-appearance')));
      await t.tap(find.byKey(const Key('social-use-app-appearance')));
      await t.pumpAndSettle();
      expect(store.choice, isNull);
      expect(
        korlixSkinOf(t.element(find.byType(SocialScreen))).id,
        'pure_black',
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('changing a real chat look keeps its draft and scroll position', (
    t,
  ) async {
    final store = SocialAppearancePreferences();
    final data = fixtures.Store();
    data.messages.addAll(
      List.generate(
        16,
        (i) => {
          'id': 'message-$i',
          'seq': i + 1,
          'sender': i.isEven ? 'peer' : 'me',
          'body': 'Sample conversation message $i',
          'created_at': '2026-10-11T12:00:00Z',
        },
      ),
    );
    await fixtures.mount(
      t,
      SocialAppearance(
        preferences: store,
        defaultChoice: messengerDefaultAppearance,
        child: SocialChatScreen(
          client: data.client,
          me: fixtures.me,
          peer: fixtures.peer,
        ),
      ),
    );
    final input = find.byType(TextField).last;
    expect(korlixSkinOf(t.element(input)).id, 'pure_black');
    expect(socialScreenSkinOf(t.element(input)), 'bubbles');
    await shots.capture(t, 'messenger-black-yellow-chat');
    await t.enterText(input, 'Keep this draft exactly.');
    final chatState = t.state(find.byType(SocialChatScreen));
    final scroll = t.widget<ListView>(find.byType(ListView).first).controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent / 2);
    await t.pumpAndSettle();
    final position = scroll.offset;
    await store.apply(KorlixAppearanceChoice('pure_white', 'glass'));
    await t.pumpAndSettle();
    expect(
      identical(t.state(find.byType(SocialChatScreen)), chatState),
      isTrue,
    );
    expect(
      t.widget<TextField>(input).controller!.text,
      'Keep this draft exactly.',
    );
    expect(scroll.offset, closeTo(position, 1));
    expect(korlixSkinOf(t.element(input)).id, 'pure_white');
    expect(socialScreenSkinOf(t.element(input)), 'glass');
    expect(data.calls.where((c) => c['action'] == 'send'), isEmpty);
    expect(t.takeException(), isNull);
    await shots.capture(t, 'social-chat-white-glass');
    await store.apply(null);
    await t.pumpAndSettle();
    expect(socialScreenSkinOf(t.element(input)), 'bubbles');
    expect(korlixSkinOf(t.element(input)).id, 'pure_black');
    expect(
      identical(t.state(find.byType(SocialChatScreen)), chatState),
      isTrue,
    );
    expect(
      t.widget<TextField>(input).controller!.text,
      'Keep this draft exactly.',
    );
  });

  testWidgets(
    'Social routes carry their look while the rest of the app keeps its theme',
    (t) async {
      await t.runAsync(
        () => kSocialAppearance.apply(
          KorlixAppearanceChoice('lavender_mist', 'mesh'),
        ),
      );
      addTearDown(() => t.runAsync(() => kSocialAppearance.apply(null)));
      final data = fixtures.Store();
      await fixtures.mount(
        t,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                SocialPageRoute<void>(
                  builder: (_) => SocialOnlineSettings(client: data.client),
                ),
              ),
              child: const Text('Open Social'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open Social'));
      await t.pumpAndSettle();
      expect(
        korlixSkinOf(t.element(find.byType(SocialOnlineSettings))).id,
        'lavender_mist',
      );
      expect(
        socialScreenSkinOf(t.element(find.byType(SocialOnlineSettings))),
        'mesh',
      );
      await t.pageBack();
      await t.pumpAndSettle();
      expect(
        korlixSkinOf(t.element(find.text('Open Social'))).id,
        'pure_black',
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('Social preview and controls fit narrow phones and tablets', (
    t,
  ) async {
    final store = SocialAppearancePreferences();
    for (final (width, height, scale, theme, skin) in [
      (320.0, 740.0, 1.6, 'pure_white', 'glass'),
      (390.0, 844.0, 1.0, 'korlix_blue', 'orbit'),
      (1024.0, 1366.0, 1.0, 'pink_white', 'bubbles'),
    ]) {
      await t.pumpWidget(const SizedBox());
      final data = fixtures.Store();
      await t.runAsync(() => store.apply(KorlixAppearanceChoice(theme, skin)));
      await fixtures.mount(
        t,
        SocialAppearance(
          preferences: store,
          child: SocialScreen(client: data.client),
        ),
        width: width,
        height: height,
        scale: scale,
      );
      expect(t.takeException(), isNull);
      await shots.capture(t, 'social-home-$theme');
      await t.tap(find.byKey(const Key('social-appearance-button')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const Key('apply-appearance')).hitTestable(),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await shots.capture(t, 'social-picker-$theme');
      await t.tap(find.byKey(const Key('appearance-tab-1')));
      await t.pumpAndSettle();
      final linen = find.byKey(const Key('skin-linen'));
      await t.ensureVisible(linen);
      await t.tap(linen);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const Key('apply-appearance')));
      await t.pumpAndSettle();
      expect(store.choice!.skinId, 'linen');
      expect(t.takeException(), isNull);
    }
  });
}
