import 'korlix_appearance_preferences.dart';
import 'korlix_theme.dart';

class KorlixLookTemplate {
  const KorlixLookTemplate(
    this.name,
    this.themeId,
    this.skinId,
    this.description,
  );
  final String name, themeId, skinId, description;
  bool get isLight => korlixSkinPaletteFor(themeId).isLight;
  KorlixAppearanceChoice get choice => KorlixAppearanceChoice(themeId, skinId);
}

const korlixLookTemplates = [
  KorlixLookTemplate(
    'Signature Orbit',
    'korlix_blue',
    'orbit',
    'Cyan rings across a midnight sky.',
  ),
  KorlixLookTemplate(
    'Pearl Contour',
    'white_gray',
    'contour',
    'Fine lines and a bright, focused workspace.',
  ),
  KorlixLookTemplate(
    'Lavender Mesh',
    'lavender_mist',
    'mesh',
    'Soft violet light with an airy finish.',
  ),
  KorlixLookTemplate(
    'Golden Prism',
    'ultra_gold',
    'prism',
    'Warm gold with cut-crystal details.',
  ),
  KorlixLookTemplate(
    'Ice Glass',
    'pure_white',
    'glass',
    'White glass with clean reflections.',
  ),
  KorlixLookTemplate(
    'Ocean Glass',
    'ocean_blue',
    'glass',
    'Layered blue glass and a deep ocean glow.',
  ),
  KorlixLookTemplate(
    'Bubblegum',
    'pink_white',
    'bubbles',
    'Rose bubbles with a playful sheen.',
  ),
  KorlixLookTemplate(
    'Mint Bubbles',
    'mint_cloud',
    'bubbles',
    'Fresh mint with pearly highlights.',
  ),
  KorlixLookTemplate(
    'Northern Lights',
    'matrix_green',
    'aurora',
    'Ribbons of color through a forest night.',
  ),
  KorlixLookTemplate(
    'Midnight Fracture',
    'korlix_blue',
    'glass_break',
    'Sharp glass facets with electric edges.',
  ),
  KorlixLookTemplate(
    'Copper Contour',
    'sunset_copper',
    'contour',
    'Warm copper lines over espresso.',
  ),
  KorlixLookTemplate(
    'Paper White',
    'pure_white',
    'linen',
    'A light woven texture for a calmer screen.',
  ),
  KorlixLookTemplate(
    'Midnight Linen',
    'pure_black',
    'linen',
    'Soft texture with a deep black finish.',
  ),
  KorlixLookTemplate(
    'Rose Silk',
    'pink_white',
    'mesh',
    'Blended rose light and rounded surfaces.',
  ),
  KorlixLookTemplate(
    'Crimson Orbit',
    'dark_crimson',
    'orbit',
    'Icy rings with rich plum accents.',
  ),
  KorlixLookTemplate(
    'Forest Linen',
    'matrix_green',
    'linen',
    'Quiet texture with fresh green details.',
  ),
  KorlixLookTemplate(
    'Silver Orbit',
    'pure_black',
    'orbit',
    'Silver rings against a black backdrop.',
  ),
  KorlixLookTemplate(
    'Pure & Simple',
    'pure_white',
    'classic',
    'True white, clear text, room to focus.',
  ),
];

String korlixLookName(KorlixAppearanceChoice choice) {
  for (final look in korlixLookTemplates) {
    if (look.themeId == choice.themeId && look.skinId == choice.skinId) {
      return look.name;
    }
  }
  return 'Your custom mix';
}
