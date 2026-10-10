// Original KORLIX vector artwork. Regenerate with sharp 0.35.5 installed, or set
// KORLIX_SHARP_MODULE to its entry point. No external images or fonts downloaded.
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
const { default: sharp } = await import(process.env.KORLIX_SHARP_MODULE || 'sharp');
const folder = new URL('../assets/social_reactions/', import.meta.url);
await mkdir(folder, { recursive: true });
const reactions = [
  ['hey', 'Hey!', 'Greetings', 'wave hello hi welcome', 'smile', '#61e3e4', '#22a0d7'],
  ['big-up', 'Big up!', 'Celebrate', 'respect jamaica proud awesome', 'cool', '#afe96e', '#2bbc9e'],
  ['lol', 'LOL', 'Reactions', 'laugh funny haha hilarious', 'laugh', '#ffd76c', '#ff9356'],
  ['love-this', 'Love this', 'Love', 'heart love adore favourite', 'love', '#ffafce', '#f268b2'],
  ['thank-you', 'Thank you', 'Everyday', 'thanks grateful appreciation', 'smile', '#a4beff', '#8b78e8'],
  ['respect', 'Respect', 'Reactions', 'salute big up agreed', 'cool', '#76e6cf', '#30bba8'],
  ['you-got-this', 'You got this', 'Everyday', 'encourage support strong', 'smile', '#ffd57a', '#ff956b'],
  ['congrats', 'Congrats!', 'Celebrate', 'congratulations win proud clap', 'star', '#c6a7ff', '#9b77ec'],
  ['lets-go', "Let’s go!", 'Celebrate', 'excited ready fire hype', 'star', '#ffb992', '#ff798b'],
  ['on-my-way', 'On my way', 'Everyday', 'coming omw travel', 'cool', '#7ce0f0', '#6da4ff'],
  ['well-done', 'Well done', 'Celebrate', 'great job applause clap', 'smile', '#ceeb85', '#64cbaa'],
  ['good-morning', 'Good morning', 'Greetings', 'sun hello morning', 'smile', '#ffe085', '#ffc066'],
  ['good-night', 'Good night', 'Greetings', 'sleep tired night bye', 'sleep', '#d4baff', '#9d8cd5'],
  ['thinking', 'Thinking…', 'Reactions', 'hmm think wait question', 'think', '#8ed3ee', '#76abd7'],
  ['seriously', 'Seriously?', 'Reactions', 'really wow shocked surprise', 'wow', '#f8c49a', '#e99c9f'],
  ['oops', 'Oops!', 'Reactions', 'mistake awkward surprised', 'wow', '#b5dd95', '#76b898'],
  ['sorry', 'Sorry', 'Everyday', 'apology apologies sad', 'sad', '#a8c2e8', '#8293c9'],
  ['hugs', 'Sending hugs', 'Love', 'hug care support comfort', 'love', '#ffb9c7', '#e58cc5'],
  ['no-worries', 'No worries', 'Everyday', 'okay alright relax fine', 'smile', '#8fe5cf', '#55b7bc'],
  ['birthday', 'Happy birthday', 'Celebrate', 'party birthday cake happy', 'star', '#f9bdea', '#cc91df'],
  ['yes', 'Yes!', 'Reactions', 'yes agree thumbs up approved', 'smile', '#b0e7a1', '#62cbae'],
  ['nope', 'Nope', 'Reactions', 'no disagree stop thumbs down', 'think', '#ffb1b2', '#e584a6'],
  ['deal', 'Deal!', 'Everyday', 'handshake agreed business done', 'cool', '#8bcfea', '#879fe0'],
  ['coffee', 'Coffee time', 'Everyday', 'coffee break tired work', 'sleep', '#ddc4a7', '#bc947e'],
];
const escape = s => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;');
const heart = (x, y, scale = 1) => `<path transform="translate(${x} ${y}) scale(${scale})" d="M0 6C-20-10-29-24-15-30C-6-34 0-27 0-22C1-30 9-34 16-29C29-20 16-5 0 6" fill="#ec428a"/>`;
function svg(row, phase, gif) {
  const [, label, , , face, a, b] = row;
  const bounce = gif ? Math.sin(phase * Math.PI * 2) * 7 : 0;
  const tilt = gif ? Math.sin(phase * Math.PI * 2) * 4 : -4;
  const eye = face === 'love'
    ? heart(112, 118, .52) + heart(167, 118, .52)
    : face === 'cool'
    ? '<path d="M90 102h39v25Q104 143 94 122ZM147 102h40l-4 21Q163 144 149 125Z" fill="#18374c"/><path d="M128 110h20M97 107l16 12M154 107l15 12" stroke="#91e2ed" stroke-width="4"/>'
    : face === 'sleep' || face === 'laugh'
    ? '<path d="M96 113q14 16 29 0M150 113q14 16 29 0" fill="none" stroke="#18374c" stroke-width="8" stroke-linecap="round"/>'
    : '<ellipse cx="111" cy="113" rx="8" ry="12" fill="#18374c"/><ellipse cx="164" cy="113" rx="8" ry="12" fill="#18374c"/><circle cx="113" cy="109" r="2.5" fill="white"/><circle cx="166" cy="109" r="2.5" fill="white"/>';
  const mouth = face === 'wow'
    ? '<ellipse cx="138" cy="150" rx="12" ry="17" fill="#18374c"/>'
    : face === 'sad'
    ? '<path d="M121 158q17-19 35 0" stroke="#18374c" fill="none" stroke-width="6" stroke-linecap="round"/>'
    : face === 'think' || face === 'sleep'
    ? '<path d="M127 150h23" stroke="#18374c" stroke-width="6" stroke-linecap="round"/>'
    : '<path d="M113 143q25 43 50 0Z" fill="#18374c"/><path d="M126 159q12-11 23 0q-12 9-23 0" fill="#ff869f"/>';
  const decor = face === 'love' ? heart(216, 53, .8)
    : face === 'sleep' ? '<text x="197" y="70" font-family="DejaVu Sans" font-size="28" font-weight="bold" fill="#f5c979">z Z</text>'
    : face === 'think' || face === 'wow' ? '<text x="207" y="68" font-family="DejaVu Sans" font-size="43" font-weight="bold" fill="#f5c979">?</text>'
    : '<path d="M211 36l5 17 17 5-17 5-5 17-5-17-17-5 17-5Z" fill="#ffe49c"/>';
  return `<svg xmlns="http://www.w3.org/2000/svg" width="288" height="288" viewBox="0 0 288 288">
  <defs><linearGradient id="body" x2=".5" y2="1"><stop stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient><linearGradient id="bg" x2="1" y2="1"><stop stop-color="#111e3a"/><stop offset="1" stop-color="#27305a"/></linearGradient></defs>
  ${gif ? '<rect width="288" height="288" rx="26" fill="url(#bg)"/><circle cx="29" cy="51" r="3" fill="#8eabd4"/><circle cx="246" cy="197" r="4" fill="#7789c4"/><path d="M44 188h12M50 182v12" stroke="#6ba7c8" stroke-width="3"/>' : ''}
  <g transform="translate(0 ${bounce}) rotate(${tilt} 144 140)">
    <ellipse cx="143" cy="203" rx="65" ry="10" fill="#11294b" opacity=".18"/>
    <path d="M68 135Q39 116 43 145Q47 165 71 158M207 135Q236 111 234 143Q230 164 206 157" stroke="white" stroke-width="12" fill="${b}" stroke-linejoin="round"/>
    <path d="M82 185l-3 14q14 13 28 0l2-16M167 186l4 16q18 10 27-4l-4-18" stroke="white" stroke-width="11" fill="${b}" stroke-linejoin="round"/>
    <path d="M72 168Q57 127 76 81Q92 48 137 54Q193 49 208 88Q227 135 205 172Q192 194 140 193Q88 193 72 168Z" fill="url(#body)" stroke="white" stroke-width="10"/>
    <path d="M87 82q18-18 47-15" fill="none" stroke="white" stroke-opacity=".45" stroke-width="7" stroke-linecap="round"/>
    <ellipse cx="92" cy="139" rx="14" ry="7" fill="#ff80a3" opacity=".6"/><ellipse cx="181" cy="139" rx="14" ry="7" fill="#ff80a3" opacity=".6"/>
    ${eye}${mouth}${decor}
  </g>
  <text x="144" y="253" text-anchor="middle" font-family="DejaVu Sans" font-weight="bold" font-size="${label.length > 12 ? 24 : label.length > 9 ? 27 : 34}" fill="#172d4c" stroke="white" stroke-width="9" stroke-linejoin="round" paint-order="stroke">${escape(label)}</text>
  </svg>`;
}
const manifest = [];
for (const row of reactions) {
  const [id, label, category, keywords] = row;
  const source = Buffer.from(svg(row, 0, false));
  await sharp(source).png().toFile(fileURLToPath(new URL(`${id}.png`, folder)));
  const frames = [];
  for (let frame = 0; frame < 16; frame++) frames.push(await sharp(Buffer.from(svg(row, frame / 16, true))).ensureAlpha().raw().toBuffer());
  await sharp(Buffer.concat(frames), { raw: { width: 288, height: 288 * 16, channels: 4, pageHeight: 288 } })
    .gif({ delay: Array(16).fill(100), loop: 0, effort: 3, colours: 128 }).toFile(fileURLToPath(new URL(`${id}.gif`, folder)));
  manifest.push({ id, label, category, keywords });
}
await writeFile(new URL('catalog.json', folder), JSON.stringify(manifest, null, 2) + '\n');
console.log(`Generated ${manifest.length} original stickers and GIFs.`);
