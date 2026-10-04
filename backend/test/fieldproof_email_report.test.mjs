import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import {PDFDocument} from 'pdf-lib';
import {PDFParse} from 'pdf-parse';
import {renderFieldProofCustomerEmail, FIELDPROOF_EMAIL_REPORT_LIMITS as LIMITS} from '../fieldproof/email_report.mjs';

const snapshot = () => ({
  job: {id: '90e7e695-c762-4662-910e-bcba51c71f0b', version: 7, state: 'completed', data: {
    title: 'Meter replacement / réparation', customer: 'José & Ana Müller', site: '12 Église Street, Kingston',
    workOrder: 'WO-000125', technician: 'François', performedOn: '2026-10-03',
    assetId: '000074.050-A', oldAssetId: '00000042', summary: 'Replaced the meter and recorded readings.',
    materials: '1 meter; 2 gaskets', exceptions: 'Customer requested a follow-up.', requiresApproval: true,
    billingNotes: 'INTERNAL_BILLING_SECRET', hours: 19.99, technicianNotes: 'INTERNAL_TECHNICIAN_SECRET',
    checks: [{label: 'Work area cleared', required: true, done: true}, {label: 'Customer handover', required: false, done: false}],
    readings: [{label: 'Initial register', value: '00001.0500', unit: 'm³', note: 'INTERNAL_READING_NOTE'}, {label: 'SNR', value: '-08.00 ± 0.50', unit: 'dB'}],
    issues: [{label: 'Recheck the boundary valve', resolved: false, blocking: true, dueOn: '2026-10-10', assignee: 'INTERNAL_ASSIGNEE'}, {label: 'Old leak', resolved: true}],
  }, approval: {name: 'Ana Müller', version: 6, recordedAt: '2026-10-02T18:00:00Z', note: 'INTERNAL_APPROVAL_NOTE', recordedBy: 'INTERNAL_APPROVER_ID'}},
  snapshotAt: '2026-10-03T19:30:00Z',
  evidence: [{id: 'photo-1', state: 'ready', tag: 'before', name: 'INTERNAL_FILE_NAME.jpg', note: 'INTERNAL_PHOTO_NOTE', previewUrl: 'https://private.example/secret?token=UNSIGNED_PRIVATE_URL', preview_path: 'PRIVATE_STORAGE_PATH'}],
  reviews: [{result: {customerReport: 'UNAPPROVED_AI_REVIEW', invoiceHandoff: 'AI_BILLING_SECRET'}}],
  events: [{action: 'PRIVATE_EVENT'}],
});
const extractText = async bytes => {
  const parser = new PDFParse({data: bytes});
  try {return (await parser.getText()).text;} finally {await parser.destroy();}
};
const jpeg = () => sharp({create: {width: 320, height: 180, channels: 3, background: '#087da0'}}).jpeg().toBuffer();

test('customer text, HTML and selectable PDF preserve Latin accents, serials and entered precision', async () => {
  const result = await renderFieldProofCustomerEmail({snapshot: snapshot()});
  assert.equal(result.attachments.length, 1);
  const attachment = result.attachments[0];
  assert.equal(attachment.contentType, 'application/pdf');
  assert.ok(Buffer.isBuffer(attachment.content));
  assert.equal(attachment.content.subarray(0, 5).toString(), '%PDF-');
  const pdfText = await extractText(attachment.content);
  for (const exact of ['réparation', 'José', 'Müller', 'François', '000074.050-A', '00000042', '00001.0500', '-08.00 ± 0.50', 'm³']) {
    assert.ok(result.text.includes(exact), `text retains ${exact}`);
    assert.ok(result.html.includes(exact), `HTML retains ${exact}`);
    assert.ok(pdfText.includes(exact), `PDF retains ${exact}`);
  }
  assert.equal(result.report.fontFallback, false);
  assert.equal(result.report.photoCount, 0);
  assert.equal(result.report.omittedPhotoCount, 1);
  assert.match(result.text, /photo sharing is off/);
  assert.match(result.text, /does not match this report revision/);
  assert.match(result.text, /not an independently verified signature/);
  assert.match(result.text, /does not independently certify/);
  assert.match(result.text, /Marked as blocking closeout/);
  assert.match(result.text, /Not marked complete: Customer handover/);
  assert.equal(result.report.byteLength, attachment.content.length);
  assert.equal(result.report.pageCount, (await PDFDocument.load(attachment.content)).getPageCount());
});

