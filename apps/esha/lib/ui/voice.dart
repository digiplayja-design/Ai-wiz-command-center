import 'dart:async';

import 'package:flutter/material.dart';

import '../voice_controller.dart';
import 'brand.dart';

String voiceTime(num seconds) {
  final whole = seconds.floor();
  return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}';
}

class EshaVoicePanel extends StatefulWidget {
  const EshaVoicePanel({super.key, required this.controller});
  final EshaVoiceController controller;
  @override
  State<EshaVoicePanel> createState() => _EshaVoicePanelState();
}

class _EshaVoicePanelState extends State<EshaVoicePanel> {
  EshaVoiceController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    unawaited(c.refresh());
  }

  @override
  void dispose() {
    // Leaving the voice screen never leaves an invisible open microphone.
    if (c.canStop) unawaited(Future<void>.microtask(c.pause));
    super.dispose();
  }

  String get status => switch (c.phase) {
    EshaVoicePhase.preparing => 'Preparing audio · not sharing yet',
    EshaVoicePhase.connecting => 'Connecting · not sharing yet',
    EshaVoicePhase.listening => 'Listening · you can interrupt Esha',
    EshaVoicePhase.stopping => 'Turning off the microphone',
    EshaVoicePhase.pending => 'Microphone off · confirming the call ended',
    EshaVoicePhase.paused => 'Paused · microphone off',
    EshaVoicePhase.ended => 'Call ended · microphone off',
    EshaVoicePhase.idle => 'Microphone off',
  };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => EshaPanel(
      color: blush,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Talk with Esha',
            style: TextStyle(fontFamily: 'Georgia', fontSize: 28),
          ),
          const SizedBox(height: 8),
          const Text(
            'Have a natural voice conversation about your beauty routine. This is an AI voice, and you can speak while Esha is talking.',
          ),
          const SizedBox(height: 20),
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                Icon(
                  c.active ? Icons.mic : Icons.mic_off_outlined,
                  color: pink,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    status,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          if (c.active || c.elapsedSeconds > 0) ...[
            const SizedBox(height: 8),
            Text('${voiceTime(c.elapsedSeconds)} conversation time'),
          ],
          const Divider(height: 32),
          if (c.usage != null) ...[
            Text(
              '${voiceTime(c.usage!.remainingSeconds)} of ${voiceTime(c.usage!.limitSeconds)} voice time remaining',
              key: const ValueKey('esha-voice-allowance'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${c.usage!.deepRemaining} of ${c.usage!.deepLimit} deep-thinking consultations remaining',
              key: const ValueKey('esha-voice-deep-allowance'),
            ),
            if (c.usage!.reservedSeconds > 0)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Some voice time is reserved while a call is active or being finalized.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ),
          ] else
            const Text(
              'Your verified voice and deep-thinking allowances will appear here when the service is available.',
            ),
          const SizedBox(height: 16),
          const Text(
            'Before you start',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Korlix and OpenAI process your microphone audio and conversation transcripts to provide spoken answers. No camera is used. Voice time includes silence and time waiting for answers. Pause and Stop turn off the microphone and end the current call; Resume starts a new call after the previous one is confirmed closed.',
            style: TextStyle(fontSize: 13),
          ),
          CheckboxListTile(
            key: const ValueKey('esha-voice-audio-consent'),
            value: c.audioConsent,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: c.api.session == null
                ? null
                : (value) => c.setAudioConsent(value == true),
            title: const Text(
              'I allow Korlix and OpenAI to process my microphone audio and conversation transcripts for this call.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          CheckboxListTile(
            key: const ValueKey('esha-voice-deep-consent'),
            value: c.deepThinkingConsent,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: c.canChooseConsent && (c.usage?.deepRemaining ?? 0) > 0
                ? (value) => c.setDeepThinkingConsent(value == true)
                : null,
            title: const Text(
              'Allow deep thinking during this call (uses your consultation allowance)',
              style: TextStyle(fontSize: 13),
            ),
          ),
          const Text(
            'Deep thinking is optional and starts off. Turn audio sharing off to end a call. Confirm your choices again for every new call, including after Pause or Restart.',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          TextButton(
            onPressed: () =>
                openSource(context, '${c.api.config.apiOrigin}/esha/privacy'),
            child: const Text('Read Esha Privacy Policy'),
          ),
          if (c.error != null) ...[
            const SizedBox(height: 8),
            Text(
              c.error!,
              style: const TextStyle(color: pink),
              key: const ValueKey('esha-voice-status-message'),
            ),
          ],
          if (c.busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (!c.canStop)
                FilledButton.icon(
                  key: const ValueKey('esha-voice-start'),
                  onPressed: c.canStart
                      ? (c.phase == EshaVoicePhase.paused ? c.resume : c.start)
                      : null,
                  icon: const Icon(Icons.mic),
                  label: Text(
                    c.phase == EshaVoicePhase.paused
                        ? 'Resume voice'
                        : c.phase == EshaVoicePhase.ended
                        ? 'Start again'
                        : 'Start voice',
                  ),
                ),
              if (c.canStop && !c.hasPendingSession ||
                  c.active ||
                  c.phase == EshaVoicePhase.connecting) ...[
                OutlinedButton.icon(
                  key: const ValueKey('esha-voice-pause'),
                  onPressed: c.pause,
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause'),
                ),
              ],
              if (c.canStop)
                OutlinedButton.icon(
                  key: const ValueKey('esha-voice-stop'),
                  onPressed: c.phase == EshaVoicePhase.stopping ? null : c.stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              if (c.active)
                TextButton.icon(
                  key: const ValueKey('esha-voice-restart'),
                  onPressed: c.restart,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Restart'),
                ),
              if (!c.active && !c.busy)
                TextButton.icon(
                  onPressed: c.refresh,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    c.hasPendingSession
                        ? 'Check previous call'
                        : 'Refresh availability',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Check product details before purchase. Esha’s voice recommendations can be mistaken.',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          if (c.hasSavedAnswerSessions || c.deepResults.isNotEmpty) ...[
            const Divider(height: 32),
            const Text(
              'Saved deep-thinking answers',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Read answers from your recent calls, including answers that finish after the microphone is off. Refreshing answers does not use another consultation.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            for (final result in c.deepResults)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: EshaPanel(
                  color: Colors.white,
                  child: SelectableText(
                    result.answer,
                    key: ValueKey('esha-voice-deep-${result.requestId}'),
                  ),
                ),
              ),
            if (c.resultsError != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  c.resultsError!,
                  style: const TextStyle(color: pink),
                ),
              ),
            TextButton.icon(
              onPressed: c.loadingResults ? null : c.refreshResults,
              icon: const Icon(Icons.refresh),
              label: Text(
                c.loadingResults ? 'Loading answers…' : 'Refresh saved answers',
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
