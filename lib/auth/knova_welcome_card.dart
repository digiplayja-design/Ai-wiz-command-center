import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/korlix_theme.dart';
import 'knova_welcome_controller.dart';

class KnovaWelcomeCard extends StatelessWidget {
  const KnovaWelcomeCard({super.key, required this.controller});
  final KnovaWelcomeController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (!controller.visible) return const SizedBox.shrink();
      final skin = korlixSkinOf(context);
      final status = switch (controller.state) {
        KnovaWelcomeState.loading => 'Getting your welcome ready…',
        KnovaWelcomeState.speaking => 'K-Nova is speaking',
        KnovaWelcomeState.blocked => 'Tap Listen to hear K-Nova.',
        KnovaWelcomeState.unavailable =>
          'Voice is unavailable right now. You can still explore.',
        KnovaWelcomeState.muted =>
          'Welcome audio is muted by your sound settings.',
        KnovaWelcomeState.ready => 'Your voice companion, across KORLIX.',
      };
      return Material(
        key: const Key('knova-signin-welcome'),
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 550,
            maxHeight: MediaQuery.sizeOf(context).height * .64,
          ),
          child: Ink(
            decoration: BoxDecoration(
              color: skin.panelDeep,
              gradient: LinearGradient(
                colors: [
                  Color.alphaBlend(
                    skin.primary.withValues(alpha: .17),
                    skin.panelDeep,
                  ),
                  skin.panelDeep,
                ],
              ),
              border: Border.all(color: skin.primary.withValues(alpha: .55)),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .3),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.graphic_eq_rounded,
                        color: skin.primary,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome to KORLIX',
                              style: TextStyle(
                                color: skin.text,
                                fontWeight: FontWeight.w800,
                                fontSize: 22,
                              ),
                            ),
                            Text(
                              'K-Nova · AI voice companion',
                              style: TextStyle(
                                color: skin.primary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const Key('knova-welcome-close'),
                        tooltip: 'Dismiss welcome',
                        onPressed: controller.dismiss,
                        icon: Icon(Icons.close, color: skin.mutedText),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    knovaWelcomeText,
                    style: TextStyle(
                      color: skin.text,
                      height: 1.5,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    status,
                    style: TextStyle(color: skin.primary, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const Key('knova-welcome-listen'),
                        onPressed: controller.active
                            ? controller.stop
                            : () => unawaited(controller.listen()),
                        icon: Icon(
                          controller.active
                              ? Icons.stop_rounded
                              : Icons.volume_up_rounded,
                        ),
                        label: Text(
                          controller.active
                              ? 'Stop'
                              : controller.state == KnovaWelcomeState.ready
                              ? 'Replay'
                              : 'Listen',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: controller.dismiss,
                        child: const Text("Let's explore"),
                      ),
                    ],
                  ),
                  SwitchListTile.adaptive(
                    key: const Key('knova-welcome-preference'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Play when I sign in',
                      style: TextStyle(color: skin.mutedText, fontSize: 13),
                    ),
                    value: controller.sounds.settings.welcomeVoice,
                    onChanged: (value) => unawaited(
                      controller.sounds.update(
                        controller.sounds.settings.copyWith(
                          welcomeVoice: value,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
