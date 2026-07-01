import '../models/template_model.dart';
import '../prompts/template_prompt_engine.dart';

class PortraitStudioController {
  PortraitStudioController({ImprovePicturePromptEngine? promptEngine})
    : _promptEngine = promptEngine ?? const ImprovePicturePromptEngine();

  final ImprovePicturePromptEngine _promptEngine;

  String buildGenerationPrompt({
    required ImproveGender gender,
    required ImproveTemplate template,
    required String variation,
    required double strength,
    required String ratio,
  }) {
    return _promptEngine.buildPrompt(
      gender: gender,
      template: template,
      variation: variation,
      strength: strength,
      ratio: ratio,
    );
  }

  Map<String, dynamic> buildGenerationPayload({
    required ImproveGender gender,
    required ImproveTemplate template,
    required String variation,
    required double strength,
    required String ratio,
    String? imageDataUrl,
    String? imageUrl,
  }) {
    final prompt = buildGenerationPrompt(
      gender: gender,
      template: template,
      variation: variation,
      strength: strength,
      ratio: ratio,
    );

    return {
      'mode': 'improve_picture_portrait_studio',
      'templateId': template.id,
      'templateName': template.name,
      'variation': variation,
      'gender': gender.name,
      'strength': strength,
      'ratio': ratio,
      'prompt': prompt,
      if (imageDataUrl != null && imageDataUrl.isNotEmpty)
        'imageDataUrl': imageDataUrl,
      if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
    };
  }

  String buildUserFacingSummary({
    required ImproveGender gender,
    required ImproveTemplate template,
    required String variation,
    required double strength,
    required String ratio,
  }) {
    final genderLabel = gender == ImproveGender.female ? 'Female' : 'Male';
    final percent = (strength * 100).round();

    return '$genderLabel • ${template.name} • $variation • $percent% • $ratio';
  }
}
