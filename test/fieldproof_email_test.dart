import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/fieldproof/fieldproof_client.dart';
import 'package:ai_wiz_command_center/fieldproof/fieldproof_email.dart';
import 'package:ai_wiz_command_center/fieldproof/fieldproof_email_screen.dart';

Map<String, dynamic> _capabilities() => {
  'ready': true,
  'sender_label': 'KORLIX FieldProof',
  'reply_to': 'owner@example.test',
  'daily_limit_max': 100,
};
Map<String, dynamic> _state([Map<String, dynamic>? settings]) => {
  'settings': settings ?? fieldProofEmailDefaults(),
  'capabilities': _capabilities(),
  'deliveries': <Map<String, dynamic>>[],
};
Map<String, dynamic> _delivery({
  String state = 'draft',
  bool approve = true,
  bool retry = false,
}) => {
  'id': 'mail-1',
  'version': 1,
  'kind': 'customer_report',
  'recipient': 'client@example.test',
  'subject': 'Completed work report',
  'state': state,
  'can_approve': approve,
  'can_retry': retry,
  'can_cancel': state == 'draft',
  'has_report': false,
  'text':
      'The recorded work is complete.\nPlease review the attached job record.',
};

class _FakeEmailClient extends FieldProofEmailClient {
  _FakeEmailClient()
    : super(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {},
        client: MockClient((_) async => http.Response('{}', 500)),
      );
  Map<String, dynamic> state = _state();
  Map<String, dynamic> jobState = {
    'job_settings': {'version': 0, 'customer_email': '', 'enabled': false},
    'deliveries': <Map<String, dynamic>>[],
  };
  Map<String, dynamic> email = _delivery();
  bool failSave = false;
  int saves = 0, jobSaves = 0, prepares = 0;
  final actions = <String>[];
  Completer<Map<String, dynamic>>? loadWait;
  final listeners = <VoidCallback>{};
  @override
  void addAccessDeniedListener(VoidCallback listener) =>
      listeners.add(listener);
  @override
  void removeAccessDeniedListener(VoidCallback listener) =>
      listeners.remove(listener);
  void changeAccount() {
    for (final listener in List<VoidCallback>.from(listeners)) {
      listener();
    }
  }

  @override
  Future<Map<String, dynamic>> load() async =>
      loadWait != null ? loadWait!.future : state;
  @override
  Future<Map<String, dynamic>> saveSettings(
    int version,
    Map<String, dynamic> settings,
  ) async {
    saves++;
    if (failSave) throw const FieldProofException('Save unavailable.');
    state = {
      ...state,
      'settings': {...settings, 'version': version + 1},
    };
    return state;
  }

  @override
  Future<Map<String, dynamic>> job(String id) async => jobState;
  @override
  Future<Map<String, dynamic>> saveJob(
    String id,
    int version,
    Map<String, dynamic> settings,
  ) async {
    jobSaves++;
    jobState = {
      ...jobState,
      'job_settings': {...settings, 'version': version + 1},
    };
    return jobState;
  }

  @override
  Future<void> prepare(String jobId, String key) async {
    prepares++;
  }

  @override
  Future<Map<String, dynamic>> delivery(String id) async => email;
  @override
  Future<void> action(String id, String action, int version) async {
    actions.add(action);
    email = {
      ...email,
      'state': 'ready',
      'can_approve': false,
      'can_cancel': true,
    };
  }
}

