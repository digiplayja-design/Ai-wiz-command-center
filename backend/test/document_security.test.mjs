import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import express from 'express';
import { PDFDocument, StandardFonts } from 'pdf-lib';
import { Document, Paragraph, Packer } from 'docx';
import ExcelJS from 'exceljs';
import { createDocumentUpload, documentUploadLimits } from '../document_upload.mjs';
import { extractUploadedDocumentText } from '../document_text.mjs';
import { previewImport } from '../contacts_crm/imports.mjs';

const require = createRequire(import.meta.url);
const JSZip = require('jszip');
const file = (buffer, originalname) => ({ buffer, originalname });

test('PDF v2 extraction returns uploaded document text and rejects excessive pages', async () => {
  const pdf = await PDFDocument.create();
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  pdf.addPage().drawText('Pre-release document verification', { x: 20, y: 700, font });
  assert.match(await extractUploadedDocumentText(file(Buffer.from(await pdf.save()), 'receipt.pdf')), /Pre-release document verification/);
  for (let i = 1; i < 101; i++) pdf.addPage();
  await assert.rejects(extractUploadedDocumentText(file(Buffer.from(await pdf.save()), 'large.pdf')), /100 pages/);
  await assert.rejects(extractUploadedDocumentText(file(Buffer.from('<html>not a PDF</html>'), 'fake.pdf')), /not a readable PDF/);
});

test('DOCX extraction survives dependency overrides and rejects expanded archives', async () => {
  const bytes = await Packer.toBuffer(new Document({ sections: [{ children: [new Paragraph('Safe DOCX contents')] }] }));
  assert.match(await extractUploadedDocumentText(file(bytes, 'brief.docx')), /Safe DOCX contents/);
  const zip = await JSZip.loadAsync(bytes);
  zip.file('word/document.xml', 'A'.repeat(8 * 1024 * 1024 + 1));
  const bomb = await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' });
  assert(bomb.length < 100_000);
  await assert.rejects(extractUploadedDocumentText(file(bomb, 'compressed.docx')), /could not be read safely/);
  await assert.rejects(extractUploadedDocumentText(file(Buffer.from('not a zip'), 'malformed.docx')), /could not be read safely/);
});

test('forged ZIP expanded lengths are rejected while streaming before DOCX parsing', async () => {
  const zip = new JSZip();
  zip.file('[Content_Types].xml', '<Types/>');
  zip.file('word/document.xml', 'A'.repeat(200_000));
  const bytes = await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' });
  let offset = 0;
  while ((offset = bytes.indexOf(Buffer.from('504b0102', 'hex'), offset)) >= 0) {
    const nameLength = bytes.readUInt16LE(offset + 28);
    if (bytes.toString('utf8', offset + 46, offset + 46 + nameLength) === 'word/document.xml') bytes.writeUInt32LE(1, offset + 24);
    offset += 46 + nameLength;
  }
  await assert.rejects(extractUploadedDocumentText(file(bytes, 'forged.docx')), /could not be read safely/);
});

test('ExcelJS conditional-formatting UUID path writes and reads XLSX with patched uuid', async () => {
  const book = new ExcelJS.Workbook(), sheet = book.addWorksheet('Audit');
  sheet.addRows([['Amount'], [25], [100]]);
  sheet.addConditionalFormatting({ ref: 'A2:A3', rules: [{ type: 'dataBar', minLength: 0, maxLength: 100,
    cfvo: [{ type: 'min' }, { type: 'max' }], color: { argb: 'FF33AA99' } }] });
  const bytes = await book.xlsx.writeBuffer();
  const archive = await JSZip.loadAsync(bytes);
  const xml = await archive.file('xl/worksheets/sheet1.xml').async('string');
  assert.match(xml, /[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}/);
  const loaded = new ExcelJS.Workbook();
  await loaded.xlsx.load(bytes);
  assert.equal(loaded.getWorksheet('Audit').getCell('A3').value, 100);
  const lock = JSON.parse(await readFile(new URL('../package-lock.json', import.meta.url)));
  assert.equal(lock.packages['node_modules/sprintf-js'], undefined);
});

