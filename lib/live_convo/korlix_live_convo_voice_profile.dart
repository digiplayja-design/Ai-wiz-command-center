import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// KORLIX_LIVE_CONVO_VOICE_PROFILE_BUILD131_V1
class KorlixLiveConvoVoiceOption {
  const KorlixLiveConvoVoiceOption({
    required this.id,
    required this.name,
    required this.presentationLabel,
    required this.description,
    this.recommended = false,
  });

  final String id;
  final String name;
  final String presentationLabel;
  final String description;
  final bool recommended;
}

class KorlixLiveConvoAccentOption {
  const KorlixLiveConvoAccentOption({
    required this.id,
    required this.name,
    required this.description,
  });

  final String id;
  final String name;
  final String description;
}

class KorlixLiveConvoVoiceSelection {
  const KorlixLiveConvoVoiceSelection({
    required this.voiceId,
    required this.accentId,
  });

  final String voiceId;
  final String accentId;

  KorlixLiveConvoVoiceOption get voice =>
      KorlixLiveConvoVoiceCatalog.voiceById(voiceId);

  KorlixLiveConvoAccentOption get accent =>
      KorlixLiveConvoVoiceCatalog.accentById(accentId);

  @override
  bool operator ==(Object other) {
    return other is KorlixLiveConvoVoiceSelection &&
        other.voiceId == voiceId &&
        other.accentId == accentId;
  }

  @override
  int get hashCode => Object.hash(voiceId, accentId);
}

class KorlixLiveConvoVoiceCatalog {
  KorlixLiveConvoVoiceCatalog._();

  static const List<KorlixLiveConvoVoiceOption> voices =
      <KorlixLiveConvoVoiceOption>[
        KorlixLiveConvoVoiceOption(
          id: 'marin',
          name: 'Marin',
          presentationLabel: 'Feminine-presenting',
          description: 'Smooth, warm, and polished.',
          recommended: true,
        ),
        KorlixLiveConvoVoiceOption(
          id: 'coral',
          name: 'Coral',
          presentationLabel: 'Feminine-presenting',
          description: 'Bright, friendly, and expressive.',
        ),
        KorlixLiveConvoVoiceOption(
          id: 'shimmer',
          name: 'Shimmer',
          presentationLabel: 'Feminine-presenting',
          description: 'Light, upbeat, and energetic.',
        ),
        KorlixLiveConvoVoiceOption(
          id: 'sage',
          name: 'Sage',
          presentationLabel: 'Feminine-presenting',
          description: 'Calm, composed, and thoughtful.',
        ),
        KorlixLiveConvoVoiceOption(
          id: 'cedar',
          name: 'Cedar',
          presentationLabel: 'Masculine-presenting',
          description: 'Rich, natural, and confident.',
          recommended: true,
        ),
        KorlixLiveConvoVoiceOption(
          id: 'ash',
          name: 'Ash',
          presentationLabel: 'Masculine-presenting',
          description: 'Clear, steady, and conversational.',
        ),
        KorlixLiveConvoVoiceOption(
          id: 'ballad',
          name: 'Ballad',
          presentationLabel: 'Masculine-presenting',
          description: 'Warm, expressive, and measured.',
        ),
        KorlixLiveConvoVoiceOption(
          id: 'echo',
          name: 'Echo',
          presentationLabel: 'Masculine-presenting',
          description: 'Deep, direct, and grounded.',
        ),
        KorlixLiveConvoVoiceOption(
          id: 'verse',
          name: 'Verse',
          presentationLabel: 'Masculine-presenting',
          description: 'Confident, versatile, and lively.',
        ),
        KorlixLiveConvoVoiceOption(
          id: 'alloy',
          name: 'Alloy',
          presentationLabel: 'Neutral-presenting',
          description: 'Balanced, flexible, and neutral.',
        ),
      ];

