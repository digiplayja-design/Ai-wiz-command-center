import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ai_wiz_command_center/social/social_alert_overlay.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final captureKey = GlobalKey();

Future<void> capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['SOCIAL_ALERT_SCREENSHOTS'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary =
        captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class AlertFixture extends SocialNotifications {
  AlertFixture(this.session)
    : super(
        baseUrl: 'https://fixture.test',
        headersBuilder: () => {},
        sessionChanges: session,
        shouldPoll: () => false,
        interval: const Duration(days: 1),
      );

  final ValueNotifier<int> session;
  SocialUnreadConversation? message;
  SocialMap? call;
  int messageVersion = 0, callVersion = 0, dismissals = 0;
  bool activeCall = false;

  @override
  SocialUnreadConversation? get messageAlert => message;
  @override
  int get messageRevision => messageVersion;
  @override
  SocialMap? get incomingCall => call;
  @override
  int get callRevision => callVersion;
  @override
  bool get callOpen => activeCall;

  void showMessage({bool group = false, String name = 'Maria Green'}) {
    message = SocialUnreadConversation(
      card: {
        'id': group ? 'group-one' : 'peer-one',
        'name': name,
        'body': 'Private message contents must never appear in this alert.',
      },
      group: group,
      unread: 1,
    );
    messageVersion++;
    notifyListeners();
  }

  void showCall({bool video = false}) {
    call = {
      'id': 'call-one',
      'mode': video ? 'video' : 'audio',
      'peer': {'id': 'caller-one', 'name': 'Chris Blue'},
    };
    callVersion++;
    notifyListeners();
  }

  void clearCall() {
    call = null;
    notifyListeners();
  }

  void clearAll() {
    message = null;
    call = null;
    notifyListeners();
  }

  @override
  void dismissMessage() {
    dismissals++;
    message = null;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
    session.dispose();
  }
}

Widget app(
  AlertFixture alerts, {
  GlobalKey<NavigatorState>? navigatorKey,
  Widget? home,
  Future<void> Function(SocialUnreadConversation)? onMessage,
  Future<void> Function(SocialMap)? onCall,
  Future<void> Function(SocialMap)? onDecline,
  bool busy = false,
  String? error,
  bool reduceMotion = false,
  bool accessibleNavigation = false,
  double textScale = 1,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: reduceMotion,
      accessibleNavigation: accessibleNavigation,
      textScaler: TextScaler.linear(textScale),
    ),
    child: RepaintBoundary(
      key: captureKey,
      child: SocialAlertOverlay(
        notifications: alerts,
        onOpenMessage: onMessage ?? (_) async {},
        onOpenCall: onCall ?? (_) async {},
        onDeclineCall: onDecline ?? (_) async {},
        callActionBusy: busy,
        callError: error,
        child: child!,
      ),
    ),
  ),
  home:
      home ?? const Scaffold(body: Center(child: Text('Another KORLIX tool'))),
);

