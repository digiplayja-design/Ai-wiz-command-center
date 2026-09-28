import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/korlix_theme.dart';
import '../theme/korlix_action_button.dart';
import 'social_client.dart';
import 'social_design.dart';
import 'social_forms.dart';

class SocialChatScreen extends StatefulWidget {
  const SocialChatScreen({
    super.key,
    required this.client,
    required this.me,
    required this.peer,
  });
  final SocialClient client;
  final SocialMap me, peer;
  @override
  State<SocialChatScreen> createState() => _SocialChatScreenState();
}

class _SocialChatScreenState extends State<SocialChatScreen>
    with WidgetsBindingObserver {
  final _text = TextEditingController(), _scroll = ScrollController();
  List<SocialMap> _messages = [];
  late SocialMap _peer = widget.peer;
  Timer? _timer;
  bool _loading = false,
      _sending = false,
      _more = false,
      _foreground = true,
      _unavailable = false;
  String? _error, _sendKey, _sendBody;
  int _generation = 0, _readThrough = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.addListener(_access);
    _scroll.addListener(_scrollChanged);
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_foreground &&
          !_loading &&
          !_sending &&
          ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_load(quiet: true));
      }
    });
  }

  void _access() {
    if (!widget.client.available && mounted) {
      _generation++;
      setState(() {
        _messages = [];
        _peer = {
          'id': '',
          'name': 'Conversation',
          'handle': '',
          'color': 'cyan',
        };
        _loading = false;
        _text.clear();
        _unavailable = true;
        _error = 'Your session changed. Close Social and sign in again.';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.client.removeListener(_access);
    WidgetsBinding.instance.removeObserver(this);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _atBottom =>
      !_scroll.hasClients ||
      _scroll.position.maxScrollExtent - _scroll.offset < 80;
  void _scrollChanged() {
    if (_atBottom) _markRead();
  }

  void _markRead() {
    if (!_foreground ||
        _messages.isEmpty ||
        !widget.client.available ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final seq = (_messages.last['seq'] as num).toInt();
    if (seq <= _readThrough) return;
    _readThrough = seq;
    unawaited(
      widget.client
          .post('read', {'peer': _peer['id'], 'through': seq})
          .catchError((_) {
            _readThrough = 0;
            return <String, dynamic>{};
          }),
    );
  }

  void _bottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
        _markRead();
      }
    });
  }

  Future<void> _load({bool quiet = false, bool older = false}) async {
    if (!widget.client.available || (_loading && quiet)) return;
    final g = ++_generation, atBottom = _atBottom;
    setState(() => _loading = true);
    try {
      final r = await widget.client.get('messages', {
        'peer': _peer['id'],
        if (older && _messages.isNotEmpty) 'before': _messages.first['seq'],
      });
      if (!mounted || g != _generation || !widget.client.available) return;
      final list = socialItems(r['items']),
          page = list.length > 50 ? list.skip(1).toList() : list;
      final merged = <String, SocialMap>{
        for (final m in _messages) m['id']: m,
        for (final m in page) m['id']: m,
      };
      setState(() {
        _messages = merged.values.toList()
          ..sort((a, b) => (a['seq'] as num).compareTo(b['seq'] as num));
        _peer = socialMap(r['peer']);
        if (older || _messages.length <= 50) _more = list.length > 50;
        _unavailable = false;
        _error = null;
      });
      if (!older && atBottom) _bottom();
    } catch (e) {
      if (mounted && g == _generation) {
        setState(() {
          _error = '$e';
          if (e is SocialException && [401, 403, 404].contains(e.status)) {
            _messages = [];
            _unavailable = true;
            _text.clear();
          }
        });
      }
    } finally {
      if (mounted && g == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending || _unavailable) return;
    if (_sendBody != body) {
      _sendBody = body;
      _sendKey = socialId();
    }
    setState(() => _sending = true);
    try {
      await widget.client.post('send', {
        'id': _sendKey,
        'peer': _peer['id'],
        'body': body,
      });
      if (!mounted || !widget.client.available) return;
      _text.clear();
      _sendBody = null;
      _sendKey = null;
      await _load();
      _bottom();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _messageAction(String action, SocialMap m) async {
    if (action == 'report') {
      final sent = await socialReport(
        context,
        widget.client,
        'message',
        m['id'],
      );
      if (mounted && sent) {
        socialNotice(context, 'Report submitted for review.');
      }
      return;
    }
    if (!await socialConfirm(
      context,
      'Remove this message?',
      'Its text will be removed for both members.',
      action: 'Remove',
    )) {
      return;
    }
    try {
      await widget.client.post('delete_message', {'id': m['id']});
      if (mounted) {
        setState(
          () => _messages = [
            for (final x in _messages)
              x['id'] == m['id'] ? {...x, 'body': '', 'deleted': true} : x,
          ],
        );
        await _load();
      }
    } catch (e) {
      if (mounted) socialNotice(context, e);
    }
  }

  Future<void> _connectionAction(String action) async {
    if (action == 'report') {
      await socialReport(context, widget.client, 'member', _peer['id']);
      return;
    }
    if (!await socialConfirm(
      context,
      action == 'block' ? 'Block ${_peer['name']}?' : 'Remove connection?',
      'This closes messaging. A new accepted follow request will be needed to reconnect.',
      action: action == 'block' ? 'Block' : 'Remove',
    )) {
      return;
    }
    try {
      await widget.client.post(action, {'peer': _peer['id']});
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) socialNotice(context, e);
    }
  }

  Widget _bubble(SocialMap m) {
    final mine = m['sender'] == widget.me['id'],
        s = korlixSkinOf(context),
        removed = m['deleted'] == true;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
          margin: EdgeInsets.only(
            left: mine ? 28 : 0,
            right: mine ? 0 : 28,
            bottom: 12,
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 10, 12),
          decoration: BoxDecoration(
            color: mine
                ? Color.alphaBlend(
                    s.primary.withValues(alpha: s.isLight ? .12 : .17),
                    s.panel,
                  )
                : s.panelDeep,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(22),
              topRight: const Radius.circular(22),
              bottomLeft: Radius.circular(mine ? 22 : 5),
              bottomRight: Radius.circular(mine ? 5 : 22),
            ),
            border: Border.all(color: s.border.withValues(alpha: .4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      mine ? 'You' : _peer['name'],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: s.mutedText,
                      ),
                    ),
                  ),
                  if (!removed)
                    PopupMenuButton<String>(
                      tooltip: 'Message options',
                      onSelected: (v) => _messageAction(v, m),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: mine ? 'delete' : 'report',
                          child: Text(
                            mine ? 'Remove message' : 'Report message',
                          ),
                        ),
                      ],
                      icon: const Icon(Icons.more_horiz_rounded, size: 18),
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
              SelectableText(
                removed ? 'Message removed' : m['body'],
                style: TextStyle(
                  height: 1.5,
                  color: removed ? s.mutedText : s.text,
                  fontStyle: removed ? FontStyle.italic : FontStyle.normal,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${socialTime(m['created_at'])}${mine && !removed ? (m['read_at'] != null ? ' · Read' : ' · Sent') : ''}',
                style: TextStyle(fontSize: 10, color: s.mutedText),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          SocialAvatar(member: _peer, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _peer['name'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _peer['online'] == true
                      ? 'Online in Social'
                      : 'Private conversation',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Conversation options',
          onSelected: _connectionAction,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'remove', child: Text('Remove connection')),
            PopupMenuItem(value: 'report', child: Text('Report member')),
            PopupMenuItem(value: 'block', child: Text('Block member')),
          ],
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              if (_error != null)
                Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Retry conversation',
                          onPressed: () => _load(),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 20),
                      child: Text(
                        'Connected by choice. Your messages are shared only with this connection. Reported messages may be reviewed by KORLIX moderators.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, height: 1.5),
                      ),
                    ),
                    if (_more)
                      TextButton(
                        onPressed: _loading ? null : () => _load(older: true),
                        child: const Text('Load earlier messages'),
                      ),
                    if (_messages.isEmpty && !_loading && !_unavailable)
                      SocialEmpty(
                        icon: Icons.waving_hand_outlined,
                        title: 'Say hello to ${_peer['name']}.',
                        body:
                            'You’re connected. Start with something you have in common.',
                      ),
                    for (final m in _messages) _bubble(m),
                    if (_loading && _messages.isEmpty)
                      const Center(child: CircularProgressIndicator()),
                  ],
                ),
              ),
              if (!_unavailable)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _text,
                          enabled: !_sending,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 2000,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Write a message…',
                            counterText: '',
                            contentPadding: EdgeInsets.all(16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        tooltip: _sending ? 'Sending message' : 'Send message',
                        onPressed: _sending ? null : _send,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(52, 52),
                          foregroundColor: korlixSkinOf(context).textOnAccent,
                        ),
                        icon: _sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                Icons.arrow_upward_rounded,
                                color: korlixSkinOf(context).textOnAccent,
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

