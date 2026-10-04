import 'dart:async';
import 'package:flutter/material.dart';
import 'knova_welcome_controller.dart';

/// Audio stays in the existing toolbar; signing in never opens a welcome panel.
class RiciWelcomeButton extends StatelessWidget {
  const RiciWelcomeButton({super.key, required this.controller});
  final KnovaWelcomeController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (!controller.visible) return const SizedBox.shrink();
      final active = controller.active;
      return IconButton(
        key: const Key('rici-welcome-audio'),
        tooltip: active ? 'Stop Rici’s welcome' : 'Listen to Rici’s welcome',
        onPressed: active
            ? controller.stop
            : () => unawaited(controller.listen()),
        icon: Icon(
          active ? Icons.stop_circle_outlined : Icons.volume_up_rounded,
          color: const Color(0xFFE4EBEE),
        ),
      );
    },
  );
}
