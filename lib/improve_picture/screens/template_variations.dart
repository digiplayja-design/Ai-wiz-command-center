import 'package:flutter/material.dart';

import '../models/template_model.dart';
import 'preview_screen.dart';

class TemplateVariationsScreen extends StatelessWidget {
  const TemplateVariationsScreen({
    super.key,
    required this.gender,
    required this.template,
    required this.hasUploadedPhoto,
  });

  final ImproveGender gender;
  final ImproveTemplate template;
  final bool hasUploadedPhoto;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05070D),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('${template.name} Ideas'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
          children: [
            Text(
              template.name,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              template.description,
              style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            ...template.variations.asMap().entries.map((entry) {
              final index = entry.key;
              final variation = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PreviewScreen(
                          gender: gender,
                          template: template,
                          variation: variation,
                          hasUploadedPhoto: hasUploadedPhoto,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    height: 150,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B0E17),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFF7B3CFF).withOpacity(0.26),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          height: 96,
                          width: 96,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF7B3CFF), Color(0xFF05070D)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Icon(
                            template.icon,
                            color: Colors.white,
                            size: 42,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Idea ${index + 1}',
                                style: const TextStyle(
                                  color: Color(0xFFC07CFF),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                variation,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Tap to preview this ${template.name.toLowerCase()} look.',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.58),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.white54,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