class SocialTopicScreen extends StatefulWidget {
  const SocialTopicScreen({
    super.key,
    required this.client,
    required this.me,
    required this.id,
    required this.categories,
  });
  final SocialClient client;
  final SocialMap me;
  final String id;
  final List<SocialMap> categories;
  @override
  State<SocialTopicScreen> createState() => _SocialTopicScreenState();
}

class _SocialTopicScreenState extends State<SocialTopicScreen> {
  final _reply = TextEditingController();
  SocialMap? _topic;
  List<SocialMap> _replies = [];
  bool _loading = false, _sending = false, _more = false;
  String? _error, _key, _body;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_access);
    unawaited(_load());
  }

  void _access() {
    if (!widget.client.available && mounted) {
      _generation++;
      setState(() {
        _topic = null;
        _loading = false;
        _replies = [];
        _reply.clear();
        _error = 'Your session changed. Close Social and sign in again.';
      });
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_access);
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load({bool next = false}) async {
    final g = ++_generation;
    setState(() => _loading = true);
    try {
      final r = await widget.client.get('topic', {
        'id': widget.id,
        if (next && _replies.isNotEmpty) 'after': _replies.last['seq'],
      });
      if (!mounted || g != _generation || !widget.client.available) return;
      final replies = socialItems(r['items']);
      setState(() {
        _topic = socialMap(r['topic']);
        _replies = next
            ? [..._replies, ...replies.take(40)]
            : replies.take(40).toList();
        _more = replies.length > 40;
        _error = null;
      });
    } catch (e) {
      if (mounted && g == _generation) {
        setState(() {
          _error = '$e';
          if (e is SocialException && [401, 403, 404].contains(e.status)) {
            _topic = null;
            _replies = [];
          }
        });
      }
    } finally {
      if (mounted && g == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _post() async {
    final body = _reply.text.trim();
    if (body.isEmpty || _sending) return;
    if (_body != body) {
      _body = body;
      _key = socialId();
    }
    setState(() => _sending = true);
    try {
      await widget.client.post('reply', {
        'id': widget.id,
        'reply_id': _key,
        'body': body,
      });
      if (mounted && widget.client.available) {
        _reply.clear();
        _key = null;
        _body = null;
        socialNotice(context, 'Reply published.');
        await _load();
      }
    } catch (e) {
      if (mounted) socialNotice(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _action(String action, SocialMap content, bool topic) async {
    if (action == 'report') {
      final sent = await socialReport(
        context,
        widget.client,
        topic ? 'topic' : 'reply',
        content['id'],
      );
      if (mounted && sent) {
        socialNotice(context, 'Report submitted for review.');
      }
      return;
    }
    if (action == 'edit') {
      if (topic) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SocialComposeTopic(
              client: widget.client,
              categories: widget.categories,
              topic: content,
            ),
          ),
        );
      } else {
        await showDialog(
          context: context,
          builder: (_) => _EditReply(client: widget.client, reply: content),
        );
      }
      if (mounted && widget.client.available) await _load();
      return;
    }
    if (!await socialConfirm(
      context,
      topic ? 'Remove this topic?' : 'Remove this reply?',
      topic
          ? 'The topic and its discussion will no longer be visible.'
          : 'Your reply will no longer be visible.',
      action: 'Remove',
    )) {
      return;
    }
    try {
      await widget.client.post(topic ? 'delete_topic' : 'delete_reply', {
        'id': content['id'],
      });
      if (mounted) {
        if (topic) {
          Navigator.pop(context);
        } else {
          await _load();
        }
      }
    } catch (e) {
      if (mounted) socialNotice(context, e);
    }
  }

  Widget _postCard(SocialMap content, bool topic) {
    final author = socialMap(content['author']),
        mine = author['id'] == widget.me['id'];
    return SocialPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SocialAvatar(member: author, size: 40, showStatus: false),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      author['name'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '@${author['handle']} · ${socialTime(content['created_at'])}',
                      style: TextStyle(
                        fontSize: 11,
                        color: korlixSkinOf(context).mutedText,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: topic ? 'Topic options' : 'Reply options',
                onSelected: (v) => _action(v, content, topic),
                itemBuilder: (_) => [
                  if (mine) ...[
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'delete', child: Text('Remove')),
                  ] else
                    const PopupMenuItem(value: 'report', child: Text('Report')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (topic) ...[
            Text(
              content['title'],
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 28,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 16),
          ],
          SelectableText(
            content['body'],
            style: const TextStyle(height: 1.65, fontSize: 15),
          ),
          if (content['updated_at'] != content['created_at'])
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Edited', style: TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Discussion'),
      actions: [
        IconButton(
          tooltip: 'Refresh discussion',
          onPressed: _loading ? null : () => _load(),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              if (_topic != null) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    widget.categories
                            .where((c) => c['id'] == _topic!['category'])
                            .firstOrNull?['name'] ??
                        'Forum',
                    style: TextStyle(
                      color: korlixSkinOf(context).primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                _postCard(_topic!, true),
                const SizedBox(height: 28),
                const Text(
                  'The conversation',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                if (_replies.isEmpty && !_loading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text('Be the first to add a perspective.'),
                  ),
                for (final reply in _replies)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _postCard(reply, false),
                  ),
                if (_more)
                  OutlinedButton(
                    onPressed: _loading ? null : () => _load(next: true),
                    child: const Text('Load more replies'),
                  ),
                const SizedBox(height: 20),
                if (_topic!['locked'] == true)
                  const SocialEmpty(
                    icon: Icons.lock_outline,
                    title: 'This discussion is locked.',
                    body:
                        'Existing posts can still be read. New replies are closed.',
                  )
                else
                  SocialPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Add your perspective',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _reply,
                          enabled: !_sending,
                          maxLength: 4000,
                          minLines: 3,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            hintText: 'Keep it thoughtful. Keep it respectful.',
                          ),
                        ),
                        const SizedBox(height: 12),
                        KorlixActionButton(
                          label: 'Publish reply',
                          icon: Icons.arrow_upward_rounded,
                          onPressed: _sending ? null : _post,
                          busy: _sending,
                          expand: true,
                        ),
                      ],
                    ),
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
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _EditReply extends StatefulWidget {
  const _EditReply({required this.client, required this.reply});
  final SocialClient client;
  final SocialMap reply;
  @override
  State<_EditReply> createState() => _EditReplyState();
}

class _EditReplyState extends State<_EditReply> {
  late final _text = TextEditingController(text: widget.reply['body']);
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_access);
  }

  void _access() {
    if (!widget.client.available && mounted) {
      _text.clear();
      setState(
        () => _error = 'Your session changed. Close Social and sign in again.',
      );
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_access);
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!widget.client.available || _text.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.client.post('edit_reply', {
        'id': widget.reply['id'],
        'body': _text.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit reply'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 10,
            maxLength: 4000,
          ),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: const Text('Save'),
      ),
    ],
  );
}

class SocialManagementScreen extends StatefulWidget {
  const SocialManagementScreen({
    super.key,
    required this.client,
    required this.action,
  });
  final SocialClient client;
  final String action;
  @override
  State<SocialManagementScreen> createState() => _SocialManagementScreenState();
}

class _SocialManagementScreenState extends State<SocialManagementScreen> {
  List<SocialMap> _items = [];
  bool _loading = false, _more = false;
  String? _error;
  int _offset = 0, _generation = 0;
  bool get _reports => widget.action == 'reports';
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_access);
    unawaited(_load());
  }

  void _access() {
    if (!widget.client.available && mounted) {
      _generation++;
      setState(() {
        _items = [];
        _error = 'Your session changed. Close Social and sign in again.';
      });
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_access);
    super.dispose();
  }

  Future<void> _load({bool next = false}) async {
    final g = ++_generation, offset = next ? _offset + 40 : 0;
    setState(() => _loading = true);
    try {
      final r = await widget.client.get(widget.action, {'offset': offset});
      if (mounted && g == _generation && widget.client.available) {
        final list = socialItems(r['items']);
        setState(() {
          _items = next
              ? [..._items, ...list.take(40)]
              : list.take(40).toList();
          _more = list.length > 40;
          _offset = offset;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && g == _generation) {
        setState(() {
          _error = '$e';
          if (e is SocialException && [401, 403].contains(e.status)) {
            _items = [];
          }
        });
      }
    } finally {
      if (mounted && g == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _act(SocialMap item, String decision) async {
    if (!await socialConfirm(
      context,
      _reports ? 'Confirm moderation action?' : 'Unblock this member?',
      _reports
          ? 'Apply “$decision” and resolve this report?'
          : 'Unblocking does not restore your connection. A new follow request must be accepted.',
      action: _reports ? 'Apply' : 'Unblock',
    )) {
      return;
    }
    setState(() => _loading = true);
    try {
      await widget.client.post(
        _reports ? 'moderate' : 'unblock',
        _reports
            ? {'id': item['id'], 'decision': decision}
            : {'peer': item['id']},
      );
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          if (e is SocialException && [401, 403].contains(e.status)) {
            _items = [];
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_reports ? 'Moderation reports' : 'Blocked members'),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_reports)
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text(
                  'Review reported content in context. These snapshots were submitted by members; private conversations are not generally accessible here.',
                ),
              ),
            if (_items.isEmpty && !_loading && _error == null)
              SocialEmpty(
                icon: _reports
                    ? Icons.verified_user_outlined
                    : Icons.person_outline,
                title: _reports ? 'No open reports.' : 'No blocked members.',
                body: _reports
                    ? 'Reports submitted by members will appear here.'
                    : 'You can block a member from their options menu.',
              ),
            for (final item in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SocialPanel(
                  child: _reports
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item['kind']} report · ${socialTime(item['created_at'])}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(item['reason']),
                            const Divider(height: 28),
                            SelectableText(
                              '${socialMap(item['snapshot'])['title'] ?? socialMap(item['snapshot'])['name'] ?? ''}\n${socialMap(item['snapshot'])['body'] ?? socialMap(item['snapshot'])['bio'] ?? ''}',
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                TextButton(
                                  onPressed: _loading
                                      ? null
                                      : () => _act(item, 'resolve'),
                                  child: const Text('Resolve without action'),
                                ),
                                if (item['kind'] == 'topic')
                                  OutlinedButton(
                                    onPressed: _loading
                                        ? null
                                        : () => _act(item, 'lock'),
                                    child: const Text('Lock topic'),
                                  ),
                                OutlinedButton(
                                  onPressed: _loading
                                      ? null
                                      : () => _act(
                                          item,
                                          item['kind'] == 'member'
                                              ? 'suspend'
                                              : 'remove',
                                        ),
                                  child: Text(
                                    item['kind'] == 'member'
                                        ? 'Suspend member'
                                        : 'Remove content',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            SocialAvatar(member: item, showStatus: false),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => _act(item, 'unblock'),
                              child: const Text('Unblock'),
                            ),
                          ],
                        ),
                ),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_more && !_loading)
              TextButton(
                onPressed: () => _load(next: true),
                child: const Text('Load more'),
              ),
          ],
        ),
      ),
    ),
  );
}
