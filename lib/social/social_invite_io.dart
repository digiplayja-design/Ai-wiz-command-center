import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'social_invite_contacts.dart';
import 'social_client.dart';
import 'social_contact_picker_native.dart'
    if (dart.library.js_interop) 'social_contact_picker_web.dart';

class SocialInviteIo {
  bool get canPickContacts => socialContactPickerAvailable;
  Future<List<InviteContact>> chooseContacts() => pickSocialContacts();
  Future<InviteImport?> importContacts() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'vcf'],
      withData: true,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final file = picked.files.single;
    if (file.size > 2 * 1024 * 1024 || file.bytes == null) {
      throw const SocialException(
        'Choose a readable CSV or vCard file smaller than 2 MB.',
      );
    }
    return importInviteContacts(file.name, file.bytes!);
  }

  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
  Future<ShareResultStatus> share(String text, Rect origin) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: 'Join me on KORLIX Social',
        sharePositionOrigin: origin,
      ),
    );
    return result.status;
  }

  Future<bool> openDraft(Uri uri) => launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
    webOnlyWindowName: '_self',
  );
}
