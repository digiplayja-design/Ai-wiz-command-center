import 'dart:convert';
import '../live_convo/agent_studio_client.dart' show agentStudioKey;

const resumeSections = [
  'summary',
  'experience',
  'education',
  'skills',
  'projects',
  'certifications',
];
const resumeSectionNames = {
  'summary': 'Profile',
  'experience': 'Experience',
  'education': 'Education',
  'skills': 'Skills',
  'projects': 'Projects & community',
  'certifications': 'Certifications & awards',
};
const resumeFields = [
  'name',
  'email',
  'phone',
  'location',
  'link',
  'role',
  'company',
  'summary',
  'skills',
  'projects',
  'certifications',
  'letter',
  'job',
  'keywords',
];

/// Only user-confirmed content is rendered. Job targeting and editor metadata
/// never appear in the exported resume.
class ResumeDraft {
  ResumeDraft({
    String? id,
    this.title = 'My resume',
    Map<String, String>? fields,
    List<Map<String, String>>? experience,
    List<Map<String, String>>? education,
    this.template = 'modern',
    this.accent = '155E75',
    this.paper = 'letter',
    this.compact = false,
    List<String>? order,
    this.updated = '',
  }) : id = id ?? agentStudioKey(),
       fields = fields ?? {},
       experience = experience ?? [],
       education = education ?? [],
       order = order ?? List.of(resumeSections);
  final String id;
  String title, template, accent, paper, updated;
  bool compact;
  final Map<String, String> fields;
  final List<Map<String, String>> experience, education;
  final List<String> order;
  String get(String key) => fields[key]?.trim() ?? '';
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'fields': fields,
    'experience': experience,
    'education': education,
    'template': template,
    'accent': accent,
    'paper': paper,
    'compact': compact,
    'order': order,
    'updated': updated,
  };
  ResumeDraft clone({bool newIdentity = false}) {
    final map = jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>;
    if (newIdentity) {
      map['id'] = agentStudioKey();
      map['title'] =
          '${title.length > 112 ? title.substring(0, 112) : title} - copy';
      map['updated'] = '';
    }
    return ResumeDraft.fromJson(map);
  }

  factory ResumeDraft.fromJson(Map<String, dynamic> json) {
    String str(dynamic x, [int max = 12000]) {
      if (x is! String || x.length > max) {
        throw const FormatException('Invalid resume field.');
      }
      return x;
    }

    Map<String, String> fields(dynamic value, Iterable<String> keys) {
      if (value is! Map) throw const FormatException('Invalid resume details.');
      return {
        for (final k in keys)
          if (value.containsKey(k))
            k: str(
              value[k],
              const <String, int>{
                    'name': 120,
                    'email': 254,
                    'phone': 60,
                    'location': 140,
                    'link': 250,
                    'role': 140,
                    'company': 160,
                    'title': 140,
                    'degree': 200,
                    'school': 200,
                    'dates': 100,
                    'summary': 3000,
                    'skills': 3000,
                    'bullets': 6000,
                    'details': 2000,
                    'projects': 6000,
                    'certifications': 4000,
                    'keywords': 1200,
                  }[k] ??
                  12000,
            ),
      };
    }

    List<Map<String, String>> entries(dynamic value, List<String> keys) {
      if (value is! List || value.length > 20) {
        throw const FormatException('Too many resume entries.');
      }
      return value.map((v) => fields(v, keys)).toList();
    }

    final id = str(json['id'], 80);
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Invalid draft.');
    }
    final order = json['order'];
    if (order is! List ||
        order.length != resumeSections.length ||
        order.toSet().length != order.length ||
        order.any((x) => !resumeSections.contains(x))) {
      throw const FormatException('Invalid section order.');
    }
    final template = str(json['template'], 30),
        accent = str(json['accent'], 6),
        paper = str(json['paper'], 10);
    if (!['modern', 'executive', 'minimal'].contains(template) ||
        !['155E75', '3730A3', '166534', '7C2D12', '1E293B'].contains(accent) ||
        !['letter', 'a4'].contains(paper)) {
      throw const FormatException('Invalid resume style.');
    }
    return ResumeDraft(
      id: id,
      title: str(json['title'], 120),
      fields: fields(json['fields'], resumeFields),
      experience: entries(json['experience'], [
        'title',
        'company',
        'location',
        'dates',
        'bullets',
      ]),
      education: entries(json['education'], [
        'degree',
        'school',
        'dates',
        'details',
      ]),
      template: template,
      accent: accent,
      paper: paper,
      compact: json['compact'] == true,
      order: order.cast<String>(),
      updated: str(json['updated'] ?? '', 80),
    );
  }
  String get fileStem {
    final name = get('name').isEmpty ? title : get('name');
    final safe = name
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '${safe.isEmpty ? 'KORLIX' : safe.substring(0, safe.length.clamp(0, 60))}-Resume';
  }

  String get text => blocks()
      .map((b) => b.kind == 'bullet' ? '- ${b.text}' : b.text)
      .join('\n');
  List<ResumeBlock> blocks({bool letter = false}) {
    final result = <ResumeBlock>[];
    void add(String kind, String text) {
      if (text.trim().isNotEmpty) result.add(ResumeBlock(kind, text.trim()));
    }

    add('name', get('name'));
    add('role', get('role'));
    add(
      'contact',
      [
        'email',
        'phone',
        'location',
        'link',
      ].map(get).where((x) => x.isNotEmpty).join('  |  '),
    );
    if (letter) {
      for (final p in get('letter').split(RegExp(r'\n\s*\n'))) {
        add('paragraph', p);
      }
      return result;
    }
    for (final section in order) {
      final content = <ResumeBlock>[];
      void line(String kind, String text) {
        if (text.trim().isNotEmpty) content.add(ResumeBlock(kind, text.trim()));
      }

      if (section == 'experience') {
        for (final e in experience) {
          line(
            'title',
            [
              e['title'] ?? '',
              e['company'] ?? '',
            ].where((s) => s.trim().isNotEmpty).join(' | '),
          );
          line(
            'meta',
            [
              e['dates'] ?? '',
              e['location'] ?? '',
            ].where((s) => s.trim().isNotEmpty).join(' | '),
          );
          for (final s in resumeLines(e['bullets'] ?? '')) {
            line('bullet', s);
          }
        }
      } else if (section == 'education') {
        for (final e in education) {
          line('title', e['degree'] ?? '');
          line(
            'meta',
            [
              e['school'] ?? '',
              e['dates'] ?? '',
            ].where((s) => s.trim().isNotEmpty).join(' | '),
          );
          line('paragraph', e['details'] ?? '');
        }
      } else {
        for (final p in get(section).split('\n')) {
          line(
            section == 'projects' || section == 'certifications'
                ? 'bullet'
                : 'paragraph',
            p,
          );
        }
      }
      if (content.isNotEmpty) {
        add('heading', resumeSectionNames[section]!);
        result.addAll(content);
      }
    }
    return result;
  }

  List<ResumeCheck> get checks => [
    ResumeCheck('Name added', get('name').isNotEmpty, 'basics'),
    ResumeCheck(
      'Professional email added',
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(get('email')),
      'basics',
    ),
    ResumeCheck('Target role added', get('role').isNotEmpty, 'basics'),
    ResumeCheck('Profile written', get('summary').isNotEmpty, 'summary'),
    ResumeCheck(
      'Experience or projects added',
      experience.any((e) => (e['bullets'] ?? '').trim().isNotEmpty) ||
          get('projects').isNotEmpty,
      'experience',
    ),
    ResumeCheck('Skills added', get('skills').isNotEmpty, 'skills'),
  ];
  int get wordCount =>
      text.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).length;
  bool get hasEvidence =>
      [
        'summary',
        'skills',
        'projects',
        'certifications',
      ].any((k) => get(k).isNotEmpty) ||
      experience.any((e) => (e['bullets'] ?? '').trim().isNotEmpty);

  String get aiFacts => jsonEncode({
    for (final k in [
      'role',
      'company',
      'summary',
      'skills',
      'projects',
      'certifications',
    ])
      k: get(k),
    'experience': experience,
    'education': education,
  });
}

