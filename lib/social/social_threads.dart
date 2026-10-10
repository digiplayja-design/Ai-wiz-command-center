import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'social_media_widgets.dart';
import 'social_voice_note.dart';

import 'package:flutter/material.dart';

import '../theme/korlix_theme.dart';
import '../theme/korlix_action_button.dart';
import 'social_client.dart';
import 'social_discover.dart';
import 'social_alert_scope.dart';
import 'social_notifications.dart';
import 'social_design.dart';
import 'social_forms.dart';
import 'social_emoji.dart';
import 'social_message_quote.dart';
import 'social_auto_dump.dart';
import 'social_dump_truck.dart';

class SocialChatScreen extends StatefulWidget {
  const SocialChatScreen({
    super.key,
    required this.client,
    required this.me,
    required this.peer,
    this.onCall,
    this.groupChat = false,
    this.onGroupDetails,
    this.attachmentPicker,
    this.autoDumpNow,
  });
  final SocialClient client;
  final SocialMap me, peer;
  final Future<void> Function(bool video)? onCall;
  final bool groupChat;
  final Future<SocialAttachmentDraft?> Function(String kind)? attachmentPicker;
  final Future<bool> Function()? onGroupDetails;
  final DateTime Function()? autoDumpNow;
  @override
  State<SocialChatScreen> createState() => _SocialChatScreenState();
}

