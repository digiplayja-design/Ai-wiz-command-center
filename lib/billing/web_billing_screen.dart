import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'web_billing_client.dart';

Future<void> showKorlixWebBilling(
  BuildContext context, {
  required String baseUrl,
  required Map<String, String> Function() headersBuilder,
  Listenable? sessionChanges,
  FutureOr<void> Function(String)? onTierChanged,
  String? checkoutReturn,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => WebBillingScreen(
        client: WebBillingClient(
          baseUrl: baseUrl,
          headersBuilder: headersBuilder,
          sessionChanges: sessionChanges,
        ),
        onTierChanged: onTierChanged,
        checkoutReturn: checkoutReturn,
      ),
    ),
  );
}

class WebBillingScreen extends StatefulWidget {
  const WebBillingScreen({
    super.key,
    required this.client,
    this.onTierChanged,
    this.checkoutReturn,
    this.openUrl,
  });
  final WebBillingClient client;
  final FutureOr<void> Function(String)? onTierChanged;
  final String? checkoutReturn;
  final Future<bool> Function(Uri)? openUrl;
  @override
  State<WebBillingScreen> createState() => _WebBillingScreenState();
}

class _WebBillingScreenState extends State<WebBillingScreen>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  BillingJson? _data;
  String? _error;
  bool _busy = false;
  Timer? _poll;
  int _polls = 0;
  BuildContext? _confirmation;
  ColorScheme get _colors => Theme.of(context).colorScheme;
  BillingJson get _membership =>
      Map<String, dynamic>.from(_data?['membership'] as Map? ?? {});
  String get _tier => _data?['tier'] as String? ?? 'basic';
  bool get _blocked => _busy || !widget.client.active;
  String _title(String tier) => switch (tier) {
    'ultra' => 'Ultra Premium',
    'pro' => 'Pro',
    'enterprise' => 'Enterprise',
    _ => 'Basic',
  };
  String _date(dynamic value) {
    final d = DateTime.tryParse(value is String ? value : '')?.toLocal();
    return d == null
        ? 'the paid period ends'
        : MaterialLocalizations.of(context).formatMediumDate(d);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.onAccessChanged = () {
      _poll?.cancel();
      if (!mounted) return;
      final dialog = _confirmation;
      if (dialog != null && dialog.mounted) Navigator.of(dialog).pop(false);
      setState(() {
        _data = null;
        _error = 'Your account changed. Close billing and sign in again.';
      });
    };
    unawaited(_load(refresh: widget.checkoutReturn == 'return'));
    if (widget.checkoutReturn == 'return') {
      _poll = Timer.periodic(const Duration(seconds: 10), (_) {
        if (!mounted ||
            !widget.client.active ||
            ++_polls > 6 ||
            _membership['paidUntil'] != null ||
            [
              'canceled',
              'expired',
              'incomplete_expired',
            ].contains(_membership['state']) ||
            _membership['held'] == true) {
          _poll?.cancel();
          return;
        }
        if (!_busy) unawaited(_load(refresh: true));
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy && widget.client.active) {
      unawaited(_load(refresh: true));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _scroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.client.dispose();
    super.dispose();
  }

  Future<void> _accept(BillingJson data) async {
    if (!mounted || !widget.client.active) return;
    if (!['basic', 'pro', 'ultra', 'enterprise'].contains(data['tier']) ||
        data['plans'] is! List ||
        data['version'] is! String) {
      throw const WebBillingException(
        'Plan information is unavailable. Please refresh billing.',
      );
    }
    setState(() => _data = data);
    await widget.onTierChanged?.call(data['tier']);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_blocked) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is WebBillingException
              ? e.message
              : 'Billing could not finish. Refresh and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load({bool refresh = false}) =>
      _run(() async => _accept(await widget.client.status(refresh: refresh)));
  Future<void> _open(Uri uri) async {
    if (!widget.client.active || !mounted) return;
    final opened =
        await (widget.openUrl?.call(uri) ??
            launchUrl(
              uri,
              mode: LaunchMode.platformDefault,
              webOnlyWindowName: '_self',
            ));
    if (!opened) {
      throw const WebBillingException(
        'Your browser could not open this page. Please try again.',
      );
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String button,
    bool checkbox = false,
  }) async {
    bool accepted = false;
    try {
      return await showDialog<bool>(
            context: context,
            builder: (dialog) {
              _confirmation = dialog;
              return StatefulBuilder(
                builder: (context, setDialogState) => AlertDialog(
                  title: Text(title),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(message),
                        if (checkbox) ...[
                          const SizedBox(height: 16),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: accepted,
                            title: const Text(
                              'I agree to the monthly recurring charge.',
                            ),
                            onChanged: (v) =>
                                setDialogState(() => accepted = v == true),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('Not now'),
                    ),
                    FilledButton(
                      onPressed: (!checkbox || accepted) && widget.client.active
                          ? () => Navigator.pop(dialog, true)
                          : null,
                      child: Text(button),
                    ),
                  ],
                ),
              );
            },
          ) ??
          false;
    } finally {
      _confirmation = null;
    }
  }

  Future<void> _buy(BillingJson plan) async {
    final amount = (plan['amount'] as num) / 100, name = plan['name'] as String;
    if (!await _confirm(
      title: 'Subscribe to $name?',
      checkbox: true,
      button: 'Continue to Stripe',
      message:
          'USD \$${amount.toStringAsFixed(2)} per month, automatically renewed until canceled. '
          'Cancel renewal in Plans & Billing; access continues through the paid period. '
          'AI GAS and Music Studio are separate. Stripe will show the final charge before you pay.',
    )) {
      return;
    }
    if (!mounted || !widget.client.active) return;
    await _run(
      () async =>
          _open(await widget.client.checkout(plan['tier'], _data!['version'])),
    );
  }

  Future<void> _cancel() async {
    if (!await _confirm(
      title: 'Stop monthly renewal?',
      button: 'Cancel renewal',
      message:
          'Your subscription will not renew. Your paid access continues until ${_date(_membership['paidUntil'])}.',
    )) {
      return;
    }
    if (!mounted || !widget.client.active) return;
    await _run(() async => _accept(await widget.client.cancelRenewal()));
  }

  Future<void> _abandon() async {
    if (!await _confirm(
      title: 'Close unpaid checkout?',
      button: 'Close checkout',
      message:
          'This closes the current unpaid checkout so you can choose another plan. Any completed payment will still be checked.',
    )) {
      return;
    }
    if (!mounted || !widget.client.active) return;
    await _run(() async => _accept(await widget.client.abandonCheckout()));
  }

  Widget _notice(String text, {bool error = false}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: error ? _colors.errorContainer : _colors.secondaryContainer,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: error ? _colors.onErrorContainer : _colors.onSecondaryContainer,
      ),
    ),
  );
  Widget _card({
    required String title,
    required String subtitle,
    required String price,
    required Color accent,
    required IconData icon,
    required List<String> features,
    Widget? action,
    bool current = false,
  }) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: accent.withValues(alpha: .55),
        width: current ? 2 : 1,
      ),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(accent.withValues(alpha: .14), _colors.surface),
          _colors.surface,
        ],
      ),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: .08),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(icon, color: accent, size: 30),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (current) const Chip(label: Text('Current plan')),
          ],
        ),
        const SizedBox(height: 12),
        Text(subtitle, style: TextStyle(color: _colors.onSurfaceVariant)),
        const SizedBox(height: 20),
        Text(
          price,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 20),
        for (final feature in features)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_outline, size: 20, color: accent),
                const SizedBox(width: 10),
                Expanded(child: Text(feature)),
              ],
            ),
          ),
        if (action != null) ...[
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: action),
        ],
      ],
    ),
  );
  Widget _paidCard(BillingJson plan) {
    final tier = plan['tier'] as String, name = plan['name'] as String;
    final pending = _membership['canResume'] == true;
    final matching = !pending || _membership['requestedTier'] == tier;
    final canBuy = _data?['canPurchase'] == true && matching;
    final manage = _data?['canManage'] == true && !pending;
    return _card(
      title: name,
      subtitle: tier == 'pro'
          ? 'Room for your everyday ideas.'
          : 'More capacity for ambitious work.',
      price:
          'USD \$${((plan['amount'] as num) / 100).toStringAsFixed(2)} / month',
      accent: tier == 'pro' ? const Color(0xFF8864E8) : const Color(0xFFBA850A),
      icon: tier == 'pro' ? Icons.auto_awesome : Icons.workspace_premium,
      current: _tier == tier,
      features: (plan['features'] as List? ?? []).whereType<String>().toList(),
      action: FilledButton(
        onPressed: _blocked
            ? null
            : canBuy
            ? () => _buy(plan)
            : manage
            ? () => _run(() async => _open(await widget.client.portal()))
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            canBuy
                ? pending
                      ? 'Continue $name checkout'
                      : 'Choose $name'
                : manage
                ? 'Manage or change plan'
                : _tier == tier
                ? 'Current plan'
                : 'Purchase unavailable',
          ),
        ),
      ),
    );
  }

  Widget _membershipCard() {
    final m = _membership, state = m['state'];
    final end = DateTime.tryParse(m['paidUntil'] as String? ?? '');
    final paid =
        end != null &&
        end.isAfter(DateTime.now()) &&
        m['paidTier'] != null &&
        m['held'] != true &&
        ['active', 'past_due'].contains(state);
    String message;
    if (m['held'] == true) {
      message =
          'A payment needs review. Contact support for help with your membership.';
    } else if (state == 'past_due') {
      message =
          'Your payment needs attention. ${paid ? 'Paid access continues until ${_date(m['paidUntil'])}.' : 'Update your payment method in Manage Billing.'}';
    } else if (paid) {
      message = m['renewalCanceled'] == true
          ? 'Renewal canceled. Paid access ends ${_date(m['paidUntil'])}.'
          : '${_title(m['paidTier'])} is active. Next period starts ${_date(m['paidUntil'])}.';
    } else if (state == 'checkout') {
      message =
          'Checkout is open. If you already paid, refresh billing while payment confirmation arrives.';
    } else if (state == 'canceled' ||
        state == 'expired' ||
        state == 'incomplete_expired') {
      message = 'No active web subscription. You can choose a plan below.';
    } else if (_data?['nativeSubscription'] == true) {
      message =
          'Your plan is billed through an app store. Manage it with that store to avoid a second subscription.';
    } else if (_tier != 'basic') {
      message =
          'Your account already has ${_title(_tier)} access. Contact support for billing or plan changes.';
    } else {
      message =
          'You are using the free Basic plan. Choose a monthly plan when you need more capacity.';
    }
    return _card(
      title: 'Your membership',
      subtitle: message,
      price: _title(_tier),
      accent: _colors.primary,
      icon: Icons.account_circle_outlined,
      features: const [],
      action: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          OutlinedButton.icon(
            onPressed: _blocked ? null : () => _load(refresh: true),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh billing'),
          ),
          if (state == 'checkout')
            TextButton(
              onPressed: _blocked ? null : _abandon,
              child: const Text('Close unpaid checkout'),
            ),
          if (_data?['canManage'] == true)
            OutlinedButton.icon(
              onPressed: _blocked
                  ? null
                  : () => _run(() async => _open(await widget.client.portal())),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Manage Billing'),
            ),
          if (m['tier'] != null &&
              !['canceled', 'incomplete_expired'].contains(state) &&
              m['renewalCanceled'] != true)
            TextButton(
              onPressed: _blocked ? null : _cancel,
              child: const Text('Cancel renewal'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plans = (_data?['plans'] as List? ?? [])
        .whereType<Map>()
        .map((x) => Map<String, dynamic>.from(x))
        .where(
          (p) =>
              ['pro', 'ultra'].contains(p['tier']) &&
              p['amount'] is num &&
              p['name'] is String &&
              p['currency'] == 'usd' &&
              p['interval'] == 'month',
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Plans & Billing')),
      body: SafeArea(
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Make room for your next idea.',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Monthly plans. Clear allowances. Billing you can manage yourself.',
                    ),
                    const SizedBox(height: 24),
                    if (_error != null) _notice(_error!, error: true),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: LinearProgressIndicator(),
                      ),
                    if (_data == null && !_busy && widget.client.active)
                      OutlinedButton(
                        onPressed: () => _load(),
                        child: const Text('Retry loading plans'),
                      ),
                    if (_data != null) ...[
                      if (_data?['livePayments'] == false)
                        _notice(
                          'Sandbox billing: test payments do not activate a paid KORLIX account.',
                        ),
                      if (_data?['checkoutEnabled'] != true)
                        _notice(
                          'New web subscriptions are being prepared. Existing billing management remains available.',
                        ),
                      if (widget.checkoutReturn == 'cancel')
                        _notice(
                          'You returned from checkout. Your subscription status below is checked with KORLIX.',
                        ),
                      _membershipCard(),
                      const SizedBox(height: 24),
                      LayoutBuilder(
                        builder: (context, constraints) => Wrap(
                          spacing: 20,
                          runSpacing: 20,
                          children: [
                            for (final p in plans)
                              SizedBox(
                                width: constraints.maxWidth >= 700
                                    ? (constraints.maxWidth - 20) / 2
                                    : constraints.maxWidth,
                                child: _paidCard(p),
                              ),
                            SizedBox(
                              width: constraints.maxWidth >= 700
                                  ? (constraints.maxWidth - 20) / 2
                                  : constraints.maxWidth,
                              child: _card(
                                title: 'Basic',
                                subtitle: 'Start exploring KORLIX.',
                                price: 'Free',
                                accent: _colors.primary,
                                icon: Icons.explore_outlined,
                                current: _tier == 'basic',
                                features: const [
                                  'All AI characters',
                                  'Daily usage limits',
                                  'No subscription required',
                                ],
                              ),
                            ),
                            SizedBox(
                              width: constraints.maxWidth >= 700
                                  ? (constraints.maxWidth - 20) / 2
                                  : constraints.maxWidth,
                              child: _card(
                                title: 'Enterprise',
                                subtitle: 'Access built around your business.',
                                price: 'Contact Sales',
                                accent: const Color(0xFF258C73),
                                icon: Icons.business_outlined,
                                current: _tier == 'enterprise',
                                features: const [
                                  'Custom organization access',
                                  'Agreed usage and support',
                                  'All AI characters',
                                ],
                                action: OutlinedButton(
                                  onPressed: _blocked
                                      ? null
                                      : () => _run(
                                          () => _open(
                                            Uri(
                                              scheme: 'mailto',
                                              path:
                                                  'support@korlixdeveloper.com',
                                              queryParameters: {
                                                'subject':
                                                    'KORLIX Enterprise enquiry',
                                              },
                                            ),
                                          ),
                                        ),
                                  child: const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text('Contact Sales'),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Plans renew monthly until canceled. AI GAS and Music Studio are separate purchases. '
                        'A generation may use more than one credit. Allowances are subject to the current feature limits and do not promise unlimited use.',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          TextButton(
                            onPressed: _blocked
                                ? null
                                : () => _run(
                                    () => _open(
                                      Uri.parse(
                                        'https://www.korlixdeveloper.com/subscription-terms.html',
                                      ),
                                    ),
                                  ),
                            child: const Text('Subscription terms'),
                          ),
                          TextButton(
                            onPressed: _blocked
                                ? null
                                : () => _run(
                                    () => _open(
                                      Uri.parse(
                                        'https://www.korlixdeveloper.com/privacy-policy.html',
                                      ),
                                    ),
                                  ),
                            child: const Text('Privacy'),
                          ),
                          TextButton(
                            onPressed: _blocked
                                ? null
                                : () => _run(
                                    () => _open(
                                      Uri.parse(
                                        'https://www.korlixdeveloper.com/support.html',
                                      ),
                                    ),
                                  ),
                            child: const Text('Billing support'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