class ResumeBlock {
  const ResumeBlock(this.kind, this.text);
  final String kind, text;
}

class ResumeCheck {
  const ResumeCheck(this.label, this.done, this.section);
  final String label, section;
  final bool done;
}

List<String> resumeLines(String value) => value
    .split('\n')
    .map((s) => s.replaceFirst(RegExp(r'^\s*[-•*]\s*'), '').trim())
    .where((s) => s.isNotEmpty)
    .toList();

/// Literal, case-insensitive phrase comparison. These are user-selected terms,
/// not an opaque ATS score or a claim that the applicant has a qualification.
Map<String, bool> resumeKeywordMatches(ResumeDraft draft) {
  final text = draft.text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final terms = draft
      .get('keywords')
      .split(RegExp(r'[,\n]'))
      .map((x) => x.trim())
      .where((x) => x.isNotEmpty)
      .toSet()
      .take(30);
  return {
    for (final term in terms)
      term: RegExp(
        '(^|[^a-z0-9])${RegExp.escape(term.toLowerCase()).replaceAll(' ', r'\s+')}([^a-z0-9]|\$)',
      ).hasMatch(text),
  };
}

ResumeDraft resumeFromAiImport(String response) {
  final clean = response
      .trim()
      .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
      .replaceFirst(RegExp(r'\s*```$'), '');
  final json = jsonDecode(clean);
  if (json is! Map ||
      json['fields'] is! Map ||
      json['experience'] is! List ||
      json['education'] is! List) {
    throw const FormatException(
      'The imported resume was incomplete. Try pasting its text.',
    );
  }
  final base = ResumeDraft().toJson();
  base['fields'] = {
    for (final k in resumeFields.where(
      (x) => !['letter', 'job', 'keywords', 'company'].contains(x),
    ))
      if (json['fields'].containsKey(k)) k: json['fields'][k],
  };
  base['experience'] = json['experience'];
  base['education'] = json['education'];
  final draft = ResumeDraft.fromJson(base);
  if (draft.text.trim().isEmpty) {
    throw const FormatException('No resume information was found.');
  }
  draft.title = draft.get('name').isEmpty
      ? 'Imported resume'
      : '${draft.get('name')} - resume';
  if (draft.title.length > 120) draft.title = draft.title.substring(0, 120);
  return draft;
}