class _SocialChatScreenState extends State<SocialChatScreen>
    with WidgetsBindingObserver, RouteAware {
  final _text = TextEditingController(), _scroll = ScrollController();
  final _composeFocus = FocusNode();
  SocialMap? _replyTo;
  String? _sendReplyId;
  bool _openingOriginal = false;
  late final SocialAutoDump _dumps = SocialAutoDump(now: widget.autoDumpNow);
  final _dumpedSeen = <String>{};
  final _dumpedLoaded = <String>{},
      _dumpedQuoted = <String>{},
      _restoreDumpIds = <String>{};
  bool _restoringDumped = false;
  final _messageKeys = <String, GlobalKey>{};
  final _dumpLayerKey = GlobalKey();
  final _historyViewportKey = GlobalKey();
  bool _dumpMode = false, _dumpSaving = false;
  String? _dumpPreview;
  double? _dumpPickupY;
  int _dumpAnimation = 0;
  SocialAttachmentDraft? _attachment;
  bool _pickingAttachment = false, _uploading = false;
  String? _sendAttachmentId;
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
  SocialNotifications? _notifications;
  RouteObserver<ModalRoute<dynamic>>? _routeObserver;
  ModalRoute<dynamic>? _chatRoute;
  SocialClient? _claimedClient;
  static final _conversationOwners = Expando<Object>();
  Object? _conversationClaim;
  bool _routeVisible = false;
  int _visibilityRevision = 0;
  String get _conversationKey =>
      '${widget.groupChat ? 'group' : 'peer'}:${widget.peer['id']}';
  String _action(String name) => widget.groupChat ? 'group_$name' : name;
  SocialMap get _destination => {
    widget.groupChat ? 'group' : 'peer': _peer['id'],
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.addListener(_access);
    _dumps.addListener(_dumpChanged);
    _scroll.addListener(_scrollChanged);
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_foreground &&
          !_loading &&
          !_sending &&
          !_dumpSaving &&
          ModalRoute.of(context)?.isActive == true) {
        unawaited(_load(quiet: true));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = SocialAlertScope.maybeOf(context);
    final route = ModalRoute.of(context);
    if (identical(_notifications, scope?.notifications) &&
        identical(_routeObserver, scope?.routeObserver) &&
        identical(_chatRoute, route)) {
      return;
    }
    _routeObserver?.unsubscribe(this);
    _releaseConversation();
    _notifications = scope?.notifications;
    _routeObserver = scope?.routeObserver;
    _chatRoute = route;
    _routeVisible = route?.isCurrent ?? false;
    if (route != null) _routeObserver?.subscribe(this, route);
    _syncConversationVisibility();
  }

  void _releaseConversation() {
    ++_visibilityRevision;
    final notifications = _notifications;
    final key = _conversationKey;
    final claim = _conversationClaim;
    if (claim == null || notifications == null) return;
    _conversationClaim = null;
    final accountClient = _claimedClient;
    _claimedClient = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(_conversationOwners[notifications], claim)) {
        _conversationOwners[notifications] = null;
        if (identical(notifications.client, accountClient) &&
            notifications.activeConversationKey == key) {
          notifications.setActiveConversation(null);
        }
      }
    });
  }

  void _syncConversationVisibility() {
    final notifications = _notifications;
    if (notifications == null) return;
    final revision = ++_visibilityRevision;
    final accountClient = notifications.client;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          revision != _visibilityRevision ||
          !identical(_notifications, notifications) ||
          !identical(notifications.client, accountClient)) {
        return;
      }
      final visible =
          _routeVisible &&
          _chatRoute?.isCurrent == true &&
          _foreground &&
          !_unavailable &&
          widget.client.available;
      if (visible) {
        final claim = _conversationClaim ??= Object();
        _conversationOwners[notifications] = claim;
        notifications.setActiveConversation(_conversationKey);
        _claimedClient = accountClient;
      } else if (_conversationClaim != null) {
        if (identical(_conversationOwners[notifications], _conversationClaim)) {
          _conversationOwners[notifications] = null;
          if (identical(_claimedClient, accountClient) &&
              notifications.activeConversationKey == _conversationKey) {
            notifications.setActiveConversation(null);
          }
        }
        _conversationClaim = null;
        _claimedClient = null;
      }
    });
  }

  @override
  void didPush() {
    _routeVisible = _chatRoute?.isCurrent ?? false;
    _syncConversationVisibility();
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _syncConversationVisibility();
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    if (_dumpPreview != null) setState(() => _dumpPreview = null);
    _syncConversationVisibility();
  }

  @override
  void didPop() {
    _routeVisible = false;
    _syncConversationVisibility();
  }

  void _access() {
    if (!widget.client.available && mounted) {
      _generation++;
      _dumps.clear();
      _dumpedSeen.clear();
      _dumpedLoaded.clear();
      _dumpedQuoted.clear();
      _restoreDumpIds.clear();
      setState(() {
        _dumpPreview = null;
        _dumpMode = false;
        _messages = [];
        _attachment = null;
        _replyTo = null;
        _sendKey = _sendBody = _sendReplyId = null;
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
      _syncConversationVisibility();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncConversationVisibility();
    if (!_foreground && _dumpPreview != null) {
      setState(() => _dumpPreview = null);
    }
    if (_foreground) unawaited(_load(quiet: true));
  }

  @override
  void dispose() {
    _routeObserver?.unsubscribe(this);
    _releaseConversation();
    _timer?.cancel();
    _dumps.removeListener(_dumpChanged);
    _dumps.dispose();
    _discardAttachment();
    widget.client.removeListener(_access);
    WidgetsBinding.instance.removeObserver(this);
    _text.dispose();
    _composeFocus.dispose();
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
          .post(_action('read'), {..._destination, 'through': seq})
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
    if (!widget.client.available || _dumpSaving || (_loading && quiet)) return;
    final g = ++_generation, atBottom = _atBottom;
    setState(() => _loading = true);
    try {
      final r = await widget.client.get(_action('messages'), {
        ..._destination,
        if (older && _messages.isNotEmpty) 'before': _messages.first['seq'],
      });
      if (!mounted || g != _generation || !widget.client.available) return;
      final list = socialItems(r['items']),
          page = list.length > 50 ? list.skip(1).toList() : list;
      _dumps.observe(r, page);
      final merged = <String, SocialMap>{
        for (final m in _messages) m['id']: m,
        for (final m in page) m['id']: m,
      };
      setState(() {
        _messages = merged.values.toList()
          ..sort((a, b) => (a['seq'] as num).compareTo(b['seq'] as num));
        _scrubDumped();
        if (widget.groupChat && r['hidden_senders'] is List) {
          final hidden = Set<String>.from(r['hidden_senders']);
          _messages = [
            for (final m in _messages)
              if (hidden.contains(m['sender']))
                {
                  ...m,
                  'sender': null,
                  'author': {'name': 'Unavailable member'},
                  'body': '',
                  'deleted': true,
                  'attachment': null,
                  'reply': null,
                }
              else if (hidden.contains(socialMap(m['reply'])['sender']))
                {...m, 'reply': null}
              else
                m,
          ];
          if (hidden.contains(_replyTo?['sender'])) _replyTo = null;
        }
        final removed = <String>{
          for (final m in page) ...[
            if (m['deleted'] == true) '${m['id']}',
            if (socialMap(m['reply'])['deleted'] == true)
              '${socialMap(m['reply'])['id']}',
          ],
        };
        if (removed.isNotEmpty) {
          _messages = [
            for (final m in _messages)
              if (removed.contains(m['id']))
                {
                  ...m,
                  'body': '',
                  'deleted': true,
                  'reply': null,
                  'attachment': null,
                }
              else if (removed.contains(socialMap(m['reply'])['id']))
                {
                  ...m,
                  'reply': {
                    ...socialMap(m['reply']),
                    'body': '',
                    'deleted': true,
                  },
                }
              else
                m,
          ];
          if (removed.contains(_replyTo?['id'])) _replyTo = null;
        }
        _peer = socialMap(r['peer']);
        if (older || _messages.length <= 50) _more = list.length > 50;
        _unavailable = false;
        _error = null;
      });
      _syncConversationVisibility();
      if (!older && atBottom) _bottom();
    } catch (e) {
      if (mounted && g == _generation) {
        setState(() {
          _error = '$e';
          _peer = {..._peer, 'online': null, 'last_login_at': null};
          if (e is SocialException && [401, 403, 404].contains(e.status)) {
            _messages = [];
            _attachment = null;
            _replyTo = null;
            _sendKey = _sendBody = _sendReplyId = null;
            _unavailable = true;
            _text.clear();
          }
        });
        _syncConversationVisibility();
      }
    } finally {
      if (mounted && g == _generation) {
        setState(() => _loading = false);
        unawaited(_restoreDumpedMessages());
      }
    }
  }

  void _discardAttachment() {
    final draft = _attachment;
    _attachment = null;
    if (draft?.uploaded != null && widget.client.available) {
      unawaited(
        widget.client
            .post('attachment_discard', {'id': draft!.id})
            .catchError((_) => <String, dynamic>{}),
      );
    }
  }

  SocialMap _dumpedQuote(SocialMap message) => {
    ...message,
    'body': '',
    'deleted': true,
    'attachment': null,
    'reply': null,
  };

  void _scrubDumped() {
    _messages = [
      for (final message in _messages)
        if (!_dumps.hidden('${message['id']}'))
          if (_dumps.hidden('${socialMap(message['reply'])['id']}'))
            {...message, 'reply': _dumpedQuote(socialMap(message['reply']))}
          else
            message,
    ];
    if (_dumps.hidden('${_replyTo?['id']}')) _replyTo = null;
  }

  void _dumpChanged() {
    if (!mounted || !widget.client.available || _unavailable) return;
    final fresh = _dumps.dumped.difference(_dumpedSeen);
    final restored = _dumpedSeen.difference(_dumps.dumped);
    _restoreDumpIds.addAll(
      restored.intersection({..._dumpedLoaded, ..._dumpedQuoted}),
    );
    _dumpedSeen.removeAll(restored);
    _dumpedLoaded.addAll([
      for (final message in _messages)
        if (fresh.contains('${message['id']}')) '${message['id']}',
    ]);
    _dumpedQuoted.addAll([
      for (final message in _messages)
        if (fresh.contains('${socialMap(message['reply'])['id']}'))
          '${socialMap(message['reply'])['id']}',
    ]);
    _dumpedSeen.addAll(fresh);
    // Only a currently visible bubble can appear in the playful pickup.
    // Expiry still redacts every loaded page while a sheet or photo is open.
    if (_dumpPreview == null &&
        _foreground &&
        ModalRoute.of(context)?.isCurrent == true) {
      final layer = _dumpLayerKey.currentContext?.findRenderObject();
      final history = _historyViewportKey.currentContext?.findRenderObject();
      if (layer is RenderBox &&
          layer.hasSize &&
          history is RenderBox &&
          history.hasSize) {
        final viewport =
            layer.globalToLocal(history.localToGlobal(Offset.zero)) &
            history.size;
        for (final message in _messages) {
          if (!fresh.contains('${message['id']}')) continue;
          final render = _messageKeys['${message['id']}']?.currentContext
              ?.findRenderObject();
          if (render is! RenderBox || !render.hasSize || !render.attached) {
            continue;
          }
          final position = layer.globalToLocal(
            render.localToGlobal(Offset.zero),
          );
          final rect = position & render.size;
          if (!viewport.overlaps(rect)) continue;
          _dumpPreview = '${message['body'] ?? ''}'.trim().isEmpty
              ? 'Selected attachment'
              : '${message['body']}';
          _dumpPickupY = rect.center.dy;
          _dumpAnimation++;
          break;
        }
      }
    }
    setState(_scrubDumped);
    if (!_loading) unawaited(_restoreDumpedMessages());
  }

  Future<void> _restoreDumpedMessages() async {
    if (_restoringDumped ||
        _restoreDumpIds.isEmpty ||
        !mounted ||
        !widget.client.available ||
        _unavailable) {
      return;
    }
    _restoringDumped = true;
    try {
      for (final id in List<String>.of(_restoreDumpIds)) {
        if (_dumps.hidden(id)) {
          _restoreDumpIds.remove(id);
          continue;
        }
        final generation = _generation;
        try {
          final result = await widget.client.get(_action('message'), {
            ..._destination,
            'id': id,
          });
          if (!mounted || !widget.client.available || _unavailable) return;
          if (generation != _generation) continue;
          final message = socialMap(result['message']);
          _dumps.observe(result, [message]);
          if (message['id'] != id || _dumps.hidden(id)) continue;
          setState(() {
            _messages = [
              for (final existing in _messages)
                if (existing['id'] == id)
                  message
                else if (socialMap(existing['reply'])['id'] == id)
                  {...existing, 'reply': message}
                else
                  existing,
              if (_dumpedLoaded.contains(id) &&
                  !_messages.any((existing) => existing['id'] == id))
                message,
            ]..sort((a, b) => (a['seq'] as num).compareTo(b['seq'] as num));
            _scrubDumped();
          });
          _restoreDumpIds.remove(id);
          _dumpedLoaded.remove(id);
          _dumpedQuoted.remove(id);
        } catch (_) {
          // Retain only the ID and retry at the next successful refresh.
        }
      }
    } finally {
      _restoringDumped = false;
    }
  }

  Future<void> _chooseAutoDump(SocialMap message) async {
    final id = '${message['id']}';
    if (_unavailable || !widget.client.available || _dumps.hidden(id)) return;
    _composeFocus.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SocialAutoDumpSheet(
        client: widget.client,
        dumps: _dumps,
        message: message,
        canDumpEveryone: message['sender'] == widget.me['id'],
        onSave: (seconds, scope, requestId) async {
          if (_unavailable || !widget.client.available) {
            throw const SocialException('This conversation is unavailable.');
          }
          ++_generation; // A read started before this mutation is stale.
          setState(() {
            _dumpSaving = true;
            _loading = false;
          });
          try {
            final result = await widget.client.post(
              seconds == null ? 'dump_cancel' : 'dump_schedule',
              {
                'id': id,
                ..._destination,
                'seconds': ?seconds,
                'request_id': requestId,
                'dump_scope': scope,
              },
            );
            if (!mounted || !widget.client.available || _unavailable) {
              throw const SocialException(
                'Your session changed. Reopen Social.',
              );
            }
            if (result['id'] != id ||
                !result.containsKey('dump_at') ||
                (scope == 'everyone' &&
                    (!result.containsKey('everyone_dump_at') ||
                        !result.containsKey('self_dump_at'))) ||
                DateTime.tryParse('${result['server_time']}') == null ||
                (result['dump_at'] != null &&
                    DateTime.tryParse('${result['dump_at']}') == null)) {
              throw const SocialException(
                'The timer was not confirmed. Please retry.',
              );
            }
            _dumps.confirm(id, result);
            setState(() => _dumpMode = false);
            socialNotice(
              context,
              result['dumped'] == true
                  ? 'This message has already been dumped from your history.'
                  : seconds == null
                  ? (result['dump_at'] == null
                        ? 'Timer cancelled. The message stays in your history.'
                        : 'Timer cancelled. The other Auto Dump timer remains active.')
                  : (scope == 'everyone'
                        ? 'Auto Dump timer confirmed for everyone.'
                        : 'Auto Dump timer confirmed for you only.'),
            );
          } finally {
            if (mounted) setState(() => _dumpSaving = false);
          }
        },
      ),
    );
    if (mounted && widget.client.available) unawaited(_load(quiet: true));
  }

  Future<void> _pickAttachment(String kind) async {
    if (_sending ||
        _pickingAttachment ||
        _unavailable ||
        !widget.client.available) {
      return;
    }
    setState(() => _pickingAttachment = true);
    try {
      SocialAttachmentDraft? picked;
      if (widget.attachmentPicker != null) {
        picked = await widget.attachmentPicker!(kind);
      } else if (kind == 'voice') {
        final bytes = await showModalBottomSheet<Uint8List>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => SocialVoiceNoteSheet(client: widget.client),
        );
        if (bytes != null) {
          picked = SocialAttachmentDraft(
            bytes: bytes,
            filename: 'Voice note.wav',
            kind: 'voice',
          );
        }
      } else if (kind == 'image') {
        final photo = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 90,
        );
        if (photo != null) {
          picked = SocialAttachmentDraft(
            bytes: await photo.readAsBytes(),
            filename: photo.name,
            kind: 'image',
          );
        }
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            'pdf',
            'doc',
            'docx',
            'xls',
            'xlsx',
            'ppt',
            'pptx',
            'txt',
            'csv',
            'zip',
          ],
          withData: false,
          withReadStream: true,
        );
        if (result != null) {
          final file = result.files.single;
          if (file.size > 20 * 1024 * 1024) {
            throw const SocialException('Choose a file smaller than 20 MB.');
          }
          final data = BytesBuilder(copy: false);
          if (file.bytes != null) {
            data.add(file.bytes!);
          } else if (file.readStream != null) {
            await for (final chunk in file.readStream!) {
              data.add(chunk);
              if (data.length > 20 * 1024 * 1024) {
                throw const SocialException(
                  'Choose a file smaller than 20 MB.',
                );
              }
            }
          }
          picked = SocialAttachmentDraft(
            bytes: data.takeBytes(),
            filename: file.name,
            kind: 'file',
          );
        }
      }
      if (!mounted ||
          !widget.client.available ||
          _unavailable ||
          picked == null) {
        return;
      }
      if (picked.bytes.isEmpty || picked.bytes.length > 20 * 1024 * 1024) {
        throw const SocialException('Choose an attachment smaller than 20 MB.');
      }
      _discardAttachment();
      setState(() {
        _attachment = picked;
        _error = null;
      });
    } catch (e) {
      if (mounted && widget.client.available) socialNotice(context, e);
    } finally {
      if (mounted) setState(() => _pickingAttachment = false);
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim(), draft = _attachment;
    if ((body.isEmpty && draft == null) ||
        _sending ||
        _pickingAttachment ||
        _unavailable) {
      return;
    }
    final replyId = _replyTo?['id'] as String?;
    if (_sendBody != body ||
        _sendReplyId != replyId ||
        _sendAttachmentId != draft?.id) {
      _sendBody = body;
      _sendReplyId = replyId;
      _sendAttachmentId = draft?.id;
      _sendKey = socialId();
    }
    setState(() => _sending = true);
    try {
      if (draft != null && draft.uploaded == null) {
        setState(() => _uploading = true);
        final uploaded = await widget.client.uploadAttachment(
          bytes: draft.bytes,
          filename: draft.filename,
          kind: draft.kind,
          id: draft.id,
          destination: _destination,
        );
        if (!mounted || !widget.client.available || _unavailable) return;
        draft.uploaded = socialMap(uploaded['attachment']);
        if (draft.uploaded?['id'] != draft.id) {
          throw const SocialException(
            'Attachment upload was not confirmed. Please retry.',
          );
        }
        setState(() => _uploading = false);
      }
      await widget.client.post(_action('send'), {
        'id': _sendKey,
        ..._destination,
        'body': body,
        'reply_to': ?replyId,
        if (draft != null) 'attachment_id': draft.id,
      });
      if (!mounted || !widget.client.available) return;
      _text.clear();
      _sendBody = _sendKey = _sendReplyId = _sendAttachmentId = null;
      _replyTo = null;
      _attachment = null;
      await _load();
      _bottom();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _uploading = false;
        });
      }
    }
  }

  Widget _attachmentDraft() {
    final draft = _attachment!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SocialPanel(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: draft.kind == 'voice'
                  ? SocialVoicePlayer(
                      key: ValueKey(draft.id),
                      bytes: draft.bytes,
                    )
                  : Row(
                      children: [
                        if (draft.kind == 'image')
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                              draft.bytes,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.image_outlined),
                            ),
                          )
                        else
                          const Icon(Icons.description_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                draft.filename,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                socialFileSize(draft.bytes.length),
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            IconButton(
              tooltip: 'Remove attachment',
              onPressed: _sending ? null : () => setState(_discardAttachment),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }

  String _author(SocialMap m) => m['sender'] == widget.me['id']
      ? 'You'
      : widget.groupChat
      ? '${socialMap(m['author'])['name'] ?? 'Member'}'
      : '${_peer['name']}';

  void _chooseReply(SocialMap m) {
    if (!mounted ||
        _sending ||
        _unavailable ||
        !widget.client.available ||
        m['deleted'] == true ||
        _dumps.hidden('${m['id']}')) {
      return;
    }
    setState(() => _replyTo = Map<String, dynamic>.from(m));
    // Request the keyboard as part of the tap, including when the field still
    // has focus after the phone's keyboard was dismissed. The Focus widget is
    // inside EditableText, so its attached context resolves the public editor
    // state without accessing TextField's private implementation.
    final editor = _composeFocus.context
        ?.findAncestorStateOfType<EditableTextState>();
    if (editor != null) {
      editor.requestKeyboard();
    } else {
      _composeFocus.requestFocus();
    }
  }

  Future<void> _viewOriginal(String id) async {
    if (_openingOriginal ||
        _unavailable ||
        !widget.client.available ||
        _dumps.hidden(id)) {
      return;
    }
    _openingOriginal = true;
    try {
      final result = await widget.client.get(_action('message'), {
        ..._destination,
        'id': id,
      });
      if (!mounted || !widget.client.available || _unavailable) return;
      final message = socialMap(result['message']);
      _dumps.observe(result, [message]);
      if (message.isEmpty) {
        throw const SocialException('Message is no longer available.');
      }
      // Refresh any loaded copies; the server is authoritative about removals.
      setState(() {
        _messages = [
          for (final m in _messages)
            m['id'] == id
                ? message
                : socialMap(m['reply'])['id'] == id
                ? {...m, 'reply': message}
                : m,
        ];
        if (_replyTo?['id'] == id) {
          _replyTo = message['deleted'] == true ? null : message;
        }
        _scrubDumped();
      });
      _composeFocus.unfocus();
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => AnimatedBuilder(
          animation: Listenable.merge([widget.client, _dumps]),
          builder: (context, _) {
            if (!widget.client.available || _unavailable) {
              return const SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('This conversation is unavailable.'),
                ),
              );
            }
            final s = korlixSkinOf(context),
                removed = message['deleted'] == true || _dumps.hidden(id);
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .75,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Original message',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close original message',
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _author(message),
                        style: TextStyle(
                          color: s.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (!removed &&
                          socialMap(message['attachment']).isNotEmpty) ...[
                        SocialAttachmentView(
                          client: widget.client,
                          attachment: socialMap(message['attachment']),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SelectableText(
                        removed
                            ? 'Message removed'
                            : '${message['body'] ?? ''}',
                        style: TextStyle(
                          height: 1.5,
                          color: removed ? s.mutedText : s.text,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        socialTime(message['created_at']),
                        style: TextStyle(color: s.mutedText, fontSize: 12),
                      ),
                      if (!removed && !_sending) ...[
                        const SizedBox(height: 20),
                        KorlixActionButton(
                          label: 'Reply to this message',
                          icon: Icons.reply_rounded,
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _chooseReply(message);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    } catch (e) {
      if (mounted && widget.client.available) socialNotice(context, e);
    } finally {
      _openingOriginal = false;
    }
  }

  Future<void> _messageAction(String action, SocialMap m) async {
    if (action == 'dump') {
      await _chooseAutoDump(m);
      return;
    }
    if (action == 'reply') {
      _chooseReply(m);
      return;
    }
    if (action == 'report') {
      final sent = await socialReport(
        context,
        widget.client,
        widget.groupChat ? 'group_message' : 'message',
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
      widget.groupChat
          ? 'This message and its attachment will be removed from the KORLIX conversation for everyone in the group. Screenshots and downloaded copies are not recalled.'
          : 'This message and its attachment will be removed from the KORLIX conversation for both members. Screenshots and downloaded copies are not recalled.',
      action: 'Remove',
    )) {
      return;
    }
    try {
      await widget.client.post(_action('delete_message'), {
        'id': m['id'],
        if (widget.groupChat) ..._destination,
      });
      if (mounted) {
        setState(() {
          if (_replyTo?['id'] == m['id']) _replyTo = null;
          _messages = [
            for (final x in _messages)
              x['id'] == m['id']
                  ? {
                      ...x,
                      'body': '',
                      'deleted': true,
                      'reply': null,
                      'attachment': null,
                    }
                  : socialMap(x['reply'])['id'] == m['id']
                  ? {
                      ...x,
                      'reply': {
                        ...socialMap(x['reply']),
                        'body': '',
                        'deleted': true,
                      },
                    }
                  : x,
          ];
        });
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
          key: _messageKeys.putIfAbsent('${m['id']}', GlobalKey.new),
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
                  if (!removed) ...[
                    SocialAvatar(
                      member: mine
                          ? widget.me
                          : widget.groupChat
                          ? socialMap(m['author'])
                          : _peer,
                      size: 26,
                      showStatus: false,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: SocialMemberName(
                      member: mine
                          ? widget.me
                          : widget.groupChat
                          ? socialMap(m['author'])
                          : _peer,
                      name: _author(m),
                      showStatus: !mine && !removed && !_unavailable,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: s.mutedText,
                      ),
                    ),
                  ),
                  if (!removed)
                    IconButton(
                      key: ValueKey('reply-${m['id']}'),
                      tooltip: 'Reply to message',
                      onPressed: _sending || _unavailable
                          ? null
                          : () => _chooseReply(m),
                      icon: Icon(
                        Icons.reply_rounded,
                        size: 20,
                        color: s.primary,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (!removed)
                    PopupMenuButton<String>(
                      tooltip: 'Message options',
                      onSelected: (v) {
                        if (v != 'reply') _messageAction(v, m);
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'reply',
                          enabled: !_sending && !_unavailable,
                          // PopupMenuItem dismisses its route before onTap.
                          // Keep keyboard activation inside the user's tap.
                          onTap: () => _chooseReply(m),
                          child: const Text('Reply'),
                        ),
                        PopupMenuItem(
                          value: 'dump',
                          enabled: !_dumpSaving && !_unavailable,
                          child: Text(
                            _dumps.deadlines.containsKey('${m['id']}')
                                ? 'Manage Auto Dump'
                                : 'Auto Dump',
                          ),
                        ),
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
              if (!removed && socialMap(m['reply']).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SocialMessageQuote(
                    key: ValueKey('quote-${m['id']}'),
                    message: socialMap(m['reply']),
                    author: _author(socialMap(m['reply'])),
                    onOpen: () => _viewOriginal('${m['reply']['id']}'),
                  ),
                ),
              if (!removed && socialMap(m['attachment']).isNotEmpty) ...[
                SocialAttachmentView(
                  key: ValueKey('attachment-${m['id']}'),
                  client: widget.client,
                  attachment: socialMap(m['attachment']),
                ),
                const SizedBox(height: 8),
              ],
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
              if (!removed &&
                  (_dumpMode || _dumps.deadlines.containsKey('${m['id']}')))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton.icon(
                    key: ValueKey('dump-message-${m['id']}'),
                    onPressed: _dumpSaving || _unavailable
                        ? null
                        : () => _chooseAutoDump(m),
                    icon: const Icon(Icons.local_shipping_rounded, size: 18),
                    style: TextButton.styleFrom(
                      foregroundColor: s.isLight
                          ? const Color(0xffa84800)
                          : const Color(0xffffba75),
                      backgroundColor: Colors.orange.withValues(alpha: .12),
                    ),
                    label: Text(
                      _dumps.deadlines.containsKey('${m['id']}')
                          ? _dumps.countdown('${m['id']}')
                          : 'Select for Auto Dump',
                    ),
                  ),
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
      toolbarHeight: MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 112 : 76,
      title: Row(
        children: [
          if (widget.groupChat)
            const Icon(Icons.groups_rounded, size: 36)
          else
            SocialAvatar(member: _peer, size: 36, showStatus: !_unavailable),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SocialMemberName(
                  member: _peer,
                  showStatus: !widget.groupChat && !_unavailable,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  widget.groupChat
                      ? '${_peer['member_count'] ?? 1} members · Group chat'
                      : 'Private conversation',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          key: const ValueKey('auto-dump-mode'),
          tooltip: _dumpMode
              ? 'Exit Auto Dump selection'
              : 'Activate Auto Dump',
          isSelected: _dumpMode,
          color: Colors.orange,
          onPressed: _unavailable
              ? null
              : () => setState(() => _dumpMode = !_dumpMode),
          icon: const Icon(Icons.local_shipping_outlined),
          selectedIcon: const Icon(Icons.local_shipping_rounded),
        ),
        if (widget.onCall != null && !_unavailable)
          PopupMenuButton<bool>(
            tooltip: 'Start a call',
            icon: const Icon(Icons.call_outlined),
            onSelected: (video) => widget.onCall!(video),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: false,
                child: ListTile(
                  leading: Icon(Icons.call_outlined),
                  title: Text('Audio call'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: true,
                child: ListTile(
                  leading: Icon(Icons.videocam_outlined),
                  title: Text('Video call'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        if (widget.groupChat)
          IconButton(
            tooltip: 'Group details',
            icon: const Icon(Icons.group_outlined),
            onPressed: _unavailable
                ? null
                : () async {
                    final left = await widget.onGroupDetails?.call() ?? false;
                    if (!mounted || !context.mounted) return;
                    if (left) {
                      Navigator.pop(context);
                    } else {
                      await _load();
                    }
                  },
          )
        else
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
    body: Stack(
      key: _dumpLayerKey,
      children: [
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  if (_dumpMode && !_unavailable)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      color: Colors.orange.withValues(alpha: .14),
                      child: const Text(
                        'Auto Dump is on. Select a message below to set its timer. Only your history changes.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer,
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
                      key: _historyViewportKey,
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Text(
                            widget.groupChat
                                ? 'Only accepted members can chat. You see messages sent after you join. Reported messages may be reviewed by KORLIX moderators.'
                                : 'Connected by choice. Your messages are shared only with this connection. Reported messages may be reviewed by KORLIX moderators.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12, height: 1.5),
                          ),
                        ),
                        if (widget.onCall != null && !_unavailable)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: SocialPanel(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                children: [
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      KorlixActionButton(
                                        label: 'Audio call',
                                        icon: Icons.call_outlined,
                                        size: KorlixButtonSize.compact,
                                        onPressed: () => widget.onCall!(false),
                                      ),
                                      KorlixActionButton(
                                        label: 'Video call',
                                        icon: Icons.videocam_outlined,
                                        size: KorlixButtonSize.compact,
                                        onPressed: () => widget.onCall!(true),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _notifications == null
                                        ? 'Both people need Social open to connect.'
                                        : 'Calls can reach you anywhere in the KORLIX AI app while it is open.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_more)
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () => _load(older: true),
                            child: const Text('Load earlier messages'),
                          ),
                        if (_messages.isEmpty && !_loading && !_unavailable)
                          SocialEmpty(
                            icon: Icons.waving_hand_outlined,
                            title: widget.groupChat
                                ? 'Welcome to ${_peer['name']}.'
                                : 'Say hello to ${_peer['name']}.',
                            body: widget.groupChat
                                ? 'Start the conversation. Invited members can join after accepting in Groups.'
                                : 'You’re connected. Start with something you have in common.',
                          ),
                        for (final m in _messages) _bubble(m),
                        if (_loading && _messages.isEmpty)
                          const Center(child: CircularProgressIndicator()),
                      ],
                    ),
                  ),
                  if (!_unavailable && _attachment != null) _attachmentDraft(),
                  if (_uploading)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: Column(
                        children: [
                          LinearProgressIndicator(),
                          SizedBox(height: 4),
                          Text(
                            'Uploading attachment…',
                            style: TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  if (!_unavailable)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Wrap(
                        spacing: 4,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final item in [
                            ('image', 'Photo', Icons.photo_outlined),
                            ('file', 'File', Icons.attach_file_rounded),
                            ('voice', 'Voice note', Icons.mic_none_rounded),
                          ])
                            TextButton.icon(
                              onPressed: _sending || _pickingAttachment
                                  ? null
                                  : () => _pickAttachment(item.$1),
                              icon: Icon(item.$3, size: 19),
                              label: Text(item.$2),
                            ),
                        ],
                      ),
                    ),
                  if (!_unavailable && _replyTo != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: SocialMessageQuote(
                        key: const ValueKey('reply-composer-preview'),
                        message: _replyTo!,
                        author: _author(_replyTo!),
                        composing: true,
                        onCancel: _sending
                            ? null
                            : () => setState(() => _replyTo = null),
                      ),
                    ),
                  if (!_unavailable)
                    Padding(
                      // Inserting/removing the quote above must not replace
                      // this editor or detach its text-input connection.
                      key: const ValueKey('social-message-composer'),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: 'Add emoji',
                            onPressed: _sending
                                ? null
                                : () async {
                                    await socialChooseEmoji(context, _text);
                                    if (!widget.client.available ||
                                        _unavailable) {
                                      _text.clear();
                                    }
                                  },
                            icon: const Icon(Icons.emoji_emotions_outlined),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _text,
                              focusNode: _composeFocus,
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
                            tooltip: _sending
                                ? 'Sending message'
                                : 'Send message',
                            onPressed: _sending ? null : _send,
                            style: IconButton.styleFrom(
                              minimumSize: const Size(52, 52),
                              foregroundColor: korlixSkinOf(context)
                                  .textOnAccent,
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
        if (_dumpPreview != null &&
            widget.client.available &&
            !_unavailable &&
            _foreground)
          Positioned.fill(
            child: SocialDumpTruck(
              key: ValueKey('dump-truck-$_dumpAnimation'),
              preview: _dumpPreview!,
              pickupY: _dumpPickupY,
              onComplete: () {
                if (mounted) setState(() => _dumpPreview = null);
              },
            ),
          ),
      ],
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
    this.voiceNotePicker,
    this.voiceCaptureFactory,
  });
  final SocialClient client;
  final SocialMap me;
  final String id;
  final List<SocialMap> categories;
  final Future<SocialAttachmentDraft?> Function()? voiceNotePicker;
  final SocialVoiceCapture Function()? voiceCaptureFactory;
  @override
  State<SocialTopicScreen> createState() => _SocialTopicScreenState();
}

class _SocialTopicScreenState extends State<SocialTopicScreen>
    with WidgetsBindingObserver {
  final _reply = TextEditingController();
  SocialMap? _topic;
  List<SocialMap> _replies = [];
  SocialAttachmentDraft? _voice;
  bool _loading = false,
      _sending = false,
      _more = false,
      _pickingVoice = false,
      _uploading = false,
      _awaitingConfirmation = false;
  String? _error, _key, _body, _sendAttachmentId;
  final _uploadAttempts = <String>{};
  int _generation = 0, _draftGeneration = 0;
  Timer? _presencePoll;
  bool _foreground = true, _refreshing = false;
  bool get _wall => _topic?['surface'] == 'wall';
  bool get _canReply =>
      widget.client.available && _topic != null && _topic!['locked'] != true;
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
          !_sending &&
          !_pickingVoice &&
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
        !_sending &&
        !_pickingVoice &&
        ModalRoute.of(context)?.isCurrent == true) {
      unawaited(_load(quiet: true));
    }
  }

  void _access() {
    if (!widget.client.available && mounted) {
      _generation++;
      setState(() {
        _clearDraft();
        _topic = null;
        _loading = false;
        _replies = [];
        _error = 'Your session changed. Close Social and sign in again.';
      });
    }
  }

  @override
  void dispose() {
    _presencePoll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _discardVoice();
    widget.client.removeListener(_access);
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load({bool next = false, bool quiet = false}) async {
    if (!widget.client.available) return;
    final g = ++_generation;
    _refreshing = true;
    if (!quiet) setState(() => _loading = true);
    try {
      final r = await widget.client.get('topic', {
        'id': widget.id,
        if (next && _replies.isNotEmpty) 'after': _replies.last['seq'],
      });
      if (!mounted || g != _generation || !widget.client.available) return;
      var replies = socialItems(r['items']);
      var more = replies.length > 40;
      final pageCount = quiet ? (_replies.length + 39) ~/ 40 : 1;
      replies = replies.take(40).toList();
      for (var page = 1; page < pageCount && more; page++) {
        final nextPage = await widget.client.get('topic', {
          'id': widget.id,
          'after': replies.last['seq'],
        });
        if (!mounted || g != _generation || !widget.client.available) return;
        final items = socialItems(nextPage['items']);
        more = items.length > 40;
        replies.addAll(items.take(40));
      }
      setState(() {
        _topic = socialMap(r['topic']);
        if (_topic!['locked'] == true) _clearDraft();
        if (_awaitingConfirmation && replies.any((r) => r['id'] == _key)) {
          _publishedDraft();
        }
        _replies = next ? [..._replies, ...replies] : replies;
        _more = more;
        _error = null;
      });
    } catch (e) {
      if (mounted && g == _generation) {
        setState(() {
          if (!quiet) _error = '$e';
          if (e is SocialException && [401, 403, 404].contains(e.status)) {
            _clearDraft();
            _topic = null;
            _replies = [];
          } else if (quiet) {
            if (_topic != null) {
              _topic = {
                ..._topic!,
                'author': {
                  ...socialMap(_topic!['author']),
                  'online': null,
                  'last_login_at': null,
                },
              };
            }
            _replies = [
              for (final reply in _replies)
                {
                  ...reply,
                  'author': {
                    ...socialMap(reply['author']),
                    'online': null,
                    'last_login_at': null,
                  },
                },
            ];
          }
        });
      }
    } finally {
      if (mounted && g == _generation) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  void _discardUploaded(SocialAttachmentDraft draft) {
    if (_uploadAttempts.contains(draft.id) && widget.client.available) {
      unawaited(
        widget.client
            .post('attachment_discard', {'id': draft.id})
            .catchError((_) => <String, dynamic>{}),
      );
    }
  }

  void _discardVoice() {
    final draft = _voice;
    _voice = null;
    if (draft != null) _discardUploaded(draft);
  }

  void _clearDraft() {
    _draftGeneration++;
    _discardVoice();
    _reply.clear();
    _key = _body = _sendAttachmentId = null;
    _awaitingConfirmation = false;
  }

  void _publishedDraft() {
    final id = _voice?.id;
    _voice = null;
    if (id != null) _uploadAttempts.remove(id);
    _reply.clear();
    _key = _body = _sendAttachmentId = null;
    _awaitingConfirmation = false;
  }

  Future<void> _recordVoice() async {
    if (!_wall ||
        !_canReply ||
        _sending ||
        _pickingVoice ||
        _awaitingConfirmation) {
      return;
    }
    final generation = _draftGeneration;
    setState(() => _pickingVoice = true);
    try {
      SocialAttachmentDraft? picked;
      if (widget.voiceNotePicker != null) {
        picked = await widget.voiceNotePicker!();
      } else {
        final capture = widget.voiceCaptureFactory?.call();
        final bytes = await showModalBottomSheet<Uint8List>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) =>
              SocialVoiceNoteSheet(client: widget.client, capture: capture),
        );
        if (bytes != null) {
          picked = SocialAttachmentDraft(
            bytes: bytes,
            filename: 'Wall voice reply.wav',
            kind: 'voice',
          );
        }
      }
      if (!mounted ||
          generation != _draftGeneration ||
          !_canReply ||
          picked == null) {
        return;
      }
      if (picked.kind != 'voice' ||
          picked.bytes.length <= 44 ||
          picked.bytes.length > SocialVoiceCapture.maxBytes + 44) {
        throw const SocialException('Record one voice note up to 3 minutes.');
      }
      setState(() {
        _discardVoice();
        _voice = picked;
        _error = null;
      });
    } catch (e) {
      if (mounted && widget.client.available) socialNotice(context, e);
    } finally {
      if (mounted) setState(() => _pickingVoice = false);
    }
  }

  Future<void> _post() async {
    final body = _awaitingConfirmation ? _body! : _reply.text.trim(),
        draft = _voice;
    if ((body.isEmpty && draft == null) ||
        _sending ||
        _pickingVoice ||
        !_canReply) {
      return;
    }
    if (_body != body || _sendAttachmentId != draft?.id) {
      _body = body;
      _sendAttachmentId = draft?.id;
      _key = socialId();
    }
    final generation = _draftGeneration;
    var publishing = false;
    setState(() => _sending = true);
    try {
      if (draft != null && draft.uploaded == null) {
        setState(() => _uploading = true);
        _uploadAttempts.add(draft.id);
        final uploaded = await widget.client.uploadAttachment(
          bytes: draft.bytes,
          filename: draft.filename,
          kind: 'voice',
          id: draft.id,
          destination: {'topic': widget.id},
        );
        if (!mounted || generation != _draftGeneration || !_canReply) {
          _discardUploaded(draft);
          return;
        }
        final attachment = socialMap(uploaded['attachment']);
        if (attachment['id'] != draft.id) {
          throw const SocialException(
            'Voice upload was not confirmed. Your recording is ready to retry.',
          );
        }
        draft.uploaded = attachment;
        setState(() => _uploading = false);
      }
      publishing = true;
      await widget.client.post('reply', {
        'id': widget.id,
        'reply_id': _key,
        'body': body,
        if (draft != null) 'attachment_id': draft.id,
      });
      if (mounted && generation == _draftGeneration && _canReply) {
        _publishedDraft();
        socialNotice(context, 'Reply published.');
        await _load();
      }
    } catch (e) {
      if (mounted && generation == _draftGeneration) {
        _awaitingConfirmation =
            _awaitingConfirmation ||
            (publishing &&
                (e is! SocialException || e.status == 0 || e.status >= 500));
        if (e is SocialException && [401, 403, 404].contains(e.status)) {
          setState(() {
            _clearDraft();
            _topic = null;
            _replies = [];
            _error = '$e';
          });
        } else {
          socialNotice(context, e);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _uploading = false;
        });
      }
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
              wall: content['surface'] == 'wall',
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
      topic
          ? (_wall ? 'Remove this wall post?' : 'Remove this topic?')
          : 'Remove this reply?',
      topic
          ? 'This post and its discussion will no longer be visible.'
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
        mine = author['id'] == widget.me['id'],
        attachment = socialMap(content['attachment']);
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
                    SocialMemberName(
                      member: author,
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
                tooltip: topic
                    ? (_wall ? 'Wall post options' : 'Topic options')
                    : 'Reply options',
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
          if (topic && '${content['title'] ?? ''}'.trim().isNotEmpty) ...[
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
          if ('${content['body'] ?? ''}'.isNotEmpty)
            SelectableText(
              '${content['body']}',
              style: const TextStyle(height: 1.65, fontSize: 15),
            ),
          if (!topic && attachment['kind'] == 'voice') ...[
            if ('${content['body'] ?? ''}'.isNotEmpty)
              const SizedBox(height: 14),
            SocialAttachmentView(
              key: ValueKey(attachment['id']),
              client: widget.client,
              attachment: attachment,
            ),
          ],
          if (content['updated_at'] != content['created_at'])
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Edited', style: TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Widget _voiceDraft() {
    final draft = _voice!;
    return Column(
      key: const ValueKey('wall-voice-draft'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const Text(
          'Listen before you publish',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SocialVoicePlayer(key: ValueKey(draft.id), bytes: draft.bytes),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('wall-replace-voice'),
              onPressed: _sending || _pickingVoice || _awaitingConfirmation
                  ? null
                  : _recordVoice,
              icon: const Icon(Icons.mic_rounded),
              label: const Text('Re-record'),
            ),
            TextButton.icon(
              key: const ValueKey('wall-remove-voice'),
              onPressed: _sending || _pickingVoice || _awaitingConfirmation
                  ? null
                  : () => setState(_discardVoice),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Remove voice note'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _composer() => SocialPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Add your perspective',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        if (_wall) ...[
          const SizedBox(height: 8),
          Text(
            'Your reply is public to KORLIX Social members who can view this wall post.',
            style: TextStyle(
              color: korlixSkinOf(context).mutedText,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('wall-reply-text'),
          controller: _reply,
          enabled: !_sending && !_pickingVoice && !_awaitingConfirmation,
          maxLength: 4000,
          minLines: _voice == null ? 3 : 2,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: _voice == null ? null : 'Caption (optional)',
            hintText: _voice == null
                ? 'Keep it thoughtful. Keep it respectful.'
                : 'Add a little context to your voice reply…',
          ),
        ),
        if (_voice != null) _voiceDraft(),
        if (_wall && _voice == null) ...[
          const SizedBox(height: 8),
          KorlixActionButton(
            key: const ValueKey('wall-record-voice'),
            label: 'Record voice note',
            colorIdentity: 'Voice',
            subtitle: 'Up to 3 minutes · Preview before publishing',
            icon: Icons.mic_rounded,
            onPressed: _sending || _pickingVoice || _awaitingConfirmation
                ? null
                : _recordVoice,
            busy: _pickingVoice,
            expand: true,
          ),
        ],
        const SizedBox(height: 12),
        if (_awaitingConfirmation)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Publication is not confirmed. Retry to confirm this reply without posting it twice. Your caption and voice note are kept until then.',
              style: TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _reply,
          builder: (_, text, _) => KorlixActionButton(
            key: const ValueKey('wall-publish-reply'),
            label: _uploading
                ? 'Uploading voice note…'
                : _awaitingConfirmation
                ? 'Retry reply'
                : 'Publish reply',
            colorIdentity: 'Publish reply',
            icon: Icons.arrow_upward_rounded,
            onPressed:
                _sending ||
                    _pickingVoice ||
                    (text.text.trim().isEmpty && _voice == null)
                ? null
                : _post,
            busy: _sending,
            expand: true,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_wall ? 'Wall thread' : 'Discussion'),
      actions: [
        IconButton(
          tooltip: 'Refresh discussion',
          onPressed: _loading || _sending || _pickingVoice
              ? null
              : () => _load(),
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
                    _wall
                        ? 'PUBLIC WALL POST'
                        : widget.categories
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
                    key: ValueKey(reply['id']),
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
                    body: 'Existing posts can still be read. New replies are closed.',
                  )
                else
                  _composer(),
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
  bool get _voice => socialMap(widget.reply['attachment'])['kind'] == 'voice';
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
    if (!widget.client.available ||
        _saving ||
        (_text.text.trim().isEmpty && !_voice)) {
      return;
    }
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
    title: Text(_voice ? 'Edit voice reply caption' : 'Edit reply'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _text,
            enabled: !_saving && widget.client.available,
            minLines: 3,
            maxLines: 10,
            maxLength: 4000,
            decoration: InputDecoration(
              labelText: _voice ? 'Caption (optional)' : null,
            ),
          ),
          if (_voice) const Text('Your voice note stays with this reply.'),
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
        onPressed: _saving || !widget.client.available ? null : _save,
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
      _reports ? 'Apply “$decision” and resolve this report?' : 'Unblocking does not restore your connection. A new follow request must be accepted.',
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
                              '${socialMap(item['snapshot'])['title'] ?? socialMap(item['snapshot'])['name'] ?? ''}\n${socialMap(item['snapshot'])['body'] ?? socialMap(item['snapshot'])['summary'] ?? socialMap(item['snapshot'])['bio'] ?? ''}',
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (item['kind'] == 'video')
                                  TextButton.icon(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => DiscoverVideoViewer(
                                          client: widget.client,
                                          items: [
                                            {
                                              ...socialMap(item['snapshot']),
                                              'id': item['target_id'],
                                              'caption': socialMap(
                                                item['snapshot'],
                                              )['body'],
                                              'author': <String, dynamic>{},
                                            },
                                          ],
                                          initialId: '${item['target_id']}',
                                          report: '${item['id']}',
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    label: const Text('Review reported video'),
                                  ),
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
