import 'dart:convert';
import 'logo_font_catalog.dart';
export 'logo_font_catalog.dart';
import 'package:flutter/material.dart';
import '../imagine_studio/imagine_catalog.dart';

const logoIndustries = [
  'Technology',
  'Food & drink',
  'Beauty & wellness',
  'Retail & fashion',
  'Property & construction',
  'Professional services',
  'Fitness & outdoors',
  'Arts & entertainment',
  'Community',
  'Other',
];
const logoStyles = [
  'Modern',
  'Elegant',
  'Bold',
  'Organic',
  'Playful',
  'Minimal',
];
const logoLayouts = ['Horizontal', 'Stacked', 'Wordmark', 'Monogram'];
const logoMarks = [
  'Orbit',
  'Peak',
  'Leaf',
  'Spark',
  'Flow',
  'Arch',
  'Shield',
  'Mosaic',
  'Beacon',
  'Initials',
  'Petal',
  'Ribbon',
  'Horizon',
  'Prism',
  'Link',
  'Compass',
  'Sunrise',
  'Wings',
  'Hexagon',
  'Crown',
  'Bolt',
  'Wave',
  'Flame',
  'Drop',
  'Lotus',
  'Mountain',
  'Pulse',
  'Infinity',
  'Diamond',
  'Triangle',
  'Cube',
  'Steps',
  'Arrow',
  'Bloom',
  'Feather',
  'Sprout',
  'Heart',
  'Butterfly',
  'Anchor',
  'Bridge',
  'Gateway',
  'Orbitals',
  'Nexus',
  'Weave',
  'Target',
  'Star',
  'Helix',
  'Crescent',
];

class LogoPalette {
  const LogoPalette(this.name, this.primary, this.secondary, this.paper);
  final String name, primary, secondary, paper;
}

const logoPalettes = [
  LogoPalette('Midnight electric', '2563EB', '06B6D4', 'F3F6FD'),
  LogoPalette('Forest & clay', '16604B', 'CB825B', 'F5F3EA'),
  LogoPalette('Ink & gold', '242834', 'B78638', 'FAF6EE'),
  LogoPalette('Violet bloom', '7038B0', 'D65780', 'FBF5FD'),
  LogoPalette('Coral energy', 'CC462C', 'E69B32', 'FFF6ED'),
  LogoPalette('Pure contrast', '161B23', '66717F', 'F4F5F6'),
  LogoPalette('Ocean & pearl', '135C73', '68BDB0', 'F2F8F5'),
  LogoPalette('Plum & rose', '572B48', 'C7788D', 'FBF3F1'),
  LogoPalette('Olive & oat', '555D3B', 'BFA46B', 'F7F4EB'),
  LogoPalette('Slate & lime', '2F4053', '8CAB47', 'F2F5EF'),
  LogoPalette('Cherry & cream', '9E2540', 'D89276', 'FFF7EF'),
  LogoPalette('Cobalt & sand', '224DB2', 'D7AD70', 'FBF6ED'),
  LogoPalette('Teal & tangerine', '096F72', 'E88845', 'F1FAF6'),
  LogoPalette('Espresso', '53392D', 'B58F6C', 'FAF3E8'),
  LogoPalette('Lavender dusk', '67517A', 'AB94BF', 'FAF5FF'),
  LogoPalette('Rosewood', '7B3445', 'BA8478', 'FAF1EF'),
  LogoPalette('Jade & gold', '24684F', 'C3A347', 'F5F8EA'),
  LogoPalette('Electric punch', '542DA8', 'E4547E', 'F8F4FF'),
  LogoPalette('Burnt sienna', 'A6472B', 'CBAD70', 'FFF4E8'),
  LogoPalette('Arctic blue', '235B85', '71B3CE', 'F1F8FD'),
  LogoPalette('Terracotta sky', 'A75441', '668F9D', 'FAF5EF'),
  LogoPalette('Mustard ink', '26323C', 'C7A03B', 'FCF8E9'),
  LogoPalette('Emerald night', '176655', '7CB39A', 'EFF8F3'),
  LogoPalette('Berry sorbet', '88367A', 'D883B0', 'FFF3FA'),
];
Color logoColor(String hex) => Color(int.parse('FF$hex', radix: 16));
String cleanLogoText(String s, int max) {
  final text = s.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
  return String.fromCharCodes(text.runes.take(max));
}

