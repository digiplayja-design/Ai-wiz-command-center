import 'dart:convert';
import 'dart:typed_data';
import 'social_client.dart';

const socialInviteUrl = 'https://www.korlixdeveloper.com/app/';
String socialInvitation(String handle) =>
    'Join me on KORLIX Social! We can chat, call, share photos and join conversations about our interests.\n\n$socialInviteUrl\n\nCreate your KORLIX account and confirm your email, then open KORLIX Social and create your Social profile.${handle.isEmpty ? '' : ' Find me as @$handle in People and send a follow request.'}';

String? inviteEmail(String value) {
  final email = value.trim();
  return email.length <= 254 &&
          RegExp(
            r'^[^\s<>,;:@]+@[^\s<>,;:@]+\.[^\s<>,;:@]+$',
          ).hasMatch(email) &&
          !RegExp(r'[\x00-\x1f\x7f]').hasMatch(email)
      ? email
      : null;
}

String? invitePhone(String value) {
  final phone = value
      .trim()
      .replaceFirst(RegExp(r'^tel:', caseSensitive: false), '')
      .replaceAll(RegExp(r'[\s().-]'), '');
  return RegExp(r'^\+?[0-9]{7,15}$').hasMatch(phone) ? phone : null;
}

class InviteContact {
  InviteContact({
    required String name,
    List<String> emails = const [],
    List<String> phones = const [],
  }) : name = _contactName(name),
       emails = emails
           .map(inviteEmail)
           .whereType<String>()
           .toSet()
           .take(12)
           .toList(),
       phones = phones
           .map(invitePhone)
           .whereType<String>()
           .toSet()
           .take(12)
           .toList();
  final String name;
  final List<String> emails, phones;
  bool get usable => emails.isNotEmpty || phones.isNotEmpty;
  String get key => emails.isNotEmpty
      ? 'email:${emails.first.toLowerCase()}'
      : 'phone:${phones.first}';
  String get label => name.isNotEmpty
      ? name
      : emails.isNotEmpty
      ? emails.first
      : phones.first;
  String get searchText =>
      '$name ${emails.join(' ')} ${phones.join(' ')}'.toLowerCase();
}

String _contactName(String value) {
  final clean = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
  return clean.length > 120 ? clean.substring(0, 120) : clean;
}

class InviteImport {
  InviteImport(this.contacts, this.skipped, this.duplicates);
  final List<InviteContact> contacts;
  final int skipped, duplicates;
}

InviteImport importInviteContacts(String filename, Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
    throw const SocialException(
      'Choose a CSV or vCard file smaller than 2 MB.',
    );
  }
  String source;
  try {
    source = utf8.decode(bytes).replaceFirst('\uFEFF', '');
  } catch (_) {
    throw const SocialException(
      'Save the contact file as UTF-8 CSV or vCard, then try again.',
    );
  }
  final raw = filename.toLowerCase().endsWith('.vcf')
      ? _vcardContacts(source)
      : filename.toLowerCase().endsWith('.csv')
      ? _csvContacts(source)
      : throw const SocialException('Choose a .csv or .vcf contact export.');
  final contacts = <String, InviteContact>{};
  var skipped = 0, duplicates = 0;
  for (final contact in raw) {
    if (!contact.usable) {
      skipped++;
      continue;
    }
    final old = contacts[contact.key];
    if (old != null) {
      duplicates++;
      contacts[contact.key] = InviteContact(
        name: old.name.isEmpty ? contact.name : old.name,
        emails: [...old.emails, ...contact.emails],
        phones: [...old.phones, ...contact.phones],
      );
    } else {
      contacts[contact.key] = contact;
    }
    if (contacts.length > 500) {
      throw const SocialException(
        'Import up to 500 contacts at a time. Choose a smaller export.',
      );
    }
  }
  if (contacts.isEmpty) {
    throw const SocialException(
      'No usable email addresses or phone numbers were found. For CSV, include Name, Email and/or Phone columns.',
    );
  }
  return InviteImport(contacts.values.toList(), skipped, duplicates);
}

