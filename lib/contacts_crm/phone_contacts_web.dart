import 'dart:js_interop';

@JS('navigator.contacts')
external _ContactPicker? get _picker;

@JS()
extension type _ContactPicker(JSObject _) implements JSObject {
  external JSPromise<JSArray<JSString>> getProperties();
  external JSPromise<JSArray<JSObject>> select(
    JSArray<JSString> properties,
    JSObject options,
  );
}

@JS()
extension type _Options._(JSObject _) implements JSObject {
  external factory _Options({bool multiple});
}

bool get phonePickerAvailable => _picker != null;
Future<List<Map<String, dynamic>>> pickPhoneContacts() async {
  final picker = _picker;
  if (picker == null) return [];
  final supported = (await picker.getProperties().toDart).toDart
      .map((e) => e.toDart)
      .toSet();
  final fields = [
    'name',
    'email',
    'tel',
  ].where(supported.contains).map((e) => e.toJS).toList().toJS;
  final selected = await picker.select(fields, _Options(multiple: true)).toDart;
  return selected.toDart.map((item) {
    final data = item.dartify() as Map;
    String first(String key) =>
        data[key] is List && (data[key] as List).isNotEmpty
        ? (data[key] as List).first.toString()
        : '';
    return <String, dynamic>{
      'name': first('name').isNotEmpty ? first('name') : first('email'),
      'email': first('email'),
      'phone': first('tel'),
    };
  }).toList();
}
