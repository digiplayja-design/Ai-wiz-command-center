import 'package:flutter/material.dart';
import '../theme/korlix_theme.dart';
import 'logo_model.dart';
import 'logo_render.dart';

/// Lightweight, illustrative placements of the current editable design.
class LogoPreviewBoard extends StatelessWidget {
  const LogoPreviewBoard({super.key, required this.design});
  final LogoDesign design;

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    return Column(
      key: const Key('logo-in-use'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'See it in use.',
          style: TextStyle(
            color: skin.text,
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'A quick look at your brand on the web, in print, and in a profile. These illustrative previews update as you edit.',
          style: TextStyle(color: skin.mutedText, height: 1.5),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 650
                ? (constraints.maxWidth - 24) / 3
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 18,
              children: [
                _placement(context, 'Website header', width, _website()),
                _placement(context, 'Business card', width, _businessCard()),
                _placement(context, 'Profile avatar', width, _profile()),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _placement(
    BuildContext context,
    String label,
    double width,
    Widget child,
  ) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: SizedBox(width: double.infinity, child: child),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: korlixSkinOf(context).mutedText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _website() => DecoratedBox(
    decoration: const BoxDecoration(color: Color(0xFFFFFFFF)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              Icon(Icons.circle, color: Color(0xFFDFDCE8), size: 7),
              SizedBox(width: 4),
              Icon(Icons.circle, color: Color(0xFFDFDCE8), size: 7),
              SizedBox(width: 4),
              Icon(Icons.circle, color: Color(0xFFDFDCE8), size: 7),
              Spacer(),
              Icon(Icons.menu_rounded, color: Color(0xFF5F6574), size: 16),
            ],
          ),
        ),
        LogoCanvas(
          design: design.copy(layout: 'Horizontal', tagline: ''),
          aspectRatio: 3.6,
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Made to stand out.',
                style: TextStyle(
                  color: Color(0xFF172033),
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 10),
              Container(height: 5, width: 120, color: const Color(0xFFE8EBF1)),
              const SizedBox(height: 5),
              Container(height: 5, width: 90, color: const Color(0xFFE8EBF1)),
              const SizedBox(height: 12),
              Container(
                width: 55,
                height: 15,
                decoration: BoxDecoration(
                  color: logoColor(design.primary),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _businessCard() => DecoratedBox(
    decoration: BoxDecoration(color: logoColor(design.paper)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LogoCanvas(design: design, aspectRatio: 1.9),
        Container(height: 5, color: logoColor(design.secondary)),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Icon(Icons.language_rounded, color: Color(0xFF526073), size: 15),
              Icon(
                Icons.alternate_email_rounded,
                color: Color(0xFF526073),
                size: 15,
              ),
              Icon(Icons.phone_outlined, color: Color(0xFF526073), size: 15),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _profile() => DecoratedBox(
    decoration: const BoxDecoration(color: Color(0xFFF0F2F8)),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          SizedBox(
            width: 92,
            child: ClipOval(
              child: LogoCanvas(design: design, iconOnly: true, aspectRatio: 1),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            design.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF172033),
              fontWeight: FontWeight.w800,
            ),
          ),
          if (design.tagline.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              design.tagline,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF596375),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            height: 5,
            width: 60,
            decoration: BoxDecoration(
              color: logoColor(design.secondary),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    ),
  );
}
