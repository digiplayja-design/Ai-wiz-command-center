import 'dart:convert';

const emailModes = ['Polish', 'From notes', 'Reply'];
const emailTones = [
  'Professional',
  'Warm',
  'Confident',
  'Friendly',
  'Diplomatic',
  'Persuasive',
];
const emailLengths = ['Keep similar', 'Shorter', 'More detailed'];
const emailLanguages = [
  'Original language',
  'English',
  'Spanish',
  'French',
  'Portuguese',
  'German',
];

class EmailEnhancerException implements Exception {
  const EmailEnhancerException(this.message);
  final String message;
  @override
  String toString() => message;
}

class EmailBrief {
  const EmailBrief({
    this.source = '',
    this.context = '',
    this.recipient = '',
    this.goal = '',
    this.signature = '',
    this.mode = 'Polish',
    this.tone = 'Professional',
    this.length = 'Keep similar',
    this.language = 'Original language',
  });
  final String source,
      context,
      recipient,
      goal,
      signature,
      mode,
      tone,
      length,
      language;
  Map<String, dynamic> get json => {
    'source': source,
    'context': context,
    'recipient': recipient,
    'goal': goal,
    'signature': signature,
    'mode': mode,
    'tone': tone,
    'length': length,
    'language': language,
  };
  factory EmailBrief.fromJson(Map<String, dynamic> j) {
    for (final e in {
      'source': 12000,
      'context': 3000,
      'recipient': 200,
      'goal': 500,
      'signature': 500,
    }.entries) {
      if (j[e.key] is! String || (j[e.key] as String).length > e.value) {
        throw const FormatException('Invalid email draft.');
      }
    }
    for (final e in {
      'mode': emailModes,
      'tone': emailTones,
      'length': emailLengths,
      'language': emailLanguages,
    }.entries) {
      if (!e.value.contains(j[e.key])) {
        throw const FormatException('Invalid email settings.');
      }
    }
    return EmailBrief(
      source: j['source'],
      context: j['context'],
      recipient: j['recipient'],
      goal: j['goal'],
      signature: j['signature'],
      mode: j['mode'],
      tone: j['tone'],
      length: j['length'],
      language: j['language'],
    );
  }
  String? get error => source.trim().length < 8
      ? 'Add an email or at least a few words of notes.'
      : mode == 'Reply' && context.trim().isEmpty
      ? 'Add what you want to say in your reply.'
      : null;
}

class EnhancedEmail {
  const EnhancedEmail({
    required this.subjects,
    required this.body,
    required this.changes,
    required this.checks,
  });
  final List<String> subjects, changes, checks;
  final String body;
  factory EnhancedEmail.fromJson(Map<String, dynamic> j) {
    List<String> strings(String key, int count, int max) {
      final v = j[key];
      if (v is! List ||
          v.length > count ||
          v.any((s) => s is! String || s.trim().isEmpty || s.length > max)) {
        throw const FormatException('Incomplete email response.');
      }
      return v.cast<String>();
    }

    final subjects = strings('subjects', 3, 180);
    if (subjects.length != 3 ||
        subjects.any((s) => s.contains(RegExp(r'[\r\n]'))) ||
        j['body'] is! String ||
        (j['body'] as String).trim().isEmpty ||
        (j['body'] as String).length > 18000) {
      throw const FormatException('Incomplete email response.');
    }
    return EnhancedEmail(
      subjects: subjects,
      body: j['body'],
      changes: strings('changes', 5, 400),
      checks: strings('checks', 5, 400),
    );
  }
  Map<String, dynamic> get json => {
    'subjects': subjects,
    'body': body,
    'changes': changes,
    'checks': checks,
  };
}

