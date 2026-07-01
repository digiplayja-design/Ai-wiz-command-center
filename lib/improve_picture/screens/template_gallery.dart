import 'package:flutter/material.dart';

import '../models/template_model.dart';
import 'template_variations.dart';

class TemplateGalleryScreen extends StatelessWidget {
  const TemplateGalleryScreen({
    super.key,
    required this.gender,
    required this.hasUploadedPhoto,
  });

  final ImproveGender gender;
  final bool hasUploadedPhoto;

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
                return InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TemplateVariationsScreen(
                          gender: gender,
                          template: template,
                          hasUploadedPhoto: hasUploadedPhoto,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B0E17),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: const Color(0xFF7B3CFF).withOpacity(0.24),
                      ),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '✦ 3 ideas',
                          style: TextStyle(
                            color: Color(0xFFC07CFF),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        Icon(template.icon, color: Colors.white, size: 42),
                        const SizedBox(height: 12),
                        Text(
                          template.name.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          template.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.62),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
