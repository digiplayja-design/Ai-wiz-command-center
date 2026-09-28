part of 'inventory_screen.dart';

extension _InventoryViews on _InventoryScreenState {
  bool get dark => Theme.of(context).brightness == Brightness.dark;
  Color get ink => dark ? const Color(0xFFF1F4FA) : const Color(0xFF1D2842);
  Color get muted => dark ? const Color(0xFFB1BDD1) : const Color(0xFF65718A);
  Color get surface => dark ? const Color(0xFF172137) : Colors.white;
  Color get canvas => dark ? const Color(0xFF0D1525) : const Color(0xFFF4F6FB);
  Color get accent => dark ? const Color(0xFFBDB1FF) : const Color(0xFF6650B8);
  Color get line => dark ? const Color(0xFF303C54) : const Color(0xFFE2E7F1);
  TextStyle heading(double size) => TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w800,
    letterSpacing: -.7,
    color: ink,
    height: 1.15,
  );
  Widget panel(Widget child, {EdgeInsets padding = const EdgeInsets.all(22)}) =>
      Container(
        padding: padding,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: line),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.08 : 0.025),
              blurRadius: 25,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: child,
      );
  Widget badge(String label, {Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: (color ?? accent).withValues(alpha: .1),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: color ?? accent,
      ),
    ),
  );
  Widget action(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    bool primary = false,
  }) => primary
      ? FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: dark ? const Color(0xFF1B1435) : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          ),
        )
      : OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: ink,
            side: BorderSide(color: line),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        );
  Widget _buildWorkspace() {
    if (_locked) {
      return Scaffold(
        appBar: AppBar(title: const Text('KORLIX Inventory')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 44),
                const SizedBox(height: 16),
                const Text(
                  'Your sign-in changed. Reopen Inventory to continue.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close Inventory'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final content = <Widget>[
      if (_error != null || _notice != null) _message(),
      if (_pending != null) _pendingPanel(),
      if (_tab == 'discover')
        _detail.isEmpty ? _discovery() : _itemView()
      else if (_tab == 'locations')
        _locationsView()
      else if (_tab == 'orders')
        _ordersView()
      else if (_tab == 'partners')
        _partnersView()
      else if (_tab == 'activity')
        _activityView()
      else
        _reportsView(),
    ];
    return Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset(
                'assets/branding/korlix_mini_mark.png',
                width: 30,
                height: 30,
                errorBuilder: (_, e, s) =>
                    Icon(Icons.inventory_2_outlined, color: accent),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(child: Text('KORLIX Inventory', style: heading(19))),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Inventory',
            onPressed: blocked ? null : () => _work(_load),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy || _loading)
              LinearProgressIndicator(minHeight: 2, color: accent),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 1050;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (wide) _sidebar(),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            wide ? 30 : 16,
                            18,
                            wide ? 30 : 16,
                            36,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1380),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!wide) _navigation(false),
                                  if (!wide) const SizedBox(height: 20),
                                  ...content,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar() => SizedBox(
    width: 225,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 25, 0, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 0, 16),
            child: Text(
              'WORKSPACE',
              style: TextStyle(
                color: muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ),
          _navigation(true),
          const Spacer(),
          panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, color: accent),
                const SizedBox(height: 8),
                Text(
                  'Your inventory, private.',
                  style: TextStyle(color: ink, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Search your locations around the world.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
          ),
        ],
      ),
    ),
  );
  Widget _navigation(bool vertical) {
    const tabs = {
      'discover': ('Discover', Icons.grid_view_rounded),
      'locations': ('Locations', Icons.public),
      'orders': ('Orders', Icons.receipt_long_outlined),
      'partners': ('Contacts', Icons.people_outline),
      'activity': ('Activity', Icons.history_rounded),
      'reports': ('Reports & import', Icons.insights_outlined),
    };
    final children = tabs.entries
        .map(
          (e) => Padding(
            padding: EdgeInsets.only(bottom: vertical ? 7 : 0),
            child: Material(
              color: _tab == e.key
                  ? accent.withValues(alpha: .13)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  _update(() {
                    _tab = e.key;
                    _detail = {};
                  });
                  if (e.key == 'activity') _work(_loadEvents);
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: vertical ? 16 : 12,
                    vertical: 13,
                  ),
                  child: Row(
                    mainAxisSize: vertical
                        ? MainAxisSize.max
                        : MainAxisSize.min,
                    children: [
                      Icon(
                        e.value.$2,
                        size: 19,
                        color: _tab == e.key ? accent : muted,
                      ),
                      const SizedBox(width: 9),
                      Text(
                        e.value.$1,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _tab == e.key ? accent : muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        )
        .toList();
    return vertical
        ? Column(children: children)
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: children),
          );
  }

  Widget _message() => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: (_error != null ? Colors.deepOrange : Colors.teal).withValues(
          alpha: .09,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _error != null ? Icons.info_outline : Icons.check_circle_outline,
            size: 20,
            color: ink,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_error ?? _notice ?? '', style: TextStyle(color: ink)),
          ),
          IconButton(
            tooltip: 'Dismiss notice',
            onPressed: () => _update(() {
              _error = null;
              _notice = null;
            }),
            icon: const Icon(Icons.close, size: 17),
          ),
        ],
      ),
    ),
  );
  Widget _pendingPanel() => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('One change needs confirmation', style: heading(18)),
          const SizedBox(height: 8),
          const Text(
            'Retry this same change to find out whether it was saved. Its request ID prevents duplicate stock movements.',
          ),
          const SizedBox(height: 12),
          action(
            'Confirm pending change',
            Icons.sync,
            blocked ? null : () => _work(() => _change(_pending!)),
            primary: true,
          ),
        ],
      ),
    ),
  );
  Widget _discovery() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LayoutBuilder(
        builder: (context, c) => Container(
          padding: EdgeInsets.all(c.maxWidth < 500 ? 22 : 32),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? [const Color(0xFF242846), const Color(0xFF153634)]
                  : [const Color(0xFFECE8FF), const Color(0xFFE3F5EE)],
            ),
            border: Border.all(color: line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: badge('INVENTORY, IN SYNC')),
                        if (c.maxWidth < 620)
                          const InventorySculpture(size: 85),
                      ],
                    ),
                    const SizedBox(height: 17),
                    Text(
                      'Find it.\nKnow it. Move it.',
                      style: heading(c.maxWidth < 500 ? 31 : 43),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Every item. Every location.\nOne beautifully simple workspace.',
                      style: TextStyle(fontSize: 15, height: 1.5, color: muted),
                    ),
                    const SizedBox(height: 22),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        action(
                          'Add item',
                          Icons.add,
                          editable ? () => _editProduct() : null,
                          primary: true,
                        ),
                        action(
                          'K-Nova Live',
                          Icons.graphic_eq,
                          editable ? _voice : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (c.maxWidth >= 620) const InventorySculpture(size: 240),
            ],
          ),
        ),
      ),
      const SizedBox(height: 22),
      _searchPanel(),
      const SizedBox(height: 20),
      _stats(),
      if (_scan.isNotEmpty) ...[const SizedBox(height: 18), _scanView()],
      const SizedBox(height: 25),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        runSpacing: 12,
        children: [
          Text(
            _query.text.isEmpty ? 'Your collection' : 'Search results',
            style: heading(24),
          ),
          Text(
            '${_results['total'] ?? 0} matching items',
            style: TextStyle(color: muted),
          ),
          ...{
            'all': 'All items',
            'available': 'In stock',
            'low': 'Low stock',
            'expired': 'Expired',
          }.entries.map(
            (e) => ChoiceChip(
              label: Text(e.value),
              selected: _filter == e.key,
              onSelected: blocked
                  ? null
                  : (_) {
                      _update(() => _filter = e.key);
                      _work(() => _search());
                    },
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      if (_loading)
        const Padding(
          padding: EdgeInsets.all(50),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (inventoryItems(_results['items']).isEmpty)
        _empty(
          _query.text.isEmpty
              ? 'Make room for what’s next.'
              : 'No matching items yet.',
          _query.text.isEmpty
              ? 'Add your first item and a location. Then receive stock, add photos and let K-Nova find it.'
              : 'Try a shorter name, SKU, serial or picture. Geographic searches include your recorded locations.',
          icon: Icons.inventory_2_outlined,
          button: _query.text.isEmpty
              ? action(
                  'Add your first item',
                  Icons.add,
                  editable ? () => _editProduct() : null,
                  primary: true,
                )
              : null,
        )
      else
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 1080
                ? 4
                : c.maxWidth >= 720
                ? 3
                : c.maxWidth >= 510
                ? 2
                : 1;
            final width = (c.maxWidth - 16 * (cols - 1)) / cols;
            return Wrap(
              spacing: 16,
              runSpacing: 18,
              children: inventoryItems(_results['items'])
                  .map(
                    (p) => SizedBox(
                      width: width,
                      child: _ProductCard(
                        product: p,
                        onTap: () => _openItem(p['id']),
                        dark: dark,
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      if (inventoryItems(_results['items']).length <
          inventoryNumber(_results['total']))
        Padding(
          padding: const EdgeInsets.only(top: 22),
          child: Center(
            child: action(
              'Load more matches',
              Icons.expand_more,
              blocked
                  ? null
                  : () => _work(
                      () => _search(
                        offset: inventoryItems(_results['items']).length,
                        append: true,
                      ),
                    ),
            ),
          ),
        ),
    ],
  );
  Widget _stats() {
    final summary = inventoryMap(_workspace['summary']);
    final stats = [
      ('Items', summary['products'] ?? 0, Icons.inventory_2_outlined),
      ('Units on hand', summary['units'] ?? 0, Icons.layers_outlined),
      ('Locations', summary['locations'] ?? 0, Icons.location_on_outlined),
      ('Reserved', summary['reserved'] ?? 0, Icons.bookmark_border),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth < 650 ? 2 : 4;
        final width = (c.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: stats
              .map(
                (s) => SizedBox(
                  width: width,
                  child: panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(s.$3, size: 18, color: accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.$1,
                                style: TextStyle(color: muted, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 13),
                        Text(inventoryQuantity(s.$2), style: heading(27)),
                      ],
                    ),
                    padding: const EdgeInsets.all(18),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _searchPanel() {
    final countries =
        locations
            .map((l) => '${inventoryMap(l['data'])['country']}')
            .toSet()
            .toList()
          ..sort();
    final regions =
        locations
            .where((l) => inventoryMap(l['data'])['country'] == _country)
            .map((l) => '${inventoryMap(l['data'])['region']}')
            .toSet()
            .toList()
          ..sort();
    return panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _query,
            onChanged: _typed,
            onSubmitted: (_) => _work(() => _search()),
            enabled: !_locked,
            decoration: InputDecoration(
              hintText: 'Search any part of a name, SKU or serial…',
              prefixIcon: Icon(Icons.search_rounded, color: accent),
              suffixIcon: IconButton(
                tooltip: 'Search Inventory',
                onPressed: blocked ? null : () => _work(() => _search()),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
              filled: true,
              fillColor: canvas,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(17),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(20),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final e in {
                'statewide': 'Statewide',
                'nationwide': 'Nationwide',
                'international': 'International',
              }.entries)
                ChoiceChip(
                  avatar: Icon(
                    e.key == 'international'
                        ? Icons.public
                        : Icons.location_on_outlined,
                    size: 16,
                  ),
                  label: Text(e.value),
                  selected: _scope == e.key,
                  onSelected: blocked
                      ? null
                      : (_) {
                          _update(() {
                            _scope = e.key;
                            if (_country.isEmpty && countries.isNotEmpty) {
                              _country = countries.first;
                            }
                            if (_region.isEmpty && regions.isNotEmpty) {
                              _region = regions.first;
                            }
                          });
                          _work(() => _search());
                        },
                ),
              if (_scope != 'international')
                SizedBox(
                  width: 145,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('country-$_country'),
                    isExpanded: true,
                    initialValue: countries.contains(_country)
                        ? _country
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Country',
                      isDense: true,
                    ),
                    items: countries
                        .map(
                          (x) => DropdownMenuItem(
                            value: x,
                            child: Text(_countryName(x)),
                          ),
                        )
                        .toList(),
                    onChanged: blocked
                        ? null
                        : (x) {
                            _update(() {
                              _country = x ?? '';
                              final matches = locations
                                  .where(
                                    (l) =>
                                        inventoryMap(l['data'])['country'] ==
                                        _country,
                                  )
                                  .toList();
                              _region = matches.isEmpty
                                  ? ''
                                  : '${inventoryMap(matches.first['data'])['region']}';
                            });
                            _work(() => _search());
                          },
                  ),
                ),
              if (_scope == 'statewide')
                SizedBox(
                  width: 185,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('region-$_country-$_region'),
                    isExpanded: true,
                    initialValue: regions.contains(_region) ? _region : null,
                    decoration: const InputDecoration(
                      labelText: 'State / province',
                      isDense: true,
                    ),
                    items: regions
                        .map(
                          (x) => DropdownMenuItem(
                            value: x,
                            child: Text(x, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: blocked
                        ? null
                        : (x) {
                            _update(() => _region = x ?? '');
                            _work(() => _search());
                          },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              action('Ask K-Nova', Icons.mic_none, editable ? _voice : null),
              action(
                'Search by picture',
                Icons.image_search,
                editable ? () => _recognize('picture') : null,
              ),
              action(
                'Scan serial',
                Icons.qr_code_scanner,
                editable ? () => _recognize('serial') : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Searches your private inventory across recorded locations. External supplier catalogs are not connected.',
            style: TextStyle(color: muted, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  String _countryName(String code) =>
      const {
        'US': 'United States',
        'JM': 'Jamaica',
        'GB': 'United Kingdom',
        'CA': 'Canada',
        'AU': 'Australia',
        'DE': 'Germany',
        'FR': 'France',
        'IN': 'India',
        'CN': 'China',
        'MX': 'Mexico',
        'BR': 'Brazil',
        'NG': 'Nigeria',
        'ZA': 'South Africa',
      }[code] ??
      code;
  Widget _scanView() {
    final ready = _scan['state'] == 'ready', d = inventoryMap(_scan['result']);
    final terms = <String>{
      if ('${d['serial'] ?? ''}'.isNotEmpty) '${d['serial']}',
      if ('${d['barcode'] ?? ''}'.isNotEmpty) '${d['barcode']}',
      if ('${d['name'] ?? ''}'.isNotEmpty) '${d['name']}',
      ...((d['terms'] as List?) ?? []).map((x) => '$x'),
    };
    return panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ready
                      ? 'Picture recognized · review your search'
                      : _scan['state'] == 'failed'
                      ? 'Picture could not be read'
                      : 'KORLIX is reading your picture…',
                  style: heading(17),
                ),
              ),
              IconButton(
                tooltip: 'Close picture result',
                onPressed: _scan['state'] == 'preparing'
                    ? null
                    : () => _update(() => _scan = {}),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (_scan['state'] == 'preparing') const LinearProgressIndicator(),
          const SizedBox(height: 10),
          if (ready) ...[
            Text(
              '${d['uncertainty'] ?? 'Check these terms before searching.'}',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: terms
                  .map(
                    (term) => ActionChip(
                      label: Text(term),
                      onPressed: () {
                        _query.text = term;
                        _work(() => _search());
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 9),
            Text(
              'Tap a term to search. Edit it in the search box if needed.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ] else if (_scan['state'] == 'failed')
            Text(
              '${_scan['message'] ?? 'Try a clearer photo. Any reserved generation credit was returned.'}',
            )
          else
            const Text('This can take a minute. Stock will not change.'),
        ],
      ),
    );
  }

  Widget _empty(
    String title,
    String body, {
    IconData icon = Icons.inbox_outlined,
    Widget? button,
  }) => panel(
    Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(icon, size: 40, color: accent),
            const SizedBox(height: 18),
            Text(title, style: heading(22), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, height: 1.6),
              ),
            ),
            if (button != null) ...[const SizedBox(height: 20), button],
          ],
        ),
      ),
    ),
  );
  Widget _sectionTitle(String title, String subtitle, List<Widget> actions) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: heading(31)),
            const SizedBox(height: 10),
            Text(subtitle, style: TextStyle(color: muted, height: 1.5)),
            const SizedBox(height: 18),
            Wrap(spacing: 10, runSpacing: 10, children: actions),
          ],
        ),
      );
  Widget _itemView() {
    final d = inventoryMap(item['data']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => _update(() => _detail = {}),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back to items'),
        ),
        const SizedBox(height: 15),
        panel(
          LayoutBuilder(
            builder: (context, c) {
              final info = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  badge('${d['category'] ?? 'Inventory'}'),
                  const SizedBox(height: 14),
                  Text('${d['name']}', style: heading(30)),
                  const SizedBox(height: 12),
                  Text(
                    '${d['brand'] ?? ''} · ${d['sku']}',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${d['currency']} ${inventoryNumber(d['price']).toStringAsFixed(2)} / ${d['unit']}',
                    style: TextStyle(
                      color: ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 19,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${d['description'] ?? ''}',
                    style: TextStyle(color: muted, height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children: [
                      action(
                        'Edit item',
                        Icons.edit_outlined,
                        editable ? () => _editProduct(item) : null,
                      ),
                      action(
                        'Add photo',
                        Icons.add_photo_alternate_outlined,
                        editable ? _productPhoto : null,
                      ),
                      action(
                        'Archive',
                        Icons.archive_outlined,
                        editable ? () => _archive(item) : null,
                      ),
                    ],
                  ),
                ],
              );
              final photo = ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  color: canvas,
                  width: c.maxWidth > 750 ? 260 : double.infinity,
                  height: 220,
                  child: item['photo_url'] == null
                      ? const Center(child: InventorySculpture(size: 180))
                      : Image.network(
                          item['photo_url'],
                          fit: BoxFit.contain,
                          errorBuilder: (_, e, s) => const Center(
                            child: Icon(Icons.broken_image_outlined, size: 45),
                          ),
                        ),
                ),
              );
              return c.maxWidth > 750
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        photo,
                        const SizedBox(width: 28),
                        Expanded(child: info),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [photo, const SizedBox(height: 24), info],
                    );
            },
          ),
        ),
        const SizedBox(height: 26),
        _sectionTitle(
          'Stock & traceability',
          'All locations for this item. Serial numbers, batches and expiry stay attached to each stock position.',
          [
            action(
              'Add stock position',
              Icons.add_location_alt_outlined,
              editable ? _addStock : null,
              primary: true,
            ),
            action(
              'Create order',
              Icons.receipt_long_outlined,
              editable ? _newOrder : null,
            ),
          ],
        ),
        if (stock.isEmpty)
          _empty(
            'Where does this item live?',
            'Add a stock position, then use Receive to record the opening quantity.',
          )
        else
          ...stock.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: panel(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 14,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _locationName(s['location_id']),
                          style: heading(20),
                        ),
                        badge('${inventoryQuantity(s['quantity'])} on hand'),
                        badge('${inventoryQuantity(s['reserved'])} reserved'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      [
                        if ('${s['bin'] ?? ''}'.isNotEmpty) 'Bin ${s['bin']}',
                        if ('${s['serial'] ?? ''}'.isNotEmpty)
                          'Serial ${s['serial']}',
                        if ('${s['batch'] ?? ''}'.isNotEmpty)
                          'Batch ${s['batch']}',
                        if (s['expiry'] != null) 'Expires ${s['expiry']}',
                        'Cost ${d['currency']} ${inventoryNumber(s['unit_cost']).toStringAsFixed(2)}',
                      ].join(' · '),
                      style: TextStyle(color: muted, height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    action(
                      'Receive / move / count',
                      Icons.swap_horiz,
                      editable ? () => _move(s) : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _locationsView() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle(
        'Every location. One view.',
        'Stores, warehouses and stockrooms, wherever your business goes.',
        [
          action(
            'Add location',
            Icons.add,
            editable ? () => _editLocation() : null,
            primary: true,
          ),
        ],
      ),
      if (locations.isEmpty)
        _empty(
          'Start with your first location.',
          'Add its state or province and country to enable geographic search.',
          icon: Icons.public,
        )
      else
        ...locations.map((l) {
          final d = inventoryMap(l['data']);
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 14,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Icon(Icons.location_on_outlined, color: accent),
                      Text('${d['name']}', style: heading(22)),
                      badge(_countryName('${d['country']}')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${d['city']} · ${d['region']}\n${d['address'] ?? ''}',
                    style: TextStyle(color: muted, height: 1.6),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      action(
                        'Search this state',
                        Icons.search,
                        blocked
                            ? null
                            : () {
                                _update(() {
                                  _scope = 'statewide';
                                  _country = d['country'];
                                  _region = d['region'];
                                  _tab = 'discover';
                                  _detail = {};
                                });
                                _work(() => _search());
                              },
                      ),
                      action(
                        'Edit',
                        Icons.edit_outlined,
                        editable ? () => _editLocation(l) : null,
                      ),
                      action(
                        'Archive',
                        Icons.archive_outlined,
                        editable ? () => _archive(l) : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
    ],
  );
  Widget _partnersView() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle(
        'People behind your inventory.',
        'Keep suppliers and customers close to the orders they support.',
        [
          action(
            'Add contact',
            Icons.person_add_alt,
            editable ? () => _editPartner() : null,
            primary: true,
          ),
        ],
      ),
      if (partners.isEmpty)
        _empty(
          'Your supplier list starts here.',
          'Save supplier and customer details for purchase and sales orders.',
          icon: Icons.people_outline,
        )
      else
        ...partners.map((p) {
          final d = inventoryMap(p['data']);
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  badge('${d['type']}'),
                  const SizedBox(height: 12),
                  Text('${d['name']}', style: heading(22)),
                  const SizedBox(height: 8),
                  Text(
                    '${d['email']}\n${d['phone']}\n${d['notes']}',
                    style: TextStyle(color: muted, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      action(
                        'Edit',
                        Icons.edit_outlined,
                        editable ? () => _editPartner(p) : null,
                      ),
                      action(
                        'Archive',
                        Icons.archive_outlined,
                        editable ? () => _archive(p) : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
    ],
  );
  Widget _ordersView() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle(
        'From ordered to on hand.',
        'Create purchase and sales orders, reserve stock, and track every receipt and shipment.',
        [
          action(
            'Create order',
            Icons.add,
            editable ? _newOrder : null,
            primary: true,
          ),
        ],
      ),
      if (orders.isEmpty)
        _empty(
          'Keep the next shipment in sight.',
          'Add items to an order. Receive purchases and ship sales in full or in parts.',
          icon: Icons.local_shipping_outlined,
        )
      else
        ...orders.map((o) {
          final d = inventoryMap(o['data']),
              open = ['open', 'partial'].contains(d['status']);
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      badge(
                        d['type'] == 'purchase'
                            ? 'Purchase order'
                            : 'Sales order',
                      ),
                      badge('${d['status']}'),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Text('${d['name']}', style: heading(22)),
                  const SizedBox(height: 10),
                  if ('${d['due'] ?? ''}'.isNotEmpty)
                    Text('Due ${d['due']}', style: TextStyle(color: muted)),
                  for (final l in inventoryItems(d['lines']))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Text(
                        '${l['product_name'] ?? 'Item'} · ${l['sku'] ?? ''}\n${l['location_name'] ?? ''} · ${l['serial'] ?? ''}\n${inventoryQuantity(l['done'])} of ${inventoryQuantity(l['quantity'])} ${d['type'] == 'purchase' ? 'received' : 'shipped'} · ${l['currency'] ?? d['currency'] ?? ''} ${inventoryNumber(l['unit_price']).toStringAsFixed(2)} each',
                        style: TextStyle(color: muted),
                      ),
                    ),
                  const SizedBox(height: 15),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (d['status'] == 'draft')
                        action(
                          d['type'] == 'sale'
                              ? 'Open & reserve stock'
                              : 'Open purchase order',
                          Icons.task_alt,
                          editable ? () => _orderAction(o, 'order_open') : null,
                          primary: true,
                        ),
                      if (open)
                        action(
                          d['type'] == 'purchase'
                              ? 'Receive items'
                              : 'Ship items',
                          Icons.local_shipping_outlined,
                          editable
                              ? () => _orderAction(o, 'order_process')
                              : null,
                          primary: true,
                        ),
                      if (open || d['status'] == 'draft')
                        action(
                          'Cancel remaining',
                          Icons.cancel_outlined,
                          editable
                              ? () => _orderAction(o, 'order_cancel')
                              : null,
                        ),
                      if ([
                        'complete',
                        'cancelled',
                        'draft',
                      ].contains(d['status']))
                        action(
                          'Archive',
                          Icons.archive_outlined,
                          editable ? () => _archive(o) : null,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
    ],
  );
  Widget _activityView() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle(
        'A history you can follow.',
        'The latest 100 inventory events. Recorded stock changes retain their reason and quantity.',
        [],
      ),
      if (_events.isEmpty)
        _empty(
          'Your activity trail is ready.',
          'Receipts, transfers, counts and orders will appear here.',
          icon: Icons.history,
        )
      else
        ..._events.map((e) {
          final d = inventoryMap(e['detail']);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: panel(
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: accent.withValues(alpha: .12),
                    child: Icon(Icons.swap_vert, color: accent),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${d['kind'] ?? e['action']}'.replaceAll('_', ' '),
                          style: TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (d['before'] != null)
                          Text(
                            '${inventoryQuantity(d['before'])} → ${inventoryQuantity(d['after'])}',
                            style: TextStyle(color: ink),
                          ),
                        if (d['name'] != null)
                          Text('${d['name']}', style: TextStyle(color: muted)),
                        if (d['note'] != null)
                          Text('${d['note']}', style: TextStyle(color: muted)),
                        Text(
                          '${e['created_at']}',
                          style: TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
    ],
  );
  Widget _reportsView() {
    final value = inventoryItems(inventoryMap(_workspace['summary'])['value']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'Clarity at a glance.',
          'Stock valuation, portable records and a simple path from spreadsheets.',
          [],
        ),
        _stats(),
        const SizedBox(height: 20),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stock value at recorded cost', style: heading(23)),
              const SizedBox(height: 10),
              Text(
                'Currencies stay separate. This is an operational stock report; accounting entries and exchange rates are not applied.',
                style: TextStyle(color: muted, height: 1.5),
              ),
              const SizedBox(height: 20),
              if (value.isEmpty)
                Text('No stock received yet.', style: TextStyle(color: muted)),
              for (final v in value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '${v['currency']} ${inventoryNumber(v['amount']).toStringAsFixed(2)}',
                    style: heading(26),
                  ),
                ),
              const SizedBox(height: 12),
              action(
                'Export inventory CSV',
                Icons.download_outlined,
                editable ? _export : null,
                primary: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bring your catalog with you.', style: heading(23)),
              const SizedBox(height: 10),
              Text(
                'Import up to 200 new items per CSV. Preview before saving. Name and SKU are required. Add opening quantities through Receive so every unit has a history.',
                style: TextStyle(color: muted, height: 1.6),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  action(
                    'Get CSV template',
                    Icons.description_outlined,
                    editable ? _template : null,
                  ),
                  action(
                    'Import items',
                    Icons.upload_file_outlined,
                    editable ? _import : null,
                    primary: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProductCard extends StatefulWidget {
  const _ProductCard({
    required this.product,
    required this.onTap,
    required this.dark,
  });
  final Map<String, dynamic> product;
  final VoidCallback onTap;
  final bool dark;
  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.product,
        d = inventoryMap(p['data']),
        available = inventoryNumber(p['available']);
    final low = available <= inventoryNumber(d['reorder']);
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.translationValues(0, hover ? -4 : 0, 0),
        decoration: BoxDecoration(
          color: widget.dark ? const Color(0xFF172137) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: widget.dark
                ? const Color(0xFF303C54)
                : const Color(0xFFE2E7F1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: hover ? 0.10 : 0.025),
              blurRadius: hover ? 28 : 15,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Container(
                      height: 174,
                      width: double.infinity,
                      color: widget.dark
                          ? const Color(0xFF202C41)
                          : const Color(0xFFF0F3F9),
                      child: p['photo_url'] == null
                          ? const Center(child: InventorySculpture(size: 150))
                          : Image.network(
                              p['photo_url'],
                              fit: BoxFit.contain,
                              errorBuilder: (_, e, s) => const Center(
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  size: 42,
                                ),
                              ),
                            ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: widget.dark
                              ? const Color(0xFF152939)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Text(
                          available <= 0
                              ? 'Out of stock'
                              : low
                              ? 'Low stock'
                              : 'In stock',
                          style: TextStyle(
                            color: widget.dark
                                ? const Color(0xFFCCF3E5)
                                : low
                                ? const Color(0xFF8A4F13)
                                : const Color(0xFF256951),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${d['brand'] ?? ''} · ${d['sku']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.dark
                              ? const Color(0xFFAFBBD0)
                              : const Color(0xFF7A859A),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        '${d['name']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.dark
                              ? Colors.white
                              : const Color(0xFF223049),
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 9,
                        runSpacing: 5,
                        children: [
                          Text(
                            '${inventoryQuantity(available)} ${d['unit']} available',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${p['locations'] ?? 0} locations',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 13),
                      Text(
                        '${d['currency']} ${inventoryNumber(d['price']).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
