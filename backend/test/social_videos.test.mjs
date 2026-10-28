import test from 'node:test';
import assert from 'node:assert/strict';
import {validateAttachment,attachmentLimit} from '../social/attachments.mjs';
import {videoFixture} from './fixtures/video.mjs';

test('chat videos transcode to private MP4 files, remove metadata and retry deterministically', async () => {
  const file = {buffer:await videoFixture(),originalname:'../my clip.mov'};
  const first = await validateAttachment(file, 'video');
  assert.equal(first.metadata.kind, 'file');
  assert.equal(first.metadata.content_type, 'video/mp4');
  assert.equal(first.metadata.extension, 'mp4');
  assert.equal(first.metadata.duration_ms, 1000);
  assert(!first.metadata.filename.includes('/'));
  assert(!first.bytes.includes(Buffer.from('private-location')));
  assert(first.bytes.length < attachmentLimit);
  assert.deepEqual(await validateAttachment(file, 'video'), first);
});
test('videos reject executable text, playlists, malformed containers and oversized files', async () => {
  for (const buffer of [Buffer.from('<script>video</script>'), Buffer.from('#EXTM3U\nhttp://169.254.169.254/'),
    Buffer.from('0000ftypbroken'), Buffer.alloc(attachmentLimit + 1)]) {
    await assert.rejects(validateAttachment({buffer,originalname:'clip.mp4'}, 'video'), {status:400});
  }
});
test('chat clips longer than three minutes are rejected without silent truncation', async () => {
  await assert.rejects(validateAttachment({buffer:await videoFixture(181),originalname:'long.mp4'}, 'video'), /180 seconds/);
});
