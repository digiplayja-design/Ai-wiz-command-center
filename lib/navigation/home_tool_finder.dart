import 'package:flutter/material.dart';
import '../theme/korlix_theme.dart';
import 'home_tool_catalog.dart';

/// Opened on request; selecting a result returns to the existing home dispatcher.
class HomeToolFinder extends StatefulWidget {
  const HomeToolFinder({super.key, required this.tools});
  final List<HomeToolEntry> tools;
  @override
  State<HomeToolFinder> createState() => _HomeToolFinderState();
}

class _HomeToolFinderState extends State<HomeToolFinder> {
  final _query = TextEditingController();
  String _group = 'All';
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final matches = widget.tools
        .where(
          (tool) =>
              (_group == 'All' || tool.group == _group) &&
              tool.matches(_query.text),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Find a tool')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What would you like to do?',
                          style: TextStyle(
                            color: skin.text,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Search by name or task. Try contacts, team reminders, news or music.',
                          style: TextStyle(color: skin.mutedText, height: 1.5),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          key: const ValueKey('tool-search'),
                          controller: _query,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            labelText: 'Search tools',
                            hintText: 'What do you need?',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _query.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    icon: const Icon(Icons.close),
                                    onPressed: () => setState(_query.clear),
                                  ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) {
                            if (matches.length == 1)
                              Navigator.pop(context, matches.single);
                          },
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (final group in [
                              'All',
                              ...widget.tools.map((t) => t.group).toSet(),
                            ])
                              ChoiceChip(
                                label: Text(group),
                                selected: _group == group,
                                onSelected: (_) =>
                                    setState(() => _group = group),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            '${matches.length} ${matches.length == 1 ? 'tool' : 'tools'}',
                            style: TextStyle(color: skin.mutedText),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (matches.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.all(24),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'No tools found',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Try a shorter name or reset your search to see all tools.',
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => setState(() {
                              _query.clear();
                              _group = 'All';
                            }),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Show all tools'),
                          ),
                        ],
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  sliver: SliverList.builder(
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final tool = matches[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: skin.panel,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(
                              color: skin.primary.withValues(alpha: .25),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            key: ValueKey('tool-${tool.identity}'),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            title: Text(
                              tool.label,
                              style: TextStyle(
                                color: skin.text,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Text(
                                tool.description,
                                style: TextStyle(
                                  color: skin.mutedText,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            trailing: Icon(
                              Icons.arrow_forward_rounded,
                              color: skin.primary,
                            ),
                            onTap: () => Navigator.pop(context, tool),
                          ),
                        ),
                      );
                    },
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
