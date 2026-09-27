'use strict';
const {spawn} = require('node:child_process');
const {mkdtemp, readFile, rm} = require('node:fs/promises');
const {createWriteStream,openSync,writeSync,closeSync} = require('node:fs');
const {join} = require('node:path');
const {tmpdir} = require('node:os');
const {pipeline} = require('node:stream/promises');
const MAX_BYTES = 32 * 1024 * 1024;

// Fixed local codec, no shell or caller-supplied paths/arguments. Temporary
// audio is private to the service process and removed after every outcome.
async function createRecordingEncoder({onFailure = () => {}} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'korlix-recording-'));
  const file = join(directory, 'audio.mp3');
  const voiceFile = join(directory, 'nova.pcm');
  let voiceFd, voiceEnd = 0, mixing;
  let child, ended = false, failed = false, outputBytes = 0, inputBytes = 0;
  let timeout;
  const closeVoice = () => { if (voiceFd !== undefined) { closeSync(voiceFd); voiceFd=undefined; } };
  const fail = () => {
    if (failed) return;
    failed = true;
    child?.kill('SIGKILL');
    mixing?.kill('SIGKILL');
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
      writeVoice(buffer,offset) {
        if (ended || failed || !Buffer.isBuffer(buffer) || !buffer.length || buffer.length>16000 ||
            buffer.length%2 || !Number.isSafeInteger(offset) || offset<0 || offset%2 ||
            offset+buffer.length>16000*2*3600) return false;
        try {
          if (voiceFd===undefined) voiceFd=openSync(voiceFile,'wx',0o600);
          let written=0;
          while(written<buffer.length) {
            const n=writeSync(voiceFd,buffer,written,buffer.length-written,offset+written);
            if(n<=0)throw Error();written+=n;
          }
          voiceEnd=Math.max(voiceEnd,offset+buffer.length);return true;
        } catch { fail(); return false; }
      },
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
        closeVoice();
        timeout = setTimeout(fail, 25000);
        try {
          // A quiet Zoom stream can end before Nova's last played sample. Fill
          // only that bounded tail, respecting the encoder's backpressure.
          while(inputBytes<voiceEnd&&!failed) {
            const silence=Buffer.alloc(Math.min(16000,voiceEnd-inputBytes));
            inputBytes+=silence.length;
            if(!child.stdin.write(silence))await Promise.race([
              new Promise(resolve=>child.stdin.once('drain',resolve)),closed]);
          }
          child.stdin.end();
          const [ok,saved] = await Promise.all([closed,written]);
          if (!ok || !saved || failed || inputBytes === 0 || outputBytes < 64 || outputBytes > MAX_BYTES)
            throw new Error('RECORDING_ENCODER_FAILED');
          let bytes = await readFile(file);
          if (bytes.length !== outputBytes) throw new Error('RECORDING_ENCODER_FAILED');
          if (voiceEnd) {
            // Both inputs are private local files; never decode caller URLs or
            // build filter expressions from request text. The sparse PCM track
            // contains only browser-confirmed, already-played Nova samples.
            mixing=spawn('ffmpeg',['-hide_banner','-loglevel','error','-nostdin',
              '-i',file,'-f','s16le','-ar','16000','-ac','1','-i',voiceFile,
              '-filter_complex','amix=inputs=2:duration=longest:normalize=0,alimiter=limit=0.95:level=0',
              '-t',String(inputBytes/32000),'-ar','16000','-ac','1',
              '-c:a','libmp3lame','-b:a','64k','-f','mp3','pipe:1'],
              {stdio:['ignore','pipe','ignore'],env:{PATH:process.env.PATH,LANG:'C'}});
            const chunks=[];let size=0;
            mixing.stdout.on('data',b=>{size+=b.length;if(size>MAX_BYTES)fail();else chunks.push(b);});
            const ok=await new Promise(resolve=>{
              mixing.once('error',()=>resolve(false));mixing.once('close',code=>resolve(code===0));
            });
            if(!ok||failed||size<64||size>MAX_BYTES)throw new Error('RECORDING_MIX_FAILED');
            bytes=Buffer.concat(chunks,size);
          }
          return bytes;
        } finally { clearTimeout(timeout);closeVoice();await rm(directory,{recursive:true,force:true}); }
      },
      async abort() {
        ended = true; child.kill('SIGKILL');mixing?.kill('SIGKILL');closeVoice();
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
