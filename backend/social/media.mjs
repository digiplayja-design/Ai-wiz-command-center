import { randomUUID } from 'node:crypto';

export const avatarBucket = 'korlix-social-avatars';
const signedPhotos = new Map();
// Resolve only paths emitted by our authorized RPC. No arbitrary URL proxying.
export async function socialPhotos(database, result) {
  const paths = new Set();
  const walk = (value, visit) => {
    if (!value || typeof value !== 'object') return;
    if (typeof value.avatar_path === 'string' && /^[0-9a-f-]{36}\/[0-9a-f-]{36}\.jpg$/.test(value.avatar_path)) visit(value);
    for (const item of Object.values(value)) if (typeof item === 'object') walk(item, visit);
  };
  walk(result, value => paths.add(value.avatar_path));
  if (!paths.size) return result;
  const missing = [...paths].filter(path => (signedPhotos.get(path)?.until || 0) < Date.now());
  if (missing.length) {
    const { data, error } = await database.storage.from(avatarBucket).createSignedUrls(missing, 600);
    if (!error) for (const item of data || []) {
      if (item.signedUrl) signedPhotos.set(item.path, { url: item.signedUrl, until: Date.now() + 420000 });
    }
    while (signedPhotos.size > 1000) signedPhotos.delete(signedPhotos.keys().next().value);
  }
  const links = new Map([...paths].map(path => [path, signedPhotos.get(path)?.url]));
  walk(result, value => { value.avatar_url = links.get(value.avatar_path) || null; delete value.avatar_path; });
  return result;
}

export function registerSocialPhotos(app, { database, authenticate, logger = console }) {
  // Authenticate before allocating any multipart buffers. Imports are lazy for
  // independent route tests and don't alter the backend's other upload limits.
  app.post('/api/social/profile_photo', async (req, res) => {
    res.set('Cache-Control', 'no-store');
    let uploaded;
    try {
      const user = await authenticate(req, res);
      if (!user) return;
      const begin = await database.rpc('korlix_social_avatar', { p_actor: user.id, p_action: 'begin' });
      if (begin.error) return res.status(begin.error.code === '54000' ? 429 : 403).json({ error: begin.error.message });
      const bucket = database.storage.from(avatarBucket);
      if (req.is('application/json') && req.body?.remove === true) {
        const saved = await database.rpc('korlix_social_avatar', { p_actor: user.id, p_action: 'save', p_path: null });
        if (saved.error) throw Error('save');
        if (saved.data.old_path) await bucket.remove([saved.data.old_path]);
        return res.json(await socialPhotos(database, { profile: saved.data.profile }));
      }
      const { default: multer } = await import('multer');
      const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 8 * 1024 * 1024, files: 1, fields: 0, parts: 2 } }).single('photo');
      try { await new Promise((resolve, reject) => upload(req, res, e => e ? reject(e) : resolve())); }
      catch { return res.status(400).json({ error: 'Choose one JPG, PNG or WebP photo smaller than 8 MB.' }); }
      if (!req.file?.buffer) return res.status(400).json({ error: 'Choose a profile photo first.' });
      let jpeg;
      try {
        const { default: sharp } = await import('sharp');
        const image = sharp(req.file.buffer, { limitInputPixels: 32000000, animated: false, failOn: 'error' });
        const metadata = await image.metadata();
        if (!['jpeg', 'png', 'webp'].includes(metadata.format) || (metadata.pages || 1) > 1) throw Error('format');
        jpeg = await image.rotate().resize(512, 512, { fit: 'cover' }).jpeg({ quality: 86 }).toBuffer();
      } catch { return res.status(400).json({ error: 'That image could not be opened. Choose a still JPG, PNG or WebP photo.' }); }
      uploaded = `${begin.data.profile_id}/${randomUUID()}.jpg`;
      const put = await bucket.upload(uploaded, jpeg, { contentType: 'image/jpeg', upsert: false, cacheControl: '600' });
      if (put.error) throw Error('upload');
      const saved = await database.rpc('korlix_social_avatar', { p_actor: user.id, p_action: 'save', p_path: uploaded });
      if (saved.error) throw Error('save');
      uploaded = null; // The new object now belongs to the saved profile.
      if (saved.data.old_path) await bucket.remove([saved.data.old_path]);
      res.json(await socialPhotos(database, { profile: saved.data.profile }));
    } catch {
      if (uploaded) await database.storage.from(avatarBucket).remove([uploaded]).catch(() => {});
      logger.warn('Social photo update could not be confirmed');
      res.status(503).json({ error: 'Your photo could not be saved. Refresh your profile before retrying.' });
    }
  });
}
