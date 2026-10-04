import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_wiz_command_center/characters/character_catalog.dart';
import 'package:ai_wiz_command_center/characters/character_selection_controller.dart';

http.Response catalog({String tier = 'basic', String id = 'jj'}) =>
    http.Response(
      jsonEncode({
        'profile': {'tier': tier, 'selected_character': id},
        'characters': [
          for (final c in korlixCharacters)
            {
              'id': c.id,
              'tier_required': 'ultra',
              'is_active': true,
              'is_coming_soon': false,
            },
          {'id': 'character_06', 'is_active': false, 'is_coming_soon': true},
        ],
      }),
      200,
    );
void main() {
  for (final tier in ['basic', 'pro', 'ultra', 'enterprise']) {
    test(
      '$tier can select each released character and restore the saved choice',
      () async {
        final selected = ValueNotifier('jj'), session = ValueNotifier(0);
        var saved = 'jj';
        final controller = CharacterSelectionController(
          baseUrl: 'https://test.example',
          headersBuilder: () => {'Authorization': 'Bearer session'},
          selected: selected,
          sessionChanges: session,
          client: MockClient((request) async {
            if (request.method == 'GET') return catalog(tier: tier, id: saved);
            expect(request.headers['Authorization'], 'Bearer session');
            saved = jsonDecode(request.body)['character_id'] as String;
            return http.Response(
              jsonEncode({
                'success': true,
                'profile': {'selected_character': saved},
              }),
              200,
            );
          }),
        );
        addTearDown(controller.dispose);
        await controller.load();
        expect(controller.availableIds.length, 5);
        expect(controller.availableIds, isNot(contains('character_06')));
        for (final c in korlixCharacters) {
          await controller.select(c.id);
          expect(selected.value, c.id);
        }
        await controller.load();
        expect(selected.value, 'ji_a');
      },
    );
  }
  test(
    'failed selection preserves confirmed character and can be retried',
    () async {
      var fail = true;
      final selected = ValueNotifier('jj');
      final c = CharacterSelectionController(
        baseUrl: 'https://test.example',
        headersBuilder: () => {},
        selected: selected,
        sessionChanges: ValueNotifier(0),
        client: MockClient((r) async {
          if (r.method == 'GET') return catalog();
          if (fail) return http.Response('{}', 500);
          return http.Response(
            '{"success":true,"profile":{"selected_character":"yuna"}}',
            200,
          );
        }),
      );
      addTearDown(c.dispose);
      await c.load();
      await c.select('yuna');
      expect(selected.value, 'jj');
      expect(c.error, isNotNull);
      expect(c.saving, false);
      fail = false;
      await c.select('yuna');
      expect(selected.value, 'yuna');
      expect(c.error, isNull);
    },
  );
  test(
    'stale save cannot change the character after an account switch; simultaneous saves are blocked',
    () async {
      final pending = Completer<http.Response>();
      final session = ValueNotifier(0), selected = ValueNotifier('jj');
      var posts = 0;
      final c = CharacterSelectionController(
        baseUrl: 'https://test.example',
        headersBuilder: () => {},
        selected: selected,
        sessionChanges: session,
        client: MockClient((r) async {
          if (r.method == 'GET') {
            return catalog(id: session.value == 0 ? 'jj' : 'phil');
          }
          posts++;
          return pending.future;
        }),
      );
      addTearDown(c.dispose);
      await c.load();
      final saving = c.select('yuna');
      await c.select('ji_a');
      await Future<void>.delayed(Duration.zero);
      expect(posts, 1);
      session.value++;
      await Future<void>.delayed(Duration.zero);
      expect(selected.value, 'phil');
      pending.complete(
        http.Response(
          '{"success":true,"profile":{"selected_character":"yuna"}}',
          200,
        ),
      );
      await saving;
      expect(selected.value, 'phil');
      expect(c.saving, false);
    },
  );
  test(
    'load failure allows retry and never enables unverified characters',
    () async {
      var fail = true;
      final c = CharacterSelectionController(
        baseUrl: 'https://test.example',
        headersBuilder: () => {},
        selected: ValueNotifier('jj'),
        sessionChanges: ValueNotifier(0),
        client: MockClient(
          (r) async => fail ? http.Response('{}', 503) : catalog(),
        ),
      );
      addTearDown(c.dispose);
      await c.load();
      expect(c.availableIds, isEmpty);
      expect(c.error, isNotNull);
      fail = false;
      await c.load();
      expect(c.availableIds.length, 5);
      expect(c.error, isNull);
    },
  );
}
