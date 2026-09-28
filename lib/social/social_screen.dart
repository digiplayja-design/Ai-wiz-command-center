import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/korlix_theme.dart';
import '../theme/korlix_action_button.dart';
import 'social_client.dart';
import 'social_design.dart';
import 'social_forms.dart';
import 'social_threads.dart';

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key, required this.client});
  final SocialClient client;
  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  SocialMap? _profile;
  List<SocialMap> _categories = [], _items = [];
  String? _category, _error;
  String _connectionFilter = 'all';
  bool _initialized = false,
      _loading = false,
      _mutating = false,
      _more = false,
      _online = false,
      _foreground = true,
      _moderator = false,
      _denied = false;
  int _tab = 0, _offset = 0, _generation = 0;
  Timer? _poll, _heartbeat, _debounce;
  SocialClient get client => widget.client;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    client.addListener(_access);
    unawaited(_initialize());
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_foreground &&
          _profile != null &&
          !_loading &&
          !_mutating &&
          _offset == 0 &&
          ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_load(quiet: true));
      }
    });
    _heartbeat = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _presence(_foreground),
    );
  }

  void _access() {
    if (!client.available && mounted) {
      _generation++;
      setState(() {
        _denied = true;
        _profile = null;
        _items = [];
        _error = null;
      });
    }
  }

  void _presence(bool active) {
    if (_profile == null || !client.available) return;
    unawaited(
      client
          .post('presence', {'active': active})
          .catchError((_) => <String, dynamic>{}),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _presence(_foreground);
  }

  @override
  void dispose() {
    _presence(false);
    _poll?.cancel();
    _heartbeat?.cancel();
    _debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    client.removeListener(_access);
    client.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() => _loading = true);
    try {
      final r = await client.get('bootstrap');
      if (!mounted || _denied) return;
      setState(() {
        _profile = r['profile'] == null ? null : socialMap(r['profile']);
        _categories = socialItems(r['categories']);
        _moderator = r['moderator'] == true;
        _initialized = true;
        _error = null;
      });
      if (_profile != null) {
        _presence(true);
        await _load();
      }
    } catch (e) {
      if (mounted && !_denied) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _load({bool quiet = false, bool next = false}) async {
    if (_profile == null || _denied) return;
    final generation = ++_generation,
        offset = next ? _offset + (_tab == 2 ? 20 : 40) : 0;
    if (!quiet) setState(() => _loading = true);
    try {
      final r = await client.get(
        _tab == 0
            ? 'members'
            : _tab == 1
            ? 'connections'
            : 'topics',
        {
          'offset': offset,
          'q': _search.text.trim(),
          if (_tab == 0) 'online': _online,
          if (_tab == 1) 'state': _connectionFilter,
          if (_tab == 2 && _category != null) 'category': _category,
        },
      );
      if (!mounted || generation != _generation || _denied) return;
      final items = socialItems(r['items']), size = _tab == 2 ? 20 : 40;
      setState(() {
        _items = next
            ? [..._items, ...items.take(size)]
            : items.take(size).toList();
        _more = items.length > size;
        _offset = offset;
        _error = null;
      });
    } catch (e) {
      if (mounted && generation == _generation && !_denied) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _switch(int tab) {
    if (_tab == tab) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    _debounce?.cancel();
    setState(() {
      _tab = tab;
      _search.clear();
      _items = [];
      _offset = 0;
      _more = false;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(_load());
  }

  Future<void> _editProfile() async {
    final result = await Navigator.push<SocialMap>(
      context,
      MaterialPageRoute(
        builder: (_) => SocialProfileForm(client: client, profile: _profile),
      ),
    );
    if (!mounted || _denied) return;
    if (result != null) {
      setState(() => _profile = result);
      _presence(true);
      await _load();
    }
  }

  Future<void> _memberAction(String action, SocialMap p) async {
    if (action == 'report') {
      final sent = await socialReport(context, client, 'member', p['id']);
      if (mounted && sent) {
        socialNotice(context, 'Report submitted for review.');
      }
      return;
    }
    if (action == 'block' &&
        !await socialConfirm(
          context,
          'Block ${p['name']}?',
          'This removes your connection and prevents messages and follow requests. Your forum content will be hidden from each other.',
          action: 'Block member',
        )) {
      return;
    }
    if (!mounted) return;
    if (action == 'remove' &&
        !await socialConfirm(
          context,
          p['connection'] == 'accepted'
              ? 'Remove connection?'
              : 'Cancel follow request?',
          'Messaging will require a newly accepted follow request.',
          action: 'Remove',
        )) {
      return;
    }
    if (!mounted || _mutating) return;
    setState(() => _mutating = true);
    try {
      await client.post(action, {'peer': p['id']});
      if (mounted && !_denied) {
        socialNotice(context, switch (action) {
          'request' => 'Follow request sent.',
          'accept' => 'Connected. You can now message each other.',
          'decline' => 'Request declined.',
          'block' => 'Member blocked.',
          _ => 'Connection updated.',
        });
        await _load();
      }
    } catch (e) {
      if (mounted && !_denied) socialNotice(context, e);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _chat(SocialMap p) async {
    final me = _profile;
    if (me == null) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SocialChatScreen(client: client, me: me, peer: p),
      ),
    );
    if (mounted && !_denied) await _load();
  }

  Future<void> _topic(String id) async {
    final me = _profile;
    if (me == null) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SocialTopicScreen(
          client: client,
          me: me,
          id: id,
          categories: _categories,
        ),
      ),
    );
    if (mounted && !_denied) await _load();
  }

  Future<void> _compose() async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SocialComposeTopic(
          client: client,
          categories: _categories,
          category: _category,
        ),
      ),
    );
    if (mounted && !_denied && id != null) await _topic(id);
  }

  Future<void> _manage(String action) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SocialManagementScreen(client: client, action: action),
      ),
    );
    if (mounted && !_denied) await _load();
  }

  Widget _heading(String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ),
        ?trailing,
      ],
    ),
  );
  Widget _hero() {
    final title = [
      'Find your people.',
      'Keep the conversation going.',
      'A place for every perspective.',
    ][_tab];
    final subtitle = [
      'Discover KORLIX members. Follow, connect and make a little room for something new.',
      'Approve a follow request to talk privately. Your connections, on your terms.',
      'Start a topic, share an idea and join conversations around the things you care about.',
    ][_tab];
    return SocialPanel(
      child: LayoutBuilder(
        builder: (context, c) => Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'KORLIX  /  SOCIAL',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.5,
                      color: korlixSkinOf(context).primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: c.maxWidth > 600 ? 34 : 27,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: -.7,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    subtitle,
                    style: TextStyle(
                      height: 1.5,
                      color: korlixSkinOf(context).mutedText,
                    ),
                  ),
                ],
              ),
            ),
            if (c.maxWidth > 500) ...[
              const SizedBox(width: 18),
              const SocialOrbit(size: 170),
            ],
          ],
        ),
      ),
    );
  }

  Widget _searchBox() => TextField(
    controller: _search,
    onChanged: (_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () => _load());
    },
    decoration: InputDecoration(
      prefixIcon: const Icon(Icons.search_rounded),
      hintText: [
        'Search names or handles',
        'Search your connections',
        'Search topics and discussions',
      ][_tab],
      suffixIcon: IconButton(
        tooltip: 'Clear search',
        onPressed: () {
          _search.clear();
          unawaited(_load());
        },
        icon: const Icon(Icons.close_rounded),
      ),
    ),
  );
  Widget _memberCard(SocialMap p) {
    final accepted = p['connection'] == 'accepted',
        pending = p['connection'] == 'pending',
        incoming = p['incoming'] == true;
    return SocialPanel(
      accent: socialColor(p['color']),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SocialAvatar(member: p),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: 'Member options',
                onSelected: (a) => _memberAction(a, p),
                itemBuilder: (_) => [
                  if (pending || accepted)
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(
                        accepted ? 'Remove connection' : 'Cancel request',
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'report',
                    child: Text('Report member'),
                  ),
                  const PopupMenuItem(
                    value: 'block',
                    child: Text('Block member'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            p['name'] ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
          ),
          const SizedBox(height: 4),
          Text(
            '@${p['handle']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: korlixSkinOf(context).mutedText,
              fontSize: 12,
            ),
          ),
          if (p['online'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '● Online in Social',
                style: TextStyle(
                  fontSize: 11,
                  color: korlixSkinOf(context).success,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            _tab == 1
                ? (p['last_message'] ??
                      (pending
                          ? (incoming
                                ? 'Wants to follow you'
                                : 'Waiting for approval')
                          : 'Say hello to your connection.'))
                : (p['bio']?.toString().isNotEmpty == true
                      ? p['bio']
                      : 'Open to new conversations.'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              height: 1.5,
              fontSize: 13,
              color: korlixSkinOf(context).mutedText,
            ),
          ),
          const SizedBox(height: 16),
          if (accepted)
            KorlixActionButton(
              label: (p['unread'] ?? 0) > 0
                  ? 'Message · ${p['unread']} new'
                  : 'Message',
              icon: Icons.chat_bubble_outline_rounded,
              expand: true,
              size: KorlixButtonSize.compact,
              onPressed: () => _chat(p),
            )
          else if (pending && incoming) ...[
            KorlixActionButton(
              label: 'Accept follow',
              icon: Icons.person_add_alt_1_rounded,
              expand: true,
              size: KorlixButtonSize.compact,
              onPressed: _mutating ? null : () => _memberAction('accept', p),
            ),
            TextButton(
              onPressed: _mutating ? null : () => _memberAction('decline', p),
              child: const Text('Decline'),
            ),
          ] else if (pending)
            OutlinedButton.icon(
              onPressed: _mutating ? null : () => _memberAction('remove', p),
              icon: const Icon(Icons.schedule_rounded, size: 16),
              label: const Text('Requested'),
            )
          else
            KorlixActionButton(
              label: 'Follow',
              icon: Icons.person_add_alt_1_outlined,
              expand: true,
              size: KorlixButtonSize.compact,
              onPressed: _mutating ? null : () => _memberAction('request', p),
            ),
        ],
      ),
    );
  }

  Widget _grid(List<Widget> children) => LayoutBuilder(
    builder: (context, c) {
      final columns = c.maxWidth >= 900
              ? 3
              : c.maxWidth >= 550
              ? 2
              : 1,
          width = (c.maxWidth - (columns - 1) * 16) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
  Widget _forums() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_category != null)
            TextButton.icon(
              onPressed: () {
                setState(() => _category = null);
                unawaited(_load());
              },
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('All forums'),
            )
          else
            const Text(
              'EXPLORE YOUR INTERESTS',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w800,
              ),
            ),
          KorlixActionButton(
            label: 'Start a topic',
            icon: Icons.add_rounded,
            onPressed: _compose,
            size: KorlixButtonSize.compact,
          ),
        ],
      ),
      const SizedBox(height: 18),
      if (_category == null) ...[
        LayoutBuilder(
          builder: (context, c) {
            final columns = c.maxWidth >= 800 ? 4 : 2,
                width = (c.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final category in _categories)
                  SizedBox(
                    width: width,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () {
                          setState(() => _category = category['id']);
                          if (_scroll.hasClients) _scroll.jumpTo(0);
                          unawaited(_load());
                        },
                        child: SocialPanel(
                          accent: socialColor(category['color']),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  gradient: LinearGradient(
                                    colors: [
                                      socialColor(
                                        category['color'],
                                      ).withValues(alpha: .3),
                                      socialColor(
                                        category['color'],
                                      ).withValues(alpha: .07),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: socialColor(
                                      category['color'],
                                    ).withValues(alpha: .4),
                                  ),
                                ),
                                child: Icon(
                                  socialIcon(category['id']),
                                  color: korlixSkinOf(context).isLight
                                      ? Theme.of(context).colorScheme.primary
                                      : socialColor(category['color']),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                category['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                category['description'],
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                  color: korlixSkinOf(context).mutedText,
                                ),
                              ),
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
        _heading('Latest discussions'),
      ] else
        _heading(
          _categories.where((c) => c['id'] == _category).firstOrNull?['name'] ??
              'Discussions',
        ),
      if (_items.isEmpty && !_loading && _error == null)
        const SocialEmpty(
          icon: Icons.forum_outlined,
          title: 'Make the first move.',
          body: 'No topics here yet. Start a conversation for others to join.',
        ),
      for (final t in _items)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: () => _topic(t['id']),
              child: SocialPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SocialAvatar(
                          member: socialMap(t['author']),
                          size: 32,
                          showStatus: false,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${socialMap(t['author'])['name']} · ${socialTime(t['created_at'])}',
                            style: TextStyle(
                              fontSize: 12,
                              color: korlixSkinOf(context).mutedText,
                            ),
                          ),
                        ),
                        if (t['locked'] == true)
                          const Icon(Icons.lock_outline_rounded, size: 17),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      t['title'],
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t['body'],
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        height: 1.5,
                        color: korlixSkinOf(context).mutedText,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        Text(
                          _categories
                                  .where((c) => c['id'] == t['category'])
                                  .firstOrNull?['name'] ??
                              '',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: korlixSkinOf(context).primary,
                          ),
                        ),
                        Text(
                          '${t['reply_count']} replies',
                          style: TextStyle(
                            fontSize: 12,
                            color: korlixSkinOf(context).mutedText,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('KORLIX Social'),
      actions: [
        IconButton(
          tooltip: 'Refresh Social',
          onPressed: _loading
              ? null
              : () => _profile == null ? _initialize() : _load(),
          icon: const Icon(Icons.refresh_rounded),
        ),
        if (_profile != null)
          PopupMenuButton<String>(
            tooltip: 'Social settings',
            onSelected: (v) => v == 'profile' ? _editProfile() : _manage(v),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'profile',
                child: Text('My Social profile'),
              ),
              const PopupMenuItem(
                value: 'blocks',
                child: Text('Blocked members'),
              ),
              if (_moderator)
                const PopupMenuItem(
                  value: 'reports',
                  child: Text('Moderation reports'),
                ),
            ],
          ),
      ],
    ),
    bottomNavigationBar: _profile == null || _denied
        ? null
        : NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: _switch,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.people_outline_rounded),
                selectedIcon: Icon(Icons.people_rounded),
                label: 'People',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline_rounded),
                selectedIcon: Icon(Icons.chat_bubble_rounded),
                label: 'Messages',
              ),
              NavigationDestination(
                icon: Icon(Icons.forum_outlined),
                selectedIcon: Icon(Icons.forum_rounded),
                label: 'Forums',
              ),
            ],
          ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: RefreshIndicator(
            onRefresh: () => _profile == null ? _initialize() : _load(),
            child: ListView(
              controller: _scroll,
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 430 ? 16 : 26,
              ),
              children: [
                if (_denied)
                  const SocialEmpty(
                    icon: Icons.lock_outline_rounded,
                    title: 'Sign in to join the conversation.',
                    body:
                        'Sign in to your KORLIX account, then reopen Social. Your previous account’s content has been cleared.',
                  )
                else if (_profile == null) ...[
                  const Center(child: SocialOrbit(size: 210)),
                  const SizedBox(height: 8),
                  const Text(
                    'More than a connection.\nA community.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Find your people, talk privately and explore ideas together. Welcome to KORLIX Social.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, height: 1.6),
                  ),
                  const SizedBox(height: 28),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_initialized)
                    KorlixActionButton(
                      label: 'Create my Social profile',
                      icon: Icons.person_add_alt_1_rounded,
                      onPressed: _editProfile,
                      expand: true,
                    ),
                  const SizedBox(height: 30),
                  for (final item in [
                    (
                      Icons.people_outline,
                      'People',
                      'Discover members and choose who you connect with.',
                    ),
                    (
                      Icons.chat_bubble_outline,
                      'Private conversations',
                      'An accepted follow request opens a two-way conversation.',
                    ),
                    (
                      Icons.forum_outlined,
                      'Forums for your interests',
                      'Sports, Entertainment, Politics, Religion, Stock Market and more.',
                    ),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: SocialPanel(
                        child: Row(
                          children: [
                            Icon(item.$1, size: 26),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.$2,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.$3,
                                    style: const TextStyle(height: 1.5),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ] else ...[
                  _hero(),
                  const SizedBox(height: 22),
                  _searchBox(),
                  const SizedBox(height: 18),
                  if (_tab == 0)
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilterChip(
                          label: const Text('Online now'),
                          avatar: const Icon(Icons.circle, size: 10),
                          selected: _online,
                          onSelected: (v) {
                            setState(() => _online = v);
                            unawaited(_load());
                          },
                        ),
                        TextButton.icon(
                          onPressed: () {
                            _switch(1);
                            setState(() => _connectionFilter = 'pending');
                            unawaited(_load());
                          },
                          icon: const Icon(Icons.person_add_alt_outlined),
                          label: const Text('Follow requests'),
                        ),
                      ],
                    ),
                  if (_tab == 1)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final f in [
                          ('all', 'All connections'),
                          ('accepted', 'Connected'),
                          ('pending', 'Requests'),
                        ])
                          ChoiceChip(
                            label: Text(f.$2),
                            selected: _connectionFilter == f.$1,
                            onSelected: (_) {
                              setState(() => _connectionFilter = f.$1);
                              unawaited(_load());
                            },
                          ),
                      ],
                    ),
                  if (_tab < 2) ...[
                    _heading(
                      _tab == 0
                          ? 'People to connect with'
                          : _connectionFilter == 'pending'
                          ? 'Follow requests'
                          : 'Your connections',
                    ),
                    if (_items.isEmpty && !_loading && _error == null)
                      SocialEmpty(
                        icon: _tab == 0
                            ? Icons.people_outline
                            : Icons.chat_bubble_outline,
                        title: _search.text.isNotEmpty
                            ? 'No matches yet.'
                            : _tab == 0
                            ? 'A community starts with you.'
                            : 'Your conversations start here.',
                        body: _tab == 0
                            ? 'Members appear here after creating their Social profile. Try another search or come back as the community grows.'
                            : 'Find someone in People and request a follow. Once accepted, you can message each other.',
                        action: _tab == 1
                            ? TextButton(
                                onPressed: () => _switch(0),
                                child: const Text('Discover people'),
                              )
                            : null,
                      ),
                    _grid([for (final p in _items) _memberCard(p)]),
                  ] else
                    _forums(),
                ],
                if (_error != null && !_denied)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: SocialPanel(
                      child: Column(
                        children: [
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                _profile == null ? _initialize() : _load(),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_loading && _profile != null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (_more && !_loading)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: OutlinedButton(
                      onPressed: () => _load(next: true),
                      child: const Text('Load more'),
                    ),
                  ),
                if (_profile != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 24, bottom: 12),
                    child: Text(
                      'Community, on your terms.  •  Block and report from member menus.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: korlixSkinOf(context).mutedText,
                      ),
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
