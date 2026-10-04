import 'package:flutter/material.dart';

import 'music_models.dart';
import 'music_voice.dart';

class MusicVoicePanel extends StatelessWidget {
  const MusicVoicePanel({
    super.key,
    required this.controller,
    required this.onReview,
    required this.onListen,
    required this.onDismiss,
  });

  final MusicVoiceController controller;
  final Future<void> Function()? onReview, onListen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (!controller.available) return const SizedBox.shrink();
      final data = controller.context, result = controller.result;
      final draft = controller.pendingDraft,
          playback = controller.pendingPlayback;
      final recipe = draft ?? (data['working_draft'] as Map?);
      final addon = data['addon'] as Map?;
      final usage = addon?['usage'] as Map?;
      final jobs = result['jobs'] is List
          ? result['jobs'] as List
          : result['job'] is Map
          ? [result['job']]
          : data['jobs'] is List
          ? data['jobs'] as List
          : <dynamic>[];
      final hasMore = result['jobs'] is List
          ? result['has_more'] == true
          : data['has_more'] == true;
      final colors = Theme.of(context).colorScheme;
      final text = Theme.of(context).textTheme;

      Widget field(String name, String value) => Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Text('$name: ${value.isEmpty ? 'Not set' : value}'),
      );
      Widget pill(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colors.onSecondaryContainer),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: colors.onSecondaryContainer)),
          ],
        ),
      );

      return Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 740),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.surfaceContainerHigh, colors.surfaceContainer],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.headphones_rounded,
                        color: colors.onPrimaryContainer,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rici · Your music producer',
                            style: text.titleMedium,
                          ),
                          const SizedBox(height: 3),
                          Text('KORLIX Music Studio', style: text.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Describe your sound, develop a chorus, or find a track in your library.',
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    pill(Icons.mic_none_rounded, 'Talk to create your idea'),
                    pill(Icons.headphones_outlined, 'Listen in Studio'),
                  ],
                ),
                if (usage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${usage['remainingThisCycle']} creations remaining · ${usage['cycle']}',
                  ),
                  if (addon?['active'] != true)
                    const Text(
                      'Music Production add-on required to generate audio. You can still develop a music idea.',
                    ),
                  if (addon?['active'] == true &&
                      addon?['providerReady'] != true)
                    const Text(
                      'Music generation is temporarily unavailable. You can still work on your idea.',
                    ),
                ],
                if (controller.busy) ...[
                  const SizedBox(height: 14),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 7),
                  const Text('Checking your studio…'),
                ],
                if (result['success'] == false &&
                    result['message'] is String) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      result['message'] as String,
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                ],
                if (recipe != null) ...[
                  const Divider(height: 28),
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        color: colors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          draft != null
                              ? 'Your next version'
                              : 'Current music idea',
                          style: text.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Unsaved idea · No music generated',
                    style: text.bodySmall,
                  ),
                  field('Title', '${recipe['title']}'),
                  field('Create', switch (recipe['mode']) {
                    'lyrics' => 'Song from your lyrics',
                    'instrumental' => 'Instrumental',
                    _ => 'Song from an idea',
                  }),
                  field('Idea', '${recipe['idea']}'),
                  field('Style', '${recipe['style']}'),
                  field('Voice preference', switch (recipe['voice']) {
                    'm' => 'Male',
                    'f' => 'Female',
                    _ => 'Automatic',
                  }),
                  field(
                    'Target length',
                    recipe['duration'] == null
                        ? 'No target set'
                        : '${recipe['duration']} seconds',
                  ),
                  if (recipe['lyrics'] != '') ...[
                    const SizedBox(height: 12),
                    Text('Lyrics', style: text.titleSmall),
                    const SizedBox(height: 7),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 240),
                        child: SingleChildScrollView(
                          child: SelectableText('${recipe['lyrics']}'),
                        ),
                      ),
                    ),
                  ],
                  if (draft != null) ...[
                    const SizedBox(height: 12),
                    if (controller.pendingValidationMessage != null)
                      Text(
                        controller.pendingValidationMessage!,
                        style: TextStyle(color: colors.error),
                      ),
                    const SizedBox(height: 6),
                    const Text(
                      'Review in Studio pauses voice and opens this editable idea. Creating music requires your confirmation and uses 1 Music Production creation.',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('music-voice-review'),
                          onPressed: controller.busy ? null : onReview,
                          icon: const Icon(Icons.tune_rounded),
                          label: const Text('Review in Studio'),
                        ),
                        TextButton(
                          onPressed: controller.busy ? null : onDismiss,
                          child: const Text('Dismiss idea'),
                        ),
                      ],
                    ),
                  ],
                ],
                if (playback != null) ...[
                  const Divider(height: 28),
                  Text('Ready for a listen', style: text.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    '${playback['title']} · Version ${(playback['track_index'] as int) + 1}',
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Voice and microphone pause before playback. Return to Talk to Rici when you want to discuss another version.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('music-voice-listen'),
                        onPressed: controller.busy ? null : onListen,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Listen in Studio'),
                      ),
                      TextButton(
                        onPressed: controller.busy ? null : onDismiss,
                        child: const Text('Dismiss selection'),
                      ),
                    ],
                  ),
                ],
                if (jobs.isNotEmpty) ...[
                  const Divider(height: 28),
                  Text(
                    result['kind'] == 'search'
                        ? 'Found in your library'
                        : 'Your creations',
                    style: text.titleMedium,
                  ),
                  for (final row in jobs.take(6)) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row['title'] == ''
                                ? 'Untitled creation'
                                : '${row['title']}',
                            style: text.titleSmall,
                          ),
                          Text(
                            musicStatuses[row['status']] ?? '${row['status']}',
                          ),
                          for (final track in row['tracks'] as List)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Version ${(track['track_index'] as int) + 1}: ${track['title']} · '
                                '${track['playable'] == true ? 'Ready to listen' : track['state']}',
                              ),
                            ),
                          if (row['refresh_error'] is String)
                            Text(row['refresh_error'] as String),
                          if (row['error'] is String)
                            Text(row['error'] as String),
                        ],
                      ),
                    ),
                  ],
                  if (hasMore || jobs.length > 6) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'More creations are available. Ask for a more specific search or open My tracks.',
                    ),
                  ],
                ],
                if (result['kind'] == 'search' && jobs.isEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('No saved creations matched that search.'),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
