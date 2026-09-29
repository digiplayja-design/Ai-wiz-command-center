import 'package:flutter/material.dart';

class ImagineChoice {
  const ImagineChoice(this.id, this.label, this.hint, this.icon);
  final String id, label, hint;
  final IconData icon;
}

const imagineStyles = [
  ImagineChoice(
    'auto',
    'Creative freedom',
    'Let the scene guide the style.',
    Icons.auto_awesome_rounded,
  ),
  ImagineChoice(
    'photo',
    'Photography',
    'Natural textures. Beautiful light.',
    Icons.camera_alt_outlined,
  ),
  ImagineChoice(
    'cinematic',
    'Cinematic',
    'Atmosphere, depth and drama.',
    Icons.movie_filter_outlined,
  ),
  ImagineChoice(
    '3d',
    '3D art',
    'Sculpted forms and tactile materials.',
    Icons.view_in_ar_rounded,
  ),
  ImagineChoice(
    'illustration',
    'Illustration',
    'Expressive shapes and color.',
    Icons.brush_outlined,
  ),
  ImagineChoice(
    'design',
    'Graphic design',
    'Posters, layouts and bold ideas.',
    Icons.dashboard_outlined,
  ),
  ImagineChoice(
    'watercolor',
    'Watercolor',
    'Pigment, paper and soft edges.',
    Icons.water_drop_outlined,
  ),
  ImagineChoice(
    'sketch',
    'Pencil sketch',
    'Hand-drawn lines and shading.',
    Icons.draw_outlined,
  ),
  ImagineChoice(
    'minimal',
    'Minimal',
    'Fewer elements. More intention.',
    Icons.crop_square_rounded,
  ),
];
const imagineSizes = [
  ImagineChoice(
    '1024x1024',
    'Square',
    '1024 × 1024 · 1:1',
    Icons.crop_square_rounded,
  ),
  ImagineChoice(
    '1024x1536',
    'Portrait',
    '1024 × 1536 · 2:3',
    Icons.crop_portrait_rounded,
  ),
  ImagineChoice(
    '1536x1024',
    'Landscape',
    '1536 × 1024 · 3:2',
    Icons.crop_landscape_rounded,
  ),
];
const imagineLighting = {
  'auto': 'Let KORLIX choose',
  'soft': 'Soft studio light',
  'golden': 'Golden hour',
  'neon': 'Neon glow',
  'dramatic': 'Dramatic shadows',
  'daylight': 'Natural daylight',
};
const imaginePalettes = {
  'auto': 'From my description',
  'cool': 'Cyan & violet',
  'warm': 'Warm earth tones',
  'gold': 'Black & gold',
  'pastel': 'Soft pastels',
  'mono': 'Black & white',
};
const imagineComposition = {
  'auto': 'Let the scene decide',
  'center': 'Centered subject',
  'close': 'Close-up detail',
  'wide': 'Wide establishing shot',
  'left': 'Leave space on the left',
  'right': 'Leave space on the right',
};

