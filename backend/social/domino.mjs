import {randomInt, createHash} from 'node:crypto';
import {socialPhotos} from './media.mjs';
import {socialCallConfig} from './calls.mjs';

export class DominoError extends Error { constructor(message,status=400){super(message);this.status=status;} }
const fail=(message,status=400)=>{throw new DominoError(message,status);};
export const dominoDeck=()=>Array.from({length:7},(_,a)=>Array.from({length:7-a},(_,b)=>`${a}-${a+b}`)).flat();
const pips=id=>id.split('-').map(Number), sum=id=>pips(id).reduce((a,b)=>a+b,0);
export function dominoLegal(state,who) {
  const hand=state.hands?.[who]||[];
  if(state.phase!=='playing'||state.turn!==who)return [];
  if(!state.board.length)return hand.filter(t=>t===state.opener).map(tile=>({tile,side:'right'}));
  const left=state.board[0].a,right=state.board.at(-1).b;
  return hand.flatMap(tile=>['left','right'].filter(side=>pips(tile).includes(side==='left'?left:right)).map(side=>({tile,side})));
}
export function dominoAction(snapshot,actor,data,{random=randomInt}={}) {
  const s=structuredClone(snapshot.state),players=snapshot.players.filter(p=>p.state==='joined').sort((a,b)=>a.seat-b.seat),ids=players.map(p=>p.id);
  if(!ids.includes(actor))fail('Join this table to play.',403);
  const id=data.requestId;
  if(typeof id!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id))fail('Refresh this table before playing.');
  const hash=createHash('sha256').update(JSON.stringify({actor,action:data.action,tile:data.tile,side:data.side,ready:data.ready})).digest('hex');
  const prior=(s.receipts||[]).find(r=>r.id===id);
  if(prior){if(prior.hash!==hash)fail('That action ID is already in use.',409);return {state:s,replayed:true};}
  if(data.revision!==snapshot.revision)fail('The table changed. Refresh before playing.',409);
  if(s.phase==='closed')fail('This table is closed.',409);
  s.ready??={};s.wins??={};s.points??={};s.round??=0;
  if(data.action==='ready'){
    if(!['waiting','finished'].includes(s.phase)||typeof data.ready!=='boolean')fail('Wait for the current round to finish.');
    s.ready[actor]=data.ready;
  }else if(data.action==='start'){
    if(snapshot.host!==actor)fail('Only the table host can deal.',403);
    if(!['waiting','finished'].includes(s.phase))fail('This round has already started.',409);
    if(players.length!==snapshot.capacity||ids.some(id=>s.ready[id]!==true)||players.some(p=>!p.online))fail('Every seat must be filled, online and ready before dealing.');
    const deck=dominoDeck();for(let i=deck.length-1;i>0;i--){const j=random(i+1);[deck[i],deck[j]]=[deck[j],deck[i]];}
    s.hands=Object.fromEntries(ids.map((id,i)=>[id,deck.slice(i*7,i*7+7)]));
    const dealt=Object.values(s.hands).flat();const doubles=dealt.filter(t=>pips(t)[0]===pips(t)[1]).sort((a,b)=>sum(b)-sum(a));
    s.opener=doubles[0]||dealt.sort((a,b)=>sum(b)-sum(a)||pips(b)[1]-pips(a)[1])[0];
    s.turn=ids.find(id=>s.hands[id].includes(s.opener));s.order=ids;s.board=[];s.passes=0;s.phase='playing';s.round++;s.ready={};s.result=null;s.last='New round dealt. Highest double opens.';
  }else if(['play','pass'].includes(data.action)){
    if(s.phase!=='playing'||s.turn!==actor)fail('Wait for your turn.',409);
    const legal=dominoLegal(s,actor);
    if(data.action==='pass'){
      if(legal.length)fail('You have a playable tile. Choose a tile instead of passing.');
      s.passes++;s.last=`${players.find(p=>p.id===actor).name} passed.`;
    }else{
      if(!legal.some(x=>x.tile===data.tile&&x.side===data.side))fail('That tile does not fit this end. Refresh and choose a highlighted tile.');
      let [a,b]=pips(data.tile);const left=data.side==='left';
      if(s.board.length){const end=left?s.board[0].a:s.board.at(-1).b;if(left?a===end:b===end)[a,b]=[b,a];}
      const piece={id:data.tile,a,b,by:actor};if(left)s.board.unshift(piece);else s.board.push(piece);
      s.hands[actor]=s.hands[actor].filter(t=>t!==data.tile);s.passes=0;s.last=`${players.find(p=>p.id===actor).name} played ${data.tile}.`;
    }
    if(!s.hands[actor].length||s.passes>=ids.length){
      const team=id=>snapshot.capacity===4?`team${players.find(p=>p.id===id).seat%2}`:id;
      const totals={};for(const id of ids)totals[team(id)]=(totals[team(id)]||0)+s.hands[id].reduce((n,t)=>n+sum(t),0);
      const lowest=Math.min(...Object.values(totals)),lowestTeams=Object.keys(totals).filter(t=>totals[t]===lowest);
      const winner=!s.hands[actor].length?team(actor):lowestTeams.length===1?lowestTeams[0]:null;
      const points=winner?Object.entries(totals).filter(([id])=>id!==winner).reduce((n,[,v])=>n+v,0):0;
      if(winner){s.wins[winner]=(s.wins[winner]||0)+1;s.points[winner]=(s.points[winner]||0)+points;}
      s.result={winner,points,totals,reason:!s.hands[actor].length?'out':'blocked'};s.phase='finished';s.turn=null;s.ready={};
    }else s.turn=ids[(ids.indexOf(actor)+1)%ids.length];
  }else fail('Choose an available domino action.');
  s.receipts=[...(s.receipts||[]),{id,hash}].slice(-80);
  return {state:s,replayed:false};
}

