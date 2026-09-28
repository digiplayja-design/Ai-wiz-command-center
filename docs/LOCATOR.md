# KORLIX Locator

Locator is a themed, scrollable place-search launcher. It opens real Google Maps
or Apple Maps listings; it does not invent places, ratings, opening hours,
availability, distances, or a map preview.

## User flow

- A prominent Find hospitals shortcut uses the currently selected map and area.
- Search accepts a place/business name or a category. An optional city, street
  address or ZIP/postal code supports searches away from the device location.
- Use my location explicitly requests device location. Permission denial,
  disabled services and timeouts leave manual search available. Map-app nearby
  search also works without requesting location in KORLIX.
- Google Maps and Apple Maps are selectable. iOS defaults to Apple Maps; other
  platforms default to Google Maps. The provider controls listings and directions.
- Health & help: hospitals, urgent care, pharmacies, police stations.
- Everyday essentials: restaurants, groceries, coffee, ATMs, gas, EV charging,
  car washes and tire shops.
- Out & about: hotels, parking, churches and bars. All original categories remain.
- Five deduplicated recent searches are retained only for the current visit;
  Clear removes them. Repeating one uses the currently selected area/provider.

## Integration and lifecycle

`lib/locator/locator_search.dart` builds encoded HTTPS URLs on fixed provider
hosts. Google categorical searches now include selected coordinates in the query;
the previous Google link dropped the acquired coordinates. Apple uses `sll` to
anchor a search, not `ll`, which could turn the query into a pin label. A typed
area takes precedence. Empty, invalid-coordinate and oversized URLs are rejected.

GPS acquisition and external launch are separate user actions so asynchronous
permission/network work does not consume the browser's map-opening gesture.
Repeated launch taps are guarded. Launch failures keep the query and offer retry
or another provider. Changing the typed area invalidates pending GPS results.
Account changes close the route, clear searches and coordinates, and ignore late
callbacks. Leaving the route discards the visit's location and history.

The old blocking `/api/location/record` step is removed from Locator. Coordinates
stay in the local route until the user opens the selected map provider. No new
backend API, dependency, paid Places API, account setting or migration is needed.

## Verification

`flutter test --no-pub test/locator_test.dart test/korlix_action_button_test.dart`
covers encoded international queries, GPS versus manual area precedence, provider
selection, hospital shortcuts, original category preservation, denied permission,
late location results, launch failure/retry, duplicate taps, account changes,
two-column layouts, phone/desktop widths and 200% text in light/dark themes.

Set `KORLIX_LOCATOR_REVIEW` and `KORLIX_FLUTTER_ROOT` to render the actual Locator
widgets. Automated tests inject geolocation and map launchers; real device
permission dialogs and the installed map app require a device smoke check.

Provider references checked for this implementation:
- https://developers.google.com/maps/documentation/urls/get-started
- https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/MapLinks/MapLinks.html
- https://pub.dev/packages/geolocator
