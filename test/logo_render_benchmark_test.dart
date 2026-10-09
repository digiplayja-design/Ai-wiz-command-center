import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_model.dart';
import 'package:ai_wiz_command_center/logo_studio/logo_render.dart';

// Diagnostic benchmark; durations are reported, never used as flaky CI gates.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('repeated logo preview rendering benchmark', () async {
    await ensureLogoFonts();
    final composition = LogoComposition(
      const LogoDesign(
        name: 'NORTH & PINE CREATIVE COMPANY',
        tagline: 'THOUGHTFUL DESIGN FOR EVERY DAY',
        tracking: 4,
        mark: 'Leaf',
      ),
    );
    void frame() {
      final recorder = ui.PictureRecorder();
      composition.paintFitted(ui.Canvas(recorder), const ui.Size(540, 360));
      recorder.endRecording().dispose();
    }

    for (var i = 0; i < 10; i++) {
      frame();
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < 300; i++) {
      frame();
    }
    watch.stop();
    // ignore: avoid_print
    print('LOGO_RENDER_300_FRAMES_MS=${watch.elapsedMilliseconds}');
  });
}
