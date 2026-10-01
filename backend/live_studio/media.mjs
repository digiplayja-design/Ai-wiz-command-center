import {spawn} from 'node:child_process';
import {writeFile, readFile} from 'node:fs/promises';
import {once} from 'node:events';
import path from 'node:path';
import sharp from 'sharp';
import {LiveStudioError} from './core.mjs';
import {validatePodWav} from '../pod/providers.mjs';

const escape = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
const lines = (text, width) => {
  const out = [''];
  for (const word of String(text).split(/\s+/)) {
    if ((out.at(-1).length + word.length) > width) out.push('');
    out[out.length - 1] += (out.at(-1) ? ' ' : '') + word;
  }
  return out;
};
export function sceneSvg({title, text, speaker = 'host', paused = false, rehearsal = false, sources = []}) {
  const accent = speaker === 'host' ? '#8c72ff' : '#41dec4';
  const caption = lines(text, 76).slice(0, 8);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="720" viewBox="0 0 1280 720">
  <defs><linearGradient id="bg" x2="1" y2="1"><stop stop-color="#111634"/><stop offset="1" stop-color="#050a17"/></linearGradient>
  <radialGradient id="glow"><stop stop-color="${accent}" stop-opacity=".3"/><stop offset="1" stop-color="${accent}" stop-opacity="0"/></radialGradient></defs>
  <rect width="1280" height="720" fill="url(#bg)"/><circle cx="1050" cy="250" r="390" fill="url(#glow)"/>
  <path d="M0 270H1280M0 320H1280M0 370H1280M0 420H1280" stroke="#7786c5" opacity=".06"/>
  <text x="58" y="61" fill="white" font-family="sans-serif" font-size="25" font-weight="bold">KORLIX <tspan fill="${accent}">LIVE STUDIO</tspan></text>
  <rect x="983" y="29" width="235" height="43" rx="21" fill="#252c47"/>
  <circle cx="1008" cy="50" r="6" fill="${paused ? '#ffcc70' : '#61e7bb'}"/>
  <text x="1027" y="57" fill="#dbe2ff" font-family="sans-serif" font-size="16">${rehearsal ? 'PRIVATE REHEARSAL' : paused ? 'BROADCAST PAUSED' : 'AI-HOSTED SHOW'}</text>
  ${lines(title, 46).slice(0, 2).map((l,i)=>`<text x="58" y="${139+i*44}" fill="white" font-family="sans-serif" font-size="36" font-weight="bold">${escape(l)}</text>`).join('')}
  <circle cx="170" cy="300" r="75" fill="#171f3f" stroke="${accent}" stroke-width="3"/>
  <rect x="153" y="260" width="34" height="59" rx="17" fill="${accent}"/>
  <path d="M139 291v12a31 31 0 0062 0v-12M170 335v25M151 360h38" fill="none" stroke="white" stroke-width="5" stroke-linecap="round"/>
  <text x="272" y="281" fill="white" font-family="sans-serif" font-size="32" font-weight="bold">${speaker==='host'?'K-Nova':'The Analyst'}</text>
  <text x="274" y="315" fill="#abb7d6" font-family="sans-serif" font-size="20">${paused ? 'The producer has paused the discussion' : speaker==='host'?'Your AI host':'AI cohost · Evidence and perspective'}</text>
  <rect x="58" y="400" width="1160" height="255" rx="24" fill="#111a30" stroke="#273451"/>
  ${caption.map((l,i)=>`<text x="82" y="${438+i*26}" fill="#f1f4ff" font-family="sans-serif" font-size="22">${escape(l)}</text>`).join('')}
  <text x="62" y="690" fill="#91a2c4" font-family="sans-serif" font-size="14">${escape(sources.length ? 'Sources: '+sources.slice(0,2).map(s=>s.title||s.url).join(' · ').slice(0,145) : 'AI-generated voices and visuals · KORLIX Live Studio')}</text></svg>`;
}
export function musicWav(seconds = 5) {
  const rate=24000, count=Math.round(seconds*rate), wav=Buffer.alloc(44+count*2);
  wav.write('RIFF');wav.writeUInt32LE(wav.length-8,4);wav.write('WAVE',8);wav.write('fmt ',12);
  wav.writeUInt32LE(16,16);wav.writeUInt16LE(1,20);wav.writeUInt16LE(1,22);wav.writeUInt32LE(rate,24);
  wav.writeUInt32LE(rate*2,28);wav.writeUInt16LE(2,32);wav.writeUInt16LE(16,34);wav.write('data',36);wav.writeUInt32LE(count*2,40);
  for(let n=0;n<count;n++) {
    const t=n/rate,fade=Math.min(1,t*3,(seconds-t)*3),beat=.55+.45*Math.sin(2*Math.PI*t/2)**2;
    const sample=(Math.sin(2*Math.PI*220*t)+.45*Math.sin(2*Math.PI*277.1826*t)+.3*Math.sin(2*Math.PI*329.6276*t));
    wav.writeInt16LE(Math.round(sample*1000*fade*beat),44+n*2);
  }
  return wav;
}
export async function runFfmpeg(args, {signal, timeout=90000}={}) {
  signal?.throwIfAborted();
  return new Promise((resolve,reject)=>{
    const child=spawn('ffmpeg',['-hide_banner','-nostdin','-loglevel','error','-y',...args],{stdio:['ignore','ignore','pipe']});
    const stop=()=>child.kill('SIGKILL'),timer=setTimeout(stop,timeout);
    signal?.addEventListener('abort',stop,{once:true});
    child.stderr.resume();
    child.once('error',()=>finish(new LiveStudioError('The video renderer is unavailable.',503)));
    child.once('close',code=>finish(code===0?null:new LiveStudioError('The video renderer stopped before finishing.',503)));
    let done=false;
    function finish(error){if(done)return;done=true;clearTimeout(timer);signal?.removeEventListener('abort',stop);error?reject(error):resolve();}
  });
}
export async function renderSegment({dir,index,show,turn,wav,offset=0,seconds,signal,width=1280,rehearsal=false,paused=false,sources=[]}) {
  const audio=validatePodWav(wav,{maxSeconds:40});
  const duration=Math.ceil(Math.min(seconds??audio.durationSeconds,audio.durationSeconds)*30)/30;
  if(duration<=0)throw new LiveStudioError('This audio segment is empty.');
  const prefix=path.join(dir,`segment-${index}`),file=prefix+'.ts';
  await writeFile(prefix+'.wav',wav);
  await sharp(Buffer.from(sceneSvg({title:show.config.title,...turn,rehearsal,paused,sources}))).resize(width,width*9/16).png().toFile(prefix+'.png');
  await runFfmpeg(['-loop','1','-framerate','30','-i',prefix+'.png','-i',prefix+'.wav',
    '-t',duration.toFixed(5),'-vf',`drawbox=x=270:y=341:w=200:h=5:color=0x8c72ff@0.7:t=fill:enable='lt(mod(t,1.2),0.8)'`,
    '-c:v','libx264','-preset','ultrafast','-tune','zerolatency','-threads','2','-pix_fmt','yuv420p','-r','30',
    '-g','60','-bf','0','-b:v',width===1280?'1500k':'500k','-c:a','aac','-ar','48000','-ac','2','-b:a','96k',
    '-af','apad,asetpts=PTS+1024/SR/TB','-output_ts_offset',offset.toFixed(5),'-muxdelay','0','-muxpreload','0','-mpegts_flags','+resend_headers','-f','mpegts',file],{signal});
  return {file,duration};
}
export async function makeReplay(files,output,{signal}={}) {
  const all=output+'.ts';
  // Private rehearsal is bounded to 60 seconds and a 50 MiB object.
  const buffers=await Promise.all(files.map(file=>readFile(file)));
  if(buffers.reduce((n,b)=>n+b.length,0)>48*1024*1024)throw new LiveStudioError('The rehearsal video exceeded its size limit.');
  await writeFile(all,Buffer.concat(buffers));
  await runFfmpeg(['-fflags','+genpts','-i',all,'-c','copy','-movflags','+faststart',output],{signal});
}
export function broadcastSink(url,{signal,spawnProcess=spawn}={}) {
  const parsed=new URL(url);
  if(parsed.protocol!=='rtmps:'||!['a.rtmps.youtube.com','b.rtmps.youtube.com'].includes(parsed.hostname)||parsed.username||parsed.password||!parsed.pathname.startsWith('/live2/')) throw new LiveStudioError('YouTube returned an unsupported broadcast destination.');
  const child=spawnProcess('ffmpeg',['-hide_banner','-nostdin','-loglevel','error','-re','-fflags','+genpts',
    '-f','mpegts','-i','pipe:0','-map','0:v:0','-map','0:a:0','-c','copy','-f','flv',url],{stdio:['pipe','ignore','pipe']});
  // Never log stderr: encoders can include the private stream key in errors.
  child.stderr.resume();child.stdin.on('error',()=>{});
  let failed=false;child.on('error',()=>{failed=true;});child.on('close',code=>{if(code!==0)failed=true;});
  const stop=()=>child.kill('SIGKILL');signal?.addEventListener('abort',stop,{once:true});
  return {async write(file){signal?.throwIfAborted();if(failed||child.exitCode!==null)throw new LiveStudioError('The stream connection was lost.',503);
    const data=await readFile(file);
    signal?.throwIfAborted();
    if(!child.stdin.write(data))await new Promise((resolve,reject)=>{
      const cleanup=()=>{child.stdin.off('drain',drained);child.stdin.off('error',lost);child.off('close',lost);child.off('error',lost);};
      const drained=()=>{cleanup();resolve();};
      const lost=()=>{cleanup();reject(new LiveStudioError('The stream connection was lost.',503));};
      child.stdin.once('drain',drained);child.stdin.once('error',lost);child.once('close',lost);child.once('error',lost);
      if(failed||child.exitCode!==null)lost();
    });
  },async close(){child.stdin.end();if(child.exitCode===null){const timer=setTimeout(stop,5000);await once(child,'close');clearTimeout(timer);}signal?.removeEventListener('abort',stop);},stop};
}
