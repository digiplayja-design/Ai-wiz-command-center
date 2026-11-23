import {pathToFileURL} from 'node:url';
import {purchaseToken} from '../google_play/core.mjs';
import {UUID} from '../web_billing/core.mjs';
import {readGoogleLicenseTestOrders} from '../store_measurement/first_charge.mjs';

const emptyResult = status => ({status, zeroValueOrders: 0, firstPayments: 0, laterPayments: 0});

async function configuredPlay() {
  const {googlePlay} = await import('../google_play/provider.mjs');
  return googlePlay();
}

// Read one original, account-matched license-test chain. A zero total alone does
// not prove a free trial. No entitlements, Analytics events or store state are changed.
export async function checkPlayTestFirstPayment(token, testerId, provider = configuredPlay) {
  try {
    purchaseToken(token);
    if (typeof testerId !== 'string' || !UUID.test(testerId)) return emptyResult('skip');
    const result = emptyResult('pending');
    let previousTime = 0;
    for await (const order of readGoogleLicenseTestOrders(token, testerId, await provider())) {
      if (order.time <= previousTime) return emptyResult('skip');
      previousTime = order.time;
      if (order.value === 0) {
        if (!order.refunded) result.zeroValueOrders++;
      } else if (result.firstPayments === 0) {
        if (order.refunded) return emptyResult('skip');
        result.firstPayments = 1;
        result.status = 'ready';
      } else if (!order.refunded) {
        result.laterPayments++;
      }
    }
    return result;
  } catch {
    return emptyResult('skip');
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.length !== 3 || process.argv[2] !== '--license-test') {
    console.error('Provide the original Google Play test purchase token and tester KORLIX ID through the environment, then run with --license-test.');
    process.exitCode = 2;
  } else {
    const result = await checkPlayTestFirstPayment(process.env.KORLIX_LICENSE_TEST_PURCHASE_TOKEN,
      process.env.KORLIX_LICENSE_TEST_USER_ID);
    console.log(JSON.stringify(result));
    process.exitCode = result.status === 'ready' ? 0 : result.status === 'pending' ? 1 : 2;
  }
}