class LogoDesign {
  const LogoDesign({
    this.name = '',
    this.tagline = '',
    this.industry = 'Technology',
    this.style = 'Modern',
    this.idea = '',
    this.mark = 'Orbit',
    this.layout = 'Horizontal',
    this.typeface = 'Strong',
    this.primary = '2563EB',
    this.secondary = '06B6D4',
    this.paper = 'F3F6FD',
    this.tracking = 1,
    this.symbolScale = 1,
  });
  final String name,
      tagline,
      industry,
      style,
      idea,
      mark,
      layout,
      typeface,
      primary,
      secondary,
      paper;
  final double tracking, symbolScale;
  // Value equality keeps identical previews from repainting and avoids JSON
  // serialization on every edit, undo, and shortlist lookup.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LogoDesign &&
          name == other.name &&
          tagline == other.tagline &&
          industry == other.industry &&
          style == other.style &&
          idea == other.idea &&
          mark == other.mark &&
          layout == other.layout &&
          typeface == other.typeface &&
          primary == other.primary &&
          secondary == other.secondary &&
          paper == other.paper &&
          tracking == other.tracking &&
          symbolScale == other.symbolScale;

  @override
  int get hashCode => Object.hash(
    name,
    tagline,
    industry,
    style,
    idea,
    mark,
    layout,
    typeface,
    primary,
    secondary,
    paper,
    tracking,
    symbolScale,
  );
  String? get error => name.trim().isEmpty
      ? 'Add your business or brand name first.'
      : name.runes.length > 50
      ? 'Keep the brand name to 50 characters.'
      : tagline.runes.length > 80
      ? 'Keep the tagline to 80 characters.'
      : null;
  String get initials {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'K';
    return words
        .take(2)
        .map((s) => String.fromCharCode(s.runes.first))
        .join()
        .toUpperCase();
  }

  String get filename {
    final clean = name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return clean.isEmpty
        ? 'my-logo'
        : clean.substring(0, clean.length.clamp(0, 48));
  }

  LogoDesign copy({
    String? name,
    String? tagline,
    String? industry,
    String? style,
    String? idea,
    String? mark,
    String? layout,
    String? typeface,
    String? primary,
    String? secondary,
    String? paper,
    double? tracking,
    double? symbolScale,
  }) => LogoDesign(
    name: name ?? this.name,
    tagline: tagline ?? this.tagline,
    industry: industry ?? this.industry,
    style: style ?? this.style,
    idea: idea ?? this.idea,
    mark: mark ?? this.mark,
    layout: layout ?? this.layout,
    typeface: typeface ?? this.typeface,
    primary: primary ?? this.primary,
    secondary: secondary ?? this.secondary,
    paper: paper ?? this.paper,
    tracking: tracking ?? this.tracking,
    symbolScale: symbolScale ?? this.symbolScale,
  );
  Map<String, dynamic> get json => {
    'version': 1,
    'name': name,
    'tagline': tagline,
    'industry': industry,
    'style': style,
    'idea': idea,
    'mark': mark,
    'layout': layout,
    'typeface': typeface,
    'primary': primary,
    'secondary': secondary,
    'paper': paper,
    'tracking': tracking,
    'symbolScale': symbolScale,
  };
  factory LogoDesign.fromJson(Map<String, dynamic> m) {
    if (m['version'] != 1 || m['name'] is! String) {
      throw const FormatException('Choose a KORLIX Logo Studio project file.');
    }
    String text(String key, int max) =>
        cleanLogoText(m[key] is String ? m[key] : '', max);
    String option(String key, List<String> choices) =>
        choices.contains(m[key]) ? m[key] : choices.first;
    String hex(String key, String fallback) =>
        m[key] is String && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(m[key])
        ? (m[key] as String).toUpperCase()
        : fallback;
    double number(String key, double fallback, double low, double high) =>
        m[key] is num && (m[key] as num).isFinite
        ? (m[key] as num).toDouble().clamp(low, high)
        : fallback;
    return LogoDesign(
      name: text('name', 50),
      tagline: text('tagline', 80),
      industry: option('industry', logoIndustries),
      style: option('style', logoStyles),
      idea: text('idea', 700),
      mark: option('mark', logoMarks),
      layout: option('layout', logoLayouts),
      typeface: option('typeface', logoTypefaces),
      primary: hex('primary', '2563EB'),
      secondary: hex('secondary', '06B6D4'),
      paper: hex('paper', 'F3F6FD'),
      tracking: number('tracking', 1, 0, 8),
      symbolScale: number('symbolScale', 1, .65, 1.25),
    );
  }
  ImagineBrief get aiBrief => ImagineBrief(
    style: 'design',
    size: '1024x1024',
    prompt:
        'Design one professional logo concept for the brand ${jsonEncode(name)}. Industry: $industry. Personality: $style. Logo direction: $mark, $layout. Color palette: #$primary and #$secondary. ${idea.isEmpty ? '' : 'Creative brief: $idea.'} Clean isolated logo on a plain light background, generous clear space, purposeful geometry, a strong small-size silhouette. No mockup, no grid, no additional branding or watermark.',
    lettering: '$name${tagline.isEmpty ? '' : '\n$tagline'}',
    avoid:
        'Unrelated words, copied brand identities, stock watermarks, illegible lettering.',
  );
}

// A fixed-size page can be regenerated from its index. Browsing never retains
// an ever-growing list of canvases or loses earlier pages. This is a permutation
// of a large, finite design space, not a claim of infinite unique identities.
const logoIdeasPerPage = 12;
const logoIdeaLayouts = ['Any layout', ...logoLayouts];

