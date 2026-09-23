import 'funnel_radius_fields.dart';

bool googleRadiusLabelValid(dynamic v) => radiusLabelValid(v);
bool googleRadiusValid(dynamic v) => radiusAreaValid(v);
bool googleRadiiValid(dynamic v) => radiusAreasValid(v);
int? googleRadiusNumber(String text, int decimals, int minimum, int maximum) =>
    radiusNumber(text, decimals, minimum, maximum);
String googleRadiusSummary(Map assets) => radiusSummary(assets);

class GoogleRadiusFields extends RadiusFields {
  const GoogleRadiusFields({
    super.key,
    required super.areas,
    required super.enabled,
    required super.onChange,
    required super.onRemove,
    required super.onAdd,
  });
}
