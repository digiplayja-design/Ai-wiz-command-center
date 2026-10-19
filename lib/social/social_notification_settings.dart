import 'social_appearance.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/korlix_theme.dart';
import '../theme/korlix_action_button.dart';
import 'social_client.dart';
import 'social_design.dart';
import 'social_online_settings.dart';
import 'social_push_platform.dart';
import 'social_push_native.dart'
    if (dart.library.js_interop) 'social_push_web.dart';

class SocialNotificationSettings extends StatefulWidget {
  const SocialNotificationSettings({
    super.key,
    required this.client,
    this.platform,
  });
  final SocialClient client;
  final SocialPushPlatform? platform;
  @override
  State<SocialNotificationSettings> createState() =>
      _SocialNotificationSettingsState();
}

class _SocialNotificationSettingsState
    extends State<SocialNotificationSettings> {
  late final platform = widget.platform ?? createSocialPushPlatform();
  late final owner = socialPushOwner(widget.client.headersBuilder());
  SocialMap? _local;
  SocialMap _config = {};
  bool _loading = true,
      _saving = false,
      _messages = true,
      _calls = true,
      _online = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await platform.syncOwner(owner);
      if (!mounted || !widget.client.available) return;
      final state = await widget.client.get(platform.action('state'), {
        if (platform.isNative && platform.provider.isNotEmpty)
          'provider': platform.provider,
      });
      if (!mounted || !widget.client.available) return;
      final local = await platform.current(owner);
      if (!mounted || !widget.client.available) return;
      final saved = socialItems(
        state['subscriptions'],
      ).where((s) =>
        local != null && s['device'] == local['device'] &&
        (!platform.isNative ||
          (local['binding'] is String &&
            (local['binding'] as String).isNotEmpty &&
            s['binding'] == local['binding'] &&
            s['provider'] == platform.provider)),
      ).firstOrNull;
      setState(() {
        _config = state;
        _local = saved == null ? null : local;
        _messages = saved?['messages'] != false;
        _calls = saved?['calls'] != false;
        _online = saved?['online'] == true;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_saving || !widget.client.available) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final enabling = _local == null;
    try {
      final local =
          _local ??
          await platform.subscribe(owner, '${_config['publicKey'] ?? ''}');
      if (!mounted || !widget.client.available) {
        await platform.unsubscribe(owner);
        return;
      }
      await widget.client.post(platform.action('subscribe'), {
        'device': local['device'],
        'binding': local['binding'],
        'subscription': local['subscription'],
        'messages': _messages,
        'calls': _calls,
        'online': _online,
      });
      if (!mounted || !widget.client.available) {
        await platform.unsubscribe(owner);
        return;
      }
      setState(() => _local = local);
    } catch (e) {
      if (enabling) await platform.unsubscribe(owner);
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _disable() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final local = _local;
    try {
      // Stop device delivery even when the server is temporarily unreachable.
      await platform.unsubscribe(owner);
      if (mounted) setState(() => _local = null);
      if (local != null && widget.client.available) {
        await widget.client.post(platform.action('unsubscribe'), {
          'device': local['device'],
          if (platform.isNative) 'binding': local['binding'],
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final native = platform.isNative;
    final where = native ? 'device' : 'browser';
    final providerConfig = socialMap(
      socialMap(_config['providers'])[platform.provider],
    );
    final capable = platform.supported && _config['enabled'] == true &&
        (!native || providerConfig['enabled'] == true);
    return SocialScaffold(
      appBar: AppBar(title: const Text('Social notifications')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SocialPanel(
                  accent: skin.primary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.notifications_active_rounded,
                        size: 40,
                        color: skin.primary,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Stay in the conversation',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Choose alerts for this $where. Notifications hide message content and caller names. Opening an alert never answers a call.',
                        style: TextStyle(color: skin.mutedText, height: 1.5),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _local != null
                            ? 'Enabled on this $where'
                            : 'Off on this $where',
                        style: TextStyle(
                          color: _local != null ? skin.success : skin.mutedText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Online alerts'),
                  subtitle: const Text(
                    'Choose people and a bell, short ring or silent alert',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    SocialPageRoute<void>(
                      builder: (_) =>
                          SocialOnlineSettings(client: widget.client),
                    ),
                  ),
                ),
                if (_loading) const LinearProgressIndicator(),
                if (!_loading && !capable)
                  SocialPanel(
                    child: Text(
                      !platform.supported
                          ? native
                            ? 'Background notifications are not configured for this app version yet. In-app alerts still work while KORLIX is active.'
                            : 'This build cannot receive background push notifications. In-app alerts still work while KORLIX is active. On iPhone or iPad, try adding KORLIX to your Home Screen and opening it there.'
                          : '${(native ? providerConfig['reason'] : null) ?? _config['reason'] ?? 'Background notification delivery is not configured yet.'}',
                      style: TextStyle(color: skin.mutedText, height: 1.5),
                    ),
                  ),
                if (platform.permission == 'denied')
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      native
                          ? 'Notifications are blocked on this device. Allow KORLIX notifications in your device Settings, then reopen this screen.'
                          : 'Notifications are blocked in this browser. Allow notifications in the site settings, then reopen this screen.',
                      style: TextStyle(color: skin.danger),
                    ),
                  ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Incoming calls'),
                  subtitle: const Text(
                    'Open the call screen and choose whether to answer',
                  ),
                  value: _calls,
                  onChanged: _saving ? null : (v) => setState(() => _calls = v),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('New messages'),
                  subtitle: const Text('Direct and group message alerts'),
                  value: _messages,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _messages = v),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Selected connections online'),
                  subtitle: const Text(
                    'Background alerts for people chosen in Online alerts; names stay hidden on the lock screen',
                  ),
                  value: _online,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _online = v),
                ),
                const SizedBox(height: 12),
                KorlixActionButton(
                  label: _local == null
                      ? native
                        ? 'Enable device notifications'
                        : 'Enable browser notifications'
                      : 'Save notification preferences',
                  icon: Icons.notifications_active_outlined,
                  busy: _saving,
                  expand: true,
                  tile: MediaQuery.textScalerOf(context).scale(1) > 1.3,
                  onPressed:
                      _loading ||
                          _saving ||
                          !capable ||
                          (!_calls && !_messages && !_online)
                      ? null
                      : _save,
                ),
                if (_local != null)
                  TextButton.icon(
                    onPressed: _saving ? null : _disable,
                    icon: const Icon(Icons.notifications_off_outlined),
                    label: Text('Turn off on this $where'),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(_error!, style: TextStyle(color: skin.danger)),
                  ),
                const SizedBox(height: 18),
                if (native && ['fcm', 'apns'].contains(platform.provider)) ...[
                  Text(
                    platform.provider == 'fcm'
                        ? 'On Android, open a conversation and choose “Keep this chat floating”. Allow bubbles in your device notification settings to keep that chat handy while using other apps.'
                        : 'On iPhone and iPad, choose Reply on a message notification. KORLIX opens after you unlock so you can continue the conversation.',
                    style: TextStyle(color: skin.mutedText, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  native
                      ? 'Delivery depends on notification permissions, device settings and your connection. Alerts can arrive while you use other apps; they never automatically answer a call or turn on your microphone.'
                      : 'Delivery depends on your browser, device settings and connection. Push can alert you when KORLIX is not visible; it does not keep an active call alive when the device suspends the app. Native app background calling needs a separately configured mobile build.',
                  style: TextStyle(color: skin.mutedText, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
