const API = 'https://uxtjzjbwtppjvnsoiijv.supabase.co/functions/v1/korlix-fax';
const $ = (id) => document.getElementById(id);
const storeKey = 'korlixFaxSession';
const labels = {
  preparing: 'Preparing',
  submitting: 'Submitting',
  checking: 'Awaiting confirmation',
  queued: 'Queued',
  sending: 'Sending',
  delivered: 'Delivered',
  received: 'Received',
  failed: 'Failed',
  requested: 'Requested',
  ordering: 'Carrier processing',
  active: 'Active',
};
const state = {
  token: sessionStorage.getItem(storeKey),
  workspace: null,
  view: 'inbound',
  epoch: 0,
};
for (const slot of document.querySelectorAll('.brand-slot'))
  slot.append($('brand').content.cloneNode(true));
function el(tag, text, cls) {
  const n = document.createElement(tag);
  if (text !== undefined) n.textContent = text;
  if (cls) n.className = cls;
  return n;
}
function note(id, txt = '') {
  const node = $(id);
  node.textContent = txt;
  node.hidden = !txt;
}
function button(text, action, cls = 'secondary') {
  const btn = el('button', text, cls);
  btn.type = 'button';
  btn.onclick = async () => {
    btn.disabled = true;
    try {
      await action();
    } catch (e) {
      note($('dialog').open ? 'dialog-error' : 'error', e.message);
    } finally {
      btn.disabled = false;
    }
  };
  return btn;
}
const formatPhone = (s) =>
  typeof s === 'string' ? s.replace(/^\+1(\d{3})(\d{3})(\d{4})$/, '+1 ($1) $2-$3') : '';
const date = (s) =>
  new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(
    new Date(s)
  );
