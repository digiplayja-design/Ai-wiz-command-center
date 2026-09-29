// Pure allocation mathematics. Not a timer, purchase verifier, wallet or ledger.
// Caller supplies SERVER-VERIFIED active seconds and commits the result atomically
// in a durable, idempotent ledger. Never call this with client-authored duration.
export const GAS_RULES = Object.freeze({
  service: 'live_convo', unit: 'seconds', consumeIncludedFirst: true,
  purchasedTimeRollsOver: true, purchasedTimeChangesTier: false,
  socialCallsUseGas: false, musicUsesGas: false, autoPurchase: false,
});
export function allocateVoiceSeconds({featureKey, activeSeconds, includedSeconds, purchasedSeconds, developerUnlimited = false} = {}) {
  if (featureKey !== GAS_RULES.service) throw new TypeError('NOT_AN_AI_GAS_SERVICE');
  for (const value of [activeSeconds, includedSeconds, purchasedSeconds]) {
    if (!Number.isSafeInteger(value) || value < 0) throw new TypeError('INVALID_VOICE_SECONDS');
  }
  if (typeof developerUnlimited !== 'boolean') throw new TypeError('INVALID_DEVELOPER_ENTITLEMENT');
  const includedDebit = developerUnlimited ? 0 : Math.min(activeSeconds, includedSeconds);
  const gasDebit = developerUnlimited ? 0 : activeSeconds - includedDebit;
  const eligible = gasDebit <= purchasedSeconds;
  return Object.freeze({
    eligible,
    reason: eligible ? (developerUnlimited ? 'DEVELOPER_VOICE_EXEMPTION' : 'BALANCE_SUFFICIENT') : 'INSUFFICIENT_VOICE_BALANCE',
    includedDebit: eligible ? includedDebit : 0,
    gasDebit: eligible ? gasDebit : 0,
    remainingIncludedSeconds: includedSeconds - (eligible ? includedDebit : 0),
    remainingPurchasedSeconds: purchasedSeconds - (eligible ? gasDebit : 0),
  });
}
