import 'package:flutter/material.dart';

/// Button faces have their own color identity, independent of page themes.
/// Endpoints and the foreground are curated together for readable gradients.
class KorlixButtonColors {
  const KorlixButtonColors({
    required this.id,
    required this.start,
    required this.end,
    this.foreground = Colors.white,
  });

  final String id;
  final Color start, end, foreground;
  List<Color> get gradientColors => [start, end];
}

const korlixButtonPalettes = <KorlixButtonColors>[
  KorlixButtonColors(
    id: 'blue',
    start: Color(0xff1f5dcf),
    end: Color(0xff1646af),
  ),
  KorlixButtonColors(
    id: 'teal',
    start: Color(0xff087b70),
    end: Color(0xff075b67),
  ),
  KorlixButtonColors(
    id: 'violet',
    start: Color(0xff7a43cd),
    end: Color(0xff572db2),
  ),
  KorlixButtonColors(
    id: 'coral',
    start: Color(0xffbc453a),
    end: Color(0xff99283e),
  ),
  KorlixButtonColors(
    id: 'amber',
    start: Color(0xfffdbf52),
    end: Color(0xffe69a26),
    foreground: Color(0xff352100),
  ),
  KorlixButtonColors(
    id: 'rose',
    start: Color(0xffb63775),
    end: Color(0xff8f2765),
  ),
  KorlixButtonColors(
    id: 'indigo',
    start: Color(0xff465bcd),
    end: Color(0xff33369c),
  ),
  KorlixButtonColors(
    id: 'emerald',
    start: Color(0xff147d55),
    end: Color(0xff0d6244),
  ),
  KorlixButtonColors(
    id: 'cyan',
    start: Color(0xff0b77a2),
    end: Color(0xff085879),
  ),
  KorlixButtonColors(
    id: 'danger',
    start: Color(0xffbc2637),
    end: Color(0xff8f1528),
  ),
];

/// Feature names keep the same color when the surrounding theme changes.
/// Recognizable icons provide aliases for translated labels. Unknown features
/// use a deterministic hash instead of the runtime-dependent String hashCode.
KorlixButtonColors korlixButtonColorsFor(
  String label, {
  IconData? icon,
  bool destructive = false,
}) {
  final normalized = label.toLowerCase().trim();
  final key = normalized.replaceAll(RegExp(r'[^a-z0-9à-ÿ]'), '');
  final destructiveLabel = RegExp(
    r'^(delete\b|discard\b|stop\b|end call\b|hang up\b|disconnect\b|cancel recording\b)',
  ).hasMatch(normalized);
  final destructiveIcon = const [
    Icons.stop,
    Icons.stop_rounded,
    Icons.stop_circle,
    Icons.stop_circle_outlined,
    Icons.stop_circle_rounded,
    Icons.delete,
    Icons.delete_outline,
    Icons.delete_outline_rounded,
    Icons.delete_forever,
    Icons.call_end,
    Icons.call_end_rounded,
  ].contains(icon);
  if (destructive || destructiveLabel || destructiveIcon) {
    return korlixButtonPalettes.last;
  }

  final id = switch (key) {
    'continue' ||
    'send' ||
    'sending' ||
    'ask' ||
    'preguntar' ||
    'demander' ||
    'upload' ||
    'workforce' ||
    'taxprep' ||
    'fixmycreditreport' ||
    'documents' => 'blue',
    'save' || 'savepng' || 'fieldproof' || 'voice' || 'voicerecorder' => 'teal',
    'liveconvo' ||
    'knova' ||
    'moretools' ||
    'imagineapicture' ||
    'openimaginestudio' ||
    'imaginestudio' ||
    'logostudio' ||
    'aivisibility' => 'violet',
    'createvideo' ||
    'createmovie' ||
    'musicstudio' ||
    'thepodandyou' => 'coral',
    'cameraask' ||
    'businessdirectory' ||
    'korlixbusinessdirectory' ||
    'bookkeeping2027' ||
    'korlix2meetu' ||
    'scheduling' ||
    'babyblend' => 'amber',
    'improvemypicture' ||
    'voicescribe' ||
    'contractradar' ||
    'virtualcloset' ||
    'contactscrm' ||
    'write' => 'rose',
    'copybox' ||
    'createanapp' ||
    'appstudio' ||
    'cybersecuritydefender' => 'indigo',
    'inventorystudio' || 'payroll' || 'funnelstudio' => 'emerald',
    'emailenhancer' ||
    'seoagent' ||
    'studystudio' ||
    'studyhelp' ||
    'étudier' ||
    'korlixsocial' ||
    'social' => 'cyan',
    _ => null,
  };
  if (id != null) {
    return korlixButtonPalettes.firstWhere((palette) => palette.id == id);
  }

  final iconId = switch (icon) {
    Icons.upload_file_rounded ||
    Icons.upload_rounded ||
    Icons.arrow_upward_rounded => 'blue',
    Icons.mic_rounded ||
    Icons.mic ||
    Icons.fact_check_outlined ||
    Icons.save_outlined ||
    Icons.save_rounded => 'teal',
    Icons.center_focus_strong_rounded || Icons.camera_alt_outlined => 'amber',
    Icons.content_copy_rounded ||
    Icons.code_rounded ||
    Icons.app_shortcut_rounded => 'indigo',
    Icons.auto_fix_high_rounded ||
    Icons.graphic_eq_rounded ||
    Icons.checkroom_rounded => 'rose',
    Icons.movie_creation_outlined || Icons.music_note_rounded => 'coral',
    Icons.auto_awesome_mosaic_rounded || Icons.polyline_outlined => 'violet',
    Icons.school_outlined || Icons.mark_email_read_outlined => 'cyan',
    Icons.inventory_2_outlined || Icons.payments_outlined => 'emerald',
    _ => null,
  };
  if (iconId != null) {
    return korlixButtonPalettes.firstWhere((palette) => palette.id == iconId);
  }

  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  // The final, destructive palette is reserved for explicit destructive intent.
  return korlixButtonPalettes[hash % (korlixButtonPalettes.length - 1)];
}
