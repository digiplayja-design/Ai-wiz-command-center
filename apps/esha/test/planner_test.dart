import 'package:esha_by_korlix/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final catalog = fixtureCatalog();
  test('a complete routine never exceeds the new-product budget', () {
    for (final goal in goals.keys) {
      for (var budget = 10; budget <= 100; budget++) {
        final state = Vanity(
          prefs: BeautyPreferences(goal: goal, budget: budget),
        );
        final result = recommend(catalog, state);
        if (!result.complete) continue;
        expect(
          result.items.map((p) => p.category).toList(),
          goals[goal]!.categories,
        );
        expect(result.costCents, lessThanOrEqualTo(budget * 100));
        expect(
          result.costCents,
          result.items.fold<int>(0, (sum, p) => sum + p.priceCents!),
        );
        expect(result.items.every((p) => p.pricedUsd), isTrue);
      }
    }
  });
  test('unknown-currency gloss is excluded until marked owned', () {
    final unknown = catalog.byId('nyx-butter-gloss')!;
    expect(unknown.priceCents, isNull);
    final prefs = const BeautyPreferences(goal: 'lips', budget: 10);
    final newPurchase = recommend(catalog, Vanity(prefs: prefs));
    expect(newPurchase.items.map((p) => p.id), isNot(contains(unknown.id)));
    final owned = recommend(catalog, Vanity(prefs: prefs, owned: [unknown.id]));
    expect(owned.items.map((p) => p.id), contains(unknown.id));
    expect(owned.costCents, 600);
    final ignored = recommend(
      catalog,
      Vanity(prefs: prefs.copyWith(useOwned: false), owned: [unknown.id]),
    );
    expect(ignored.items.map((p) => p.id), isNot(contains(unknown.id)));
  });
  test('body fragrance is strict and independent of makeup finish', () {
    for (final finish in ['natural', 'dewy', 'satin', 'matte', 'any']) {
      final result = recommend(
        catalog,
        Vanity(
          prefs: BeautyPreferences(
            goal: 'body',
            fragrance: 'none',
            finish: finish,
            budget: 25,
          ),
        ),
      );
      expect(result.complete, isTrue);
      expect(result.items.every((p) => p.fragrance == 'none'), isTrue);
      expect(result.costCents, 2199);
    }
    final insufficient = recommend(
      catalog,
      Vanity(prefs: const BeautyPreferences(goal: 'body', budget: 10)),
    );
    expect(insufficient.complete, isFalse);
    expect(insufficient.minimumCents, 2199);
    expect(insufficient.items, isEmpty);
  });
  test(
    'schema v2 roundtrip preserves saved selection and private sharing default',
    () {
      final routine = SavedRoutine(
        id: 'saved-routine',
        name: 'Saved lips',
        ids: ['nyx-butter-gloss', 'elf-o-face-dirty-talk'],
        costCents: 1000,
        createdAt: '2026-11-15T00:00:00Z',
        prefs: const BeautyPreferences(goal: 'lips'),
        ownedAtSave: ['nyx-butter-gloss'],
        items: [
          {'id': 'nyx-butter-gloss', 'name': 'Saved label', 'priceCents': null},
        ],
      );
      final state = Vanity(
        favorites: ['elf-soft-glam'],
        routines: [routine],
        looks: [
          const StudioLook(
            id: 'look1',
            shade: 3,
            finish: 'Gloss',
            lashes: 'Bold',
          ),
        ],
      );
      final restored = Vanity.fromJson(state.toJson());
      expect(restored.toJson(), state.toJson());
      expect(restored.routines.single.ids, [
        'nyx-butter-gloss',
        'elf-o-face-dirty-talk',
      ]);
      expect(restored.routines.single.items.single['name'], 'Saved label');
      expect(restored.beautyProfile.shareWithEsha, isFalse);
      expect(
        () => Vanity.fromJson({...state.toJson(), 'schemaVersion': 1}),
        throwsA(isA<EshaException>()),
      );
      expect(
        () => Vanity.fromJson({
          ...state.toJson(),
          'favorites': List.filled(101, 'x'),
        }),
        throwsA(isA<EshaException>()),
      );
    },
  );
}
