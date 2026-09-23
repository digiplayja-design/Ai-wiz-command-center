import 'package:flutter/material.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';

void validateMetaPages(Map<String, dynamic> state) {
  final c = state['connection'];
  if (c == null) return;
  bool id(dynamic v) => v is String && RegExp(r'^\d{1,40}$').hasMatch(v);
  var valid =
      c is Map &&
      c['version'] is int &&
      c['version'] > 0 &&
      c['accounts'] is List;
  if (valid) {
    final pages = c['pages'] ?? [];
    valid = pages is List && pages.length <= 500;
    final ids = <String>{};
    if (valid) {
      for (final p in pages) {
        if (p is! Map ||
            !id(p['id']) ||
            !ids.add(p['id']) ||
            p['name'] is! String ||
            p['name'].trim().isEmpty ||
            p['name'].length > 200 ||
            p['category'] is! String ||
            p['category'].length > 200 ||
            p.keys.any((k) => !['id', 'name', 'category'].contains(k))) {
          valid = false;
          break;
        }
      }
      valid =
          valid &&
          (c['selected_page'] == null || ids.contains(c['selected_page'])) &&
          (pages.isEmpty || c['selected_account'] != null) &&
          (c['pages_access_denied'] == null ||
              c['pages_access_denied'] is bool) &&
          (c['pages_access_denied'] != true ||
              (pages.isEmpty && c['selected_page'] == null)) &&
          (c['pages_refreshed_at'] == null ||
              (c['pages_refreshed_at'] is String &&
                  DateTime.tryParse(c['pages_refreshed_at']) != null));
    }
  }
  if (!valid) {
    throw const FunnelException(
      'Meta Page details could not be read. Check the connection again.',
    );
  }
}

class FunnelMetaPages extends StatefulWidget {
  const FunnelMetaPages({
    super.key,
    required this.connection,
    required this.available,
    required this.onAction,
  });
  final Map<String, dynamic> connection;
  final bool available;
  final Future<void> Function(String, [String?]) onAction;
  @override
  State<FunnelMetaPages> createState() => _FunnelMetaPagesState();
}

class _FunnelMetaPagesState extends State<FunnelMetaPages> {
  String _search = '';
  int _page = 0;
  @override
  Widget build(BuildContext context) {
    final c = widget.connection, all = c['pages'] as List? ?? [];
    final rows = all
        .where(
          (p) => '${p['name']} ${p['id']} ${p['category']}'
              .toLowerCase()
              .contains(_search.toLowerCase()),
        )
        .toList();
    final enabled = widget.available && c['selected_account'] != null;
    final selected = all.where((p) => p['id'] == c['selected_page']);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Facebook Page',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose a Page shared with KORLIX for your Meta setup. Ad permissions will need a separate check before future publishing.',
            style: TextStyle(color: WfStyle.muted, height: 1.5),
          ),
          const SizedBox(height: 12),
          if (c['selected_account'] == null)
            const Text(
              'Select an ad account above to choose a Facebook Page.',
              style: TextStyle(color: WfStyle.muted, height: 1.5),
            ),
          if (c['pages_access_denied'] == true)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Page permission is needed. Check the Pages shared during Meta sign-in, then reconnect after KORLIX Page access is approved. Your ad account reports remain available.',
                style: TextStyle(color: Colors.amber, height: 1.5),
              ),
            ),
          if (selected.isNotEmpty) ...[
            Text(
              'Selected Page: ${selected.first['name']}',
              style: const TextStyle(
                color: WfStyle.cyan,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: enabled ? () => widget.onAction('pages') : null,
                icon: const Icon(Icons.sync),
                label: const Text('Refresh Facebook Pages'),
              ),
              if (c['selected_page'] != null)
                TextButton(
                  onPressed: enabled
                      ? () => widget.onAction('clear-page')
                      : null,
                  child: const Text('Clear Page selection'),
                ),
            ],
          ),
          if (c['pages_refreshed_at'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Pages last checked: ${DateTime.tryParse(c['pages_refreshed_at'])?.toLocal().toString().split('.').first ?? 'Refresh Pages'}',
                style: const TextStyle(color: WfStyle.muted, fontSize: 12),
              ),
            ),
          if (all.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: TextField(
                onChanged: (value) => setState(() {
                  _search = value;
                  _page = 0;
                }),
                decoration: const InputDecoration(
                  labelText: 'Find a Facebook Page',
                  hintText: 'Name, Page ID or category',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
          if (rows.isEmpty && c['selected_account'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                _search.isNotEmpty
                    ? 'No Pages match your search.'
                    : c['pages_refreshed_at'] == null
                    ? 'Refresh Facebook Pages to load the Pages shared with KORLIX.'
                    : 'No Pages were returned. Check which Pages you shared during Meta sign-in, then refresh.',
                style: const TextStyle(color: WfStyle.muted, height: 1.5),
              ),
            ),
          for (final p in rows.skip(_page * 20).take(20))
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF071B29),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: c['selected_page'] == p['id']
                      ? WfStyle.cyan
                      : WfStyle.line,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Page ${p['id']}${p['category'].isEmpty ? '' : ' · ${p['category']}'}',
                    style: const TextStyle(color: WfStyle.muted, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: enabled && c['selected_page'] != p['id']
                        ? () => widget.onAction('select-page', p['id'])
                        : null,
                    icon: Icon(
                      c['selected_page'] == p['id']
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                    ),
                    label: Text(
                      c['selected_page'] == p['id']
                          ? 'Selected Page'
                          : 'Use this Page',
                    ),
                  ),
                ],
              ),
            ),
          if (rows.length > 20)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Page ${_page + 1} of ${(rows.length / 20).ceil()} · ${rows.length} Pages',
                  ),
                  TextButton(
                    onPressed: _page > 0 ? () => setState(() => _page--) : null,
                    child: const Text('Previous Pages'),
                  ),
                  TextButton(
                    onPressed: (_page + 1) * 20 < rows.length
                        ? () => setState(() => _page++)
                        : null,
                    child: const Text('Next Pages'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
