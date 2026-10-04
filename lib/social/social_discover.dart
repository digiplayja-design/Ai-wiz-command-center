import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../theme/korlix_theme.dart';
import 'social_client.dart';
import 'social_design.dart';
import 'social_forms.dart';

const discoverTopics = {
  'all': 'All topics',
  'jamaica': 'Jamaica & Caribbean',
  'world': 'World',
  'business': 'Business',
  'technology': 'Technology',
  'sports': 'Sports',
  'entertainment': 'Entertainment',
};

class SocialDiscoverScreen extends StatefulWidget {
  const SocialDiscoverScreen({
    super.key,
    required this.client,
    required this.profile,
  });
  final SocialClient client;
  final SocialMap profile;
  @override
  State<SocialDiscoverScreen> createState() => _SocialDiscoverScreenState();
}

class _SocialDiscoverScreenState extends State<SocialDiscoverScreen> {
  List<SocialMap> _news = [], _videos = [];
  String _tab = 'all', _topic = 'all', _feed = 'all';
  String? _newsError, _videoError, _checked;
  bool _loading = false, _more = false, _newsPending = false;
  int _generation = 0, _polls = 0;
  Timer? _poll;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_access);
    unawaited(_load());
  }

  void _access() {
    if (!widget.client.available && mounted) {
      _generation++;
      _poll?.cancel();
      setState(() {
        _news = [];
        _videos = [];
        _loading = false;
        _checked = null;
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _poll?.cancel();
    widget.client.removeListener(_access);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SocialDiscoverScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      oldWidget.client.removeListener(_access);
      widget.client.addListener(_access);
      _generation++;
      _poll?.cancel();
      _news = [];
      _videos = [];
      _busy.clear();
      unawaited(_load());
    }
  }

  Future<SocialMap> _fetch(String action, SocialMap data) async {
    try {
      return await widget.client.get(action, data);
    } catch (e) {
      return {'error': '$e'};
    }
  }

  Future<void> _load() async {
    if (!widget.client.available) return;
    final generation = ++_generation;
    _poll?.cancel();
    _polls = 0;
    setState(() => _loading = true);
    final saved = _tab == 'saved';
    final results = await Future.wait([
      _fetch('discover_news', {'feed': saved ? 'saved' : 'all'}),
      _fetch('discover_videos', {
        'feed': saved
            ? 'saved'
            : _tab == 'videos'
            ? _feed
            : 'all',
      }),
    ]);
    if (!mounted || !widget.client.available || generation != _generation) {
      return;
    }
    setState(() {
      _newsError = results[0]['error'];
      _videoError = results[1]['error'];
      _news = socialItems(results[0]['items']);
      _acceptNews(results[0]);
      final videos = socialItems(results[1]['items']);
      _more = videos.length > 20;
      _videos = videos.take(20).toList();
      _loading = false;
    });
    _scheduleNews(generation);
  }

  void _acceptNews(SocialMap result) {
    _checked = result['refreshed_at']?.toString();
    final date = DateTime.tryParse(_checked ?? '');
    _newsPending =
        result['available'] == true &&
        (result['refreshing'] == true ||
            date == null ||
            DateTime.now().difference(date).inHours >= 3);
  }

  void _scheduleNews(int generation) {
    if (!_newsPending || _polls >= 20 || _tab == 'saved') return;
    _poll = Timer(const Duration(seconds: 6), () async {
      if (!mounted || !widget.client.available || generation != _generation) {
        return;
      }
      _polls++;
      final result = await _fetch('discover_news', {});
      if (!mounted || !widget.client.available || generation != _generation) {
        return;
      }
      setState(() {
        _newsError = result['error'];
        if (_newsError == null) {
          _news = socialItems(result['items']);
          _acceptNews(result);
        }
        if (_polls >= 20) _newsPending = false;
      });
      _scheduleNews(generation);
    });
  }

  Future<void> _moreVideos() async {
    if (_loading || !_more || _videos.isEmpty) return;
    final generation = _generation;
    setState(() => _loading = true);
    final result = await _fetch('discover_videos', {
      'feed': _tab == 'saved'
          ? 'saved'
          : _tab == 'videos'
          ? _feed
          : 'all',
      'before': _videos.last['seq'],
    });
    if (!mounted || !widget.client.available || generation != _generation) {
      return;
    }
    setState(() {
      _videoError = result['error'];
      _loading = false;
      if (_videoError == null) {
        final rows = socialItems(result['items']);
        _more = rows.length > 20;
        final ids = _videos.map((v) => v['id']).toSet();
        _videos.addAll(rows.take(20).where((v) => !ids.contains(v['id'])));
      }
    });
  }

  Future<void> _mark(SocialMap item, String kind, String field) async {
    final key = '${item['id']}:$field';
    if (_busy.contains(key) || !widget.client.available) return;
    final value = item[field] != true;
    setState(() => _busy.add(key));
    try {
      await widget.client.post('discover_mark', {
        'id': item['id'],
        'kind': kind,
        'field': field,
        'value': value,
      });
      if (mounted && widget.client.available) {
        setState(() {
          item[field] = value;
          if (field == 'liked') {
            item['like_count'] =
                ((item['like_count'] as num?)?.toInt() ?? 0) + (value ? 1 : -1);
          }
        });
      }
    } catch (e) {
      if (mounted) socialNotice(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _upload([SocialMap? draft]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DiscoverUploadScreen(client: widget.client, draft: draft),
      ),
    );
    if (mounted && widget.client.available) await _load();
  }

  Future<void> _options(SocialMap item, String kind, String action) async {
    if (!widget.client.available) return;
    try {
      if (action == 'report') {
        if (await socialReport(context, widget.client, kind, '${item['id']}')) {
          if (mounted && widget.client.available) await _load();
        }
      } else if (action == 'delete') {
        if (!await socialConfirm(
          context,
          'Delete this video?',
          'It will be removed from Discover and your saved videos. Copies already downloaded by other people cannot be recalled.',
          action: 'Delete',
        )) {
          return;
        }
        await widget.client.post('discover_delete', {'id': item['id']});
        if (mounted) await _load();
      } else if (action == 'block') {
        if (!await socialConfirm(
          context,
          'Block this creator?',
          'Their videos will disappear from your feed. This also blocks Social contact.',
          action: 'Block',
        )) {
          return;
        }
        await widget.client.post('block', {
          'peer': socialMap(item['author'])['id'],
        });
        if (mounted) await _load();
      }
    } catch (e) {
      if (mounted) socialNotice(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final news = _news
        .where(
          (n) => _tab != 'news' || _topic == 'all' || n['category'] == _topic,
        )
        .toList();
    final cards = <(SocialMap, String)>[];
    if (_tab == 'news') {
      cards.addAll(news.map((n) => (n, 'news')));
    } else if (_tab == 'videos') {
      cards.addAll(_videos.map((v) => (v, 'video')));
    } else {
      for (var i = 0; i < news.length || i < _videos.length; i++) {
        if (i < news.length) cards.add((news[i], 'news'));
        if (i < _videos.length) cards.add((_videos[i], 'video'));
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            tooltip: 'Refresh Discover',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: !widget.client.available
          ? const Center(
              child: Text(
                'Your session changed. Reopen Social after signing in.',
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(constraints.maxWidth < 430 ? 16 : 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1060),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SocialPanel(
                            accent: socialColor('violet'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'KORLIX DISCOVER',
                                  style: TextStyle(
                                    color: skin.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Your world.\nA fresh perspective.',
                                  style: TextStyle(
                                    fontSize: 32,
                                    height: 1.12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -.7,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Source-linked news. Videos from your community.',
                                  style: TextStyle(fontSize: 16, height: 1.5),
                                ),
                                const SizedBox(height: 18),
                                FilledButton.icon(
                                  key: const ValueKey('discover-upload'),
                                  onPressed: () => _upload(),
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('Share a video'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final entry in {
                                'all': 'Discover',
                                'news': 'News',
                                'videos': 'Videos',
                                'saved': 'Saved',
                              }.entries)
                                ChoiceChip(
                                  key: ValueKey('discover-tab-${entry.key}'),
                                  label: Text(entry.value),
                                  selected: _tab == entry.key,
                                  onSelected: (_) {
                                    setState(() {
                                      _tab = entry.key;
                                      _news = [];
                                      _videos = [];
                                    });
                                    unawaited(_load());
                                  },
                                ),
                            ],
                          ),
                          if (_tab == 'news') ...[
                            const SizedBox(height: 12),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final topic in discoverTopics.entries)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: FilterChip(
                                        label: Text(topic.value),
                                        selected: _topic == topic.key,
                                        onSelected: (_) =>
                                            setState(() => _topic = topic.key),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                          if (_tab == 'videos') ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final entry in {
                                  'all': 'Latest',
                                  'following': 'Following',
                                  'mine': 'My videos',
                                }.entries)
                                  ChoiceChip(
                                    label: Text(entry.value),
                                    selected: _feed == entry.key,
                                    onSelected: (_) {
                                      setState(() => _feed = entry.key);
                                      unawaited(_load());
                                    },
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 16),
                          if (_tab != 'videos')
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                _checked == null
                                    ? 'News summaries are AI-written and link to the original reporting.'
                                    : 'AI-written news summaries · Edition checked ${socialTime(_checked)}. Open the source for the full reporting.',
                                style: TextStyle(
                                  color: skin.mutedText,
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          if (_loading)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: LinearProgressIndicator(),
                            ),
                          if (_newsError != null && _tab != 'videos')
                            _error('News: $_newsError'),
                          if (_videoError != null && _tab != 'news')
                            _error('Videos: $_videoError'),
                          if (!_loading &&
                              _tab != 'videos' &&
                              news.isEmpty &&
                              _tab != 'saved')
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: SocialEmpty(
                                icon: Icons.newspaper_rounded,
                                title: _newsPending
                                    ? 'Checking the latest stories…'
                                    : 'No news stories available here yet.',
                                body: _newsPending
                                    ? 'The first edition can take a minute. Videos are ready to browse below.'
                                    : 'Try another topic or refresh in a few minutes. We only show stories with source links.',
                              ),
                            ),
                          if (!_loading &&
                              _videos.isEmpty &&
                              _tab != 'news' &&
                              _tab != 'saved')
                            const Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: SocialEmpty(
                                icon: Icons.play_circle_outline_rounded,
                                title: 'Your community starts here.',
                                body:
                                    'Share the first video, or check back for new clips. Videos appear after their creators publish them.',
                              ),
                            ),
                          if (!_loading && cards.isEmpty && _tab == 'saved')
                            const SocialEmpty(
                              icon: Icons.bookmark_border_rounded,
                              title: 'Keep the good finds.',
                              body:
                                  'Save a story or video and come back to it here.',
                            ),
                          LayoutBuilder(
                            builder: (context, c) {
                              final width = c.maxWidth >= 700
                                  ? (c.maxWidth - 16) / 2
                                  : c.maxWidth;
                              return Wrap(
                                spacing: 16,
                                runSpacing: 16,
                                children: [
                                  for (final card in cards)
                                    SizedBox(
                                      width: width,
                                      child: _card(card.$1, card.$2),
                                    ),
                                ],
                              );
                            },
                          ),
                          if (_more && _tab != 'news')
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: OutlinedButton(
                                  onPressed: _loading ? null : _moreVideos,
                                  child: const Text('More videos'),
                                ),
                              ),
                            ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _error(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
  Widget _card(SocialMap item, String kind) {
    final news = kind == 'news',
        author = socialMap(item['author']),
        owned = author['id'] == widget.profile['id'];
    final draft = !news && item['state'] != 'published';
    return SocialPanel(
      key: ValueKey('discover-card-${item['id']}'),
      padding: EdgeInsets.zero,
      accent: news ? socialColor('blue') : socialColor('violet'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            child: InkWell(
              onTap: news
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DiscoverNewsReader(
                          items: _news,
                          initial: _news.indexOf(item),
                          client: widget.client,
                        ),
                      ),
                    )
                  : item['state'] == 'uploading'
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DiscoverVideoViewer(
                          client: widget.client,
                          items: _videos
                              .where((v) => v['state'] != 'uploading')
                              .toList(),
                          initialId: '${item['id']}',
                        ),
                      ),
                    ),
              child: AspectRatio(
                aspectRatio: news ? 1.65 : 1.25,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: news
                              ? [
                                  const Color(0xFF133F68),
                                  const Color(0xFF142939),
                                ]
                              : [
                                  const Color(0xFF34285B),
                                  const Color(0xFF142939),
                                ],
                        ),
                      ),
                    ),
                    if (!news && item['thumbnail_url'] is String)
                      Image.network(
                        item['thumbnail_url'],
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(
                            Icons.videocam_outlined,
                            size: 52,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    if (news)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.all(26),
                          child: Icon(
                            item['category'] == 'jamaica'
                                ? Icons.public_rounded
                                : socialIcon(item['category']),
                            size: 86,
                            color: Colors.white24,
                          ),
                        ),
                      ),
                    if (!news)
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          size: 66,
                          color: Colors.white,
                        ),
                      ),
                    Positioned(
                      left: 18,
                      top: 18,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          news
                              ? 'NEWS · ${(discoverTopics[item['category']] ?? 'World').toUpperCase()}'
                              : draft
                              ? 'PRIVATE DRAFT'
                              : 'COMMUNITY VIDEO',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    if (news)
                      Positioned(
                        left: 18,
                        bottom: 18,
                        right: 18,
                        child: Text(
                          '${item['source']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (news) ...[
                  Text(
                    '${item['title']}',
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${item['summary']}',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Published ${socialTime(item['published_at'])}',
                    style: TextStyle(
                      color: korlixSkinOf(context).mutedText,
                      fontSize: 12,
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      SocialAvatar(member: author, size: 34, showStatus: false),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${author['name']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  if ('${item['caption'] ?? ''}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '${item['caption']}',
                        style: const TextStyle(height: 1.5),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    draft
                        ? 'Private · unpublished'
                        : '${((item['duration_ms'] as num?)?.toInt() ?? 0) ~/ 1000}s · ${socialTime(item['created_at'])}',
                    style: TextStyle(
                      color: korlixSkinOf(context).mutedText,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (draft && item['state'] == 'ready')
                      FilledButton.tonal(
                        onPressed: () => _upload(item),
                        child: const Text('Publish draft'),
                      ),
                    if (!draft) ...[
                      IconButton(
                        tooltip: item['saved'] == true ? 'Unsave' : 'Save',
                        onPressed: _busy.contains('${item['id']}:saved')
                            ? null
                            : () => _mark(item, kind, 'saved'),
                        icon: Icon(
                          item['saved'] == true
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                        ),
                      ),
                      if (!news)
                        TextButton.icon(
                          onPressed: _busy.contains('${item['id']}:liked')
                              ? null
                              : () => _mark(item, kind, 'liked'),
                          icon: Icon(
                            item['liked'] == true
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                          ),
                          label: Text('${item['like_count'] ?? 0}'),
                        ),
                      if (news)
                        TextButton.icon(
                          onPressed: () => _openNewsSource(context, item),
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: const Text('Read source'),
                        ),
                      if (news)
                        IconButton(
                          tooltip: 'Copy story link',
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: '${item['url']}'),
                            );
                            if (mounted) {
                              socialNotice(context, 'Story link copied.');
                            }
                          },
                          icon: const Icon(Icons.link_rounded),
                        ),
                    ],
                    PopupMenuButton<String>(
                      tooltip: 'Content options',
                      onSelected: (action) => _options(item, kind, action),
                      itemBuilder: (_) => [
                        if (!draft)
                          const PopupMenuItem(
                            value: 'report',
                            child: Text('Report'),
                          ),
                        if (!news && !owned)
                          const PopupMenuItem(
                            value: 'block',
                            child: Text('Block creator'),
                          ),
                        if (owned)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete video'),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openNewsSource(BuildContext context, SocialMap item) async {
  final uri = Uri.tryParse('${item['url']}');
  try {
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw const SocialException('The source could not be opened.');
    }
  } catch (e) {
    if (context.mounted) socialNotice(context, e);
  }
}

class DiscoverNewsReader extends StatefulWidget {
  const DiscoverNewsReader({
    super.key,
    required this.items,
    required this.initial,
    required this.client,
  });
  final List<SocialMap> items;
  final int initial;
  final SocialClient client;
  @override
  State<DiscoverNewsReader> createState() => _DiscoverNewsReaderState();
}

class _DiscoverNewsReaderState extends State<DiscoverNewsReader> {
  late final PageController _pages = PageController(
    initialPage: widget.initial,
  );
  late int _index = widget.initial;
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_access);
  }

  void _access() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.client.removeListener(_access);
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('News · ${_index + 1}/${widget.items.length}')),
    body: !widget.client.available
        ? const Center(child: Text('Your session changed.'))
        : Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Swipe for the next story'),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: widget.items.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) {
                    final n = widget.items[i];
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 650),
                          child: SocialPanel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${discoverTopics[n['category']]} · ${n['source']}',
                                  style: TextStyle(
                                    color: korlixSkinOf(context).primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  '${n['title']}',
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800,
                                    height: 1.15,
                                  ),
                                ),
                                const SizedBox(height: 22),
                                Text(
                                  '${n['summary']}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    height: 1.6,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'AI-written summary. Published ${socialTime(n['published_at'])}; checked ${socialTime(n['checked_at'])}.',
                                  style: TextStyle(
                                    color: korlixSkinOf(context).mutedText,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                FilledButton.icon(
                                  onPressed: () => _openNewsSource(context, n),
                                  icon: const Icon(Icons.open_in_new_rounded),
                                  label: const Text('Read original reporting'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
  );
}

class DiscoverUploadScreen extends StatefulWidget {
  const DiscoverUploadScreen({super.key, required this.client, this.draft});
  final SocialClient client;
  final SocialMap? draft;
  @override
  State<DiscoverUploadScreen> createState() => _DiscoverUploadScreenState();
}

class _DiscoverUploadScreenState extends State<DiscoverUploadScreen> {
  final _caption = TextEditingController();
  late String _id = widget.draft?['id']?.toString() ?? socialId();
  Uint8List? _bytes;
  String? _filename, _error;
  bool _busy = false, _ready = false, _accepted = false;
  @override
  void initState() {
    super.initState();
    _ready = widget.draft != null;
    _caption.text = '${widget.draft?['caption'] ?? ''}';
    widget.client.addListener(_access);
  }

  void _access() {
    if (!widget.client.available && mounted) {
      _bytes = null;
      _caption.clear();
      setState(() => _error = 'Your session changed. Reopen Social.');
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_access);
    _caption.dispose();
    _bytes = null;
    super.dispose();
  }

  Future<void> _pick() async {
    if (!widget.client.available || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mov', 'webm'],
        withData: true,
      );
      if (!mounted || !widget.client.available || result == null) return;
      final file = result.files.single;
      if (file.size > 50 * 1024 * 1024 ||
          file.bytes == null ||
          file.bytes!.isEmpty) {
        throw const SocialException('Choose a video smaller than 50 MB.');
      }
      setState(() {
        _id = socialId();
        _bytes = file.bytes;
        _filename = file.name;
        _ready = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepare() async {
    if (_bytes == null || _busy || !widget.client.available) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.uploadDiscoverVideo(_bytes!, _id);
      if (mounted && widget.client.available) {
        setState(() {
          _ready = true;
          _bytes = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    if (!_ready || !_accepted || _busy || !widget.client.available) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.post('discover_publish', {
        'id': _id,
        'caption': _caption.text.trim(),
        'accepted_rules': true,
      });
      if (mounted && widget.client.available) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Share a video')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Make a moment worth sharing.',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                const Text(
                  'MP4, MOV or WebM · 1–60 seconds · up to 50 MB. Your video stays private until you tap Publish. Unpublished drafts expire after 24 hours.',
                  style: TextStyle(height: 1.5),
                ),
                const SizedBox(height: 24),
                if (!_ready)
                  OutlinedButton.icon(
                    onPressed: _busy || !widget.client.available ? null : _pick,
                    icon: const Icon(Icons.video_library_outlined),
                    label: Text(_filename ?? 'Choose a video'),
                  ),
                if (_ready)
                  FilledButton.tonalIcon(
                    onPressed: _busy || !widget.client.available
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => DiscoverVideoViewer(
                                client: widget.client,
                                items: [
                                  {
                                    'id': _id,
                                    'caption': _caption.text,
                                    'author': {},
                                  },
                                ],
                                initialId: _id,
                              ),
                            ),
                          ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Preview private video'),
                  ),
                const SizedBox(height: 20),
                TextField(
                  key: const ValueKey('discover-caption'),
                  controller: _caption,
                  enabled: !_busy && widget.client.available,
                  maxLength: 500,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Caption (optional)',
                    hintText: 'Tell the story behind your clip…',
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _accepted,
                  onChanged: _busy || !widget.client.available
                      ? null
                      : (v) => setState(() => _accepted = v == true),
                  title: const Text(
                    'I have permission to share this video and its music.',
                  ),
                  subtitle: const Text(
                    'Keep it respectful and follow the KORLIX Community Guidelines. Published videos are visible to eligible Social members.',
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text(
                    'Preparing your video. Keep this screen open; longer clips can take a few minutes.',
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const ValueKey('discover-publish'),
                  onPressed: _busy || !widget.client.available
                      ? null
                      : _ready
                      ? (_accepted ? _publish : null)
                      : _bytes == null
                      ? null
                      : _prepare,
                  icon: Icon(
                    _ready ? Icons.public_rounded : Icons.cloud_upload_outlined,
                  ),
                  label: Text(
                    _ready ? 'Publish video' : 'Upload private draft',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// A single active controller; switching clips disposes media before loading the
/// next signed URL. Leaving the app, covering this route, or changing account
/// pauses playback. Audio starts only after a Play tap.
class DiscoverVideoViewer extends StatefulWidget {
  const DiscoverVideoViewer({
    super.key,
    required this.client,
    required this.items,
    required this.initialId,
    this.report,
  });
  final SocialClient client;
  final List<SocialMap> items;
  final String initialId;
  final String? report;
  @override
  State<DiscoverVideoViewer> createState() => _DiscoverVideoViewerState();
}

class _DiscoverVideoViewerState extends State<DiscoverVideoViewer>
    with WidgetsBindingObserver {
  late int _index = widget.items
      .indexWhere((i) => i['id'] == widget.initialId)
      .clamp(0, widget.items.length - 1);
  late final PageController _pages = PageController(initialPage: _index);
  VideoPlayerController? _player;
  String? _error;
  int _generation = 0;
  bool _loading = false;
  bool _playing = false;
  Timer? _visibility;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.addListener(_access);
    _visibility = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted && ModalRoute.of(context)?.isCurrent != true) {
        unawaited(_player?.pause());
      }
    });
  }

  void _access() {
    if (!widget.client.available) {
      _stop();
      if (mounted) {
        setState(() => _error = 'Your session changed. Reopen Social.');
      }
    }
  }

  void _stop() {
    _generation++;
    final player = _player;
    _player = null;
    player?.removeListener(_playerChanged);
    if (player != null) unawaited(_release(player));
    _loading = false;
    _playing = false;
  }

  Future<void> _release(VideoPlayerController player) async {
    try {
      await player.pause();
    } catch (_) {}
    try {
      await player.dispose();
    } catch (_) {}
  }

  void _playerChanged() {
    final value = _player?.value;
    if (!mounted || value == null) return;
    if (value.hasError) {
      _stop();
      setState(
        () => _error = 'Playback stopped. Tap Play to get a fresh link.',
      );
    } else if (_playing != value.isPlaying) {
      setState(() => _playing = value.isPlaying);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_player?.pause());
  }

  @override
  void dispose() {
    _stop();
    _visibility?.cancel();
    widget.client.removeListener(_access);
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    if (_loading || !widget.client.available) return;
    if (_player != null) {
      try {
        if (_player!.value.isPlaying) {
          await _player!.pause();
        } else {
          await _player!.play();
        }
      } catch (_) {
        _stop();
        if (mounted) {
          setState(() => _error = 'Playback stopped. Tap Play to try again.');
        }
      }
      if (mounted) setState(() {});
      return;
    }
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    VideoPlayerController? controller;
    try {
      final r = await widget.client.get('discover_link', {
        'id': widget.items[_index]['id'],
        if (widget.report != null) 'report': widget.report,
      });
      if (!mounted || !widget.client.available || generation != _generation) {
        return;
      }
      final url = Uri.tryParse('${r['url']}');
      if (url == null || url.scheme != 'https') {
        throw const SocialException('The playback link is unavailable.');
      }
      controller = VideoPlayerController.networkUrl(url);
      await controller.initialize();
      if (!mounted || !widget.client.available || generation != _generation) {
        await controller.dispose();
        return;
      }
      _player = controller;
      controller.addListener(_playerChanged);
      await controller.setLooping(true);
      if (!mounted || !widget.client.available || generation != _generation) {
        return;
      }
      if (ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        await controller.play();
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (controller != null) {
        if (identical(_player, controller)) _player = null;
        controller.removeListener(_playerChanged);
        await controller.dispose();
      }
      if (mounted && generation == _generation) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF060F19),
    appBar: AppBar(
      title: Text('Videos · ${_index + 1}/${widget.items.length}'),
    ),
    body: !widget.client.available
        ? const Center(child: Text('Your session changed.'))
        : Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Swipe up for the next video',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  scrollDirection: Axis.vertical,
                  itemCount: widget.items.length,
                  onPageChanged: (i) {
                    _stop();
                    setState(() {
                      _index = i;
                      _error = null;
                    });
                  },
                  itemBuilder: (context, i) {
                    final item = widget.items[i],
                        player = i == _index ? _player : null;
                    return LayoutBuilder(
                      builder: (context, c) => Column(
                        children: [
                          Expanded(
                            child: Center(
                              child:
                                  player != null && player.value.isInitialized
                                  ? AspectRatio(
                                      aspectRatio: player.value.aspectRatio,
                                      child: VideoPlayer(player),
                                    )
                                  : item['thumbnail_url'] is String
                                  ? Image.network(
                                      item['thumbnail_url'],
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.videocam_outlined,
                                        size: 80,
                                        color: Colors.white70,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.videocam_outlined,
                                      size: 80,
                                      color: Colors.white70,
                                    ),
                            ),
                          ),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: c.maxHeight * .45,
                            ),
                            child: SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  20,
                                  8,
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '${socialMap(item['author'])['name'] ?? 'Private preview'}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if ('${item['caption'] ?? ''}'.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          '${item['caption']}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    if (i == _index && _error != null)
                                      Text(
                                        _error!,
                                        style: const TextStyle(
                                          color: Colors.orangeAccent,
                                        ),
                                      ),
                                    const SizedBox(height: 8),
                                    FilledButton.icon(
                                      onPressed: _loading ? null : _play,
                                      icon: _loading
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Icon(
                                              player?.value.isPlaying == true
                                                  ? Icons.pause_rounded
                                                  : Icons.play_arrow_rounded,
                                            ),
                                      label: Text(
                                        _loading
                                            ? 'Opening…'
                                            : player?.value.isPlaying == true
                                            ? 'Pause'
                                            : 'Play',
                                      ),
                                    ),
                                    if (player != null &&
                                        player.value.isInitialized)
                                      VideoProgressIndicator(
                                        player,
                                        allowScrubbing: true,
                                        padding: const EdgeInsets.only(top: 12),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
  );
}