class ImagineBrief {
  const ImagineBrief({
    this.prompt = '',
    this.style = 'auto',
    this.size = '1024x1024',
    this.lighting = 'auto',
    this.palette = 'auto',
    this.composition = 'auto',
    this.lettering = '',
    this.avoid = '',
  });
  final String prompt,
      style,
      size,
      lighting,
      palette,
      composition,
      lettering,
      avoid;
  String get styleLabel => imagineStyles
      .firstWhere((x) => x.id == style, orElse: () => imagineStyles.first)
      .label;
  String get sizeLabel => imagineSizes
      .firstWhere((x) => x.id == size, orElse: () => imagineSizes.first)
      .label;
  Map<String, dynamic> get json => {
    'prompt': prompt,
    'style': style,
    'size': size,
    'lighting': lighting,
    'palette': palette,
    'composition': composition,
    'lettering': lettering,
    'avoid': avoid,
  };
  factory ImagineBrief.fromJson(Map<String, dynamic> data) {
    String pick(String key, Iterable<String> options, String fallback) =>
        options.contains(data[key]) ? '${data[key]}' : fallback;
    String bounded(String key, int limit) {
      final s = data[key] is String ? data[key] as String : '';
      return s.length <= limit ? s : s.substring(0, limit);
    }

    return ImagineBrief(
      prompt: bounded('prompt', 8000),
      style: pick('style', imagineStyles.map((x) => x.id), 'auto'),
      size: pick('size', imagineSizes.map((x) => x.id), '1024x1024'),
      lighting: pick('lighting', imagineLighting.keys, 'auto'),
      palette: pick('palette', imaginePalettes.keys, 'auto'),
      composition: pick('composition', imagineComposition.keys, 'auto'),
      lettering: bounded('lettering', 300),
      avoid: bounded('avoid', 600),
    );
  }
  String get compiledPrompt => [
    prompt.trim(),
    if (lighting != 'auto') 'Lighting direction: ${imagineLighting[lighting]}.',
    if (palette != 'auto') 'Color direction: ${imaginePalettes[palette]}.',
    if (composition != 'auto')
      'Composition direction: ${imagineComposition[composition]}.',
    if (lettering.trim().isNotEmpty)
      'Include only this exact additional lettering, preserving spelling, punctuation and line breaks:\n${lettering.trim()}\nMake the lettering legible and integrated into the design.',
    if (avoid.trim().isNotEmpty) 'Avoid these elements: ${avoid.trim()}',
  ].join('\n\n');
  String? get error => prompt.trim().isEmpty
      ? 'Describe the picture you want to create.'
      : prompt.length > 8000
      ? 'Keep your description under 8,000 characters.'
      : lettering.length > 300 || avoid.length > 600
      ? 'Shorten the lettering or details to avoid.'
      : compiledPrompt.length > 11000
      ? 'Shorten your creative brief.'
      : null;
}

class ImagineStarter {
  const ImagineStarter(this.title, this.note, this.brief, this.art);
  final String title, note;
  final ImagineBrief brief;
  final int art;
}

const imagineStarters = [
  ImagineStarter(
    'Product spotlight',
    'Make a product the hero',
    ImagineBrief(
      prompt:
          'An elegant unbranded amber skincare bottle on a sculpted stone pedestal, fine water droplets, a warm architectural backdrop, premium editorial product photography.',
      style: 'photo',
      lighting: 'soft',
      palette: 'warm',
      composition: 'center',
    ),
    0,
  ),
  ImagineStarter(
    'Dream escape',
    'Somewhere beyond the ordinary',
    ImagineBrief(
      prompt:
          'A quiet glass cabin above a sea of clouds, distant mountain peaks, sunrise reflecting in the windows, an inviting path leading toward the cabin.',
      style: 'cinematic',
      size: '1536x1024',
      lighting: 'golden',
    ),
    1,
  ),
  ImagineStarter(
    'Social poster',
    'An idea worth sharing',
    ImagineBrief(
      prompt:
          'A contemporary launch poster for a neighborhood coffee pop-up, sculptural coffee cup, warm cream and deep espresso colors, clear typography and generous spacing.',
      style: 'design',
      size: '1024x1536',
      lettering: 'SOMETHING GOOD\nIS BREWING',
    ),
    2,
  ),
  ImagineStarter(
    'Sculpted worlds',
    'Play with form and texture',
    ImagineBrief(
      prompt:
          'An iridescent glass sphere floating above a brushed metal ring, tactile sculptural surfaces, a deep blue gallery space, soft reflections, sophisticated 3D editorial artwork.',
      style: '3d',
      palette: 'cool',
      lighting: 'soft',
    ),
    3,
  ),
  ImagineStarter(
    'Album artwork',
    'Give your sound a visual identity',
    ImagineBrief(
      prompt:
          'A lone figure beside a luminous ocean at midnight, a distant violet moon, reflective water, a dreamy illustrated album cover with no lettering.',
      style: 'illustration',
      palette: 'cool',
    ),
    1,
  ),
  ImagineStarter(
    'Botanical study',
    'Quiet detail, painted by hand',
    ImagineBrief(
      prompt:
          'A delicate study of tropical leaves and a single white orchid on warm textured paper, expressive transparent pigment, thoughtful empty space and graceful stems.',
      style: 'watercolor',
      size: '1024x1536',
      palette: 'warm',
    ),
    2,
  ),
];
