import 'package:flutter/material.dart';
import 'k135z_feedback_button.dart';
import 'k135z_zoom_runtime_binding.dart';

class K135zStartupPanel extends StatelessWidget {
  const K135zStartupPanel({super.key, required this.binding});
  final K135zZoomRuntimeBinding? binding;

  @override
  Widget build(BuildContext context) {
    final b = binding, c = b?.capture, meeting = b?.listeningMeeting;
    final available = b != null && b.usable && !b.busy && !b.capture.busy;
    final listening = c?.statusLabel == 'Listening';
    final voiceSupported = b?.response.spoken.player.supported == true;
    final voice = b?.response.spoken;
    final novaOn = voice?.enabled == true && c?.meetingUuid == meeting?.uuid;
    const muted = Color(0xFF9CB8CA), cyan = Color(0xFF22D8FF);
    return Material(
      color: const Color(0xFF0A223A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF1A5872))),
      child: Padding(padding: const EdgeInsets.all(18), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Start with Nova', style: TextStyle(color: Colors.white,
            fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(b == null ? 'Open Meeting Copilot from your selected agent in Agent Hub.'
            : b.connected ? meeting == null ? 'Choose your meeting below.'
              : 'Meeting: ${meeting.topic}' : b.message,
            key: const Key('g6c-connection-message'), style: const TextStyle(color: muted)),
          if (b != null && b.connected && b.meetings.length > 1) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final item in b.meetings)
                K135zFeedbackButton.outlined(
                  selected: item.uuid != null && item.uuid == meeting?.uuid,
                  onPressed: available && item.uuid != null
                    ? () => b.chooseListeningMeeting(item.uuid!) : null,
                  child: Text(item.topic)),
            ]),
          ],
          const SizedBox(height: 12),
          Text(voiceSupported
            ? 'Tap Start Nova, then say “Nova” and your question. This allows listening, '
              'transcription and spoken replies to anyone who addresses her in the meeting shown, '
              'including brief acknowledgments while she thinks.'
            : 'By tapping Start listening, I consent to listening and transcription '
              'for the meeting shown. Open this page in a supported browser for spoken replies.',
            key: const Key('listening-consent-notice'), style: const TextStyle(color: muted, fontSize: 13)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            K135zFeedbackButton.filled(
              buttonKey: Key(voiceSupported ? 'start-nova-button' : 'start-listening-button'),
              selected: voiceSupported ? novaOn : listening && c?.meetingUuid == meeting?.uuid,
              activeColor: const Color(0xFF63E6A1),
              pendingLabel: voiceSupported ? 'Starting Nova…' : 'Starting listening…',
              icon: const Icon(Icons.headset_mic_outlined),
              onPressed: voiceSupported
                ? voice?.needsAudioTap == true && voice?.busy == false
                  ? () => voice!.returnToPage(userGesture:true)
                  : b?.canStartNova == true ? b!.startNova : null
                : b?.canStartListening == true ? b!.startListening : null,
              child: Text(voiceSupported ? voice?.needsAudioTap == true ? 'Resume Nova'
                : novaOn ? 'Nova is on' : 'Start Nova' : 'Start listening')),
            K135zFeedbackButton.outlined(
              buttonKey: const Key('stop-listening-button'),
              pendingLabel: 'Stopping listening…',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: c?.canStop == true ? b!.stopListening : null,
              child: const Text('Stop listening')),
            if (voiceSupported)
              K135zFeedbackButton.outlined(
                buttonKey: const Key('startup-stop-nova'),
                onPressed: () => b!.response.stop(),
                icon: const Icon(Icons.volume_off_outlined),
                child: const Text('Silence Nova')),
          ]),
          const SizedBox(height: 10),
          Semantics(liveRegion: true, child: Text(
            voice?.starting == true || voice?.enabled == true ? voice!.message
              : c?.meetingUuid != null ? c!.listeningMessage
              : b?.busy == true ? 'Finding your meeting…'
              : meeting != null ? 'Ready. One tap starts Nova.'
              : b?.connected == true ? 'Start your meeting in Zoom, then refresh the meeting list.'
              : 'Connect Zoom once to enable listening.',
            key: const Key('g6n-session-message'),
            style: TextStyle(color: c?.actionError == null ? cyan : const Color(0xFFFFA2A2)))),
          if (b != null && !b.connected) ...[
            const SizedBox(height: 10),
            K135zFeedbackButton.filled(
              buttonKey: const Key('g6c-connect'),
              onPressed: b.canOpenAuthorization ? b.openAuthorization
                : available ? b.prepareAuthorization : null,
              pendingLabel: 'Preparing Zoom…',
              child: Text(b.canOpenAuthorization ? 'Continue to Zoom' : 'Connect Zoom')),
          ],
          ExpansionTile(
            key: const Key('copilot-connection-options'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Connection options', style: TextStyle(color: muted, fontSize: 14)),
            children: [Wrap(spacing: 8, runSpacing: 8, children: [
              if (voiceSupported)
                K135zFeedbackButton.outlined(
                  buttonKey: const Key('start-listening-button'),
                  onPressed: b?.canStartListening == true && voice?.busy == false ? () {
                    b!.response.stop(); return b.startListening();
                  } : null,
                  child: const Text('Start listening only')),
              K135zFeedbackButton.outlined(buttonKey: const Key('g6c-refresh'),
                onPressed: available ? b.initialize : null, pendingLabel: 'Checking…',
                child: const Text('Refresh connection & meetings')),
              if (c != null && listening)
                K135zFeedbackButton.outlined(buttonKey: const Key('pause-listening-button'),
                  onPressed: c.canPause ? c.pause : null, child: const Text('Pause listening')),
              if (b != null && b.connected)
                K135zFeedbackButton.outlined(buttonKey: const Key('g6c-prepare'),
                  onPressed: available ? b.prepareAuthorization : null, child: const Text('Reconnect Zoom')),
              if (b?.canOpenAuthorization == true)
                K135zFeedbackButton.outlined(buttonKey: const Key('g6c-open'),
                  onPressed: b!.openAuthorization, child: const Text('Continue to Zoom')),
              if (b != null && b.connected)
                K135zFeedbackButton.outlined(buttonKey: const Key('g6c-disconnect'),
                  onPressed: available ? b.disconnect : null, child: const Text('Disconnect Zoom')),
            ])],
          ),
          const Text('Keep this tab open. Nova stays active while your browser allows it '
            'and reconnects when you return. On phones and tablets, keep KORLIX visible '
            'for reliable replies. Stop listening ends the session.',
            style: TextStyle(color: muted, fontSize: 12)),
        ],
      )),
    );
  }
}
