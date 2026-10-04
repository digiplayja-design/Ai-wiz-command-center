import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_studio_client.dart';

Map<String, dynamic> portalMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Map<String, dynamic>> portalRows(Object? value) => value is List
    ? value.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
    : [];
String portalText(Object? value) => value?.toString() ?? '';
String portalRole(Object? value) => switch (value) {
  'owner' => 'Owner',
  'staff' => 'Staff',
  _ => 'Customer',
};
String? validatePortalForm(String name, String description, String payment) {
  if (name.trim().length < 3 || name.trim().length > 80) {
    return 'Enter a portal name with 3–80 characters.';
  }
  if (description.trim().length > 1000) {
    return 'Keep the welcome message to 1,000 characters.';
  }
  if (payment.trim().isNotEmpty) {
    final uri = Uri.tryParse(payment.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        payment.length > 2000) {
      return 'Use a complete, secure checkout link starting with https://.';
    }
  }
  return null;
}

/// Owner setup, member directory and signed-in invitation entry.
/// Portal request screens are hosted by the backend and opened with a short-lived
/// launch link; only the public landing link is offered for sharing.
class AppPortalScreen extends StatefulWidget {
  const AppPortalScreen({
    super.key,
    required this.client,
    this.project,
    this.portalId,
    this.inviteToken,
    this.disposeClient = true,
    this.openUrl,
    this.copyText,
  });
  final AppStudioClient client;
  final Map<String, dynamic>? project;
  final String? portalId, inviteToken;
  final bool disposeClient;
  final Future<bool> Function(Uri)? openUrl;
  final Future<void> Function(String)? copyText;
  @override
  State<AppPortalScreen> createState() => _AppPortalScreenState();
}

