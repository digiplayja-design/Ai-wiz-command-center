import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../models.dart';

const plum = Color(0xFF392033);
const pink = Color(0xFF9A3C65);
const ivory = Color(0xFFFCF8F3);
const blush = Color(0xFFF3E4E6);
const muted = Color(0xFF74616C);

ThemeData get eshaTheme => ThemeData(
  useMaterial3: true,
  colorScheme:
      ColorScheme.fromSeed(
        seedColor: pink,
        brightness: Brightness.light,
      ).copyWith(
        primary: pink,
        onPrimary: Colors.white,
        secondary: plum,
        surface: ivory,
        onSurface: plum,
      ),
  scaffoldBackgroundColor: ivory,
  textTheme: const TextTheme(
    bodyLarge: TextStyle(fontSize: 16, height: 1.5),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5),
    titleLarge: TextStyle(
      fontSize: 23,
      fontWeight: FontWeight.w600,
      color: plum,
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: ivory,
    foregroundColor: plum,
    centerTitle: false,
    elevation: 0,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 50),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: plum,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: pink,
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.all(16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFE2D5DB)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFE2D5DB)),
    ),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.white,
    indicatorColor: blush,
    labelTextStyle: WidgetStateProperty.resolveWith(
      (_) => const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: plum,
      ),
    ),
  ),
  dividerColor: const Color(0xFFE5D9DE),
);

class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Esha by Korlix',
    excludeSemantics: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'esha',
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: compact ? 34 : 44,
            fontStyle: FontStyle.italic,
            height: 1,
            letterSpacing: -2,
            color: plum,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'BY KORLIX',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.5,
            color: muted,
          ),
        ),
      ],
    ),
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.eyebrow, this.title, this.description, {super.key});
  final String eyebrow, title, description;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: const TextStyle(
            color: pink,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Georgia',
            fontSize: 32,
            height: 1.18,
            color: plum,
          ),
        ),
        const SizedBox(height: 10),
        Text(description, style: const TextStyle(color: muted)),
      ],
    ),
  );
}

class EshaPanel extends StatelessWidget {
  const EshaPanel({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFEADFE2)),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class ChoiceGroup extends StatelessWidget {
  const ChoiceGroup({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final String label, value;
  final Map<String, String> options;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: options.entries
            .map(
              (entry) => ChoiceChip(
                label: Text(entry.value),
                selected: value == entry.key,
                onSelected: onChanged == null
                    ? null
                    : (_) => onChanged!(entry.key),
                selectedColor: blush,
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
              ),
            )
            .toList(),
      ),
    ],
  );
}

void showMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
Future<void> openSource(BuildContext context, String url) async {
  final uri = safeHttpsUrl(url);
  if (uri == null) {
    showMessage(context, 'This product link is unavailable.');
    return;
  }
  try {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      showMessage(context, 'The link could not be opened. Please try again.');
    }
  } catch (_) {
    if (context.mounted) {
      showMessage(context, 'The link could not be opened. Please try again.');
    }
  }
}

