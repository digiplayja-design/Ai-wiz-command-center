import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

for (const filename of ['web/index.html', 'web/flutter_bootstrap.js']) {
  test(`${filename} removes legacy cache workers and preserves opt-in push`, async () => {
    const source = await readFile(new URL(`../${filename}`, import.meta.url), 'utf8');
    const start = source.indexOf('if ("serviceWorker" in navigator)');
    const end = filename.endsWith('.html')
      ? source.indexOf('</script>', start)
      : source.indexOf('korlixBootStatus("Starting', start);
    assert(start >= 0 && end > start);
    const removed = [];
    const registration = (label, state, scriptURL) => ({
      [state]: {scriptURL},
      unregister: async () => { removed.push(label); },
    });
    const registrations = [
      registration('flutter', 'active', 'https://www.korlixdeveloper.com/app/flutter_service_worker.js?v=old'),
      registration('installing-flutter', 'installing', 'https://www.korlixdeveloper.com/app/flutter_service_worker.js'),
      registration('push', 'active', 'https://www.korlixdeveloper.com/app/korlix_social_push_sw.js'),
      registration('waiting-push', 'waiting', 'https://www.korlixdeveloper.com/app/korlix_social_push_sw.js'),
      {unregister: async () => { removed.push('empty'); }},
    ];
    vm.runInNewContext(source.slice(start, end), {
      URL,
      navigator: {serviceWorker: {getRegistrations: async () => registrations}},
    });
    await new Promise(resolve => setImmediate(resolve));
    assert.deepEqual(removed, ['flutter', 'installing-flutter']);
  });
}
