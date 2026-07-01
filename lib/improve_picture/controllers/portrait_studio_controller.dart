import '../models/template_model.dart';

class PortraitStudioController {
  String buildGenerationPrompt({
    required ImproveGender gender,
    required ImproveTemplate template,
    required String variation,
    required double strength,
    required String ratio,
    bool bestResults = true,
    bool identityLock = true,
  }) {
    final subject = gender == ImproveGender.female ? 'woman' : 'man';
    final intensity = (strength * 100).round();

    final bestResultsClause = bestResults
        ? '''
Best-results mode:
- Use premium professional image quality.
- Improve lighting, skin texture, sharpness, color balance, face clarity, and background polish.
- Make the final image look finished, high-end, and ready for social/profile use.
'''
        : '''
Natural mode:
- Keep the enhancement subtle and realistic.
- Avoid over-editing.
''';

    final identityLockClause = identityLock
        ? '''
Identity-lock mode:
- Preserve the exact same person, facial identity, age range, face shape, skin tone, eyes, nose, lips, hairline, and recognizable features.
- Do not change the person into a different person.
- Do not replace the face.
'''
        : '''
Creative identity mode:
- Keep the person recognizable while allowing a slightly more stylized interpretation.
''';

    return '''
Improve this uploaded portrait using the selected AI Portrait Studio template.

Selected template: ${template.name}
Selected look: $variation
Subject type: $subject
Output ratio: $ratio
Effect strength: $intensity%

Template direction:
${template.description}

$bestResultsClause

$identityLockClause

Generation requirements:
- Generate one final finished portrait, not a before/after split.
- Apply the selected ${template.name} / $variation look visibly.
- If the template is Mask, add an elegant mask or masked styling that clearly matches the selected variation.
- If the template is Gothic, add gothic fashion, mood, lighting, and styling.
- If the template is Cartoon or Caricature, apply that style while preserving identity.
- If the template is Fiery, Smoky, Wet, Mirror, Smooth, White, Black, or Asian, apply that visual direction clearly.
- Preserve realism unless the selected template is intentionally stylized.
- Do not return the original unchanged.
- Do not only enhance brightness; apply the selected template.
- Keep the final output polished, premium, and high quality.
'''
        .trim();
  }

  Map<String, dynamic> buildGenerationPayload({
    required ImproveGender gender,
    required ImproveTemplate template,
    required String variation,
    required double strength,
    required String ratio,
    bool bestResults = true,
    bool identityLock = true,
  }) {
    return {
      'gender': gender.name,
      'template': template.name,
      'variation': variation,
      'strength': strength,
      'ratio': ratio,
      'bestResults': bestResults,
      'identityLock': identityLock,
      'prompt': buildGenerationPrompt(
        gender: gender,
        template: template,
        variation: variation,
        strength: strength,
        ratio: ratio,
        bestResults: bestResults,
        identityLock: identityLock,
      ),
    };
  }

  String buildUserFacingSummary({
    required ImproveGender gender,
    required ImproveTemplate template,
    required String variation,
    required double strength,
    required String ratio,
    bool bestResults = true,
    bool identityLock = true,
  }) {
    final parts = <String>[
      '${template.name} • $variation',
      gender.name,
      ratio,
      'strength ${(strength * 100).round()}%',
      if (bestResults) 'best results',
      if (identityLock) 'identity lock',
    ];

    return parts.join(' • ');
  }
}
