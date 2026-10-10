/// Shared by the home sections and More tools so each feature has one entry.
const homeBusinessTools = <String>[
  // Keep CRM first and visible independently of the home tier request.
  'Contacts CRM',
  'Logo Studio',
  'KORLIX 2MEETU',
  'SEO Agent',
  'AI Visibility',
  'Contract Radar',
  'Workforce',
  'Business Directory',
];
const homeEnterpriseTools = <String>[
  'FieldProof',
  'Inventory Studio',
  'Bookkeeping 2027',
  'Funnel Studio',
  'Payroll',
];
const homePersonalTools = <String>[
  'THE RECEIPT WIZ',
  'Live Studio',
  'The Pod and You',
  'Tax Prep',
  'BabyBlend',
  'Virtual Closet',
  'Cybersecurity Defender',
];
const _activeTools = <String>[
  ...homeBusinessTools,
  ...homeEnterpriseTools,
  ...homePersonalTools,
  'Study Studio',
  'App Studio',
  'Music Studio',
  'Voice-scribe',
  'Copy Box',
  'Background remover',
  'Songwriter',
];

String homeToolIdentity(String label) => switch (label.trim().toLowerCase()) {
  'study / learn' || 'estudiar' || 'étudier' => 'study studio',
  'create an app' || 'build an app' => 'app studio',
  final name => name,
};

List<String> moreHomeTools({
  required Iterable<String> quickActionLabels,
  required bool enterprise,
}) {
  final mainTools = {
    ...homeBusinessTools.map(homeToolIdentity),
    ...homePersonalTools.map(homeToolIdentity),
    if (enterprise) ...homeEnterpriseTools.map(homeToolIdentity),
    // Music Studio has its own tile in the personal section in every language.
    'music studio',
    ...quickActionLabels.map(homeToolIdentity),
  };
  return _activeTools
      .where((tool) {
        if (!enterprise && homeEnterpriseTools.contains(tool)) return false;
        return !mainTools.contains(homeToolIdentity(tool));
      })
      .toList(growable: false);
}

class HomeToolEntry {
  const HomeToolEntry(
    this.label,
    this.description,
    this.group, [
    this.keywords = '',
  ]);
  final String label, description, group, keywords;
  String get identity => homeToolIdentity(label);
  bool matches(String query) {
    final haystack = '$label $description $group $keywords'.toLowerCase();
    return query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .every(haystack.contains);
  }
}

const _toolDetails = <String, String>{
  'Contacts CRM': 'Contacts, leads, follow-ups and autonomous email',
  'Workforce': 'Team tasks, work updates and email reminders',
  'Business Directory': 'Find business listings and build connections',
  'KORLIX Social': 'News, user videos, people and messages',
  'Live Convo': 'Talk with Rici in a live conversation',
  'Upload': 'Bring files and photos into your conversation',
  'Voice': 'Speak or type a message to Rici',
  'Camera Ask': 'Take a photo and ask about what you see',
  'Locator': 'Find places nearby',
  'Logo Studio': 'Design a logo for your brand',
  'Inventory Studio': 'Track stock, products and inventory · Enterprise',
  'Bookkeeping 2027': 'Organize your business finances · Enterprise',
  'KORLIX 2MEETU': 'Free scheduling for meetings and appointments',
  'FieldProof': 'Document jobs and field work · Enterprise',
  'SEO Agent': 'Improve how your website is found',
  'AI Visibility': 'Check your presence in AI answers',
  'Contract Radar': 'Find and track contract opportunities',
  'Funnel Studio': 'Build business funnels · Enterprise',
  'Payroll': 'Manage payroll · Enterprise',
  'Live Studio': 'Create a live session',
  'The Pod and You': 'Create a podcast with AI',
  'Tax Prep': 'Organize tax preparation',
  'THE RECEIPT WIZ': 'Free receipt scanner, automatic categories and connected finance inboxes',
  'BabyBlend': 'Explore family photo blends',
  'Virtual Closet': 'Organize outfits and style ideas',
  'Cybersecurity Defender': 'Review digital security',
  'Study Studio': 'Learn a topic and build study guides',
  'App Studio': 'Turn an app idea into a project',
  'Music Studio': 'Create music and explore song ideas',
  'Voice-scribe': 'Transcribe and work with spoken content',
  'Copy Box': 'Write and refine your copy',
  'Background remover': 'Remove the background from a photo',
  'Songwriter': 'Start writing a song',
  'Email enhancer': 'Draft and improve an email',
};

/// The finder uses the same active catalog and real quick actions as home.
/// It never adds inactive utilities or duplicate translated aliases.
List<HomeToolEntry> searchableHomeTools({
  required Iterable<String> quickActionLabels,
  required bool enterprise,
}) {
  final entries = <String, HomeToolEntry>{};
  void add(String label, String group) {
    final identity = homeToolIdentity(label);
    if (!enterprise &&
        homeEnterpriseTools.any((tool) => homeToolIdentity(tool) == identity)) {
      return;
    }
    entries.putIfAbsent(
      identity,
      () => HomeToolEntry(
        label,
        _toolDetails[label] ??
            (group == 'Quick actions'
                ? 'Start this task with Rici'
                : 'Open $label'),
        group,
        identity == 'contacts crm'
            ? 'customers clients contacts crm import auto pull directory rici'
            : '',
      ),
    );
  }

  for (final tool in ['Live Convo', 'Upload', 'Voice', 'Camera Ask']) {
    add(tool, 'Start here');
  }
  add('KORLIX Social', 'Personal');
  for (final tool in homeBusinessTools) {
    add(tool, 'Business');
  }
  if (enterprise) {
    for (final tool in homeEnterpriseTools) {
      add(tool, 'Business');
    }
  }
  for (final tool in homePersonalTools) {
    add(tool, 'Personal');
  }
  add('Locator', 'Personal');
  for (final tool in _activeTools) {
    if (!enterprise && homeEnterpriseTools.contains(tool)) continue;
    add(tool, 'Create & learn');
  }
  for (final tool in quickActionLabels) {
    add(tool, 'Quick actions');
  }
  return entries.values.toList(growable: false);
}
