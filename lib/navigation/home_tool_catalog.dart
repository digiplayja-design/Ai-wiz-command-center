/// Shared by the home sections and More tools so each feature has one entry.
const homeBusinessTools = <String>[
  'Logo Studio',
  'Inventory Studio',
  'Bookkeeping 2027',
  'KORLIX 2MEETU',
  'FieldProof',
  'SEO Agent',
  'AI Visibility',
  'Contract Radar',
  'Workforce',
  'Business Directory',
  // Keep the entry visible even while the home tier request is loading/fails.
  // CRM verifies Enterprise access on its own authenticated API.
  'Contacts CRM',
];
const homeEnterpriseTools = <String>['Funnel Studio', 'Payroll'];
const homePersonalTools = <String>[
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
