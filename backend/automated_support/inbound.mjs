import {parseFragment} from 'parse5';
import {verifyKorlixAgentEmailResendWebhook} from '../korlix_agent_email_delivery.mjs';
import {validateTransactionalEmailAddress} from '../fieldproof/email_provider.mjs';
import {matchSupportReplyAddress} from './provider.mjs';

export const SUPPORT_WEBHOOK_PATH = '/api/automated-support/resend/webhook';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function mailbox(value) {
  if (typeof value !== 'string' || value.length > 600 || /[\r\n\x00]/.test(value)) return null;
  const named = /^(?:[^<>]*)<([^<>]+)>$/.exec(value.trim());
  try {return validateTransactionalEmailAddress(named ? named[1].trim() : value.trim());}
  catch {return null;}
}
function headersOf(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  const result = Object.create(null);
  for (const [key, content] of Object.entries(value)) {
    if (typeof content === 'string') result[key.toLowerCase()] = content.slice(0,4000);
  }
  return result;
}
function isAutomated(email, profiles) {
  const headers = headersOf(email.headers);
  const automatic = headers['auto-submitted']?.trim().toLowerCase();
  if (automatic && automatic !== 'no') return true;
  if (headers['list-id'] || /^(bulk|list|junk)$/i.test(headers.precedence || '')) return true;
  if (headers['return-path']?.trim() === '<>') return true;
  const from = mailbox(email.from)?.toLowerCase();
  if (!from || /^(mailer-daemon|postmaster|no-?reply)@/i.test(from)) return true;
  return profiles.some(profile => [profile.fromEmail,profile.replyTo,...profile.inboundAddresses].includes(from));
}
function textFromHtml(html) {
  if (typeof html !== 'string' || html.length > 500000) return '';
  const stack = [...parseFragment(html).childNodes].reverse();
  const parts = [];
  let total = 0, visited = 0;
  while (stack.length && total < 30000 && ++visited <= 30000) {
    const node = stack.pop();
    if (['script','style','head','template'].includes(node.tagName)) continue;
    if (node.nodeName === '#text') {
      const value = (node.value || '').slice(0,30000 - total);
      parts.push(value); total += value.length;
    } else {
      if (['p','div','br','li','tr','blockquote'].includes(node.tagName)) parts.push('\n');
      if (node.childNodes) stack.push(...node.childNodes.slice(0,10000).reverse());
    }
  }
  return parts.join('').replace(/\n{3,}/g,'\n\n').trim();
}
export function supportInboundContent(email) {
  let text = typeof email.text === 'string' ? email.text.slice(0,30000).trim() : '';
  if (!text) text = textFromHtml(email.html);
  const attachments = (Array.isArray(email.attachments) ? email.attachments : []).slice(0,10)
    .filter(file => UUID.test(file?.id || ''))
    .map(file => ({
      id:file.id,
      filename:String(file.filename || 'Attachment').replace(/[\x00-\x1f\x7f]/g,' ').slice(0,200),
      contentType:String(file.content_type || 'application/octet-stream').slice(0,120),
      size:Number.isSafeInteger(file.size) && file.size >= 0 ? file.size : null,
    }));
  if (attachments.length) text += '\n\nAttachments received: ' + attachments.map(file => file.filename).join(', ');
  text = text.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g,' ').trim();
  if (text.length > 20000) text = text.slice(0,19900) + '\n\n[Long reply truncated. The original email remains with the email provider.]';
  return {text,attachments};
}

export function registerAutomatedSupportInbound(app, {
  service, provider, profiles, environment = process.env, now = Date.now,
}) {
  app.post(SUPPORT_WEBHOOK_PATH, async (req,res) => {
    res.set('Cache-Control','no-store');
    try {
      if (req.originalUrl?.includes('?')) return res.status(400).json({ok:false,error:'Invalid support event.'});
      const {event} = verifyKorlixAgentEmailResendWebhook({
        rawBody:req.korlixSupportRawBody,
        headers:req.headers,
        secret:environment.KORLIX_SUPPORT_WEBHOOK_SECRET,
        now,
      });
      if (event?.type !== 'email.received') return res.json({ok:true,ignored:true});
      const emailId = event.data?.email_id;
      if (!UUID.test(emailId || '')) return res.status(400).json({ok:false,error:'Invalid support event.'});
      const email = await provider.receive(emailId);
      // Provider authentication is distinct from webhook authentication. Never
      // let a failed sender check modify a customer's case.
      if (email.authentication?.dmarc === 'fail' || email.authentication?.dkim === 'fail' && email.authentication?.spf === 'fail') {
        return res.json({ok:true,ignored:true});
      }
      if (isAutomated(email,profiles)) return res.json({ok:true,ignored:true});
      const recipients = [...new Set([
        ...(Array.isArray(email.to) ? email.to : []),
        ...(Array.isArray(email.received_for) ? email.received_for : []),
      ].map(mailbox).filter(Boolean))];
      const matches = recipients.map(value => matchSupportReplyAddress(value,profiles,environment)).filter(Boolean);
      const unique = new Map(matches.map(match => [match.profile.id + ':' + match.caseId,match]));
      // One email addressed to several cases is ambiguous; never copy it into
      // multiple businesses' support histories.
      if (unique.size !== 1) return res.json({ok:true,ignored:true});
      const {profile,caseId} = [...unique.values()][0];
      const fromEmail = mailbox(email.from)?.toLowerCase();
      const content = supportInboundContent(email);
      if (!fromEmail || !content.text) return res.json({ok:true,ignored:true});
      const headers = headersOf(email.headers);
      await service.receiveReply({
        profileId:profile.id,caseId,fromEmail,
        text:content.text,attachments:content.attachments,
        providerMessageId:emailId.toLowerCase(),
        internetMessageId:typeof email.message_id === 'string' ? email.message_id.slice(0,1000) : null,
        inReplyTo:headers['in-reply-to'] || null,
        senderAuthenticated:email.authentication?.dmarc === 'pass' || email.authentication?.dkim === 'pass',
      });
      return res.json({ok:true});
    } catch (error) {
      // Permanent ownership/format rejection is acknowledged without revealing
      // whether a case exists. Fetch/storage failures retain provider retries.
      if ([403,404,409,422].includes(error?.statusCode)) return res.json({ok:true,ignored:true});
      const status = [400,401].includes(error?.statusCode) ? error.statusCode : 503;
      return res.status(status).json({ok:false,error:status === 503
        ? 'Support replies are temporarily unavailable. Please retry.'
        : 'The support event could not be verified.'});
    }
  });
}
