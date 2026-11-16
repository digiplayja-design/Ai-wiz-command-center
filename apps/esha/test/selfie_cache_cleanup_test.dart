import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:esha_by_korlix/services/selfie.dart';

void main() {
  late Directory fixture;
  late Directory pickerCache;
  late Directory codeCache;
  late PickerFileCleaner cleaner;

  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('esha-picker-cleanup-');
    pickerCache = await Directory('${fixture.path}/cache').create();
    codeCache = await Directory('${fixture.path}/code_cache').create();
    cleaner = PickerFileCleaner(
      temporaryDirectory: () async => pickerCache.path,
    );
  });

  tearDown(() async {
    await fixture.delete(recursive: true);
  });

  Future<File> write(String relative) async {
    final file = File('${fixture.path}/$relative');
    await file.parent.create(recursive: true);
    return file.writeAsString('local fixture image');
  }

  test('cleans Android picker cache rather than Dart code_cache', () async {
    final photo = await write('cache/picker-uuid/selfie.jpg');
    final engineFile = await write('code_cache/engine-data');
    expect(codeCache.path, isNot(pickerCache.path));

    await cleaner.clean(XFile(photo.path));

    expect(await photo.exists(), isFalse);
    expect(await engineFile.readAsString(), 'local fixture image');
    // Empty picker UUID directories are harmless; cleanup deletes image data.
    expect(await photo.parent.exists(), isTrue);
  });

  test('preserves original outside cache and sibling prefix paths', () async {
    final original = await write('photos/original.jpg');
    final sibling = await write('cache-other/another.jpg');

    await cleaner.clean(XFile(original.path));
    await cleaner.clean(XFile(sibling.path));

    expect(await original.readAsString(), 'local fixture image');
    expect(await sibling.readAsString(), 'local fixture image');
  });

  test('rejects parent traversal out of the owned cache', () async {
    final original = await write('photos/original.jpg');

    await cleaner.clean(XFile('${pickerCache.path}/../photos/original.jpg'));

    expect(await original.readAsString(), 'local fixture image');
  });

  test('rejects file and directory symlinks escaping the cache', () async {
    final original = await write('photos/original.jpg');
    final fileLink = await Link('${pickerCache.path}/linked.jpg')
        .create(original.path);
    final directoryLink = await Link('${pickerCache.path}/linked-photos')
        .create(original.parent.path);

    await cleaner.clean(XFile(fileLink.path));
    await cleaner.clean(XFile('${directoryLink.path}/original.jpg'));

    expect(await original.readAsString(), 'local fixture image');
    expect(await fileLink.exists(), isTrue);
    expect(await directoryLink.exists(), isTrue);
  });

  test(
    'canonicalizes an owned cache alias before containment checks',
    () async {
      final photo = await write('cache/picker-uuid/selfie.jpg');
      final alias = await Link('${fixture.path}/cache-alias')
          .create(pickerCache.path);
      final aliasedCleaner = PickerFileCleaner(
        temporaryDirectory: () async => alias.path,
      );

      await aliasedCleaner.clean(XFile(photo.path));

      expect(await photo.exists(), isFalse);
    },
  );

  test('missing files and empty picker paths are harmless', () async {
    await cleaner.clean(XFile('${pickerCache.path}/missing.jpg'));
    await cleaner.clean(XFile(''));

    expect(await pickerCache.exists(), isTrue);
  });

  test('empty native directory cannot broaden the deletion scope', () async {
    final photo = await write('cache/picker-uuid/selfie.jpg');
    final unavailable = PickerFileCleaner(temporaryDirectory: () async => '');

    await unavailable.clean(XFile(photo.path));

    expect(await photo.readAsString(), 'local fixture image');
  });

  test('native cache failures keep cleanup nonfatal', () async {
    final photo = await write('cache/picker-uuid/selfie.jpg');
    for (final failure in <Object>[
      PlatformException(code: 'temporary_directory_unavailable'),
      MissingPluginException('fixture'),
      const FileSystemException('fixture'),
    ]) {
      final unavailable = PickerFileCleaner(
        temporaryDirectory: () async => throw failure,
      );
      await expectLater(unavailable.clean(XFile(photo.path)), completes);
      expect(await photo.readAsString(), 'local fixture image');
    }
  });

  test('an unanswered native cache lookup is bounded', () async {
    final photo = await write('cache/picker-uuid/selfie.jpg');
    final unanswered = Completer<String>();
    final unavailable = PickerFileCleaner(
      temporaryDirectory: () => unanswered.future,
    );

    await unavailable
        .clean(XFile(photo.path))
        .timeout(const Duration(seconds: 3));

    expect(await photo.readAsString(), 'local fixture image');
  });
}
