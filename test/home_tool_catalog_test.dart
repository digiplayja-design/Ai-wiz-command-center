import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wiz_command_center/navigation/home_tool_catalog.dart';

void main() {
  for (final enterprise in [false, true]) {
    for (final study in ['Study / learn', 'Estudiar', 'Étudier']) {
      test(
        'More tools preserves unique access: $study, enterprise=$enterprise',
        () {
          final quickActions = [
            study,
            if (study == 'Study / learn') 'Create an App',
          ];
          final extras = moreHomeTools(
            quickActionLabels: quickActions,
            enterprise: enterprise,
          );
          expect(extras, [
            if (study != 'Study / learn') 'App Studio',
            'Voice-scribe',
            'Copy Box',
            'Background remover',
            'Songwriter',
          ]);
          final all = [
            ...homeBusinessTools,
            if (enterprise) ...homeEnterpriseTools,
            ...homePersonalTools,
            'Music Studio',
            ...quickActions,
            ...extras,
          ].map(homeToolIdentity).toList();
          expect(all.toSet().length, all.length);
          expect(all, containsAll(['study studio', 'app studio', 'workforce']));
          expect(all.where((tool) => tool == 'contacts crm').length, 1);
          expect(extras, isNot(contains('Contacts CRM')));
        },
      );
    }
  }
  test(
    'normalization also deduplicates translated and repeated quick actions',
    () {
      expect(
        moreHomeTools(
          quickActionLabels: [
            ' STUDY / LEARN ',
            'Study Studio',
            'Build an App',
            'Copy Box',
          ],
          enterprise: true,
        ),
        ['Voice-scribe', 'Background remover', 'Songwriter'],
      );
    },
  );
}
