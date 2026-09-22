import 'package:flutter/material.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';

class FunnelRehearsal extends StatefulWidget {
  const FunnelRehearsal({
    super.key,
    required this.client,
    required this.funnel,
    required this.document,
    required this.name,
    required this.dirty,
  });
  final FunnelClient client;
  final Map<String, dynamic> funnel, document;
  final String name;
  final bool dirty;
  @override
  State<FunnelRehearsal> createState() => _FunnelRehearsalState();
}

class _FunnelRehearsalState extends State<FunnelRehearsal> {
  String _source = 'draft', _scenario = 'valid';
  bool _busy = false, _denied = false;
  String? _error;
  Map<String, dynamic>? _result;

  Future<void> _run() async {
    if (_busy || _denied) return;
    setState(() {
      _busy = true;
      _result = null;
      _error = null;
    });
    try {
      final data = await widget.client.request(
        'POST',
        '/${widget.funnel['id']}/rehearsal',
        body: {
          'source': _source,
          'scenario': _scenario,
          'version': widget.funnel['version'],
          if (_source == 'draft') ...{
            'name': widget.name,
            'document': widget.document,
          },
        },
      );
      if (!mounted) return;
      if (data['kind'] != 'simulation' ||
          data['checks'] is! List ||
          data['tasks'] is! List ||
          data['sample'] is! Map ||
          data['performed_actions'] is! List ||
          (data['performed_actions'] as List).isNotEmpty ||
          data['delivery_tested'] != false) {
        throw const FunnelException(
          'Rehearsal could not load the result. Please try again.',
        );
      }
      setState(() => _result = data);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _denied =
              e is FunnelException && (e.status == 401 || e.status == 403);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: WfStyle.surface,
      border: Border.all(color: WfStyle.line),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  Widget _title(String title, String description) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(
        description,
        style: const TextStyle(color: WfStyle.muted, height: 1.5),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (_denied) {
      return const Text('Sign in with an Enterprise account to run rehearsal.');
    }
    final controls = _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WfBadge('SIMULATION', color: WfStyle.violet),
          const SizedBox(height: 14),
          _title(
            'Rehearse the next conversation',
            'Explore a sample inquiry using your page and saved follow-up settings.',
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            key: const ValueKey('rehearsal-source'),
            initialValue: _source,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Page to rehearse'),
            items: const [
              DropdownMenuItem(
                value: 'draft',
                child: Text('Current editor draft'),
              ),
              DropdownMenuItem(
                value: 'published',
                child: Text('Published page'),
              ),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _source = v!;
                    _result = null;
                    _error = null;
                  }),
          ),
          const SizedBox(height: 14),
          Text(
            _source == 'draft'
                ? 'Assumes this draft is published after review. ${widget.dirty ? 'Your unsaved edits are included.' : 'Uses the content in the editor.'}'
                : 'Uses the published snapshot. Newer editor changes are excluded.',
            style: const TextStyle(color: WfStyle.gold, height: 1.5),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            key: const ValueKey('rehearsal-scenario'),
            initialValue: _scenario,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Sample inquiry'),
            items: const [
              DropdownMenuItem(value: 'valid', child: Text('Complete inquiry')),
              DropdownMenuItem(
                value: 'missing_consent',
                child: Text('Response consent missing'),
              ),
              DropdownMenuItem(
                value: 'invalid_email',
                child: Text('Invalid email address'),
              ),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _scenario = v!;
                    _result = null;
                    _error = null;
                  }),
          ),
          const SizedBox(height: 20),
          Text(
            'Sample visitor: Taylor Morgan\n${_scenario == 'invalid_email' ? 'not-an-email' : 'taylor@example.com'}',
            style: const TextStyle(color: WfStyle.muted, height: 1.5),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('rehearsal-run'),
            onPressed: _busy ? null : _run,
            icon: const Icon(Icons.play_circle_outline),
            label: Text(_busy ? 'Rehearsing…' : 'Run sample'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _error!,
                style: const TextStyle(color: WfStyle.danger),
              ),
            ),
          const SizedBox(height: 18),
          const Text(
            'No inquiry, contact, task, email, call or ad is created. Rehearsal does not publish your page or change your workflow.',
            style: TextStyle(fontSize: 12, color: WfStyle.muted, height: 1.5),
          ),
        ],
      ),
    );
    final output = _result == null
        ? _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.route_outlined, color: WfStyle.cyan, size: 36),
                const SizedBox(height: 18),
                _title(
                  'See the path before launch',
                  'Run a sample to see page checks, inquiry validation, the thank-you message, and the review tasks your saved workflow would prepare.',
                ),
                const SizedBox(height: 18),
                const Text(
                  'A rehearsal previews the flow. It does not verify live form submission or message delivery.',
                  style: TextStyle(color: WfStyle.muted, height: 1.5),
                ),
              ],
            ),
          )
        : _report();
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 950) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 360, child: controls),
              const SizedBox(width: 20),
              Expanded(child: output),
            ],
          );
        }
        return Column(children: [controls, const SizedBox(height: 20), output]);
      },
    );
  }

  Widget _report() {
    final r = _result!, accepted = r['accepted_in_scenario'] == true;
    final tasks = r['tasks'] as List;
    final receipt = r['receipt'] as Map?;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(
            accepted ? 'Inquiry path preview' : 'This sample would be blocked',
            'Simulated result · saved page version ${r['saved_version']} · ${r['workflow_version'] == null ? 'follow-ups not configured' : 'workflow version ${r['workflow_version']}'}',
          ),
          const SizedBox(height: 20),
          for (final check in r['checks'] as List)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    check['status'] == 'blocked'
                        ? Icons.block
                        : check['status'] == 'scenario'
                        ? Icons.visibility_outlined
                        : Icons.check_circle_outline,
                    color: check['status'] == 'blocked'
                        ? WfStyle.gold
                        : WfStyle.cyan,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${check['title']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (check['detail'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(
                              '${check['detail']}',
                              style: const TextStyle(
                                color: WfStyle.muted,
                                height: 1.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (accepted) ...[
            const Divider(height: 26),
            const Text(
              '1 · Inquiry received',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Would appear in Leads and link to Contacts CRM. Existing contact preferences stay in effect.',
              style: TextStyle(color: WfStyle.muted, height: 1.5),
            ),
            if (receipt != null) ...[
              const SizedBox(height: 18),
              const Text(
                'Visitor’s thank-you message',
                style: TextStyle(
                  color: WfStyle.cyan,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${receipt['message']}',
                style: const TextStyle(height: 1.5),
              ),
              if ('${receipt['booking_url'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Next-step link: ${receipt['booking_url']}',
                  style: const TextStyle(color: WfStyle.muted, height: 1.5),
                ),
              ],
            ],
          ],
          const Divider(height: 32),
          Text(
            '${accepted ? '2 · ' : ''}Saved follow-up workflow',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '${r['workflow_note']}',
            style: const TextStyle(color: WfStyle.muted, height: 1.5),
          ),
          for (final task in tasks)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: WfStyle.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task['channel'] == 'email'
                        ? 'Email · awaiting review'
                        : 'Call review task',
                    style: const TextStyle(
                      color: WfStyle.cyan,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (task['channel'] == 'email') ...[
                    Text(
                      '${task['subject']}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${task['body']}',
                      style: const TextStyle(height: 1.5),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Sending still requires recipient permission, NOVA readiness and your approval.',
                      style: TextStyle(
                        color: WfStyle.muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ] else
                    const Text(
                      'The team reviews the inquiry and calling permission. This task does not place a call.',
                      style: TextStyle(color: WfStyle.muted, height: 1.5),
                    ),
                ],
              ),
            ),
          const Divider(height: 32),
          const Text(
            'Separate live checks',
            style: TextStyle(color: WfStyle.gold, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '${r['limits']}',
            style: const TextStyle(
              color: WfStyle.muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
