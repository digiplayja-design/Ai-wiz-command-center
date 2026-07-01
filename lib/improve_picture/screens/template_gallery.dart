import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';

import '../models/portrait_studio_callback.dart';
import '../models/template_model.dart';
import '../widgets/template_card.dart';
import 'template_variations.dart';

class TemplateGalleryScreen extends StatelessWidget {
  const TemplateGalleryScreen({
    super.key,
    required this.gender,
    required this.hasUploadedPhoto,
    this.uploadedFile,
    this.onGeneratePrompt,
  });

  final ImproveGender gender;
  final bool hasUploadedPhoto;
  final fp.PlatformFile? uploadedFile;
  final ImprovePicturePromptCallback? onGeneratePrompt;

  @override
  Widget build(BuildContext context) {
    final genderLabel = gender == ImproveGender.female ? 'Female' : 'Male';

    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05070D),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('$genderLabel Templates'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
          children: [
            Text(
              'Improve My Picture',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose 1 of 12 categories. Each category includes 3 premium ideas.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            if (uploadedFile != null)
              Text(
                'Photo ready: ${uploadedFile!.name}',
                style: const TextStyle(
                  color: Color(0xFFB6FF2E),
                  fontWeight: FontWeight.w800,
                ),
              ),
            const SizedBox(height: 16),
            GridView.builder(
              itemCount: kImprovePictureTemplates.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.84,
              ),
              itemBuilder: (context, index) {
                final template = kImprovePictureTemplates[index];

                return TemplateCard(
                  template: template,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TemplateVariationsScreen(
                          gender: gender,
                          template: template,
                          hasUploadedPhoto: hasUploadedPhoto,
                          uploadedFile: uploadedFile,
                          onGeneratePrompt: onGeneratePrompt,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
