import 'package:flutter/material.dart';
import '../theme/korlix_action_button.dart';
import '../theme/korlix_theme.dart';

class KorlixWelcomeConfirmation extends StatelessWidget {
  const KorlixWelcomeConfirmation({
    super.key,
    required this.email,
    required this.onSignIn,
    required this.onChangeEmail,
  });
  final String email;
  final VoidCallback onSignIn, onChangeEmail;
  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final stepSize =
        28 * (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 3.0);
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [skin.panelSoft, skin.panelDeep],
                ),
                border: Border.all(color: skin.primary.withValues(alpha: .5)),
                boxShadow: [
                  BoxShadow(
                    color: skin.primary.withValues(alpha: .14),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Image.asset('assets/branding/korlix_mini_mark.png'),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Welcome to KORLIX AI',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: skin.text,
              fontSize: 28,
              height: 1.15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'One last step: confirm your email.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: skin.primary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: skin.panelSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.mark_email_unread_outlined,
                  color: skin.primary,
                  size: 28,
                ),
                const SizedBox(height: 9),
                SelectableText(
                  email,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: skin.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          for (final step in const [
            ('1', 'Open your inbox', 'Use the email address shown above.'),
            (
              '2',
              'Look for Supabase',
              'Find the confirmation email from Supabase, the service KORLIX uses for sign-in.',
            ),
            (
              '3',
              'Confirm, then sign in',
              'Tap the confirmation link in that email. You must confirm your email address before you can log in.',
            ),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: stepSize,
                    height: stepSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: skin.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      step.$1,
                      style: TextStyle(
                        color: skin.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.$2,
                          style: TextStyle(
                            color: skin.text,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          step.$3,
                          style: TextStyle(
                            color: skin.mutedText,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Text(
            'Not seeing it? Check Spam or Junk and search your inbox for “Supabase”. Email delivery may take a few minutes.',
            style: TextStyle(color: skin.mutedText, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 22),
          KorlixActionButton(
            label: 'Back to sign in',
            icon: Icons.login_rounded,
            onPressed: onSignIn,
            expand: true,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onChangeEmail,
            child: const Text('Use a different email address'),
          ),
        ],
      ),
    );
  }
}
