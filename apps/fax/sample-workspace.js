// The sample uses synthetic records in memory and never contacts the fax carrier.
const number = '+12125550140';
const recipient = '+12125550141';
const contacts = [{ phone: recipient, name: 'Harbor Studio' }];
const files = new Map();
const plans = {
  solo: { name: 'Solo', pages: 100, price: '9.99' },
  business: { name: 'Business', pages: 250, price: '19.99' }
};
let line = { state: 'active', phone: number, preference: '212', requested_plan: 'solo' };
const date = new Date().toISOString();
const records = [
  { direction: 'inbound', sender: recipient, recipient: number, status: 'received', name: 'Project brief.pdf' },
  { direction: 'outbound', sender: number, recipient, status: 'delivered', name: 'Work order.pdf' }
].map((row, i) => ({ ...row, id: 'a19bd6b0-3314-4995-a5d8-1de7ed4424e' + i,
  pages: 1, created_at: date, updated_at: date, hasFile: true }));

function totals(items) {
  const inboundPages = items.filter(item => item.direction === 'inbound').reduce((sum, item) => sum + item.pages, 0);
  const pages = items.reduce((sum, item) => sum + item.pages, 0);
  return { pages, inboundPages, outboundPages: pages - inboundPages, pendingReports: 0 };
}
export const sampleWorkspace = {
  async request(path, options = {}) {
    const url = new URL(path, 'https://sample.invalid');
    switch (url.pathname) {
      case '/workspace':
        return { sample: true, email: 'sample@example.com', operator: false,
          line, plans, usage: totals(records), customerEnrollmentOpen: true };
      case '/line':
        if (!line && options.method === 'POST') {
          const { preference, plan } = options.body;
          line = { state: 'requested', preference, requested_plan: plan };
        }
        return { line };
      case '/account/delete-request':
        if (options.method === 'POST' && options.body?.confirm) return { requested: true };
        throw Error('Confirm the sample deletion request.');
      case '/contacts': {
        if (options.method !== 'POST') return { items: [...contacts] };
        const { phone, name } = options.body;
        const existing = contacts.find(item => item.phone === phone);
        if (existing) existing.name = name;
        else contacts.push({ phone, name });
        return { phone, name };
      }
      case '/history':
        return { items: records.filter(item => item.direction === url.searchParams.get('direction')), more: false };
      case '/activity': {
        const month = url.searchParams.get('month');
        const items = records.filter(item => item.updated_at.startsWith(month));
        return { summary: totals(items), items, next: null };
      }
      case '/signout':
        files.clear();
        return { ok: true };
      default: {
        if (url.pathname.startsWith('/document/')) {
          const item = records.find(record => record.id === url.pathname.slice('/document/'.length));
          if (item) return item;
        }
        throw Error('This action requires a live fax account.');
      }
    }
  },
  previewLineRequest() { line = null; },
  activateRequestedLine() {
    if (line?.state === 'requested') line = { ...line, state: 'active', phone: number };
  },
  send(doc, to) {
    if (line?.state !== 'active') throw Error('Activate the sample line first.');
    const id = crypto.randomUUID();
    const time = new Date().toISOString();
    records.unshift({ id, direction: 'outbound', sender: number, recipient: to, name: doc.name,
      status: 'delivered', pages: doc.pages, hasFile: true, created_at: time, updated_at: time,
      detail: 'Sample delivery on this device.' });
    files.set(id, doc.file);
    return { id, status: 'delivered' };
  },
  file(id) { return files.get(id); }
};