class EmailVersion {
  const EmailVersion(this.brief, this.result);
  final EmailBrief brief;
  final EnhancedEmail result;
  Map<String, dynamic> get json => {'brief': brief.json, 'result': result.json};
  factory EmailVersion.fromJson(Map<String, dynamic> j) => EmailVersion(
    EmailBrief.fromJson(Map<String, dynamic>.from(j['brief'])),
    EnhancedEmail.fromJson(Map<String, dynamic>.from(j['result'])),
  );
}

class EmailDraft {
  const EmailDraft({
    required this.id,
    required this.brief,
    required this.subject,
    required this.body,
    required this.savedAt,
    this.version,
  });
  final String id, subject, body, savedAt;
  final EmailBrief brief;
  final EmailVersion? version;
  String get title => subject.trim().isNotEmpty
      ? subject.trim()
      : brief.source.trim().split('\n').first;
  Map<String, dynamic> get json => {
    'id': id,
    'brief': brief.json,
    'subject': subject,
    'body': body,
    'savedAt': savedAt,
    'version': version?.json,
  };
  factory EmailDraft.fromJson(Map<String, dynamic> j) {
    for (final e in {
      'id': 80,
      'subject': 180,
      'body': 18000,
      'savedAt': 60,
    }.entries) {
      if (j[e.key] is! String || (j[e.key] as String).length > e.value) {
        throw const FormatException('Invalid saved draft.');
      }
    }
    return EmailDraft(
      id: j['id'],
      brief: EmailBrief.fromJson(Map<String, dynamic>.from(j['brief'])),
      subject: j['subject'],
      body: j['body'],
      savedAt: j['savedAt'],
      version: j['version'] == null
          ? null
          : EmailVersion.fromJson(Map<String, dynamic>.from(j['version'])),
    );
  }
}

int emailWordCount(String value) =>
    value.trim().isEmpty ? 0 : value.trim().split(RegExp(r'\s+')).length;
String emailCopy(String subject, String body) =>
    'Subject: ${subject.trim()}\n\n${body.trim()}';
String emailEml(String subject, String body) {
  // Encoded words prevent header injection; split by code point before UTF-8 encoding.
  final units = subject.replaceAll(RegExp(r'[\r\n]'), ' ').runes.toList();
  final words = <String>[];
  for (var i = 0; i < units.length; i += 12) {
    words.add(
      '=?UTF-8?B?${base64.encode(utf8.encode(String.fromCharCodes(units.sublist(i, (i + 12).clamp(0, units.length)))))}?=',
    );
  }
  final payload = base64.encode(
    utf8.encode(body.replaceAll(RegExp(r'\r?\n'), '\r\n')),
  );
  final lines = [
    for (var i = 0; i < payload.length; i += 76)
      payload.substring(i, (i + 76).clamp(0, payload.length)),
  ];
  return 'MIME-Version: 1.0\r\nX-Unsent: 1\r\nSubject: ${words.join('\r\n ')}\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n${lines.join('\r\n')}\r\n';
}

const emailStarters = <String, EmailBrief>{
  'Follow up': EmailBrief(
    mode: 'From notes',
    tone: 'Warm',
    source:
        'Follow up on our recent conversation about [topic]. Ask whether there are any updates and offer to answer questions.',
    goal: 'Get an update without sounding pushy.',
  ),
  'Meeting request': EmailBrief(
    mode: 'From notes',
    source:
        'Request a meeting with [name] to discuss [topic]. Suggest [date and time] and ask what works for them.',
    goal: 'Agree on a meeting time.',
  ),
  'Thank you': EmailBrief(
    mode: 'From notes',
    tone: 'Warm',
    source:
        'Thank [name] for [specific help]. Explain how it helped with [outcome].',
    goal: 'Show sincere appreciation.',
  ),
  'Payment reminder': EmailBrief(
    mode: 'From notes',
    tone: 'Diplomatic',
    source:
        'Ask for an update on invoice [number] for [amount], due [date]. Invite them to let me know if they need any information.',
    goal: 'Confirm the expected payment date.',
  ),
};
