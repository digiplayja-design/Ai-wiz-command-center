/// Ready-to-use sizes for a complete logo or its standalone profile mark.
class LogoExportPreset {
  const LogoExportPreset({
    required this.id,
    required this.label,
    required this.width,
    required this.height,
    this.iconOnly = false,
  });
  final String id, label;
  final int width, height;
  final bool iconOnly;
}

const logoExportPresets = <LogoExportPreset>[
  LogoExportPreset(
    id: 'standard',
    label: 'Standard',
    width: 2400,
    height: 1600,
  ),
  LogoExportPreset(id: 'wide', label: 'Wide', width: 2400, height: 1200),
  LogoExportPreset(id: 'square', label: 'Square', width: 1600, height: 1600),
  LogoExportPreset(
    id: 'profile',
    label: 'Profile icon',
    width: 1024,
    height: 1024,
    iconOnly: true,
  ),
];
