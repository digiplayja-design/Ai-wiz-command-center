import {readFile} from 'node:fs/promises';
import {PDFDocument, rgb} from 'pdf-lib';
import fontkit from '@pdf-lib/fontkit';
import sharp from 'sharp';
import {FieldProofError, TAGS} from './model.mjs';

export const FIELDPROOF_EMAIL_REPORT_LIMITS = Object.freeze({
  photos: 12, previewBytes: 1024 * 1024, totalPreviewBytes: 8 * 1024 * 1024,
  attachmentBytes: 5 * 1024 * 1024, pages: 24, evidenceRecords: 24,
});
const LIMITS = FIELDPROOF_EMAIL_REPORT_LIMITS;
const DISCLAIMER = 'This report contains technician-entered records. It does not independently certify workmanship, safety, dates, location, readings or customer identity.';
const PHOTO_NOTE = 'Photos are reduced-size previews of supplied evidence. They do not independently establish capture time, location or work quality.';
const FONT_NOTE = 'Some characters are outside the PDF font. They appear as [U+XXXX] below; the email body preserves the original text.';
const escapeHtml = value => value.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const fail = message => {throw new FieldProofError(message, 422);};
function field(value, max, label, fallback = '') {
  if (value == null || value === '') return fallback;
  if (typeof value !== 'string' || value.length > max || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/u.test(value)) {
    fail(`The saved ${label} cannot be included in this report. Review the job before sending.`);
  }
  return value;
}
function rows(value, max, label) {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > max || value.some(v => !v || typeof v !== 'object' || Array.isArray(v))) {
    fail(`The saved ${label} cannot be included in this report. Review the job before sending.`);
  }
  return value;
}
const singleLine = (value, max) => [...value.replace(/[\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim()].slice(0, max).join('');
const filePart = value => value.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/gi, '-').replace(/^-+|-+$/g, '').slice(0, 38) || 'job';

// This module accepts an authenticated snapshot and verified preview bytes only.
// It never loads an evidence URL or sends email. Unknown snapshot properties are
// deliberately ignored: internal billing, AI drafts, events and storage paths
// must not leak into a customer-facing report.
function customerReport(snapshot, includePhotos) {
  const job = snapshot?.job;
  if (!job?.data || typeof job.data !== 'object' || !Number.isInteger(job.version) || job.version < 1) fail('Refresh this job before preparing its email report.');
  const d = job.data;
  const id = field(job.id, 100, 'job identifier', 'Not recorded');
  const title = field(d.title, 120, 'job title', 'Field work report');
  const customer = field(d.customer, 160, 'customer', 'Not entered');
  const workOrder = field(d.workOrder, 100, 'work order', 'Not entered');
  const sections = [];
  const add = (heading, lines) => sections.push({heading, lines});
  const completed = job.state === 'completed';
  add('Job details', [
    `Customer: ${customer}`,
    `Site: ${field(d.site, 350, 'site', 'Not entered')}`,
    `Work order: ${workOrder}`,
    `Technician: ${field(d.technician, 120, 'technician name', 'Not entered')}`,
    `Work date (entered): ${field(d.performedOn, 10, 'work date', 'Not entered')}`,
    `Asset / serial (entered): ${field(d.assetId, 120, 'asset serial', 'Not entered')}`,
    `Previous serial (entered): ${field(d.oldAssetId, 120, 'previous serial', 'Not entered')}`,
    `Job status: ${completed ? 'Technician marked this job complete' : 'Working record - job has not been marked complete'}`,
    `Job ID: ${id} | Revision: ${job.version}`,
    `Report snapshot: ${field(snapshot.snapshotAt, 40, 'snapshot date', 'Not supplied')}`,
  ]);
  add('Technician-reported work', [field(d.summary, 4000, 'completed work', 'No completed work description entered.')]);
  if (d.materials) add('Materials and quantities (entered)', [field(d.materials, 2000, 'materials')]);
  const checks = rows(d.checks, 32, 'checklist');
  add('Technician-reported checklist', checks.length ? checks.map(c => {
    if (typeof c.done !== 'boolean') fail('Review the saved checklist before sending.');
    return `${c.done ? '[x] Reported complete' : '[ ] Not marked complete'}: ${field(c.label, 180, 'checklist label')}${c.required === true ? ' (required)' : ''}`;
  }) : ['No checklist items recorded.']);
  const readings = rows(d.readings, 20, 'readings');
  add('Readings and measurements (entered)', readings.length ? readings.map(r => {
    const unit = field(r.unit, 40, 'reading unit');
    // Values and identifiers remain strings. Never coerce, round or localize them.
    return `${field(r.label, 100, 'reading label')}: ${field(r.value, 160, 'reading value')}${unit ? ' ' + unit : ''}`;
  }) : ['No readings entered.']);
  const issues = rows(d.issues, 16, 'follow-up items');
  const open = issues.filter(i => i.resolved !== true);
  add('Outstanding items and follow-up', [
    `Technician-entered exceptions: ${field(d.exceptions, 2000, 'outstanding items', 'None entered.')}`,
    ...(open.length ? open.map(i => `${field(i.label, 200, 'follow-up label')}${i.dueOn ? ' | Follow-up date (entered): ' + field(i.dueOn, 10, 'follow-up date') : ''}${i.blocking === true ? ' | Marked as blocking closeout' : ''}`) : ['No open punch-list items recorded.']),
    ...(issues.some(i => i.resolved === true) ? [`${issues.filter(i => i.resolved === true).length} punch-list item(s) marked resolved by the technician.`] : []),
  ]);
  const approval = job.approval;
  add('Customer approval record', approval && typeof approval === 'object' ? [
    `Reported approver: ${field(approval.name, 160, 'reported approver', 'Not entered')}`,
    `Recorded: ${field(approval.recordedAt, 40, 'approval date', 'Not entered')}`,
    `Revision: ${Number.isInteger(approval.version) ? approval.version : 'Not recorded'}${approval.version === job.version ? ' (current report revision)' : ' (does not match this report revision)'}`,
    'Technician-recorded declaration; not an independently verified signature or customer identity.',
  ] : [d.requiresApproval === true ? 'Required approval has not been recorded.' : 'No customer approval recorded.']);
  const ready = rows(snapshot.evidence, LIMITS.evidenceRecords, 'photo records').filter(p => p.state === 'ready');
  const photos = includePhotos ? ready.slice(0, LIMITS.photos).map((p, index) => ({
    id: field(p.id, 100, 'photo identifier'),
    title: `${index + 1}. ${Object.hasOwn(TAGS, p.tag) ? TAGS[p.tag] : 'Other evidence'}`,
    // General evidence notes may be internal. Only an explicitly public caption
    // is included; filenames, storage URLs, upload metadata and EXIF are omitted.
    caption: field(p.publicCaption, 500, 'public photo caption'),
  })) : [];
  if (new Set(photos.map(p => p.id)).size !== photos.length || photos.some(p => !p.id)) fail('Refresh the saved photo records before sending.');
  const omittedPhotoCount = ready.length - photos.length;
  add('Photo evidence', [
    photos.length ? `${photos.length} photo preview(s) included in the attached PDF.` : 'No photo previews are included in this email.',
    ...(omittedPhotoCount ? [`${omittedPhotoCount} saved photo(s) omitted${includePhotos ? ' because this email report includes at most ' + LIMITS.photos + ' previews' : ' because photo sharing is off'}.`] : []),
    PHOTO_NOTE,
  ]);
  add('About this report', [DISCLAIMER]);
  const text = ['KORLIX FIELDPROOF', title, ...sections.flatMap(s => ['', s.heading.toUpperCase(), ...s.lines])].join('\n');
  if (Buffer.byteLength(text, 'utf8') > 64000) fail('Shorten the saved job record before preparing its email report.');
  return {title, customer, workOrder, version: job.version, snapshotAt: snapshot.snapshotAt, sections, text, photos, omittedPhotoCount};
}

let fontsPromise;
const fonts = () => fontsPromise ||= Promise.all(['Roboto-Regular.ttf', 'Roboto-Bold.ttf'].map(name => readFile(new URL(`./assets/${name}`, import.meta.url))));

async function normalizedPhotos(photos, previews) {
  const result = [];
  let bytes = 0;
  for (const photo of photos) {
    const input = previews instanceof Map ? previews.get(photo.id) : null;
    if (!(input instanceof Uint8Array) || input.byteLength === 0) fail('A selected photo preview is missing. Refresh the job before sending.');
    bytes += input.byteLength;
    if (input.byteLength > LIMITS.previewBytes || bytes > LIMITS.totalPreviewBytes) fail('Selected photo previews exceed the email attachment limit. Send the report without photos.');
    try {
      const options = {limitInputPixels: 1440000, failOn: 'warning'};
      const meta = await sharp(input, options).metadata();
      if (!['jpeg', 'png'].includes(meta.format) || (meta.pages || 1) !== 1 || !meta.width || !meta.height) throw Error('preview format');
      // Re-encode even authenticated previews: never preserve EXIF or other
      // embedded metadata, and cap the outbound dimensions and image quality.
      const image = await sharp(input, options).rotate().resize({width: 1100, height: 800, fit: 'inside', withoutEnlargement: true}).flatten({background: '#ffffff'}).jpeg({quality: 78}).toBuffer();
      result.push({...photo, image});
    } catch {
      fail('A selected photo preview is unreadable. Refresh the job or send its report without photos.');
    }
  }
  return result;
}

async function buildPdf(report, photos) {
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const [regularBytes, boldBytes] = await fonts();
  const regular = await pdf.embedFont(regularBytes, {subset: true});
  const bold = await pdf.embedFont(boldBytes, {subset: true});
  const boldCharacters = new Set(bold.getCharacterSet());
  const supported = new Set(regular.getCharacterSet().filter(c => boldCharacters.has(c)));
  let fallback = false;
  const safe = text => [...text].map(c => {
    const cp = c.codePointAt(0);
    if (c === '\n' || c === '\r' || c === '\t' || supported.has(cp)) return c;
    fallback = true;
    return `[U+${cp.toString(16).toUpperCase().padStart(4, '0')}]`;
  }).join('');
  const title = safe(report.title);
  const sections = report.sections.map(s => ({heading: s.heading, lines: s.lines.map(safe)}));
  const photoCaptions = photos.map(p => ({...p, caption: safe(p.caption)}));
  if (fallback) sections.unshift({heading: 'Character display note', lines: [FONT_NOTE]});
  const navy = rgb(0.063, 0.184, 0.263), cyan = rgb(0.03, 0.49, 0.63), ink = rgb(0.14, 0.19, 0.23), muted = rgb(0.36, 0.43, 0.47), pale = rgb(0.93, 0.97, 0.98);
  const width = 595.28, height = 841.89, left = 42, contentWidth = width - left * 2, bottom = 59;
  let page, y;
  const newPage = () => {
    if (pdf.getPageCount() >= LIMITS.pages) fail('This report exceeds the email page limit. Shorten the saved notes or send without photos.');
    page = pdf.addPage([width, height]);
    page.drawRectangle({x: 0, y: height - 72, width, height: 72, color: navy});
    page.drawText('KORLIX FIELDPROOF', {x: left, y: height - 35, font: bold, size: 18, color: rgb(1, 1, 1)});
    page.drawText('Customer job report', {x: left, y: height - 53, font: regular, size: 10, color: rgb(0.53, 0.88, 0.96)});
    y = height - 96;
  };
  const ensure = needed => {if (!page || y - needed < bottom) newPage();};
  const wrap = (text, font, size, maxWidth = contentWidth) => {
    const out = [];
    for (const raw of text.replace(/\r\n?/g, '\n').replace(/\t/g, '    ').split('\n')) {
      if (!raw) {out.push(''); continue;}
      let line = '';
      for (const token of raw.match(/\S+|\s+/gu) || []) {
        if (font.widthOfTextAtSize(line + token, size) <= maxWidth) {line += token; continue;}
        if (line.trim()) out.push(line.trimEnd());
        line = token.trimStart();
        while (font.widthOfTextAtSize(line, size) > maxWidth) {
          let chunk = '', length = 0;
          for (const c of line) {if (font.widthOfTextAtSize(chunk + c, size) > maxWidth) break; chunk += c; length += c.length;}
          if (!length) fail('A report value could not be laid out. Review the saved job.');
          out.push(chunk); line = line.slice(length);
        }
      }
      if (line || !out.length) out.push(line.trimEnd());
    }
    return out;
  };
  const paragraph = (text, {font = regular, size = 9.5, color = ink, spacing = 13.5} = {}) => {
    for (const line of wrap(text, font, size)) {ensure(spacing); if (line) page.drawText(line, {x: left, y: y - size, font, size, color}); y -= spacing;}
    y -= 5;
  };
  newPage();
  paragraph(title, {font: bold, size: 17, color: navy, spacing: 22});
  paragraph(`Revision ${report.version} | Technician-entered records`, {size: 9, color: muted});
  for (const section of sections) {
    // Keep short factual sections together, including the approval limitation.
    // Long notes may continue naturally over multiple pages.
    const sectionHeight = 33 + section.lines.reduce((total, line) => total + wrap(line, regular, 9.5).length * 13.5 + 5, 0);
    ensure(sectionHeight <= 230 ? sectionHeight : 45); y -= 7;
    page.drawRectangle({x: left - 4, y: y - 21, width: contentWidth + 8, height: 24, color: pale});
    paragraph(section.heading, {font: bold, size: 11, color: cyan, spacing: 21});
    for (const line of section.lines) paragraph(line);
  }
  if (photoCaptions.length) {
    newPage();
    paragraph('Photo evidence', {font: bold, size: 17, color: navy, spacing: 22});
    paragraph('Reduced-size previews of technician-supplied records.', {size: 9, color: muted});
  }
  for (const p of photoCaptions) {
    const captionLines = wrap(p.caption, regular, 9);
    const captionHeight = p.caption ? captionLines.length * 13 + 8 : 0;
    ensure(255 + captionHeight);
    paragraph(p.title, {font: bold, size: 11, color: cyan, spacing: 18});
    const image = await pdf.embedJpg(p.image), scale = Math.min(contentWidth / image.width, 200 / image.height);
    page.drawRectangle({x: left, y: y - 205, width: contentWidth, height: 205, color: pale});
    page.drawImage(image, {x: left + (contentWidth - image.width * scale) / 2, y: y - 202 + (200 - image.height * scale) / 2, width: image.width * scale, height: image.height * scale});
    y -= 215;
    if (p.caption) paragraph(p.caption, {size: 9, color: muted, spacing: 13});
    y -= 12;
  }
  pdf.getPages().forEach((p, index) => {
    p.drawLine({start: {x: left, y: 43}, end: {x: width - left, y: 43}, thickness: 0.5, color: rgb(0.8, 0.86, 0.89)});
    p.drawText(`KORLIX FIELDPROOF | Revision ${report.version}`, {x: left, y: 28, font: regular, size: 8, color: muted});
    p.drawText(`${index + 1} / ${pdf.getPageCount()}`, {x: width - 72, y: 28, font: regular, size: 8, color: muted});
  });
  pdf.setTitle(`KORLIX FieldProof - ${report.title}`); pdf.setAuthor('KORLIX FieldProof');
  // Immutable outbox payloads may be regenerated after an interrupted prepare.
  // Never let the renderer's wall clock change the bytes for the same snapshot.
  const parsedDate = Date.parse(report.snapshotAt);
  const reportDate = new Date(Number.isFinite(parsedDate) ? parsedDate : 0);
  pdf.setCreationDate(reportDate); pdf.setModificationDate(reportDate);
  const content = Buffer.from(await pdf.save());
  if (content.length > LIMITS.attachmentBytes) fail('This report exceeds the email attachment limit. Send it without photos.');
  return {content, pageCount: pdf.getPageCount(), fontFallback: fallback};
}

/** Customer report only. The caller owns authorization, consent and delivery. */
export async function renderFieldProofCustomerEmail({snapshot, previews = new Map(), includePhotos = false} = {}) {
  if (typeof includePhotos !== 'boolean') fail('Choose whether to include report photos.');
  const report = customerReport(snapshot, includePhotos);
  const photos = await normalizedPhotos(report.photos, previews);
  const pdf = await buildPdf(report, photos);
  const subject = singleLine(`FieldProof job report: ${report.title} - ${report.customer}`, 150);
  const html = `<!doctype html><html><body style="margin:0;background:#edf5f8;color:#23313b;font-family:Arial,sans-serif"><main style="max-width:680px;margin:24px auto;background:#fff;padding:28px"><div style="color:#087da0;font-size:13px;font-weight:bold">KORLIX FIELDPROOF</div><h1 style="font-size:24px;color:#102f43">${escapeHtml(report.title)}</h1>${report.sections.map(s => `<section><h2 style="font-size:17px;color:#087da0;margin-top:24px">${escapeHtml(s.heading)}</h2>${s.lines.map(line => `<p style="font-size:14px;line-height:1.5;white-space:pre-wrap;overflow-wrap:anywhere">${escapeHtml(line)}</p>`).join('')}</section>`).join('')}</main></body></html>`;
  return {
    subject, text: report.text, html,
    attachments: [{filename: `FieldProof-${filePart(report.customer)}-${filePart(report.workOrder === 'Not entered' ? report.title : report.workOrder)}-r${report.version}.pdf`, contentType: 'application/pdf', content: pdf.content}],
    report: {photoCount: photos.length, omittedPhotoCount: report.omittedPhotoCount, byteLength: pdf.content.length, pageCount: pdf.pageCount, fontFallback: pdf.fontFallback},
  };
}
