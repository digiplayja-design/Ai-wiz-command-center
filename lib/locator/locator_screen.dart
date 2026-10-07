import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'locator_search.dart';
import '../theme/korlix_action_button.dart';
import '../theme/korlix_action_grid.dart';
import '../theme/korlix_theme.dart';

class LocatorCategory {
  const LocatorCategory(this.name, this.query, this.icon);
  final String name, query;
  final IconData icon;
}

const locatorCare = [
  LocatorCategory('Hospitals', 'hospitals', Icons.local_hospital_rounded),
  LocatorCategory(
    'Urgent care',
    'urgent care',
    Icons.health_and_safety_outlined,
  ),
  LocatorCategory('Pharmacies', 'pharmacies', Icons.local_pharmacy_outlined),
  LocatorCategory(
    'Police stations',
    'police stations',
    Icons.local_police_outlined,
  ),
];
const locatorEveryday = [
  LocatorCategory('Restaurants', 'restaurants', Icons.restaurant_rounded),
  LocatorCategory(
    'Grocery stores',
    'grocery stores',
    Icons.local_grocery_store_outlined,
  ),
  LocatorCategory('Coffee shops', 'coffee shops', Icons.local_cafe_outlined),
  LocatorCategory('ATMs', 'ATMs', Icons.account_balance_outlined),
  LocatorCategory(
    'Gas stations',
    'gas stations',
    Icons.local_gas_station_outlined,
  ),
  LocatorCategory(
    'EV charging',
    'EV charging stations',
    Icons.ev_station_outlined,
  ),
  LocatorCategory('Car washes', 'car washes', Icons.local_car_wash_outlined),
  LocatorCategory('Tire shops', 'tire shops', Icons.tire_repair_rounded),
];
const locatorExplore = [
  LocatorCategory('Hotels', 'hotels', Icons.hotel_outlined),
  LocatorCategory('Parking', 'parking', Icons.local_parking_rounded),
  LocatorCategory('Churches', 'churches', Icons.church_outlined),
  LocatorCategory('Bars', 'bars', Icons.local_bar_outlined),
];

class KorlixLocatorScreen extends StatefulWidget {
  const KorlixLocatorScreen({
    super.key,
    this.locate = requestLocatorPosition,
    this.openMap = launchLocatorMap,
    this.sessionChanges,
    this.isSessionCurrent,
  });
  final Future<LocatorPosition> Function() locate;
  final Future<bool> Function(Uri) openMap;
  final Listenable? sessionChanges;
  final bool Function()? isSessionCurrent;
  @override
  State<KorlixLocatorScreen> createState() => _KorlixLocatorScreenState();
}

class _KorlixLocatorScreenState extends State<KorlixLocatorScreen> {
  final _query = TextEditingController(), _area = TextEditingController();
  final _scroll = ScrollController();
  final _recent = <String>[];
  late LocatorMapProvider _provider;
  LocatorPosition? _position;
  String? _error, _notice;
  bool _locating = false, _opening = false, _expired = false;
  int _locationRequest = 0;
  bool get _valid => !_expired && (widget.isSessionCurrent?.call() ?? true);
  String get _mapName =>
      _provider == LocatorMapProvider.google ? 'Google Maps' : 'Apple Maps';
  @override
  void initState() {
    super.initState();
    _provider = defaultTargetPlatform == TargetPlatform.iOS
        ? LocatorMapProvider.apple
        : LocatorMapProvider.google;
    widget.sessionChanges?.addListener(_checkSession);
  }

