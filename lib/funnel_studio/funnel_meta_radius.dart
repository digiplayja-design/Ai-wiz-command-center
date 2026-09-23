import 'funnel_radius_fields.dart';

bool metaRadiiValid(dynamic v) => radiusAreasValid(v, maxMeters: 80000);
String metaRadiusSummary(Map assets) =>
    radiusSummary(assets, key: 'custom_locations');
const metaRadiusCategoryNotice =
    'For undecided or special categories, radius drafts can be saved, but KORLIX cannot complete their preparation review yet. Keep every category that applies to your offer. Location restrictions and eligibility require live Meta checks.';

class MetaRadiusFields extends RadiusFields {
  const MetaRadiusFields({
    super.key,
    required super.areas,
    required super.enabled,
    required super.onChange,
    required super.onRemove,
    required super.onAdd,
  }) : super(
         maxMeters: 80000,
         planningHint:
             'The 1–80 km range is a KORLIX planning limit, not a guarantee of Meta eligibility or exact coverage. City lookup, location exclusions and delivery settings remain separate.',
       );
}