test('customer output is a whitelist: billing, notes, AI drafts, private metadata and URLs never leak', async () => {
  const result = await renderFieldProofCustomerEmail({snapshot: snapshot()});
  const all = [result.subject, result.text, result.html, result.attachments[0].filename, await extractText(result.attachments[0].content)].join('\n');
  for (const secret of ['INTERNAL_', 'PRIVATE_', 'UNSIGNED_PRIVATE_URL', 'UNAPPROVED_AI_REVIEW', 'AI_BILLING_SECRET', '19.99', 'private.example']) assert.ok(!all.includes(secret), secret);
  assert.ok(!result.html.includes('<img'));
  assert.ok(!result.html.includes('href='));
});

test('HTML escapes user markup and header/filename cannot contain newline or path injection', async () => {
  const input = snapshot();
  input.job.data.title = '<img src=x onerror="bad()"> & <script>oops</script>\r\nBcc: unwanted@example.com';
  input.job.data.customer = '../Ana <script>alert(1)</script>\r\nX-Bad: bad';
  const result = await renderFieldProofCustomerEmail({snapshot: input});
  assert.ok(result.text.includes(input.job.data.title));
  assert.ok(result.html.includes('&lt;img src=x onerror=&quot;bad()&quot;&gt;'));
  assert.ok(!result.html.includes('<script>'));
  assert.ok(!result.html.includes('<img src=x'));
  assert.ok(!/[\r\n]/.test(result.subject));
  assert.ok([...result.subject].length <= 150);
  assert.match(result.attachments[0].filename, /^FieldProof-[a-z0-9-]+-r7\.pdf$/i);
  assert.ok(result.attachments[0].filename.length < 105);
});

test('unsupported glyphs have an explicit PDF fallback while UTF-8 email remains exact', async () => {
  const input = snapshot(); input.job.data.assetId = '00001-🚚-東京';
  const result = await renderFieldProofCustomerEmail({snapshot: input});
  assert.ok(result.text.includes('00001-🚚-東京'));
  assert.ok(result.html.includes('00001-🚚-東京'));
  assert.equal(result.report.fontFallback, true);
  const text = await extractText(result.attachments[0].content);
  assert.ok(text.includes('[U+1F69A]'));
  assert.ok(text.includes('email body preserves the original text'));
});

test('photo bytes are optional and never fetched through snapshot URLs', async () => {
  const input = snapshot(); input.evidence[0].previewUrl = 'http://127.0.0.1:1/private';
  await assert.rejects(renderFieldProofCustomerEmail({snapshot: input, includePhotos: true}), /preview is missing/);
  const result = await renderFieldProofCustomerEmail({snapshot: input, includePhotos: true, previews: new Map([['photo-1', await jpeg()]])});
  assert.equal(result.report.photoCount, 1);
  assert.equal(result.report.omittedPhotoCount, 0);
  assert.ok(!result.text.includes('127.0.0.1'));
  assert.match(await extractText(result.attachments[0].content), /1\. Before work/);
});

test('photo previews discard EXIF and expose only explicitly public captions', async () => {
  const input = snapshot(); input.evidence[0].publicCaption = 'Before work: façade <north>';
  const photo = await sharp(await jpeg()).withExif({IFD0: {ImageDescription: 'PRIVATE_PHOTO_METADATA', Artist: 'PRIVATE_PHOTOGRAPHER'}}).jpeg().toBuffer();
  assert.ok(photo.includes(Buffer.from('PRIVATE_PHOTO_METADATA')));
  const result = await renderFieldProofCustomerEmail({snapshot: input, includePhotos: true, previews: new Map([['photo-1', photo]])});
  const attachment = result.attachments[0].content;
  assert.ok(!attachment.includes(Buffer.from('PRIVATE_PHOTO_METADATA')));
  assert.ok(!attachment.includes(Buffer.from('PRIVATE_PHOTOGRAPHER')));
  const text = await extractText(attachment);
  assert.match(text, /Before work: façade <north>/);
  assert.ok(!text.includes('INTERNAL_PHOTO_NOTE'));
});

