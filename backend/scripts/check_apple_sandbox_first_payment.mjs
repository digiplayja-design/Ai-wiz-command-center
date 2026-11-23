import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {PACKAGE} from '../google_play/core.mjs';
import {readAppleSandboxChargeHistory} from '../store_measurement/first_charge.mjs';
import {UUID} from '../web_billing/core.mjs';

const appleId = /^[1-9]\d{0,31}$/;
const skipped = () => ({status: 'skip', freeTrials: 0, firstPayments: 0, laterPayments: 0});

// Run in the existing Apple billing verification environment. Read identifiers from the
// environment so a tester's account and transaction don't appear in command histories.
async function appleSandboxProvider() {
  const env = process.env;
  const privateKey = env.KORLIX_APPLE_PRIVATE_KEY_BASE64
    ? Buffer.from(env.KORLIX_APPLE_PRIVATE_KEY_BASE64, 'base64').toString('utf8')
    : env.KORLIX_APPLE_PRIVATE_KEY?.replace(/\\n/g, '\n');
  if (!privateKey?.trim() || !env.KORLIX_APPLE_KEY_ID || !env.KORLIX_APPLE_ISSUER_ID) {
    throw new Error('Apple verification is unavailable.');
  }
  const library = await import('@apple/app-store-server-library');
  const certificates = await Promise.all([
    'AppleIncRootCertificate.cer', 'AppleRootCA-G2.cer', 'AppleRootCA-G3.cer',
  ].map(name => readFile(new URL('../apple_root_certs/' + name, import.meta.url))));
  return {
    library,
    sandboxClient: new library.AppStoreServerAPIClient(privateKey.trim(), env.KORLIX_APPLE_KEY_ID,
      env.KORLIX_APPLE_ISSUER_ID, PACKAGE, library.Environment.SANDBOX),
    sandboxVerifier: new library.SignedDataVerifier(certificates, true, library.Environment.SANDBOX, PACKAGE),
  };
}

export async function checkAppleSandboxFirstPayment(originalId, testerId, provider = appleSandboxProvider) {
  if (typeof originalId !== 'string' || !appleId.test(originalId) ||
      typeof testerId !== 'string' || !UUID.test(testerId)) return skipped();
  try {
    const entries = new Map();
    const first = await readAppleSandboxChargeHistory(originalId, testerId, await provider(), (tx, charge) => {
      if (tx.appAccountToken?.toLowerCase() !== testerId.toLowerCase() || !appleId.test(tx.transactionId)) {
        throw new Error('Unmatched sandbox purchase.');
      }
      // Count a transaction once across pages. Conflicting copies cannot establish its status.
      const entry = {time: tx.purchaseDate, sku: tx.productId, price: tx.price, currency: tx.currency,
        trial: tx.offerDiscountType === 'FREE_TRIAL', paid: Boolean(charge), revoked: tx.revocationDate != null};
      const previous = entries.get(tx.transactionId);
      if (previous && JSON.stringify(previous) !== JSON.stringify(entry)) throw new Error('Conflicting history.');
      entries.set(tx.transactionId, entry);
    });
    const original = entries.get(originalId);
    if (!original || original.revoked) return skipped();
    const transactions = [...entries.values()];
    if (transactions.some(tx => tx.time < original.time)) return skipped();
    const freeTrials = transactions.filter(tx => tx.trial && !tx.revoked).length;
    if (!first) return {status: 'pending', freeTrials, firstPayments: 0, laterPayments: 0};
    const payments = transactions.filter(tx => tx.paid);
    if (first.refunded || payments.filter(tx => tx.time === first.time).length !== 1) return skipped();
    const laterPayments = payments.filter(tx => tx.time > first.time && !tx.revoked).length;
    return {status: 'ready', freeTrials, firstPayments: 1, laterPayments};
  } catch {
    // Provider errors may include authorization data, receipt values or transaction identifiers.
    return skipped();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.length !== 3 || process.argv[2] !== '--sandbox') {
    console.error('Usage: set KORLIX_SANDBOX_ORIGINAL_TRANSACTION_ID and KORLIX_SANDBOX_TESTER_USER_ID, then run this script with --sandbox.');
    process.exitCode = 2;
  } else {
    const result = await checkAppleSandboxFirstPayment(process.env.KORLIX_SANDBOX_ORIGINAL_TRANSACTION_ID,
      process.env.KORLIX_SANDBOX_TESTER_USER_ID);
    console.log(JSON.stringify(result));
    process.exitCode = result.status === 'ready' ? 0 : result.status === 'pending' ? 1 : 2;
  }
}
