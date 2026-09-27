Map<String, dynamic> musicMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : {};
List<Map<String, dynamic>> musicRows(dynamic v) => v is List
    ? v.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList()
    : [];
const musicStatuses = {
  'submitting': 'Submitting',
  'submitted': 'Queued',
  'processing': 'Creating your music',
  'completed': 'Ready to play',
  'partial': 'One version ready',
  'failed': 'Could not finish',
  'uncertain': 'Needs a status check',
};
bool musicPending(Map<String, dynamic> j) =>
    ['submitting', 'submitted', 'processing'].contains(j['status']);
String musicTime(Duration d) =>
    '${d.inSeconds ~/ 60}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
Map<String, dynamic> blankMusic() => {
  'mode': 'idea',
  'idea': '',
  'title': '',
  'style': '',
  'lyrics': '',
  'voice': 'auto',
  'duration': null,
};
const musicStarters = [
  {
    'name': 'Island sunshine',
    'icon': 'sun',
    'mode': 'idea',
    'idea':
        'An uplifting song about enjoying life by the sea, with a memorable chorus and warm vocals.',
    'style': 'reggae, sunny, relaxed',
    'duration': 180,
  },
  {
    'name': 'Dance-floor energy',
    'icon': 'bolt',
    'mode': 'idea',
    'idea':
        'A confident feel-good anthem about celebrating a hard-earned win, with a catchy hook.',
    'style': 'dancehall, energetic, bold bass',
    'duration': 180,
  },
  {
    'name': 'Business jingle',
    'icon': 'store',
    'mode': 'idea',
    'idea':
        'A friendly, memorable jingle introducing [business name] and its [main benefit].',
    'style': 'pop, bright, welcoming',
    'duration': 30,
  },
  {
    'name': 'Focus & unwind',
    'icon': 'headphones',
    'mode': 'instrumental',
    'idea':
        'Warm piano, soft drums and a gentle repeating melody for a calm afternoon of focused work.',
    'style': 'lo-fi, calm, mellow',
    'duration': 180,
  },
  {
    'name': 'A song for someone',
    'icon': 'heart',
    'mode': 'idea',
    'idea':
        'A heartfelt song for [name], celebrating [memory] and saying what makes them special.',
    'style': 'soul, warm, heartfelt',
    'duration': 180,
  },
  {
    'name': 'Cinematic moment',
    'icon': 'movie',
    'mode': 'instrumental',
    'idea':
        'An inspiring instrumental that starts gently and builds to a hopeful, cinematic finish.',
    'style': 'cinematic, uplifting, strings',
    'duration': 90,
  },
];
Uri? musicUrl(dynamic value) {
  final u = Uri.tryParse('$value');
  return u != null &&
          u.scheme == 'https' &&
          u.host.isNotEmpty &&
          u.userInfo.isEmpty
      ? u
      : null;
}
