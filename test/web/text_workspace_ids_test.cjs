const assert = require('node:assert/strict');
const { test } = require('node:test');
const { execFileSync } = require('node:child_process');
const { mkdtempSync, writeFileSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

// Run the production ID generator after Dart-to-JavaScript compilation.
// Native widget tests cannot detect JavaScript's 32-bit shift behavior.
test('new saved-box IDs work in the compiled web app', () => {
  const dart = process.env.DART_BIN || 'dart';
  const directory = mkdtempSync(path.join(tmpdir(), 'korlix-box-id-'));
  const source = path.join(directory, 'box_id_probe.dart');
  const compiled = path.join(directory, 'box_id_probe.js');
  const generator = pathToFileURL(path.resolve(__dirname,
    '../../lib/text_workspace/box_id.dart')).href;
  try {
    writeFileSync(source, `import '${generator}';
void main() {
  final ids = <String>{};
  for (var i = 0; i < 2000; i++) {
    final id = boxId();
    if (!RegExp(r'^\\d+-\\d+$').hasMatch(id) || !ids.add(id)) {
      throw StateError('Invalid or duplicate saved box ID');
    }
  }
  print('Created ' + ids.length.toString() + ' distinct saved box IDs');
}
`);
    execFileSync(dart, ['compile', 'js', '-O2', source, '-o', compiled], {
      encoding: 'utf8', stdio: 'pipe',
    });
    const result = execFileSync(process.execPath, ['-e',
      'globalThis.self = globalThis; ' +
      'globalThis.crypto = require("node:crypto").webcrypto; ' +
      'require(process.argv[1]);', compiled], { encoding: 'utf8' });
    assert.match(result, /Created 2000 distinct saved box IDs/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
