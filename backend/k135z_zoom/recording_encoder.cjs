'use strict';
const {spawn} = require('node:child_process');
const {mkdtemp, readFile, rm} = require('node:fs/promises');
const {createWriteStream} = require('node:fs');
const {join} = require('node:path');
const {tmpdir} = require('node:os');
const {pipeline} = require('node:stream/promises');
const MAX_BYTES = 32 * 1024 * 1024;

// Fixed local codec, no shell or caller-supplied paths/arguments. Temporary
// audio is private to the service process and removed after every outcome.
async function createRecordingEncoder({onFailure = () => {}} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'korlix-recording-'));
  const file = join(directory, 'audio.mp3');
  let child, ended = false, failed = false, outputBytes = 0, inputBytes = 0;
  let timeout;
  const fail = () => {
    if (failed) return;
    failed = true;
    child?.kill('SIGKILL');
    try { onFailure(); } catch {}
  };
  try {
    child = spawn('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-nostdin',
      '-f', 's16le', '-ar', '16000', '-ac', '1', '-i', 'pipe:0',
      '-c:a', 'libmp3lame', '-b:a', '64k', '-f', 'mp3', 'pipe:1'],
    {stdio:['pipe','pipe','pipe'], env:{PATH:process.env.PATH, LANG:'C'}});
    // Never forward codec diagnostics or media bytes to application logs.
    child.stderr.resume();
    child.stdin.on('error', fail);
    const closed = new Promise(resolve => {
      child.once('error', () => { fail(); resolve(false); });
      child.once('close', code => { if (code !== 0) fail(); resolve(code === 0); });
    });
    child.stdout.on('data', bytes => { outputBytes += bytes.length; if (outputBytes > MAX_BYTES) fail(); });
    const written = pipeline(child.stdout, createWriteStream(file, {flags:'wx',mode:0o600}))
      .then(() => true, () => { fail(); return false; });
    await new Promise((resolve,reject) => {
      child.once('spawn',resolve);
      child.once('error',reject);
    });
    return {
      write(buffer) {
        if (ended || failed || !Buffer.isBuffer(buffer) || buffer.length === 0 ||
            buffer.length > 65536 || buffer.length % 2 || child.stdin.writableLength > 1024*1024) {
          fail(); return false;
        }
        inputBytes += buffer.length;
        if (inputBytes > 16000*2*3600) { fail(); return false; }
        // Native SDK buffers can be reused after their callback returns.
        child.stdin.write(Buffer.from(buffer));
        return true;
      },
      async finish() {
        if (ended) throw new Error('RECORDING_ENCODER_CLOSED');
        ended = true;
        timeout = setTimeout(fail, 15000);
        child.stdin.end();
        try {
          const [ok,saved] = await Promise.all([closed,written]);
          if (!ok || !saved || failed || inputBytes === 0 || outputBytes < 64 || outputBytes > MAX_BYTES)
            throw new Error('RECORDING_ENCODER_FAILED');
          const bytes = await readFile(file);
          if (bytes.length !== outputBytes) throw new Error('RECORDING_ENCODER_FAILED');
          return bytes;
        } finally { clearTimeout(timeout); await rm(directory,{recursive:true,force:true}); }
      },
      async abort() {
        ended = true; child.kill('SIGKILL');
        await Promise.all([closed,written]);
        clearTimeout(timeout); await rm(directory,{recursive:true,force:true});
      },
    };
  } catch (error) {
    child?.kill('SIGKILL');
    await rm(directory,{recursive:true,force:true});
    throw error;
  }
}
module.exports = {createRecordingEncoder, MAX_BYTES};