  static const List<KorlixLiveConvoAccentOption> accents =
      <KorlixLiveConvoAccentOption>[
        KorlixLiveConvoAccentOption(
          id: 'neutral',
          name: 'Clear International',
          description: 'Natural delivery without a requested regional accent.',
        ),
        KorlixLiveConvoAccentOption(
          id: 'general_american',
          name: 'General American',
          description: 'Clear, modern American English delivery.',
        ),
        KorlixLiveConvoAccentOption(
          id: 'british_english',
          name: 'British English',
          description: 'Natural modern British English delivery.',
        ),
        KorlixLiveConvoAccentOption(
          id: 'australian_english',
          name: 'Australian English',
          description: 'Relaxed, clear Australian English delivery.',
        ),
        KorlixLiveConvoAccentOption(
          id: 'jamaican_caribbean_english',
          name: 'Jamaican / Caribbean English',
          description:
              'Subtle Caribbean-influenced English, kept clear and respectful.',
        ),
        KorlixLiveConvoAccentOption(
          id: 'nigerian_english',
          name: 'Nigerian English',
          description: 'Clear, educated Nigerian English delivery.',
        ),
        KorlixLiveConvoAccentOption(
          id: 'indian_english',
          name: 'Indian English',
          description: 'Clear, educated Indian English delivery.',
        ),
        KorlixLiveConvoAccentOption(
          id: 'irish_english',
          name: 'Irish English',
          description: 'Natural, clear Irish English delivery.',
        ),
        KorlixLiveConvoAccentOption(
          id: 'canadian_english',
          name: 'Canadian English',
          description: 'Natural, clear Canadian English delivery.',
        ),
      ];

  static const KorlixLiveConvoVoiceSelection defaultSelection =
      KorlixLiveConvoVoiceSelection(voiceId: 'marin', accentId: 'neutral');

  static KorlixLiveConvoVoiceOption voiceById(String rawId) {
    final id = rawId.trim().toLowerCase();
    return voices.firstWhere(
      (voice) => voice.id == id,
      orElse: () => voices.first,
    );
  }

  static KorlixLiveConvoAccentOption accentById(String rawId) {
    final id = rawId.trim().toLowerCase();
    return accents.firstWhere(
      (accent) => accent.id == id,
      orElse: () => accents.first,
    );
  }

  static KorlixLiveConvoVoiceSelection normalize({
    required String voiceId,
    required String accentId,
  }) {
    return KorlixLiveConvoVoiceSelection(
      voiceId: voiceById(voiceId).id,
      accentId: accentById(accentId).id,
    );
  }
}

class KorlixLiveConvoVoicePreferences {
  KorlixLiveConvoVoicePreferences._();

  static const String _voiceKey = 'korlix_live_convo_voice_v1';
  static const String _accentKey = 'korlix_live_convo_accent_v1';

  static Future<KorlixLiveConvoVoiceSelection> load() async {
    final preferences = await SharedPreferences.getInstance();
    return KorlixLiveConvoVoiceCatalog.normalize(
      voiceId:
          preferences.getString(_voiceKey) ??
          KorlixLiveConvoVoiceCatalog.defaultSelection.voiceId,
      accentId:
          preferences.getString(_accentKey) ??
          KorlixLiveConvoVoiceCatalog.defaultSelection.accentId,
    );
  }

  static Future<void> save(KorlixLiveConvoVoiceSelection selection) async {
    final normalized = KorlixLiveConvoVoiceCatalog.normalize(
      voiceId: selection.voiceId,
      accentId: selection.accentId,
    );
    final preferences = await SharedPreferences.getInstance();
    final voiceSaved = await preferences.setString(
      _voiceKey,
      normalized.voiceId,
    );
    final accentSaved = await preferences.setString(
      _accentKey,
      normalized.accentId,
    );
    if (!voiceSaved || !accentSaved) {
      throw StateError('The LIVE CONVO voice preference could not be saved.');
    }
  }
}

Future<KorlixLiveConvoVoiceSelection?> showKorlixLiveConvoVoiceSelector({
  required BuildContext context,
  required KorlixLiveConvoVoiceSelection currentSelection,
}) {
  return showModalBottomSheet<KorlixLiveConvoVoiceSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xCC02070C),
    builder: (sheetContext) {
      return _KorlixLiveConvoVoiceSelectorSheet(
        currentSelection: currentSelection,
      );
    },
  );
}

class _KorlixLiveConvoVoiceSelectorSheet extends StatefulWidget {
  const _KorlixLiveConvoVoiceSelectorSheet({required this.currentSelection});

  final KorlixLiveConvoVoiceSelection currentSelection;

  @override
  State<_KorlixLiveConvoVoiceSelectorSheet> createState() =>
      _KorlixLiveConvoVoiceSelectorSheetState();
}

