import {createCipheriv,createDecipheriv,randomBytes} from 'node:crypto';
import {GasError,PACKAGE_NAME,token,tokenHash,userId,productId} from './google.mjs';
function associated(context) {
  if (!context || !/^[a-f0-9]{64}$/.test(context.tokenHash)) throw new GasError('GAS_TOKEN_CONTEXT_INVALID');
  return Buffer.from(JSON.stringify([1,PACKAGE_NAME,userId(context.userId),productId(context.productId),context.tokenHash]));
}
function decode(text, length=null) {
  if (typeof text!=='string' || !/^[A-Za-z0-9_-]+$/.test(text)) throw new GasError('GAS_TOKEN_DECRYPT_FAILED');
  const b=Buffer.from(text,'base64url');
  if (b.toString('base64url')!==text || (length!==null && b.length!==length)) throw new GasError('GAS_TOKEN_DECRYPT_FAILED');
  return b;
}
export function createTokenVault({activeKeyId,keys}={}) {
  if (!(keys instanceof Map) || !/^[A-Za-z0-9_-]{1,24}$/.test(activeKeyId??'') || !keys.has(activeKeyId)) throw new GasError('GAS_TOKEN_KEY_INVALID');
  const ring=new Map();
  for (const [id,key] of keys) {
    if (!/^[A-Za-z0-9_-]{1,24}$/.test(id) || !Buffer.isBuffer(key) || key.length!==32) throw new GasError('GAS_TOKEN_KEY_INVALID');
    ring.set(id,Buffer.from(key));
  }
  return Object.freeze({
    seal(purchaseToken,context) {
      token(purchaseToken); const aad=associated(context);
      if (tokenHash(purchaseToken)!==context.tokenHash) throw new GasError('GAS_TOKEN_CONTEXT_INVALID');
      const iv=randomBytes(12), cipher=createCipheriv('aes-256-gcm',ring.get(activeKeyId),iv);
      cipher.setAAD(aad);
      const data=Buffer.concat([cipher.update(purchaseToken,'utf8'),cipher.final()]);
      return Object.freeze({v:1,kid:activeKeyId,iv:iv.toString('base64url'),tag:cipher.getAuthTag().toString('base64url'),data:data.toString('base64url')});
    },
    open(sealed,context) {
      try {
        if (!sealed || sealed.v!==1 || !ring.has(sealed.kid) || typeof sealed.data!=='string' || sealed.data.length>2800) throw new Error();
        const decipher=createDecipheriv('aes-256-gcm',ring.get(sealed.kid),decode(sealed.iv,12));
        decipher.setAAD(associated(context)); decipher.setAuthTag(decode(sealed.tag,16));
        const plaintext=Buffer.concat([decipher.update(decode(sealed.data)),decipher.final()]).toString('utf8');
        token(plaintext); if (tokenHash(plaintext)!==context.tokenHash) throw new Error();
        return plaintext;
      } catch {throw new GasError('GAS_TOKEN_DECRYPT_FAILED');}
    },
  });
}
