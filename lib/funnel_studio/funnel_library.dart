import 'funnel_templates.dart';

/// Curated starting copy using the existing public page renderer.
/// Presets create private drafts; publication and outreach stay separate.
class FunnelPreset {
  const FunnelPreset(
    this.id,
    this.name,
    this.category,
    this.description,
    this.layout,
    this.accent,
    this.headline,
    this.subheadline,
    this.cta,
    this.benefits,
  );

  final String id, name, category, description, layout, accent;
  final String headline, subheadline, cta;
  final List<String> benefits;

  Map<String, dynamic> document() => {
    ...funnelTemplate(layout),
    'accent': accent,
    'headline': headline,
    'subheadline': subheadline,
    'cta': cta,
    'benefits': [...benefits],
  };
}

const funnelPresets = [
  FunnelPreset(
    'consultation',
    'The first conversation',
    'Services',
    'Invite prospects to discuss their goals and explore your services.',
    'consultation',
    'cyan',
    'Your next chapter starts with a conversation.',
    'Tell us where you want to go and what is standing in your way. Let’s explore how we can help you take the next step.',
    'Let’s talk',
    ['Share your goals', 'Explore your options', 'Find a practical next step'],
  ),
  FunnelPreset(
    'professional',
    'Expertise, introduced',
    'Services',
    'A clear introduction for consultants and professional service teams.',
    'consultation',
    'gold',
    'Bring your challenge. Let’s explore the possibilities.',
    'Looking for a fresh perspective? Share your priorities with our team and ask about the services that fit your needs.',
    'Discuss my project',
    [
      'A conversation about your priorities',
      'Clear information about our services',
      'An approach shaped around your project',
    ],
  ),
  FunnelPreset(
    'home',
    'Your next home project',
    'Services',
    'Collect project inquiries for local and home service businesses.',
    'consultation',
    'cyan',
    'Let’s plan what comes next for your home.',
    'Tell us about your project, location, and preferred timing. We’ll review your request and discuss availability and next steps.',
    'Ask about my project',
    [
      'Describe the work you have in mind',
      'Discuss timing and availability',
      'Ask about an estimate',
    ],
  ),
  FunnelPreset(
    'demo',
    'Show what’s possible',
    'Products',
    'Introduce your product and collect requests for a demonstration.',
    'product',
    'violet',
    'See how a better solution could work for you.',
    'Explore what our product can do for your team. Tell us what you need and request a conversation or demonstration.',
    'Request a demo',
    [
      'Explore the features that matter to you',
      'Discuss your team’s workflow',
      'Ask about plans and availability',
    ],
  ),
  FunnelPreset(
    'vehicle',
    'Find your next drive',
    'Products',
    'Help vehicle shoppers share their preferences with your team.',
    'product',
    'gold',
    'Your next drive starts here.',
    'Tell us about the vehicle you’re looking for, your budget, and the features you need. Ask our team about available options.',
    'Share my preferences',
    [
      'Compare available options',
      'Ask about features and pricing',
      'Discuss a visit with our team',
    ],
  ),
  FunnelPreset(
    'event',
    'Make an impression',
    'Events',
    'Build interest in an upcoming workshop, gathering, or event.',
    'event',
    'violet',
    'Good ideas start when people come together.',
    'Interested in our next event? Share your details to ask about the agenda, dates, availability, and how to participate.',
    'Register interest',
    [
      'Ask about the agenda',
      'Explore participation options',
      'Request event details',
    ],
  ),
  FunnelPreset(
    'coaching',
    'Make your next move',
    'Learning',
    'Invite learners to ask about coaching or a training program.',
    'consultation',
    'violet',
    'A new goal deserves a thoughtful next step.',
    'Tell us what you want to learn or improve. We’ll discuss our programs and help you explore whether there’s a fit.',
    'Explore a program',
    [
      'Share your learning goals',
      'Ask about the program format',
      'Discuss schedules and next steps',
    ],
  ),
  FunnelPreset(
    'resource',
    'Start with insight',
    'Learning',
    'Collect inquiries about a guide, resource, or learning material.',
    'product',
    'cyan',
    'Looking for a clearer way forward?',
    'Ask our team about the resources available for your goals. Share what you’re working on so we can point you toward a useful next step.',
    'Ask about resources',
    [
      'Tell us what you’re exploring',
      'Ask about available materials',
      'Connect with our team',
    ],
  ),
];

String funnelSlugSuggestion(String name) {
  var value = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  value = value.replaceAll(RegExp(r'^-+|-+$'), '');
  if (value.length > 60) {
    value = value.substring(0, 60).replaceAll(RegExp(r'-+$'), '');
  }
  return value;
}

/// Deliberately copies page content only. No campaign, lead, or workflow state.
Map<String, dynamic> funnelCreatePayload(
  String name,
  String slug,
  Map document,
) => {
  'name': name.trim(),
  'slug': slug.trim(),
  'document': copyFunnel({
    for (final key in funnelTemplate('consultation').keys)
      if (document.containsKey(key)) key: document[key],
  }),
};

bool funnelHttpsAddress(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.host.isEmpty ||
      !uri.host.contains('.')) {
    return false;
  }
  final host = uri.host.toLowerCase();
  return host != 'localhost' &&
      !host.startsWith('127.') &&
      !host.startsWith('0.') &&
      !host.startsWith('169.254.');
}

bool funnelContactEmail(String value) =>
    RegExp(r'^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$').hasMatch(value.trim());