class _KorlixLiveConvoVoiceSelectorSheetState
    extends State<_KorlixLiveConvoVoiceSelectorSheet> {
  late String _voiceId;
  late String _accentId;

  @override
  void initState() {
    super.initState();
    final normalized = KorlixLiveConvoVoiceCatalog.normalize(
      voiceId: widget.currentSelection.voiceId,
      accentId: widget.currentSelection.accentId,
    );
    _voiceId = normalized.voiceId;
    _accentId = normalized.accentId;
  }

  Widget _voiceCard(KorlixLiveConvoVoiceOption voice) {
    final selected = voice.id == _voiceId;
    final accent = selected ? const Color(0xFF21D4F4) : const Color(0xFF244858);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() {
              _voiceId = voice.id;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF0B2B38)
                  : const Color(0xFF071722),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: accent.withValues(alpha: selected ? 0.95 : 0.62),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.record_voice_over_rounded,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              voice.name,
                              style: const TextStyle(
                                color: Color(0xFFF1F6F8),
                                fontWeight: FontWeight.w900,
                                fontSize: 15.5,
                              ),
                            ),
                          ),
                          if (voice.recommended)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFFD166,
                                ).withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(
                                    0xFFFFD166,
                                  ).withValues(alpha: 0.65),
                                ),
                              ),
                              child: const Text(
                                'RECOMMENDED',
                                style: TextStyle(
                                  color: Color(0xFFFFD166),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        voice.description,
                        style: const TextStyle(
                          color: Color(0xFFA9C6CF),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _voiceGroup(String label) {
    final options = KorlixLiveConvoVoiceCatalog.voices
        .where((voice) => voice.presentationLabel == label)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 9, top: 8),
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF7BDFF2),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ),
        for (final voice in options) _voiceCard(voice),
      ],
    );
  }

  Widget _accentSelector() {
    final selectedAccent = KorlixLiveConvoVoiceCatalog.accentById(_accentId);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF071722),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF31596A)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedAccent.id,
          isExpanded: true,
          dropdownColor: const Color(0xFF071722),
          iconEnabledColor: const Color(0xFF21D4F4),
          style: const TextStyle(
            color: Color(0xFFF1F6F8),
            fontWeight: FontWeight.w800,
          ),
          items: [
            for (final accent in KorlixLiveConvoVoiceCatalog.accents)
              DropdownMenuItem<String>(
                value: accent.id,
                child: Text(accent.name),
              ),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              _accentId = value;
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final selectedAccent = KorlixLiveConvoVoiceCatalog.accentById(_accentId);

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.93),
        decoration: const BoxDecoration(
          color: Color(0xFF031019),
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(top: BorderSide(color: Color(0xFF21D4F4), width: 1.2)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF21D4F4).withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF21D4F4).withValues(alpha: 0.65),
                      ),
                    ),
                    child: const Icon(
                      Icons.voice_chat_rounded,
                      color: Color(0xFF21D4F4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CHOOSE LIVE CONVO VOICE',
                          style: TextStyle(
                            color: Color(0xFFF1F6F8),
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Voice and accent are saved for future sessions.',
                          style: TextStyle(
                            color: Color(0xFFA9C6CF),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close voice selector',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: const Color(0xFFC7D7DC),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1B0D),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFFFD166).withValues(alpha: 0.55),
                      ),
                    ),
                    child: const Text(
                      'Feminine, masculine, and neutral are KORLIX presentation '
                      'labels to help selection; they are not official voice '
                      'gender designations. Accent presets are best effort and '
                      'are designed to remain natural and respectful.',
                      style: TextStyle(
                        color: Color(0xFFFFE6A6),
                        height: 1.4,
                        fontSize: 12.2,
                      ),
                    ),
                  ),
                  _voiceGroup('Feminine-presenting'),
                  _voiceGroup('Masculine-presenting'),
                  _voiceGroup('Neutral-presenting'),
                  const SizedBox(height: 8),
                  const Text(
                    'ACCENT',
                    style: TextStyle(
                      color: Color(0xFF7BDFF2),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 9),
                  _accentSelector(),
                  const SizedBox(height: 8),
                  Text(
                    selectedAccent.description,
                    style: const TextStyle(
                      color: Color(0xFFA9C6CF),
                      height: 1.35,
                      fontSize: 12.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Changing voice during LIVE CONVO reconnects the voice '
                    'session and restores the current chat automatically.',
                    style: TextStyle(
                      color: Color(0xFF8EB4BF),
                      height: 1.35,
                      fontSize: 12.2,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(
                          KorlixLiveConvoVoiceCatalog.normalize(
                            voiceId: _voiceId,
                            accentId: _accentId,
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF21D4F4),
                        foregroundColor: const Color(0xFF031019),
                      ),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text(
                        'Apply Voice',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
