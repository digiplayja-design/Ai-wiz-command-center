import 'package:flutter/material.dart';

import '../sounds/korlix_sound_actions.dart';
import '../theme/korlix_theme.dart';
import 'korlix_entry_intro.dart';

/// A preview of the product, not an unauthenticated generation surface.
class KorlixEntryWelcome extends StatelessWidget {
  const KorlixEntryWelcome({
    super.key,
    required this.onCreateAccount,
    required this.onSignIn,
    this.showBranding = true,
  });

  final VoidCallback onCreateAccount;
  final VoidCallback onSignIn;
  final bool showBranding;

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBranding) ...[
        Image.asset('assets/branding/korlix_mini_mark.png', height: 58),
        const SizedBox(height: 12),
        Text(
          'KORLIX AI',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: skin.text,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 28),
        ],
        Text(
          'Turn your ideas into useful work.',
          style: TextStyle(
            color: skin.text,
            fontSize: 30,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Create for yourself. Build more for your business.',
          style: TextStyle(color: skin.mutedText, fontSize: 16, height: 1.5),
        ),
        const SizedBox(height: 10),
        const KorlixEntryIntro(),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: skin.panelSoft,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: skin.primary.withValues(alpha: .35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EXAMPLE',
                style: TextStyle(
                  color: skin.mutedText,
                  fontSize: 11,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.mail_outline_rounded, color: skin.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'A better business email',
                      style: TextStyle(
                        color: skin.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Hi Jordan,\nThanks for your time today.\nHere are the next steps we discussed.',
                style: TextStyle(color: skin.text, fontSize: 14, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Start with the free Basic plan.',
          textAlign: TextAlign.center,
          style: TextStyle(color: skin.mutedText, height: 1.4),
        ),
        const SizedBox(height: 14),
        FilledButton(
          key: const Key('welcome-create-account'),
          onPressed: korlixSoundAction(onCreateAccount),
          style: korlixSoundButtonStyle(
            FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              backgroundColor: skin.primary,
              foregroundColor: skin.textOnAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          child: const Text(
            'Create free account',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'No card required.',
          textAlign: TextAlign.center,
          style: TextStyle(color: skin.mutedText, fontSize: 13),
        ),
        const SizedBox(height: 14),
        TextButton(
          key: const Key('welcome-sign-in'),
          onPressed: korlixSoundAction(onSignIn),
          child: const Text(
            'Already registered? Sign in',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