Future<void> _show(
  WidgetTester t,
  _FakeEmailClient client, {
  double width = 390,
  double scale = 1,
  bool job = false,
  bool completed = false,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: themeMode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: FieldProofEmailScreen(
        client: client,
        jobId: job ? 'job-1' : null,
        jobTitle: job ? 'Water meter replacement' : null,
        jobCompleted: completed,
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _tap(WidgetTester t, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<void> _mode(WidgetTester t, String key, String value) async {
  final dropdown = find.byKey(ValueKey('$key-off'));
  await _tap(t, dropdown);
  await t.tap(find.text(value).last);
  await t.pumpAndSettle();
}

String _jwt(String sub, [String session = 's1']) =>
    'Bearer h.${base64Url.encode(utf8.encode(jsonEncode({'iss': 'test', 'sub': sub, 'session_id': session}))).replaceAll('=', '')}.sig';

void main() {
  test(
    'all modes default off and business addresses are bounded and normalized',
    () {
      final defaults = fieldProofEmailDefaults();
      expect(defaults['customer_mode'], 'off');
      expect(defaults['followup_mode'], 'off');
      expect(defaults['supervisor_mode'], 'off');
      expect(validateFieldProofEmailSettings(defaults), isNull);
      expect(
        fieldProofSupervisorEmails(
          ' A@EXAMPLE.TEST, a@example.test\nb@example.test; ',
        ),
        ['a@example.test', 'b@example.test'],
      );
      expect(
        validateFieldProofEmailSettings({
          ...defaults,
          'supervisor_mode': 'automatic',
        }),
        contains('at least one'),
      );
      expect(
        validateFieldProofEmailSettings({
          ...defaults,
          'supervisor_emails': List.filled(6, 'a@example.test'),
        }),
        contains('five'),
      );
      expect(
        validateFieldProofEmailSettings({...defaults, 'summary_days': []}),
        contains('day'),
      );
      expect(
        validateFieldProofEmailSettings({...defaults, 'summary_time': '25:00'}),
        contains('24-hour'),
      );
      expect(
        validateFieldProofEmailSettings({...defaults, 'daily_limit': 101}),
        contains('1–100'),
      );
      expect(
        validateFieldProofEmailSettings({...defaults, 'followup_days': 0}),
        contains('1–30'),
      );
      expect(
        validateFieldProofEmailSettings({
          ...defaults,
          'timezone': 'America/Jamaica',
        }),
        isNull,
      );
    },
  );
  test(
    'client authenticates, pins version, and accepts only confirmed state shape',
    () async {
      final requests = <http.Request>[];
      final client = FieldProofEmailClient(
        backendBaseUrl: 'https://example.test/',
        headersBuilder: () => {'Authorization': _jwt('owner')},
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(
            jsonEncode(_state({...fieldProofEmailDefaults(), 'version': 4})),
            200,
          );
        }),
      );
      await client.saveSettings(3, fieldProofEmailDefaults());
      expect(requests.single.url.path, '/api/fieldproof/email/settings');
      expect(requests.single.headers['Authorization'], _jwt('owner'));
      final body = jsonDecode(requests.single.body);
      expect(body['version'], 3);
      expect(body['confirmed'], true);
      client.dispose();
      final invalid = FieldProofEmailClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {},
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await expectLater(invalid.load(), throwsA(isA<FieldProofException>()));
      invalid.dispose();
    },
  );
  test('in-flight response is discarded after account switch', () async {
    final wait = Completer<http.Response>();
    var bearer = _jwt('one');
    final changes = ValueNotifier(0);
    var denied = 0;
    final client = FieldProofEmailClient(
      backendBaseUrl: 'https://example.test',
      headersBuilder: () => {'Authorization': bearer},
      sessionChanges: changes,
      client: MockClient((_) => wait.future),
    );
    client.addAccessDeniedListener(() => denied++);
    final response = client.load();
    final assertion = expectLater(
      response,
      throwsA(isA<FieldProofException>()),
    );
    bearer = _jwt('two');
    changes.value++;
    wait.complete(http.Response(jsonEncode(_state()), 200));
    await assertion;
    expect(denied, 1);
    expect(client.sessionChanged, true);
    client.dispose();
    changes.dispose();
  });
  test('token refresh in the same account session remains allowed', () async {
    var bearer = _jwt('one');
    final changes = ValueNotifier(0);
    final client = FieldProofEmailClient(
      backendBaseUrl: 'https://example.test',
      headersBuilder: () => {'Authorization': bearer},
      sessionChanges: changes,
      client: MockClient((_) async => http.Response(jsonEncode(_state()), 200)),
    );
    bearer = '${_jwt('one')}new-signature';
    changes.value++;
    expect((await client.load())['settings'], isNotEmpty);
    client.dispose();
    changes.dispose();
  });
  test(
    'private report checks PDF bytes and never treats HTML as a PDF',
    () async {
      final client = FieldProofEmailClient(
        backendBaseUrl: 'https://example.test',
        headersBuilder: () => {},
        client: MockClient(
          (_) async => http.Response('<html>blocked</html>', 200),
        ),
      );
      await expectLater(
        client.report('mail-1'),
        throwsA(isA<FieldProofException>()),
      );
      client.dispose();
    },
  );
  test('unchanged save revision never claims a successful save', () async {
    final client = FieldProofEmailClient(
      backendBaseUrl: 'https://example.test',
      headersBuilder: () => {},
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(_state({...fieldProofEmailDefaults(), 'version': 3})),
          200,
        ),
      ),
    );
    await expectLater(
      client.saveSettings(3, fieldProofEmailDefaults()),
      throwsA(isA<FieldProofException>()),
    );
    client.dispose();
  });
  testWidgets(
    'queue limits and delivery readiness display actionable notices',
    (t) async {
      final client = _FakeEmailClient()
        ..state = {
          ..._state(),
          'queue_notice':
              'Some new reports were not queued. Review recent jobs.',
          'capabilities': {
            ..._capabilities(),
            'ready': false,
            'reason': 'Verify your email before sending.',
          },
        };
      await _show(t, client);
      expect(
        find.text('Some new reports were not queued. Review recent jobs.'),
        findsOneWidget,
      );
      expect(find.text('Verify your email before sending.'), findsOneWidget);
    },
  );
  testWidgets(
    'draft mode saves without automatic confirmation and preserves chosen settings',
    (t) async {
      final client = _FakeEmailClient();
      await _show(t, client);
      await _mode(t, 'customer_mode', 'Review drafts');
      await _tap(t, find.byKey(const Key('fp-email-save')));
      expect(client.saves, 1);
      expect(client.state['settings']['customer_mode'], 'draft');
      expect(find.text('Confirm automatic email'), findsNothing);
    },
  );
  testWidgets(
    'automatic mode requires concrete confirmation and cancellation performs no save',
    (t) async {
      final client = _FakeEmailClient();
      await _show(t, client);
      await _mode(t, 'customer_mode', 'Automatic');
      await _tap(t, find.byKey(const Key('fp-email-save')));
      expect(client.saves, 0);
      expect(find.text('Confirm automatic email'), findsOneWidget);
      expect(find.textContaining('Daily limit: 25 emails'), findsOneWidget);
      await _tap(t, find.text('Go back'));
      expect(client.saves, 0);
      await _tap(t, find.byKey(const Key('fp-email-save')));
      await _tap(t, find.text('Save and activate'));
      expect(client.saves, 1);
      expect(client.state['settings']['customer_mode'], 'automatic');
    },
  );
  testWidgets(
    'ordinary saves do not reconfirm an already active automatic mode',
    (t) async {
      final client = _FakeEmailClient()
        ..state = _state({
          ...fieldProofEmailDefaults(),
          'customer_mode': 'automatic',
        });
      await _show(t, client);
      await t.enterText(
        find.byKey(const Key('fp-email-business')),
        'Updated business name',
      );
      await _tap(t, find.byKey(const Key('fp-email-save')));
      expect(client.saves, 1);
      expect(find.text('Confirm automatic email'), findsNothing);
    },
  );
  testWidgets(
    'adding automatic supervisor recipients requires the updated address confirmation',
    (t) async {
      final client = _FakeEmailClient()
        ..state = _state({
          ...fieldProofEmailDefaults(),
          'supervisor_mode': 'automatic',
          'supervisor_emails': ['first@example.test'],
        });
      await _show(t, client);
      await t.ensureVisible(find.byKey(const Key('fp-email-supervisors')));
      await t.enterText(
        find.byKey(const Key('fp-email-supervisors')),
        'first@example.test, second@example.test',
      );
      await _tap(t, find.byKey(const Key('fp-email-save')));
      expect(client.saves, 0);
      expect(
        find.textContaining(
          'Supervisors: first@example.test, second@example.test',
        ),
        findsOneWidget,
      );
      await _tap(t, find.text('Go back'));
    },
  );
  testWidgets('invalid supervisor configuration cannot be saved', (t) async {
    final client = _FakeEmailClient();
    await _show(t, client);
    await _mode(t, 'supervisor_mode', 'Review drafts');
    await _tap(t, find.byKey(const Key('fp-email-save')));
    expect(client.saves, 0);
    expect(
      find.text('Add at least one supervisor email address.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'failed saves retain entered values and require refresh before another mutation',
    (t) async {
      final client = _FakeEmailClient()..failSave = true;
      await _show(t, client);
      await t.enterText(
        find.byKey(const Key('fp-email-business')),
        'My service company',
      );
      await _tap(t, find.byKey(const Key('fp-email-save')));
      expect(find.text('My service company'), findsOneWidget);
      expect(find.text('Save unavailable.'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('fp-email-save')))
            .onPressed,
        isNull,
      );
      expect(client.saves, 1);
      await _tap(t, find.byKey(const Key('fp-email-reload')));
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('fp-email-save')))
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'account change clears private recipients and disables the screen',
    (t) async {
      final client = _FakeEmailClient()
        ..state = _state({
          ...fieldProofEmailDefaults(),
          'supervisor_emails': ['private@example.test'],
        });
      await _show(t, client);
      expect(find.text('private@example.test'), findsOneWidget);
      client.changeAccount();
      await t.pumpAndSettle();
      expect(find.text('private@example.test'), findsNothing);
      expect(find.byKey(const Key('fp-email-save')), findsNothing);
      expect(
        find.textContaining('Your account session changed'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'job recipient requires valid address and saved enabled scope before draft preparation',
    (t) async {
      final client = _FakeEmailClient()
        ..state = _state({
          ...fieldProofEmailDefaults(),
          'customer_mode': 'draft',
        });
      await _show(t, client, job: true, completed: true);
      await _tap(t, find.byKey(const Key('fp-email-job-enabled')));
      await _tap(t, find.byKey(const Key('fp-email-save-job')));
      expect(client.jobSaves, 0);
      expect(
        find.textContaining('Enter a valid customer email'),
        findsOneWidget,
      );
      await t.enterText(
        find.byKey(const Key('fp-email-customer')),
        'client@example.test',
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('fp-email-prepare')))
            .onPressed,
        isNull,
      );
      await _tap(t, find.byKey(const Key('fp-email-save-job')));
      expect(client.jobSaves, 1);
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('fp-email-prepare')))
            .onPressed,
        isNotNull,
      );
      await t.enterText(
        find.byKey(const Key('fp-email-customer')),
        'other@example.test',
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('fp-email-prepare')))
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'activity gives truthful acceptance and does not invent approval or retry actions',
    (t) async {
      final delivery = _delivery(state: 'accepted', approve: false);
      final client = _FakeEmailClient()
        ..email = delivery
        ..state = {
          ..._state(),
          'deliveries': [delivery],
        };
      await _show(t, client);
      await _tap(t, find.byKey(const Key('fp-email-activity')));
      expect(find.text('Accepted by email provider'), findsOneWidget);
      await _tap(t, find.text('View email'));
      expect(find.text('Approve & queue email'), findsNothing);
      expect(find.text('Retry same email'), findsNothing);
      expect(
        find.text('Provider acceptance does not confirm inbox delivery.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'draft approval displays recipient and queues only after explicit confirmation',
    (t) async {
      final client = _FakeEmailClient()
        ..state = {
          ..._state(),
          'deliveries': [_delivery()],
        };
      await _show(t, client);
      await _tap(t, find.byKey(const Key('fp-email-activity')));
      await _tap(t, find.text('View email'));
      await _tap(t, find.byKey(const Key('fp-email-approve')));
      expect(client.actions, isEmpty);
      expect(find.textContaining('To: client@example.test'), findsNWidgets(2));
      await _tap(t, find.text('Approve email'));
      expect(client.actions, ['approve']);
      expect(find.text('Queued to send'), findsOneWidget);
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      '320px setup and job layout remain scrollable at 200 percent text ${dark ? 'dark' : 'light'}',
      (t) async {
        final client = _FakeEmailClient();
        await _show(
          t,
          client,
          width: 320,
          scale: 2,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        );
        await t.ensureVisible(find.byKey(const Key('fp-email-save')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await _show(
          t,
          client,
          width: 320,
          scale: 2,
          job: true,
          completed: true,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        );
        await t.ensureVisible(find.byKey(const Key('fp-email-prepare')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
    );
  }
}
