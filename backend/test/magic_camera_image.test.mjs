import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import {PRESETS,options,instructions,prepareSource,validateOutput,renderer} from '../magic_camera/core.mjs';

const colors=[[220,30,30],[30,200,30],[30,30,220],[220,200,30]];
// EXIF's eight transforms, expressed as the expected top-left, top-right,
// bottom-left and bottom-right colors. An asymmetric frame catches double turns.
const corners=[null,[0,1,2,3],[1,0,3,2],[3,2,1,0],[2,3,0,1],
 [0,2,1,3],[2,0,3,1],[3,1,2,0],[1,3,0,2]];
async function fixture(format,orientation) {
 const tiles=await Promise.all(colors.map(async(rgb,i)=>({
  input:await sharp({create:{width:384,height:256,channels:3,background:{r:rgb[0],g:rgb[1],b:rgb[2]}}}).png().toBuffer(),
  left:(i%2)*384,top:Math.floor(i/2)*256,
 })));
 return sharp({create:{width:768,height:512,channels:3,background:'black'}})
  .composite(tiles).withMetadata({orientation}).toFormat(format).toBuffer();
}
async function assertUpright(bytes,orientation) {
 const metadata=await sharp(bytes).metadata();
 const width=orientation<5?768:512,height=orientation<5?512:768;
 assert.equal(metadata.width,width);assert.equal(metadata.height,height);
 assert.equal(metadata.orientation,undefined);assert.equal(metadata.exif,undefined);
 const {data,info}=await sharp(bytes).removeAlpha().raw().toBuffer({resolveWithObject:true});
 for(let i=0;i<4;i++) {
  const x=Math.floor(width*((i%2)*0.5+0.25)),y=Math.floor(height*(Math.floor(i/2)*0.5+0.25));
  const offset=(y*width+x)*info.channels;
  colors[corners[orientation][i]].forEach((value,c)=>assert(Math.abs(data[offset+c]-value)<8,`orientation ${orientation}, corner ${i}, channel ${c}`));
 }
}
for(let orientation=1;orientation<=8;orientation++) {
 test(`source EXIF ${orientation} becomes upright pixels without metadata or double rotation`,async()=>{
  const normalized=await prepareSource(await fixture('jpeg',orientation));
  await assertUpright(normalized,orientation);
  await assertUpright(await prepareSource(normalized),orientation);
 });
 test(`generated PNG EXIF ${orientation} is normalized before storage with final dimensions`,async()=>{
  const result=await validateOutput((await fixture('png',orientation)).toString('base64'));
  await assertUpright(result.bytes,orientation);
  const metadata=await sharp(result.bytes).metadata();
  assert.equal(result.width,metadata.width);assert.equal(result.height,metadata.height);
 });
}
test('every preset and custom edit includes conditional grooming, shine control and cinematic lighting without changing identity',()=>{
 for(const preset of [...PRESETS.map(p=>p.id),'custom']) {
  for(const preserveFace of [true,false]) {
   const prompt=instructions(options({preset,preserveFace,prompt:preset==='custom'?'A moonlit garden':''}));
   for(const rule of [/when hair needs grooming/,/Leave already groomed hair alone/,/natural curl pattern/,/Do not invent hair/,/Reduce excessive oily shine/,/exact skin tone, pores/,/Leave balanced skin alone/,/soft directional key light/,/keep natural mode subtle/,/do not turn the whole photograph sideways/])assert.match(prompt,rule,preset);
   assert.doesNotMatch(prompt,/Do not reshape, beautify/);
   if(preserveFace)assert.match(prompt,/retain each person’s facial structure/);
   if(preset==='custom')assert.match(prompt,/A moonlit garden/);
  }
 }
});
test('the image editor receives normalized source and portrait defaults and returns normalized output',async()=>{
 const source=await prepareSource(await fixture('jpeg',6));
 const output=await fixture('png',8);
 let seenPrompt;
 const render=renderer({
  toFile:async(bytes,name,settings)=>{await assertUpright(bytes,6);assert.equal(settings.type,'image/jpeg');return {name};},
  client:{images:{edit:async(request)=>{seenPrompt=request.prompt;return {data:[{b64_json:output.toString('base64')}]};}}},
 });
 const result=await render(source,options());
 await assertUpright(result.bytes,8);
 assert.match(seenPrompt,/Reduce excessive oily shine/);
 assert.match(seenPrompt,/when hair needs grooming/);
 assert.equal(result.width,512);assert.equal(result.height,768);
});
