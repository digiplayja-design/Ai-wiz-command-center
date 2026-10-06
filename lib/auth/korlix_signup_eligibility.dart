import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/korlix_theme.dart';

const korlixSignupPolicyVersion = '2026-10-06';

enum KorlixSignupAgeBand {
  under16('under_16', 'Under 16'),
  teen('16_17', '16–17'),
  adult('18_plus', '18 or older');

  const KorlixSignupAgeBand(this.value, this.label);
  final String value;
  final String label;
}

String? korlixSignupEligibilityError({
  required KorlixSignupAgeBand? ageBand,
  required bool acceptedPolicies,
  required bool parentPermission,
}) {
  if (ageBand == null) return 'Select your age range to continue.';
  if (ageBand == KorlixSignupAgeBand.under16) {
    return 'You must be at least 16 to create a KORLIX account.';
  }
  if (ageBand == KorlixSignupAgeBand.teen && !parentPermission) {
    return 'Users aged 16–17 need permission from a parent or guardian.';
  }
  if (!acceptedPolicies) {
    return 'Please agree to the Terms of Use and acknowledge the Privacy Policy.';
  }
  return null;
}

Uri korlixSignupPolicyUri(String file, {Uri? webBase, bool? isWeb}) {
  if (isWeb ?? kIsWeb) {
    final base = webBase ?? Uri.base;
    return base.resolve('/$file');
  }
  return Uri.https('www.korlixdeveloper.com', '/$file');
}

class KorlixAgeNotice extends StatelessWidget {
  const KorlixAgeNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: skin.primary.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: skin.primary.withValues(alpha: .24)),
      ),
      child: Text(
        '16+ · KORLIX is for users aged 16 and older.',
        key: const Key('auth-age-notice'),
        textAlign: TextAlign.center,
        style: TextStyle(color: skin.text, fontSize: 13, height: 1.4),
      ),
    );
  }
}

class KorlixSignupAgeField extends StatelessWidget {
  const KorlixSignupAgeField({
    super.key,
    required this.ageBand,
    required this.onChanged,
    required this.enabled,
  });

  final KorlixSignupAgeBand? ageBand;
  final ValueChanged<KorlixSignupAgeBand?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<KorlixSignupAgeBand>(
          key: const Key('signup-age-range'),
          initialValue: ageBand,
          isExpanded: true,
          dropdownColor: skin.panel,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: skin.text,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            labelText: 'Your age range',
            helperText: 'No date of birth or ID needed for this step.',
            helperMaxLines: 3,
            labelStyle: TextStyle(color: skin.mutedText),
            helperStyle: TextStyle(color: skin.mutedText, height: 1.35),
            filled: true,
            fillColor: skin.inputFill,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          hint: const Text('Select your age range'),
          items: [
            for (final band in KorlixSignupAgeBand.values)
              DropdownMenuItem(value: band, child: Text(band.label)),
          ],
          onChanged: enabled ? onChanged : null,
        ),
        if (ageBand == KorlixSignupAgeBand.under16)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Semantics(
              liveRegion: true,
              child: Text(
                'You must be at least 16 to create a KORLIX account.',
                key: const Key('signup-underage-message'),
                style: TextStyle(color: skin.text, height: 1.4),
              ),
            ),
          ),
      ],
    );
  }
}

class KorlixSignupAcknowledgments extends StatelessWidget {
  const KorlixSignupAcknowledgments({
    super.key,
    required this.ageBand,
    required this.acceptedPolicies,
    required this.parentPermission,
    required this.onPoliciesChanged,
    required this.onParentPermissionChanged,
    required this.enabled,
  });

  final KorlixSignupAgeBand? ageBand;
  final bool acceptedPolicies;
  final bool parentPermission;
  final ValueChanged<bool> onPoliciesChanged;
  final ValueChanged<bool> onParentPermissionChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final canAcknowledge = enabled && ageBand != KorlixSignupAgeBand.under16;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ageBand == KorlixSignupAgeBand.teen) ...[
          Text(
            'Review these policies with your parent or guardian.',
            style: TextStyle(color: skin.mutedText, fontSize: 13, height: 1.4),
          ),
          CheckboxListTile(
            key: const Key('signup-parent-permission'),
            value: parentPermission,
            onChanged: canAcknowledge
                ? (value) => onParentPermissionChanged(value ?? false)
                : null,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              'I have permission from a parent or guardian to use KORLIX.',
              style: TextStyle(color: skin.text, fontSize: 14, height: 1.4),
            ),
          ),
        ],
        CheckboxListTile(
          key: const Key('signup-policy-acceptance'),
          value: acceptedPolicies,
          onChanged: canAcknowledge
              ? (value) => onPoliciesChanged(value ?? false)
              : null,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            'I agree to the Terms of Use and acknowledge the Privacy Policy.',
            style: TextStyle(color: skin.text, fontSize: 14, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class KorlixSignupPolicyLinks extends StatelessWidget {
  const KorlixSignupPolicyLinks({super.key, this.openPolicy});

  final Future<bool> Function(Uri)? openPolicy;

  Future<void> _open(BuildContext context, String file) async {
    final uri = korlixSignupPolicyUri(file);
    var opened = false;
    try {
      opened =
          await (openPolicy?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
    } catch (_) {
      // Keep the form intact and give the user the actual policy address.
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open this policy. Visit $uri')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      children: [
        TextButton(
          key: const Key('auth-terms-link'),
          onPressed: () => _open(context, 'terms.html'),
          child: const Text('Terms of Use'),
        ),
        TextButton(
          key: const Key('auth-privacy-link'),
          onPressed: () => _open(context, 'privacy-policy.html'),
          child: const Text('Privacy Policy'),
        ),
      ],
    );
  }
}
