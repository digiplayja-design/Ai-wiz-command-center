import { createHash } from 'node:crypto';
export const attachmentBucket = 'korlix-social-attachments';
export const attachmentLimit = 20 * 1024 * 1024;
const bad = message => Object.assign(new Error(message), { status: 400 });
const links = new Map();

export async function validateAttachment(file, kind) {
  if (!file?.buffer?.length || file.buffer.length > attachmentLimit) throw bad('Choose a file smaller than 20 MB.');
  if (!['image', 'gif', 'sticker', 'file', 'voice'].includes(kind)) throw bad('Choose a photo, GIF, sticker, file or voice note.');
  let bytes = file.buffer;
  let filename = String(file.originalname || 'Attachment').replace(/[\x00-\x1f\x7f/\\<>:"|?*]/g, '_').slice(-140);
  let extension = filename.split('.').at(-1).toLowerCase(), content_type, duration_ms = null;
  if (kind === 'gif' || kind === 'sticker') {
    const gif = kind === 'gif';
    try {
      const { default: sharp } = await import('sharp');
      const image = sharp(bytes, { limitInputPixels: 32000000, animated: gif, failOn: 'warning' });
      const meta = await image.metadata();
      const frames = meta.pages || 1;
      if (gif ? meta.format !== 'gif' || frames > 160 : !['png', 'webp', 'jpeg'].includes(meta.format) || frames > 1) throw Error();
      if (gif && (meta.width > 2048 || (meta.pageHeight || meta.height) > 2048)) throw Error();
      const resized = image.resize(gif ? 640 : 512, gif ? 640 : 512, { fit: 'inside', withoutEnlargement: true }).timeout({ seconds: 15 });
      // Re-encode every frame, strip metadata, and retain sticker alpha. Store
      // as the existing image kind so older clients and access rules still work.
      bytes = await (gif ? resized.gif({ effort: 3 }) : resized.png()).toBuffer();
      if (bytes.length > attachmentLimit) throw Error();
    } catch { throw bad(gif ? 'Choose a GIF under 20 MB, 2048 pixels and 160 frames. Try a shorter or smaller GIF.' : 'Choose a still PNG, WebP or JPG sticker under 20 MB.'); }
    extension = gif ? 'gif' : 'png'; content_type = gif ? 'image/gif' : 'image/png';
    filename = filename.replace(/\.[^.]+$/, '').replace(/^Sticker - /i, '').slice(0, 125);
    filename = (gif ? '' : 'Sticker - ') + filename + '.' + extension;
    kind = 'image';
  } else if (kind === 'image') {
    try {
      const { default: sharp } = await import('sharp');
      const image = sharp(bytes, { limitInputPixels: 32000000, animated: false, failOn: 'error' });
      const meta = await image.metadata();
      if (!['jpeg', 'png', 'webp', 'heif'].includes(meta.format) || (meta.pages || 1) > 1) throw Error();
      bytes = await image.rotate().resize(2048, 2048, { fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 87 }).toBuffer();
    } catch { throw bad('That photo could not be opened. Choose a still JPG, PNG or WebP photo.'); }
    filename = filename.replace(/\.[^.]+$/, '') + '.jpg'; extension = 'jpg'; content_type = 'image/jpeg';
  } else if (kind === 'voice') {
    // Recorded PCM WAV is playable across Safari, Chrome, Android and iOS.
    if (bytes.length < 46 || bytes.toString('ascii', 0, 4) !== 'RIFF' || bytes.toString('ascii', 8, 12) !== 'WAVE' || bytes.toString('ascii', 12, 16) !== 'fmt ' || bytes.readUInt32LE(16) !== 16 || bytes.readUInt16LE(20) !== 1 || bytes.readUInt16LE(22) !== 1 || bytes.readUInt16LE(34) !== 16 || bytes.toString('ascii', 36, 40) !== 'data') throw bad('This voice note could not be read. Please record it again.');
    const rate = bytes.readUInt32LE(24), size = bytes.readUInt32LE(40);
    if (![16000, 24000, 44100, 48000].includes(rate) || size !== bytes.length - 44 || size % 2 || bytes.readUInt32LE(4) !== bytes.length - 8 || bytes.readUInt32LE(28) !== rate * 2 || bytes.readUInt16LE(32) !== 2) throw bad('This voice note is incomplete. Please record it again.');
    duration_ms = Math.round(size / (rate * 2) * 1000);
    if (duration_ms < 300 || duration_ms > 180000) throw bad('Record a voice note between a moment and 3 minutes.');
    filename = 'Voice note.wav'; extension = 'wav'; content_type = 'audio/wav';
  } else {
    const zip = ['zip', 'docx', 'xlsx', 'pptx'], ole = ['doc', 'xls', 'ppt'];
    if (extension === 'pdf' && bytes.subarray(0, 5).toString() === '%PDF-') content_type = 'application/pdf';
    else if (zip.includes(extension) && bytes[0] === 0x50 && bytes[1] === 0x4b && [3, 5, 7].includes(bytes[2])) content_type = 'application/octet-stream';
    else if (ole.includes(extension) && bytes.subarray(0, 8).equals(Buffer.from('d0cf11e0a1b11ae1', 'hex'))) content_type = 'application/octet-stream';
    else if (['txt', 'csv'].includes(extension)) {
      try { const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes); if (/[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(text)) throw Error(); } catch { throw bad('Choose a UTF-8 text or CSV file.'); }
      content_type = 'application/octet-stream';
    } else throw bad('Choose a PDF, Word, Excel, PowerPoint, TXT, CSV or ZIP file. Use Photo for images.');
  }
  return { bytes, metadata: { kind, filename, extension, content_type, size_bytes: bytes.length, duration_ms, checksum: createHash('sha256').update(bytes).digest('hex') } };
}

// Only metadata returned by the access-checked RPC can become a signed URL.
export async function socialAttachments(database, result) {
  const found = [];
  const walk = x => {
    if (!x || typeof x !== 'object') return;
    if (x.attachment && typeof x.attachment === 'object') found.push(x.attachment);
    for (const [key, value] of Object.entries(x)) if (key !== 'attachment' && typeof value === 'object') walk(value);
  };
  walk(result);
  for (const a of found) {
    const path = a.object_path;
    delete a.object_path;
    if (typeof path !== 'string' || !/^[0-9a-f-]{36}\/[0-9a-f-]{36}\.[a-z0-9]{1,8}$/.test(path)) continue;
    // Document links are minted only on explicit download, always as attachments.
    // Wall audio is public to eligible Social viewers, but can be removed or
    // blocked. Recheck access at playback instead of caching a five-minute URL.
    if (a.kind === 'file' || a.scope === 'wall') continue;
    let link = links.get(path);
    if (!link || link.until < Date.now()) {
      const { data, error } = await database.storage.from(attachmentBucket).createSignedUrl(path, 300);
      if (!error && data?.signedUrl) { link = { url: data.signedUrl, until: Date.now() + 240000 }; links.set(path, link); }
    }
    if (link) a.url = link.url;
    while (links.size > 1000) links.delete(links.keys().next().value);
  }
  return result;
}

function storageError(error) {
  const status = { '42501': 403, P0002: 404, P0001: 400, '23505': 409, '23514': 400, '22P02': 400, '54000': 429 }[error?.code];
  return Object.assign(new Error(status ? error.message : 'The attachment could not be confirmed. Retry before changing the message.'), { status: status || 503 });
}

export function registerSocialAttachments(app, { database, authenticate, logger = console, maintenance = true }) {
  let cleaning = false;
  const uploadingUsers = new Set();
  const cleanup = async () => {
    if (cleaning || !database) return;
    cleaning = true;
    try {
      const result = await database.rpc('korlix_social_attachment_cleanup', {});
      if (result.error || !result.data?.length) return;
      const paths = result.data.map(x => x.path);
      const removed = await database.storage.from(attachmentBucket).remove(paths);
      if (!removed.error) {
        await database.rpc('korlix_social_attachment_cleanup', { p_ids: result.data.map(x => x.id) });
        for (const path of paths) links.delete(path);
      }
    } catch { logger.warn('Social attachment cleanup will retry.'); }
    finally { cleaning = false; }
  };
  if (maintenance) {
    const timer = setInterval(() => { void cleanup(); }, 30 * 60 * 1000); timer.unref?.();
    const start = setTimeout(() => { void cleanup(); }, 15000); start.unref?.();
  }
  const rpc = async (user, action, data) => {
    const result = await database.rpc('korlix_social_attachment_v1', { p_actor: user.id, p_action: action, p_data: data });
    if (result.error) throw storageError(result.error);
    if (!result.data) throw storageError();
    return result.data;
  };
  app.post('/api/social/attachment_upload', async (req, res) => {
    res.set('Cache-Control', 'no-store');
    let uploadOwner;
    try {
      const user = await authenticate(req, res); if (!user) return;
      if (uploadingUsers.has(user.id) || uploadingUsers.size >= 2) throw Object.assign(new Error('Uploads are busy. Please try again in a moment.'), {status: 429});
      uploadOwner = user.id; uploadingUsers.add(uploadOwner);
      const destinations = ['peer', 'group', 'topic'].filter(key => req.query[key] != null);
      if (destinations.length !== 1 || typeof req.query[destinations[0]] !== 'string') throw bad('Choose one conversation or wall post.');
      const destination = { [destinations[0]]: req.query[destinations[0]] };
      if (destination.topic && req.query.kind !== 'voice') throw bad('Wall replies support recorded voice notes.');
      await rpc(user, 'access', destination);
      const { default: multer } = await import('multer');
      const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: attachmentLimit, files: 1, fields: 0, parts: 2 } }).single('file');
      try { await new Promise((resolve, reject) => upload(req, res, e => e ? reject(e) : resolve())); }
      catch { throw bad('Choose one attachment smaller than 20 MB.'); }
      const { bytes, metadata } = await validateAttachment(req.file, req.query.kind);
      const prepared = await rpc(user, 'prepare', { ...destination, ...metadata, id: req.query.id });
      if (prepared.state === 'uploading') {
        const result = await database.storage.from(attachmentBucket).upload(prepared.attachment.object_path, bytes, { contentType: metadata.content_type, cacheControl: '300', upsert: false });
        // A retry of the same immutable checksum may encounter an existing object.
        const duplicate = result.error && (String(result.error.statusCode) === '409' ||
          (String(result.error.statusCode) === '400' && /already exists|duplicate/i.test(`${result.error.error || ''} ${result.error.message || ''}`)));
        if (result.error && !duplicate) throw storageError();
      }
      const ready = await rpc(user, 'ready', { id: req.query.id });
      res.json(await socialAttachments(database, ready));
    } catch (error) { res.status(error.status || 503).json({ error: error.status ? error.message : 'Attachment upload could not be confirmed. Retry with the same file.' }); }
    finally { if (uploadOwner) uploadingUsers.delete(uploadOwner); }
  });
  app.get('/api/social/attachment_link', async (req, res) => {
    res.set('Cache-Control', 'no-store');
    try {
      const user = await authenticate(req, res); if (!user) return;
      const { attachment } = await rpc(user, 'link', { id: req.query.id });
      const download = req.query.download === 'true' || attachment.kind === 'file';
      const result = await database.storage.from(attachmentBucket).createSignedUrl(attachment.object_path, download || attachment.scope === 'wall' ? 60 : 300, download ? { download: attachment.filename } : {});
      if (result.error || !result.data?.signedUrl) throw storageError();
      res.json({ url: result.data.signedUrl });
    } catch (error) { res.status(error.status || 503).json({ error: error.status ? error.message : 'Attachment could not be opened.' }); }
  });
  app.post('/api/social/attachment_discard', async (req, res) => {
    res.set('Cache-Control', 'no-store');
    try {
      const user = await authenticate(req, res); if (!user) return;
      const result = await rpc(user, 'discard', { id: req.body?.id });
      res.json(result); if (maintenance) void cleanup();
    } catch (error) { res.status(error.status || 503).json({ error: error.status ? error.message : 'Attachment could not be removed.' }); }
  });
  return { cleanup };
}
