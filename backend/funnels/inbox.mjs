import {createHash} from 'node:crypto';
import {fail, uuid} from './core.mjs';
import {LEAD_STATUSES,LEAD_STATUS_LABELS} from './lead_management.mjs';

const scalar = (value, max, label) => {
  if (value === undefined || value === '') return '';
  if (typeof value !== 'string' || value.length > max || /[\x00-\x1f\x7f]/.test(value)) fail(`Enter a valid ${label}.`);
  return value.trim();
};
const instant = value => {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(value) || !Number.isFinite(Date.parse(value))) fail('Refresh the lead inbox to restart paging.');
  return value; // Preserve Postgres microseconds for tied timestamps.
};
const date = (value, label) => {
  const s = scalar(value, 10, label);
  if (s && (!/^\d{4}-\d{2}-\d{2}$/.test(s) || !Number.isFinite(Date.parse(s)) || new Date(s).toISOString().slice(0, 10) !== s)) fail(`Enter a valid ${label}.`);
  return s;
};
export function inboxQuery(query = {}, exporting = false) {
  if (Object.keys(query).some(key => !['search','source','status','from','to','snapshot','cursor'].includes(key))) fail('Invalid inbox filter. Refresh and try again.');
  const data = {search:scalar(query.search, 160, 'search'), source:scalar(query.source, 120, 'source'), status:scalar(query.status,20,'lead status'), from:date(query.from, 'start date'), to:date(query.to, 'end date'), export:exporting};
  if(data.status&&!LEAD_STATUSES.includes(data.status))fail('Choose an available lead status.');
  if (data.from && data.to && data.from > data.to) fail('The end date must be on or after the start date.');
  const fingerprint = createHash('sha256').update(JSON.stringify([data.search,data.source,data.from,data.to,data.status])).digest('hex');
  if (query.snapshot !== undefined) data.snapshot = instant(query.snapshot);
  if (query.cursor !== undefined && query.cursor !== '') {
    if (exporting) fail('Export starts from the first matching inquiry.');
    const raw = scalar(query.cursor, 800, 'page cursor');
    let c;
    try {c = JSON.parse(Buffer.from(raw, 'base64url').toString('utf8'));} catch {fail('Refresh the lead inbox to restart paging.');}
    if (!c || c.f !== fingerprint || c.s !== data.snapshot) fail('Refresh the lead inbox after changing filters.');
    data.before_at = instant(c.t); data.before_id = uuid(c.id);
  }
  return {data, fingerprint};
}

// All cells are quoted; formula-like cells are forced to text in spreadsheet apps.
export function csvCell(value) {
  let s = String(value ?? '').replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, '');
  if (/^[\s\uFEFF]*[=+\-@]/.test(s) || /^[\t\r\n]/.test(s)) s = "'" + s;
  return '"' + s.replaceAll('"', '""') + '"';
}
export function leadCsv(leads) {
  const headings = ['Inquiry ID','Received (UTC)','Name','Email','Phone','Message','Source','Campaign','Medium','Content','Term','CRM contact ID','Submitted consent','Identity verification','Lead status (owner-set)','Private note','Status / note updated (UTC)'];
  const rows = leads.map(l => [l.id,l.created_at,l.name,l.email,l.phone,l.message,l.utm?.utm_source,l.utm?.utm_campaign,l.utm?.utm_medium,l.utm?.utm_content,l.utm?.utm_term,l.contact_id,l.consent_text,'Unverified',LEAD_STATUS_LABELS[l.inbox_status??'new'],l.private_note,l.inbox_updated_at]);
  return '\uFEFF' + [headings,...rows].map(row => row.map(csvCell).join(',')).join('\r\n') + '\r\n';
}
export function registerInbox(app, {base, owner, command}) {
  app.get(base+'/:id/inbox', owner(async(q,r,u) => {
    const {data,fingerprint} = inboxQuery(q.query);
    const result = await command(u,'inbox',uuid(q.params.id),data);
    const next = result.next;
    r.json({...result,next:undefined,next_cursor:next ? Buffer.from(JSON.stringify({t:next.created_at,id:next.id,s:result.snapshot,f:fingerprint})).toString('base64url') : null});
  }));
  app.get(base+'/:id/inbox/export', owner(async(q,r,u) => {
    const {data} = inboxQuery(q.query,true);
    const id = uuid(q.params.id), result = await command(u,'inbox',id,data);
    r.json({csv:leadCsv(result.leads),count:result.leads.length,filename:`korlix-leads-${id}.csv`,snapshot:result.snapshot});
  }));
}
