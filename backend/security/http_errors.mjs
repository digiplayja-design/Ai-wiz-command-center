// Handle parser, multipart, and unexpected failures without exposing stack
// traces, submitted bodies, or upstream diagnostic text to API callers.
export function publicApiErrorHandler(error, _req, res, next) {
  if (res.headersSent) return next(error);
  let status = Number(error?.statusCode || error?.status || 500);
  if (!Number.isInteger(status) || status < 400 || status > 599) status = 500;
  let code = 'request_failed';
  let message = status >= 500
    ? 'The request could not be completed. Please try again.'
    : 'The request could not be accepted. Check your input and try again.';

  if (error?.type === 'entity.parse.failed') {
    status = 400;
    code = 'invalid_json';
    message = 'Send a valid JSON request.';
  } else if (error?.type === 'entity.too.large'
      || ['LIMIT_FILE_SIZE', 'LIMIT_FILE_COUNT', 'LIMIT_FIELD_COUNT',
        'LIMIT_FIELD_VALUE', 'LIMIT_PART_COUNT'].includes(error?.code)) {
    status = 413;
    code = 'request_too_large';
    message = 'This upload is too large or contains too many files or fields.';
  } else if (error?.name === 'MulterError') {
    status = 400;
    code = 'invalid_upload';
    message = 'Check the selected files and try again.';
  }

  res.setHeader('Cache-Control', 'no-store');
  return res.status(status).json({ok: false, code, error: message});
}
