import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/korlix_action_button.dart';
import '../theme/korlix_theme.dart';
import 'social_client.dart';
import 'social_design.dart';
import 'social_invite_contacts.dart';
import 'social_invite_io.dart';

class SocialInviteScreen extends StatefulWidget {
  const SocialInviteScreen({
    super.key,
    required this.client,
    required this.handle,
    this.io,
  });
  final SocialClient client;
  final String handle;
  final SocialInviteIo? io;
  @override
  State<SocialInviteScreen> createState() => _SocialInviteScreenState();
}

class _SocialInviteScreenState extends State<SocialInviteScreen> {
  late final io = widget.io ?? SocialInviteIo();
  late final message = TextEditingController(
    text: socialInvitation(widget.handle),
  );
  final search = TextEditingController();
  final contacts = <String, InviteContact>{};
  final opened = <String>{};
  bool busy = false;
  int visible = 50;
  String? status;
  bool get available => widget.client.available;
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_session);
  }

  void _session() {
    if (!available && mounted) {
      setState(() {
        contacts.clear();
        opened.clear();
        message.clear();
        search.clear();
        status = null;
      });
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_session);
    contacts.clear();
    opened.clear();
    message.dispose();
    search.dispose();
    super.dispose();
  }

  void notice(String text) {
    if (mounted && available) setState(() => status = text);
  }

  String? get messageError => message.text.trim().isEmpty
      ? 'Write an invitation first.'
      : message.text.length > 1600
      ? 'Keep the invitation under 1,600 characters.'
      : null;

  Future<void> _share(BuildContext buttonContext) async {
    if (busy || !available) return;
    if (messageError != null) {
      notice(messageError!);
      return;
    }
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => busy = true);
    try {
      final result = await io.share(message.text.trim(), origin);
      if (result == ShareResultStatus.unavailable) {
        notice(
          'Sharing may not be available here. Use Copy invitation and paste it into your preferred app.',
        );
      } else if (result == ShareResultStatus.success) {
        notice(
          'Invitation shared with your chosen app. KORLIX cannot confirm delivery.',
        );
      }
    } catch (_) {
      notice('Sharing did not open. Use Copy invitation instead.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _copy(String text, String confirmation) async {
    if (!available) return;
    try {
      await io.copy(text);
      notice(confirmation);
    } catch (_) {
      notice(
        'Copy did not work. Select the invitation text and copy it manually.',
      );
    }
  }

  Future<void> _import(bool picker) async {
    if (busy || !available) return;
    setState(() => busy = true);
    try {
      // Invoke the browser picker before any await to preserve the tap.
      final result = picker
          ? InviteImport(await io.chooseContacts(), 0, 0)
          : await io.importContacts();
      if (!mounted || !available || result == null || result.contacts.isEmpty) {
        return;
      }
      var added = 0, duplicates = result.duplicates;
      for (final c in result.contacts.where((c) => c.usable)) {
        if (contacts.containsKey(c.key)) {
          duplicates++;
          continue;
        }
        if (contacts.length >= 500) break;
        contacts[c.key] = c;
        added++;
      }
      notice(
        '$added contacts added.${duplicates > 0 ? ' $duplicates duplicates skipped.' : ''}${result.skipped > 0 ? ' ${result.skipped} entries had no usable email or phone.' : ''} Choose a person to review an invitation.',
      );
    } catch (e) {
      notice(
        e is SocialException
            ? e.message
            : 'Contacts could not be imported. Try a CSV or vCard export.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _manual() async {
    final contact = await showDialog<InviteContact>(
      context: context,
      builder: (_) => AnimatedBuilder(
        animation: widget.client,
        builder: (context, _) =>
            available ? const _ManualInviteContact() : _expired(context),
      ),
    );
    if (!mounted || !available || contact == null) return;
    if (contacts.length >= 500 && !contacts.containsKey(contact.key)) {
      notice('Clear some contacts before adding another.');
      return;
    }
    setState(() {
      contacts[contact.key] = contact;
      status = '${contact.label} added. Review their invitation when ready.';
    });
  }

  Widget _expired(BuildContext context) => AlertDialog(
    title: const Text('Your session changed'),
    content: const Text(
      'Contact details have been cleared. Close this screen and sign in again.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
  Future<void> _review(InviteContact contact) async {
    if (!available) return;
    if (messageError != null) {
      notice(messageError!);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => AnimatedBuilder(
        animation: widget.client,
        builder: (context, _) => available
            ? _ReviewInvite(
                contact: contact,
                message: message.text.trim(),
                io: io,
                isCurrent: () => available,
                onOpened: () {
                  if (mounted && available) {
                    setState(() => opened.add(contact.key));
                  }
                },
              )
            : _expired(context),
      ),
    );
  }

  Widget _button(String label, IconData icon, VoidCallback? action) =>
      KorlixActionButton(
        label: label,
        icon: icon,
        onPressed: action,
        tile: true,
        expand: true,
      );
  Widget _pair(Widget a, Widget b) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: a),
      const SizedBox(width: 12),
      Expanded(child: b),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    final filtered = contacts.values
        .where((c) => c.searchText.contains(search.text.trim().toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Invite friends & family')),
      body: SafeArea(
        child: !available
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Your session changed. Contact details have been cleared. Sign in and reopen Social.',
                  ),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      SocialPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'KORLIX  /  YOUR CIRCLE',
                              style: TextStyle(
                                color: skin.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Better with\nyour people.',
                              style: TextStyle(
                                color: skin.text,
                                fontSize: 34,
                                height: 1.08,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.8,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Bring the people you love into the conversation. Share your invitation, or choose someone from your contacts.',
                              style: TextStyle(
                                color: skin.mutedText,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 22),
                            _pair(
                              Builder(
                                builder: (ctx) => _button(
                                  'Share invitation',
                                  Icons.ios_share_rounded,
                                  busy ? null : () => _share(ctx),
                                ),
                              ),
                              _button(
                                'Copy invitation',
                                Icons.copy_all_rounded,
                                () {
                                  if (messageError != null) {
                                    notice(messageError!);
                                  } else {
                                    _copy(
                                      message.text.trim(),
                                      'Invitation copied. Paste it into a message.',
                                    );
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    socialInviteUrl,
                                    style: TextStyle(
                                      color: skin.primary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Copy join link',
                                  onPressed: () => _copy(
                                    socialInviteUrl,
                                    'Join link copied.',
                                  ),
                                  icon: const Icon(Icons.link_rounded),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SocialPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Make it personal',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              key: const Key('social-invite-message'),
                              controller: message,
                              minLines: 5,
                              maxLines: 10,
                              maxLength: 1600,
                              decoration: const InputDecoration(
                                labelText: 'Your invitation',
                                alignLabelWithHint: true,
                              ),
                              onChanged: (_) => setState(() => status = null),
                            ),
                            TextButton.icon(
                              onPressed: () => setState(
                                () => message.text = socialInvitation(
                                  widget.handle,
                                ),
                              ),
                              icon: const Icon(Icons.restart_alt_rounded),
                              label: const Text('Restore invitation'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SocialPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Invite your contacts',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Contacts stay in this screen and clear when you close it. Choose each person, review the message, then send from your own app.',
                              style: TextStyle(
                                color: skin.mutedText,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _pair(
                              _button(
                                io.canPickContacts
                                    ? 'Choose contacts'
                                    : 'Add a person',
                                io.canPickContacts
                                    ? Icons.contacts_outlined
                                    : Icons.person_add_alt_1_rounded,
                                busy
                                    ? null
                                    : io.canPickContacts
                                    ? () => _import(true)
                                    : _manual,
                              ),
                              _button(
                                'Import contacts',
                                Icons.file_upload_outlined,
                                busy ? null : () => _import(false),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'CSV or vCard (.vcf) · Up to 500 contacts · 2 MB',
                              style: TextStyle(
                                color: skin.mutedText,
                                fontSize: 12,
                              ),
                            ),
                            if (!io.canPickContacts)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'This browser does not offer direct contact access. Import an export, add a person, or use Share invitation.',
                                  style: TextStyle(
                                    color: skin.mutedText,
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            if (io.canPickContacts)
                              TextButton.icon(
                                onPressed: busy ? null : _manual,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Add a person manually'),
                              ),
                            if (busy)
                              const Padding(
                                padding: EdgeInsets.only(top: 16),
                                child: LinearProgressIndicator(),
                              ),
                          ],
                        ),
                      ),
                      if (status != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              status!,
                              style: TextStyle(
                                color: skin.primary,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                      if (contacts.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${contacts.length} contacts',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                contacts.clear();
                                opened.clear();
                                search.clear();
                                status = 'Imported contacts cleared.';
                              }),
                              child: const Text('Clear all'),
                            ),
                          ],
                        ),
                        TextField(
                          controller: search,
                          onChanged: (_) => setState(() => visible = 50),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search_rounded),
                            hintText: 'Search name, email or phone',
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (filtered.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(18),
                            child: Text('No contacts match your search.'),
                          ),
                        for (final c in filtered.take(visible))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SocialPanel(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    c.emails.isNotEmpty
                                        ? c.emails.first
                                        : c.phones.first,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: skin.mutedText),
                                  ),
                                  Wrap(
                                    spacing: 12,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () => _review(c),
                                        icon: const Icon(Icons.send_outlined),
                                        label: const Text('Review invitation'),
                                      ),
                                      IconButton(
                                        tooltip: 'Remove ${c.label}',
                                        onPressed: () => setState(() {
                                          contacts.remove(c.key);
                                          opened.remove(c.key);
                                        }),
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                    ],
                                  ),
                                  if (opened.contains(c.key))
                                    Text(
                                      'Draft opened · delivery not confirmed',
                                      style: TextStyle(
                                        color: skin.mutedText,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        if (filtered.length > visible)
                          TextButton(
                            onPressed: () => setState(() => visible += 50),
                            child: const Text('Show more contacts'),
                          ),
                      ],
                      const SizedBox(height: 22),
                      Text(
                        'Joining does not automatically follow anyone. Accepted follow requests open private messages and calls.',
                        style: TextStyle(
                          color: skin.mutedText,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _ManualInviteContact extends StatefulWidget {
  const _ManualInviteContact();
  @override
  State<_ManualInviteContact> createState() => _ManualInviteContactState();
}

class _ManualInviteContactState extends State<_ManualInviteContact> {
  final name = TextEditingController(),
      email = TextEditingController(),
      phone = TextEditingController();
  String? error;
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    super.dispose();
  }

  void _add() {
    final c = InviteContact(
      name: name.text,
      emails: [email.text],
      phones: [phone.text],
    );
    if (!c.usable ||
        email.text.trim().isNotEmpty && inviteEmail(email.text) == null ||
        phone.text.trim().isNotEmpty && invitePhone(phone.text) == null) {
      setState(
        () => error =
            'Enter a valid email address or phone number. Add a country code for international numbers.',
      );
      return;
    }
    Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Add a person'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            maxLength: 254,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            maxLength: 30,
            decoration: const InputDecoration(
              labelText: 'Phone',
              hintText: '+1 555 123 4567',
            ),
          ),
          if (error != null) Text(error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(onPressed: _add, child: const Text('Add contact')),
    ],
  );
}

class _ReviewInvite extends StatefulWidget {
  const _ReviewInvite({
    required this.contact,
    required this.message,
    required this.io,
    required this.isCurrent,
    required this.onOpened,
  });
  final InviteContact contact;
  final String message;
  final SocialInviteIo io;
  final bool Function() isCurrent;
  final VoidCallback onOpened;
  @override
  State<_ReviewInvite> createState() => _ReviewInviteState();
}

class _ReviewInviteState extends State<_ReviewInvite> {
  late final targets = [
    for (final e in widget.contact.emails) (true, e),
    for (final p in widget.contact.phones) (false, p),
  ];
  int selected = 0;
  bool busy = false;
  String? status;
  Future<void> _open() async {
    if (busy || !widget.isCurrent()) return;
    setState(() => busy = true);
    try {
      final target = targets[selected];
      final opened = await widget.io.openDraft(
        inviteDraftUri(
          recipient: target.$2,
          email: target.$1,
          message: widget.message,
        ),
      );
      if (!mounted || !widget.isCurrent()) return;
      if (opened) widget.onOpened();
      setState(
        () => status = opened
            ? 'Draft opened. Review and send in your app. If the message is blank, use Copy invitation and paste it there.'
            : 'No compatible app opened. Copy the invitation and paste it into your messaging app.',
      );
    } catch (_) {
      if (mounted && widget.isCurrent()) {
        setState(
          () => status = 'The draft did not open. Copy the invitation instead.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: const EdgeInsets.all(16),
    title: const Text('Review invitation'),
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'To: ${widget.contact.label}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < targets.length; i++)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: selected == i,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: busy ? null : (_) => setState(() => selected = i),
              title: Text(targets[i].$2),
              subtitle: Text(
                targets[i].$1 ? 'Email draft' : 'Text message draft',
              ),
            ),
          const Divider(height: 24),
          SelectableText(widget.message, style: const TextStyle(height: 1.5)),
          const SizedBox(height: 12),
          const Text(
            'Your app opens a draft for this person. You press Send there.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(status!),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      TextButton(
        onPressed: busy
            ? null
            : () async {
                try {
                  await widget.io.copy(widget.message);
                  if (mounted && widget.isCurrent()) {
                    setState(() => status = 'Invitation copied.');
                  }
                } catch (_) {
                  if (mounted) {
                    setState(
                      () => status =
                          'Select the invitation text to copy it manually.',
                    );
                  }
                }
              },
        child: const Text('Copy invitation'),
      ),
      TextButton(
        onPressed: busy ? null : _open,
        child: Text(
          targets[selected].$1 ? 'Open email draft' : 'Open text draft',
        ),
      ),
    ],
  );
}
