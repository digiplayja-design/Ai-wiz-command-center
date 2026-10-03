import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/korlix_action_button.dart';
import '../theme/korlix_theme.dart';
import 'social_albums.dart';
import 'social_client.dart';
import 'social_design.dart';
import 'social_forms.dart';
import 'social_profile_details.dart';
import 'social_threads.dart';

/// Public posts use the same moderated discussion and reply flow as forums.
class SocialWallComposerCard extends StatelessWidget {
  const SocialWallComposerCard({
    super.key,
    required this.profile,
    required this.onPost,
    required this.onStatus,
    required this.onProfile,
  });
  final SocialMap profile;
  final VoidCallback onPost, onStatus, onProfile;

  @override
  Widget build(BuildContext context) => SocialPanel(
    accent: const Color(0xFFA994FF),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onProfile,
              borderRadius: BorderRadius.circular(32),
              child: SocialAvatar(member: profile, showStatus: false),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your voice belongs here.',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${profile['status_caption'] ?? ''}'.trim().isNotEmpty
                        ? profile['status_caption']
                        : 'Share a thought, start a thread, or tell your people what’s new.',
                    style: TextStyle(
                      height: 1.5,
                      color: korlixSkinOf(context).mutedText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        KorlixActionButton(
          key: const ValueKey('social-write-wall'),
          label: 'Write on your wall',
          icon: Icons.edit_note_rounded,
          onPressed: onPost,
          expand: true,
          accent: const Color(0xFFA994FF),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton.icon(
              key: const ValueKey('social-update-status'),
              onPressed: onStatus,
              icon: const Icon(Icons.auto_awesome_outlined, size: 19),
              label: const Text('Update status caption'),
            ),
            TextButton.icon(
              onPressed: onProfile,
              icon: const Icon(Icons.account_circle_outlined, size: 19),
              label: const Text('View my profile'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Wall posts are public to KORLIX Social members and appear in your followers’ feeds.',
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: korlixSkinOf(context).mutedText,
          ),
        ),
      ],
    ),
  );
}

class SocialWallPostCard extends StatelessWidget {
  const SocialWallPostCard({
    super.key,
    required this.post,
    required this.onOpen,
    required this.onProfile,
  });
  final SocialMap post;
  final VoidCallback onOpen, onProfile;

