/// Keeps a spoken approval bound to the exact proposal the user heard.
/// A completed transcript from speech that began before readback cannot approve.
class SchedulingVoiceReadbackGuard {
  static const confirmationPhrase = 'Confirm scheduling change';
  String proposalId = '', ticket = '', responseId = '';
  String _expectedReadback = '';
  bool _completed = false, _audioStopped = false, _promptSpoken = false;
  final Set<String> _freshSpeech = {};

  bool get armed =>
      proposalId.isNotEmpty &&
      responseId.isNotEmpty &&
      _completed &&
      _audioStopped &&
      _promptSpoken;
  bool get finished => _completed && _audioStopped;

  static String normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'\ba\.?\s*m\.?\b'), 'am')
      .replaceAll(RegExp(r'\bp\.?\s*m\.?\b'), 'pm')
      .replaceAllMapped(
        RegExp(
          r'\b(?:(?:twenty|thirty)[ -](?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth)|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|eleventh|twelfth|thirteenth|fourteenth|fifteenth|sixteenth|seventeenth|eighteenth|nineteenth|twentieth|thirtieth)\b',
        ),
        (m) => _ordinal(m[0]!),
      )
      // Keep offset direction; UTC-04:00 must never equal UTC+04:00.
      .replaceAllMapped(
        RegExp(r'([+\-−])\s*(?=\d)'),
        (m) => m[1] == '+' ? ' plus ' : ' minus ',
      )
      .replaceAllMapped(
        RegExp(r'\b(\d{1,4})(?:st|nd|rd|th)?\b'),
        (m) => _number(int.parse(m[1]!)),
      )
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _ordinal(String value) {
    const words = {
      'first': 'one',
      'second': 'two',
      'third': 'three',
      'fourth': 'four',
      'fifth': 'five',
      'sixth': 'six',
      'seventh': 'seven',
      'eighth': 'eight',
      'ninth': 'nine',
      'tenth': 'ten',
      'eleventh': 'eleven',
      'twelfth': 'twelve',
      'thirteenth': 'thirteen',
      'fourteenth': 'fourteen',
      'fifteenth': 'fifteen',
      'sixteenth': 'sixteen',
      'seventeenth': 'seventeen',
      'eighteenth': 'eighteen',
      'nineteenth': 'nineteen',
      'twentieth': 'twenty',
      'thirtieth': 'thirty',
    };
    final parts = value.split(RegExp('[ -]'));
    return parts.map((part) => words[part] ?? part).join(' ');
  }

  static String _number(int value) {
    const small = [
      'zero',
      'one',
      'two',
      'three',
      'four',
      'five',
      'six',
      'seven',
      'eight',
      'nine',
      'ten',
      'eleven',
      'twelve',
      'thirteen',
      'fourteen',
      'fifteen',
      'sixteen',
      'seventeen',
      'eighteen',
      'nineteen',
    ];
    const tens = [
      '',
      '',
      'twenty',
      'thirty',
      'forty',
      'fifty',
      'sixty',
      'seventy',
      'eighty',
      'ninety',
    ];
    if (value < 20) return small[value];
    if (value < 100) {
      return '${tens[value ~/ 10]}${value % 10 == 0 ? '' : ' ${small[value % 10]}'}';
    }
    if (value < 1000) {
      return '${small[value ~/ 100]} hundred${value % 100 == 0 ? '' : ' ${_number(value % 100)}'}';
    }
    return '${small[value ~/ 1000]} thousand${value % 1000 == 0 ? '' : ' ${_number(value % 1000)}'}';
  }

  static bool isConfirmation(String text) =>
      normalize(text) == normalize(confirmationPhrase);

  void begin(String proposal, String nonce, String expectedReadback) {
    clear();
    proposalId = proposal;
    ticket = nonce;
    _expectedReadback = normalize(expectedReadback);
  }

  void responseCreated(String id, Map<String, dynamic> metadata) {
    if (id.isEmpty ||
        proposalId.isEmpty ||
        responseId.isNotEmpty ||
        metadata['korlix_scheduling_readback'] != proposalId ||
        metadata['korlix_scheduling_ticket'] != ticket) {
      return;
    }
    responseId = id;
  }

  void transcriptDone(String id, String transcript) {
    if (id != responseId || id.isEmpty) return;
    final normalized = normalize(transcript);
    _promptSpoken =
        _expectedReadback.isNotEmpty &&
        normalized.contains(_expectedReadback) &&
        normalized.contains(normalize(confirmationPhrase));
  }

  void responseDone(String id, String status) {
    if (id != responseId || id.isEmpty) return;
    if (status != 'completed') {
      clear();
      return;
    }
    _completed = true;
  }

  void audioStopped(String id, {bool interrupted = false}) {
    if (id != responseId || id.isEmpty) return;
    if (interrupted) {
      clear();
      return;
    }
    _audioStopped = true;
  }

  void speechStarted(String itemId) {
    _freshSpeech.clear();
    if (!armed || itemId.isEmpty || _freshSpeech.length >= 100) return;
    _freshSpeech.add(itemId);
  }

  bool consume(String itemId, String text, String currentProposal) {
    final fresh = itemId.isNotEmpty && _freshSpeech.remove(itemId);
    if (!fresh ||
        !armed ||
        currentProposal != proposalId ||
        !isConfirmation(text)) {
      return false;
    }
    clear();
    return true;
  }

  void clear() {
    proposalId = '';
    ticket = '';
    responseId = '';
    _expectedReadback = '';
    _completed = false;
    _audioStopped = false;
    _promptSpoken = false;
    _freshSpeech.clear();
  }
}
