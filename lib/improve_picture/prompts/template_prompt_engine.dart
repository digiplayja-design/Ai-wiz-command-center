import '../models/template_model.dart';

class ImprovePicturePromptEngine {
  const ImprovePicturePromptEngine();

  String buildPrompt({
    required ImproveGender gender,
    required ImproveTemplate template,
    required String variation,
    required double strength,
    required String ratio,
  }) {
    final genderLabel = gender == ImproveGender.female ? 'female' : 'male';
    final strengthPercent = (strength * 100).round();

    return '''
Transform the uploaded portrait using the "${template.name}" template and "$variation" variation.

SUBJECT RULES:
- Subject gender presentation: $genderLabel.
- Preserve the original person's core facial identity.
- Keep eye shape, nose structure, mouth shape, jawline, face shape, facial proportions, and recognizable expression consistent.
- Do not create a new person.
- Do not over-cartoon unless the selected template is Cartoon or Caricature.
- Use realistic HD quality by default.
- Maintain believable human skin texture, pores, lighting, and natural facial depth.
- Preserve the original pose and camera angle unless the template specifically requires mirror positioning.
- Avoid plastic skin, warped eyes, melted features, extra limbs, distorted teeth, incorrect hands, and low-resolution artifacts.

OUTPUT RULES:
- Aspect ratio: $ratio.
- Effect strength: $strengthPercent%.
- Premium app-quality result.
- Clean professional portrait composition.
- No text, watermark, logos, UI, frame labels, or template names in the image.

TEMPLATE DIRECTION:
${_templateDirection(template.id, variation, genderLabel)}
''';
  }

  String _templateDirection(String id, String variation, String genderLabel) {
    switch (id) {
      case 'cartoon':
        return _cartoon(variation);
      case 'caricature':
        return _caricature(variation);
      case 'gothic':
        return _gothic(variation, genderLabel);
      case 'mirror':
        return _mirror(variation);
      case 'smoky':
        return _smoky(variation);
      case 'smooth':
        return _smooth(variation);
      case 'fiery':
        return _fiery(variation);
      case 'wet':
        return _wet(variation);
      case 'white':
        return _white(variation);
      case 'black':
        return _black(variation);
      case 'asian':
        return _asian(variation);
      case 'mask':
        return _mask(variation);
      default:
        return 'Create a realistic premium portrait enhancement while preserving identity.';
    }
  }

  String _cartoon(String variation) =>
      '''
Create a polished premium cartoon portrait, clean outlines, expressive but still recognizable face, modern editorial illustration quality.
Variation focus: $variation.
Keep identity clear and attractive, not childish, not low-quality, not overly exaggerated.
''';

  String _caricature(String variation) =>
      '''
Create a premium caricature portrait with tasteful exaggeration only.
Variation focus: $variation.
Slightly emphasize personality and expression while keeping the person recognizable and attractive.
Avoid ugly distortion, offensive exaggeration, or cheap meme style.
''';

  String _gothic(String variation, String genderLabel) =>
      '''
Create a true gothic transformation where the character themself looks gothic before the background is noticed.
Variation focus: $variation.
Use dark refined styling, gothic hair direction, dramatic eyes, moody luxury wardrobe, subtle gothic accessories, deep shadows, cathedral-inspired atmosphere, cinematic dark fashion editorial quality.
The subject must not look like a normal person pasted onto a gothic background.
Keep it realistic, intense, stylish, and premium.
''';

  String _mirror(String variation) =>
      '''
Create a mirror-world portrait where the person appears inside or facing a mirror reflection.
Variation focus: $variation.
The subject must look directly toward the viewer through the mirror/reflection, with correct facial symmetry and identity preserved.
Avoid mixing male and female features, avoid duplicate distorted faces, avoid warped reflection.
Use luxury antique mirror lighting, realistic glass depth, subtle reflection highlights, and cinematic realism.
''';

  String _smoky(String variation) =>
      '''
Create a high-end smoky aura portrait, not a basic smoke overlay.
Variation focus: $variation.
Use elegant curved smoke designs around the subject, visible flowing smoke ribbons, cool cinematic atmosphere, layered depth, controlled haze, and luxury editorial lighting.
The smoke should feel designed and premium, not random or messy.
Keep the face sharp and realistic.
''';

  String _smooth(String variation) =>
      '''
Create a luxury smooth portrait enhancement.
Variation focus: $variation.
Improve lighting, skin polish, color balance, clarity, facial depth, and professional studio quality while keeping realistic pores and human texture.
Avoid over-smoothing, waxy skin, beauty filter distortion, or changing identity.
''';

  String _fiery(String variation) =>
      '''
Create a premium fiery portrait with cinematic 3D depth.
Variation focus: $variation.
Use controlled flames, ember particles, warm rim light, glowing highlights, dramatic heat atmosphere, and realistic fire depth.
Do not cover the face. Keep identity visible and sharp.
Fire should look powerful, stylish, and luxury, not cheap.
''';

  String _wet(String variation) =>
      '''
Create a realistic wet-look portrait.
Variation focus: $variation.
Use natural water droplets, rain shine, glossy realistic highlights, damp hair/skin details when appropriate, cinematic wet lighting, and sharp facial identity.
Avoid messy distortion, plastic shine, or fake sticker-like water.
''';

  String _white(String variation) =>
      '''
Create an identity-preserving race-transformation portrait representing a white ethnic appearance.
Variation focus: $variation.
Change ethnicity-related visual cues such as skin tone, hair texture/color where appropriate, and subtle complexion characteristics while preserving the same person's facial structure, expression, pose, and identity.
Do not simply add white clothing or a white background.
Keep the result realistic, respectful, and photorealistic.
''';

  String _black(String variation) =>
      '''
Create an identity-preserving race-transformation portrait representing a Black ethnic appearance.
Variation focus: $variation.
Change ethnicity-related visual cues such as skin tone, hair texture/style where appropriate, and subtle complexion characteristics while preserving the same person's facial structure, expression, pose, and identity.
Do not simply darken the image or add a dark background.
Keep the result realistic, respectful, and photorealistic.
''';

  String _asian(String variation) =>
      '''
Create an identity-preserving race-transformation portrait representing an Asian ethnic appearance.
Variation focus: $variation.
Change ethnicity-related visual cues such as skin tone, hair texture/style where appropriate, and subtle complexion characteristics while preserving the same person's facial structure, expression, pose, and identity.
Do not create a generic new person. Keep the same recognizable face and realistic HD quality.
''';

  String _mask(String variation) =>
      '''
Create an elegant luxury mask portrait.
Variation focus: $variation.
Use a refined ornate mask with high-fashion detail, gold or jewel-like craftsmanship, luxury masquerade energy, elegant dramatic styling, premium lighting, and realistic skin.
The mask should feel expensive, bold, glamorous, and highly detailed.
Do not cover the entire identity; the person must remain recognizable.
''';
}