  @override
  Widget build(BuildContext context) {
    final author = socialMap(post['author']);
    final title = '${post['title'] ?? ''}'.trim();
    final count = post['reply_count'] ?? 0;
    return SocialPanel(
      accent: socialColor(author['color']),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('wall-author-${post['id']}'),
            onTap: onProfile,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SocialAvatar(member: author, size: 44, showStatus: false),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SocialMemberName(
                          member: author,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '@${author['handle'] ?? ''} · ${socialTime(post['created_at'])}',
                          style: TextStyle(
                            fontSize: 11,
                            color: korlixSkinOf(context).mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 21),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          InkWell(
            key: ValueKey('wall-post-${post['id']}'),
            onTap: onOpen,
            borderRadius: BorderRadius.circular(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title.isNotEmpty) ...[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  '${post['body'] ?? ''}',
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(height: 1.6, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: Text(
                  '$count ${count == 1 ? 'reply' : 'replies'} · Open thread',
                ),
              ),
              Text(
                post['locked'] == true ? 'Replies closed' : 'Public wall post',
                style: TextStyle(
                  fontSize: 11,
                  color: korlixSkinOf(context).mutedText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Loads the profile again so optional details follow server-side audiences.
class SocialProfileWallScreen extends StatefulWidget {
  const SocialProfileWallScreen({
    super.key,
    required this.client,
    required this.me,
    required this.member,
    required this.categories,
    this.onProfileChanged,
    this.onChat,
    this.onBlocked,
    this.onConnectionRemoved,
  });
  final SocialClient client;
  final SocialMap me, member;
  final List<SocialMap> categories;
  final ValueChanged<SocialMap>? onProfileChanged;
  final ValueChanged<String>? onBlocked, onConnectionRemoved;
  final Future<void> Function(SocialMap member)? onChat;

  @override
  State<SocialProfileWallScreen> createState() =>
      _SocialProfileWallScreenState();
}

class _SocialProfileWallScreenState extends State<SocialProfileWallScreen>
    with WidgetsBindingObserver {
  SocialMap? _profile;
  List<SocialMap> _posts = [];
  String? _error;
  bool _loading = false, _mutating = false, _more = false, _about = false;
  int _generation = 0, _offset = 0;
  Timer? _presencePoll;
  bool _foreground = true, _refreshing = false;
  bool get _owned => widget.member['id'] == widget.me['id'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.addListener(_access);
    unawaited(_load());
    _presencePoll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_foreground &&
          !_loading &&
          !_refreshing &&
          !_mutating &&
          ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_load(quiet: true));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground &&
        !_loading &&
        !_refreshing &&
        !_mutating &&
        ModalRoute.of(context)?.isCurrent == true) {
      unawaited(_load(quiet: true));
    }
  }

  void _access() {
    if (!widget.client.available && mounted) {
      _generation++;
      setState(() {
        _profile = null;
        _posts = [];
        _loading = false;
        _more = false;
        _error = 'Your session changed. Close Social and sign in again.';
      });
    }
  }

  @override
  void dispose() {
    _presencePoll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.client.removeListener(_access);
    super.dispose();
  }

  Future<void> _load({bool next = false, bool quiet = false}) async {
    if (!widget.client.available) return;
    if (quiet) return _refreshProfile();
    final generation = ++_generation;
    final offset = next ? _offset + 20 : 0;
    _refreshing = true;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.client.get('member', {'peer': widget.member['id']}),
        widget.client.get('wall', {
          'member': widget.member['id'],
          'offset': offset,
        }),
      ]);
      if (!mounted || generation != _generation || !widget.client.available) {
        return;
      }
      final profile = socialMap(results[0]['profile']);
      if (profile['id'] != widget.member['id']) {
        throw const SocialException(
          'This profile is no longer available.',
          404,
        );
      }
      final incoming = [
        for (final page in results.skip(1))
          ...socialItems(page['items']).take(20),
      ];
      setState(() {
        _profile = profile;
        _posts = <String, SocialMap>{
          if (next)
            for (final post in _posts) '${post['id']}': post,
          for (final post in incoming) '${post['id']}': post,
        }.values.toList();
        _more = socialItems(results.last['items']).length > 20;
        _offset = offset;
        _error = null;
      });
      if (_owned) widget.onProfileChanged?.call(profile);
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = '$e';
          if (e is SocialException && [401, 403, 404].contains(e.status)) {
            _profile = null;
            _posts = [];
            _more = false;
          }
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _refreshProfile() async {
    if (_refreshing || !widget.client.available) return;
    final generation = ++_generation;
    _refreshing = true;
    try {
      final result = await widget.client.get('member', {
        'peer': widget.member['id'],
      });
      if (!mounted || generation != _generation || !widget.client.available) {
        return;
      }
      final profile = socialMap(result['profile']);
      if (profile['id'] != widget.member['id']) {
        throw const SocialException(
          'This profile is no longer available.',
          404,
        );
      }
      setState(() {
        _profile = profile;
        _posts = [
          for (final post in _posts)
            {
              ...post,
              if (socialMap(post['author'])['id'] == profile['id'])
                'author': {...socialMap(post['author']), ...profile},
            },
        ];
      });
      if (_owned) widget.onProfileChanged?.call(profile);
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        if (e is SocialException && [401, 403, 404].contains(e.status)) {
          _profile = null;
          _posts = [];
          _more = false;
          _error = '$e';
        } else {
          if (_profile != null) _profile = {..._profile!, 'online': null};
          _posts = [
            for (final post in _posts)
              {
                ...post,
                'author': {...socialMap(post['author']), 'online': null},
              },
          ];
        }
      });
    } finally {
      if (generation == _generation) _refreshing = false;
    }
  }

  Future<void> _edit() async {
    final profile = _profile;
    if (profile == null) return;
    final updated = await Navigator.push<SocialMap>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SocialProfileForm(client: widget.client, profile: profile),
      ),
    );
    if (!mounted || !widget.client.available || updated == null) return;
    widget.onProfileChanged?.call(updated);
    setState(() => _profile = updated);
    await _load();
  }

  Future<void> _compose() async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SocialComposeTopic(
          client: widget.client,
          categories: widget.categories,
          wall: true,
        ),
      ),
    );
    if (!mounted || !widget.client.available || id == null) return;
    await _openPost(id);
  }

  Future<void> _openPost(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SocialTopicScreen(
          client: widget.client,
          me: widget.me,
          id: id,
          categories: widget.categories,
        ),
      ),
    );
    if (mounted && widget.client.available) await _load();
  }

  Future<void> _memberAction(String action) async {
    final p = _profile;
    if (p == null || _mutating || !widget.client.available) return;
    if (action == 'report') {
      final sent = await socialReport(
        context,
        widget.client,
        'member',
        '${p['id']}',
      );
      if (mounted && sent) {
        socialNotice(context, 'Report submitted for review.');
      }
      return;
    }
    if (['block', 'remove'].contains(action)) {
      final approved = await socialConfirm(
        context,
        action == 'block' ? 'Block ${p['name']}?' : 'Remove this connection?',
        action == 'block'
            ? 'Your wall posts and profiles will be hidden from each other. This also removes your connection.'
            : 'Their updates will leave your Following feed. Messaging requires a newly accepted follow request.',
        action: action == 'block' ? 'Block member' : 'Remove',
      );
      if (!approved || !mounted) return;
    }
    setState(() => _mutating = true);
    try {
      await widget.client.post(action, {'peer': p['id']});
      if (!mounted || !widget.client.available) return;
      if (action == 'block') {
        widget.onBlocked?.call('${p['id']}');
        Navigator.pop(context);
        return;
      }
      if (action == 'remove') {
        widget.onConnectionRemoved?.call('${p['id']}');
        setState(() {
          _profile = null;
          _posts = [];
          _more = false;
        });
      }
      socialNotice(context, switch (action) {
        'request' => 'Follow request sent.',
        'accept' => 'Connected. Their updates are now in your Following feed.',
        'decline' => 'Follow request declined.',
        _ => 'Connection updated.',
      });
      await _load();
    } catch (e) {
      if (mounted && widget.client.available) socialNotice(context, e);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Widget _header(SocialMap p) => SocialPanel(
    accent: socialColor(p['color']),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SocialAvatar(member: p, size: 68),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SocialMemberName(
                    member: p,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '@${p['handle'] ?? ''}',
                    style: TextStyle(color: korlixSkinOf(context).mutedText),
                  ),
                  if (p['connection'] == 'accepted') ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Following · Connected',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if ('${p['status_caption'] ?? ''}'.trim().isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            p['status_caption'],
            style: const TextStyle(
              fontSize: 18,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if ('${p['bio'] ?? ''}'.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            p['bio'],
            style: TextStyle(
              height: 1.5,
              color: korlixSkinOf(context).mutedText,
            ),
          ),
        ],
        const SizedBox(height: 18),
        if (_owned)
          KorlixActionButton(
            label: 'Edit profile & status',
            icon: Icons.edit_outlined,
            onPressed: _edit,
            expand: true,
          )
        else if (p['connection'] == 'accepted' && widget.onChat != null)
          KorlixActionButton(
            label: 'Message',
            icon: Icons.chat_bubble_outline_rounded,
            onPressed: () => widget.onChat!(p),
            expand: true,
          )
        else if (p['connection'] == 'pending' && p['incoming'] == true) ...[
          KorlixActionButton(
            label: 'Accept follow',
            icon: Icons.person_add_alt_1_rounded,
            onPressed: _mutating ? null : () => _memberAction('accept'),
            expand: true,
          ),
          TextButton(
            onPressed: _mutating ? null : () => _memberAction('decline'),
            child: const Text('Decline'),
          ),
        ] else if (p['connection'] == 'pending')
          OutlinedButton.icon(
            onPressed: _mutating ? null : () => _memberAction('remove'),
            icon: const Icon(Icons.schedule_rounded),
            label: const Text('Follow requested'),
          )
        else if (p['connection'] != 'accepted')
          KorlixActionButton(
            label: 'Follow',
            icon: Icons.person_add_alt_1_outlined,
            onPressed: _mutating ? null : () => _memberAction('request'),
            expand: true,
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SocialAlbumsScreen(
                client: widget.client,
                profile: p,
                owned: _owned,
              ),
            ),
          ),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Photo albums'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_owned ? 'My Social profile' : 'Social profile'),
      actions: [
        if (!_owned && _profile != null)
          PopupMenuButton<String>(
            tooltip: 'Member options',
            onSelected: _mutating ? null : _memberAction,
            itemBuilder: (_) => [
              if (_profile!['connection'] != null)
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove connection'),
                ),
              const PopupMenuItem(
                value: 'report',
                child: Text('Report member'),
              ),
              const PopupMenuItem(value: 'block', child: Text('Block member')),
            ],
          ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(18),
              children: [
                if (_profile != null) ...[
                  _header(_profile!),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Wall'),
                        selected: !_about,
                        onSelected: (_) => setState(() => _about = false),
                      ),
                      ChoiceChip(
                        key: const ValueKey('social-profile-about'),
                        label: const Text('About'),
                        selected: _about,
                        onSelected: (_) => setState(() => _about = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_about)
                    socialProfileFields.any(
                          (field) =>
                              '${_profile![field.id] ?? ''}'.trim().isNotEmpty,
                        )
                        ? SocialProfileDetails(
                            profile: _profile!,
                            owned: _owned,
                          )
                        : SocialEmpty(
                            icon: Icons.person_outline_rounded,
                            title: _owned
                                ? 'Add a little more about you.'
                                : 'Nothing more shared yet.',
                            body: _owned
                                ? 'Your profile details are optional. Choose an audience for anything you add.'
                                : 'This member hasn’t shared optional details with you.',
                            action: _owned
                                ? TextButton(
                                    onPressed: _edit,
                                    child: const Text('Edit optional details'),
                                  )
                                : null,
                          )
                  else ...[
                    if (_owned) ...[
                      KorlixActionButton(
                        label: 'Write on your wall',
                        icon: Icons.edit_note_rounded,
                        onPressed: _compose,
                        expand: true,
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (_posts.isEmpty && !_loading && _error == null)
                      SocialEmpty(
                        icon: Icons.dynamic_feed_outlined,
                        title: _owned
                            ? 'Make this wall yours.'
                            : 'No wall posts yet.',
                        body: _owned
                            ? 'Share your first public thread with your followers.'
                            : 'Public updates will appear here when this member posts.',
                      ),
                    for (final post in _posts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: SocialWallPostCard(
                          post: post,
                          onOpen: () => _openPost('${post['id']}'),
                          onProfile: () => setState(() => _about = true),
                        ),
                      ),
                    if (_more && !_loading)
                      OutlinedButton(
                        onPressed: () => _load(next: true),
                        child: const Text('Load more posts'),
                      ),
                  ],
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  SocialPanel(
                    child: Column(
                      children: [
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        if (widget.client.available)
                          TextButton(
                            onPressed: _load,
                            child: const Text('Try again'),
                          ),
                      ],
                    ),
                  ),
                ],
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
