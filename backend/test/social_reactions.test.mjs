import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { validateAttachment, attachmentLimit } from '../social/attachments.mjs';

const gifBytes = async (frames = 3) => {
  const pixels = Buffer.alloc(16 * 16 * frames * 4);
  for (let f = 0; f < frames; f++) {
    for (let p = f * 16 * 16 * 4; p < (f + 1) * 16 * 16 * 4; p += 4) {
      pixels[p] = f % 2 ? 240 : 20; pixels[p + 1] = f % 2 ? 20 : 240;
      pixels[p + 2] = f; pixels[p + 3] = 255;
    }
  }
  return sharp(pixels, {raw:{width:16,height:16 * frames,channels:4,pageHeight:16}}).gif({loop:0,delay:Array(frames).fill(150)}).toBuffer();
};

test('GIF validation retains all animated frames and uses the existing private image model', async () => {
  const input = await gifBytes();
  const result = await validateAttachment({buffer:input,originalname:'Happy.gif'}, 'gif');
  const meta = await sharp(result.bytes, {animated:true}).metadata();
  assert.equal(meta.format, 'gif'); assert.equal(meta.pages, 3);
  assert.deepEqual(meta.delay, [150,150,150]); assert.equal(meta.loop, 0);
  assert.equal(result.metadata.kind, 'image');
  assert.equal(result.metadata.content_type, 'image/gif');
  assert.equal(result.metadata.extension, 'gif'); assert.equal(result.metadata.duration_ms, null);
  assert.deepEqual(await validateAttachment({buffer:input,originalname:'Happy.gif'}, 'gif'), result);
});

test('sticker validation preserves alpha, bounds dimensions and strips input metadata', async () => {
  const input = await sharp({create:{width:800,height:600,channels:4,background:{r:20,g:220,b:170,alpha:.4}}}).png().toBuffer();
  const result = await validateAttachment({buffer:input,originalname:'../Sticker - hello.png'}, 'sticker');
  const meta = await sharp(result.bytes).metadata();
  assert.equal(meta.format, 'png'); assert.equal(meta.hasAlpha, true);
  assert.equal(meta.width, 512); assert.equal(meta.height, 384); assert.equal(meta.exif, undefined);
  assert.equal(result.metadata.kind, 'image'); assert.equal(result.metadata.content_type, 'image/png');
  assert(result.metadata.filename.startsWith('Sticker - ')); assert(!result.metadata.filename.includes('/'));
  const decoded = await sharp(result.bytes).raw().toBuffer(); assert(decoded[3] < 255 && decoded[3] > 0);
});

test('renamed files, scripts, broken GIFs, oversized inputs and excessive frames are rejected', async () => {
  for (const kind of ['gif', 'sticker']) {
    await assert.rejects(validateAttachment({buffer:Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><rect width="5" height="5"/></svg>'),originalname:'fake.gif'}, kind), {status:400});
    await assert.rejects(validateAttachment({buffer:Buffer.alloc(attachmentLimit + 1),originalname:'large.gif'}, kind), {status:400});
  }
  await assert.rejects(validateAttachment({buffer:Buffer.from('GIF89a broken'),originalname:'broken.gif'}, 'gif'), {status:400});
  const png = await sharp({create:{width:10,height:10,channels:4,background:'red'}}).png().toBuffer();
  await assert.rejects(validateAttachment({buffer:png,originalname:'renamed.gif'}, 'gif'), {status:400});
  await assert.rejects(validateAttachment({buffer:await gifBytes(161),originalname:'long.gif'}, 'gif'), {status:400});
  await assert.rejects(validateAttachment({buffer:await gifBytes(),originalname:'animated.png'}, 'sticker'), {status:400});
});

test('existing photo uploads still produce JPEG with their previous validation', async () => {
  const input = await sharp({create:{width:20,height:10,channels:3,background:'cyan'}}).png().toBuffer();
  const result = await validateAttachment({buffer:input,originalname:'photo.png'}, 'image');
  assert.equal(result.metadata.content_type, 'image/jpeg'); assert.equal(result.metadata.filename, 'photo.jpg');
});
