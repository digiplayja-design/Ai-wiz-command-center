import 'dart:async';

import 'package:ai_wiz_command_center/reviews/korlix_review_invitation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixture {
  final revision = ValueNotifier(0);
  final navigator = GlobalKey<NavigatorState>();
  final observer = KorlixReviewRouteObserver();
  int storeCalls = 0;
  bool storeAvailable = true;
  Object? storeError;
  Completer<bool>? storeResponse;
  bool? choice;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  settings: const RouteSettings(name: '/feature'),
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () async {
                        choice = await showDialog<bool>(
                          context: context,
                          builder: (_) => KorlixReviewInvitation(
                            sessionChanges: revision,
                            openStore: () async {
                              storeCalls++;
                              if (storeError != null) throw storeError!;
                              return storeResponse?.future ??
                                  Future.value(storeAvailable);
                            },
                          ),
                        );
                      },
                      child: const Text('Open invitation'),
                    ),
                  ),
                ),
              ),
              child: const Text('Open feature'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open feature'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open invitation'));
    await tester.pumpAndSettle();
  }
}

void main() {
  late _Fixture fixture;
  setUp(() => fixture = _Fixture());

  testWidgets('both choices are available without asking for sentiment', (
    tester,
  ) async {
    await fixture.open(tester);
    expect(find.text('Send private feedback'), findsOneWidget);
    expect(find.text('Review on Google Play'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(find.textContaining('honest review'), findsOneWidget);
    expect(find.text('I love this'), findsNothing);
    expect(find.text('I hate this'), findsNothing);
    expect(find.byIcon(Icons.star), findsNothing);
    expect(fixture.storeCalls, 0);
    await tester.pump(const Duration(minutes: 3));
    expect(fixture.storeCalls, 0);
  });

  testWidgets(
    'private feedback is an explicit choice and never opens the store',
    (tester) async {
      await fixture.open(tester);
      await tester.tap(find.byKey(const Key('korlix-review-private-feedback')));
      await tester.pumpAndSettle();
      expect(fixture.choice, isTrue);
      expect(fixture.storeCalls, 0);
      expect(find.text('Open invitation'), findsOneWidget);
    },
  );

  testWidgets('public review opens only after the member requests it', (
    tester,
  ) async {
    await fixture.open(tester);
    await tester.tap(find.byKey(const Key('korlix-review-google-play')));
    await tester.pumpAndSettle();
    expect(fixture.storeCalls, 1);
    expect(fixture.choice, isFalse);
    expect(find.text('Open invitation'), findsOneWidget);
  });

  for (final throwsError in [false, true]) {
    testWidgets(
      'store failure ($throwsError) preserves both choices without redirect',
      (tester) async {
        fixture.storeAvailable = false;
        if (throwsError) fixture.storeError = StateError('Store unavailable');
        await fixture.open(tester);
        await tester.tap(find.byKey(const Key('korlix-review-google-play')));
        await tester.pumpAndSettle();
        expect(
          find.text('Google Play could not open. You can try again later.'),
          findsOneWidget,
        );
        expect(find.text('Send private feedback'), findsOneWidget);
        expect(find.text('Review on Google Play'), findsOneWidget);
        expect(fixture.choice, isNull);
        expect(fixture.storeCalls, 1);
        await tester.pump(const Duration(seconds: 30));
        expect(fixture.storeCalls, 1);
      },
    );
  }

  testWidgets('repeat store activation sends one request', (tester) async {
    fixture.storeResponse = Completer<bool>();
    await fixture.open(tester);
    final callback = tester
        .widget<OutlinedButton>(
          find.byKey(const Key('korlix-review-google-play')),
        )
        .onPressed!;
    callback();
    callback();
    await tester.pump();
    expect(fixture.storeCalls, 1);
    fixture.storeResponse!.complete(true);
    await tester.pumpAndSettle();
    expect(fixture.choice, isFalse);
  });

  testWidgets(
    'late store response after Not now never pops the underlying page',
    (tester) async {
      fixture.storeResponse = Completer<bool>();
      await fixture.open(tester);
      await tester.tap(find.byKey(const Key('korlix-review-google-play')));
      await tester.pump();
      await tester.tap(find.text('Not now'));
      // Complete while the dismissed dialog is still mounted for its animation.
      fixture.storeResponse!.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Open invitation'), findsOneWidget);
      expect(find.text('Open feature'), findsNothing);
      expect(fixture.choice, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account change during store request removes only the invitation',
    (tester) async {
      fixture.storeResponse = Completer<bool>();
      await fixture.open(tester);
      await tester.tap(find.byKey(const Key('korlix-review-google-play')));
      await tester.pump();
      fixture.revision.value++;
      fixture.storeResponse!.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Open invitation'), findsOneWidget);
      expect(find.text('Send private feedback'), findsNothing);
      expect(fixture.choice, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account change during close animation cannot remove a completed route',
    (tester) async {
      await fixture.open(tester);
      await tester.tap(find.text('Not now'));
      fixture.revision.value++;
      await tester.pumpAndSettle();
      expect(find.text('Open invitation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account change before the first dialog frame cancels invitation',
    (tester) async {
      final revision = ValueNotifier(0);
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  unawaited(
                    showKorlixReviewInvitation(
                      context,
                      baseUrl: 'https://unused.example.test',
                      headersBuilder: () => {},
                      sessionChanges: revision,
                    ),
                  );
                  revision.value++;
                },
                child: const Text('Open then switch account'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open then switch account'));
      await tester.pumpAndSettle();
      expect(find.text('Send private feedback'), findsNothing);
      expect(find.text('Review on Google Play'), findsNothing);
      expect(find.byType(KorlixReviewInvitation), findsNothing);
      expect(key.currentState!.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('home boundary excludes feature pages and modal routes', (
    tester,
  ) async {
    final key = GlobalKey<NavigatorState>();
    final observer = KorlixReviewRouteObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [observer],
        home: const Scaffold(body: Text('Home')),
      ),
    );
    await tester.pumpAndSettle();
    expect(observer.atHome, isTrue);
    key.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Feature')),
      ),
    );
    await tester.pumpAndSettle();
    expect(observer.atHome, isFalse);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(observer.atHome, isTrue);
    final context = key.currentState!.overlay!.context;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Another dialog')),
      ),
    );
    await tester.pumpAndSettle();
    expect(observer.atHome, isFalse);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(observer.atHome, isTrue);
  });
}
