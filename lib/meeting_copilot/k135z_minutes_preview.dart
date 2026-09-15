import 'k135z_copilot_contract.dart';

abstract final class K135zMinutesProjector {
  static K135zMinutesPreview project({
    required K135zNotesResult notes,
    required K135zMeetingMetadata metadata,
  }) {
    if (notes.context != metadata.context) {
      return K135zMinutesPreview(
        ok: false,
        title: 'Meeting minutes — unavailable',
        coverageNotice: 'The meeting metadata belongs to another context.',
        sections: const <K135zMinutesSection>[],
        plainText: '',
        errorCode: 'K135Z_MINUTES_CONTEXT_MISMATCH',
      );
    }
    if (notes.status != K135zNotesStatus.ready &&
        notes.status != K135zNotesStatus.empty) {
      return K135zMinutesPreview(
        ok: false,
        title: 'Meeting minutes — unavailable',
        coverageNotice: notes.message ?? 'Validated notes are not ready.',
        sections: const <K135zMinutesSection>[],
        plainText: '',
        errorCode: 'K135Z_MINUTES_NOT_READY',
      );
    }

    final String cleanTitle = metadata.title?.trim() ?? '';
    final String title = cleanTitle.isEmpty
        ? 'Meeting minutes — draft'
        : '$cleanTitle — draft minutes';
    final String coverage = switch (notes.freshness) {
      K135zFreshness.current => 'Validated against the current source window.',
      K135zFreshness.notReflected =>
        'New transcript content exists outside this notes window.',
      K135zFreshness.invalidated =>
        'The source changed; these minutes require regeneration.',
    };
    final List<K135zMinutesSection> sections = <K135zMinutesSection>[
      for (final K135zInsightCategory category in K135zInsightCategory.values)
        K135zMinutesSection(
          category: category,
          items: notes.category(category),
        ),
    ];
    final StringBuffer text = StringBuffer()
      ..writeln(title)
      ..writeln(coverage);
    if (metadata.participants.isNotEmpty) {
      text.writeln(
        'Participants${metadata.participantsComplete ? '' : ' (partial)'}: '
        '${metadata.participants.join(', ')}',
      );
    }
    if (metadata.timezone?.trim().isNotEmpty == true) {
      text.writeln('Timezone: ${metadata.timezone!.trim()}');
    }
    for (final K135zMinutesSection section in sections) {
      text.writeln();
      text.writeln(section.category.label);
      if (section.items.isEmpty) {
        text.writeln('No validated items.');
        continue;
      }
      for (final K135zInsight insight in section.items) {
        final String owner = insight.owner == null ? '' : ' — ${insight.owner}';
        final String deadline = insight.deadlineText == null
            ? ''
            : ' — ${insight.deadlineText}';
        text.writeln('• ${insight.title}: ${insight.detail}$owner$deadline');
      }
    }
    return K135zMinutesPreview(
      ok: true,
      title: title,
      coverageNotice: coverage,
      sections: sections,
      plainText: text.toString().trimRight(),
    );
  }
}
