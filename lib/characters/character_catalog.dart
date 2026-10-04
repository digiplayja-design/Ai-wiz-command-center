import 'package:flutter/material.dart';

String normalizeKorlixCharacterId(String? id) {
  final raw = (id ?? '')
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  return switch (raw) {
    '' => 'jj',
    'jia' => 'ji_a',
    'cheechai' || 'cheechaichee' => 'chee_chai_chee',
    _ => raw,
  };
}

class KorlixCharacter {
  const KorlixCharacter(
    this.id,
    this.name,
    this.role,
    this.description,
    this.folder,
    this.color,
  );
  final String id, name, role, description, folder;
  final Color color;
  String get portrait => 'assets/characters/$folder/portrait.jpg';
  String get video => 'assets/characters/$folder/intro.mp4';
}

const korlixCharacters = [
  KorlixCharacter(
    'jj',
    'JJ',
    'THE CURIOUS ONE',
    'Curious, thoughtful, and always ready to chat. Ask JJ anything.',
    'jj',
    Color(0xFF39D9F9),
  ),
  KorlixCharacter(
    'phil',
    'Phil',
    'YOUR EVERYDAY GUIDE',
    'Helpful, confident, and easy to talk to. Turn your ideas into next steps.',
    'phil',
    Color(0xFFFFB86B),
  ),
  KorlixCharacter(
    'chee_chai_chee',
    'Chee Chai Chee',
    'THE CYBER MYSTIC',
    'A little mystery. A lot of perspective. Explore bold ideas and thoughtful strategies.',
    'chee_chai_chee',
    Color(0xFFAA92FF),
  ),
  KorlixCharacter(
    'yuna',
    'Yuna',
    'THE CREATIVE MIND',
    'Elegant, imaginative, and strategic. Find a fresh angle on your next big idea.',
    'yuna',
    Color(0xFFFF81C2),
  ),
  KorlixCharacter(
    'ji_a',
    'Ji-a',
    'THE CALM THINKER',
    'Clear thinking with a thoughtful touch. Bring focus to whatever comes next.',
    'ji-a',
    Color(0xFF63E8BF),
  ),
];

KorlixCharacter korlixCharacterFor(String id) => korlixCharacters.firstWhere(
  (character) => character.id == normalizeKorlixCharacterId(id),
  orElse: () => korlixCharacters.first,
);
