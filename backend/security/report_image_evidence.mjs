import sharp from 'sharp';
import {createHash} from 'node:crypto';

export const maxReportImageInputBytes = 1024 * 1024;
export const maxReportImageBytes = 512 * 1024;
const invalid = () => Object.assign(new Error('The report image could not be read.'), {statusCode:400});
const tooLarge = () => Object.assign(new Error('The report image is too large.'), {statusCode:413});

// Only this field has a separate size budget. Other/unknown fields retain the
// normal metadata limit. Never retrieve a client-supplied URL on the server.
export function validateReportImageInput(value, contentType) {
  if (value === undefined || value === null) return;
  if (typeof value !== 'string' || contentType !== 'image') throw invalid();
  if (value.length > 64 + 4 * Math.ceil(maxReportImageInputBytes / 3)) throw tooLarge();
  if (!/^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}$/.test(value)) throw invalid();
  const encoded = value.slice(value.indexOf(',') + 1);
  const bytes = Buffer.from(encoded, 'base64');
  if (!bytes.length || bytes.toString('base64') !== encoded) throw invalid();
  if (bytes.length > maxReportImageInputBytes) throw tooLarge();
}

export async function prepareReportImageEvidence(value) {
  if (value === undefined || value === null) return null;
  validateReportImageInput(value, 'image');
  const bytes = Buffer.from(value.slice(value.indexOf(',') + 1), 'base64');
  const options = {limitInputPixels:4 * 1024 * 1024, failOn:'warning'};
  try {
    const metadata = await sharp(bytes, options).metadata();
    const declared = value.slice(11, value.indexOf(';'));
    if (!['png','jpeg','webp'].includes(metadata.format) || metadata.format !== declared || (metadata.pages || 1) !== 1) throw invalid();
    for (const dimension of [1280, 960, 640]) {
      // Re-encode all input: strip EXIF/GPS and discard any trailing payload.
      const {data, info} = await sharp(bytes, options).rotate()
        .resize({width:dimension,height:dimension,fit:'inside',withoutEnlargement:true})
        .flatten({background:'#ffffff'}).jpeg({quality:84})
        .toBuffer({resolveWithObject:true});
      if (data.length <= maxReportImageBytes) return {
        version:1, mimeType:'image/jpeg', base64:data.toString('base64'),
        byteLength:data.length, width:info.width, height:info.height,
        sha256:createHash('sha256').update(data).digest('hex'),
      };
    }
    throw tooLarge();
  } catch (error) {
    if (error?.statusCode === 413) throw error;
    throw invalid();
  }
}

export function reportImageMetadata(evidence) {
  if (!evidence) return null;
  const {version,mimeType,byteLength,width,height,sha256} = evidence;
  return {version,mimeType,byteLength,width,height,sha256};
}

export function reportImageAttachments(evidence) {
  return evidence ? [{filename:'reported-image.jpg',content:evidence.base64,
    content_type:'image/jpeg',content_id:'reported-image'}] : [];
}
