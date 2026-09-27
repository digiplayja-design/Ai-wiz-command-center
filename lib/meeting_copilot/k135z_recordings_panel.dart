import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'k135z_recordings_controller.dart';
import 'k135z_recording_audio.dart';

class K135zRecordingsPanel extends StatelessWidget {
  const K135zRecordingsPanel({
    super.key,
    required this.controller,
    required this.beforePlayback,
  });
  final K135zRecordingsController controller;
  final VoidCallback beforePlayback;
  static const muted = Color(0xFF9CB8CA);
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final c = controller;
      return Material(
        color: const Color(0xFF0A223A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF1A5872)),
        ),
        child: ExpansionTile(
          key: const Key('nova-recordings-panel'),
          title: const Text(
            'Meeting audio recording',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            c.hasActive
                ? 'Recording or saving in progress'
                : 'Record, play back, or download',
            style: TextStyle(
              color: c.hasActive ? const Color(0xFFFFAD72) : muted,
            ),
          ),
          onExpansionChanged: (open) {
            if (open) c.refresh();
          },
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Save meeting audio privately for this agent. Up to 60 minutes per recording; '
                  '20 saved recordings. Audio is saved when you stop. Keep listening connected until then.',
                  style: TextStyle(color: muted),
                ),
                CheckboxListTile(
                  key: const Key('nova-recording-include-voice'),
                  contentPadding: EdgeInsets.zero,
                  value: c.includeNova,
                  onChanged: c.available && !c.busy && !c.hasActive
                    ? (value) => c.setIncludeNova(value == true) : null,
                  title: const Text('Include Nova’s voice from this browser',
                    style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Turn off if Zoom already includes Nova’s device audio.',
                    style: TextStyle(color: muted)),
                ),
                CheckboxListTile(
                  key: const Key('nova-recording-consent'),
                  contentPadding: EdgeInsets.zero,
                  value: c.consent,
                  onChanged:
                      !c.busy &&
                          !c.hasActive &&
                          c.capture.responseBinding != null
                      ? (value) => c.setConsent(value == true)
                      : null,
                  title: const Text(
                    'I have told participants and have permission to record.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      key: const Key('nova-recording-start'),
                      onPressed: c.canStart ? c.start : null,
                      icon: const Icon(Icons.fiber_manual_record),
                      label: const Text('Start recording'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('nova-recordings-refresh'),
                      onPressed: c.available && !c.busy
                          ? () => c.refresh()
                          : null,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh recordings'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (c.capture.responseBinding == null && !c.hasActive)
                  const Text(
                    'Start Nova or Start listening before recording.',
                    style: TextStyle(color: muted),
                  ),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    c.message,
                    style: const TextStyle(color: Color(0xFF22D8FF)),
                  ),
                ),
                if (c.busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  ),
                if (c.voiceWarning != null)
                  Text(c.voiceWarning!, style: const TextStyle(color: Color(0xFFFFAD72))),
                for (final r in c.recordings)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF07192D),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _date(r.createdAt),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_status(r)} · ${r.duration} audio',
                            style: const TextStyle(color: muted),
                          ),
                          if (r.endReason == 'duration_limit' &&
                              r.status == 'ready')
                            const Text(
                              'Saved at the 60-minute limit.',
                              style: TextStyle(color: muted),
                            ),
                          if (r.endReason == 'capture_ended' &&
                              r.status == 'ready')
                            const Text(
                              'Listening ended; received audio was saved.',
                              style: TextStyle(color: muted),
                            ),
                          if (r.status == 'failed')
                            Text(
                              r.endReason == 'no_audio'
                                  ? 'No meeting audio was received. Check the audio meter before trying again.'
                                  : 'This recording could not be saved. You can delete this entry.',
                              style: const TextStyle(color: muted),
                            ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (r.status == 'recording')
                                FilledButton(
                                  key: Key('nova-recording-stop-${r.id}'),
                                  onPressed: !c.busy ? () => c.stop(r) : null,
                                  child: const Text('Stop & save'),
                                ),
                              if (r.status == 'saving')
                                const Text(
                                  'Saving…',
                                  style: TextStyle(color: Color(0xFF22D8FF)),
                                ),
                              if (r.status == 'ready')
                                OutlinedButton(
                                  key: Key('nova-recording-open-${r.id}'),
                                  onPressed: !c.busy && !c.hasActive
                                      ? () {
                                          beforePlayback();
                                          c.open(r);
                                        }
                                      : null,
                                  child: const Text('Open recording'),
                                ),
                              if (!r.active)
                                TextButton(
                                  key: Key('nova-recording-delete-${r.id}'),
                                  onPressed: !c.busy
                                      ? () async {
                                          final confirmed = await showDialog<bool>(
                                            context: context,
                                            builder: (dialogContext) => AlertDialog(
                                              title: const Text(
                                                'Delete this recording?',
                                              ),
                                              content: const Text(
                                                'The saved audio will be permanently deleted.',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        dialogContext,
                                                        false,
                                                      ),
                                                  child: const Text('Cancel'),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        dialogContext,
                                                        true,
                                                      ),
                                                  child: const Text('Delete'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirmed == true)
                                            await c.remove(r);
                                        }
                                      : null,
                                  child: const Text('Delete'),
                                ),
                            ],
                          ),
                          if (c.playbackId == r.id &&
                              c.playbackUrl != null) ...[
                            const SizedBox(height: 10),
                            recordingAudio(c.playbackUrl!),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: c.downloadUrl == null
                                    ? null
                                    : () => launchUrl(
                                        c.downloadUrl!,
                                        mode: LaunchMode.externalApplication,
                                        webOnlyWindowName: '_blank',
                                      ),
                                icon: const Icon(Icons.download),
                                label: const Text('Download MP3'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Silence Nova pauses her replies, not recording. Stop listening also ends recording. '
                  'Recordings stay private until you download or share them, and remain saved until you delete them.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  static String _date(DateTime time) {
    final d = time.toLocal();
    return '${d.month}/${d.day}/${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _status(K135zRecording r) => switch (r.status) {
    'recording' =>
      r.durationMs == 0 ? 'Waiting for meeting audio' : 'Recording',
    'saving' => 'Saving',
    'ready' => 'Saved',
    'deleting' => 'Deletion pending',
    _ => 'Not saved',
  };
}