List<LogoDesign> logoDirections(
  LogoDesign brief, {
  int round = 0,
  bool keepColors = true,
  String layout = 'Any layout',
}) {
  final preferredMarks = switch (brief.industry) {
    'Food & drink' => ['Leaf', 'Sunrise', 'Sprout', 'Arch', 'Flame'],
    'Beauty & wellness' => ['Petal', 'Lotus', 'Drop', 'Butterfly', 'Bloom'],
    'Property & construction' => ['Arch', 'Bridge', 'Cube', 'Gateway', 'Peak'],
    'Fitness & outdoors' => ['Mountain', 'Bolt', 'Wings', 'Pulse', 'Compass'],
    'Professional services' => ['Shield', 'Nexus', 'Link', 'Crown', 'Hexagon'],
    'Arts & entertainment' => ['Spark', 'Star', 'Ribbon', 'Wave', 'Mosaic'],
    'Community' => ['Heart', 'Link', 'Sprout', 'Bloom', 'Sunrise'],
    _ => ['Orbit', 'Prism', 'Nexus', 'Arrow', 'Helix'],
  };
  final marks = {...preferredMarks, ...logoMarks}.toList();
  final preferredFonts = switch (brief.style) {
    'Elegant' => [
      'Playfair Display',
      'Bodoni Moda',
      'Cormorant Garamond',
      'Cinzel',
    ],
    'Organic' => ['Manrope', 'Lora', 'Quicksand', 'Fraunces'],
    'Playful' => ['Fredoka', 'Righteous', 'Pacifico', 'Bungee'],
    'Bold' => ['Anton', 'Bebas Neue', 'Alfa Slab One', 'Montserrat'],
    'Minimal' => ['Outfit', 'Josefin Sans', 'Raleway', 'Space Grotesk'],
    _ => ['Space Grotesk', 'Poppins', 'Montserrat', 'Manrope'],
  };
  final fonts = {
    ...preferredFonts,
    ...logoFontCatalog.map((f) => f.name),
  }.toList();
  final lockups = <(String, String)>[
    for (final candidate in ['Horizontal', 'Stacked'])
      if (layout == 'Any layout' || layout == candidate)
        for (final mark in marks) (candidate, mark),
    if (layout == 'Any layout' || layout == 'Wordmark')
      ('Wordmark', 'Initials'),
    if (layout == 'Any layout' || layout == 'Monogram')
      ('Monogram', 'Initials'),
  ];
  if (lockups.isEmpty) throw ArgumentError.value(layout, 'layout');
  final palettes = <LogoPalette>[
    LogoPalette('Your colors', brief.primary, brief.secondary, brief.paper),
    if (!keepColors)
      ...logoPalettes.where(
        (p) =>
            p.primary != brief.primary ||
            p.secondary != brief.secondary ||
            p.paper != brief.paper,
      ),
  ];
  // Omit invisible dimensions: wordmarks have no symbol size, and connected
  // script lettering/monograms have no tracking. This avoids cosmetic duplicates.
  final ranges =
      <
        ({
          int start,
          int end,
          String layout,
          String mark,
          String font,
          int trackingCount,
          int scaleCount,
        })
      >[];
  var total = 0;
  for (final lockup in lockups) {
    for (final font in fonts) {
      final trackingCount =
          lockup.$1 == 'Monogram' || logoFontFor(font).category == 'Script'
          ? 1
          : 17;
      final scaleCount = lockup.$1 == 'Wordmark' || lockup.$1 == 'Monogram'
          ? 1
          : 13;
      final count = palettes.length * trackingCount * scaleCount;
      ranges.add((
        start: total,
        end: total + count,
        layout: lockup.$1,
        mark: lockup.$2,
        font: font,
        trackingCount: trackingCount,
        scaleCount: scaleCount,
      ));
      total += count;
    }
  }
  var step = 104729;
  while (step.gcd(total) != 1) {
    step += 2;
  }
  return List.generate(logoIdeasPerPage, (i) {
    final index =
        (((round < 0 ? 0 : round) * logoIdeasPerPage + i) % total * step) %
        total;
    var low = 0, high = ranges.length - 1;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (ranges[middle].end <= index) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final range = ranges[low];
    var value = index - range.start;
    final palette = palettes[value % palettes.length];
    value ~/= palettes.length;
    final tracking = (value % range.trackingCount) / 2;
    value ~/= range.trackingCount;
    final scale = range.layout == 'Wordmark'
        ? 1.0
        : .65 + (value % range.scaleCount) * .05;
    return brief.copy(
      mark: range.mark,
      layout: range.layout,
      typeface: range.font,
      primary: palette.primary,
      secondary: palette.secondary,
      paper: palette.paper,
      tracking: tracking,
      symbolScale: scale,
    );
  });
}
