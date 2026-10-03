import 'package:flutter/material.dart';

import '../theme/korlix_theme.dart';
import 'social_client.dart';
import 'social_design.dart';

const socialProfileAudiences = {
  'members': 'Public',
  'connections': 'Followers',
  'private': 'Only me',
};

class SocialProfileField {
  const SocialProfileField(
    this.id,
    this.label,
    this.icon,
    this.limit,
    this.section, {
    required this.hint,
    this.defaultAudience = 'members',
  });

  final String id, label, section, hint, defaultAudience;
  final IconData icon;
  final int limit;
}

const socialProfileFields = [
  SocialProfileField(
    'status_caption',
    'Status caption',
    Icons.chat_bubble_outline_rounded,
    160,
    'Your status',
    hint: 'What would you like people to know today?',
  ),
  SocialProfileField(
    'home_country',
    'Home country',
    Icons.public_rounded,
    80,
    'Places & contact',
    hint: 'Where you call home',
  ),
  SocialProfileField(
    'city',
    'City',
    Icons.location_city_rounded,
    100,
    'Places & contact',
    hint: 'Your city or town',
  ),
  SocialProfileField(
    'phone_number',
    'Phone number',
    Icons.phone_outlined,
    40,
    'Places & contact',
    hint: 'Include your country code',
    defaultAudience: 'private',
  ),
  SocialProfileField(
    'profession',
    'Profession',
    Icons.work_outline_rounded,
    100,
    'Work & life',
    hint: 'e.g. Designer, Nurse, Entrepreneur',
  ),
  SocialProfileField(
    'current_job',
    'Current job',
    Icons.business_center_outlined,
    120,
    'Work & life',
    hint: 'Your role or workplace',
  ),
  SocialProfileField(
    'marital_status',
    'Marital status',
    Icons.favorite_border_rounded,
    60,
    'Work & life',
    hint: 'Describe it in your own words',
  ),
  SocialProfileField(
    'income_level',
    'Income level',
    Icons.account_balance_wallet_outlined,
    100,
    'Work & life',
    hint: 'An income range, with currency if useful',
    defaultAudience: 'private',
  ),
  SocialProfileField(
    'favorite_color',
    'Favorite color',
    Icons.palette_outlined,
    60,
    'A few favorites',
    hint: 'The color that feels like you',
  ),
  SocialProfileField(
    'favorite_food',
    'Favorite food',
    Icons.restaurant_rounded,
    100,
    'A few favorites',
    hint: 'Your go-to dish or cuisine',
  ),
];

String socialProfileAudience(SocialMap profile, SocialProfileField field) {
  final value = socialMap(profile['profile_visibility'])[field.id];
  return socialProfileAudiences.containsKey(value)
      ? value as String
      : field.defaultAudience;
}

IconData socialProfileAudienceIcon(String audience) => switch (audience) {
  'connections' => Icons.people_outline_rounded,
  'private' => Icons.lock_outline_rounded,
  _ => Icons.public_rounded,
};

/// Shows only the optional values supplied by the profile API. Other members'
/// responses are filtered by the server according to each field's audience.
class SocialProfileDetails extends StatelessWidget {
  const SocialProfileDetails({
    super.key,
    required this.profile,
    this.owned = false,
  });

  final SocialMap profile;
  final bool owned;

  @override
  Widget build(BuildContext context) {
    final fields = socialProfileFields
        .where((field) => '${profile[field.id] ?? ''}'.trim().isNotEmpty)
        .toList();
    if (fields.isEmpty) return const SizedBox.shrink();
    final sections = fields.map((field) => field.section).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SocialPanel(
              padding: const EdgeInsets.all(18),
              accent: socialColor(
                section == 'Your status'
                    ? 'violet'
                    : section == 'A few favorites'
                    ? 'coral'
                    : 'mint',
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    section == 'Your status' ? 'Status' : section,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  for (final field in fields.where(
                    (field) => field.section == section,
                  )) ...[const SizedBox(height: 16), _detail(context, field)],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _detail(BuildContext context, SocialProfileField field) {
    final skin = korlixSkinOf(context);
    final audience = socialProfileAudience(profile, field);
    return Row(
      key: ValueKey('social-profile-detail-${field.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(field.icon, size: 20, color: skin.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (field.id != 'status_caption') ...[
                Text(
                  field.label,
                  style: TextStyle(
                    color: skin.mutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              SelectableText(
                '${profile[field.id]}',
                style: TextStyle(
                  fontSize: field.id == 'status_caption' ? 17 : 15,
                  height: 1.45,
                  fontWeight: field.id == 'status_caption'
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
              if (owned) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      socialProfileAudienceIcon(audience),
                      color: skin.mutedText,
                      size: 13,
                    ),
                    Text(
                      socialProfileAudiences[audience]!,
                      style: TextStyle(color: skin.mutedText, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
