export class PodError extends Error {
  constructor(message, status = 400, code = 'pod_request_invalid') {
    super(message); this.name = 'PodError'; this.status = status; this.statusCode = status; this.code = code;
  }
}

export const POD_CATALOG = Object.freeze([
  {id:'trending',label:'Trending',topics:['Which technology stories matter most today?', 'What deserves a closer look in the news today?']},
  {id:'politics',label:'Politics',topics:['What is happening in US politics today?', 'How can we evaluate a policy beyond the headlines?']},
  {id:'sports',label:'Sports',topics:['What are the biggest sports stories today?', 'What makes a great team beyond individual talent?']},
  {id:'religion',label:'Faith & Religion',topics:['How do different traditions approach forgiveness?', 'What role can faith play in everyday community life?']},
  {id:'culture',label:'Culture',topics:['How does music shape a generation?', 'What makes a story stay with us?']},
  {id:'business',label:'Business',topics:['How could AI help a small business?', 'What makes customers come back?']},
  {id:'technology',label:'Technology',topics:['Can AI make everyday life better?', 'How can families build healthier technology habits?']},
]);

export function podUuid(value) {
  if (typeof value !== 'string' || !/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(value)) {
    throw new PodError('Refresh your pod before trying this request again.');
  }
  return value.toLowerCase();
}
export function podText(value, max, label) {
  if (typeof value !== 'string' || !value.trim() || value.length > max || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(value)) {
    throw new PodError(`${label} must contain 1–${max} characters.`);
  }
  return value.trim();
}
export function podInput(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new PodError('Choose your pod settings.');
  if (body.consent !== true) throw new PodError('Confirm AI sharing and the LIVE CONVO allowance before starting.');
  const category = body.category;
  if (!POD_CATALOG.some(c => c.id === category)) throw new PodError('Choose a topic category.');
  if (![300,600,900].includes(body.durationSeconds)) throw new PodError('Choose a 5-, 10-, or 15-minute pod.');
  if (![2,3].includes(body.hostCount)) throw new PodError('Choose two or three AI hosts.');
  if (!['balanced','relaxed','debate'].includes(body.style)) throw new PodError('Choose a discussion style.');
  return {category,topic:podText(body.topic,240,'The topic'),durationSeconds:body.durationSeconds,
    hostCount:body.hostCount,style:body.style};
}
export function podVersion(value) {
  if (!Number.isSafeInteger(value) || value < 0) throw new PodError('Refresh the episode before continuing.');
  return value;
}
export function podAudioBody(value) {
  const maxBytes = 1440044;
  if (typeof value !== 'string' || value.length > Math.ceil(maxBytes / 3) * 4 ||
      value.length % 4 || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) {
    throw new PodError('Record a voice contribution of 30 seconds or less.');
  }
  const wav = Buffer.from(value,'base64');
  if (wav.length < 44 || wav.length > maxBytes || wav.toString('base64') !== value) {
    throw new PodError('The recording could not be read. Record up to 30 seconds and try again.');
  }
  return wav;
}

const episodeKeys = ['id','category','topic','durationSeconds','hostCount','style','state','phase','version',
  'createdAt','startedAt','deadlineAt','serverNow','turns','sources','checkedAt','summary','endReason','error','usageLabel'];
const pick = (value, keys) => value && typeof value === 'object'
  ? Object.fromEntries(keys.filter(k=>value[k]!==undefined).map(k=>[k,value[k]])) : null;
export const publicPodTurn = turn => pick(turn,['id','seq','speaker','text','sourceIds','createdAt','interrupted']);
export function publicPodEpisode(episode) {
  if (!episode || typeof episode !== 'object') return null;
  const value=pick(episode,episodeKeys);
  value.turns=(Array.isArray(episode.turns)?episode.turns:[]).map(publicPodTurn);
  value.sources=(Array.isArray(episode.sources)?episode.sources:[]).map(s=>pick(s,['id','title','url']));
  return value;
}

export function podUsage(usage, callKey) {
  const number = v => Number.isSafeInteger(v) && v >= 0 && v <= 10000000 ? v : 0;
  const transcription = callKey === 'transcribe';
  return {inputTokens:transcription ? 0 : number(usage?.inputTokens),
    outputTokens:transcription ? 0 : number(usage?.outputTokens),
    totalTokens:transcription ? 0 : number(usage?.totalTokens),
    transcriptionTokens:transcription ? number(usage?.totalTokens) : 0,
    inputAudioTokens:number(usage?.inputAudioTokens),outputAudioTokens:number(usage?.outputAudioTokens)};
}

export function podFailure(error) {
  const known = ['PodError','PodStorageError','PodProviderError'].includes(error?.name);
  return {status:known ? (error.status || error.statusCode || 503) : 503,
    error:known ? error.message : 'Your pod could not finish this request. Refresh its status before trying again.',
    code:known ? error.code : 'pod_unavailable'};
}
