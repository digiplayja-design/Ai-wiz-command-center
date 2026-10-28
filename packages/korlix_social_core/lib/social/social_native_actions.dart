import 'dart:async';

import 'package:flutter/material.dart';

import 'social_client.dart';
import 'social_push_platform.dart';

/// Native notifications only request a destination. The current authenticated
/// client and backend still authorize every read and send.
class SocialNativeAction {
  const SocialNativeAction({
    required this.owner,
    required this.id,
    required this.group,
    required this.requestId,
    this.reply,
    this.callId,
    this.acceptCall = false,
  });

  final String owner, id, requestId;
  final bool group;
  final String? reply, callId;
  final bool acceptCall;

  static SocialNativeAction? parse(SocialMap value, String owner) {
    final kind = value['kind'];
    final type = value['type'];
    final id = value['id'];
    final requestId = value['requestId'];
    if (owner.isEmpty ||
        value['owner'] != owner ||
        !['peer', 'group'].contains(kind) ||
        !['open', 'reply'].contains(type) ||
        id is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id) ||
        requestId is! String ||
        requestId.length > 100 ||
        requestId.isEmpty) {
      return null;
    }
    final callId = value['callId'];
    if (callId != null &&
        (kind != 'peer' ||
            type != 'open' ||
            callId is! String ||
            !RegExp(
              r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
            ).hasMatch(callId)))
      return null;
    if (value['acceptCall'] == true && callId == null) return null;
    final text = value['text'];
    if (type == 'reply' &&
        (text is! String ||
            text.trim().isEmpty ||
            text.length > 2000 ||
            !RegExp(
              r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
            ).hasMatch(requestId))) {
      return null;
    }
    return SocialNativeAction(
      owner: owner,
      id: id,
      group: kind == 'group',
      requestId: requestId,
      reply: type == 'reply' ? (text as String).trim() : null,
      callId: callId as String?,
      acceptCall: value['acceptCall'] == true,
    );
  }

  bool matches(SocialClient client) =>
      client.available && socialPushOwner(client.headersBuilder()) == owner;

  Future<void> send(SocialClient client) async {
    if (reply == null || !matches(client)) {
      throw const SocialException(
        'Your session changed. Reopen the conversation.',
        401,
      );
    }
    await client.post(group ? 'group_send' : 'send', {
      'id': requestId,
      group ? 'group' : 'peer': id,
      'body': reply,
    });
    if (!matches(client)) {
      throw const SocialException(
        'Your session changed. Reopen the conversation.',
        401,
      );
    }
  }
}

/// Reached only after the user presses Send on an unlocked native reply action.
/// A normal notification tap never constructs this page or sends a message.
class SocialQuickReplyScreen extends StatefulWidget {
  const SocialQuickReplyScreen({
    super.key,
    required this.action,
    required this.client,
  });
  final SocialNativeAction action;
  final SocialClient client;

  @override
  State<SocialQuickReplyScreen> createState() => _SocialQuickReplyScreenState();
}

class _SocialQuickReplyScreenState extends State<SocialQuickReplyScreen> {
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_accessChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_send());
    });
  }

  void _accessChanged() {
    if (mounted && !widget.action.matches(widget.client)) {
      setState(() {
        _sending = false;
        _error = 'Your account changed. Close this screen and reopen Social.';
      });
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_accessChanged);
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.action.send(widget.client);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = widget.action.matches(widget.client)
              ? 'Your reply was not confirmed. Retry uses the same message ID to avoid duplicates.'
              : 'Your account changed. Close this screen and reopen Social.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sending,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Reply in KORLIX Social'),
        automaticallyImplyLeading: !_sending,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                if (_sending) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 20),
                  const Text('Sending your reply…'),
                ],
                const SizedBox(height: 16),
                if (widget.action.matches(widget.client))
                  SelectableText(widget.action.reply ?? ''),
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Text(_error!),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: widget.action.matches(widget.client)
                        ? _send
                        : null,
                    child: const Text('Retry reply'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Close'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
