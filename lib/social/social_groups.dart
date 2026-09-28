import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/korlix_theme.dart';
import '../theme/korlix_action_button.dart';
import 'social_client.dart';
import 'social_design.dart';
import 'social_threads.dart';

Future<void> socialOpenGroup(
  BuildContext context,
  SocialClient client,
  SocialMap me,
  SocialMap group,
) => Navigator.push<void>(
  context,
  MaterialPageRoute(
    builder: (chatContext) => SocialChatScreen(
      client: client,
      me: me,
      peer: group,
      groupChat: true,
      onGroupDetails: () async =>
          await Navigator.push<bool>(
            chatContext,
            MaterialPageRoute(
              builder: (_) => SocialGroupDetails(client: client, group: group),
            ),
          ) ??
          false,
    ),
  ),
);

class SocialGroupCard extends StatelessWidget {
  const SocialGroupCard({
    super.key,
    required this.group,
    required this.busy,
    required this.onOpen,
    required this.onAccept,
    required this.onDecline,
  });
  final SocialMap group;
  final bool busy;
  final VoidCallback onOpen, onAccept, onDecline;
  @override
  Widget build(BuildContext context) {
    final invited = group['state'] == 'invited', s = korlixSkinOf(context);
    return SocialPanel(
      accent: s.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    colors: [
                      s.primary.withValues(alpha: .3),
                      s.primary.withValues(alpha: .06),
                    ],
                  ),
                  border: Border.all(color: s.primary.withValues(alpha: .35)),
                ),
                child: Icon(Icons.groups_rounded, color: s.primary, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  invited
                      ? 'GROUP INVITATION'
                      : group['is_owner'] == true
                      ? 'YOUR GROUP'
                      : 'GROUP CHAT',
                  style: TextStyle(
                    color: s.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              if ((group['unread'] ?? 0) > 0)
                Badge(
                  label: Text('${group['unread']}'),
                  child: const Icon(Icons.chat_bubble_outline_rounded),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '${group['name']}',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '${group['member_count']} joined · ${group['invited_count']} invited',
            style: TextStyle(color: s.mutedText),
          ),
          const SizedBox(height: 12),
          if (invited) ...[
            Text(
              'Invited by ${socialMap(group['owner_profile'])['name'] ?? 'the group owner'}',
              style: TextStyle(color: s.primary, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Join to start chatting. You will see new messages from the moment you join.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 16),
            KorlixActionButton(
              label: 'Accept invitation',
              icon: Icons.group_add_outlined,
              expand: true,
              onPressed: busy ? null : onAccept,
            ),
            TextButton(
              onPressed: busy ? null : onDecline,
              child: const Text('Decline'),
            ),
          ] else
            KorlixActionButton(
              label: 'Open group',
              icon: Icons.chat_bubble_outline_rounded,
              expand: true,
              onPressed: onOpen,
            ),
        ],
      ),
    );
  }
}

class SocialGroupInvite extends StatefulWidget {
  const SocialGroupInvite({
    super.key,
    required this.client,
    this.group,
    this.excluded = const {},
  });
  final SocialClient client;
  final SocialMap? group;
  final Set<String> excluded;
  @override
  State<SocialGroupInvite> createState() => _SocialGroupInviteState();
}

