import 'package:flutter/material.dart';
import '../theme/korlix_action_button.dart';
import 'social_client.dart';
import 'social_design.dart';

class SocialProfileForm extends StatefulWidget {
  const SocialProfileForm({super.key, required this.client, this.profile});
  final SocialClient client;
  final SocialMap? profile;
  @override
  State<SocialProfileForm> createState() => _SocialProfileFormState();
}

class _SocialProfileFormState extends State<SocialProfileForm> {
  late final _name = TextEditingController(text: widget.profile?['name']);
  late final _handle = TextEditingController(text: widget.profile?['handle']);
  late final _bio = TextEditingController(text: widget.profile?['bio']);
  late bool _discoverable = widget.profile?['discoverable'] != false,
      _online = widget.profile?['show_online'] == true,
      _rules = widget.profile != null;
  late String _color = widget.profile?['color'] ?? 'cyan';
  bool _saving = false;
  String? _error;
  final _form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (!widget.client.available && mounted) {
      _name.clear();
      _handle.clear();
      _bio.clear();
      setState(
        () => _error = 'Your session changed. Close Social and sign in again.',
      );
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_sessionChanged);
    _name.dispose();
    _handle.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!widget.client.available ||
        !_form.currentState!.validate() ||
        !_rules) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await widget.client.post('save_profile', {
        'name': _name.text.trim(),
        'handle': _handle.text.trim().toLowerCase(),
        'bio': _bio.text.trim(),
        'color': _color,
        'discoverable': _discoverable,
        'show_online': _online,
        'accepted_rules': _rules,
      });
      if (mounted) Navigator.pop(context, socialMap(r['profile']));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.profile == null ? 'Join KORLIX Social' : 'Your Social profile',
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SocialPanel(
                  child: Column(
                    children: [
                      SocialAvatar(
                        member: {'name': _name.text, 'color': _color},
                        size: 80,
                        showStatus: false,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.profile == null
                            ? 'Make yourself at home.'
                            : 'A profile that feels like you.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Choose what other KORLIX members see. Your account email stays private.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _name,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: 'Display name'),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Add a display name'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _handle,
                  maxLength: 24,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Unique handle',
                    prefixText: '@',
                    helperText: '3–24 letters, numbers or underscores',
                  ),
                  validator: (v) =>
                      RegExp(
                        r'^[a-z0-9_]{3,24}$',
                      ).hasMatch((v ?? '').trim().toLowerCase())
                      ? null
                      : 'Use 3–24 letters, numbers or underscores',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bio,
                  maxLength: 300,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'A little about you',
                    hintText: 'Interests, ideas, and what brings you here',
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'YOUR COLOR',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in [
                      'cyan',
                      'violet',
                      'coral',
                      'mint',
                      'gold',
                      'blue',
                    ])
                      Semantics(
                        selected: _color == c,
                        child: IconButton.filledTonal(
                          tooltip: 'Choose $c',
                          style: IconButton.styleFrom(
                            backgroundColor: socialColor(c),
                            foregroundColor: const Color(0xFF112233),
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: _saving
                              ? null
                              : () => setState(() => _color = c),
                          icon: Icon(
                            _color == c
                                ? Icons.check_rounded
                                : Icons.circle_outlined,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                SocialPanel(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        title: const Text('Appear in People'),
                        subtitle: const Text(
                          'Let members discover your profile and request a follow.',
                        ),
                        value: _discoverable,
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _discoverable = v),
                      ),
                      SwitchListTile.adaptive(
                        title: const Text('Show when I am online'),
                        subtitle: const Text(
                          'Visible while you use Social. It expires shortly after you leave.',
                        ),
                        value: _online,
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _online = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your name, handle, bio and forum posts are visible to other Social members. Hiding from People does not hide your posts or existing connections. Accepted follows allow both members to message. You can remove or block a connection at any time.',
                  style: TextStyle(fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 20),
                if (widget.profile == null)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _rules,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _rules = v == true),
                    title: const Text(
                      'I agree to keep this community respectful.',
                    ),
                    subtitle: const Text(
                      'No harassment, threats, impersonation, spam or sharing someone else’s private information. Report content that breaks these rules.',
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                KorlixActionButton(
                  label: widget.profile == null
                      ? 'Create my Social profile'
                      : 'Save profile',
                  icon: Icons.check_rounded,
                  busy: _saving,
                  expand: true,
                  onPressed: _saving || !_rules ? null : _save,
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

class SocialComposeTopic extends StatefulWidget {
  const SocialComposeTopic({
    super.key,
    required this.client,
    required this.categories,
    this.category,
    this.topic,
  });
  final SocialClient client;
  final List<SocialMap> categories;
  final String? category;
  final SocialMap? topic;
  @override
  State<SocialComposeTopic> createState() => _SocialComposeTopicState();
}

class _SocialComposeTopicState extends State<SocialComposeTopic> {
  late final _title = TextEditingController(text: widget.topic?['title']);
  late final _body = TextEditingController(text: widget.topic?['body']);
  late String _category =
      widget.topic?['category'] ??
      widget.category ??
      widget.categories.first['id'];
  late final _id = widget.topic?['id'] ?? socialId();
  bool _saving = false;
  String? _error;
  final _form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (!widget.client.available && mounted) {
      _title.clear();
      _body.clear();
      setState(
        () => _error = 'Your session changed. Close Social and sign in again.',
      );
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_sessionChanged);
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (!widget.client.available || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.client
          .post(widget.topic == null ? 'create_topic' : 'edit_topic', {
            'id': _id,
            'category': _category,
            'title': _title.text.trim(),
            'body': _body.text.trim(),
          });
      if (mounted) Navigator.pop(context, _id);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.topic == null ? 'Start a conversation' : 'Edit your topic',
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Good conversations start with a good question.',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your topic will be visible to KORLIX Social members. Share ideas, welcome other perspectives and keep personal information private.',
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Forum'),
                  items: [
                    for (final c in widget.categories)
                      DropdownMenuItem(
                        value: c['id'] as String,
                        child: Text(c['name']),
                      ),
                  ],
                  onChanged: _saving || widget.topic != null
                      ? null
                      : (v) => setState(() => _category = v!),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _title,
                  maxLength: 140,
                  decoration: const InputDecoration(
                    labelText: 'Topic title',
                    hintText: 'What would you like to discuss?',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Add a title' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _body,
                  maxLength: 8000,
                  minLines: 8,
                  maxLines: 20,
                  decoration: const InputDecoration(
                    labelText: 'Your post',
                    alignLabelWithHint: true,
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Write your post' : null,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                KorlixActionButton(
                  label: widget.topic == null
                      ? 'Publish topic'
                      : 'Save changes',
                  icon: Icons.arrow_upward_rounded,
                  busy: _saving,
                  onPressed: _saving ? null : _publish,
                  expand: true,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<bool> socialReport(
  BuildContext context,
  SocialClient client,
  String kind,
  String target,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _ReportDialog(client: client, kind: kind, target: target),
    ) ??
    false;

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.client,
    required this.kind,
    required this.target,
  });
  final SocialClient client;
  final String kind, target;
  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _reason = TextEditingController(), _id = socialId();
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (!widget.client.available && mounted) {
      _reason.clear();
      setState(
        () => _error = 'Your session changed. Close Social and sign in again.',
      );
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_sessionChanged);
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!widget.client.available) return;
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Add a reason for this report.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.client.post('report', {
        'id': _id,
        'kind': widget.kind,
        'target': widget.target,
        'reason': _reason.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Report to KORLIX'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.kind == 'message'
                ? 'This message and your reason will be shared with KORLIX moderators for review.'
                : 'This content and your reason will be shared with KORLIX moderators for review.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            maxLength: 1000,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Why are you reporting this?',
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _send,
        child: Text(_saving ? 'Submitting…' : 'Submit report'),
      ),
    ],
  );
}
