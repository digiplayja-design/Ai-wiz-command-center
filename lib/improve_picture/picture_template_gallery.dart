import 'package:flutter/material.dart';

import '../theme/korlix_theme.dart';
import 'picture_templates.dart';

class PictureTemplateGallery extends StatefulWidget {
  const PictureTemplateGallery({super.key, this.selectedId});
  final String? selectedId;

  @override
  State<PictureTemplateGallery> createState() => _PictureTemplateGalleryState();
}

class _PictureTemplateGalleryState extends State<PictureTemplateGallery> {
  final _search = TextEditingController();
  String _category = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final query = _search.text.trim().toLowerCase();
    final matches = pictureTemplates.where((template) {
      return (_category == 'All' || template.category == _category) &&
          '${template.name} ${template.category} ${template.description}'
              .toLowerCase()
              .contains(query);
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Photo templates')),
      body: SafeArea(
        child: SingleChildScrollView(
          key: const Key('picture-template-scroll'),
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1060),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Find your next look.',
                    style: TextStyle(
                      color: skin.text,
                      fontSize: 30,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Choose a starting point, then make it yours. '
                    'Your photo and personal instructions stay in the editor.',
                    style: TextStyle(color: skin.mutedText, height: 1.5),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    key: const Key('picture-template-search'),
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search templates',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () => setState(_search.clear),
                              icon: const Icon(Icons.close),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final category in pictureTemplateCategories)
                        ChoiceChip(
                          key: ValueKey('picture-template-category-$category'),
                          label: Text(category),
                          selected: _category == category,
                          onSelected: (_) =>
                              setState(() => _category = category),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${matches.length} ${matches.length == 1 ? 'template' : 'templates'}'
                    ' · Tap a style to use it',
                    style: TextStyle(color: skin.mutedText, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  if (matches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Column(
                        children: [
                          const Icon(Icons.search_off, size: 36),
                          const SizedBox(height: 12),
                          const Text('No templates match your search.'),
                          TextButton(
                            onPressed: () => setState(() {
                              _search.clear();
                              _category = 'All';
                            }),
                            child: const Text('Show all templates'),
                          ),
                        ],
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final largeText =
                            MediaQuery.textScalerOf(context).scale(1) >= 1.5;
                        final columns = largeText
                            ? (constraints.maxWidth >= 700 ? 2 : 1)
                            : constraints.maxWidth >= 950
                            ? 4
                            : constraints.maxWidth >= 620
                            ? 3
                            : constraints.maxWidth >= 320
                            ? 2
                            : 1;
                        final width =
                            (constraints.maxWidth - (columns - 1) * 14) /
                            columns;
                        return Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: [
                            for (final template in matches)
                              SizedBox(
                                width: width,
                                child: _TemplateCard(
                                  template: template,
                                  selected: widget.selectedId == template.id,
                                  onTap: () =>
                                      Navigator.of(context).pop(template),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });
  final PictureTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: skin.panel,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? skin.primary : skin.border.withValues(alpha: .45),
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          key: ValueKey('picture-template-${template.id}'),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 132,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PictureTemplateArtwork(template: template),
                    Positioned(
                      right: 10,
                      top: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xff172131).withValues(alpha: .8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(7),
                          child: Icon(
                            selected ? Icons.check : template.icon,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name,
                      style: TextStyle(
                        color: skin.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      template.description,
                      style: TextStyle(
                        color: skin.mutedText,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      selected ? 'Selected' : template.category,
                      style: TextStyle(
                        color: skin.text,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vector style illustrations, never presented as edits of the user's photo.
class PictureTemplateArtwork extends StatelessWidget {
  const PictureTemplateArtwork({super.key, required this.template});
  final PictureTemplate template;

  @override
  Widget build(BuildContext context) =>
      ExcludeSemantics(child: CustomPaint(painter: _TemplatePainter(template)));
}

class _TemplatePainter extends CustomPainter {
  const _TemplatePainter(this.template);
  final PictureTemplate template;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);
    final colors = template.colors;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ).createShader(bounds),
    );
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    final scale = size.height / 132;
    canvas.scale(scale);
    canvas.drawCircle(
      const Offset(-74, -27),
      63,
      Paint()..color = Colors.white.withValues(alpha: .1),
    );
    canvas.drawCircle(
      const Offset(84, 72),
      66,
      Paint()..color = colors.first.withValues(alpha: .22),
    );
    canvas.rotate(-.07);
    final frame = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-47, -53, 94, 110),
      const Radius.circular(7),
    );
    canvas.drawShadow(
      Path()..addRRect(frame),
      const Color(0xff263447),
      8,
      false,
    );
    canvas.drawRRect(frame, Paint()..color = const Color(0xfff4f0e9));
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-41, -47, 82, 91),
        const Radius.circular(3),
      ),
    );
    canvas.drawRect(
      const Rect.fromLTWH(-41, -47, 82, 91),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors.reversed.toList(),
        ).createShader(const Rect.fromLTWH(-41, -47, 82, 91)),
    );
    final ink = template.look == 'mono'
        ? const Color(0xff46484b)
        : Color.lerp(colors.first, const Color(0xff17293b), .58)!;
    if (template.category == 'Products') {
      if (template.preset == 'cutout') {
        for (var y = -47; y < 44; y += 10) {
          for (var x = -41; x < 41; x += 10) {
            canvas.drawRect(
              Rect.fromLTWH(x.toDouble(), y.toDouble(), 10, 10),
              Paint()
                ..color = ((x + 41 + y + 47) ~/ 10).isEven
                    ? const Color(0xffebeff1)
                    : const Color(0xffd9e0e3),
            );
          }
        }
      }
      canvas.drawOval(
        const Rect.fromLTWH(-28, 30, 56, 9),
        Paint()..color = ink.withValues(alpha: .18),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-19, -22, 38, 56),
          const Radius.circular(8),
        ),
        Paint()..color = ink,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-11, -34, 22, 14),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0xffeadcc4),
      );
      canvas.drawRect(
        const Rect.fromLTWH(-14, -5, 28, 21),
        Paint()..color = colors.last,
      );
      canvas.drawCircle(
        const Offset(0, 5),
        5,
        Paint()..color = ink.withValues(alpha: .7),
      );
    } else if ([
      'travel-color',
      'golden-hour',
      'vintage-film',
      'low-light-rescue',
    ].contains(template.id)) {
      canvas.drawCircle(
        const Offset(21, -25),
        12,
        Paint()..color = const Color(0xffffe1a4),
      );
      canvas.drawPath(
        Path()
          ..moveTo(-50, 47)
          ..lineTo(-15, -14)
          ..lineTo(33, 47)
          ..close(),
        Paint()..color = ink.withValues(alpha: .55),
      );
      canvas.drawPath(
        Path()
          ..moveTo(-17, 47)
          ..lineTo(20, 2)
          ..lineTo(51, 47)
          ..close(),
        Paint()..color = ink,
      );
    } else if (template.id == 'food-photo') {
      canvas.drawOval(
        const Rect.fromLTWH(-34, -28, 68, 62),
        Paint()..color = const Color(0xfff4eee3),
      );
      canvas.drawOval(
        const Rect.fromLTWH(-26, -20, 52, 46),
        Paint()..color = const Color(0xff899b6b),
      );
      for (final point in [
        const Offset(-13, 3),
        const Offset(11, -4),
        const Offset(4, 15),
      ]) {
        canvas.drawCircle(point, 8, Paint()..color = const Color(0xffcb795c));
        canvas.drawCircle(
          point + const Offset(-2, -2),
          3,
          Paint()..color = const Color(0xffe8b58a),
        );
      }
    } else if (template.id == 'pet-portrait') {
      canvas.drawPath(
        Path()
          ..moveTo(-27, -8)
          ..lineTo(-28, -35)
          ..lineTo(-10, -19)
          ..lineTo(10, -19)
          ..lineTo(28, -35)
          ..lineTo(27, -8)
          ..close(),
        Paint()..color = ink,
      );
      canvas.drawOval(
        const Rect.fromLTWH(-27, -21, 54, 57),
        Paint()..color = ink,
      );
      canvas.drawOval(
        const Rect.fromLTWH(-15, 3, 30, 24),
        Paint()..color = const Color(0xffe2cbaf),
      );
      for (final x in [-11.0, 11.0]) {
        canvas.drawCircle(
          Offset(x, -4),
          3,
          Paint()..color = const Color(0xffead898),
        );
      }
      canvas.drawPath(
        Path()
          ..moveTo(-4, 8)
          ..lineTo(4, 8)
          ..lineTo(0, 13)
          ..close(),
        Paint()..color = ink,
      );
    } else {
      final skin = template.look == 'mono'
          ? const Color(0xffc7c3be)
          : const Color(0xffbf896c);
      canvas.drawPath(
        Path()
          ..moveTo(-39, 49)
          ..quadraticBezierTo(-34, 13, 0, 15)
          ..quadraticBezierTo(34, 13, 39, 49)
          ..close(),
        Paint()..color = ink,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-7, 5, 14, 17),
          const Radius.circular(5),
        ),
        Paint()..color = skin,
      );
      canvas.drawOval(
        const Rect.fromLTWH(-19, -35, 38, 47),
        Paint()..color = ink,
      );
      canvas.drawOval(
        const Rect.fromLTWH(-15, -29, 30, 41),
        Paint()..color = skin,
      );
      canvas.drawPath(
        Path()
          ..moveTo(-18, -10)
          ..lineTo(-18, -23)
          ..quadraticBezierTo(-14, -45, 10, -32)
          ..quadraticBezierTo(24, -24, 16, -4)
          ..lineTo(11, -23)
          ..quadraticBezierTo(0, -17, -12, -22)
          ..close(),
        Paint()..color = ink,
      );
      final detail = Paint()
        ..color = ink
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(const Offset(-9, -10), const Offset(-6, -10), detail);
      canvas.drawLine(const Offset(6, -10), const Offset(9, -10), detail);
      canvas.drawArc(
        const Rect.fromLTWH(-5, -6, 10, 10),
        .3,
        2.5,
        false,
        detail,
      );
      if ([
        'celebration',
        'neon-night',
        'ember-glow',
        'smoke-aura',
      ].contains(template.id)) {
        for (var i = 0; i < 7; i++) {
          canvas.drawCircle(
            Offset(i.isEven ? -30 : 29, -39 + i * 12),
            template.id == 'smoke-aura' ? 8 : 2.5,
            Paint()..color = colors.last.withValues(alpha: .55),
          );
        }
      }
      if (template.id == 'pencil-sketch' || template.id == 'restore-memory') {
        for (var i = 0; i < 11; i++) {
          canvas.drawLine(
            Offset(-41, -38 + i * 8),
            Offset(41, -45 + i * 8),
            Paint()
              ..color = ink.withValues(alpha: .12)
              ..strokeWidth = .6,
          );
        }
      }
    }
    canvas.restore();
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TemplatePainter oldDelegate) =>
      template != oldDelegate.template;
}
