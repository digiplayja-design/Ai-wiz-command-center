import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';

import '../models/portrait_studio_callback.dart';
import '../models/template_model.dart';
import 'preview_screen.dart';

class TemplateVariationsScreen extends StatelessWidget {
  const TemplateVariationsScreen({
    super.key,
    required this.gender,
    required this.template,
    required this.hasUploadedPhoto,
    required this.bestResults,
    required this.identityLock,
    this.uploadedFile,
    this.onGeneratePrompt,
  });

  final ImproveGender gender;
  final ImproveTemplate template;
  final bool hasUploadedPhoto;
  final bool bestResults;
  final bool identityLock;
  final fp.PlatformFile? uploadedFile;
  final ImprovePicturePromptCallback? onGeneratePrompt;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05070D),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(template.name),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
          children: [
            Text(
              '${template.name} Looks',
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
            const SizedBox(height: 10),
            Text(
              '${bestResults ? 'Best Results ON' : 'Best Results OFF'} • ${identityLock ? 'Identity Lock ON' : 'Identity Lock OFF'}',
              style: const TextStyle(
                color: Color(0xFFB6FF2E),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            ...template.variations.map((variation) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PreviewScreen(
                            gender: gender,
                            template: template,
                            variation: variation,
                            hasUploadedPhoto: hasUploadedPhoto,
                            uploadedFile: uploadedFile,
                            bestResults: bestResults,
                            identityLock: identityLock,
                            onGeneratePrompt: onGeneratePrompt,
                          ),
                        ),
                      );
                    },
                    child: Ink(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B0E17),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: const Color(0xFF7B3CFF).withOpacity(0.26),
                        ),
                      ),
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Icon(template.icon, color: const Color(0xFFC07CFF)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  variation,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tap to preview and generate this look.',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.58),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ],
                      ),
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
