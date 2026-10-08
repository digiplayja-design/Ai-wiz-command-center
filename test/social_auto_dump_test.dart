import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/social/social_auto_dump.dart';
import 'package:ai_wiz_command_center/social/social_client.dart';
import 'package:ai_wiz_command_center/social/social_dump_truck.dart';
import 'package:ai_wiz_command_center/social/social_threads.dart';

import 'social_replies_test.dart' as replies;
import 'social_test.dart' as fixtures;

class DumpStore {
  DumpStore(this.now);
  final DateTime Function() now;
  final revision = ValueNotifier(0);
  String token = 'Bearer dump-account';
  final calls = <SocialMap>[];
  final due = <String, DateTime>{};
  final everyoneDue = <String, DateTime>{};
  DateTime? effectiveDue(String id) {
    final self = due[id], everyone = everyoneDue[id];
    if (self == null) return everyone;
    if (everyone == null) return self;
    return self.isBefore(everyone) ? self : everyone;
  }

  final rows = <SocialMap>[
    replies.message('first', 1, 'Private meeting address'),
    {
      ...replies.message('second', 2, 'I will be there', sender: 'me'),
      'reply_to': 'first',
    },
  ];
  bool fail = false;
  bool failHistory = false, omitFirst = false, omitSecond = false;
  Completer<void>? saveGate;
  DateTime get serverNow => now().add(const Duration(days: 8));
  List<String> get hidden => [
    for (final id in {...due.keys, ...everyoneDue.keys})
      if (!effectiveDue(id)!.isAfter(serverNow)) id,
  ];
  SocialMap card(SocialMap row) {
    final parent = row['reply_to'] == null
        ? null
        : rows.firstWhere((item) => item['id'] == row['reply_to']);
    return {
      ...row,
      'dump_at': effectiveDue('${row['id']}')?.toIso8601String(),
      'self_dump_at': due[row['id']]?.toIso8601String(),
      'everyone_dump_at': everyoneDue[row['id']]?.toIso8601String(),
      if (parent != null)
        'reply': hidden.contains(parent['id'])
            ? {
                ...parent,
                'body': '',
                'deleted': true,
                'dump_at': effectiveDue('${parent['id']}')?.toIso8601String(),
                'self_dump_at': due[parent['id']]?.toIso8601String(),
                'everyone_dump_at': everyoneDue[parent['id']]
                    ?.toIso8601String(),
              }
            : {
                ...parent,
                'dump_at': effectiveDue('${parent['id']}')?.toIso8601String(),
                'self_dump_at': due[parent['id']]?.toIso8601String(),
                'everyone_dump_at': everyoneDue[parent['id']]
                    ?.toIso8601String(),
              },
    };
  }

