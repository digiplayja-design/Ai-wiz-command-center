import 'package:flutter/material.dart';
import '../workforce/workforce_style.dart';
import 'funnel_meta_format.dart';

BigInt _amount(dynamic value) {
  final parts = '$value'.split('.');
  return BigInt.parse(parts.first) * BigInt.from(1000000) +
      BigInt.parse((parts.length == 1 ? '' : parts[1]).padRight(6, '0'));
}

int compareMetaCampaigns(Map a, Map b, String sort) {
  final int order;
  switch (sort) {
    case 'spend':
      order = _amount(b['spend']).compareTo(_amount(a['spend']));
    case 'impressions':
    case 'clicks':
      order = (b[sort] as int).compareTo(a[sort] as int);
    default:
      order = '${a['campaign_name']}'.toLowerCase().compareTo(
        '${b['campaign_name']}'.toLowerCase(),
      );
  }
  return order == 0
      ? '${a['campaign_id']}'.compareTo('${b['campaign_id']}')
      : order;
}

class FunnelMetaCampaignResults extends StatefulWidget {
  const FunnelMetaCampaignResults({
    super.key,
    required this.rows,
    required this.currency,
  });
  final List<Map> rows;
  final String currency;
  @override
  State<FunnelMetaCampaignResults> createState() =>
      _FunnelMetaCampaignResultsState();
}

class _FunnelMetaCampaignResultsState extends State<FunnelMetaCampaignResults> {
  final _search = TextEditingController();
  String _sort = 'spend', _query = '';
  int _page = 0;
  static const _pageSize = 20;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _caption(String value) => Text(
    value,
    style: const TextStyle(color: WfStyle.muted, fontSize: 12, height: 1.5),
  );

  Widget _campaign(Map row) => Container(
    key: ValueKey('meta-campaign-${row['campaign_id']}'),
    width: double.infinity,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: WfStyle.background,
      border: Border.all(color: WfStyle.line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          '${row['campaign_name']}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        _caption('Campaign ID: ${row['campaign_id']}'),
        const SizedBox(height: 14),
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            Text(
              'Spent: ${metaMoney(widget.currency, row['spend'])}',
              style: const TextStyle(
                color: WfStyle.cyan,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text('Impressions: ${metaCount(row['impressions'])}'),
            Text('Clicks (all): ${metaCount(row['clicks'])}'),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final matches =
        widget.rows
            .where(
              (r) =>
                  '${r['campaign_name']}'.toLowerCase().contains(_query) ||
                  '${r['campaign_id']}'.contains(_query),
            )
            .toList()
          ..sort((a, b) => compareMetaCampaigns(a, b, _sort));
    final start = (_page * _pageSize).clamp(0, matches.length);
    final end = (start + _pageSize).clamp(0, matches.length);
    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Campaign comparison',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('meta-campaign-search'),
            controller: _search,
            maxLength: 100,
            decoration: InputDecoration(
              labelText: 'Search campaign name or ID',
              counterText: '',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                        _page = 0;
                      }),
                      icon: const Icon(Icons.close),
                    ),
            ),
            onChanged: (value) => setState(() {
              _query = value.trim().toLowerCase();
              _page = 0;
            }),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: const ValueKey('meta-campaign-sort'),
            initialValue: _sort,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Sort campaigns'),
            items: const [
              DropdownMenuItem(value: 'spend', child: Text('Highest spend')),
              DropdownMenuItem(
                value: 'impressions',
                child: Text('Most impressions'),
              ),
              DropdownMenuItem(
                value: 'clicks',
                child: Text('Most clicks (all)'),
              ),
              DropdownMenuItem(value: 'name', child: Text('Name A–Z')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _sort = value;
                  _page = 0;
                });
              }
            },
          ),
          const SizedBox(height: 12),
          _caption(
            '${matches.length} of ${widget.rows.length} returned campaigns match. Search and sorting use this loaded report.',
          ),
          if (matches.isEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'No matching campaigns. Try another name or ID.',
              style: TextStyle(color: WfStyle.muted),
            ),
          ] else ...[
            const SizedBox(height: 8),
            _caption('Showing ${start + 1}–$end of ${matches.length}'),
            for (final row in matches.sublist(start, end)) _campaign(row),
            if (matches.length > _pageSize) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('meta-campaign-prev'),
                    onPressed: _page == 0
                        ? null
                        : () => setState(() => _page--),
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Previous'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('meta-campaign-next'),
                    onPressed: end >= matches.length
                        ? null
                        : () => setState(() => _page++),
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Next'),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