// Deliberate allowlist: opponents' hands, request receipts and unused tiles
// never leave the server, including after a round or in an error response.
export function dominoView(r) {
  const s=r.state||{},me=r.me,players=r.players||[];
  return {id:r.id,host:r.host,capacity:r.capacity,name:r.name,revision:r.revision,me,expiresAt:r.expiresAt,
    phase:s.phase||'waiting',round:s.round||0,board:s.board||[],turn:s.turn||null,opener:!s.board?.length?s.opener:null,last:s.last||'',result:s.result||null,
    wins:s.wins||{},points:s.points||{},hand:s.hands?.[me]||[],legal:dominoLegal(s,me),
    players:players.map(p=>({...p,ready:s.ready?.[p.id]===true,count:s.hands?.[p.id]?.length??0})),
    signals:r.signals||[],};
}
export function registerDomino(app,{database,authenticate,env=process.env,logger=console}) {
  const rpc=async(user,action,data)=>{
    const r=await database.rpc('korlix_domino_v1',{p_actor:user.id,p_action:action,p_data:data});
    if(r.error){const status={P0001:400,P0002:404,'42501':403,'23505':409,'40001':409,'54000':429,'22P02':400,'23514':400}[r.error.code];if(status)fail(['22P02','23514'].includes(r.error.code)?'Check the table settings and try again.':r.error.message,status);throw Error('Domino storage unavailable');}
    if(!r.data)throw Error('Empty domino response');return r.data;
  };
  app.post('/api/social/domino',async(req,res)=>{
    res.set('Cache-Control','no-store');
    try{
      const user=await authenticate(req,res);if(!user)return;
      const b=req.body;if(!b||Array.isArray(b)||Buffer.byteLength(JSON.stringify(b))>180000)fail('This table request is too large.');
      const action=b.action;
      if(!['list','create','invite','join','decline','leave','sync','move','media','signal'].includes(action))fail('Domino action not found.',404);
      if(action==='move'){
        const snapshot=await rpc(user,'snapshot',{id:b.id}),move=dominoAction(snapshot,snapshot.me,b.move||{});
        const result=move.replayed?snapshot:await rpc(user,'commit',{id:b.id,revision:snapshot.revision,state:move.state});
        return res.json({table:await socialPhotos(database,dominoView(result))});
      }
      if((action==='signal'||action==='media'&&b.enabled===true)&&env.SOCIAL_CALLS_ENABLED==='false')fail('Video is temporarily unavailable. You can still play.',503);
      const result=await rpc(user,action,b);
      if(action==='list')return res.json(await socialPhotos(database,result));
      if(result.state)return res.json({table:await socialPhotos(database,dominoView(result)),...(action==='sync'?{videoConfig:socialCallConfig(env)}:{})});
      res.json(result);
    }catch(e){if(!(e instanceof DominoError))logger.warn('Domino request failed',{type:e?.name||'Error'});res.status(e instanceof DominoError?e.status:503).json({error:e instanceof DominoError?e.message:'The table could not be updated. Refresh before retrying.'});}
  });
}