  late final client = SocialClient(
    baseUrl: 'https://fixture.test',
    headersBuilder: () => {'Authorization': token},
    sessionChanges: revision,
    client: MockClient((request) async {
      final action = request.url.pathSegments.last;
      final data = request.method == 'POST'
          ? socialMap(jsonDecode(request.body))
          : <String, dynamic>{...request.url.queryParameters};
      calls.add({'action': action, ...data});
      SocialMap result = {};
      var status = 200;
      if (action == 'messages' || action == 'group_messages') {
        result = {
          'items': [
            for (final row in rows)
              if (!hidden.contains(row['id']) &&
                  !(omitFirst && row['id'] == 'first') &&
                  !(omitSecond && row['id'] == 'second'))
                card(row),
          ],
          'peer': fixtures.peer,
          'dumped_ids': hidden,
          'dump_schedules': {
            for (final id in {...due.keys, ...everyoneDue.keys})
              if (!hidden.contains(id)) id: effectiveDue(id)!.toIso8601String(),
          },
          'dump_self_schedules': {
            for (final entry in due.entries)
              if (!hidden.contains(entry.key))
                entry.key: entry.value.toIso8601String(),
          },
          'dump_everyone_schedules': {
            for (final entry in everyoneDue.entries)
              if (!hidden.contains(entry.key))
                entry.key: entry.value.toIso8601String(),
          },
          'server_time': serverNow.toIso8601String(),
        };
        if (failHistory) {
          status = 503;
          result = {'error': 'History is temporarily offline.'};
        }
      } else if (action == 'message' || action == 'group_message') {
        result = {
          'message': card(rows.firstWhere((row) => row['id'] == data['id'])),
          'server_time': serverNow.toIso8601String(),
        };
      } else if (action == 'dump_schedule' || action == 'dump_cancel') {
        await saveGate?.future;
        if (fail) {
          status = 503;
          result = {'error': 'Timer connection interrupted. Please retry.'};
        } else {
          final id = '${data['id']}';
          final schedules = data['dump_scope'] == 'everyone'
              ? everyoneDue
              : due;
          if (!hidden.contains(id)) {
            if (action == 'dump_schedule') {
              schedules[id] = serverNow.add(
                Duration(seconds: data['seconds'] as int),
              );
            } else {
              schedules.remove(id);
            }
          }
          result = {
            'id': id,
            'dump_at': effectiveDue(id)?.toIso8601String(),
            'self_dump_at': due[id]?.toIso8601String(),
            'everyone_dump_at': everyoneDue[id]?.toIso8601String(),
            'server_time': serverNow.toIso8601String(),
            'dumped': hidden.contains(id),
          };
        }
      }
      return http.Response(
        jsonEncode(result),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );

  void switchAccount() {
    token = 'Bearer replacement-account';
    revision.value++;
  }
}

Future<void> mount(
  WidgetTester t,
  DumpStore store, {
  bool group = false,
  double width = 390,
  double scale = 1,
}) async {
  await fixtures.mount(
    t,
    SocialChatScreen(
      client: store.client,
      me: fixtures.me,
      peer: fixtures.peer,
      groupChat: group,
      autoDumpNow: t.binding.clock.now,
    ),
    width: width,
    scale: scale,
  );
}

Future<void> choose(WidgetTester t, String id) async {
  if (find.byKey(ValueKey('dump-message-$id')).evaluate().isEmpty) {
    await replies.tap(t, find.byKey(const ValueKey('auto-dump-mode')));
  }
  await replies.tap(t, find.byKey(ValueKey('dump-message-$id')));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final delay in socialAutoDumpDelays.entries) {
    test('server clock expires ${delay.value} despite device clock skew', () {
      var local = DateTime.utc(2001);
      final server = DateTime.utc(2026, 10, 3, 18);
      final model = SocialAutoDump(now: () => local);
      model.confirm('one', {
        'dump_at': server.add(Duration(seconds: delay.key)).toIso8601String(),
        'server_time': server.toIso8601String(),
        'dumped': false,
      });
      expect(model.remaining('one'), Duration(seconds: delay.key));
      expect(model.hidden('one'), false);
      local = local.add(Duration(seconds: delay.key));
      model.observe({}, []);
      expect(model.hidden('one'), true);
      model.dispose();
    });
  }

  test('cancelling an expired server timer never resurrects history', () {
    final model = SocialAutoDump();
    model.confirm('one', {
      'dump_at': null,
      'dumped': true,
      'server_time': '2026-10-03T18:00:00Z',
    });
    model.confirm('one', {
      'dump_at': null,
      'dumped': false,
      'server_time': '2026-10-03T18:00:01Z',
    });
    expect(model.hidden('one'), true);
    model.clear();
    expect(model.hidden('one'), false);
    model.dispose();
  });

  test('new authoritative snapshot restores local expiry after another device cancels', () {
    var local = DateTime.utc(2026, 10, 3, 18);
    final model = SocialAutoDump(now: () => local);
    model.confirm('old', {
      'dump_at': local.add(const Duration(seconds: 15)).toIso8601String(),
      'server_time': local.toIso8601String(),
      'dumped': false,
    });
    local = local.add(const Duration(seconds: 16));
    model.observe({}, []);
    expect(model.hidden('old'), true);
    model.observe({
      'server_time': local.toIso8601String(),
      'dump_schedules': <String, String>{},
      'dumped_ids': <String>[],
    }, []);
    expect(model.hidden('old'), false);
    // A delayed pre-cancellation original-message response is ignored.
    model.observe(
      {
        'server_time': local
            .subtract(const Duration(seconds: 10))
            .toIso8601String(),
      },
      [
        {'id': 'old', 'dump_at': local.toIso8601String()},
      ],
    );
    expect(model.deadlines.containsKey('old'), false);
    model.dispose();
  });

  test('late confirmed cancellation clears local expiry immediately', () {
    var local = DateTime.utc(2026, 10, 3, 18);
    final model = SocialAutoDump(now: () => local);
    model.confirm('one', {
      'dump_at': local.add(const Duration(seconds: 15)).toIso8601String(),
      'server_time': local.toIso8601String(),
      'dumped': false,
    });
    local = local.add(const Duration(seconds: 16));
    model.observe({}, []);
    expect(model.hidden('one'), true);
    model.confirm('one', {
      'dump_at': null,
      'server_time': local.toIso8601String(),
      'dumped': false,
    });
    expect(model.hidden('one'), false);
    expect(model.deadlines.containsKey('one'), false);
    model.dispose();
  });

  testWidgets(
    'select received message, schedule, expire and keep draft plus other message',
    (t) async {
      final store = DumpStore(t.binding.clock.now);
      await mount(t, store);
      await t.enterText(find.byType(TextField), 'Keep this unsent draft');
      await choose(t, 'first');
      expect(
        find.text(
          'Remove from your history on all your devices. Other participants keep their copies.',
        ),
        findsOneWidget,
      );
      for (final seconds in socialAutoDumpDelays.keys) {
        expect(find.byKey(ValueKey('dump-delay-$seconds')), findsOneWidget);
      }
      await replies.tap(t, find.byKey(const ValueKey('dump-confirm')));
      final request = store.calls.lastWhere(
        (call) => call['action'] == 'dump_schedule',
      );
      expect(request['id'], 'first');
      expect(request['dump_scope'], 'self');
      expect(find.byKey(const ValueKey('dump-scope-everyone')), findsNothing);
      expect(request['peer'], fixtures.peer['id']);
      expect(request['seconds'], 15);
      expect(find.textContaining('Auto Dump in'), findsOneWidget);
      await t.pump(const Duration(seconds: 16));
      await t.pump();
      expect(find.byType(SocialDumpTruck), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Private meeting address'), findsNothing);
      expect(find.text('I will be there'), findsOneWidget);
      expect(find.text('Keep this unsent draft'), findsOneWidget);
      expect(find.text('Message removed'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('sender can choose everyone for a group message', (t) async {
    final store = DumpStore(t.binding.clock.now);
    await mount(t, store, group: true);
    await choose(t, 'second');
    expect(find.text('For everyone'), findsOneWidget);
    await replies.tap(t, find.byKey(const ValueKey('dump-scope-everyone')));
    expect(find.textContaining('Screenshots, downloads'), findsOneWidget);
    await replies.tap(t, find.byKey(const ValueKey('dump-confirm')));
    final request = store.calls.lastWhere(
      (call) => call['action'] == 'dump_schedule',
    );
    expect(request['dump_scope'], 'everyone');
    expect(request['group'], fixtures.peer['id']);
    expect(store.due, isEmpty);
    expect(store.everyoneDue.keys, ['second']);
  });

  testWidgets(
    'recipient cannot cancel an everyone timer and can set personal timer',
    (t) async {
      final store = DumpStore(t.binding.clock.now);
      store.everyoneDue['first'] = store.serverNow.add(
        const Duration(hours: 1),
      );
      await mount(t, store);
      await choose(t, 'first');
      expect(find.byKey(const ValueKey('dump-scope-everyone')), findsNothing);
      expect(find.byKey(const ValueKey('dump-cancel')), findsNothing);
      expect(find.textContaining('Sender timer for everyone:'), findsOneWidget);
      await replies.tap(t, find.byKey(const ValueKey('dump-confirm')));
      expect(store.due.containsKey('first'), true);
      expect(store.everyoneDue.containsKey('first'), true);
    },
  );

  testWidgets('cancelling personal timer leaves sender everyone timer active', (
    t,
  ) async {
    final store = DumpStore(t.binding.clock.now);
    store.due['second'] = store.serverNow.add(const Duration(minutes: 1));
    store.everyoneDue['second'] = store.serverNow.add(const Duration(hours: 1));
    await mount(t, store);
    await choose(t, 'second');
    expect(
      find.textContaining('A personal timer and an everyone timer'),
      findsOneWidget,
    );
    await replies.tap(t, find.byKey(const ValueKey('dump-cancel')));
    expect(store.due, isEmpty);
    expect(store.everyoneDue.containsKey('second'), true);
    final request = store.calls.lastWhere(
      (call) => call['action'] == 'dump_cancel',
    );
    expect(request['dump_scope'], 'self');
    expect(
      find.textContaining('The other Auto Dump timer remains active'),
      findsOneWidget,
    );
  });

  testWidgets(
    'everyone expiry scrubs loaded original, reply and composer draft',
    (t) async {
      final store = DumpStore(t.binding.clock.now);
      store.everyoneDue['first'] = store.serverNow.add(
        const Duration(seconds: 15),
      );
      await mount(t, store);
      await replies.tap(t, find.byKey(const ValueKey('reply-first')));
      await t.enterText(find.byType(TextField), 'Keep my response');
      await replies.tap(t, find.byKey(const ValueKey('quote-second')));
      await t.pump(const Duration(seconds: 16));
      await t.pumpAndSettle();
      expect(find.text('Private meeting address'), findsNothing);
      expect(
        find.byKey(const ValueKey('reply-composer-preview')),
        findsNothing,
      );
      await replies.tap(t, find.byTooltip('Close original message'));
      expect(find.text('Keep my response'), findsOneWidget);
    },
  );

  testWidgets('scope change after failed save uses a fresh request id', (
    t,
  ) async {
    final store = DumpStore(t.binding.clock.now)..fail = true;
    await mount(t, store);
    await choose(t, 'second');
    await replies.tap(t, find.byKey(const ValueKey('dump-confirm')));
    final first = store.calls.lastWhere(
      (call) => call['action'] == 'dump_schedule',
    );
    await replies.tap(t, find.byKey(const ValueKey('dump-scope-everyone')));
    store.fail = false;
    await replies.tap(t, find.byKey(const ValueKey('dump-confirm')));
    final second = store.calls.lastWhere(
      (call) => call['action'] == 'dump_schedule',
    );
    expect(second['request_id'], isNot(first['request_id']));
    expect(second['dump_scope'], 'everyone');
  });

  testWidgets(
    'failed save preserves selected message and retries same request id',
    (t) async {
      final store = DumpStore(t.binding.clock.now)..fail = true;
      await mount(t, store);
      await choose(t, 'first');
      await replies.tap(t, find.byKey(const ValueKey('dump-confirm')));
      expect(
        find.textContaining('Timer connection interrupted'),
        findsOneWidget,
      );
      expect(find.byType(SocialAutoDumpSheet), findsOneWidget);
      expect(store.due, isEmpty);
      final first = store.calls.lastWhere(
        (call) => call['action'] == 'dump_schedule',
      );
      store.fail = false;
      await replies.tap(t, find.byKey(const ValueKey('dump-confirm')));
      final second = store.calls.lastWhere(
        (call) => call['action'] == 'dump_schedule',
      );
      expect(second['request_id'], first['request_id']);
      expect(find.byType(SocialAutoDumpSheet), findsNothing);
    },
  );

  testWidgets(
    'cancel confirmed timer keeps message and reschedule uses new duration',
    (t) async {
      final store = DumpStore(t.binding.clock.now);
      await mount(t, store);
      await choose(t, 'first');
      await replies.tap(t, find.byKey(const ValueKey('dump-confirm')));
      await choose(t, 'first');
      await replies.tap(t, find.byKey(const ValueKey('dump-delay-3600')));
      await replies.tap(t, find.byKey(const ValueKey('dump-confirm')));
      final schedules = store.calls
          .where((call) => call['action'] == 'dump_schedule')
          .toList();
      expect(schedules.last['seconds'], 3600);
      expect(
        schedules.last['request_id'],
        isNot(schedules.first['request_id']),
      );
      await choose(t, 'first');
      await replies.tap(t, find.byKey(const ValueKey('dump-cancel')));
      expect(store.due, isEmpty);
      await t.pump(const Duration(seconds: 20));
      await t.pump();
      expect(find.text('Private meeting address'), findsNWidgets(2));
      expect(find.byType(SocialDumpTruck), findsNothing);
    },
  );

  testWidgets('group sent message is selected at 320px with scaled text', (
    t,
  ) async {
    final store = DumpStore(t.binding.clock.now);
    await mount(t, store, group: true, width: 320, scale: 1.8);
    await choose(t, 'second');
    await replies.tap(t, find.byKey(const ValueKey('dump-delay-86400')));
    await replies.tap(t, find.byKey(const ValueKey('dump-confirm')));
    final request = store.calls.lastWhere(
      (call) => call['action'] == 'dump_schedule',
    );
    expect(request['group'], fixtures.peer['id']);
    expect(request.containsKey('peer'), false);
    expect(request['seconds'], 86400);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'account change while save is pending clears private preview and prevents success',
    (t) async {
      final store = DumpStore(t.binding.clock.now)
        ..saveGate = Completer<void>();
      await mount(t, store);
      await choose(t, 'first');
      await t.tap(find.byKey(const ValueKey('dump-confirm')));
      await t.pump();
      store.switchAccount();
      await t.pump();
      expect(find.text('Private meeting address'), findsNothing);
      store.saveGate!.complete();
      await t.pumpAndSettle();
      expect(find.textContaining('Auto Dump scheduled'), findsNothing);
      expect(find.byType(SocialDumpTruck), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'expiry scrubs original message sheet and selected reply without losing draft',
    (t) async {
      final store = DumpStore(t.binding.clock.now);
      await mount(t, store);
      await choose(t, 'first');
      await replies.tap(t, find.byKey(const ValueKey('dump-confirm')));
      await replies.tap(t, find.byKey(const ValueKey('reply-first')));
      await t.enterText(find.byType(TextField), 'Keep my response');
      await replies.tap(t, find.byKey(const ValueKey('quote-second')));
      expect(find.text('Original message'), findsOneWidget);
      await t.pump(const Duration(seconds: 16));
      await t.pumpAndSettle();
      expect(find.text('Private meeting address'), findsNothing);
      expect(find.text('Reply to this message'), findsNothing);
      expect(
        find.byKey(const ValueKey('reply-composer-preview')),
        findsNothing,
      );
      expect(find.byType(SocialDumpTruck), findsNothing);
      await replies.tap(t, find.byTooltip('Close original message'));
      expect(find.text('Keep my response'), findsOneWidget);
    },
  );

  testWidgets(
    'cross device expiry removes cached message via dumped ids on refresh',
    (t) async {
      final store = DumpStore(t.binding.clock.now);
      await mount(t, store);
      store.due['first'] = store.serverNow.subtract(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(find.text('Private meeting address'), findsNothing);
      expect(find.text('I will be there'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel on another device restores an older loaded message after local offline expiry',
    (t) async {
      final store = DumpStore(t.binding.clock.now);
      await mount(t, store);
      await choose(t, 'first');
      await replies.tap(t, find.byKey(const ValueKey('dump-confirm')));
      store.failHistory = true;
      store.due.remove(
        'first',
      ); // Other device cancels before the old deadline.
      await t.pump(const Duration(seconds: 16));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Private meeting address'), findsNothing);
      store.failHistory = false;
      store.omitFirst =
          true; // Original is now outside the newest history page.
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(
        store.calls.any(
          (call) => call['action'] == 'message' && call['id'] == 'first',
        ),
        true,
      );
      expect(find.text('Private meeting address'), findsNWidgets(2));
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel restores older quote without inserting an unloaded original bubble',
    (t) async {
      final store = DumpStore(t.binding.clock.now)..omitFirst = true;
      store.due['first'] = store.serverNow.add(const Duration(seconds: 15));
      await mount(t, store);
      expect(find.text('Private meeting address'), findsOneWidget);
      store.failHistory = true;
      store.due.remove('first');
      await t.pump(const Duration(seconds: 16));
      await t.pumpAndSettle();
      expect(find.text('Private meeting address'), findsNothing);
      store.rows.add(replies.message('third', 3, 'A newer history page'));
      store.omitSecond = true;
      store.failHistory = false;
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(find.text('Private meeting address'), findsOneWidget);
      expect(find.byKey(const ValueKey('reply-first')), findsNothing);
      expect(find.text('I will be there'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
