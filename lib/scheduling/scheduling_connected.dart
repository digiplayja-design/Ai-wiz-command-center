import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'scheduling_client.dart';

String schedulingMoney(dynamic cents) =>
    '\$${((cents as num? ?? 0) / 100).toStringAsFixed(2)} USD';
String _requestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final s = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

class SchedulingConnectedPanel extends StatefulWidget {
  const SchedulingConnectedPanel({
    super.key,
    required this.mode,
    required this.data,
    required this.client,
    required this.refresh,
  });
  final String mode;
  final SchedulingMap data;
  final SchedulingClient client;
  final Future<void> Function() refresh;
  @override
  State<SchedulingConnectedPanel> createState() =>
      _SchedulingConnectedPanelState();
}

class _SchedulingConnectedPanelState extends State<SchedulingConnectedPanel> {
  final _prompt = TextEditingController();
  String _request = _requestId();
  SchedulingMap _proposal = {};
  String? _error;
  bool _busy = false;
  SchedulingMap get _cap => schedulingMap(widget.data['capabilities']);
  SchedulingMap get _stripe =>
      schedulingMap(schedulingMap(_cap['providers'])['stripe']);
  SchedulingMap get _merchantSetup =>
      schedulingMap(widget.data['merchant_setup']);
  List<SchedulingMap> get _connections =>
      schedulingItems(widget.data['connections']);
  List<SchedulingMap> get _teams => schedulingItems(widget.data['teams']);
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_access);
  }

  void _access() {
    if (!widget.client.available && mounted) {
      setState(() {
        _proposal = {};
        _prompt.clear();
        _error = null;
      });
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_access);
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      widget.client.guard();
      await action();
    } catch (e) {
      if (mounted && widget.client.available) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(
    String title,
    String body, [
    String label = 'Confirm',
  ]) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(label),
            ),
          ],
        ),
      ) ==
      true;
  Future<String?> _input(String title, String label, {int max = 100}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLength: max,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    return result;
  }

  Widget _card(List<Widget> children) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
  Widget _title(String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(body),
      ],
    ),
  );
  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _connect(String provider) async {
    final payment = provider == 'stripe';
    if (!await _confirm(
      payment
          ? 'Connect your Stripe business account?'
          : 'Connect your calendar?',
      payment
          ? 'Customers pay your Stripe Standard account directly. Stripe processing fees apply to your account. KORLIX can create booking checkout sessions and issue approved full refunds, including automatic refunds when a paid booking cannot be confirmed. Review the account before enabling it.'
          : 'KORLIX will read event times from calendars you select. You may also choose one calendar for appointment updates. These entries do not invite guests. You will review the account and calendar choices before enabling availability checks.',
      'Continue to $provider',
    )) {
      return;
    }
    await _run(() async {
      final d = await widget.client.post('connections/$provider/start', {
        'confirmed': true,
      });
      widget.client.guard();
      final uri = Uri.parse('${d['url']}');
      if (uri.scheme != 'https' ||
          uri.origin != Uri.parse(widget.client.baseUrl).origin ||
          uri.userInfo.isNotEmpty) {
        throw const SchedulingException(
          'The connection link could not be verified.',
        );
      }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const SchedulingException(
          'Open the connection link again from this screen.',
        );
      }
      await widget.refresh();
      _notice(
        'After authorization, return here, refresh, and confirm the account.',
      );
    });
  }

  Future<void> _openMerchantSetup(SchedulingMap result) async {
    widget.client.guard();
    final uri = Uri.tryParse('${result['url']}');
    if (uri == null ||
        uri.scheme != 'https' ||
        !const {
          'connect.stripe.com',
          'accounts.stripe.com',
        }.contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443) {
      throw const SchedulingException(
        'The Stripe setup link could not be verified. Try continuing setup again.',
      );
    }
    if (!await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_self',
    )) {
      throw const SchedulingException(
        'Stripe could not open. Choose Continue Stripe setup to try again.',
      );
    }
    widget.client.guard();
    await widget.refresh();
    _notice(
      'After Stripe setup, return here and review and confirm your account.',
    );
  }

  Future<void> _startMerchantSetup() async {
    final name = TextEditingController(
      text: '${schedulingMap(widget.data['profile'])['display_name'] ?? ''}',
    );
    final country = TextEditingController(text: 'US');
    final form = GlobalKey<FormState>();
    final testMode = _stripe['livemode'] != true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Set up your Stripe business'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    testMode
                        ? 'This creates a sandbox Stripe business account for this KORLIX account. No real payments are taken.'
                        : 'This creates a Stripe business account for this KORLIX account.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Customers pay your business directly. KORLIX charges no transaction fee; Stripe processing fees apply. Enter bank and verification details only on Stripe. Your current merchant stays connected until you review and confirm the new account.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('merchant-display-name'),
                    controller: name,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Business name',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter your business name.'
                        : null,
                  ),
                  TextFormField(
                    key: const ValueKey('merchant-country'),
                    controller: country,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Business country',
                      helperText:
                          'Setup is currently available for United States businesses only.',
                      helperMaxLines: 2,
                    ),
                    validator: (value) => value?.trim().toUpperCase() == 'US'
                        ? null
                        : 'Stripe business setup is currently available in the United States only.',
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(dialog, true);
            },
            child: const Text('Create Stripe account'),
          ),
        ],
      ),
    );
    final displayName = name.text.trim(),
        countryCode = country.text.trim().toUpperCase();
    Future<void>.delayed(const Duration(seconds: 1), () {
      name.dispose();
      country.dispose();
    });
    if (accepted != true || !mounted) return;
    await _run(() async {
      final result = await widget.client.post('stripe/merchant-setup/start', {
        'confirmed': true,
        'display_name': displayName,
        'country': countryCode,
      });
      await _openMerchantSetup(result);
    });
  }

  Future<void> _resumeMerchantSetup() async {
    final id = '${_merchantSetup['id']}';
    if (!await _confirm(
      'Continue Stripe setup?',
      'Open Stripe to finish this business account’s verification. Bank and identity details stay on Stripe. Return here to review and confirm the account before replacing your current merchant.',
      'Continue to Stripe',
    )) {
      return;
    }
    if (!mounted) return;
    await _run(() async {
      final result = await widget.client.post(
        'stripe/merchant-setup/$id/resume',
        {'confirmed': true},
      );
      await _openMerchantSetup(result);
    });
  }

  Future<void> _reviewMerchantSetup() async {
    final id = '${_merchantSetup['id']}';
    await _run(() async {
      final result = await widget.client.get(
        'stripe/merchant-setup/$id/review',
      );
      widget.client.guard();
      if (!mounted) return;
      final identity = schedulingMap(result['identity']);
      final reviewToken = result['review_token'];
      if (reviewToken is! String || reviewToken.isEmpty) {
        throw const SchedulingException(
          'Refresh and review the Stripe account again.',
        );
      }
      final ready = identity['charges_enabled'] == true;
      final description = [
        '${identity['label']} (${identity['id']})',
        identity['livemode'] == true
            ? 'Live Stripe account.'
            : 'TEST MODE — no real payments.',
        ready
            ? 'Stripe payment capabilities are active. Checkout remains subject to KORLIX payment availability.'
            : 'Stripe verification is still pending. You can save this account, but payments remain unavailable until verification is complete.',
        if (result['replaces_existing'] == true)
          'Confirming replaces the Stripe merchant connected to this KORLIX account.',
        'Customers pay your business directly. KORLIX charges no transaction fee; Stripe processing fees apply.',
      ].join('\n\n');
      if (!await _confirm(
        'Confirm your Stripe business?',
        description,
        'Confirm account',
      )) {
        return;
      }
      await widget.client.post('stripe/merchant-setup/$id/confirm', {
        'confirmed': true,
        'review_token': reviewToken,
      });
      await widget.refresh();
      _notice(
        ready
            ? 'Stripe business account saved.'
            : 'Account saved. Complete Stripe verification before taking payments.',
      );
    });
  }

  Future<void> _calendars(SchedulingMap c) async {
    await _run(() async {
      await widget.client.post('connections/${c['id']}/calendars');
      final latest = await widget.client.get('connections');
      final fresh = schedulingItems(
        latest['connections'],
      ).firstWhere((x) => x['id'] == c['id']);
      if (!mounted) return;
      final choices = schedulingItems(fresh['calendars']);
      final selected = Set<String>.from(
        (fresh['busy_ids'] as List? ?? []).map((x) => '$x'),
      ).intersection(choices.map((x) => '${x['id']}').toSet());
      String target =
          choices.any(
            (x) => x['id'] == fresh['write_id'] && x['writable'] == true,
          )
          ? '${fresh['write_id']}'
          : '';
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Calendar availability and updates'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose one to five calendars to check for conflicts. New bookings stop if these calendars cannot be checked.',
                    ),
                    const SizedBox(height: 12),
                    for (final cal in choices)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${cal['name']}'),
                        subtitle: Text('${cal['timezone']}'),
                        value: selected.contains(cal['id']),
                        onChanged: (on) => update(() {
                          if (on == true && selected.length < 5) {
                            selected.add('${cal['id']}');
                          } else if (on != true) {
                            selected.remove(cal['id']);
                          }
                        }),
                      ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: target,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Write appointment updates to',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Do not create calendar entries'),
                        ),
                        for (final cal in choices.where(
                          (x) => x['writable'] == true,
                        ))
                          DropdownMenuItem(
                            value: '${cal['id']}',
                            child: Text(
                              '${cal['name']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => update(() => target = v ?? ''),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'One write calendar per host. Future KORLIX booking activity creates or updates host-only entries. Make appointment changes in KORLIX; edits made in your calendar do not reschedule the KORLIX appointment.',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(dialog, true),
                child: const Text('Enable selected calendars'),
              ),
            ],
          ),
        ),
      );
      if (accepted == true) {
        await widget.client.post('connections/${c['id']}/settings', {
          'revision': fresh['revision'],
          'confirmed': true,
          'busy_ids': selected.toList(),
          'write_id': target.isEmpty ? null : target,
        });
      }
      await widget.refresh();
    });
  }

  Widget _connectionView() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(
        'Your connections',
        'Choose which calendars protect your availability and where your business receives booking payments.',
      ),
      for (final provider in ['google', 'microsoft', 'stripe'])
        _card([
          Text(
            {
              'google': 'Google Calendar',
              'microsoft': 'Microsoft Outlook',
              'stripe': 'Stripe payments',
            }[provider]!,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            provider == 'stripe'
                ? 'Direct payments to your business. USD card checkout, payment verification, and full refunds.'
                : 'Check calendar conflicts at booking time and keep a selected calendar updated.',
          ),
          const SizedBox(height: 12),
          if (schedulingMap(
                schedulingMap(_cap['providers'])[provider],
              )['configured'] !=
              true) ...[
            if (provider != 'stripe' ||
                _stripe['onboarding_configured'] != true) ...[
              const Chip(label: Text('Administrator setup required')),
              const Text(
                'The provider’s application credentials must be configured before accounts can connect.',
              ),
            ],
          ] else
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _connect(provider),
              icon: const Icon(Icons.add_link),
              label: const Text('Connect account'),
            ),
          if (provider == 'stripe' &&
              _stripe['onboarding_configured'] == true) ...[
            const SizedBox(height: 10),
            if (_merchantSetup.isEmpty)
              FilledButton.icon(
                onPressed: _busy ? null : _startMerchantSetup,
                icon: const Icon(Icons.business_outlined),
                label: const Text('Set up Stripe business'),
              )
            else ...[
              Text(
                'Business setup: ${_merchantSetup['display_name']}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                _merchantSetup['livemode'] == true
                    ? 'Finish verification on Stripe, then review the account here.'
                    : 'Sandbox setup — no real payments. Finish on Stripe, then review the account here.',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : _resumeMerchantSetup,
                    child: const Text('Continue Stripe setup'),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _reviewMerchantSetup,
                    child: const Text('Review and confirm business'),
                  ),
                ],
              ),
            ],
          ],
          for (final c in _connections.where((c) => c['provider'] == provider))
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${c['label']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${c['state']} · ${c['enabled'] == true ? 'enabled' : 'not enabled'}',
                  ),
                  if (provider == 'stripe')
                    Text(
                      '${c['livemode'] == true ? 'Live payments' : 'TEST MODE — no real payments'} · ${c['charges_enabled'] == true ? 'Charges enabled' : 'Stripe onboarding incomplete'}',
                    ),
                  if (c['last_sync_at'] != null)
                    Text('Last calendar check: ${c['last_sync_at']}'),
                  if (c['last_error'] != null) Text('${c['last_error']}'),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      if (provider != 'stripe' && c['state'] == 'connected')
                        TextButton(
                          onPressed: _busy ? null : () => _calendars(c),
                          child: const Text('Choose calendars'),
                        ),
                      if (c['state'] != 'disconnected')
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  if (await _confirm(
                                    'Disconnect this account?',
                                    provider == 'stripe'
                                        ? 'Paid event types will stop taking new payments. Use Stripe directly for older refunds after disconnecting. Complete open checkout holds and pending refunds first.'
                                        : 'KORLIX will stop checking this account and updating its entries. Existing external calendar entries remain; remove or manage them in your calendar. New bookings will use your remaining enabled calendars and KORLIX availability.',
                                  )) {
                                    await _run(() async {
                                      await widget.client.post(
                                        'connections/${c['id']}/disconnect',
                                        {'confirmed': true},
                                      );
                                      await widget.refresh();
                                    });
                                  }
                                },
                          child: const Text('Disconnect'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ]),
      for (final a in schedulingItems(widget.data['pending']))
        _card([
          Text('${a['provider']} connection · ${a['status']}'),
          if (a['status'] == 'ready') ...[
            Text('${schedulingMap(a['identity'])['label']}'),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      if (await _confirm(
                        'Use this account?',
                        'Connect ${schedulingMap(a['identity'])['label']} to this KORLIX host?',
                        'Confirm account',
                      )) {
                        await _run(() async {
                          await widget.client.post(
                            'connections/attempts/${a['id']}/confirm',
                            {'confirmed': true},
                          );
                          await widget.refresh();
                        });
                      }
                    },
              child: const Text('Review and confirm account'),
            ),
          ] else
            const Text(
              'Finish authorization in the opened tab, then refresh here.',
            ),
        ]),
      OutlinedButton.icon(
        onPressed: _busy ? null : () => _run(widget.refresh),
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh connections'),
      ),
    ],
  );
  Future<void> _invite(SchedulingMap team) async {
    if (!await _confirm(
      'Create a team invitation?',
      'This replaces the previous invite code. Anyone with the new code can review and join this team for seven days. Share it only with intended hosts.',
      'Create invite code',
    )) {
      return;
    }
    await _run(() async {
      final d = await widget.client.post('teams/${team['id']}/invite', {
        'revision': team['revision'],
        'confirmed': true,
      });
      await widget.refresh();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Team invite code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Share this privately. Expires in seven days. Team members must have a verified KORLIX account and save their host profile.',
              ),
              const SizedBox(height: 12),
              SelectableText('${d['invite']}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () async {
                widget.client.guard();
                await Clipboard.setData(ClipboardData(text: '${d['invite']}'));
                _notice('Invite code copied.');
              },
              child: const Text('Copy code'),
            ),
          ],
        ),
      );
    });
  }

  Widget _teamView() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title(
        'Meet as a team',
        'Round-robin assigns one available host fairly. Collective meetings require every selected host. Configure assignments in an event type.',
      ),
      Wrap(
        spacing: 12,
        runSpacing: 10,
        children: [
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    final name = await _input(
                      'Create a scheduling team',
                      'Team name',
                    );
                    if (name != null && name.isNotEmpty) {
                      await _run(() async {
                        await widget.client.post('teams', {'name': name});
                        await widget.refresh();
                      });
                    }
                  },
            icon: const Icon(Icons.group_add_outlined),
            label: const Text('Create team'),
          ),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () async {
                    final code = await _input(
                      'Join a scheduling team',
                      'Invite code',
                      max: 64,
                    );
                    if (code == null || code.isEmpty) return;
                    await _run(() async {
                      final t = await widget.client.post('teams/preview_join', {
                        'invite': code,
                      });
                      if (!mounted) return;
                      if (await _confirm(
                        'Join ${t['name']}?',
                        '${t['owner_name']} can assign team meetings during your available hours. Your name, timezone, and participation are visible to the team. Assigned appointments and guest details appear in your schedule. Leaving stops future assignments; existing appointments remain.',
                        'Join team',
                      )) {
                        await widget.client.post('teams/join', {
                          'invite': code,
                          'confirmed': true,
                        });
                        await widget.refresh();
                      }
                    });
                  },
            child: const Text('Join with invite code'),
          ),
        ],
      ),
      const SizedBox(height: 22),
      if (_teams.isEmpty)
        _card([
          const Text('Create a team or join using a private invite code.'),
        ]),
      for (final team in _teams)
        _card([
          Text(
            '${team['name']}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            team['is_owner'] == true ? 'You manage this team' : 'Team member',
          ),
          const SizedBox(height: 12),
          for (final m in schedulingItems(team['members']))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${m['name']}'),
              subtitle: Text(
                '${m['timezone']} · ${m['active'] == true ? 'active' : 'inactive'}',
              ),
              trailing:
                  team['is_owner'] == true &&
                      m['active'] == true &&
                      m['is_owner'] != true
                  ? TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              if (await _confirm(
                                'Remove ${m['name']}?',
                                'Future assignments stop. Existing appointments remain.',
                              )) {
                                await _run(() async {
                                  await widget.client.post(
                                    'teams/${team['id']}/remove',
                                    {
                                      'user_id': m['user_id'],
                                      'confirmed': true,
                                    },
                                  );
                                  await widget.refresh();
                                });
                              }
                            },
                      child: const Text('Remove'),
                    )
                  : null,
            ),
          Wrap(
            spacing: 10,
            children: [
              if (team['is_owner'] == true)
                OutlinedButton(
                  onPressed: _busy ? null : () => _invite(team),
                  child: const Text('Create invite code'),
                ),
              if (team['is_owner'] != true)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          if (await _confirm(
                            'Leave this team?',
                            'Future assignments stop. Your existing appointments remain.',
                          )) {
                            await _run(() async {
                              await widget.client.post(
                                'teams/${team['id']}/leave',
                                {'confirmed': true},
                              );
                              await widget.refresh();
                            });
                          }
                        },
                  child: const Text('Leave team'),
                ),
            ],
          ),
        ]),
    ],
  );
  String _time(dynamic value) {
    final t = DateTime.tryParse('$value')?.toLocal();
    return t == null
        ? '$value'
        : '${t.toString().substring(0, 16)} ${t.timeZoneName} (your device time)';
  }

  Widget _assistantView() {
    final plan = schedulingMap(_proposal['plan']);
    final state = _proposal['state'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          'Plan with KORLIX',
          'Describe the meeting or schedule change. KORLIX prepares a proposal for your review. Nothing changes until you approve.',
        ),
        _card([
          const Text(
            'Try “Create a 30-minute discovery call”, “Find times for my consultation next Tuesday”, or “Make Fridays unavailable”.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _prompt,
            enabled: !_busy,
            maxLines: 4,
            maxLength: 3000,
            decoration: const InputDecoration(
              labelText: 'What would you like to schedule?',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              _request = _requestId();
            },
          ),
          const SizedBox(height: 10),
          const Text(
            'Uses your host timezone, availability, event titles, and upcoming booking names/times. Guest emails and answers are excluded. Up to ten requests per day.',
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _busy || _cap['ai_scheduling'] != true
                ? null
                : () => _run(() async {
                    final d = await widget.client.post('ai/propose', {
                      'prompt': _prompt.text.trim(),
                      'request_id': _request,
                    });
                    if (mounted) {
                      setState(() => _proposal = schedulingMap(d['proposal']));
                    }
                  }),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Prepare proposal'),
          ),
          if (_cap['ai_scheduling'] != true)
            const Text('KORLIX 2MEETU AI needs administrator setup.'),
        ]),
        if (_proposal.isNotEmpty)
          _card([
            Text(
              state == 'applied'
                  ? 'Change applied'
                  : state == 'generating'
                  ? 'KORLIX is preparing your proposal'
                  : state == 'failed'
                  ? 'Proposal could not be prepared'
                  : 'Review your proposal',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (plan.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('${plan['summary']}'),
              if (plan['old_starts_at'] != null)
                Text('Current: ${_time(plan['old_starts_at'])}'),
              if (plan['starts_at'] != null)
                Text('Proposed: ${_time(plan['starts_at'])}'),
              if (plan['action'] == 'draft') ...[
                const SizedBox(height: 12),
                Text('${schedulingMap(plan['data'])['description']}'),
                const Text(
                  'Review location, buffers, price, and other settings in Event types before publishing.',
                ),
              ],
              if (plan['action'] == 'availability') ...[
                const SizedBox(height: 12),
                for (final day in schedulingItems(
                  schedulingMap(plan['data'])['weekly'],
                ))
                  Text(
                    '${['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][day['day'] as int]}: ${(day['windows'] as List).isEmpty ? 'Unavailable' : (day['windows'] as List).map((w) {
                            String m(dynamic v) => '${'${(v as int) ~/ 60}'.padLeft(2, '0')}:${'${v % 60}'.padLeft(2, '0')}';
                            return '${m(w[0])}–${m(w[1])}';
                          }).join(', ')}',
                  ),
              ],
              if (plan['action'] == 'slots') ...[
                const SizedBox(height: 12),
                if (schedulingItems(plan['slots']).isEmpty)
                  const Text('No available times in this week.'),
                for (final slot in schedulingItems(plan['slots']).take(40))
                  Text(_time(slot['starts_at'])),
                if (schedulingItems(plan['slots']).length > 40)
                  const Text('More times are available on the booking page.'),
              ],
              const SizedBox(height: 14),
              if (state == 'review' &&
                  [
                    'draft',
                    'availability',
                    'cancel',
                    'reschedule',
                  ].contains(plan['action']))
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          if (await _confirm(
                            'Apply this proposal?',
                            '${plan['summary']}\n${plan['starts_at'] != null ? 'New time: ${_time(plan['starts_at'])}' : ''}',
                            'Approve change',
                          )) {
                            await _run(() async {
                              final d = await widget.client.post(
                                'ai/${_proposal['id']}/apply',
                                {'confirmed': true},
                              );
                              if (mounted) {
                                setState(
                                  () =>
                                      _proposal = schedulingMap(d['proposal']),
                                );
                              }
                              await widget.refresh();
                            });
                          }
                        },
                  child: const Text('Review and approve change'),
                ),
            ],
            if (state == 'generating')
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        final d = await widget.client.get(
                          'ai/${_proposal['id']}',
                        );
                        if (mounted) {
                          setState(
                            () => _proposal = schedulingMap(d['proposal']),
                          );
                        }
                      }),
                child: const Text('Refresh proposal'),
              ),
            if (state == 'review')
              Text('Proposal expires: ${_time(_proposal['expires_at'])}'),
          ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.client.available) return const SizedBox.shrink();
    if (schedulingMap(widget.data['profile']).isEmpty) {
      return _card([
        const Text(
          'Save your host name and availability before using connections, teams, or scheduling AI.',
        ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          _card([
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ]),
        switch (widget.mode) {
          'connections' => _connectionView(),
          'teams' => _teamView(),
          _ => _assistantView(),
        },
      ],
    );
  }
}
