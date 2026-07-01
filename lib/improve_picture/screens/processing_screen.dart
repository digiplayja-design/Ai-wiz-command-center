import 'package:flutter/material.dart';

import '../controllers/portrait_studio_controller.dart';
import '../controllers/portrait_studio_controller.dart';
import '../models/template_model.dart';
import 'result_screen.dart';

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({
    super.key,
    required this.gender,
    required this.template,
    required this.variation,
    required this.strength,
    required this.ratio,
    required this.hasUploadedPhoto,
  });

  final ImproveGender gender;
  final ImproveTemplate template;
  final String variation;
  final double strength;
  final String ratio;
  final bool hasUploadedPhoto;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  final PortraitStudioController _controller = PortraitStudioController();
  @override
  void initState() {
    super.initState();
    final prompt = _controller.buildGenerationPrompt(
      gender: widget.gender,
      template: widget.template,
      variation: widget.variation,
      strength: widget.strength,
      ratio: widget.ratio,
    );
    debugPrint('Portrait Studio prompt ready: $prompt');
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            gender: widget.gender,
            template: widget.template,
            variation: widget.variation,
            strength: widget.strength,
            ratio: widget.ratio,
            hasUploadedPhoto: widget.hasUploadedPhoto,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  height: 120,
                  width: 120,
                  child: CircularProgressIndicator(
                    strokeWidth: 8,
                    color: Color(0xFFB266FF),
                    backgroundColor: Color(0xFF171B29),
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  'Enhancing your portrait...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${widget.template.name} • ${widget.variation}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFC07CFF),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Preserving identity while applying the selected look.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.62),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
