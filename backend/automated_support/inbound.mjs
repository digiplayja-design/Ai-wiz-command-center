import {parseFragment} from 'parse5';
import {verifyKorlixAgentEmailResendWebhook} from '../korlix_agent_email_delivery.mjs';
import {validateTransactionalEmailAddress} from '../fieldproof/email_provider.mjs';
import {matchSupportReplyAddress} from './provider.mjs';
import {AutomatedSupportError} from './config.mjs';
import {supportWebhookSecret} from './secrets.mjs';

export const SUPPORT_WEBHOOK_PATH = '/api/automated-support/resend/webhook';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function mailbox(value) {
  if (typeof value !== 'string' || value.length > 600 || /[\r\n\x00]/.test(value)) return null;
  const named = /^(?:[^<>]*)<([^<>]+)>$/.exec(value.trim());
  try {return validateTransactionalEmailAddress(named ? named[1].trim() : value.trim());}
  catch {return null;}
}

function recipientHeaderMailboxes(value) {
  // Support the ordinary mailbox-list syntax used in replies. Unsupported or
  // incomplete syntax disables recovery for the whole list; never take a
  // matching prefix from a truncated or malformed recipient header.
  if (typeof value !== 'string' || value.length > 4000) return null;
  const unfolded = value.replace(/\r\n[ \t]+/g,' ');
  if (/[\x00-\x08\x0a-\x1f\x7f]/.test(unfolded)) return null;
  const parts = [];
  let start = 0, quoted = false, escaped = false, angle = false;
  for (let index = 0; index < unfolded.length; index++) {
    const character = unfolded[index];
    if (quoted) {
      if (escaped) escaped = false;
      else if (character === '\\') escaped = true;
      else if (character === '"') quoted = false;
      continue;
    }
    if (character === '"') quoted = true;
    else if (character === '<') {if (angle) return null; angle = true;}
    else if (character === '>') {if (!angle) return null; angle = false;}
    else if (character === ',' && !angle) {
      parts.push(unfolded.slice(start,index).trim()); start = index + 1;
      if (parts.length >= 100) return null;
    }
  }
  if (quoted || escaped || angle) return null;
  parts.push(unfolded.slice(start).trim());
  const addresses = [];
  for (const part of parts) {
    if (!part) return null;
    const named = /^([^<>]*)<([^<>]+)>$/.exec(part);
    if (named) {
      const display = named[1].trim();
      if (display.startsWith('"')) {
        if (!/^"(?:[^"\\]|\\.)*"$/.test(display)) return null;
      } else if (/["():;,\\\[\]]/.test(display)) return null;
    }
    const parsed = mailbox(part);
    if (!parsed) return null;
    addresses.push(parsed);
  }
  return addresses;
}

function supportReceivingRecipients(email) {
  const actual = [
    ...(Array.isArray(email.to) ? email.to : []),
    ...(Array.isArray(email.received_for) ? email.received_for : []),
  ];
  if (actual.length > 100) return [];
  const canonical = [...new Set(actual.map(mailbox).filter(Boolean))];
  const normalized = new Set(canonical.map(value => value.toLowerCase()));
  const headers = email.headers;
  if (!headers || typeof headers !== 'object' || Array.isArray(headers)) return canonical;
  const entries = Object.entries(headers);
  if (entries.length > 200) return canonical;
  const recovered = [], seen = new Set();
  for (const [name,value] of entries) {
    const kind = name.toLowerCase();
    if (kind !== 'to' && kind !== 'cc') continue;
    if (seen.has(kind)) return canonical;
    seen.add(kind);
    const addresses = recipientHeaderMailboxes(value);
    if (!addresses || recovered.length + addresses.length > 100) return canonical;
    recovered.push(...addresses);
  }
  // Resend can lowercase its canonical recipients while retaining original
  // casing in To/Cc. Headers may recover casing only for a mailbox already in
  // that canonical set. They cannot introduce a new receiving destination.
  // Exact HMAC verification below still applies to every candidate.
  return [...new Set([...canonical,...recovered.filter(value => normalized.has(value.toLowerCase()))])];
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

// Internal callback for events already verified against the exact raw provider
// request. HTTP callers reach this only through one of the signed handlers.
export function createAutomatedSupportInboundProcessor({
  service, provider, profiles, environment = process.env,
}) {
  return async function processVerifiedSupportEvent(event) {
    try {
      if (event?.type !== 'email.received') return {ignored:true};
      const emailId = event.data?.email_id;
      if (!UUID.test(emailId || '')) throw new AutomatedSupportError('Invalid support event.',400,'support_inbound_invalid');
      const email = await provider.receive(emailId);
      // Provider authentication is distinct from webhook authentication. Never
      // let a failed sender check modify a customer's case.
      if (email.authentication?.dmarc === 'fail' || email.authentication?.dkim === 'fail' && email.authentication?.spf === 'fail') {
        return {ignored:true};
      }
      if (isAutomated(email,profiles)) return {ignored:true};
      const recipients = supportReceivingRecipients(email);
      const matches = recipients.map(value => matchSupportReplyAddress(value,profiles,environment)).filter(Boolean);
      const unique = new Map(matches.map(match => [match.profile.id + ':' + match.caseId,match]));
      // One email addressed to several cases is ambiguous; never copy it into
      // multiple businesses' support histories.
      if (unique.size !== 1) return {ignored:true};
      const {profile,caseId} = [...unique.values()][0];
      const fromEmail = mailbox(email.from)?.toLowerCase();
      const content = supportInboundContent(email);
      if (!fromEmail || !content.text) return {ignored:true};
      const headers = headersOf(email.headers);
      await service.receiveReply({
        profileId:profile.id,caseId,fromEmail,
        text:content.text,attachments:content.attachments,
        providerMessageId:emailId.toLowerCase(),
        internetMessageId:typeof email.message_id === 'string' ? email.message_id.slice(0,1000) : null,
        inReplyTo:headers['in-reply-to'] || null,
        senderAuthenticated:email.authentication?.dmarc === 'pass' || email.authentication?.dkim === 'pass',
      });
      return {ignored:false};
    } catch (error) {
      // Permanent ownership/format rejection is acknowledged without revealing
      // whether a case exists. Fetch/storage failures retain provider retries.
      if ([403,404,409,422].includes(error?.statusCode)) return {ignored:true};
      const status = [400,401].includes(error?.statusCode) ? error.statusCode : 503;
      throw new AutomatedSupportError(status === 503
        ? 'Support replies are temporarily unavailable. Please retry.'
        : 'The support event could not be verified.',status,'support_inbound_unavailable');
    }
  };
}

export function registerAutomatedSupportInbound(app, {
  service, provider, profiles, environment = process.env, now = Date.now,
  processVerifiedEvent = createAutomatedSupportInboundProcessor({service,provider,profiles,environment}),
}) {
  app.post(SUPPORT_WEBHOOK_PATH, async (req,res) => {
    res.set('Cache-Control','no-store');
    try {
      if (req.originalUrl?.includes('?')) return res.status(400).json({ok:false,error:'Invalid support event.'});
      const {event} = verifyKorlixAgentEmailResendWebhook({
        rawBody:req.korlixSupportRawBody,
        headers:req.headers,
        secret:supportWebhookSecret(environment),
        now,
      });
      const result = await processVerifiedEvent(event);
      return res.json(result.ignored ? {ok:true,ignored:true} : {ok:true});
    } catch (error) {
      const status = [400,401].includes(error?.statusCode) ? error.statusCode : 503;
      return res.status(status).json({ok:false,error:status === 503
        ? 'Support replies are temporarily unavailable. Please retry.'
        : 'The support event could not be verified.'});
    }
  });
}