/// Used by feature surfaces and their separate modal routes. Losing access
/// replaces their content even when the route was opened while entitled.
class EntitledContent extends StatelessWidget {
  const EntitledContent({
    super.key,
    required this.controller,
    required this.builder,
    this.ownerId,
  });
  final EshaController controller;
  final WidgetBuilder builder;
  final String? ownerId;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (controller.hasAppAccess &&
          (ownerId == null || ownerId == controller.session?.userId)) {
        return builder(context);
      }
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: EshaPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Esha membership',
                    style: TextStyle(fontFamily: 'Georgia', fontSize: 26),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    ownerId != null && ownerId != controller.session?.userId
                        ? 'This view belongs to a different signed-in account. Close it to continue.'
                        : controller.purchases.accessMessage,
                  ),
                  if (Navigator.of(context).canPop()) ...[
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close this view'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.controller,
  });
  final Product product;
  final EshaController controller;
  @override
  Widget build(BuildContext context) {
    final favorite = controller.vanity.favorites.contains(product.id),
        owned = controller.vanity.owned.contains(product.id);
    return EshaPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
            child: Stack(
              children: [
                SizedBox(
                  height: 130,
                  width: double.infinity,
                  child: ColoredBox(
                    color:
                        product.category == 'Body wash' ||
                            product.category == 'Lotion'
                        ? const Color(0xFFEDECE2)
                        : blush,
                    child: ExcludeSemantics(
                      child: CustomPaint(
                        painter: ProductPainter(product.category),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton.filledTonal(
                    tooltip: favorite
                        ? 'Remove ${product.name} from favorites'
                        : 'Favorite ${product.name}',
                    onPressed: controller.canEditCollection
                        ? () => controller.toggleFavorite(product)
                        : null,
                    icon: Icon(
                      favorite ? Icons.favorite : Icons.favorite_border,
                      size: 20,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: .9),
                    ),
                  ),
                ),
                const Positioned(
                  bottom: 7,
                  left: 11,
                  child: Text(
                    'ILLUSTRATION',
                    style: TextStyle(
                      fontSize: 8,
                      letterSpacing: 1.3,
                      color: muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.brand.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9,
                    letterSpacing: .8,
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  product.name,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  product.priceLabel,
                  style: const TextStyle(
                    color: pink,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                TextButton(
                  onPressed: () => showProduct(context, product, controller),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                  ),
                  child: const Text('View details ↗'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton.icon(
              onPressed: controller.canEditCollection
                  ? () => controller.toggleOwned(product)
                  : null,
              icon: Icon(
                owned ? Icons.check_circle : Icons.add_circle_outline,
                size: 17,
              ),
              label: Text(
                owned ? 'In my vanity' : 'I own this',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void showProduct(
  BuildContext context,
  Product product,
  EshaController controller,
) {
  if (!controller.hasAppAccess) return;
  final ownerId = controller.session!.userId;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: ivory,
    builder: (context) => EntitledContent(
      controller: controller,
      ownerId: ownerId,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                product.brand.toUpperCase(),
                style: const TextStyle(
                  color: pink,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                product.name,
                style: const TextStyle(fontFamily: 'Georgia', fontSize: 28),
              ),
              const SizedBox(height: 12),
              Text(product.description),
              if (product.shadeNames.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Documented variant: ${product.shadeNames.join(', ')}'),
              ],
              const SizedBox(height: 16),
              Text(
                product.priceLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: pink,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Price snapshot checked ${product.priceCheckedAt}. Product cost only, before tax and shipping. Availability is not live verified.',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
              const SizedBox(height: 14),
              const Text(
                'Choose your shade and check the current ingredient list, package size and stock on the manufacturer’s page. Preferences are not an allergy-safety or exact shade-match guarantee.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => openSource(context, product.sourceUrl),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open manufacturer page'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ProductGrid extends StatelessWidget {
  const ProductGrid({
    super.key,
    required this.products,
    required this.controller,
  });
  final List<Product> products;
  final EshaController controller;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final columns = constraints.maxWidth >= 780
          ? 4
          : constraints.maxWidth >= 540
          ? 3
          : scale > 1.35 || constraints.maxWidth < 280
          ? 1
          : 2;
      final width = (constraints.maxWidth - 14 * (columns - 1)) / columns;
      return Wrap(
        spacing: 14,
        runSpacing: 18,
        children: products
            .map(
              (p) => SizedBox(
                width: width,
                child: ProductCard(product: p, controller: controller),
              ),
            )
            .toList(),
      );
    },
  );
}

class ProductPainter extends CustomPainter {
  ProductPainter(this.category);
  final String category;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2 + 4);
    final shadow = Paint()
      ..color = plum.withValues(alpha: .1)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawOval(const Rect.fromLTWH(-47, 39, 94, 12), shadow);
    final dark = Paint()..color = plum,
        pale = Paint()..color = const Color(0xFFFFFCF5),
        accent = Paint()..color = pink;
    switch (category) {
      case 'Lipstick':
        canvas.rotate(-.16);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-15, 0, 30, 43),
            const Radius.circular(4),
          ),
          dark,
        );
        canvas.drawRect(
          const Rect.fromLTWH(-13, -13, 26, 15),
          Paint()..color = const Color(0xFFC69B74),
        );
        canvas.drawPath(
          Path()
            ..moveTo(-10, -14)
            ..lineTo(-10, -47)
            ..quadraticBezierTo(1, -51, 10, -37)
            ..lineTo(10, -14)
            ..close(),
          accent,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(29, -5, 26, 49),
            const Radius.circular(4),
          ),
          pale,
        );
      case 'Lip gloss':
        canvas.rotate(.12);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-13, -22, 26, 65),
            const Radius.circular(5),
          ),
          Paint()..color = const Color(0xFFC68195),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-13, -46, 26, 26),
            const Radius.circular(3),
          ),
          dark,
        );
        canvas.drawLine(
          const Offset(-6, -14),
          const Offset(-6, 30),
          Paint()
            ..color = Colors.white.withValues(alpha: .5)
            ..strokeWidth = 3,
        );
      case 'Lashes':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-57, -33, 114, 66),
            const Radius.circular(12),
          ),
          pale,
        );
        for (final y in [-11.0, 14.0]) {
          final path = Path()
            ..moveTo(-35, y)
            ..quadraticBezierTo(0, y + 25, 35, y);
          canvas.drawPath(
            path,
            Paint()
              ..color = plum
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
          for (var i = 0; i <= 12; i++) {
            final x = -32 + i * 64 / 12;
            final curve = 11 * (1 - math.pow(x / 35, 2));
            canvas.drawLine(
              Offset(x, y + curve),
              Offset(x * 1.12, y + curve - 10 - 5 * (1 - (x / 35).abs())),
              Paint()
                ..color = plum
                ..strokeWidth = 1.3,
            );
          }
        }
      case 'Body wash':
      case 'Lotion':
        canvas.rotate(-.08);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-25, -29, 50, 77),
            const Radius.circular(12),
          ),
          pale,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-13, -42, 26, 15),
            const Radius.circular(3),
          ),
          dark,
        );
        if (category == 'Lotion') {
          canvas.drawRect(const Rect.fromLTWH(-3, -51, 6, 12), dark);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(-14, -55, 40, 7),
              const Radius.circular(3),
            ),
            dark,
          );
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-17, -3, 34, 27),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xFFDBB9BF),
        );
        canvas.drawLine(
          const Offset(-10, 7),
          const Offset(10, 7),
          Paint()
            ..color = plum.withValues(alpha: .4)
            ..strokeWidth = 2,
        );
      default:
        canvas.rotate(.1);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-23, -23, 46, 69),
            const Radius.circular(7),
          ),
          Paint()..color = const Color(0xFFD8A884),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-21, -46, 42, 26),
            const Radius.circular(4),
          ),
          dark,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-16, -2, 32, 25),
            const Radius.circular(2),
          ),
          pale,
        );
        canvas.drawLine(
          const Offset(-9, 7),
          const Offset(9, 7),
          Paint()
            ..color = pink
            ..strokeWidth = 2,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ProductPainter oldDelegate) =>
      oldDelegate.category != category;
}

