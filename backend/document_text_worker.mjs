import { parentPort, workerData } from 'node:worker_threads';
import yauzl from 'yauzl';
import { zipDirectory } from './archive_security.mjs';

const MAX_EXPANDED = 30 * 1024 * 1024;
const MAX_XML = 8 * 1024 * 1024;
const MAX_TEXT = 1_000_000;

async function inspectDocx(buffer) {
  zipDirectory(buffer);
  const zip = await yauzl.fromBufferPromise(buffer, { lazyEntries: true, validateEntrySizes: true, strictFileNames: true });
  let entries = 0, total = 0;
  const names = new Set();
  for await (const entry of zip.eachEntry()) {
    if (++entries > 1000 || names.has(entry.fileName) || entry.isEncrypted()) throw Error('archive');
    names.add(entry.fileName);
    const limit = /\.(xml|rels)$/i.test(entry.fileName) ? MAX_XML : MAX_EXPANDED;
    if (entry.uncompressedSize > limit || total + entry.uncompressedSize > MAX_EXPANDED) throw Error('archive');
    if (entry.fileName.endsWith('/')) continue;
    const stream = await zip.openReadStreamPromise(entry);
    let size = 0;
    // The stream validates actual decompressed length, including forged metadata.
    for await (const chunk of stream) {
      size += chunk.length;
      total += chunk.length;
      if (size > limit || total > MAX_EXPANDED) {
        stream.destroy();
        throw Error('archive');
      }
    }
  }
  if (!names.has('[Content_Types].xml') || !names.has('word/document.xml')) throw Error('archive');
}

try {
  const buffer = Buffer.from(workerData.bytes);
  let text;
  if (workerData.kind === 'pdf') {
    const { PDFParse } = await import('pdf-parse');
    const parser = new PDFParse({ data: buffer, isEvalSupported: false, useWorkerFetch: false, verbosity: 0 });
    try {
      const info = await parser.getInfo();
      if (info.total > 100) throw Error('pages');
      text = (await parser.getText()).text || '';
    } finally { await parser.destroy(); }
  } else {
    await inspectDocx(buffer);
    const { default: mammoth } = await import('mammoth');
    text = (await mammoth.extractRawText({ buffer })).value || '';
  }
  if (text.length > MAX_TEXT) throw Error('text');
  parentPort.postMessage({ ok: true, text });
} catch (error) {
  parentPort.postMessage({ ok: false, message: error.message === 'pages'
    ? 'Choose a PDF with 100 pages or fewer.'
    : 'This document could not be read safely. Try a smaller PDF or DOCX file.' });
}
