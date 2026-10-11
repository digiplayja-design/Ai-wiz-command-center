import 'package:flutter/material.dart';

/// Local editing recipes. Browsing or selecting one never uploads a photo.
class PictureTemplate {
  const PictureTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.instructions,
    required this.icon,
    required this.colors,
    this.preset = 'enhance',
    this.strength = 'balanced',
    this.look = 'original',
    this.lighting = 'original',
    this.size = 'auto',
  });

  final String id, name, category, description, instructions;
  final String preset, strength, look, lighting, size;
  final IconData icon;
  final List<Color> colors;

  String promptWith(String personalInstructions) => [
    'Photo template starting point: $name.\n$instructions',
    'Use the selected treatment, color, lighting, strength and output shape. '
        'Preserve the subject\'s identity and defining details. '
        'Do not add text, template names or watermarks.',
    if (personalInstructions.trim().isNotEmpty)
      'My personal instructions (take priority over the template):\n'
          '${personalInstructions.trim()}',
  ].join('\n\n');
}

const pictureTemplateCategories = [
  'All',
  'Portraits',
  'Everyday',
  'Creative',
  'Products',
  'Restore',
];

const pictureTemplates = <PictureTemplate>[
  PictureTemplate(
    id: 'clean-headshot',
    name: 'Clean headshot',
    category: 'Portraits',
    description: 'A polished profile with a calm studio backdrop.',
    instructions:
        'Create a professional headshot against a simple neutral '
        'studio background. Keep the existing outfit, expression, hair and '
        'natural skin texture. Frame the face and shoulders comfortably.',
    preset: 'headshot',
    lighting: 'studio',
    size: '1024x1024',
    icon: Icons.badge_outlined,
    colors: [Color(0xff8d9deb), Color(0xffddd8f6)],
  ),
  PictureTemplate(
    id: 'natural-glow',
    name: 'Natural glow',
    category: 'Everyday',
    description: 'Fresh light and gentle polish, still completely you.',
    instructions:
        'Gently polish this photo while keeping the original '
        'scene and composition. Retain pores, freckles and natural texture; '
        'do not reshape the face or body.',
    strength: 'subtle',
    lighting: 'soft',
    icon: Icons.auto_awesome_outlined,
    colors: [Color(0xffde9fa6), Color(0xffffdfb7)],
  ),
  PictureTemplate(
    id: 'golden-hour',
    name: 'Golden hour',
    category: 'Everyday',
    description: 'The warmth of a late afternoon photograph.',
    instructions:
        'Give the existing scene an inviting late-afternoon '
        'photographic finish. Preserve the location and all subjects; '
        'do not add a sun or change clothing.',
    look: 'warm',
    lighting: 'golden',
    icon: Icons.wb_twilight,
    colors: [Color(0xffe88e60), Color(0xffffdb94)],
  ),
  PictureTemplate(
    id: 'cinematic-portrait',
    name: 'Cinematic portrait',
    category: 'Portraits',
    description: 'Rich depth and the mood of a film still.',
    instructions:
        'Create a photographic cinematic portrait with subtle '
        'background separation and a composed, dramatic atmosphere. Keep '
        'the same person, expression and outfit. Retain shadow detail.',
    preset: 'headshot',
    look: 'cinematic',
    icon: Icons.movie_outlined,
    colors: [Color(0xff3c7b8e), Color(0xffd8a88c)],
  ),
  PictureTemplate(
    id: 'editorial',
    name: 'Editorial portrait',
    category: 'Portraits',
    description: 'A refined magazine photoshoot without the lettering.',
    instructions:
        'Create a sophisticated fashion-editorial photograph '
        'with a minimal studio background, considered composition and '
        'clear fabric texture. Keep the original clothing and person. '
        'Do not create a magazine cover layout or lettering.',
    preset: 'headshot',
    lighting: 'studio',
    size: '1024x1536',
    icon: Icons.camera_alt_outlined,
    colors: [Color(0xffb68d9f), Color(0xffefe0db)],
  ),
  PictureTemplate(
    id: 'timeless-mono',
    name: 'Timeless monochrome',
    category: 'Portraits',
    description: 'Classic black and white with soft, rich tones.',
    instructions:
        'Create a timeless fine-art black-and-white photograph. '
        'Preserve the original subject and scene with detailed midtones '
        'and natural texture; avoid crushed blacks or blank highlights.',
    look: 'mono',
    lighting: 'soft',
    icon: Icons.tonality,
    colors: [Color(0xff667382), Color(0xffe1e4e5)],
  ),
  PictureTemplate(
    id: 'social-profile',
    name: 'Social profile',
    category: 'Portraits',
    description: 'An inviting square portrait that stands out.',
    instructions:
        'Make a friendly, polished profile photograph with a '
        'simple complementary background. Center the existing person '
        'with comfortable room around the head. Keep their expression '
        'and outfit; do not add a border or icons.',
    preset: 'headshot',
    look: 'vivid',
    lighting: 'soft',
    size: '1024x1024',
    icon: Icons.account_circle_outlined,
    colors: [Color(0xff6b91d9), Color(0xffbdc7fa)],
  ),
  PictureTemplate(
    id: 'celebration',
    name: 'Celebration',
    category: 'Portraits',
    description: 'Soft party lights and a little sparkle.',
    instructions:
        'Create a celebratory portrait with a softly blurred '
        'background of small festive lights. Preserve the people, clothing '
        'and expressions. Keep decorative light behind the subjects and '
        'away from faces; do not add text, numbers or extra people.',
    preset: 'custom',
    look: 'warm',
    lighting: 'soft',
    icon: Icons.celebration_outlined,
    colors: [Color(0xffbd77bb), Color(0xfff1c485)],
  ),
  PictureTemplate(
    id: 'travel-color',
    name: 'Travel colors',
    category: 'Everyday',
    description: 'Bring out the beauty of the place you captured.',
    instructions:
        'Polish this travel photograph with balanced exposure '
        'and clear atmospheric detail. Preserve the actual location, '
        'weather, landmarks, people and readable signs. Do not invent '
        'scenery or replace the sky.',
    look: 'vivid',
    lighting: 'brighten',
    icon: Icons.landscape_outlined,
    colors: [Color(0xff4faaa1), Color(0xffb4e7de)],
  ),
  PictureTemplate(
    id: 'vintage-film',
    name: 'Vintage film',
    category: 'Everyday',
    description: 'A nostalgic print with a subtle film finish.',
    instructions:
        'Give this photo the gentle character of an analog '
        'film print, with restrained fine grain and soft highlight '
        'roll-off. Preserve the scene, details and people; do not add '
        'damage, dates, borders or light leaks over faces.',
    look: 'warm',
    strength: 'subtle',
    icon: Icons.photo_camera_back_outlined,
    colors: [Color(0xffa09a78), Color(0xffe4d6ad)],
  ),
  PictureTemplate(
    id: 'food-photo',
    name: 'Food spotlight',
    category: 'Everyday',
    description: 'Appetizing detail and inviting table light.',
    instructions:
        'Polish the photographed food and table setting with '
        'faithful color, clear texture and natural depth. Keep the exact '
        'dish, ingredients and portions. Do not add garnishes, fake steam '
        'or replace the tableware.',
    look: 'warm',
    lighting: 'soft',
    icon: Icons.restaurant_outlined,
    colors: [Color(0xffbf8261), Color(0xffe8c9a5)],
  ),
  PictureTemplate(
    id: 'pet-portrait',
    name: 'Pet portrait',
    category: 'Everyday',
    description: 'Clear eyes, beautiful fur and plenty of character.',
    instructions:
        'Polish the existing pet photograph, keeping the same '
        'animal, markings, fur, eyes and proportions. Gently separate '
        'the pet from distractions in the existing background. Do not '
        'add costumes or accessories.',
    lighting: 'soft',
    icon: Icons.pets_outlined,
    colors: [Color(0xff88a795), Color(0xffe1d7b6)],
  ),
  PictureTemplate(
    id: 'cartoon',
    name: 'Cartoon portrait',
    category: 'Creative',
    description: 'Expressive illustrated lines and smooth color.',
    instructions:
        'Transform the photo into a polished editorial cartoon '
        'illustration with clean outlines and intentional shading. Keep '
        'each person recognizable, retaining facial proportions, skin '
        'tone, hairstyle, expression and clothing. Avoid exaggeration.',
    preset: 'custom',
    strength: 'creative',
    look: 'vivid',
    icon: Icons.draw_outlined,
    colors: [Color(0xff9d83d6), Color(0xfff6c498)],
  ),
  PictureTemplate(
    id: 'watercolor',
    name: 'Watercolor',
    category: 'Creative',
    description: 'Delicate washes with a textured paper finish.',
    instructions:
        'Reinterpret the source as a refined watercolor '
        'painting with translucent pigment, soft edges and paper texture. '
        'Preserve the composition, recognizable faces, clothing and '
        'important details. Deliver one artwork without a frame.',
    preset: 'custom',
    strength: 'creative',
    icon: Icons.water_drop_outlined,
    colors: [Color(0xff81b3bd), Color(0xffe9bbce)],
  ),
  PictureTemplate(
    id: 'pencil-sketch',
    name: 'Pencil sketch',
    category: 'Creative',
    description: 'Fine graphite lines and carefully shaded detail.',
    instructions:
        'Transform the photo into a detailed graphite drawing '
        'on lightly textured paper. Preserve the original composition '
        'and recognizable subject with fine linework and controlled '
        'shading. Do not add an artist signature, frame or extra objects.',
    preset: 'custom',
    strength: 'creative',
    look: 'mono',
    icon: Icons.edit_outlined,
    colors: [Color(0xff96989d), Color(0xffefeee6)],
  ),
  PictureTemplate(
    id: 'neon-night',
    name: 'Neon night',
    category: 'Creative',
    description: 'Electric color and a cinematic night atmosphere.',
    instructions:
        'Create a cinematic night portrait with tasteful teal '
        'and magenta accent light and a softly blurred neon background. '
        'Keep the same person and clothing, natural facial detail and '
        'believable skin. Do not add signs or invented lettering.',
    preset: 'custom',
    strength: 'creative',
    look: 'cinematic',
    icon: Icons.nightlife_outlined,
    colors: [Color(0xff5469bd), Color(0xffd478c9)],
  ),
  PictureTemplate(
    id: 'smoke-aura',
    name: 'Smoke aura',
    category: 'Creative',
    description: 'A sculpted smoke backdrop with moody depth.',
    instructions:
        'Create an artistic studio portrait with elegant '
        'curves of soft smoke in the background and subtle rim light. '
        'Preserve the person, outfit and pose. Keep the face and body '
        'clear and unobscured; the subject is not smoking.',
    preset: 'custom',
    strength: 'creative',
    look: 'cinematic',
    icon: Icons.cloud_outlined,
    colors: [Color(0xff637891), Color(0xffb1b8dc)],
  ),
  PictureTemplate(
    id: 'ember-glow',
    name: 'Ember glow',
    category: 'Creative',
    description: 'A dramatic, warm fantasy portrait.',
    instructions:
        'Create a fantasy portrait with ember-like light '
        'particles in the background and a warm rim light. Keep the '
        'person, outfit and natural features unchanged. This is a '
        'decorative lighting effect: no fire touching the person or '
        'clothing and no damage or injury.',
    preset: 'custom',
    strength: 'creative',
    look: 'warm',
    icon: Icons.local_fire_department_outlined,
    colors: [Color(0xffbb6059), Color(0xfff5ae63)],
  ),
  PictureTemplate(
    id: 'white-studio',
    name: 'White studio',
    category: 'Products',
    description: 'Clean catalog photography with a grounded shadow.',
    instructions:
        'Place the exact existing product on a seamless white '
        'studio background with a soft contact shadow. Preserve its '
        'geometry, color, materials, logo and label text. Do not invent '
        'packaging, accessories or reflections containing extra objects.',
    preset: 'product',
    lighting: 'studio',
    size: '1024x1024',
    icon: Icons.inventory_2_outlined,
    colors: [Color(0xff94b3bd), Color(0xffe4edf0)],
  ),
  PictureTemplate(
    id: 'luxury-product',
    name: 'Luxury product',
    category: 'Products',
    description: 'Deep tones and carefully controlled reflections.',
    instructions:
        'Create a premium product photograph on a simple '
        'dark studio background and surface. Keep reflections subtle '
        'and physically plausible. Preserve the exact product shape, '
        'materials, brand colors and readable label text; add no props.',
    preset: 'product',
    lighting: 'studio',
    size: '1024x1024',
    icon: Icons.diamond_outlined,
    colors: [Color(0xff657887), Color(0xffc9b591)],
  ),
  PictureTemplate(
    id: 'transparent-cutout',
    name: 'Clean cutout',
    category: 'Products',
    description: 'Your subject, ready for a new background.',
    instructions:
        'Isolate the existing subject on genuine transparency '
        'with carefully preserved hair, fine edges and product details. '
        'Remove the entire background without adding a painted backdrop, '
        'checkerboard, halo or drop shadow.',
    preset: 'cutout',
    strength: 'subtle',
    icon: Icons.content_cut,
    colors: [Color(0xff78a5aa), Color(0xffc4e0d3)],
  ),
  PictureTemplate(
    id: 'restore-memory',
    name: 'Restore a memory',
    category: 'Restore',
    description: 'Repair wear while protecting the original character.',
    instructions:
        'Conservatively repair visible fading, dust, scratches '
        'and damage. Keep the people, clothing, era, setting and '
        'composition faithful to the source. Do not invent uncertain '
        'facial details. Keep monochrome photographs monochrome.',
    preset: 'restore',
    strength: 'subtle',
    icon: Icons.restore,
    colors: [Color(0xffa19082), Color(0xffead9bf)],
  ),
  PictureTemplate(
    id: 'colorize-memory',
    name: 'Colorize a memory',
    category: 'Restore',
    description: 'A gentle color interpretation of an older photo.',
    instructions:
        'Restore visible damage conservatively and colorize '
        'the photograph with restrained, plausible colors. Treat unknown '
        'original colors as an interpretation, not verified historical '
        'fact. Preserve faces, clothing, era and composition.',
    preset: 'restore',
    strength: 'subtle',
    icon: Icons.palette_outlined,
    colors: [Color(0xffbe9d7a), Color(0xffadd2bd)],
  ),
  PictureTemplate(
    id: 'low-light-rescue',
    name: 'Low-light rescue',
    category: 'Restore',
    description: 'Lift a dark photo without losing its atmosphere.',
    instructions:
        'Recover useful detail in the underexposed photograph '
        'and gently reduce distracting noise. Preserve the actual scene, '
        'nighttime atmosphere and natural texture. Do not fabricate '
        'unreadable text or facial details hidden in darkness.',
    strength: 'subtle',
    lighting: 'brighten',
    icon: Icons.brightness_6_outlined,
    colors: [Color(0xff7582b5), Color(0xffc4d2ec)],
  ),
];
