import 'dart:convert';

typedef Json = Map<String, dynamic>;

class EshaException implements Exception {
  const EshaException(this.code, this.message, [this.status = 0]);
  final String code;
  final String message;
  final int status;
  @override
  String toString() => message;
}

Json object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<String> strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : <String>[];
String choice(Object? value, List<String> allowed, String fallback) =>
    value is String && allowed.contains(value) ? value : fallback;
String usd(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';
Uri? safeHttpsUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

class Product {
  Product.fromJson(Json json)
    : id = json['id'] as String,
      brand = json['brand'] as String,
      name = json['name'] as String,
      category = json['category'] as String,
      description = json['description'] as String? ?? '',
      priceCents = json['priceCents'] is int && (json['priceCents'] as int) >= 0
          ? json['priceCents'] as int
          : null,
      currency = json['currency'] as String?,
      sourceUrl = json['sourceUrl'] as String,
      priceCheckedAt = json['priceCheckedAt'] as String? ?? '',
      finishTags = strings(json['finishTags']),
      textureTags = strings(json['textureTags']),
      shadeNames = strings(json['shadeNames']),
      fragrance = json['fragrance'] as String? ?? 'unknown';
  final String id,
      brand,
      name,
      category,
      description,
      sourceUrl,
      priceCheckedAt,
      fragrance;
  final int? priceCents;
  final String? currency;
  final List<String> finishTags, textureTags, shadeNames;
  bool get pricedUsd => priceCents != null && currency == 'USD';
  String get priceLabel =>
      pricedUsd ? '${usd(priceCents!)} USD' : 'Check current price';
  Json toContext() => {
    'id': id,
    'brand': brand,
    'name': name,
    'category': category,
    'description': description,
    'priceCents': priceCents,
    'currency': currency,
    'priceCheckedAt': priceCheckedAt,
    'sourceUrl': sourceUrl,
    'finishTags': finishTags,
    'textureTags': textureTags,
    'shadeNames': shadeNames,
    'fragrance': fragrance,
  };
}

class Catalog {
  Catalog.fromJson(Json json)
    : products = (json['products'] as List)
          .map((p) => Product.fromJson(object(p)))
          .toList(growable: false),
      checkedAt = json['checkedAt'] as String? ?? '',
      pricingNotice = json['pricingNotice'] as String? ?? '',
      availabilityNotice = json['availabilityNotice'] as String? ?? '',
      ingredientsNotice = json['ingredientsNotice'] as String? ?? '';
  final List<Product> products;
  final String checkedAt, pricingNotice, availabilityNotice, ingredientsNotice;
  Product? byId(String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  static const categories = [
    'Makeup',
    'Lipstick',
    'Lip gloss',
    'Lashes',
    'Body wash',
    'Lotion',
  ];
}

class BeautyPreferences {
  const BeautyPreferences({
    this.goal = 'look',
    this.budget = 45,
    this.finish = 'natural',
    this.fragrance = 'none',
    this.useOwned = true,
    this.bodyTexture = 'light',
  });
  factory BeautyPreferences.fromJson(Json j) => BeautyPreferences(
    goal: choice(j['goal'], goals.keys.toList(), 'look'),
    budget: j['budget'] is num
        ? (j['budget'] as num).round().clamp(10, 100)
        : 45,
    finish: choice(j['finish'], [
      'natural',
      'dewy',
      'satin',
      'matte',
      'any',
    ], 'natural'),
    fragrance: choice(j['fragrance'], ['none', 'any'], 'none'),
    useOwned: j['useOwned'] != false,
    bodyTexture: choice(j['bodyTexture'], ['light', 'rich', 'any'], 'light'),
  );
  final String goal, finish, fragrance, bodyTexture;
  final int budget;
  final bool useOwned;
  BeautyPreferences copyWith({
    String? goal,
    int? budget,
    String? finish,
    String? fragrance,
    bool? useOwned,
    String? bodyTexture,
  }) => BeautyPreferences(
    goal: goal ?? this.goal,
    budget: budget ?? this.budget,
    finish: finish ?? this.finish,
    fragrance: fragrance ?? this.fragrance,
    useOwned: useOwned ?? this.useOwned,
    bodyTexture: bodyTexture ?? this.bodyTexture,
  );
  Json toJson() => {
    'goal': goal,
    'budget': budget,
    'finish': finish,
    'fragrance': fragrance,
    'useOwned': useOwned,
    'bodyTexture': bodyTexture,
  };
}

class BeautyProfile {
  const BeautyProfile({
    this.undertone = 'not_sure',
    this.shareWithEsha = false,
  });
  factory BeautyProfile.fromJson(Json j) => BeautyProfile(
    undertone: choice(j['undertone'], [
      'not_sure',
      'warm',
      'cool',
      'neutral',
      'olive',
    ], 'not_sure'),
    shareWithEsha: j['shareWithEsha'] == true,
  );
  final String undertone;
  final bool shareWithEsha;
  Json toJson() => {'undertone': undertone, 'shareWithEsha': shareWithEsha};
}

class StudioLook {
  const StudioLook({
    this.id = '',
    this.shade = 0,
    this.finish = 'Satin',
    this.lashes = 'Soft',
  });
  factory StudioLook.fromJson(Json j) => StudioLook(
    id: j['id'] is String ? j['id'] as String : '',
    shade: j['shade'] is int ? (j['shade'] as int).clamp(0, 3) : 0,
    finish: choice(j['finish'], ['Satin', 'Gloss'], 'Satin'),
    lashes: choice(j['lashes'], ['Soft', 'Wispy', 'Bold'], 'Soft'),
  );
  final String id, finish, lashes;
  final int shade;
  StudioLook copyWith({
    String? id,
    int? shade,
    String? finish,
    String? lashes,
  }) => StudioLook(
    id: id ?? this.id,
    shade: shade ?? this.shade,
    finish: finish ?? this.finish,
    lashes: lashes ?? this.lashes,
  );
  Json toJson({bool includeId = true}) => {
    if (includeId) 'id': id,
    'shade': shade,
    'finish': finish,
    'lashes': lashes,
  };
}

class SavedRoutine {
  SavedRoutine({
    required this.id,
    required this.name,
    required this.ids,
    required this.costCents,
    required this.createdAt,
    required this.prefs,
    required this.ownedAtSave,
    required this.items,
  });
  factory SavedRoutine.fromJson(Json j) => SavedRoutine(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? 'Your beauty edit',
    ids: strings(j['ids']),
    costCents: j['costCents'] is int ? j['costCents'] as int : 0,
    createdAt: j['createdAt'] as String? ?? '',
    prefs: BeautyPreferences.fromJson(object(j['prefs'])),
    ownedAtSave: strings(j['ownedAtSave']),
    items: j['items'] is List ? (j['items'] as List).map(object).toList() : [],
  );
  final String id, name, createdAt;
  final List<String> ids, ownedAtSave;
  final int costCents;
  final BeautyPreferences prefs;
  final List<Json> items;
  Json toJson() => {
    'id': id,
    'name': name,
    'ids': ids,
    'costCents': costCents,
    'createdAt': createdAt,
    'prefs': prefs.toJson(),
    'ownedAtSave': ownedAtSave,
    'items': items,
  };
}

class Vanity {
  Vanity({
    List<String>? favorites,
    List<String>? owned,
    List<SavedRoutine>? routines,
    List<StudioLook>? looks,
    this.prefs = const BeautyPreferences(),
    this.beautyProfile = const BeautyProfile(),
    this.studio = const StudioLook(),
  }) : favorites = List.unmodifiable(favorites ?? []),
       owned = List.unmodifiable(owned ?? []),
       routines = List.unmodifiable(routines ?? []),
       looks = List.unmodifiable(looks ?? []);
  factory Vanity.fromJson(Json j) {
    if (j['schemaVersion'] != 2) {
      throw const EshaException(
        'INVALID_STATE',
        'This collection uses an unsupported format.',
      );
    }
    for (final field in ['favorites', 'owned', 'routines', 'looks']) {
      if (j[field] is! List || (j[field] as List).length > 100) {
        throw const EshaException(
          'INVALID_STATE',
          'This collection could not be read safely.',
        );
      }
    }
    if (utf8.encode(jsonEncode(j)).length > 262144) {
      throw const EshaException(
        'INVALID_STATE',
        'This collection is too large to save.',
      );
    }
    return Vanity(
      favorites: strings(j['favorites']).toSet().toList(),
      owned: strings(j['owned']).toSet().toList(),
      routines: (j['routines'] as List)
          .map((v) => SavedRoutine.fromJson(object(v)))
          .toList(),
      looks: (j['looks'] as List)
          .map((v) => StudioLook.fromJson(object(v)))
          .toList(),
      prefs: BeautyPreferences.fromJson(object(j['prefs'])),
      beautyProfile: BeautyProfile.fromJson(object(j['beautyProfile'])),
      studio: StudioLook.fromJson(object(j['studio'])),
    );
  }
  final List<String> favorites, owned;
  final List<SavedRoutine> routines;
  final List<StudioLook> looks;
  final BeautyPreferences prefs;
  final BeautyProfile beautyProfile;
  final StudioLook studio;
  Vanity copyWith({
    List<String>? favorites,
    List<String>? owned,
    List<SavedRoutine>? routines,
    List<StudioLook>? looks,
    BeautyPreferences? prefs,
    BeautyProfile? beautyProfile,
    StudioLook? studio,
  }) => Vanity(
    favorites: favorites ?? this.favorites,
    owned: owned ?? this.owned,
    routines: routines ?? this.routines,
    looks: looks ?? this.looks,
    prefs: prefs ?? this.prefs,
    beautyProfile: beautyProfile ?? this.beautyProfile,
    studio: studio ?? this.studio,
  );
  Json toJson() => {
    'schemaVersion': 2,
    'favorites': favorites,
    'owned': owned,
    'routines': routines.map((v) => v.toJson()).toList(),
    'looks': looks.map((v) => v.toJson()).toList(),
    'prefs': prefs.toJson(),
    'beautyProfile': beautyProfile.toJson(),
    'studio': studio.toJson(includeId: false),
  };
  bool sameAs(Vanity other) =>
      jsonEncode(toJson()) == jsonEncode(other.toJson());
}

class Goal {
  const Goal(this.title, this.categories, this.description);
  final String title, description;
  final List<String> categories;
}

const goals = {
  'look': Goal('Your makeup edit', [
    'Makeup',
    'Lipstick',
    'Lashes',
  ], 'A complexion product, a lip color and lashes for your next look.'),
  'body': Goal('Your body ritual', [
    'Body wash',
    'Lotion',
  ], 'A wash and lotion, with your fragrance and texture preferences in mind.'),
  'lips': Goal('Your lip pairing', [
    'Lipstick',
    'Lip gloss',
  ], 'A lipstick and gloss to make your own.'),
  'lashes': Goal('Your lash edit', [
    'Lashes',
  ], 'A lash style from the sourced collection.'),
};

bool finishMatches(Product p, String finish) {
  if (finish == 'any') return false;
  if (finish == 'natural') {
    return p.finishTags.any(['sheer', 'satin', 'sheen'].contains);
  }
  return p.finishTags.contains(finish);
}

bool textureMatches(Product p, String texture) => texture == 'light'
    ? p.textureTags.any(['lightweight', 'silky'].contains)
    : texture == 'rich'
    ? p.textureTags.any(['rich', 'thick', 'buttery'].contains)
    : false;

class Recommendation {
  const Recommendation({
    this.items = const [],
    this.costCents = 0,
    this.minimumCents,
    this.reason,
    this.unavailable = const [],
  });
  final List<Product> items;
  final int costCents;
  final int? minimumCents;
  final String? reason;
  final List<String> unavailable;
  bool get complete => reason == null && items.isNotEmpty;
}

Recommendation recommend(Catalog catalog, Vanity vanity) {
  final p = vanity.prefs;
  final groups = goals[p.goal]!.categories
      .map(
        (category) => catalog.products
            .where(
              (item) =>
                  item.category == category &&
                  (p.goal != 'body' ||
                      p.fragrance == 'any' ||
                      item.fragrance == 'none') &&
                  ((p.useOwned && vanity.owned.contains(item.id)) ||
                      item.pricedUsd),
            )
            .toList(),
      )
      .toList();
  final unavailable = <String>[];
  for (var i = 0; i < groups.length; i++) {
    if (groups[i].isEmpty) unavailable.add(goals[p.goal]!.categories[i]);
  }
  if (unavailable.isNotEmpty) {
    return Recommendation(reason: 'coverage', unavailable: unavailable);
  }
  List<Product>? best;
  var bestScore = -1, bestCost = 1 << 30, minimum = 1 << 30;
  void visit(int index, List<Product> items) {
    if (index < groups.length) {
      for (final item in groups[index]) {
        visit(index + 1, [...items, item]);
      }
      return;
    }
    var cost = 0, score = 0;
    for (final item in items) {
      final owned = p.useOwned && vanity.owned.contains(item.id);
      cost += owned ? 0 : item.priceCents!;
      score += owned ? 20 : 0;
      score +=
          (p.goal == 'body'
              ? textureMatches(item, p.bodyTexture)
              : finishMatches(item, p.finish))
          ? 5
          : 0;
    }
    if (cost < minimum) minimum = cost;
    if (cost <= p.budget * 100 &&
        (score > bestScore || (score == bestScore && cost < bestCost))) {
      best = items;
      bestScore = score;
      bestCost = cost;
    }
  }

  visit(0, []);
  return best == null
      ? Recommendation(reason: 'budget', minimumCents: minimum)
      : Recommendation(
          items: best!,
          costCents: bestCost,
          minimumCents: minimum,
        );
}

String recommendationReason(Product product, Vanity vanity) {
  final p = vanity.prefs;
  final parts = <String>[];
  if (p.goal == 'body') {
    parts.add(
      product.fragrance == 'none'
          ? 'The manufacturer labels this fragrance-free.'
          : 'Fits your open fragrance preference.',
    );
    if (textureMatches(product, p.bodyTexture)) {
      parts.add('Its documented texture fits your preference.');
    }
  } else {
    parts.add(
      finishMatches(product, p.finish)
          ? 'Its documented finish fits your preference.'
          : 'Fits this category within your budget.',
    );
  }
  if (p.useOwned && vanity.owned.contains(product.id)) {
    parts.add('You marked this as owned, so it adds no new product cost.');
  }
  return parts.join(' ');
}
