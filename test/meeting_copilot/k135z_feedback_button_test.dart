import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../lib/meeting_copilot/k135z_feedback_button.dart';

void main() {
  testWidgets('tap illuminates while pending, prevents duplicates, and does not imply success', (tester) async {
    final request = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      K135zFeedbackButton.elevated(buttonKey: const Key('start'),
        onPressed: () { calls++; return request.future; },
        pendingLabel: 'Starting…', child: const Text('Start Listening')))));
    await tester.tap(find.byKey(const Key('start')));
    await tester.pump();
    expect(find.text('Starting…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.byKey(const Key('start'))).style!.side!.resolve({})!.color,
      const Color(0xFFFFCC66));
    await tester.tap(find.byKey(const Key('start')));
    expect(calls, 1);
    request.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.text('Start Listening'), findsOneWidget);
  });

  testWidgets('confirmed selection stays illuminated even when action is disabled', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      K135zFeedbackButton.elevated(buttonKey: Key('listening'), onPressed: null,
        selected: true, activeColor: Color(0xFF63E6A1), child: Text('Listening')))));
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byKey(const Key('listening')));
    expect(button.onPressed, isNull);
    expect(button.style!.side!.resolve({})!.color, const Color(0xFF63E6A1));
  });

  testWidgets('disabled control cannot dispatch or show pending feedback', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      K135zFeedbackButton.outlined(buttonKey: Key('disabled'), onPressed: null, child: Text('Pause')))));
    await tester.tap(find.byKey(const Key('disabled')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });
}
