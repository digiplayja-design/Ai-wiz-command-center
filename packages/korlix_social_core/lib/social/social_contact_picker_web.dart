import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'social_client.dart';
import 'social_invite_contacts.dart';

@JS()
extension type _Contacts(JSObject _) implements JSObject {
  external JSPromise<JSArray<JSObject>> select(
    JSArray<JSString> properties,
    JSObject options,
  );
}
bool get socialContactPickerAvailable =>
    web.window.isSecureContext &&
    web.window.top == web.window &&
    web.window.navigator.hasProperty('contacts'.toJS).toDart;

Future<List<InviteContact>> pickSocialContacts() async {
  if (!socialContactPickerAvailable) return [];
  try {
    final manager = _Contacts(
      web.window.navigator.getProperty<JSObject>('contacts'.toJS),
    );
    // Call directly from the tap. Request only the fields needed for an invite.
    final selected = await manager
        .select(
          ['name'.toJS, 'email'.toJS, 'tel'.toJS].toJS,
          {'multiple': true}.jsify() as JSObject,
        )
        .toDart;
    return selected.toDart
        .take(500)
        .map((entry) {
          final data = entry.dartify() as Map;
          List<String> values(String key) =>
              (data[key] is List ? data[key] as List : [])
                  .whereType<String>()
                  .toList();
          return InviteContact(
            name: values('name').join(' '),
            emails: values('email'),
            phones: values('tel'),
          );
        })
        .where((c) => c.usable)
        .toList();
  } catch (e) {
    if ('$e'.contains('AbortError')) return [];
    throw const SocialException(
      'Contact selection did not open. You can import a CSV or vCard file, or add someone manually.',
    );
  }
}
