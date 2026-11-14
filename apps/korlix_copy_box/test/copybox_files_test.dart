import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:korlix_copy_box/copybox_files.dart';
import 'package:korlix_copy_box/copybox_store.dart';

void main() {
  test('streams an import without corrupting split UTF-8 characters', () async {
    const text = 'Hello, Rici 👋';
    final encoded = utf8.encode(text);
    final bytes = await readCopyBoxImportBytes(
      () => Stream.fromIterable([
        encoded.sublist(0, encoded.length - 2),
        encoded.sublist(encoded.length - 2),
      ]),
    );
    expect(utf8.decode(bytes), text);
  });

  test('accepts a file exactly at the 5 MiB byte limit', () async {
    final bytes = await readCopyBoxImportBytes(
      () => Stream.value(Uint8List(copyBoxMaxBytes)),
      declaredLength: copyBoxMaxBytes,
    );
    expect(bytes.length, copyBoxMaxBytes);
  });

  test('rejects a known oversized file before opening its stream', () async {
    var opened = false;
    await expectLater(
      readCopyBoxImportBytes(() {
        opened = true;
        return const Stream<List<int>>.empty();
      }, declaredLength: copyBoxMaxBytes + 1),
      throwsA(isA<CopyBoxDataException>()),
    );
    expect(opened, isFalse);
  });

  for (final declaredLength in <int?>[null, 1]) {
    test(
      'cancels an oversized stream with reported size $declaredLength',
      () async {
        var advancedAfterLimit = false;
        var cancelled = false;
        Stream<List<int>> source() async* {
          try {
            yield Uint8List(copyBoxMaxBytes);
            yield const [1];
            advancedAfterLimit = true;
            yield const [2];
          } finally {
            cancelled = true;
          }
        }

        await expectLater(
          readCopyBoxImportBytes(source, declaredLength: declaredLength),
          throwsA(isA<CopyBoxDataException>()),
        );
        expect(advancedAfterLimit, isFalse);
        expect(cancelled, isTrue);
      },
    );
  }
}
