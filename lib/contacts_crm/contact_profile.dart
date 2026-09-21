import 'package:flutter/material.dart';
import 'contacts_client.dart';
import 'contacts_style.dart';

class ContactProfile extends StatelessWidget {
  const ContactProfile({
    super.key,
    required this.contact,
    required this.onEdit,
    required this.onEmail,
    required this.onCall,
    required this.onCopy,
    required this.onFavorite,
    required this.onArchive,
    this.busy = false,
    this.onClose,
  });
  final Map<String, dynamic> contact;
  final void Function(int section) onEdit;
  final VoidCallback onEmail, onCall, onFavorite, onArchive;
  final void Function(String) onCopy;
  final VoidCallback? onClose;
  final bool busy;
  Widget _datum(IconData icon, String title, String? value) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: CrmStyle.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: CrmStyle.muted, fontSize: 10),
              ),
              const SizedBox(height: 4),
              SelectableText(
                (value?.isNotEmpty ?? false) ? value! : 'Not added',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (value?.isNotEmpty ?? false)
          SizedBox(
            width: 30,
            height: 30,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: 'Copy $title',
              onPressed: () => onCopy(value!),
              icon: const Icon(
                Icons.copy_rounded,
                size: 14,
                color: CrmStyle.muted,
              ),
            ),
          ),
      ],
    ),
  );
  Widget _action(
    IconData icon,
    String title,
    String detail,
    VoidCallback? tap, {
    Color color = CrmStyle.violet,
  }) => Material(
    color: color.withValues(alpha: .055),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: .2)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: tap == null ? CrmStyle.muted : color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: CrmStyle.muted,
                      fontSize: 10,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_outward_rounded, size: 15, color: color),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final c = contact, blocked = c['do_not_contact'] == true;
    final emailReady =
        !blocked &&
        c['email'] != null &&
        ['transactional', 'marketing'].contains(c['email_permission']);
    final callReady =
        !blocked && c['phone'] != null && c['call_permission'] == 'allowed';
    final completeness = [
      'name',
      'email',
      'phone',
      'company',
    ].where((k) => (c[k] ?? '').toString().trim().isNotEmpty).length;
    return Container(
      decoration: BoxDecoration(
        color: CrmStyle.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CrmStyle.line),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: CrmSectionLabel('Contact studio')),
                IconButton(
                  tooltip: c['favorite'] == true
                      ? 'Remove favorite'
                      : 'Add favorite',
                  onPressed: busy ? null : onFavorite,
                  icon: Icon(
                    c['favorite'] == true
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 19,
                    color: c['favorite'] == true
                        ? CrmStyle.gold
                        : CrmStyle.muted,
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    tooltip: 'Close contact',
                    onPressed: onClose,
                    icon: const Icon(Icons.close, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 13),
            ContactAvatar(contact: c, size: 64),
            const SizedBox(height: 16),
            Text(
              c['name'],
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                letterSpacing: -.5,
                height: 1.2,
              ),
            ),
            if ((c['company'] ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                c['company'],
                style: const TextStyle(fontSize: 12, color: CrmStyle.muted),
              ),
            ],
            const SizedBox(height: 13),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                RelationshipBadge(c['category']),
                if (blocked)
                  const CrmBadge('Do not contact', color: CrmStyle.danger),
              ],
            ),
            _datum(Icons.alternate_email_rounded, 'Email address', c['email']),
            _datum(Icons.phone_outlined, 'Telephone', c['phone']),
            const SizedBox(height: 22),
            const Divider(height: 1),
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: CrmStyle.violet,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Nova workspace',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: CrmStyle.violet,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _action(
              Icons.mark_email_read_outlined,
              emailReady ? 'Open Nova Email' : 'Set email permission',
              emailReady
                  ? 'Create a draft or use an autonomous rule.'
                  : 'Choose how Nova may email this contact.',
              busy || blocked
                  ? null
                  : emailReady
                  ? onEmail
                  : () => onEdit(2),
            ),
            const SizedBox(height: 9),
            _action(
              Icons.phone_forwarded_outlined,
              callReady ? 'Prepare Nova call' : 'Set call permission',
              'Call briefs available · calling not activated.',
              busy || blocked
                  ? null
                  : callReady
                  ? onCall
                  : () => onEdit(2),
              color: CrmStyle.cyan,
            ),
            if (blocked)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Nova outreach is blocked for this contact.',
                  style: TextStyle(color: CrmStyle.danger, fontSize: 11),
                ),
              ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(child: CrmSectionLabel('Next follow-up')),
                TextButton(
                  onPressed: () => onEdit(1),
                  child: Text(
                    c['follow_up_on'] == null ? 'Schedule' : 'Change',
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 17,
                  color: contactDue(c) ? CrmStyle.gold : CrmStyle.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    contactDate(c['follow_up_on']),
                    style: TextStyle(
                      color: contactDue(c) ? CrmStyle.gold : CrmStyle.text,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (contactDue(c)) const CrmBadge('Due', color: CrmStyle.gold),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(child: CrmSectionLabel('Notes & context')),
                TextButton(
                  onPressed: () => onEdit(1),
                  child: const Text('Edit'),
                ),
              ],
            ),
            Text(
              (c['notes'] ?? '').isEmpty
                  ? 'Add the details that make your next conversation personal.'
                  : c['notes'],
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CrmStyle.muted,
                fontSize: 12,
                height: 1.7,
              ),
            ),
            if (((c['tags'] as List?) ?? []).isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in (c['tags'] as List).take(6))
                    CrmBadge(tag.toString(), color: CrmStyle.muted),
                ],
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Contact completeness',
                    style: TextStyle(color: CrmStyle.muted, fontSize: 10),
                  ),
                ),
                Text(
                  '${completeness * 25}%',
                  style: const TextStyle(
                    color: CrmStyle.cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: completeness / 4,
                minHeight: 4,
                backgroundColor: CrmStyle.line,
                color: CrmStyle.cyan,
              ),
            ),
            const SizedBox(height: 13),
            Text(
              'Added from ${contactLabel(c['source'] ?? 'manual')}',
              style: const TextStyle(color: CrmStyle.muted, fontSize: 10),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : () => onEdit(0),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('Edit contact'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Archive contact',
                  onPressed: busy ? null : onArchive,
                  icon: const Icon(
                    Icons.archive_outlined,
                    size: 18,
                    color: CrmStyle.muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
