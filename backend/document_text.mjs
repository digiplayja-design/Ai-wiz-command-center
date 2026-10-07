import { Worker } from 'node:worker_threads';

const failure = message => Object.assign(new Error(message), { statusCode: 422 });
let activeWorkers = 0;

export async function extractUploadedDocumentText(file) {
  const buffer = file?.buffer;
  if (!buffer?.length || buffer.length > 15 * 1024 * 1024) {
    throw failure('Choose a nonempty document smaller than 15 MB.');
  }
  const name = String(file.originalname || '').toLowerCase();
  const mime = String(file.mimetype || '').toLowerCase();
  const kind = name.endsWith('.pdf') || mime.includes('pdf') ? 'pdf'
    : name.endsWith('.docx') || mime.includes('wordprocessingml.document') ? 'docx'
    : /\.(txt|md|csv)$/.test(name) || mime.includes('text/') || mime.includes('csv') ? 'text' : null;
  if (!kind) return '';
  if (kind === 'text') return buffer.toString('utf8');
  if (kind === 'pdf' && buffer.subarray(0, 1024).indexOf('%PDF-') < 0) {
    throw failure('This file is not a readable PDF. Export it as a PDF and try again.');
  }
  if (activeWorkers >= 2) {
    throw Object.assign(new Error('Document processing is busy. Please try again in a moment.'), { statusCode: 429 });
  }

  // Keep malformed archives/XML/PDF work away from the HTTP event loop, with
  // a deadline and an isolated heap. No file path or remote URL reaches the parser.
  return new Promise((resolve, reject) => {
    const worker = new Worker(new URL('./document_text_worker.mjs', import.meta.url), {
      workerData: { kind, bytes: buffer },
      resourceLimits: { maxOldGenerationSizeMb: 128, maxYoungGenerationSizeMb: 16 },
    });
    activeWorkers++;
    worker.once('exit', () => { activeWorkers--; });
    let settled = false;
    const finish = (error, text) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      // Await teardown so a sequential upload cannot lose its processing slot
      // to a worker that already returned a result but has not stopped yet.
      void worker.terminate().then(
        () => error ? reject(error) : resolve(text),
        () => reject(error || failure('This document could not be read safely. Try a smaller PDF or DOCX file.')),
      );
    };
    const timer = setTimeout(() => finish(failure('This document took too long to read. Try a smaller PDF or DOCX file.')), 15_000);
    worker.once('message', result => result.ok
      ? finish(null, result.text)
      : finish(failure(result.message)));
    worker.once('error', () => finish(failure('This document could not be read safely. Try a smaller PDF or DOCX file.')));
    worker.once('exit', () => { if (!settled) finish(failure('This document could not be read safely. Try a smaller PDF or DOCX file.')); });
  });
}
