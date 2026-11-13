import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory('runtime-screenshots');
  await output.create(recursive: true);
  final screenshots = <Map<String, Object>>[];
  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [arguments]) async {
      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name)) return false;
      final file = File('${output.path}/$name.png');
      await file.writeAsBytes(bytes, flush: true);
      screenshots.add({'name': name, 'file': file.path, 'bytes': bytes.length});
      return bytes.isNotEmpty;
    },
    responseDataCallback: (data) async {
      final report = Map<String, dynamic>.from(data ?? {})..remove('screenshots');
      report['screenshots'] = screenshots;
      await File('${output.path}/projection-runtime-evidence.json')
          .writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
    },
  );
}
