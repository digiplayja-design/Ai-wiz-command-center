import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brain_api.dart';

/// A server response may only open the fixed directions URL for the exact
/// destination the user reviewed. No bearer token crosses to either map app.
Uri? checkedBrainDirections(
  Object? value, {
  required String destination,
  required String mode,
  required bool apple,
}) {
  if (value is! String || value.length > 2048 ||
      !(const {'driving', 'walking', 'transit'}).contains(mode) ||
      destination.length < 2 || destination.length > 300 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(destination)) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
      uri.hasFragment || (uri.hasPort && uri.port != 443)) {
    return null;
  }
  final expected = apple
      ? {'destination': destination, 'mode': mode}
      : {'api': '1', 'destination': destination, 'travelmode': mode};
  Map<String, List<String>> parameters;
  try {
    parameters = uri.queryParametersAll;
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
  if (uri.host != (apple ? 'maps.apple.com' : 'www.google.com') ||
      uri.path != (apple ? '/directions' : '/maps/dir/') ||
      parameters.length != expected.length) {
    return null;
  }
  for (final entry in expected.entries) {
    final values = parameters[entry.key];
    if (values == null || values.length != 1 || values.single != entry.value) {
      return null;
    }
  }
  return uri;
}

class BrainDirectionsScreen extends StatefulWidget {
  const BrainDirectionsScreen({super.key, required this.api,
    required this.beforeOpen, this.initialDestination = '', this.launcher});
  final BrainApi api;
  final Future<void> Function() beforeOpen;
  final String initialDestination;
  final Future<bool> Function(Uri)? launcher;

  @override
  State<BrainDirectionsScreen> createState() => _BrainDirectionsScreenState();
}

class _BrainDirectionsScreenState extends State<BrainDirectionsScreen> {
  late final TextEditingController _destination;
  late final int _ownerRevision;
  bool _checking = true, _allowed = false, _busy = false, _confirming = false;
  Route<dynamic>? _confirmationRoute;
  String _mode = 'driving';
  String? _error;

  bool get _current => mounted && widget.api.auth.session != null &&
      widget.api.auth.revision == _ownerRevision;

  @override
  void initState() {
    super.initState();
    _ownerRevision = widget.api.auth.revision;
    _destination = TextEditingController(text: widget.initialDestination);
    widget.api.auth.addListener(_accountChanged);
    _loadAccess();
  }

  void _accountChanged() {
    if (!mounted || _current) return;
    final route = _confirmationRoute;
    _confirmationRoute = null;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
    setState(() {
      _destination.clear();
      _allowed = false;
      _busy = false;
      _confirming = false;
      _checking = false;
      _error = 'Your account changed. Close this screen and open directions again.';
    });
  }

  Future<void> _loadAccess() async {
    if (!_current) return;
    try {
      final config = await widget.api.json('GET', '/api/brain-projection/config');
      if (!_current) return;
      setState(() {
        _allowed = config['directionsAvailable'] == true;
        if (!_allowed) _error = 'Address routing is not enabled for this account.';
      });
    } catch (error) {
      if (_current) {
        setState(() => _error = error is BrainApiException
            ? error.message : 'Address routing could not be checked. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _open(bool apple) async {
    if (_busy || !_allowed || !_current) return;
    final destination = _destination.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (destination.length < 2 || destination.length > 300) {
      setState(() => _error = 'Enter a full street address or place, up to 300 characters.');
      return;
    }
    final mode = _mode;
    setState(() { _busy = true; _error = null; });
    try {
      final data = await widget.api.json('POST', '/api/brain-projection/directions',
          {'destination': destination, 'mode': mode});
      if (!mounted || !_current) return;
      final uri = checkedBrainDirections(data[apple ? 'appleMapsUrl' : 'googleMapsUrl'],
          destination: destination, mode: mode, apple: apple);
      if (uri == null || data['destination'] != destination ||
          data['mode'] != mode || data['requiresConfirmation'] != true) {
        throw const BrainApiException('The directions could not be verified. Please try again.');
      }
      // Keep the controls locked, but no work is pending while the user reviews
      // the address. Do not animate a loading indicator behind this dialog.
      setState(() => _confirming = true);
      final approved = await showDialog<bool>(context: context, builder: (context) {
        _confirmationRoute = ModalRoute.of(context);
        if (!_current) {
          return const AlertDialog(content: Text('Your account changed. Close this screen and open directions again.'));
        }
        return AlertDialog(
        title: Text('Open ${apple ? 'Apple' : 'Google'} Maps?'),
        content: SingleChildScrollView(child: Text('$destination\n\n${mode[0].toUpperCase()}${mode.substring(1)} directions. Check the address match in Maps before starting your route.')),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Open directions'))],
        );
      });
      _confirmationRoute = null;
      if (mounted) setState(() => _confirming = false);
      if (approved != true || !_current) return;
      await widget.beforeOpen();
      if (!_current) return;
      final launcher = widget.launcher;
      final opened = launcher == null
          ? await launchUrl(uri, mode: LaunchMode.externalApplication)
          : await launcher(uri);
      if (!opened) {
        throw const BrainApiException('Maps could not open. Try the other map app.');
      }
    } catch (error) {
      if (_current) {
        setState(() => _error = error is BrainApiException
            ? error.message : 'Directions could not open. Please try again.');
      }
    } finally {
      if (mounted) setState(() { _busy = false; _confirming = false; });
    }
  }

  @override
  void dispose() {
    widget.api.auth.removeListener(_accountChanged);
    _destination.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Address directions')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(24), children: [
      const Icon(Icons.route_rounded, size: 48, color: Color(0xff7de4ff)),
      const SizedBox(height: 16),
      Text('Where would you like to go?', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 10),
      const Text('Enter the street, city, and postal code. Choose your map app to review the route from your current location.'),
      const SizedBox(height: 24),
      if (_checking) const Center(child: CircularProgressIndicator()),
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 16),
        child: Text(_error!, style: const TextStyle(color: Color(0xffffb4ab)))),
      TextField(controller: _destination, maxLength: 300, minLines: 2, maxLines: 4,
        enabled: _allowed && !_busy,
        decoration: const InputDecoration(labelText: 'Full destination',
          hintText: 'Street address, city, state, postal code', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final entry in const {'driving':'Drive','walking':'Walk','transit':'Transit'}.entries)
          ChoiceChip(label: Text(entry.value), selected: _mode == entry.key,
            onSelected: _busy || !_allowed ? null : (_) => setState(() => _mode = entry.key)),
      ]),
      const SizedBox(height: 24),
      FilledButton.icon(onPressed: _allowed && !_busy ? () => _open(false) : null,
        icon: const Icon(Icons.map_outlined), label: const Text('Google Maps directions')),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: _allowed && !_busy ? () => _open(true) : null,
        icon: const Icon(Icons.navigation_outlined), label: const Text('Apple Maps directions')),
      if (_busy && !_confirming) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      const SizedBox(height: 16),
      const Text('Rici pauses before Maps opens. Return to Brain + Voice and tap Resume when you are ready.'),
      if (!_checking && !_allowed && _current) TextButton(onPressed: () {
        setState(() { _checking = true; _error = null; }); _loadAccess();
      }, child: const Text('Check access again')),
    ])),
  );
}
