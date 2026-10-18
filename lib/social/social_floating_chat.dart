import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'social_client.dart';
import 'social_native_bridge.dart';
import 'social_push_platform.dart';

/// A bubble carries only routing identifiers. Authentication stays in the
/// platform keystore and is revalidated by the bubble's independent engine.
class SocialFloatingTarget {
  const SocialFloatingTarget({
    required this.owner,
    required this.kind,
    required this.id,
  });

  final String owner, kind, id;

  static SocialFloatingTarget? parse(dynamic value) {
    if (value is! Map || value['type'] != 'open') return null;
    final owner = value['owner'], kind = value['kind'], id = value['id'];
    if (owner is! String ||
        owner.length > 2048 ||
        (kind != 'peer' && kind != 'group') ||
        id is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id)) {
      return null;
    }
    try {
      final account = jsonDecode(owner);
      if (account is! List ||
          account.length != 2 ||
          account.any((v) => v is! String || v.isEmpty)) {
        return null;
      }
      final issuer = Uri.tryParse(account.first as String);
      if (issuer == null ||
          (issuer.scheme != 'https' && issuer.scheme != 'http') ||
          issuer.host.isEmpty) {
        return null;
      }
    } catch (_) {
      return null;
    }
    return SocialFloatingTarget(owner: owner, kind: kind as String, id: id);
  }

  SocialMap toMap() => {'type': 'open', 'owner': owner, 'kind': kind, 'id': id};
}

class SocialFloatingChat {
  static bool get supportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<SocialMap> capabilities() async {
    if (!supportedPlatform) return {'bubbles': false, 'push': false};
    try {
      return {
        'bubbles': false,
        'push': false,
        ...socialMap(await SocialNativeBridge.invoke('capabilities')),
      };
    } on MissingPluginException {
      return {'bubbles': false, 'push': false};
    } on PlatformException {
      return {'bubbles': false, 'push': false};
    }
  }

  static Future<SocialMap> pin(
    SocialFloatingTarget target,
    String title,
  ) async {
    if (!supportedPlatform || SocialFloatingTarget.parse(target.toMap()) == null) {
      return {'status': 'unsupported'};
    }
    try {
      final result = socialMap(await SocialNativeBridge.invoke('pin', {
        'owner': target.owner,
        'kind': target.kind,
        'id': target.id,
        'title': title.trim().isEmpty ? 'KORLIX Social' : title.trim(),
      }));
      return result['status'] is String ? result : {'status': 'unsupported'};
    } on MissingPluginException {
      return {'status': 'unsupported'};
    } on PlatformException {
      return {'status': 'denied'};
    }
  }

  static Future<SocialFloatingTarget?> launchTarget() async {
    try {
      return SocialFloatingTarget.parse(
        await SocialNativeBridge.invoke('launchAction'),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<void> close() => _action('closeBubble');
  static Future<void> openMain([SocialFloatingTarget? target]) =>
      _action('openMain', target?.toMap());

  static Future<void> _action(String method, [dynamic args]) async {
    try {
      await SocialNativeBridge.invoke(method, args);
    } on MissingPluginException {
      // This may be an old app build or a test host without native bubbles.
    } on PlatformException {
      // An unavailable native window must not crash the conversation.
    }
  }
}

Future<void> keepSocialChatFloating(
  BuildContext context, {
  required SocialClient client,
  required SocialMap peer,
  required bool groupChat,
}) async {
  final owner = socialPushOwner(client.headersBuilder());
  final target = SocialFloatingTarget.parse({
    'type': 'open',
    'owner': owner,
    'kind': groupChat ? 'group' : 'peer',
    'id': peer['id'],
  });
  if (target == null || !client.available) return;
  final capabilities = await SocialFloatingChat.capabilities();
  if (!context.mounted || !client.available) return;
  if (capabilities['bubbles'] != true) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Floating chats are not supported on this device.'),
    ));
    return;
  }
  final approved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Keep this chat floating'),
      content: SingleChildScrollView(
        child: Text(
          'Keep this conversation in an Android chat bubble while you use '
          'other apps. Tap the bubble to read and reply; drag it away to dismiss. '
          'Android may ask you to allow notifications and bubbles for KORLIX.'
          '${capabilities['push'] == true ? '' : '\n\nYou can read and reply while the bubble is open. Alerts for new messages when it is closed need background notifications to be configured.'}',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Keep floating'),
        ),
      ],
    ),
  );
  if (approved != true ||
      !context.mounted ||
      !client.available ||
      socialPushOwner(client.headersBuilder()) != owner) return;
  final result = await SocialFloatingChat.pin(target, '${peer['name'] ?? ''}');
  if (!context.mounted || !client.available) return;
  final message = switch (result['status']) {
    'shown' => 'Chat bubble requested. If it stays in notifications, enable '
        'bubbles for this conversation in Android settings.',
    'settings' => 'Allow bubbles in Android settings, then return and tap '
        'Keep this chat floating again.',
    'denied' => 'Allow KORLIX notifications and bubbles in Android settings '
        'to keep this chat floating.',
    _ => 'Floating chats are not available on this device.',
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
