import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp,readFile,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
const run = promisify(execFile);
export async function videoFixture(seconds = 1) {
  const folder = await mkdtemp(join(tmpdir(), 'korlix-video-test-'));
  try {
    const path = join(folder, 'clip.mp4');
    await run('ffmpeg', ['-v','error','-f','lavfi','-i',`color=c=yellow:s=64x64:r=2:d=${seconds}`,
      '-c:v','libx264','-threads','1','-pix_fmt','yuv420p','-metadata','comment=private-location',path],
      {timeout:15000,maxBuffer:1024*1024});
    return await readFile(path);
  } finally { await rm(folder,{recursive:true,force:true}); }
}