class _AppPortalScreenState extends State<AppPortalScreen> {
  final _name = TextEditingController(),
      _description = TextEditingController(),
      _payment = TextEditingController(),
      _email = TextEditingController(),
      _code = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _portals = [], _members = [], _invites = [];
  Map<String, dynamic>? _project, _portal, _newInvite;
  String? _portalId, _error, _notice, _publicUrl;
  String _tab = 'setup', _role = 'customer', _baseline = '';
  bool _loading = true,
      _busy = false,
      _locked = false,
      _allowPop = false,
      _invitationCopied = false;
  BuildContext? _dialogContext;
  bool get _managing => _project != null;
  bool get _blocked => _busy || _locked || _loading;
  bool get _published => _portal?['published'] == true;
  String get _form =>
      '${_name.text}\u0000${_description.text}\u0000${_payment.text}';
  bool get _dirty => _managing && _form != _baseline;
  ColorScheme get colors => Theme.of(context).colorScheme;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _portalId = widget.portalId;
    _code.text = widget.inviteToken ?? '';
    widget.client.addAccessDeniedListener(_lock);
    if (widget.client.sessionChanged) {
      _locked = true;
      _loading = false;
      _error = 'Your sign-in changed. Reopen App Studio after signing in.';
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    widget.client.removeAccessDeniedListener(_lock);
    if (widget.disposeClient) widget.client.dispose();
    for (final c in [_name, _description, _payment, _email, _code]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _lock() {
    if (!mounted || _locked) return;
    final dialog = _dialogContext;
    if (dialog != null && dialog.mounted) Navigator.pop(dialog, false);
    setState(() {
      _locked = true;
      _portal = null;
      _project = null;
      _newInvite = null;
      _publicUrl = null;
      _portals = [];
      _members = [];
      _invites = [];
      for (final c in [_name, _description, _payment, _email, _code]) {
        c.clear();
      }
      _error = 'Your sign-in changed. Reopen App Studio after signing in.';
      _notice = null;
    });
  }

  void _acceptSetup(Map<String, dynamic> result) {
    _portal = result['portal'] == null ? null : portalMap(result['portal']);
    _portalId = _portal?['id']?.toString();
    _members = portalRows(result['members']);
    _invites = portalRows(result['invites']);
    _publicUrl = result['url']?.toString();
    _name.text =
        _portal?['name']?.toString() ?? _project?['name']?.toString() ?? '';
    _description.text =
        _portal?['description']?.toString() ??
        portalMap(_project?['spec'])['tagline']?.toString() ??
        '';
    _payment.text = _portal?['payment_url']?.toString() ?? '';
    _baseline = _form;
  }

  Future<void> _load() async {
    try {
      if (_managing) {
        final result = await widget.client.portalSetup(_project!['id']);
        if (mounted && !_locked) setState(() => _acceptSetup(result));
      } else if (_portalId != null && _code.text.isEmpty) {
        final result = await widget.client.portal(_portalId!);
        if (mounted && !_locked) {
          setState(() {
            _portal = portalMap(result['portal']);
            _publicUrl = result['url']?.toString();
          });
        }
      } else if (_portalId == null) {
        final rows = await widget.client.portals();
        if (mounted && !_locked) setState(() => _portals = rows);
      }
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _work(Future<void> Function() action) async {
    if (_busy || _locked) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String label) async {
    if (_locked || !mounted || _dialogContext != null) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        _dialogContext = ctx;
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(label),
            ),
          ],
        );
      },
    );
    _dialogContext = null;
    return result == true && mounted && !_locked;
  }

  Future<void> _refresh() async {
    if (_dirty &&
        !await _confirm(
          'Refresh portal?',
          'Refreshing will replace the unsaved changes on this screen.',
          'Refresh',
        )) {
      return;
    }
    if (!mounted || _locked) return;
    await _work(_load);
  }

  Future<void> _leave() async {
    if (_allowPop) return;
    if ((_dirty ||
            _email.text.trim().isNotEmpty ||
            _newInvite != null && !_invitationCopied) &&
        !await _confirm(
          'Leave portal setup?',
          _newInvite != null && !_invitationCopied
              ? 'Your new invitation code has not been copied. It will not be shown again after you leave. Unsaved entries will also be discarded.'
              : 'Your unsaved entries will be discarded.',
          'Leave',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.pop(context);
  }

  Future<void> _save(bool published) async {
    final error = validatePortalForm(
      _name.text,
      _description.text,
      _payment.text,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    if (published &&
        !await _confirm(
          _published
              ? 'Update the live portal?'
              : 'Publish this customer portal?',
          'This publishes your saved design’s name, color and theme as a customer portal. '
          'People you invite can sign in, submit requests, exchange replies and attach files. '
          'Only invited members can view requests. Preview records are not copied.',
          _published ? 'Update live portal' : 'Publish portal',
        )) {
      return;
    }
    if (!published &&
        _published &&
        !await _confirm(
          'Unpublish this portal?',
          'Customers and staff will lose portal access until you publish it again. Saved requests and memberships remain.',
          'Unpublish',
        )) {
      return;
    }
    if (!mounted || _locked) return;
    await _work(() async {
      await widget.client.savePortal(_project!['id'], {
        'version': _portal?['version'] ?? 0,
        'project_version': _project!['version'],
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'payment_url': _payment.text.trim(),
        'published': published,
        'confirmed': true,
      });
      if (!mounted || _locked) return;
      await _load();
      if (mounted && !_locked && _error == null) {
        setState(
          () => _notice = published
              ? 'Your customer portal is live. Invite customers and staff when you are ready.'
              : 'Portal saved as a draft. Member access is off.',
        );
      }
    });
  }

  Future<void> _invite() async {
    final email = _email.text.trim().toLowerCase();
    if (!RegExp(r'^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$').hasMatch(email) ||
        email.length > 254) {
      setState(() => _error = 'Enter the email address they use for KORLIX.');
      return;
    }
    if (!await _confirm(
      'Invite ${portalRole(_role).toLowerCase()}?',
      '$email can join using this invitation after verifying that email in KORLIX. '
          '${_role == 'staff' ? 'Staff can view all portal requests, reply and change their status.' : 'Customers can see only their own requests, replies and files.'} '
          'You will receive a link to share. No email is sent automatically.',
      'Create invitation',
    )) {
      return;
    }
    if (!mounted || _locked) return;
    await _work(() async {
      final result = await widget.client.invitePortal(_portal!['id'], {
        'email': email,
        'role': _role,
        'expires_days': 7,
        'confirmed': true,
      });
      if (!mounted || _locked) return;
      setState(() {
        _newInvite = result;
        _invitationCopied = false;
        _email.clear();
      });
      final setup = await widget.client.portalSetup(_project!['id']);
      if (mounted && !_locked) {
        setState(() {
          _members = portalRows(setup['members']);
          _invites = portalRows(setup['invites']);
          _notice =
              'Invitation created. Copy the link now; it is only shown once.';
        });
      }
    });
  }

  Future<void> _revoke(Map<String, dynamic> row, bool member) async {
    if (!await _confirm(
      member ? 'Remove this member?' : 'Revoke this invitation?',
      '${portalText(row['email'])} ${member ? 'will lose access to this portal. Existing requests remain saved.' : 'will no longer be able to use this invitation.'}',
      member ? 'Remove access' : 'Revoke',
    )) {
      return;
    }
    if (!mounted || _locked) return;
    await _work(() async {
      if (member) {
        await widget.client.removePortalMember(_portal!['id'], row['user_id']);
      } else {
        await widget.client.revokePortalInvite(_portal!['id'], row['id']);
      }
      if (!mounted || _locked) return;
      final setup = await widget.client.portalSetup(_project!['id']);
      if (mounted && !_locked) {
        setState(() {
          _members = portalRows(setup['members']);
          _invites = portalRows(setup['invites']);
          if (!member && portalMap(_newInvite?['invite'])['id'] == row['id']) {
            _newInvite = null;
          }
          _notice = member ? 'Member access removed.' : 'Invitation revoked.';
        });
      }
    });
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.isEmpty || code.length > 300) {
      setState(() => _error = 'Enter the invitation code you received.');
      return;
    }
    await _work(() async {
      final result = await widget.client.joinPortal(code, portalId: _portalId);
      if (!mounted || _locked) return;
      final portal = portalMap(result['portal']);
      if (_portalId != null && portal['id'] != _portalId) {
        throw const AppStudioException(
          'This invitation belongs to a different portal. Open My portals to continue.',
        );
      }
      setState(() {
        _portal = portal;
        _portalId = portal['id'];
        _publicUrl = result['url']?.toString();
        _code.clear();
        _notice = 'You joined the portal. Open it below to get started.';
      });
    });
  }

  Future<void> _open(String id) => _work(() async {
    final url = await widget.client.launchPortal(id);
    if (!mounted || _locked) return;
    final opened =
        await (widget.openUrl?.call(url) ??
            launchUrl(url, webOnlyWindowName: '_self'));
    if (!opened) {
      throw const AppStudioException(
        'The portal could not open. Please try again.',
      );
    }
  });

  Future<void> _copy(String value) => _work(() async {
    if (widget.copyText != null) {
      await widget.copyText!(value);
    } else {
      await Clipboard.setData(ClipboardData(text: value));
    }
    if (mounted && !_locked) {
      setState(() {
        if (_newInvite != null &&
            (value == _newInvite!['code'] ||
                value == _newInvite!['join_url'])) {
          _invitationCopied = true;
        }
        _notice = 'Copied. Share it with the intended person.';
      });
    }
  });

  Future<void> _manageProject(String id) => _work(() async {
    final result = await widget.client.open(id);
    if (!mounted || _locked) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppPortalScreen(
          client: widget.client,
          project: portalMap(result['project']),
          disposeClient: false,
          openUrl: widget.openUrl,
          copyText: widget.copyText,
        ),
      ),
    );
    if (mounted && !_locked) await _load();
  });

  Widget _card(Widget child, {Color? tint}) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Material(
      color: tint ?? colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    ),
  );
  Widget _heading(String title, String description) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(description),
      const SizedBox(height: 18),
    ],
  );
  Widget _field(
    TextEditingController controller,
    String label, {
    int max = 80,
    int lines = 1,
    String? hint,
  }) => TextField(
    controller: controller,
    enabled: !_blocked,
    maxLength: max,
    minLines: lines,
    maxLines: lines,
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
  Widget _button(
    String label,
    IconData icon,
    VoidCallback? action, {
    bool primary = false,
  }) => primary
      ? FilledButton.icon(
          onPressed: _blocked ? null : action,
          icon: Icon(icon),
          label: Text(label),
        )
      : OutlinedButton.icon(
          onPressed: _blocked ? null : action,
          icon: Icon(icon),
          label: Text(label),
        );
  Widget _banner(String text, bool error) => _card(
    Text(
      text,
      style: TextStyle(
        color: error ? colors.onErrorContainer : colors.onPrimaryContainer,
      ),
    ),
    tint: error ? colors.errorContainer : colors.primaryContainer,
  );
  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      label,
      style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w700),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(_managing ? 'Customer portal' : 'My portals'),
        actions: [
          IconButton(
            tooltip: 'Refresh portals',
            onPressed: _blocked ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) _banner(_error!, true),
                    if (_notice != null) _banner(_notice!, false),
                    if (_loading || _busy) const LinearProgressIndicator(),
                    if (_loading || _busy) const SizedBox(height: 18),
                    if (!_locked && !_loading) ...[
                      if (_managing)
                        ..._manageView()
                      else if (_portalId != null)
                        ..._memberView()
                      else
                        ..._directoryView(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  List<Widget> _manageView() => [
    _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.public, size: 36, color: Color(0xff149f93)),
          const SizedBox(height: 12),
          _heading(
            'A real home for your customers',
            'Publish a private customer portal with shared requests, replies, status updates and file attachments. Everyone signs in with their KORLIX account.',
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _badge(
                _published ? 'Live portal' : 'Draft · access off',
                _published ? Colors.teal : Colors.orange,
              ),
              _badge('Saved design v${_project!['version']}', Colors.indigo),
              if (_portal != null)
                _badge('Portal revision ${_portal!['version']}', Colors.purple),
            ],
          ),
          if (_published) ...[
            const SizedBox(height: 12),
            Text(
              'Live design: v${_portal!['project_version']}. New App Studio builds stay private until you update this portal.',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _button(
                  'Open portal',
                  Icons.open_in_new,
                  () => _open(_portal!['id']),
                  primary: true,
                ),
                if (_safePublicUrl != null)
                  _button(
                    'Copy public link',
                    Icons.link,
                    () => _copy(_safePublicUrl!),
                  ),
              ],
            ),
          ],
        ],
      ),
      tint: colors.primaryContainer.withValues(alpha: .38),
    ),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Setup & publish'),
          selected: _tab == 'setup',
          onSelected: _blocked ? null : (_) => setState(() => _tab = 'setup'),
        ),
        ChoiceChip(
          label: const Text('People & invitations'),
          selected: _tab == 'people',
          onSelected: _blocked || _portal == null
              ? null
              : (_) => setState(() => _tab = 'people'),
        ),
      ],
    ),
    const SizedBox(height: 18),
    if (_tab == 'setup') ..._setupView() else ..._peopleView(),
  ];

  String? get _safePublicUrl {
    final url = Uri.tryParse(_publicUrl ?? '');
    if (url == null ||
        url.scheme != 'https' ||
        url.userInfo.isNotEmpty ||
        url.origin != Uri.parse(widget.client.backendBaseUrl).origin ||
        url.hasQuery ||
        url.hasFragment ||
        !url.path.endsWith('/portals/${_portal?['id']}')) {
      return null;
    }
    return url.toString();
  }

  List<Widget> _setupView() => [
    _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            '1. Make it yours',
            'Your portal uses the color and theme of this saved App Studio design.',
          ),
          _field(_name, 'Portal name'),
          const SizedBox(height: 10),
          _field(_description, 'Welcome message', max: 1000, lines: 3),
          const SizedBox(height: 10),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Optional checkout link'),
            subtitle: const Text('Use your own payment provider'),
            children: [
              _field(
                _payment,
                'Secure checkout URL',
                max: 2000,
                hint: 'https://…',
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'Customers leave the portal to pay through your provider. KORLIX does not collect payments or confirm whether a request has been paid.',
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            '2. Review what goes live',
            'This publishes one complete customer portal, using your saved design’s branding.',
          ),
          _check(
            'Customers submit requests and see only their own information.',
          ),
          _check(
            'Staff can work across requests, reply, attach files and update status.',
          ),
          _check(
            'Invitations require the intended person’s verified KORLIX email.',
          ),
          _check(
            'Files remain private to the request’s customer and your team.',
          ),
          const SizedBox(height: 10),
          const Text(
            'Prototype screens and sample records remain in your preview and ZIP export. They are not converted into custom live features or imported into this portal.',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _button(
                _published ? 'Update live portal' : 'Publish portal',
                Icons.rocket_launch_outlined,
                () => _save(true),
                primary: true,
              ),
              _button(
                _published ? 'Unpublish portal' : 'Save draft',
                _published ? Icons.pause_circle_outline : Icons.save_outlined,
                () => _save(false),
              ),
            ],
          ),
          if (_dirty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('You have unsaved setup changes.'),
            ),
        ],
      ),
    ),
  ];
  Widget _check(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle, color: Color(0xff149f93), size: 22),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );

  List<Widget> _peopleView() => [
    _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            'Invite a customer or teammate',
            'Create a link for one person. It expires after seven days and can be accepted once.',
          ),
          _field(_email, 'Their KORLIX email', max: 254),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final role in ['customer', 'staff'])
                ChoiceChip(
                  label: Text(portalRole(role)),
                  selected: _role == role,
                  onSelected: _blocked
                      ? null
                      : (_) => setState(() => _role = role),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _role == 'staff'
                ? 'Staff can view and work on every customer request in this portal.'
                : 'Customers see only their own requests, replies and files.',
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: _button(
              'Create invitation',
              Icons.person_add_alt_1,
              _invite,
              primary: true,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'No email is sent automatically. You choose how to share the invitation.',
          ),
        ],
      ),
    ),
    if (_newInvite != null)
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(
              'Your invitation is ready',
              'Copy this private invitation before leaving. You cannot reveal the code again.',
            ),
            Text(
              'For ${portalMap(_newInvite!['invite'])['email']} · ${portalRole(portalMap(_newInvite!['invite'])['role'])}',
            ),
            const SizedBox(height: 12),
            SelectableText(portalText(_newInvite!['code'])),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _button(
                  'Copy invitation link',
                  Icons.link,
                  () => _copy(portalText(_newInvite!['join_url'])),
                  primary: true,
                ),
                _button(
                  'Copy code',
                  Icons.copy,
                  () => _copy(portalText(_newInvite!['code'])),
                ),
              ],
            ),
          ],
        ),
        tint: colors.tertiaryContainer.withValues(alpha: .5),
      ),
    _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading('Members', 'You control who can access your portal.'),
          if (_members.isEmpty)
            const Text(
              'You are the owner. Invite your first customer or teammate above.',
            ),
          for (final member in _members) _personRow(member, member: true),
        ],
      ),
    ),
    _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading('Invitations', 'Revoke any unused invitation here.'),
          if (_invites.isEmpty) const Text('No invitations yet.'),
          for (final invite in _invites) _personRow(invite, member: false),
        ],
      ),
    ),
  ];

  Widget _personRow(Map<String, dynamic> row, {required bool member}) {
    final expired =
        DateTime.tryParse(
          portalText(row['expires_at']),
        )?.isBefore(DateTime.now()) ??
        false;
    final active =
        row['revoked_at'] == null && row['used_at'] == null && !expired;
    final status = member
        ? portalRole(row['role'])
        : row['revoked_at'] != null
        ? 'Revoked'
        : row['used_at'] != null
        ? 'Accepted'
        : expired
        ? 'Expired'
        : 'Waiting · ${portalRole(row['role'])}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            portalText(row['email']),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(status),
          if (member && row['role'] != 'owner' || !member && active)
            TextButton(
              onPressed: _blocked ? null : () => _revoke(row, member),
              child: Text(member ? 'Remove access' : 'Revoke invitation'),
            ),
        ],
      ),
    );
  }

  List<Widget> _directoryView() => [
    _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            'Your customer portals',
            'Work with businesses and customers through your KORLIX account.',
          ),
          if (_portals.isEmpty)
            const Text(
              'No portals yet. Publish a customer portal from a saved App Studio project, or join one with an invitation.',
            ),
          for (final portal in _portals)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    portalText(portal['name']),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${portalRole(portal['role'])} · ${portal['published'] == true ? 'Live' : 'Unpublished'}',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (portal['published'] == true)
                        _button(
                          'Open portal',
                          Icons.open_in_new,
                          () => _open(portal['id']),
                          primary: true,
                        ),
                      if (portal['role'] == 'owner')
                        _button(
                          'Manage portal',
                          Icons.settings_outlined,
                          () => _manageProject(portal['project_id']),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
    _joinCard(),
  ];

  Widget _joinCard() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Have an invitation?',
          'Use the KORLIX account with the email address your invitation was sent to. That email must be verified.',
        ),
        _field(_code, 'Invitation code', max: 300),
        const SizedBox(height: 10),
        const Text(
          'Accepting adds your account to this portal. The business owner will see your account email. Customers see their own requests; staff can work across customer requests.',
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: _button(
            'Accept invitation',
            Icons.login,
            _join,
            primary: true,
          ),
        ),
      ],
    ),
  );

  List<Widget> _memberView() => [
    if (_code.text.isNotEmpty || _portal == null) _joinCard(),
    if (_portal != null)
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(
              portalText(_portal!['name']),
              portalText(_portal!['description']),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _badge(portalRole(_portal!['role']), Colors.indigo),
                _badge(
                  _published ? 'Live' : 'Unpublished',
                  _published ? Colors.teal : Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              _published
                  ? 'Open your secure portal to submit requests, exchange replies and share files.'
                  : 'This portal is currently unpublished. The business owner can make it available again.',
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (_published)
                  _button(
                    'Open secure portal',
                    Icons.open_in_new,
                    () => _open(_portal!['id']),
                    primary: true,
                  ),
                if (_portal!['role'] == 'owner')
                  _button(
                    'Manage portal',
                    Icons.settings_outlined,
                    () => _manageProject(_portal!['project_id']),
                  ),
              ],
            ),
          ],
        ),
      ),
  ];
}
