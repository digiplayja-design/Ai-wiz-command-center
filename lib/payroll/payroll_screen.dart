import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'payroll_client.dart';

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({
    super.key,
    required this.client,
    this.openBookkeeping,
    this.openWorkforce,
  });
  final PayrollClient client;
  final Future<void> Function()? openBookkeeping, openWorkforce;
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen>
    with WidgetsBindingObserver {
  List<PayrollMap> _accounts = [], _businesses = [], _audit = [];
  PayrollMap _provider = {}, _onboarding = {};
  String? _selected, _error;
  bool _loading = true, _busy = false;
  Timer? _timer;
  ModalRoute<dynamic>? _route;
  int _generation = 0;
  PayrollMap get _account =>
      _accounts.where((a) => a['id'] == _selected).firstOrNull ?? {};
  bool get _connected => _account['status'] == 'connected';
  bool get _usable =>
      _connected &&
      _account['terms_accepted'] == true &&
      _provider['ready'] == true &&
      _account['environment'] == _provider['environment'] &&
      _account['needs_attention'] != true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.addListener(_accessChanged);
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!_busy && !_loading && widget.client.available) {
        unawaited(_load(quiet: true));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_busy &&
        widget.client.available) {
      unawaited(_load());
    }
  }

  void _accessChanged() {
    if (!mounted || widget.client.available) return;
    _generation++;
    setState(() {
      _accounts = [];
      _businesses = [];
      _audit = [];
      _onboarding = {};
      _provider = {};
      _selected = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _route != null) {
        Navigator.of(context).popUntil((r) => r == _route || r.isFirst);
      }
    });
  }

  Future<void> _load({bool quiet = false, String? select}) async {
    final generation = ++_generation;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await widget.client.get('workspaces');
      if (!mounted || generation != _generation) return;
      final accounts = payrollItems(result['accounts']);
      final selected = select ?? _selected;
      final current = accounts.any((a) => a['id'] == selected)
          ? selected
          : accounts.firstOrNull?['id']?.toString();
      PayrollMap details = {};
      if (current != null) {
        details = await widget.client.get('workspaces/$current');
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        if (current != _selected) _onboarding = {};
        _accounts = accounts;
        _businesses = payrollItems(result['businesses']);
        _provider = payrollMap(result['provider']);
        _selected = current;
        _audit = payrollItems(details['audit']);
      });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = '$e');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
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
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final used = _accounts.map((a) => a['business_id']).toSet();
    final choices = _businesses.where((b) => !used.contains(b['id'])).toList();
    if (choices.isEmpty) {
      await widget.openBookkeeping?.call();
      if (mounted) await _load();
      return;
    }
    String business = '${choices.first['id']}';
    final name = TextEditingController(text: '${choices.first['name']}');
    bool confirmed = false;
    final result = await showDialog<PayrollMap>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Create US payroll workspace'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose a business you own. Each business has a separate payroll workspace in US dollars.',
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    initialValue: business,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Business'),
                    items: choices
                        .map(
                          (b) => DropdownMenuItem(
                            value: '${b['id']}',
                            child: Text(
                              '${b['name']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => update(() {
                      business = v!;
                      name.text =
                          '${choices.firstWhere((b) => b['id'] == v)['name']}';
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: name,
                    maxLength: 160,
                    decoration: const InputDecoration(
                      labelText: 'Legal business name',
                    ),
                    onChanged: (_) => update(() {}),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: confirmed,
                    onChanged: (v) => update(() => confirmed = v == true),
                    title: const Text(
                      'This is a US business and I am authorized to manage its payroll.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: confirmed && name.text.trim().isNotEmpty
                  ? () => Navigator.pop(dialog, <String, dynamic>{
                      'business_id': business,
                      'legal_name': name.text.trim(),
                      'country': 'US',
                      'confirmed': true,
                    })
                  : null,
              child: const Text('Create workspace'),
            ),
          ],
        ),
      ),
    );
    // Dispose after the route's closing animation has released the text fields.
    Future<void>.delayed(const Duration(seconds: 1), name.dispose);
    if (result != null && mounted) {
      await _run(() async {
        final response = await widget.client.post('workspaces', result);
        await _load(select: '${payrollMap(response['account'])['id']}');
      });
    }
  }

  Future<void> _connect() async {
    final account = _selected;
    final first = TextEditingController(), last = TextEditingController();
    bool confirmed = false;
    final result = await showDialog<PayrollMap>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Connect payroll provider'),
          content: SizedBox(
            width: 470,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create a Gusto Embedded payroll company for ${_account['legal_name']}. Your name, verified account email, and business name will be shared with Gusto.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: first,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Your first name',
                    ),
                    onChanged: (_) => update(() {}),
                  ),
                  TextField(
                    controller: last,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Your last name',
                    ),
                    onChanged: (_) => update(() {}),
                  ),
                  const Text(
                    'Already using Gusto? Contact payroll support for an assisted migration before creating another company.',
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: confirmed,
                    onChanged: (v) => update(() => confirmed = v == true),
                    title: const Text(
                      'I authorize this connection and confirm this business does not already have a Gusto payroll account.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  confirmed &&
                      first.text.trim().isNotEmpty &&
                      last.text.trim().isNotEmpty
                  ? () => Navigator.pop(dialog, <String, dynamic>{
                      'first_name': first.text.trim(),
                      'last_name': last.text.trim(),
                      'confirmed': true,
                      'new_company': true,
                    })
                  : null,
              child: const Text('Create connection'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), () {
      first.dispose();
      last.dispose();
    });
    if (result != null && mounted) {
      await _run(() async {
        try {
          await widget.client.post('workspaces/$account/connect', result);
        } finally {
          await _load(select: account);
        }
      });
    }
  }

  Future<void> _terms() async {
    final account = _selected;
    bool accepted = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Review payroll terms'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Review the provider agreement before entering company, employee, bank, or tax information.',
                ),
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://flows.gusto.com/terms'),
                    mode: LaunchMode.externalApplication,
                    webOnlyWindowName: '_blank',
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Read Gusto Embedded Payroll terms'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: accepted,
                  onChanged: (v) => update(() => accepted = v == true),
                  title: const Text(
                    'I have read and accept these terms on behalf of this business.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: accepted ? () => Navigator.pop(dialog, true) : null,
              child: const Text('Accept and continue'),
            ),
          ],
        ),
      ),
    );
    if (result == true && mounted) {
      await _run(() async {
        await widget.client.post('workspaces/$account/terms', {
          'accepted': true,
        });
        await _load(select: account);
      });
    }
  }

  Future<void> _refreshProvider() => _run(() async {
    final account = _selected;
    final result = await widget.client.post('workspaces/$account/refresh');
    if (mounted && account == _selected) {
      setState(() {
        _onboarding = payrollMap(result['onboarding']);
        _audit = payrollItems(result['audit']);
      });
    }
  });
  Future<void> _flow(String type) => _run(() async {
    final result = await widget.client.post('workspaces/$_selected/flows', {
      'flow_type': type,
    });
    final uri = payrollFlowUri(result), issued = DateTime.now();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('${result['title']}'),
        content: const SizedBox(
          width: 430,
          child: Text(
            'Continue in the secure payroll window. Review all amounts, employees, funding, and payment dates there before submitting. Return here and refresh setup status when finished.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open secure payroll'),
            onPressed: () async {
              try {
                widget.client.guard();
                if (DateTime.now().difference(issued) >
                    const Duration(minutes: 1)) {
                  throw const PayrollException(
                    'This launch link expired. Close this dialog and open a new payroll session.',
                  );
                }
                final opened = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                  webOnlyWindowName: '_blank',
                );
                if (!opened) {
                  throw const PayrollException(
                    'Allow a new browser window, then try opening payroll again.',
                  );
                }
                if (dialog.mounted) Navigator.pop(dialog);
              } catch (e) {
                if (dialog.mounted) Navigator.pop(dialog);
                if (mounted) setState(() => _error = '$e');
              }
            },
          ),
        ],
      ),
    );
  });
  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.client.removeListener(_accessChanged);
    widget.client.dispose();
    super.dispose();
  }

  Widget _panel(Widget child, {Color? color}) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: .55),
      ),
    ),
    child: child,
  );
  Widget _label(String title, String value, IconData icon) => SizedBox(
    width: 230,
    child: Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _action(
    String title,
    String description,
    IconData icon,
    String flow, {
    bool payroll = false,
  }) => SizedBox(
    width: 300,
    child: _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 27, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(description),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: !_busy && _usable ? () => _flow(flow) : null,
            icon: Icon(
              payroll ? Icons.arrow_forward : Icons.open_in_new,
              size: 18,
            ),
            label: Text(payroll ? 'Review payroll' : 'Open'),
          ),
        ],
      ),
    ),
  );
  String _eventLabel(String action) {
    if (action.startsWith('secure_session_opened:')) {
      return 'Secure session opened · ${action.split(':').last.replaceAll('_', ' ')}';
    }
    return switch (action) {
      'workspace_created' => 'US payroll workspace created',
      'provider_connection_started' => 'Provider connection requested',
      'provider_connected' => 'Payroll provider connected',
      'provider_connection_needs_review' => 'Provider connection needs review',
      'provider_terms_accepted' => 'Provider terms accepted',
      _ => 'Workspace updated',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), denied = !widget.client.available;
    final status = switch (_account['status']) {
      'connected' =>
        _account['terms_accepted'] == true ? 'Connected' : 'Terms required',
      'connecting' || 'connection_review' => 'Review needed',
      _ => 'Not connected',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('KORLIX Payroll'),
        actions: [
          IconButton(
            tooltip: 'Refresh workspace',
            onPressed: _busy || denied ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: denied
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 48),
                    const SizedBox(height: 20),
                    Text(
                      'Enterprise business access required',
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Sign in with a verified, active Enterprise business account to manage payroll.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : _loading && _accounts.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SelectionArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            const Chip(
                              avatar: Icon(
                                Icons.verified_user_outlined,
                                size: 16,
                              ),
                              label: Text('ENTERPRISE'),
                            ),
                            const Chip(label: Text('UNITED STATES · USD')),
                            if (_provider['environment'] == 'demo')
                              const Chip(
                                label: Text('DEMO · NO REAL PAYMENTS'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Your people. Paid with confidence.',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Manage US payroll, employee onboarding, direct deposit, and payroll tax workflows from one business workspace.',
                        ),
                        const SizedBox(height: 28),
                        if (_error != null) ...[
                          _panel(
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: theme.colorScheme.error,
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(_error!)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                        if (_provider['ready'] != true ||
                            _provider['environment'] == 'demo') ...[
                          _panel(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _provider['environment'] == 'demo' &&
                                          _provider['ready'] == true
                                      ? 'Demo payroll environment'
                                      : 'Prepare now. Activate payroll next.',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_provider['message'] ?? 'Provider status is unavailable. Refresh to try again.'}',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (_accounts.isNotEmpty)
                              SizedBox(
                                width: 350,
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey(_selected),
                                  initialValue: _selected,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Payroll business',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: _accounts
                                      .map(
                                        (a) => DropdownMenuItem(
                                          value: '${a['id']}',
                                          child: Text(
                                            '${a['legal_name']}',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _busy
                                      ? null
                                      : (v) {
                                          setState(() {
                                            _selected = v;
                                            _onboarding = {};
                                          });
                                          unawaited(_load(select: v));
                                        },
                                ),
                              ),
                            FilledButton.icon(
                              onPressed: _busy || _loading ? null : _create,
                              icon: const Icon(Icons.add),
                              label: Text(
                                _businesses.isEmpty
                                    ? 'Add a business'
                                    : 'New payroll workspace',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        if (_busy || _loading) ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: 16),
                        ],
                        if (_accounts.isEmpty)
                          _panel(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.account_balance_outlined,
                                  size: 42,
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Start with your US business',
                                  style: theme.textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Add your business in Bookkeeping, then create its payroll workspace. Only the Enterprise business owner can access payroll.',
                                ),
                                const SizedBox(height: 24),
                                const Text(
                                  '1. Create your workspace     2. Complete company setup     3. Review and run payroll',
                                ),
                              ],
                            ),
                          )
                        else ...[
                          _panel(
                            Wrap(
                              spacing: 35,
                              runSpacing: 24,
                              children: [
                                _label(
                                  'Provider connection',
                                  status,
                                  Icons.link,
                                ),
                                _label(
                                  'Company onboarding',
                                  _onboarding['onboarding_completed'] == true
                                      ? 'Complete'
                                      : 'Review setup',
                                  Icons.fact_check_outlined,
                                ),
                                _label(
                                  'Access',
                                  'Enterprise owner',
                                  Icons.shield_outlined,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (_account['needs_attention'] == true) ...[
                            _panel(
                              const Text(
                                'This connection needs payroll support review. To prevent duplicate companies or repeated credential changes, creating another connection is paused.',
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                          if (_connected &&
                              _account['environment'] !=
                                  _provider['environment']) ...[
                            _panel(
                              const Text(
                                'This workspace belongs to a different payroll environment. Contact payroll support before continuing.',
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                          if (!_connected && _account['status'] == 'draft') ...[
                            _panel(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Connect your payroll company',
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Gusto handles secure employee and bank details, payroll calculations, payments, and tax workflows. No payroll is submitted by connecting.',
                                  ),
                                  const SizedBox(height: 20),
                                  FilledButton.icon(
                                    onPressed:
                                        !_busy && _provider['ready'] == true
                                        ? _connect
                                        : null,
                                    icon: const Icon(Icons.link),
                                    label: const Text(
                                      'Connect payroll provider',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                          if (_connected &&
                              _account['terms_accepted'] != true) ...[
                            _panel(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Review your provider agreement',
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                    onPressed:
                                        _busy || _provider['ready'] != true
                                        ? null
                                        : _terms,
                                    child: const Text(
                                      'Review and accept terms',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                          _panel(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Company setup',
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Complete business addresses, federal and state tax details, funding, employee onboarding, pay schedules, and signed documents.',
                                ),
                                const SizedBox(height: 18),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: !_busy && _usable
                                          ? () => _flow('company_onboarding')
                                          : null,
                                      icon: const Icon(Icons.arrow_forward),
                                      label: const Text('Continue setup'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: !_busy && _usable
                                          ? _refreshProvider
                                          : null,
                                      icon: const Icon(Icons.sync),
                                      label: const Text('Refresh setup status'),
                                    ),
                                  ],
                                ),
                                for (final step in payrollItems(
                                  _onboarding['steps'],
                                ))
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      step['completed'] == true
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                    ),
                                    title: Text('${step['title']}'),
                                    trailing: Text(
                                      step['completed'] == true
                                          ? 'Complete'
                                          : step['required'] == true
                                          ? 'Required'
                                          : 'Optional',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'Payroll operations',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              _action(
                                'Run payroll',
                                'Review hours, earnings, deductions, taxes, and payment dates before submitting.',
                                Icons.payments_outlined,
                                'run_payroll',
                                payroll: true,
                              ),
                              _action(
                                'Employees',
                                'Manage employee onboarding, compensation, and employment changes.',
                                Icons.badge_outlined,
                                'employee_management',
                              ),
                              _action(
                                'Contractors',
                                'Manage contractor records and payment setup.',
                                Icons.work_outline,
                                'contractor_management',
                              ),
                              _action(
                                'Contractor payments',
                                'Review contractor payments and their funding details.',
                                Icons.receipt_long_outlined,
                                'contractor_payments',
                                payroll: true,
                              ),
                              _action(
                                'Off-cycle payroll',
                                'Prepare additional payroll outside the regular schedule.',
                                Icons.event_repeat,
                                'run_off_cycle_payroll',
                                payroll: true,
                              ),
                              _action(
                                'Pay schedules',
                                'Manage pay frequency, pay periods, and check dates.',
                                Icons.calendar_month_outlined,
                                'manage_payroll_schedule',
                              ),
                              _action(
                                'Payroll history',
                                'Review historical payrolls and completed run details.',
                                Icons.history,
                                'payroll_history',
                              ),
                              _action(
                                'Tax documents',
                                'Review company details and year-end tax documents.',
                                Icons.description_outlined,
                                'eoy_company_review',
                              ),
                              _action(
                                'Payroll reports',
                                'Create payroll reports without sensitive identity fields.',
                                Icons.bar_chart,
                                'reports_no_pii',
                              ),
                              _action(
                                'Benefits',
                                'Manage company benefits and employee benefit deductions.',
                                Icons.health_and_safety_outlined,
                                'benefits',
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          _panel(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Connected business tools',
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Review approved time in Workforce and record payroll expenses in Bookkeeping. Hours and ledger entries are not automatically transferred.',
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : widget.openWorkforce,
                                      icon: const Icon(Icons.groups_outlined),
                                      label: const Text('Open Workforce'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : widget.openBookkeeping,
                                      icon: const Icon(
                                        Icons.account_balance_wallet_outlined,
                                      ),
                                      label: const Text('Open Bookkeeping'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (_audit.isNotEmpty)
                            _panel(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Workspace activity',
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 10),
                                  for (final event in _audit.take(8))
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(
                                        Icons.check_circle_outline,
                                        size: 18,
                                      ),
                                      title: Text(
                                        _eventLabel('${event['action']}'),
                                      ),
                                      subtitle: Text(
                                        '${event['created_at']}'
                                            .replaceFirst('T', ' ')
                                            .split('.')
                                            .first,
                                      ),
                                    ),
                                  const Text(
                                    'Payment and filing status is available in the secure provider workspace.',
                                  ),
                                ],
                              ),
                            ),
                        ],
                        const SizedBox(height: 28),
                        Text(
                          'Payroll services provided through Gusto Embedded Payroll. US businesses only. Availability depends on provider approval and completed onboarding.',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