test('ZIP entry-count mismatch cannot bypass document or CRM decompression preflight', async () => {
  const doc = await Packer.toBuffer(new Document({ sections: [{ children: [new Paragraph('Valid contents')] }] }));
  const badDoc = Buffer.from(doc), docEnd = badDoc.length - 22;
  assert.equal(badDoc.readUInt32LE(docEnd), 0x06054b50);
  badDoc.writeUInt16LE(badDoc.readUInt16LE(docEnd + 10) - 1, docEnd + 8);
  badDoc.writeUInt16LE(badDoc.readUInt16LE(docEnd + 10) - 1, docEnd + 10);
  await assert.rejects(extractUploadedDocumentText(file(badDoc, 'hidden-entry.docx')), /could not be read safely/);

  const book = new ExcelJS.Workbook();
  book.addWorksheet('Contacts').addRows([['Name', 'Email'], ['Alex', 'alex@example.com']]);
  const bytes = Buffer.from(await book.xlsx.writeBuffer());
  // ExcelJS/JSZip scans the directory regardless of this count; the old preflight
  // iterated zero times and allowed every compressed entry into ExcelJS unchecked.
  bytes.writeUInt16LE(0, bytes.length - 22 + 8);
  bytes.writeUInt16LE(0, bytes.length - 22 + 10);
  const unchecked = new ExcelJS.Workbook(); await unchecked.xlsx.load(bytes);
  assert.equal(unchecked.getWorksheet('Contacts').getCell('A2').value, 'Alex');
  let enteredParser = false;
  await assert.rejects(previewImport({ source: 'spreadsheet', filename: 'contacts.xlsx', content: bytes.toString('base64') }, {
    loadWorkbook: async () => { enteredParser = true; return unchecked; },
  }), /not a valid Excel workbook/);
  assert.equal(enteredParser, false);
});

test('multipart requires identity, caps fields and files, and holds per-user/global slots', async () => {
  const app = express(), held = new Map();
  const upload = createDocumentUpload();
  app.post('/upload', (req, _res, next) => {
    if (req.headers.authorization) req.korlixDocumentUploadUser = { id: req.headers.authorization };
    next();
  }, upload.array('files', 8), (req, res) => {
    if (req.query.hold) held.set(req.korlixDocumentUploadUser.id, res);
    else res.json({ files: req.files.length });
  });
  app.use((error, _req, res, _next) => res.status(400).json({ code: error.code }));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const url = `http://127.0.0.1:${server.address().port}/upload`;
  const send = (user, form = new FormData(), suffix = '') => fetch(url + suffix, { method: 'POST', headers: user ? { Authorization: user } : {}, body: form });
  const heldRequests = [];
  try {
    assert.equal((await send(null)).status, 401);
    const fields = new FormData();
    for (let i = 0; i < 25; i++) fields.append('field' + i, 'x');
    assert.equal((await (await send('a', fields)).json()).code, 'LIMIT_FIELD_COUNT');
    const long = new FormData(); long.append('prompt', 'x'.repeat(documentUploadLimits.fieldSize + 1));
    assert.equal((await (await send('a', long)).json()).code, 'LIMIT_FIELD_VALUE');
    const files = new FormData();
    for (let i = 0; i < 9; i++) files.append('files', new Blob(['x']), 'test.txt');
    assert.equal((await (await send('a', files)).json()).code, 'LIMIT_FILE_COUNT');
    for (const user of ['a', 'b']) {
      heldRequests.push(send(user, new FormData(), '?hold=1'));
      for (let i = 0; !held.has(user) && i < 100; i++) await new Promise(resolve => setTimeout(resolve, 5));
      assert(held.has(user));
      if (user === 'a') assert.equal((await send('a')).status, 429);
    }
    const busy = await send('c');
    assert.equal(busy.status, 429); assert.equal(busy.headers.get('retry-after'), '5');
    held.get('a').json({ finished: true });
    await heldRequests[0];
    assert.equal((await send('c')).status, 200);
    held.get('b').json({ finished: true });
    await heldRequests[1];
    assert.equal((await send('a')).status, 200);
  } finally {
    for (const res of held.values()) if (!res.writableEnded) res.end();
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
});