double shakeOffset(WidgetTester tester) => tester
    .widget<Transform>(find.byKey(const ValueKey('social-alert-screen-motion')))
    .transform
    .storage[12];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'))).load();
    final root = Platform.environment['KORLIX_FLUTTER_ROOT'];
    if (root != null) {
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  late AlertFixture alerts;
  setUp(() => alerts = AlertFixture(ValueNotifier(0)));
  tearDown(() => alerts.dispose());

  testWidgets('private and group alerts reveal names, never message contents', (
    tester,
  ) async {
    await tester.pumpWidget(app(alerts));
    alerts.showMessage();
    await tester.pumpAndSettle();
    expect(find.text('Incoming message'), findsOneWidget);
    expect(find.text('Maria Green'), findsOneWidget);
    expect(find.text('You have a new private message.'), findsOneWidget);
    expect(find.textContaining('Private message contents'), findsNothing);
    alerts.showMessage(group: true, name: 'Family chat');
    await tester.pumpAndSettle();
    expect(find.text('Family chat'), findsOneWidget);
    expect(find.text('New message in your group.'), findsOneWidget);
    expect(find.text('Maria Green'), findsNothing);
  });

  testWidgets('alert remains actionable above navigator routes and dialogs', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    var opened = 0;
    await tester.pumpWidget(
      app(
        alerts,
        navigatorKey: navigator,
        onMessage: (_) async {
          opened++;
          alerts.dismissMessage();
        },
      ),
    );
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Logo Studio route')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(
      showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Tool dialog')),
      ),
    );
    await tester.pumpAndSettle();
    alerts.showMessage();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open message'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('Tool dialog'), findsOneWidget);
    expect(find.text('Incoming message'), findsNothing);
  });

  testWidgets('outside the card stays interactive with no modal barrier', (
    tester,
  ) async {
    var tapped = 0;
    await tester.pumpWidget(
      app(
        alerts,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: TextButton(
              onPressed: () => tapped++,
              child: const Text('Continue working'),
            ),
          ),
        ),
      ),
    );
    final existingBarriers = find.byType(ModalBarrier).evaluate().length;
    alerts.showMessage();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue working'));
    expect(tapped, 1);
    expect(find.byType(ModalBarrier), findsNWidgets(existingBarriers));
    expect(find.text('Incoming message'), findsOneWidget);
  });

  testWidgets('calls take priority and wait for explicit view or decline', (
    tester,
  ) async {
    SocialMap? viewed, declined;
    await tester.pumpWidget(
      app(
        alerts,
        onCall: (call) async => viewed = call,
        onDecline: (call) async => declined = call,
      ),
    );
    alerts.showMessage();
    alerts.showCall();
    await tester.pumpAndSettle();
    expect(find.text('Incoming phone call'), findsOneWidget);
    expect(find.text('Incoming message'), findsNothing);
    expect(viewed, isNull);
    expect(declined, isNull);
    await tester.pump(const Duration(seconds: 15));
    expect(find.text('Incoming phone call'), findsOneWidget);
    await tester.tap(find.text('View call'));
    await tester.pump();
    expect(viewed?['id'], 'call-one');
    expect(declined, isNull);
    await tester.tap(find.text('Decline'));
    await tester.pump();
    expect(declined?['id'], 'call-one');
    alerts.clearCall();
    await tester.pumpAndSettle();
    expect(find.text('Incoming message'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('Incoming message'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Incoming message'), findsNothing);
  });

  testWidgets(
    'busy video call disables actions and shows a recoverable error',
    (tester) async {
      var actions = 0;
      alerts.showCall(video: true);
      await tester.pumpWidget(
        app(
          alerts,
          busy: true,
          error: 'Connection unavailable. Try again.',
          onCall: (_) async => actions++,
          onDecline: (_) async => actions++,
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Incoming video call'), findsOneWidget);
      expect(find.text('Connection unavailable. Try again.'), findsOneWidget);
      for (final button in tester.widgetList<FilledButton>(
        find.byType(FilledButton),
      )) {
        expect(button.onPressed, isNull);
      }
      await tester.tap(find.text('View call'));
      expect(actions, 0);
      await tester.pumpWidget(app(alerts));
      await tester.pumpAndSettle();
      expect(find.text('Connection unavailable. Try again.'), findsNothing);
      expect(
        tester
            .widgetList<FilledButton>(find.byType(FilledButton))
            .first
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('dismiss removes message without opening or marking chat read', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(app(alerts, onMessage: (_) async => opened++));
    alerts.showMessage();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(alerts.dismissals, 1);
    expect(opened, 0);
    expect(find.byKey(const ValueKey('social-alert-card')), findsNothing);
  });

  testWidgets('new messages get a fresh ten-second window; polls do not', (
    tester,
  ) async {
    await tester.pumpWidget(app(alerts));
    alerts.showMessage();
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));
    alerts.showMessage(name: 'New sender');
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));
    alerts.notifyListeners();
    await tester.pump();
    expect(find.text('New sender'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('social-alert-card')), findsNothing);
    expect(alerts.dismissals, 1);
  });

  testWidgets('screen gives one bounded shake for each new visible revision', (
    tester,
  ) async {
    await tester.pumpWidget(app(alerts));
    alerts.showMessage();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(shakeOffset(tester).abs(), greaterThan(0));
    expect(shakeOffset(tester).abs(), lessThanOrEqualTo(5));
    await tester.pump(const Duration(milliseconds: 600));
    expect(shakeOffset(tester), 0);
    alerts.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(shakeOffset(tester), 0);
    alerts.showCall();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(shakeOffset(tester).abs(), greaterThan(0));
    await tester.pump(const Duration(milliseconds: 600));
    alerts.showMessage(name: 'Queued message');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(shakeOffset(tester), 0);
  });

  for (final accessible in [false, true]) {
    testWidgets(
      '${accessible ? 'accessible navigation' : 'reduced motion'} keeps screen still',
      (tester) async {
        await tester.pumpWidget(
          app(
            alerts,
            reduceMotion: !accessible,
            accessibleNavigation: accessible,
          ),
        );
        alerts.showMessage();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(shakeOffset(tester), 0);
        alerts.showCall();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(shakeOffset(tester), 0);
        expect(find.text('Incoming phone call'), findsOneWidget);
      },
    );
  }

  testWidgets('320px screens and large text scroll without hiding actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    alerts.showMessage(
      group: true,
      name: 'A very long family group name that should wrap gracefully',
    );
    await tester.pumpWidget(app(alerts, textScale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture(tester, 'social-alert-320-large-text');
    await tester.scrollUntilVisible(
      find.text('Dismiss'),
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('social-alert-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'social-alert-320-large-text-actions');
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(alerts.dismissals, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only the alert is a live region and clearing removes it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(app(alerts));
    alerts.showMessage();
    await tester.pumpAndSettle();
    final node = tester.getSemantics(
      find.byKey(const ValueKey('social-alert-live-region')),
    );
    expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    final overlay = tester.widget<SocialAlertOverlay>(
      find.byType(SocialAlertOverlay),
    );
    expect(overlay.child, isNot(isA<Semantics>()));
    alerts.clearAll();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('social-alert-live-region')),
      findsNothing,
    );
    expect(find.text('Another KORLIX tool'), findsOneWidget);
    handle.dispose();
  });

  testWidgets(
    'pending callbacks cannot restore errors after account clearing',
    (tester) async {
      final pending = Completer<void>();
      var opens = 0;
      await tester.pumpWidget(
        app(
          alerts,
          onMessage: (_) {
            opens++;
            return pending.future;
          },
        ),
      );
      alerts.showMessage();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open message'));
      await tester.pump();
      await tester.tap(find.text('Open message'));
      expect(opens, 1);
      alerts.clearAll();
      await tester.pump();
      pending.completeError(StateError('old account'));
      await tester.pump();
      expect(find.byKey(const ValueKey('social-alert-card')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('active calls hide and pause queued alerts until the call ends', (
    tester,
  ) async {
    await tester.pumpWidget(app(alerts));
    alerts.activeCall = true;
    alerts.showMessage();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(shakeOffset(tester), 0);
    expect(find.byKey(const ValueKey('social-alert-card')), findsNothing);
    await tester.pump(const Duration(seconds: 15));
    expect(alerts.messageAlert, isNotNull);
    expect(alerts.dismissals, 0);
    alerts.activeCall = false;
    alerts.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(shakeOffset(tester).abs(), greaterThan(0));
    expect(find.text('Incoming message'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('Incoming message'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Incoming message'), findsNothing);
  });

  testWidgets('accessible navigation waits for explicit message dismissal', (
    tester,
  ) async {
    await tester.pumpWidget(app(alerts, accessibleNavigation: true));
    alerts.showMessage();
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Incoming message'), findsOneWidget);
    expect(alerts.dismissals, 0);
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    expect(find.text('Incoming message'), findsNothing);
  });

  testWidgets('320px message and call cards remain within the viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(alerts));
    alerts.showMessage();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture(tester, 'social-alert-320-message');
    alerts.showCall();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byKey(const ValueKey('social-alert-card'))).right,
      lessThanOrEqualTo(320),
    );
    await capture(tester, 'social-alert-320-call');
  });
}
