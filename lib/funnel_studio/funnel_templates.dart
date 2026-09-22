import 'dart:convert';

Map<String, dynamic> funnelTemplate(String layout) => {
  'brand': 'Your business',
  'headline': switch (layout) {
    'product' => 'Find your next great solution.',
    'event' => 'Make room for your next big idea.',
    _ => 'A better next step starts here.',
  },
  'subheadline':
      'Tell visitors what you offer, who it helps, and why they should get in touch.',
  'cta': layout == 'event' ? 'Register interest' : 'Let’s talk',
  'thank_you': 'Thank you for reaching out. Your request has been received.',
  'benefits': [
    'A solution built around your needs',
    'A clear next step',
    'A conversation with our team',
  ],
  'faq': [
    {
      'q': 'What happens next?',
      'a': 'Our team will review your request and get in touch.',
    },
  ],
  'layout': layout,
  'accent': 'cyan',
  'privacy_url': '',
  'booking_url': '',
  'contact_email': '',
};

Map<String, dynamic> copyFunnel(Map source) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(source)) as Map);

String campaignLink(String url, Map<String, String> tags) => Uri.parse(url)
    .replace(
      queryParameters: {
        for (final entry in tags.entries)
          if (entry.value.trim().isNotEmpty)
            'utm_${entry.key}': entry.value.trim(),
      },
    )
    .toString();

Map<String, dynamic> generatedCopy(Map current, Map generated) => {
  ...generated,
  for (final key in ['privacy_url', 'booking_url', 'contact_email'])
    key: current[key] ?? '',
};
