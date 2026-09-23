import 'package:flutter/material.dart';
import '../workforce/workforce_style.dart';

bool radiusLabelValid(dynamic v) =>
    v is String &&
    v.isNotEmpty &&
    v.runes.length <= 80 &&
    !v.startsWith(' ') &&
    !v.endsWith(' ') &&
    !v.runes.any(
      (c) =>
          c < 32 ||
          (c >= 127 && c <= 159) ||
          (c >= 0xd800 && c <= 0xdfff) ||
          c == 0x2028 ||
          c == 0x2029 ||
          c == 60 ||
          c == 62,
    );

bool radiusAreaValid(dynamic v, {int maxMeters = 200000}) {
  bool integer(dynamic n, int lo, int hi) => n is int && n >= lo && n <= hi;
  return v is Map &&
      v.length == 4 &&
      radiusLabelValid(v['label']) &&
      integer(v['latitude_micro'], -90000000, 90000000) &&
      integer(v['longitude_micro'], -180000000, 180000000) &&
      integer(v['radius_meters'], 1000, maxMeters);
}

bool radiusAreasValid(dynamic v, {int maxMeters = 200000}) =>
    v is List &&
    v.length <= 10 &&
    v.every((a) => radiusAreaValid(a, maxMeters: maxMeters)) &&
    v
            .map(
              (r) =>
                  '${r['latitude_micro']}:${r['longitude_micro']}:${r['radius_meters']}',
            )
            .toSet()
            .length ==
        v.length;

// Decimal input is converted with integer arithmetic, preserving every stored
// microdegree/metre and rejecting excess precision rather than rounding it.
int? radiusNumber(String text, int decimals, int minimum, int maximum) {
  final value = text.trim();
  if (value.length > 20 ||
      !RegExp('^-?[0-9]+(?:\\.[0-9]{1,$decimals})?\$').hasMatch(value)) {
    return null;
  }
  final negative = value.startsWith('-');
  final parts = (negative ? value.substring(1) : value).split('.');
  final combined = int.tryParse(
    parts.first + (parts.length == 1 ? '' : parts.last).padRight(decimals, '0'),
  );
  if (combined == null) return null;
  final n = negative ? -combined : combined;
  return n >= minimum && n <= maximum ? n : null;
}

String radiusSummary(Map assets, {String key = 'proximities'}) {
  final radii = assets[key];
  if (radii is! List) return 'Target area type: whole countries';
  if (radii.isEmpty) {
    return 'Target area type: radius areas\nNo radius areas selected.';
  }
  return 'Target area type: radius areas\n${radii.map((r) => '${r['label']}: ${(r['radius_meters'] / 1000).toStringAsFixed(3)} km around ${(r['latitude_micro'] / 1000000).toStringAsFixed(6)}, ${(r['longitude_micro'] / 1000000).toStringAsFixed(6)}').join('\n')}\nCoordinates are owner supplied; provider location eligibility remains unchecked.';
}

class RadiusFields extends StatelessWidget {
  const RadiusFields({
    super.key,
    required this.areas,
    required this.enabled,
    required this.onChange,
    required this.onRemove,
    required this.onAdd,
    this.maxMeters = 200000,
    this.planningHint =
        'The 1–200 km range is a KORLIX planning limit. Country exclusions can remove part or all of an area. Provider eligibility and actual coverage still need checking.',
  });
  final int maxMeters;
  final String planningHint;
  final List areas;
  final bool enabled;
  final void Function(Map area, String key, dynamic value) onChange;
  final ValueChanged<Map> onRemove;
  final VoidCallback onAdd;

  Widget _field(
    Map area,
    String key,
    String label,
    String hint,
    int decimals,
    int minimum,
    int maximum,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      key: ValueKey(key),
      initialValue: area[key] == null
          ? ''
          : ((area[key] as num) / (decimals == 6 ? 1000000 : 1000))
                .toStringAsFixed(decimals),
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        helperMaxLines: 3,
        errorMaxLines: 3,
        errorText:
            area[key] is! int || area[key] < minimum || area[key] > maximum
            ? 'Enter a valid value within this range.'
            : null,
      ),
      onChanged: (v) =>
          onChange(area, key, radiusNumber(v, decimals, minimum, maximum)),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Add up to 10 areas using center coordinates and a radius. Use coordinates from a map you trust. Area names are labels; they are not looked up or geocoded.',
      ),
      const SizedBox(height: 8),
      Text(planningHint, style: const TextStyle(color: WfStyle.muted)),
      for (final area in areas)
        Container(
          key: ObjectKey(area),
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: WfStyle.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Radius area',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove radius area',
                    onPressed: enabled ? () => onRemove(area) : null,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              TextFormField(
                key: const ValueKey('radius-label'),
                initialValue: area['label'] as String,
                enabled: enabled,
                decoration: InputDecoration(
                  labelText: 'Area name',
                  helperText: 'Up to 80 characters.',
                  errorMaxLines: 3,
                  errorText: radiusLabelValid(area['label'])
                      ? null
                      : 'Enter a plain area name without leading or trailing spaces.',
                ),
                onChanged: (v) => onChange(area, 'label', v),
              ),
              _field(
                area,
                'latitude_micro',
                'Latitude',
                '−90 to 90; up to 6 decimal places.',
                6,
                -90000000,
                90000000,
              ),
              _field(
                area,
                'longitude_micro',
                'Longitude',
                '−180 to 180; up to 6 decimal places.',
                6,
                -180000000,
                180000000,
              ),
              _field(
                area,
                'radius_meters',
                'Radius (km)',
                '1 to ${maxMeters ~/ 1000} km; up to 3 decimal places.',
                3,
                1000,
                maxMeters,
              ),
            ],
          ),
        ),
      if (!radiusAreasValid(areas, maxMeters: maxMeters) &&
          areas.every((a) => radiusAreaValid(a, maxMeters: maxMeters)))
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text(
            'Remove duplicate areas with the same center and radius.',
            style: TextStyle(color: WfStyle.gold),
          ),
        ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: enabled && areas.length < 10 ? onAdd : null,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add radius area'),
      ),
    ],
  );
}