class _SocialGroupInviteState extends State<SocialGroupInvite> {
  final _name = TextEditingController(), _search = TextEditingController();
  final _selected = <String, SocialMap>{};
  List<SocialMap> _connections = [];
  Timer? _debounce;
  String? _error, _requestId, _requestShape;
  bool _loading = false, _saving = false, _more = false;
  int _offset = 0, _generation = 0;
  bool get _available => widget.client.available;
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_access);
    unawaited(_load());
  }

  void _access() {
    if (!_available && mounted) {
      _generation++;
      setState(() {
        _selected.clear();
        _connections = [];
        _name.clear();
        _search.clear();
        _error = 'Your session changed. Close Social and sign in again.';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.client.removeListener(_access);
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool next = false}) async {
    if (!_available) return;
    final generation = ++_generation, offset = next ? _offset + 40 : 0;
    setState(() => _loading = true);
    try {
      final r = await widget.client.get('connections', {
        'state': 'accepted',
        'q': _search.text.trim(),
        'offset': offset,
      });
      if (!mounted || generation != _generation || !_available) return;
      final list = socialItems(r['items']);
      setState(() {
        _connections = next
            ? [..._connections, ...list.take(40)]
            : list.take(40).toList();
        _more = list.length > 40;
        _offset = offset;
        _error = null;
      });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = '$e');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_saving || !_available) return;
    if (_selected.isEmpty ||
        (widget.group == null && _name.text.trim().isEmpty)) {
      setState(
        () => _error = 'Add a group name and select at least one connection.',
      );
      return;
    }
    final ids = _selected.keys.toList()..sort();
    final shape = '${_name.text.trim()}|${ids.join(',')}';
    if (shape != _requestShape) {
      _requestId = socialId();
      _requestShape = shape;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.client
          .post(widget.group == null ? 'group_create' : 'group_invite', {
            'group': widget.group?['id'] ?? _requestId,
            'members': ids,
            if (widget.group == null) 'name': _name.text.trim(),
          });
      if (mounted && _available) {
        Navigator.pop(context, widget.group ?? socialMap(result['group']));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.group == null ? 'Create a group' : 'Invite people'),
    ),
    bottomNavigationBar: !_available
        ? null
        : SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: KorlixActionButton(
                label: _saving
                    ? 'Sending invitations…'
                    : widget.group == null
                    ? 'Create & invite (${_selected.length})'
                    : 'Invite selected (${_selected.length})',
                icon: Icons.group_add_rounded,
                expand: true,
                onPressed: _saving || _selected.isEmpty ? null : _submit,
              ),
            ),
          ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_available) ...[
                SocialPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.groups_rounded,
                        size: 40,
                        color: korlixSkinOf(context).primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.group == null
                            ? 'Bring your people together.'
                            : 'Make room for more.',
                        style: const TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Select several connections and invite them together. Each person chooses whether to join. Up to 50 people, including pending invitations.',
                        style: TextStyle(height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (widget.group == null) ...[
                  TextField(
                    controller: _name,
                    enabled: !_saving,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Group name',
                      hintText: 'Family, project team, weekend plans…',
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _search,
                  enabled: !_saving,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 300),
                      () => _load(),
                    );
                  },
                  decoration: const InputDecoration(
                    labelText: 'Search your connections',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                if (_selected.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final p in _selected.values.take(6))
                        InputChip(
                          label: Text('${p['name']}'),
                          onDeleted: _saving
                              ? null
                              : () => setState(() => _selected.remove(p['id'])),
                        ),
                      if (_selected.length > 6)
                        Chip(label: Text('+${_selected.length - 6} more')),
                    ],
                  ),
                const SizedBox(height: 8),
                if (_connections.isEmpty && !_loading)
                  const SocialEmpty(
                    icon: Icons.person_add_alt_1_outlined,
                    title: 'No connections found.',
                    body:
                        'Connect with people in Social first. Once a follow request is accepted, you can invite them here.',
                  ),
                for (final p in _connections)
                  CheckboxListTile(
                    key: ValueKey('invite-${p['id']}'),
                    value: _selected.containsKey(p['id']),
                    onChanged: _saving || widget.excluded.contains(p['id'])
                        ? null
                        : (v) {
                            if (v == true && _selected.length >= 49) {
                              socialNotice(
                                context,
                                'Select up to 49 people at once.',
                              );
                              return;
                            }
                            setState(
                              () => v == true
                                  ? _selected[p['id']] = p
                                  : _selected.remove(p['id']),
                            );
                          },
                    secondary: SocialAvatar(member: p, size: 38),
                    title: Text('${p['name']}'),
                    subtitle: Text(
                      widget.excluded.contains(p['id'])
                          ? 'Already joined or invited'
                          : '@${p['handle']}',
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  ),
                if (_more)
                  TextButton(
                    onPressed: _loading ? null : () => _load(next: true),
                    child: const Text('Load more connections'),
                  ),
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_error != null && _available)
                TextButton(
                  onPressed: _loading ? null : () => _load(),
                  child: const Text('Refresh connections'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SocialGroupDetails extends StatefulWidget {
  const SocialGroupDetails({
    super.key,
    required this.client,
    required this.group,
  });
  final SocialClient client;
  final SocialMap group;
  @override
  State<SocialGroupDetails> createState() => _SocialGroupDetailsState();
}

class _SocialGroupDetailsState extends State<SocialGroupDetails> {
  late SocialMap _group = widget.group;
  List<SocialMap> _members = [];
  final _name = TextEditingController();
  bool _busy = false, _unavailable = false, _editing = false;
  String? _error;
  Timer? _poll;
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_access);
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_busy && ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_load());
      }
    });
  }

  void _access() {
    if (!widget.client.available && mounted) {
      setState(() {
        _members = [];
        _group = {};
        _name.clear();
        _unavailable = true;
        _error = 'Your session changed. Close Social and sign in again.';
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    widget.client.removeListener(_access);
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!widget.client.available || _unavailable) return;
    try {
      final r = await widget.client.get('group_details', {
        'group': widget.group['id'],
      });
      if (mounted && widget.client.available) {
        setState(() {
          _group = socialMap(r['group']);
          _members = socialItems(r['members']);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          if (e is SocialException && [401, 403, 404].contains(e.status)) {
            _members = [];
            _group = {};
            _name.clear();
            _unavailable = true;
          }
        });
      }
    }
  }

  Future<void> _change(String action, [SocialMap data = const {}]) async {
    if (_busy || _unavailable || !widget.client.available) return;
    setState(() => _busy = true);
    try {
      await widget.client.post(action, {'group': widget.group['id'], ...data});
      if (!mounted || !widget.client.available) return;
      if (action == 'group_leave') {
        Navigator.pop(context, true);
        return;
      }
      setState(() => _editing = false);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invite() async {
    await Navigator.push<SocialMap>(
      context,
      MaterialPageRoute(
        builder: (_) => SocialGroupInvite(
          client: widget.client,
          group: _group,
          excluded: {
            for (final m in _members) '${socialMap(m['profile'])['id']}',
          },
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Group details')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (!_unavailable) ...[
                SocialPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.groups_rounded,
                        size: 54,
                        color: korlixSkinOf(context).primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${_group['name'] ?? ''}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${_group['member_count'] ?? 1} joined · ${_group['invited_count'] ?? 0} invited',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Members see messages sent after joining. Leaving closes access. Messages from blocked members are hidden.',
                        textAlign: TextAlign.center,
                        style: TextStyle(height: 1.5),
                      ),
                      if (_group['is_owner'] == true) ...[
                        const SizedBox(height: 20),
                        KorlixActionButton(
                          label: 'Invite people',
                          icon: Icons.group_add_outlined,
                          expand: true,
                          onPressed: _busy ? null : _invite,
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Rename group'),
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _name.text = '${_group['name']}';
                                  _editing = !_editing;
                                }),
                        ),
                        if (_editing) ...[
                          TextField(
                            controller: _name,
                            maxLength: 80,
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              labelText: 'Group name',
                            ),
                          ),
                          KorlixActionButton(
                            label: 'Save name',
                            icon: Icons.check_rounded,
                            onPressed: _busy
                                ? null
                                : () => _change('group_rename', {
                                    'name': _name.text.trim(),
                                  }),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Members & invitations',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                for (final m in _members)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    leading: SocialAvatar(
                      member: socialMap(m['profile']),
                      size: 42,
                    ),
                    title: Text('${socialMap(m['profile'])['name']}'),
                    subtitle: Text(
                      m['is_owner'] == true
                          ? 'Group owner'
                          : m['state'] == 'invited'
                          ? 'Invitation pending'
                          : 'Member',
                    ),
                    trailing:
                        _group['is_owner'] == true && m['is_owner'] != true
                        ? IconButton(
                            tooltip: m['state'] == 'invited'
                                ? 'Cancel invitation'
                                : 'Remove member',
                            icon: const Icon(Icons.person_remove_outlined),
                            onPressed: _busy
                                ? null
                                : () async {
                                    if (await socialConfirm(
                                      context,
                                      m['state'] == 'invited'
                                          ? 'Cancel invitation?'
                                          : 'Remove member?',
                                      '${socialMap(m['profile'])['name']} will no longer have access to this group.',
                                      action: 'Remove',
                                    )) {
                                      await _change('group_remove', {
                                        'member': socialMap(m['profile'])['id'],
                                      });
                                    }
                                  },
                          )
                        : null,
                  ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Leave group'),
                  onPressed: _busy
                      ? null
                      : () async {
                          if (await socialConfirm(
                            context,
                            'Leave this group?',
                            _group['is_owner'] == true
                                ? 'Ownership will pass to another joined member. If no one else has joined, the group will close.'
                                : 'You will lose access to this conversation. A new invitation is needed to rejoin.',
                            action: 'Leave',
                          )) {
                            await _change('group_leave');
                          }
                        },
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_busy) const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    ),
  );
}