  void _checkSession() {
    if (!mounted || _valid) return;
    _expired = true;
    _locationRequest++;
    _position = null;
    _query.clear();
    _area.clear();
    _recent.clear();
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      Navigator.of(context).popUntil((r) => r == route);
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _locationRequest++;
    widget.sessionChanges?.removeListener(_checkSession);
    _query.dispose();
    _area.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _manualArea(String _) {
    _locationRequest++;
    setState(() {
      _position = null;
      _locating = false;
      _error = null;
      _notice = null;
    });
  }

  Future<void> _locate() async {
    if (_locating || _opening || !_valid) return;
    final request = ++_locationRequest;
    setState(() {
      _locating = true;
      _error = null;
      _notice = null;
    });
    try {
      final position = await widget.locate().timeout(
        const Duration(seconds: 20),
      );
      if (!mounted || !_valid || request != _locationRequest) return;
      if (!position.valid) {
        throw const FormatException(
          'Location could not be read. Enter a city or postal code instead.',
        );
      }
      setState(() {
        _position = position;
        _area.clear();
      });
    } catch (error) {
      if (mounted && _valid && request == _locationRequest) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'Could not get your location. Enter a city or postal code, or try again.',
        );
      }
    } finally {
      if (mounted && request == _locationRequest) {
        setState(() => _locating = false);
      }
    }
  }

  Future<void> _open([String? category]) async {
    if (_opening || _locating || !_valid) return;
    final text = category ?? _query.text;
    Uri uri;
    try {
      uri = locatorSearchUri(
        query: text,
        provider: _provider,
        area: _area.text,
        position: _position,
      );
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      _top();
      return;
    }
    final query = cleanLocatorQuery(text);
    final providerName = _mapName;
    setState(() {
      _opening = true;
      _error = null;
      _notice = null;
      _query.text = query;
    });
    try {
      // Launch directly from the tap; permission/network waits happen separately.
      final opened = await widget.openMap(uri);
      if (!mounted || !_valid) return;
      setState(() {
        if (opened) {
          _recent.removeWhere((q) => q.toLowerCase() == query.toLowerCase());
          _recent.insert(0, query);
          if (_recent.length > 5) _recent.removeLast();
          _notice =
              'Opened $providerName for “$query”. Choose a listing there for details and directions.';
        } else {
          _error =
              'Maps did not open. Try the search button again or choose the other map provider.';
        }
      });
    } catch (_) {
      if (mounted && _valid) {
        setState(
          () => _error =
              'Maps could not open. Try again or choose the other map provider.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
      if (mounted && _error != null) _top();
    }
  }

  void _top() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Widget _categories(
    String title,
    String description,
    IconData icon,
    List<LocatorCategory> categories,
  ) => KorlixActionSection(
    title: title,
    description: description,
    icon: icon,
    children: [
      for (final c in categories)
        KorlixActionButton(
          label: c.name,
          icon: c.icon,
          tile: true,
          onPressed: _opening || _locating ? null : () => _open(c.query),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final accuracy = _position?.accuracy;
    final locationLabel = _locating
        ? 'Finding your location…'
        : _position != null
        ? 'Device location ready${accuracy != null && accuracy.isFinite && accuracy > 0 ? ' · reported accuracy ${accuracy.round()} m' : ''}'
        : _area.text.trim().isNotEmpty
        ? 'Search around ${_area.text.trim()}'
        : 'Your map app will choose the nearby area.';
    return Scaffold(
      appBar: AppBar(title: const Text('KORLIX Locator')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [skin.panelSoft, skin.panelDeep],
                      ),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: skin.primary.withValues(alpha: .35),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: skin.primary.withValues(alpha: .07),
                          blurRadius: 25,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [skin.primary, skin.secondary],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: skin.primary.withValues(alpha: .16),
                                offset: const Offset(0, 6),
                                blurRadius: 15,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.explore_rounded,
                            size: 36,
                            color: skin.textOnAccent,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Find the places you need.',
                          style: TextStyle(
                            color: skin.text,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Care, essentials, and everyday stops. Search nearby or explore another city.',
                          style: TextStyle(color: skin.mutedText, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  KorlixActionButton(
                    label: 'Find hospitals',
                    subtitle: 'Open $_mapName with your selected area',
                    icon: Icons.local_hospital_rounded,
                    accent: skin.secondary,
                    expand: true,
                    onPressed: _opening || _locating
                        ? null
                        : () => _open('hospitals'),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    key: const Key('locator-query'),
                    controller: _query,
                    maxLength: 100,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _open(),
                    decoration: InputDecoration(
                      labelText: 'What are you looking for?',
                      hintText: 'Hospital, place name, or category',
                      counterText: '',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _opening
                            ? null
                            : () => setState(_query.clear),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('locator-area'),
                    controller: _area,
                    maxLength: 100,
                    onChanged: _manualArea,
                    decoration: const InputDecoration(
                      labelText: 'City, address, or ZIP / postal code',
                      hintText: 'Optional · e.g. Columbus, Ohio',
                      counterText: '',
                      prefixIcon: Icon(Icons.location_city_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  KorlixActionButton(
                    label: _locating
                        ? 'Finding location…'
                        : _position != null
                        ? 'Refresh my location'
                        : 'Use my location',
                    icon: Icons.my_location_rounded,
                    busy: _locating,
                    expand: true,
                    onPressed: _locating || _opening ? null : _locate,
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      locationLabel,
                      style: TextStyle(
                        color: _position != null
                            ? skin.primary
                            : skin.mutedText,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                  if (_position != null || _area.text.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _opening
                            ? null
                            : () {
                                _area.clear();
                                _manualArea('');
                              },
                        child: const Text('Let maps choose the area'),
                      ),
                    ),
                  const SizedBox(height: 18),
                  KorlixActionGrid(
                    compact: true,
                    children: [
                      for (final provider in LocatorMapProvider.values)
                        KorlixActionButton(
                          label: provider == LocatorMapProvider.google
                              ? 'Google Maps'
                              : 'Apple Maps',
                          selected: _provider == provider,
                          expand: true,
                          onPressed: _opening
                              ? null
                              : () => setState(() {
                                  _provider = provider;
                                  _error = null;
                                  _notice = null;
                                }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  KorlixActionButton(
                    label: _opening ? 'Opening maps…' : 'Search in $_mapName',
                    icon: Icons.north_east_rounded,
                    expand: true,
                    busy: _opening,
                    onPressed: _opening || _locating ? null : () => _open(),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Listings, photos, hours, and directions open in your chosen map app. Your selected location is shared with that provider when you search.',
                    style: TextStyle(
                      color: skin.mutedText,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  if (_error != null || _notice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error ?? _notice!,
                          style: TextStyle(
                            color: _error == null ? skin.primary : skin.danger,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  if (_recent.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Recent searches · this visit',
                            style: TextStyle(
                              color: skin.mutedText,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(_recent.clear),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final query in _recent)
                          ActionChip(
                            label: Text(query),
                            onPressed: _opening || _locating
                                ? null
                                : () => _open(query),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 30),
                  _categories(
                    'Health & help',
                    'Hospitals, everyday care, and local assistance.',
                    Icons.local_hospital_outlined,
                    locatorCare,
                  ),
                  const SizedBox(height: 28),
                  _categories(
                    'Everyday essentials',
                    'Food, fuel, money, and stops along the way.',
                    Icons.local_mall_outlined,
                    locatorEveryday,
                  ),
                  const SizedBox(height: 28),
                  _categories(
                    'Out & about',
                    'Find a place to stay, park, meet, or unwind.',
                    Icons.explore_outlined,
                    locatorExplore,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
