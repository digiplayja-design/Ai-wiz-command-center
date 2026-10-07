const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function reject(message, statusCode) {
  const error = new Error(message);
  error.statusCode = statusCode;
  throw error;
}

// TestFlight and sandbox receipts are genuine Apple signatures, but are not
// paid production purchases. Test access is a server-controlled account grant.
// Expired/revoked observations must still pass so they can remove old access.
export function assertAppleSandboxAccess({userId, transaction, environment = process.env, now = Date.now}) {
  if (String(transaction?.environment || '').toLowerCase() !== 'sandbox') return;
  const active = ['active', 'grace_period'].includes(transaction?.status) &&
    !transaction?.revokedAt && Date.parse(transaction?.expiresAt || '') > now();
  if (!active) return;
  const allowed = new Set(String(environment.APPLE_SANDBOX_ALLOWED_USER_IDS || '')
    .split(/[,;\s]+/).filter(value => UUID.test(value)).map(value => value.toLowerCase()));
  if (!UUID.test(String(userId || '')) || !allowed.has(String(userId).toLowerCase())) {
    reject('Sandbox test purchases are not enabled for this Korlix account. Ask the administrator to enable paid-plan testing.', 403);
  }
}

// Apple authenticates a transaction, not the KORLIX account presenting it.
// Older purchases without an appAccountToken can only restore an existing
// server-owned binding; knowing a transaction ID is not proof of ownership.
export async function assertAppleAccountBinding({userId, transaction, database, environment = process.env, now = Date.now}) {
  assertAppleSandboxAccess({userId, transaction, environment, now});
  const owner = String(userId || '').toLowerCase();
  const accountToken = String(transaction?.appAccountToken || '').toLowerCase();
  if (!owner || !transaction?.originalTransactionId) {
    reject('Apple account ownership could not be verified.', 409);
  }
  if (accountToken) {
    if (accountToken !== owner) {
      reject('This Apple subscription is linked to a different Korlix account.', 409);
    }
    return;
  }
  if (!database) reject('Apple account verification is temporarily unavailable.', 503);
  let result;
  try {
    result = await database.from('korlix_apple_transaction_bindings')
      .select('user_id')
      .eq('original_transaction_id', transaction.originalTransactionId)
      .maybeSingle();
  } catch {
    reject('Apple account verification is temporarily unavailable.', 503);
  }
  if (result?.error) reject('Apple account verification is temporarily unavailable.', 503);
  if (!result?.data?.user_id || String(result.data.user_id).toLowerCase() !== owner) {
    reject('This older Apple purchase has no verified link to this Korlix account. Contact support to restore it.', 409);
  }
}

// A previously signed active purchase remains cryptographically valid after a
// refund. Always obtain the current provider observation before granting access.
export async function refreshSignedAppleTransaction({
  signedTransactionInfo, preferredEnvironment, expectedProductId,
  verifyTransaction, fetchHistory,
}) {
  const supplied = await verifyTransaction(signedTransactionInfo, preferredEnvironment);
  const transactionId = String(supplied?.decoded?.transactionId || '').trim();
  const original = String(supplied?.decoded?.originalTransactionId || '').trim();
  if (!transactionId || !original || (expectedProductId && supplied.decoded.productId !== expectedProductId)) {
    reject('Apple transaction could not be matched to the requested purchase.', 400);
  }
  const current = await fetchHistory({transactionId, expectedProductId});
  if (String(current?.decoded?.originalTransactionId || '').trim() !== original ||
      (expectedProductId && current?.decoded?.productId !== expectedProductId) ||
      current?.environment !== supplied.environment) {
    reject('Apple transaction ownership or environment changed during verification.', 409);
  }
  return current;
}