test('photo count cap and attachment/page bounds are enforced and omissions disclosed', async () => {
  const input = snapshot(), image = await jpeg();
  input.evidence = Array.from({length: 24}, (_, i) => ({id: `p-${i}`, tag: i % 2 ? 'after' : 'before', state: 'ready'}));
  const previews = new Map(input.evidence.map(p => [p.id, image]));
  const result = await renderFieldProofCustomerEmail({snapshot: input, includePhotos: true, previews});
  assert.equal(result.report.photoCount, LIMITS.photos);
  assert.equal(result.report.omittedPhotoCount, 12);
  assert.match(result.text, /12 saved photo\(s\) omitted/);
  assert.ok(result.report.pageCount <= LIMITS.pages);
  assert.ok(result.report.byteLength <= LIMITS.attachmentBytes);
  const text = await extractText(result.attachments[0].content);
  assert.match(text, /12\. Completed work/);
  assert.ok(!text.includes('13. Before work'));
});

test('unsafe, oversized or missing preview input fails before an attachment can be sent', async () => {
  const input = snapshot();
  for (const bad of ['https://private.example/file.jpg', Buffer.alloc(LIMITS.previewBytes + 1), Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><rect width="20" height="20"/></svg>'), Buffer.from('not an image')]) {
    await assert.rejects(renderFieldProofCustomerEmail({snapshot: input, includePhotos: true, previews: new Map([['photo-1', bad]])}), /preview|attachment limit/);
  }
  const oversizedPixels = await sharp({create: {width: 1500, height: 1500, channels: 3, background: '#fff'}}).jpeg().toBuffer();
  await assert.rejects(renderFieldProofCustomerEmail({snapshot: input, includePhotos: true, previews: new Map([['photo-1', oversizedPixels]])}), /unreadable/);
});

test('combined input byte cap applies across individually valid selected previews', async () => {
  const input = snapshot(), image = await jpeg();
  const padded = Buffer.concat([image, Buffer.alloc(LIMITS.previewBytes - image.length)]);
  input.evidence = Array.from({length: 9}, (_, i) => ({id: `p-${i}`, state: 'ready'}));
  await assert.rejects(renderFieldProofCustomerEmail({snapshot: input, includePhotos: true, previews: new Map(input.evidence.map(p => [p.id, padded]))}), /attachment limit/);
});

test('bounded saved fields reject invalid data instead of truncating serials or coercing readings', async () => {
  const tooLong = snapshot(); tooLong.job.data.assetId = '0'.repeat(121);
  await assert.rejects(renderFieldProofCustomerEmail({snapshot: tooLong}), /asset serial/);
  const numeric = snapshot(); numeric.job.data.readings[0].value = 1.5;
  await assert.rejects(renderFieldProofCustomerEmail({snapshot: numeric}), /reading value/);
  const invalid = snapshot(); invalid.job.data.summary = 'work\u0000done';
  await assert.rejects(renderFieldProofCustomerEmail({snapshot: invalid}), /completed work/);
  await assert.rejects(renderFieldProofCustomerEmail({snapshot: snapshot(), includePhotos: 'yes'}), /whether to include/);
  await assert.rejects(renderFieldProofCustomerEmail(), /Refresh this job/);
});

test('long multilingual notes and unbroken identifiers paginate within the report boundary', async () => {
  const input = snapshot();
  input.job.data.summary = ('Réparation terminée. Lectura confirmada por el técnico. '.repeat(80)).slice(0, 3990);
  input.job.data.materials = 'B'.repeat(1900);
  input.job.data.readings = Array.from({length: 20}, (_, i) => ({label: `Reading ${i}`, value: '0'.repeat(150), unit: 'mm'}));
  const result = await renderFieldProofCustomerEmail({snapshot: input});
  assert.ok(result.report.pageCount > 1);
  assert.ok(result.report.pageCount <= LIMITS.pages);
  const text = await extractText(result.attachments[0].content);
  assert.ok(text.includes('Réparation terminée'));
  assert.ok(text.includes('Reading 19'));
  assert.ok(text.includes('About this report'));
});

test('identical snapshots and previews produce byte-identical immutable PDF payloads', async () => {
  const input = snapshot(), previews = new Map([['photo-1', await jpeg()]]);
  const first = await renderFieldProofCustomerEmail({snapshot: input, previews, includePhotos: true});
  const second = await renderFieldProofCustomerEmail({snapshot: structuredClone(input), previews, includePhotos: true});
  assert.deepEqual(first.attachments[0].content, second.attachments[0].content);
  assert.equal(first.text, second.text);
  assert.equal(first.html, second.html);
  const pdf = await PDFDocument.load(first.attachments[0].content, {updateMetadata: false});
  assert.equal(pdf.getCreationDate().toISOString(), new Date(input.snapshotAt).toISOString());
  assert.equal(pdf.getModificationDate().toISOString(), new Date(input.snapshotAt).toISOString());
});
