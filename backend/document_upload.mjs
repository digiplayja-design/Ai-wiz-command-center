import multer from 'multer';

export const documentUploadLimits = Object.freeze({
  fileSize: 15 * 1024 * 1024,
  files: 8,
  fields: 24,
  fieldSize: 128 * 1024,
  parts: 32,
});

// Authentication precedes these parsers. Keep the slot until the response ends:
// parsing is only the first stage that retains the uploaded buffers in memory.
export function createDocumentUpload() {
  const parser = multer({ storage: multer.memoryStorage(), limits: documentUploadLimits });
  let active = 0;
  const users = new Set();
  const wrap = middleware => (req, res, next) => {
    const user = req.korlixDocumentUploadUser || req.korlixVideoUser;
    if (!user?.id) return res.status(401).json({ error: 'Sign in before uploading a document.' });
    if (active >= 2 || users.has(user.id)) {
      res.set('Retry-After', '5');
      return res.status(429).json({ error: 'Document uploads are busy. Please try again in a moment.' });
    }
    active++;
    users.add(user.id);
    let released = false;
    const release = () => {
      if (released) return;
      released = true;
      active--;
      users.delete(user.id);
      res.off('finish', release);
      res.off('close', release);
    };
    res.once('finish', release);
    res.once('close', release);
    middleware(req, res, error => {
      if (error) release();
      next(error);
    });
  };
  return Object.freeze({
    single: name => wrap(parser.single(name)),
    array: (name, count) => wrap(parser.array(name, Math.min(count, documentUploadLimits.files))),
  });
}