const lookColors = [
  Color(0xFFAE526B),
  Color(0xFF73314D),
  Color(0xFFB93348),
  Color(0xFF875043),
];
const lookNames = ['Rosé', 'Berry', 'Cherry', 'Cocoa'];

class LookPainter extends CustomPainter {
  LookPainter(this.look);
  final StudioLook look;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    final scale = math.min(size.width / 280, size.height / 340);
    canvas.scale(scale);
    final hair = Paint()..color = plum;
    canvas.drawOval(const Rect.fromLTWH(-100, -150, 200, 272), hair);
    canvas.drawPath(
      Path()
        ..moveTo(-105, 168)
        ..quadraticBezierTo(-95, 100, -33, 91)
        ..lineTo(-26, 55)
        ..lineTo(27, 55)
        ..lineTo(34, 91)
        ..quadraticBezierTo(95, 100, 106, 168)
        ..close(),
      Paint()..color = const Color(0xFFB87C60),
    );
    canvas.drawOval(
      const Rect.fromLTWH(-75, -125, 150, 224),
      Paint()..color = const Color(0xFFCA9473),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-81, -41)
        ..quadraticBezierTo(-107, -153, -5, -154)
        ..quadraticBezierTo(86, -151, 82, -52)
        ..quadraticBezierTo(20, -77, 13, -115)
        ..quadraticBezierTo(-10, -66, -81, -41)
        ..close(),
      hair,
    );
    final line = Paint()
      ..color = plum
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(-58, -34)
        ..quadraticBezierTo(-38, -47, -19, -34),
      line,
    );
    canvas.drawPath(
      Path()
        ..moveTo(19, -34)
        ..quadraticBezierTo(38, -47, 58, -34),
      line,
    );
    for (final side in [-1, 1]) {
      canvas.save();
      canvas.scale(side.toDouble(), 1);
      canvas.drawPath(
        Path()
          ..moveTo(18, -14)
          ..quadraticBezierTo(39, -2, 60, -14),
        line,
      );
      final count = look.lashes == 'Soft'
          ? 5
          : look.lashes == 'Wispy'
          ? 8
          : 11;
      for (var i = 0; i < count; i++) {
        final x = 24 + i * 32 / (count - 1);
        canvas.drawLine(
          Offset(x, -7),
          Offset(x + 3, -15 - (look.lashes == 'Bold' ? 7 : 3)),
          line..strokeWidth = look.lashes == 'Bold' ? 2.2 : 1.6,
        );
      }
      canvas.restore();
    }
    canvas.drawPath(
      Path()
        ..moveTo(1, -7)
        ..quadraticBezierTo(-7, 19, 2, 25)
        ..lineTo(10, 23),
      Paint()
        ..color = const Color(0xFFAA715B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawOval(
      const Rect.fromLTWH(-60, 10, 35, 17),
      Paint()
        ..color = lookColors[look.shade].withValues(alpha: .15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawOval(
      const Rect.fromLTWH(25, 10, 35, 17),
      Paint()
        ..color = lookColors[look.shade].withValues(alpha: .15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-28, 48)
        ..quadraticBezierTo(-9, 34, 0, 42)
        ..quadraticBezierTo(10, 34, 28, 48)
        ..quadraticBezierTo(0, 77, -28, 48)
        ..close(),
      Paint()..color = lookColors[look.shade],
    );
    canvas.drawPath(
      Path()
        ..moveTo(-25, 49)
        ..quadraticBezierTo(0, 53, 25, 49),
      Paint()
        ..color = plum.withValues(alpha: .5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    if (look.finish == 'Gloss') {
      canvas.drawPath(
        Path()
          ..moveTo(-10, 58)
          ..quadraticBezierTo(1, 61, 10, 57),
        Paint()
          ..color = Colors.white.withValues(alpha: .65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(-105, 169)
        ..quadraticBezierTo(-100, 124, -49, 109)
        ..quadraticBezierTo(0, 137, 49, 109)
        ..quadraticBezierTo(100, 124, 105, 169)
        ..close(),
      Paint()..color = const Color(0xFFE9C9D0),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LookPainter oldDelegate) =>
      oldDelegate.look.shade != look.shade ||
      oldDelegate.look.finish != look.finish ||
      oldDelegate.look.lashes != look.lashes;
}
