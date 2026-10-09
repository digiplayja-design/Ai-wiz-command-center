import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'logo_font_catalog.dart';

// Fetch and register only fonts that are actually shown. Each family has one
// in-flight load; failures are evicted so a retry can recover from offline use.
final _loading = <String, Future<void>>{};
final _ready = <String>{};
bool logoFontReady(String face) => _ready.contains(logoFontFamily(face));
Future<void> _loadFont(String face) {
  final family = logoFontFamily(face);
  if (_ready.contains(family)) return Future.value();
  return _loading.putIfAbsent(family, () async {
    try {
      final loader = FontLoader(family);
      if (isClassicLogoFont(face)) {
        loader.addFont(rootBundle.load('assets/fieldproof/Roboto-Regular.ttf'));
        loader.addFont(rootBundle.load('assets/fieldproof/Roboto-Bold.ttf'));
      } else {
        loader.addFont(rootBundle.load(logoFontFor(face).asset));
      }
      await loader.load();
      _ready.add(family);
    } catch (_) {
      _loading.remove(family);
      rethrow;
    }
  });
}

Future<void> ensureLogoFonts([String face = 'Clean']) async {
  await Future.wait([
    _loadFont('Clean'),
    if (!isClassicLogoFont(face)) _loadFont(face),
  ]);
}

/// Wait for the real font before measuring or painting any lettering. A failed
/// asset request must not silently produce a logo with substituted typography.
class LogoFontReady extends StatefulWidget {
  const LogoFontReady({super.key, required this.face, required this.builder});
  final String face;
  final WidgetBuilder builder;
  @override
  State<LogoFontReady> createState() => _LogoFontReadyState();
}

class _LogoFontReadyState extends State<LogoFontReady> {
  late Future<void> _future;
  void _load() => _future = ensureLogoFonts(widget.face);
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LogoFontReady oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.face != oldWidget.face) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (logoFontReady(widget.face) && logoFontReady('Clean')) {
      return widget.builder(context);
    }
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return widget.builder(context);
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton.icon(
              onPressed: () => setState(_load),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry font'),
            ),
          );
        }
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text('Loading font…', style: TextStyle(fontSize: 12)),
          ),
        );
      },
    );
  }
}
