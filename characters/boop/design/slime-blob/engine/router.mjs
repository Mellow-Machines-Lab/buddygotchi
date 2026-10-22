// Boop vocabulary only. These are visual targets, never a new wire field.
export const stateFamilies=Object.freeze({
  no_app:'rest',asleep:'rest',idle:'idle',listening:'listen',starting:'start',
  planning:'desk',working:'desk',terminal:'desk',tool_use:'desk',searching:'desk',
  analyzing:'desk',testing:'desk',delegating:'helpers',helper_return:'helpers',
  waiting:'desk',needs_you:'alert',reply_ready:'result',task_complete:'result',
  error:'result',stopped:'result',poked:'touch',tap_spam:'touch',
  wake_up:'start'
});
const acts=new Set(['planning','terminal','tool_use','searching','analyzing','testing','delegating','waiting']);
const momentNames=new Set(['starting','helper_return','reply_ready','task_complete','error','stopped','poked','tap_spam','wake_up','react']);
const copy=value=>JSON.parse(JSON.stringify(value));
const text=value=>typeof value==='string'?value:'';
const attentionTuple=attn=>JSON.stringify([attn.id??0,attn.agent,attn.project]);

export function createRouter({hasMood=()=>false}={}) {
  let facts={base:'idle',act:null,attn:null},linkTimedOut=false,listening=null,moment=null,overlay=null;
  let activation=0,sequence=0,attentionRequest=null;
  const seen=new Set();
  function setFacts(value) {
    if(!value||typeof value!=='object'||Array.isArray(value))throw new TypeError('facts must be a complete snapshot object');
    const next=copy(value);
    next.base=['working','asleep'].includes(next.base)?next.base:'idle';
    next.act=next.base==='working'&&acts.has(next.act)?next.act:null;
    const supplied=next.attn&&typeof next.attn==='object'&&!Array.isArray(next.attn)?next.attn:null;
    next.attn=supplied?{id:supplied.id??0,agent:text(supplied.agent),project:text(supplied.project),name:text(supplied.name),more:Math.max(0,Number.isFinite(supplied.more)?Math.trunc(supplied.more):0)}:null;
    if(next.attn&&(!facts.attn||attentionTuple(next.attn)!==attentionTuple(facts.attn))){
      attentionRequest='attention:'+ ++activation+':'+attentionTuple(next.attn);
    }
    if(!next.attn)attentionRequest=null;
    facts=next;
    // A snapshot's attention cuts decorative moments at once. Listening keeps
    // its higher priority until the actual reply/stop signal arrives.
    if(facts.attn){moment=null;overlay=null;}
  }
  function setLinkTimedOut(value) {
    linkTimedOut=Boolean(value);
  }
  function oneShot(value,time=0,overlayLoopMs=3200) {
    if(!value||typeof value!=='object')throw new TypeError('oneShot requires a moment object');
    const name=value.name,args=value.args&&typeof value.args==='object'?copy(value.args):{};
    // A reply ends mic listening even if attention/no-app then refuses its art.
    if(Object.hasOwn(args,'say')&&args.say!==null)listening=null;
    if(name==='stop_listening'){
      const accepted=Boolean(listening);listening=null;
      return {accepted,reason:accepted?'stopped':'not_listening'};
    }
    if(name!=='listening'&&!momentNames.has(name))return {accepted:false,reason:'unknown_name'};
    if(linkTimedOut)return {accepted:false,reason:'no_app'};
    if(name==='listening'){
      if(listening)return {accepted:true,reason:'continued',requestId:listening.requestId};
      moment=null;overlay=null;
      listening={requestId:'listening:'+String(value.id??++sequence)};
      return {accepted:true,reason:'started',requestId:listening.requestId};
    }
    if(listening)return {accepted:false,reason:'listening'};
    if(facts.attn)return {accepted:false,reason:'needs_you'};
    const id=String(value.id??'local-'+ ++sequence),requestId='moment:'+name+':'+id;
    if(seen.has(requestId))return {accepted:false,reason:'duplicate'};
    seen.add(requestId);
    const loops=Math.max(1,Math.min(6,Number.isFinite(args.loops)?Math.trunc(args.loops):1));
    if(name==='react'){
      if(!hasMood(args.mood))return {accepted:false,reason:Object.hasOwn(args,'say')?'voice_only':'nothing'};
      overlay={requestId,expression:args.mood,until:time+overlayLoopMs*loops};
      return {accepted:true,reason:'expression',requestId};
    }
    overlay=null;
    // A host that times its own moments (the board's Behaviour) holds them
    // until it clears them, and may choose the take it has already timed:
    // any of a state's takes (the scene refuses one its state hasn't).
    moment={name,id,requestId,loops,startedAt:time,expiresAt:time+overlayLoopMs*loops,hold:value.hold===true,
      variant:Number.isInteger(args.variant)&&args.variant>=0&&args.variant<=3?args.variant:null,
      outcome:name==='task_complete'&&['success','failure'].includes(args.outcome)?args.outcome:null,
      ctx:name==='starting'&&['new_task','session','continuation','compacted'].includes(args.ctx)?args.ctx:null,
      expression:hasMood(args.mood)?args.mood:null};
    return {accepted:true,reason:'started',requestId};
  }
  function resolve() {
    const baseState=facts.base==='working'?(facts.act||'working'):facts.base;
    const state=linkTimedOut?'no_app':listening?'listening':facts.attn?'needs_you':moment&&moment.name!=='react'?moment.name:baseState;
    const requestId=linkTimedOut?'link-timeout':listening?.requestId||(facts.attn?attentionRequest:moment?.requestId)||'base:'+state;
    return {state,family:stateFamilies[state],requestId,baseState,
      quiet:state==='asleep'||state==='no_app',attention:facts.attn?{...facts.attn}:null,
      moment:moment?{...moment}:null,expression:overlay?.expression||moment?.expression||null,
      overlay:overlay?{...overlay}:null,
      outcome:moment?.outcome||null,ctx:moment?.ctx||null,loops:moment?.loops||1,
      linkTimedOut};
  }
  return {
    setFacts,setLinkTimedOut,oneShot,resolve,
    clearTransient() {listening=null;moment=null;overlay=null;},
    // The host's borrowed expression, held until it says otherwise: on the
    // moment playing, else over the look. Null lets the mood show again.
    holdExpression(expression) {
      if(moment)moment.expression=expression;
      overlay=expression&&!moment?{requestId:null,expression,until:Infinity}:null;
    },
    advance(time) {
      if(overlay&&time>=overlay.until)overlay=null;
      if(moment&&!moment.hold&&time>=moment.expiresAt)moment=null;
    },
    setMomentDuration(requestId,duration) {if(moment?.requestId===requestId)moment.expiresAt=moment.startedAt+duration*moment.loops;},
    finish(requestId) {if(moment?.requestId===requestId)moment=null;},
    facts:()=>copy(facts)
  };
}