List<InviteContact> _vcardContacts(String text) {
  final rows = text
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'\n[ \t]'), '')
      .split('\n');
  final out = <InviteContact>[];
  var open = false, name = '', fallback = '';
  var emails = <String>[], phones = <String>[];
  String unescape(String s) => s
      .replaceAll(r'\n', ' ')
      .replaceAll(r'\N', ' ')
      .replaceAll(r'\,', ',')
      .replaceAll(r'\;', ';')
      .replaceAll(r'\\', r'\');
  for (final row in rows) {
    if (row.trim().toUpperCase() == 'BEGIN:VCARD') {
      open = true;
      name = fallback = '';
      emails = [];
      phones = [];
      continue;
    }
    if (row.trim().toUpperCase() == 'END:VCARD') {
      if (open) {
        out.add(
          InviteContact(
            name: name.isEmpty ? fallback : name,
            emails: emails,
            phones: phones,
          ),
        );
      }
      open = false;
      continue;
    }
    if (!open) continue;
    final colon = row.indexOf(':');
    if (colon < 0) continue;
    final property = row
        .substring(0, colon)
        .split(';')
        .first
        .split('.')
        .last
        .toUpperCase();
    final value = row.substring(colon + 1);
    if (property == 'FN') name = unescape(value);
    if (property == 'N') {
      final n = value.split(';');
      fallback = unescape([if (n.length > 1) n[1], n[0]].join(' '));
    }
    if (property == 'EMAIL') emails.add(value);
    if (property == 'TEL') phones.add(value);
  }
  if (open) {
    throw const SocialException(
      'This vCard is incomplete. Export the contacts again.',
    );
  }
  return out;
}

List<List<String>> _csvRows(String text) {
  final rows = <List<String>>[];
  var row = <String>[], field = StringBuffer(), quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (ch == ',' && !quoted) {
      row.add(field.toString());
      field = StringBuffer();
    } else if ((ch == '\n' || ch == '\r') && !quoted) {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      if (row.any((v) => v.trim().isNotEmpty)) rows.add(row);
      row = [];
      field = StringBuffer();
    } else {
      field.write(ch);
    }
  }
  if (quoted) {
    throw const SocialException(
      'The CSV has an unfinished quoted field. Export it again.',
    );
  }
  row.add(field.toString());
  if (row.any((v) => v.trim().isNotEmpty)) rows.add(row);
  return rows;
}

List<InviteContact> _csvContacts(String text) {
  final rows = _csvRows(text);
  if (rows.isEmpty) return [];
  final headers = rows.first
      .map((s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''))
      .toList();
  bool isEmail(String s) =>
      ['email', 'emailaddress', 'primaryemail'].contains(s) ||
      RegExp(r'^email\d+value$').hasMatch(s);
  bool isPhone(String s) =>
      [
        'phone',
        'phonenumber',
        'mobile',
        'mobilephone',
        'homephone',
        'businessphone',
        'telephone',
      ].contains(s) ||
      RegExp(r'^phone\d+value$').hasMatch(s);
  if (!headers.any((h) => isEmail(h) || isPhone(h))) {
    throw const SocialException(
      'CSV needs an Email or Phone column. Google and Outlook contact exports are also supported.',
    );
  }
  return rows.skip(1).map((row) {
    String cell(int i) => i < row.length ? row[i] : '';
    String value(List<String> keys) {
      final i = headers.indexWhere(keys.contains);
      return i < 0 ? '' : cell(i);
    }

    final full = value(['name', 'fullname', 'displayname']);
    return InviteContact(
      name: full.isEmpty
          ? '${value(['firstname', 'givenname'])} ${value(['lastname', 'familyname'])}'
          : full,
      emails: [
        for (var i = 0; i < headers.length; i++)
          if (isEmail(headers[i])) cell(i),
      ],
      phones: [
        for (var i = 0; i < headers.length; i++)
          if (isPhone(headers[i])) cell(i),
      ],
    );
  }).toList();
}

Uri inviteDraftUri({
  required String recipient,
  required bool email,
  required String message,
}) {
  final checked = email ? inviteEmail(recipient) : invitePhone(recipient);
  if (checked == null) {
    throw const SocialException(
      'Choose a valid email address or phone number.',
    );
  }
  final values = {
    if (email) 'subject': 'Join me on KORLIX Social',
    'body': message,
  };
  return Uri(
    scheme: email ? 'mailto' : 'sms',
    path: checked,
    query: values.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&'),
  );
}
