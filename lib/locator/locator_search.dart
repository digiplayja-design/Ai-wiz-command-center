import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

enum LocatorMapProvider { google, apple }

class LocatorPosition {
  const LocatorPosition(this.latitude, this.longitude, {this.accuracy});
  final double latitude, longitude;
  final double? accuracy;
  bool get valid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;
  String get coordinates =>
      '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';
}

String cleanLocatorQuery(String value) {
  var result = value.trim().replaceFirst(
    RegExp(
      r'^(find|show|locate|search|get)\s+(me\s+)?(a\s+|an\s+|the\s+)?',
      caseSensitive: false,
    ),
    '',
  );
  result = result
      .replaceFirst(
        RegExp(r'\s+(near me|around me|nearby)$', caseSensitive: false),
        '',
      )
      .trim();
  return result;
}

Uri locatorSearchUri({
  required String query,
  required LocatorMapProvider provider,
  String area = '',
  LocatorPosition? position,
}) {
  final term = cleanLocatorQuery(query);
  if (term.isEmpty) {
    throw const FormatException('Enter a place name or choose a category.');
  }
  if (position != null && !position.valid) {
    throw const FormatException(
      'Location could not be read. Enter a city or postal code instead.',
    );
  }
  final place = area.trim();
  final specificArea = place.isNotEmpty;
  final search = specificArea ? '$term in $place' : term;
  final uri = provider == LocatorMapProvider.apple
      ? Uri.https('maps.apple.com', '/', {
          'q': search,
          if (!specificArea && position != null) 'sll': position.coordinates,
        })
      : Uri.https('www.google.com', '/maps/search/', {
          'api': '1',
          'query': !specificArea && position != null
              ? '$term near ${position.coordinates}'
              : search,
        });
  if (uri.toString().length > 2048) {
    throw const FormatException('Please shorten the place name or location.');
  }
  return uri;
}

Future<LocatorPosition> requestLocatorPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const FormatException(
      'Location is switched off. Enter a city or postal code, or turn on device location and try again.',
    );
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw const FormatException(
      'Location access was not granted. You can still search by city or postal code, or let your map app choose the area.',
    );
  }
  final result = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.medium,
      timeLimit: Duration(seconds: 15),
    ),
  );
  return LocatorPosition(
    result.latitude,
    result.longitude,
    accuracy: result.accuracy,
  );
}

Future<bool> launchLocatorMap(Uri uri) => launchUrl(
  uri,
  mode: LaunchMode.externalApplication,
  webOnlyWindowName: '_blank',
);
