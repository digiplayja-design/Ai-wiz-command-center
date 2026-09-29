import 'dart:convert';
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
const logoTypefaces = ['Clean', 'Strong', 'Wide', 'Slanted'];
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

List<LogoDesign> logoDirections(LogoDesign brief, {int round = 0}) {
  final marks = switch (brief.industry) {
    'Food & drink' => ['Leaf', 'Arch', 'Spark', 'Flow', 'Beacon', 'Initials'],
    'Beauty & wellness' => [
      'Leaf',
      'Orbit',
      'Flow',
      'Arch',
      'Spark',
      'Initials',
    ],
    'Property & construction' => [
      'Arch',
      'Peak',
      'Mosaic',
      'Shield',
      'Beacon',
      'Initials',
    ],
    'Fitness & outdoors' => [
      'Peak',
      'Flow',
      'Shield',
      'Spark',
      'Leaf',
      'Initials',
    ],
    'Professional services' => [
      'Shield',
      'Arch',
      'Mosaic',
      'Beacon',
      'Orbit',
      'Initials',
    ],
    _ => ['Orbit', 'Spark', 'Mosaic', 'Flow', 'Peak', 'Initials'],
  };
  final font = switch (brief.style) {
    'Elegant' => 'Wide',
    'Minimal' || 'Organic' => 'Clean',
    'Playful' => 'Slanted',
    _ => 'Strong',
  };
  return List.generate(
    6,
    (i) => brief.copy(
      mark: marks[(i + round) % marks.length],
      layout: [
        'Horizontal',
        'Stacked',
        'Horizontal',
        'Stacked',
        'Wordmark',
        'Monogram',
      ][i],
      typeface: i == 2 ? 'Wide' : font,
      tracking: brief.style == 'Elegant'
          ? 4
          : i == 4
          ? 3
          : 1,
      primary: i == 3 ? brief.secondary : brief.primary,
      secondary: i == 3 ? brief.primary : brief.secondary,
    ),
  );
}

const logoDirectionNames = [
  'Signature',
  'Emblem',
  'Architect',
  'Expressive',
  'Wordmark',
  'Monogram',
];