const dollars = (n) =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(n);
function loginScreen(msg = '') {
  state.token = null;
  state.workspace = null;
  state.view = 'inbound';
  state.epoch++;
  sessionStorage.removeItem(storeKey);
  if ($('dialog').open) $('dialog').close();
  $('app').hidden = true;
  $('login').hidden = false;
  $('password').value = '';
  $('password').type = 'password';
  $('show-password').textContent = 'Show';
  $('show-password').setAttribute('aria-pressed', 'false');
  $('show-password').setAttribute('aria-label', 'Show password');
  $('content').replaceChildren();
  $('account').textContent = '';
  $('side-value').textContent = '';
  note('login-error', msg);
}
async function api(path, { method = 'GET', body, headers = {}, raw = false } = {}) {
  const options = {
    method,
    headers: { ...headers },
    cache: 'no-store',
    referrerPolicy: 'no-referrer',
  };
  if (state.token) options.headers['X-Fax-Session'] = state.token;
  if (body !== undefined) {
    options.body = raw ? body : JSON.stringify(body);
    if (!raw) options.headers['Content-Type'] = 'application/json';
  }
  let res;
  try {
    res = await fetch(API + path, options);
  } catch {
    throw Error('Could not reach the fax service. Check your connection and try again.');
  }
  const data = await res.json().catch(() => ({}));
  if (res.status === 401 && state.token && path !== '/signin')
    loginScreen('Your session ended. Sign in again.');
  if (!res.ok) throw Error(data.error || 'Could not complete this request.');
  return data;
}
function openDialog(title, content) {
  $('dialog-title').textContent = title;
  $('dialog-body').replaceChildren(content);
  note('dialog-error');
  if (!$('dialog').open) $('dialog').showModal();
}
$('close-dialog').onclick = () => $('dialog').close();
$('show-password').onclick = () => {
  const show = $('password').type === 'password';
  $('password').type = show ? 'text' : 'password';
  $('show-password').textContent = show ? 'Hide' : 'Show';
  $('show-password').setAttribute('aria-pressed', String(show));
  $('show-password').setAttribute('aria-label', show ? 'Hide password' : 'Show password');
};
$('login-form').onsubmit = async (event) => {
  event.preventDefault();
  const btn = $('login-button');
  btn.disabled = true;
  note('login-error');
  btn.textContent = 'Signing in…';
  try {
    let device = localStorage.getItem('korlixFaxDevice');
    if (!device) {
      device = crypto.randomUUID();
      localStorage.setItem('korlixFaxDevice', device);
    }
    const auth = await api('/signin', {
      method: 'POST',
      body: { email: $('email').value, password: $('password').value, device },
    });
    $('password').value = '';
    state.token = auth.token;
    sessionStorage.setItem(storeKey, auth.token);
    await loadWorkspace();
  } catch (e) {
    note('login-error', e.message);
  } finally {
    btn.disabled = false;
    btn.textContent = 'Sign in to Fax Number';
  }
};
$('logout').onclick = async () => {
  try {
    await api('/signout', { method: 'POST' });
    loginScreen();
  } catch (e) {
    note('error', e.message);
  }
};
function updateLine() {
  const w = state.workspace,
    line = w.line;
  $('account').textContent = w.email;
  $('ops-nav').hidden = !w.operator;
  $('side-value').textContent =
    line?.state === 'active'
      ? formatPhone(line.phone)
      : line
        ? 'Activation pending'
        : 'Get a number';
  $('side-detail').textContent = line
    ? line.preference === 'toll_free'
      ? 'U.S. toll-free'
      : 'Area code ' + line.preference
    : 'For sending and receiving faxes';
}
async function loadWorkspace() {
  state.workspace = await api('/workspace');
  updateLine();
  $('login').hidden = true;
  $('app').hidden = false;
  await render(state.view);
}
function heading(title, sub, action) {
  const row = el('div', undefined, 'headrow'),
    left = el('div');
  left.append(el('h1', title));
  if (sub) left.append(el('p', sub, 'sub'));
  row.append(left);
  if (action) row.append(action);
  return row;
}
function empty(title, copy, action) {
  const box = el('div', undefined, 'empty');
  box.append(el('h2', title), el('p', copy, 'muted'));
  if (action) box.append(action);
  return box;
}
function detail(fields) {
  const list = el('dl', undefined, 'detail');
  for (const [k, v] of fields) {
    if (v != null && v !== '') list.append(el('dt', k), el('dd', String(v)));
  }
  return list;
}
async function render(view) {
  state.view = view;
  const generation = ++state.epoch;
  note('error');
  note('notice');
  document
    .querySelectorAll('[data-view]')
    .forEach((n) =>
      n.getAttribute('data-view') === view
        ? n.setAttribute('aria-current', 'page')
        : n.removeAttribute('aria-current')
    );
  const content = $('content');
  content.replaceChildren();
  try {
    if (view === 'number') {
      showNumber(content);
      return;
    }
    if (view === 'ops') {
      await showOps(content, generation);
      return;
    }
    const inbound = view === 'inbound';
    content.append(
      heading(
        inbound ? 'Inbox' : 'Sent',
        inbound ? 'Faxes received on your number.' : 'Delivery status for outgoing faxes.',
        button('Refresh', () => render(view), 'textbtn')
      )
    );
    const list = el('div', undefined, 'history');
    content.append(list);
    async function page(offset) {
      const data = await api('/history?direction=' + view + '&offset=' + offset);
      if (generation !== state.epoch) return;
      if (offset === 0 && !data.items.length) {
        const active = state.workspace.line?.state === 'active';
        list.append(
          empty(
            inbound ? 'Your inbox is empty' : 'No sent faxes yet',
            inbound
              ? active
                ? 'Share your number to receive your first fax.'
                : 'Incoming PDFs will appear here once your line is active.'
              : active
                ? 'Send a PDF to see its delivery status here.'
                : 'Activate your line to send your first PDF.',
            button(
              active && !inbound ? 'New fax' : 'View my number',
              active && !inbound ? compose : () => render('number')
            )
          )
        );
      }
      for (const doc of data.items) {
        const row = button('', () => documentDetails(doc), 'row'),
          label = el('span');
        label.append(
          el('strong', inbound ? formatPhone(doc.sender) : doc.name),
          el(
            'small',
            (inbound ? 'Received ' : 'To ' + formatPhone(doc.recipient) + ' · ') +
              date(doc.created_at)
          )
        );
        row.append(label, el('span', labels[doc.status] || doc.status, 'status'));
        list.append(row);
      }
      if (data.more) {
        const load = button('Load older faxes', async () => {
          await page(offset + data.items.length);
          load.remove();
        });
        list.append(load);
      }
    }
    await page(0);
  } catch (e) {
    if (generation === state.epoch) note('error', e.message);
  }
}
function showNumber(content) {
  const line = state.workspace.line;
  content.append(
    heading('My number', 'Your dedicated fax line.', button('Refresh', loadWorkspace, 'textbtn'))
  );
  if (line) {
    const card = el('div', undefined, 'line-card');
    card.append(
      el('span', labels[line.state], 'status'),
      el(
        'h2',
        line.state === 'active'
          ? formatPhone(line.phone)
          : line.is_company
            ? 'Korlix company line'
            : 'Your line request'
      )
    );
    const text =
      line.state === 'active'
        ? 'Use this number to receive faxes.'
        : line.state === 'ordering'
          ? 'The carrier is processing your line.'
          : 'Your request is saved. The number will appear here once the carrier activates it.';
    card.append(
      el('p', text, 'muted'),
      el(
        'p',
        line.preference === 'toll_free' ? 'U.S. toll-free' : 'U.S. area code ' + line.preference,
        'muted'
      )
    );
    if (line.state === 'active')
      card.append(
        button('Copy number', async () => {
          await navigator.clipboard.writeText(line.phone);
          note('notice', 'Number copied.');
        })
      );
    content.append(card);
    if (state.workspace.operator && line.state !== 'active')
      content.append(button('Manage line requests', () => render('ops')));
    return;
  }
  const box = el('form', undefined, 'surface narrow');
  box.append(
    el('h2', 'Request a number'),
    el('p', 'Choose toll-free or a local U.S. area code.', 'muted')
  );
  const label = el('label', 'Number type');
  label.htmlFor = 'number-type';
  const type = el('select');
  type.id = 'number-type';
  for (const [v, t] of [
    ['toll_free', 'U.S. toll-free'],
    ['local', 'U.S. local number'],
  ]) {
    const o = el('option', t);
    o.value = v;
    type.append(o);
  }
  const areaLabel = el('label', 'Preferred area code');
  areaLabel.htmlFor = 'area';
  const area = el('input');
  area.id = 'area';
  area.inputMode = 'numeric';
  area.maxLength = 3;
  area.pattern = '[2-9][0-9]{2}';
  area.placeholder = 'e.g. 614';
  areaLabel.hidden = area.hidden = true;
  type.onchange = () => {
    areaLabel.hidden = area.hidden = type.value !== 'local';
    area.required = type.value === 'local';
  };
  const submit = el('button', 'Request number', 'primary wide');
  submit.type = 'submit';
  box.append(label, type, areaLabel, area, submit);
  content.append(box);
  box.onsubmit = async (e) => {
    e.preventDefault();
    submit.disabled = true;
    try {
      const r = await api('/line', {
        method: 'POST',
        body: { preference: type.value === 'local' ? area.value : type.value },
      });
      state.workspace.line = r.line;
      updateLine();
      await render('number');
    } catch (err) {
      note('error', err.message);
    } finally {
      submit.disabled = false;
    }
  };
}
function documentDetails(doc) {
  const wrap = el('div');
  wrap.append(
    el('strong', doc.name),
    detail([
      ['Status', labels[doc.status]],
      ['From', formatPhone(doc.sender)],
      ['To', formatPhone(doc.recipient)],
      ['Pages', doc.pages],
      ['Created', date(doc.created_at)],
      ['Updated', date(doc.updated_at)],
      ['Details', doc.detail],
    ])
  );
  if (doc.hasFile)
    wrap.append(
      button('Get PDF link', async () => {
        const f = await api('/file/' + doc.id);
        const a = el('a', 'Open PDF', 'secondary linkbtn');
        a.href = f.url;
        a.target = '_blank';
        a.rel = 'noopener noreferrer';
        wrap.lastElementChild.replaceWith(a);
        a.focus();
      })
    );
  openDialog(doc.direction === 'inbound' ? 'Received fax' : 'Fax receipt', wrap);
}
function compose() {
  if (state.workspace.line?.state !== 'active' || !state.workspace.carrierReady) {
    render('number');
    note('notice', 'Sending becomes available when your line is active.');
    return;
  }
  const form = el('form'),
    label = el('label', 'Recipient fax number'),
    to = el('input');
  label.htmlFor = 'to';
  to.id = 'to';
  to.type = 'tel';
  to.placeholder = '+1 (614) 555-0100';
  to.required = true;
  const fileLabel = el('label', 'PDF document'),
    file = el('input', undefined, 'file');
  file.type = 'file';
  file.required = true;
  file.accept = 'application/pdf,.pdf';
  file.id = 'pdf';
  fileLabel.htmlFor = 'pdf';
  const submit = el('button', 'Review fax', 'primary wide');
  submit.type = 'submit';
  const actions = el('div', undefined, 'actions');
  actions.append(submit);
  form.append(label, to, fileLabel, file, el('p', 'One PDF, up to 8 MB.', 'hint'), actions);
  openDialog('New fax', form);
  form.onsubmit = (e) => {
    e.preventDefault();
    note('dialog-error');
    const digits = to.value.replace(/\D/g, '');
    const recipient = digits.length === 10 ? '+1' + digits : '+' + digits;
    const doc = file.files[0];
    if (!/^\+1[2-9]\d{2}[2-9]\d{6}$/.test(recipient)) {
      note('dialog-error', 'Enter a valid 10-digit or +1 fax number.');
      return;
    }
    if (!doc || doc.size < 5 || doc.size > 8388608) {
      note('dialog-error', 'Choose a PDF up to 8 MB.');
      return;
    }
    const wrap = el('div');
    wrap.append(
      detail([
        ['From', formatPhone(state.workspace.line.phone)],
        ['To', formatPhone(recipient)],
        ['Document', doc.name],
      ])
    );
    const actions = el('div', undefined, 'actions');
    const dispatch = button(
      'Send fax',
      async () => {
        const checksum = Array.from(
          new Uint8Array(await crypto.subtle.digest('SHA-256', await doc.arrayBuffer())),
          (x) => x.toString(16).padStart(2, '0')
        ).join('');
        const pending = 'faxPending:' + state.workspace.email + ':' + recipient + ':' + checksum;
        const request = sessionStorage.getItem(pending) || crypto.randomUUID();
        sessionStorage.setItem(pending, request);
        const result = await api('/send', {
          method: 'POST',
          raw: true,
          body: doc,
          headers: {
            'Content-Type': 'application/pdf',
            'X-Request-ID': request,
            'X-Fax-To': recipient,
            'X-Filename': encodeURIComponent(doc.name.slice(0, 120)),
          },
        });
        sessionStorage.removeItem(pending);
        $('dialog').close();
        await render('outbound');
        note('notice', 'Fax status: ' + (labels[result.status] || result.status) + '.');
      },
      'primary'
    );
    actions.append(
      button('Edit', () => openDialog('New fax', form)),
      dispatch
    );
    wrap.append(actions);
    openDialog('Review fax', wrap);
  };
}
async function showOps(content, generation) {
  content.append(
    heading(
      'Line requests',
      'Review and activate requested numbers.',
      button('Refresh', loadWorkspace, 'textbtn')
    )
  );
  const data = await api('/operator/requests');
  if (generation !== state.epoch) return;
  if (!state.workspace.carrierReady)
    content.append(
      el(
        'p',
        'Carrier connection pending. Requests are saved while Telnyx activation is completed.',
        'notice'
      )
    );
  if (!data.items.length) {
    content.append(empty('No pending requests', 'New line requests will appear here.'));
    return;
  }
  const list = el('div', undefined, 'stack');
  content.append(list);
  for (const row of data.items) {
    const box = el('div', undefined, 'surface');
    box.append(
      el(
        'h2',
        row.is_company ? 'Korlix company line' : 'Customer line · ' + row.id.slice(0, 8),
        'ops-title'
      ),
      el(
        'p',
        (row.preference === 'toll_free' ? 'U.S. toll-free' : 'Local · ' + row.preference) +
          ' · ' +
          labels[row.state] +
          ' · ' +
          date(row.created_at),
        'muted'
      )
    );
    if (state.workspace.carrierReady) {
      if (row.state === 'ordering')
        box.append(
          button('Check order', async () => {
            await api('/operator/' + row.id + '/sync', { method: 'POST' });
            await loadWorkspace();
          })
        );
      else
        box.append(
          button('View available numbers', async () => {
            const offer = await api('/operator/' + row.id + '/options');
            const options = el('div', undefined, 'stack');
            if (!offer.items.length)
              options.append(
                el(
                  'p',
                  'No matching fax numbers are available at $2/month or less with zero upfront cost.',
                  'muted'
                )
              );
            for (const q of offer.items)
              options.append(
                button(formatPhone(q.number) + ' · ' + dollars(q.monthly) + '/month', () => {
                  const confirmation = el('div');
                  confirmation.append(
                    detail([
                      ['Number', formatPhone(q.number)],
                      ['Monthly', dollars(q.monthly)],
                      ['Upfront', dollars(q.upfront)],
                      ['Usage', 'Fax pages and carrier transmission are extra.'],
                    ]),
                    button(
                      'Order this number',
                      async () => {
                        await api('/operator/' + row.id + '/order', { method: 'POST', body: q });
                        $('dialog').close();
                        await loadWorkspace();
                      },
                      'primary'
                    )
                  );
                  openDialog('Confirm number order', confirmation);
                })
              );
            openDialog('Available fax numbers', options);
          })
        );
      box.append(
        button(
          'Link an owned number',
          () => {
            const form = el('form'),
              label = el('label', 'Active Telnyx fax number'),
              input = el('input');
            input.type = 'tel';
            input.required = true;
            input.id = 'owned';
            label.htmlFor = 'owned';
            const submit = el('button', 'Link number', 'primary wide');
            submit.type = 'submit';
            form.append(
              label,
              input,
              el('p', 'Use a number already assigned to the Korlix fax application.', 'hint'),
              submit
            );
            form.onsubmit = async (event) => {
              event.preventDefault();
              submit.disabled = true;
              try {
                const digits = input.value.replace(/\D/g, '');
                const phone = digits.length === 10 ? '+1' + digits : '+' + digits;
                await api('/operator/' + row.id + '/attach', { method: 'POST', body: { phone } });
                $('dialog').close();
                await loadWorkspace();
              } catch (e) {
                note('dialog-error', e.message);
              } finally {
                submit.disabled = false;
              }
            };
            openDialog('Link an owned number', form);
          },
          'textbtn'
        )
      );
    }
    list.append(box);
  }
}
for (const btn of document.querySelectorAll('[data-view]'))
  btn.onclick = () => render(btn.dataset.view);
$('compose').onclick = compose;
if (state.token) loadWorkspace().catch((e) => loginScreen(e.message));
