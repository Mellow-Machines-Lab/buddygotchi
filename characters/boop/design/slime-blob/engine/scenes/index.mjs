import {createVariations} from '../variation.mjs';
import {sceneConstants,implementedStates} from './constants.mjs';
import {deskRecipe} from './desk.mjs';
import {alertRecipe} from './alert.mjs';
import {resultRecipe,statusResultRecipe} from './result.mjs';
import {restRecipe,snore} from './rest.mjs';
import {idleRecipe} from './idle.mjs';
import {listenRecipe} from './listen.mjs';
import {startRecipe,wakeRecipe} from './start.mjs';
import {helpersRecipe} from './helpers.mjs';
import {touchRecipe} from './touch.mjs';
import {gestureRecipe} from './gesture.mjs';
import {occasionShare,fits,lookOccasions,realizeOccasion} from './occasion.mjs';
import {recoveryGesture} from './profile.mjs';
import {sceneMoodTraits} from './mood.mjs';
import {createRamp} from './ramp.mjs';

const clamp=(x,lo,hi)=>Math.min(hi,Math.max(lo,x));
const smooth=x=>{const t=clamp(x,0,1);return t*t*(3-2*t);};
const isDesk=state=>['working','planning','terminal','tool_use','searching','analyzing','testing','delegating','waiting'].includes(state);
// Asleep picks again after each take, as routine work does, so it can snore.
const routine=state=>isDesk(state)||state==='listening'||state==='asleep';
// A state's takes: three, and a fourth for two of them, asleep's snore and a
// successful finish's hiccups. Its bag deals the fourth from its second round.
// A gesture has one for each gesture, which the board names, never dealt.
export function takesOf(state,outcome=null) {
  return state==='gesture'?10:state==='asleep'||(state==='task_complete'&&outcome==='success')?4:3;
}
const implemented=new Set(implementedStates);
// CONTINUITY.md, Representative activity scenes: each prop keeps the content
// it last showed while its ramp fades it out.
const propNames=['alert','result','start','helpers','listening','touch'];
const hiddenContent=Object.freeze({alert:{requestId:null,agent:'',project:'',name:'',more:0},
  result:{state:null,label:'FINISHED',outcome:null,reveal:0},start:{label:'START',ctx:null,reveal:0},
  helpers:{mode:'dispatch',count:0,progress:0,report:false,direction:1,presence:0},listening:{pulse:.5},touch:{kind:null}});

export function createScenes({rand,reduced,profiles,gestures=[],notices=[],occasions=[],occasion={when:new Set(),lookMs:0}}) {
  const looks=lookOccasions(occasions).map((entry,index)=>({...entry,index}));
  const variation=createVariations(rand),alerts=new Map(),moments=new Map();
  const activity={lean:{x:0,v:0},squash:{x:0,v:0},forward:{x:0,v:0}};
  const desk={x:0,v:0},quietMix={x:0,v:0};
  let route=null,mood='calm',expression='calm',generation=0,iteration=0,variant=0;
  let started=0,recipe=null,cursor=0,contacts=[],lastContact=null,resultRevealed=false,revealAt=0;
  let phase='sustain',ageMs=0,completed=false,quietRestored=false;
  const slots=Object.fromEntries(propNames.map(name=>[name,{key:null,ramp:createRamp(sceneConstants.propRampMs),content:{...hiddenContent[name]}}]));
  function phaseAt(age) {
    return age<sceneConstants.entryMs?'enter':age<recipe.duration-sceneConstants.recoveryMs?'act':age<recipe.duration?'recover':'sustain';
  }
  function pickRecipe(time) {
    started=time;ageMs=0;cursor=0;completed=false;lastContact=null;resultRevealed=false;
    const key=[mood,route.state,route.outcome||route.ctx||''].join(':');
    if(route.moment&&moments.has(route.moment.requestId)){
      const saved=moments.get(route.moment.requestId);variant=saved.variant;recipe=saved.recipe;
      phase='enter';return;
    }
    // The host's take if its state has it; the first rest is always the
    // still one, and asleep deals from its bag after that. A look deals an
    // occasion's take instead, while one fits, occasionShare of the time
    // (numbered after the state's own); a gesture's take is the board's, or
    // the first.
    const takes=takesOf(route.state,route.outcome);
    const asked=Boolean(route.moment&&route.moment.variant!==null&&route.moment.variant<takes);
    const deal=!asked&&route.state!=='gesture'&&(implemented.has(route.state)&&!route.quiet&&route.state!=='idle'
      ||route.state==='asleep'&&iteration>0);
    let look=null;
    if(deal&&!route.moment){
      const fit=looks.filter(entry=>entry.state===route.state&&fits(entry,occasion));
      if(fit.length&&rand()<occasionShare)look=fit[Math.floor(rand()*fit.length)];
    }
    variant=asked?route.moment.variant:look?takes+look.index:deal?variation.next(key,takes):0;
    const profile=profiles[expression];
    if(look)recipe=realizeOccasion(look.recipe,rand);
    else if(route.state==='gesture')recipe=gestureRecipe(gestures,variant);
    else if(route.state==='notice')recipe=gestureRecipe(notices,variant);
    else if(route.family==='desk')recipe=deskRecipe(route.state,mood,variant,rand,profile);
    else if(route.state==='needs_you'){
      recipe=alertRecipe(variant,mood,profile);
    }else if(route.state==='task_complete')recipe=resultRecipe(route.outcome,variant,mood,profile);
    else if(route.family==='result')recipe=statusResultRecipe(route.state,variant,mood,profile);
    else if(route.state==='starting')recipe=startRecipe(route.ctx,variant,mood,profile);
    else if(route.state==='wake_up')recipe=wakeRecipe(variant,mood,profile);
    else if(route.family==='helpers')recipe=helpersRecipe(route.state,variant,mood,profile);
    else if(route.family==='touch')recipe=touchRecipe(route.state,variant);
    else if(route.state==='listening')recipe=listenRecipe(variant);
    else if(route.quiet)recipe=restRecipe(variant);
    else recipe=idleRecipe();
    recipe={...recipe,profile,profileExpression:expression};
    if(route.state==='needs_you')alerts.set(route.requestId,{variant,recipe,ageMs:0,cursor:0});
    if(route.moment)moments.set(route.moment.requestId,{variant,recipe});
    phase='enter';
  }
  function setRoute(next,time,nextExpression) {
    expression=nextExpression;mood=profiles[expression].mood;
    if(route&&route.state===next.state&&route.requestId===next.requestId){route=next;return;}
    // An alert left before its knocks and ding finished keeps its place, so
    // each request signals exactly once however it is interrupted.
    if(route?.state==='needs_you'&&alerts.has(route.requestId))Object.assign(alerts.get(route.requestId),{ageMs,cursor});
    route=next;generation++;iteration=0;contacts=[];resultRevealed=false;
    quietRestored=route.state==='needs_you'&&alerts.has(route.requestId);
    if(quietRestored){
      const saved=alerts.get(route.requestId);
      variant=saved.variant;recipe=saved.recipe;lastContact=null;
      if(saved.cursor>=recipe.contacts.length){
        started=time-recipe.duration;ageMs=recipe.duration;cursor=recipe.contacts.length;
        completed=true;phase='sustain';
      }else {
        started=time-saved.ageMs;ageMs=saved.ageMs;cursor=saved.cursor;completed=false;phase=phaseAt(ageMs);
      }
    }else {
      const returning=Boolean(route.moment&&moments.has(route.moment.requestId));
      pickRecipe(time);
      if(returning){
        iteration=Math.floor((time-route.moment.startedAt)/recipe.duration);
        started=route.moment.startedAt+iteration*recipe.duration;ageMs=time-started;
        cursor=recipe.contacts.filter(contact=>contact.at<=ageMs).length;
        for(const contact of recipe.contacts.slice(0,cursor))if(contact.kind.endsWith('_reveal')){resultRevealed=true;revealAt=contact.at;}
      }
    }
  }
  function envelope(time,kind) {
    if(!lastContact||lastContact.kind!==kind)return 0;
    const age=time-lastContact.timeMs;
    return age>=0&&age<sceneConstants.contactMs?Math.cos(age/sceneConstants.contactMs*Math.PI/2)**2:0;
  }
  function advance(dt,time,{grabActive=false}={}) {
    contacts=[];
    if(!route)return null;
    if(completed){
      if(route.moment&&route.moment.name!=='listening'){
        if(iteration+1>=route.loops){if(!route.moment.hold)return route.moment.requestId;}
        else {iteration++;pickRecipe(time);}
      }else if(routine(route.state)){iteration++;pickRecipe(time);}
    }
    ageMs=Math.max(0,time-started);
    if(route.quiet||!implemented.has(route.state)||route.state==='idle'){
      phase=ageMs<sceneConstants.entryMs?'enter':'sustain';
      if((route.moment||route.state==='asleep')&&ageMs>=recipe.duration)completed=true;
    }else if(ageMs<sceneConstants.entryMs)phase='enter';
    else if(ageMs<recipe.duration-sceneConstants.recoveryMs)phase='act';
    else if(ageMs<recipe.duration)phase='recover';
    else {phase='sustain';completed=true;}
    // Elapsed contacts are consumed even during a grab. Releasing never plays
    // a backlog, and retargeting replaces the recipe cursor immediately.
    // Quiet rest has no contacts but a snore's breaths.
    while(cursor<recipe.contacts.length&&ageMs>=recipe.contacts[cursor].at){
      const cue=recipe.contacts[cursor],index=cursor++;
      if((route.quiet&&cue.kind!=='breath_contact')||(grabActive&&!cue.kind.endsWith('_reveal')))continue;
      const event={id:route.requestId+':'+generation+':'+iteration+':'+index,kind:cue.kind,
        requestId:route.requestId,generation,iteration,index,timeMs:time,side:cue.side,strength:cue.strength};
      contacts.push(event);lastContact=event;
      if(cue.kind.endsWith('_reveal')&&cue.kind!=='alert_reveal'){resultRevealed=true;revealAt=cue.at;}
    }
    const active=!grabActive&&!route.quiet;
    const attack=smooth(ageMs/sceneConstants.entryMs);
    const recovery=phase==='recover'?smooth((recipe.duration-ageMs)/sceneConstants.recoveryMs):phase==='sustain'?0:1;
    const contact=active?Math.max(envelope(time,'key_contact'),envelope(time,'screen_knock'),envelope(time,'body_contact'))*(lastContact?.strength||1):0;
    const scale=reduced.matches?.18:1;
    const success=route.state==='task_complete'&&route.outcome==='success';
    const failure=route.state==='task_complete'&&route.outcome==='failure';
    const reveal=active?Math.max(envelope(time,'success_reveal'),envelope(time,'failure_reveal'))*(lastContact?.strength||1):0;
    const present=active?Math.max(...['start_reveal','helper_reveal','reply_ready_reveal','error_reveal','stopped_reveal'].map(kind=>envelope(time,kind)))*(lastContact?.strength||1):0;
    const recoveryPose=active&&phase==='recover'&&!recipe.gag?recoveryGesture(recipe.profile,variant,1-(recipe.duration-ageMs)/sceneConstants.recoveryMs):{lean:0,squash:0,forward:0};
    const quietActivity=route.state==='waiting'||route.state==='listening';
    const wave=quietActivity?.65+.35*Math.sin(ageMs/recipe.duration*Math.PI*2*(recipe.focusCycles||recipe.pulseCycles||1)):1;
    // A snore's breath swells the sleeping body a little, rising and falling.
    const swell=route.quiet&&lastContact?.kind==='breath_contact'&&time-lastContact.timeMs<snore.swellMs?
      Math.sin((time-lastContact.timeMs)/snore.swellMs*Math.PI)**2*lastContact.strength*snore.swell:0;
    const target={
      lean:active?(recipe.lean*attack*recovery*wave+(lastContact?.side||0)*contact*.024+recoveryPose.lean)*scale:0,
      squash:active?(-contact*.052+(success?.036:failure?-.048:0)*reveal+present*.018+recoveryPose.squash)*scale:swell*scale,
      forward:active?(contact*.045+(success?.025:failure?-.035:0)*reveal+present*(route.state==='error'?-.025:.018)+recoveryPose.forward)*scale:0
    };
    for(const [name,m] of Object.entries(activity)){
      const limit=sceneConstants.activityBounds[name];let left=dt;
      while(left>0){const h=Math.min(left,1/240);m.v+=(sceneConstants.activityFrequency**2*(target[name]-m.x)-sceneConstants.activityDamping*m.v)*h;m.x+=m.v*h;left-=h;}
      m.x=clamp(m.x,-limit,limit);m.v=clamp(m.v,-sceneConstants.activityVelocity,sceneConstants.activityVelocity);
    }
    const deskTarget=isDesk(route.state)||isDesk(route.baseState)?1:0;
    let left=dt;
    while(left>0){const h=Math.min(left,1/240);desk.v+=(sceneConstants.propFrequency**2*(deskTarget-desk.x)-sceneConstants.propDamping*desk.v)*h;desk.x+=desk.v*h;left-=h;}
    desk.x=clamp(desk.x,0,1);
    left=dt;
    while(left>0){const h=Math.min(left,1/240);quietMix.v+=(sceneConstants.activityFrequency**2*(Number(route.quiet)-quietMix.x)-sceneConstants.activityDamping*quietMix.v)*h;quietMix.x+=quietMix.v*h;left-=h;}
    quietMix.x=clamp(quietMix.x,0,1);
    updateProps(time);
    return null;
  }
  function recoveryFactor() {
    return phase==='recover'?smooth((recipe.duration-ageMs)/sceneConstants.recoveryMs):phase==='sustain'?0:1;
  }
  // A card rises over the prop ramp from its reveal contact and fades in recovery.
  function cardReveal() {
    return resultRevealed?smooth((ageMs-revealAt)/sceneConstants.propRampMs)*recoveryFactor():0;
  }
  function focus() {
    const progress=clamp(ageMs/recipe.duration,0,1);
    return reduced.matches?.5:.5+.5*Math.sin(progress*Math.PI*2*(recipe.focusCycles||recipe.pulseCycles||1));
  }
  function propKey(name) {
    const state=route.state;
    if(name==='alert')return state==='needs_you'?'alert':null;
    if(name==='result')return route.family==='result'?route.requestId:null;
    if(name==='start')return state==='starting'?route.requestId:null;
    if(name==='helpers')return route.family==='helpers'?route.requestId+':'+iteration:null;
    if(name==='listening')return state==='listening'?route.requestId:null;
    return route.family==='touch'?route.requestId:null;
  }
  function liveContent(name) {
    const attn=route.attention||{};
    if(name==='alert')return {requestId:route.requestId,agent:attn.agent||'',project:attn.project||'',name:attn.name||'',more:attn.more||0};
    // A gift (proud's bug) shows beside its card; the key appears only with one.
    if(name==='result')return {state:route.state,label:recipe.label||(route.outcome==='success'?'COMPLETE':route.outcome==='failure'?'FAILED':'FINISHED'),
      outcome:route.outcome,reveal:cardReveal(),...(recipe.gift?{gift:true}:{})};
    if(name==='start')return {label:recipe.label,ctx:route.ctx,reveal:cardReveal()};
    if(name==='helpers')return {mode:route.state==='helper_return'?'return':'dispatch',count:recipe.helperCount,
      progress:smooth(ageMs/(recipe.contacts.at(-1)?.at||recipe.duration)),report:route.state==='helper_return'&&resultRevealed,
      direction:recipe.helperDirection||1,presence:recoveryFactor()};
    if(name==='listening')return {pulse:focus()};
    return {kind:route.state};
  }
  // What of a prop's ramp is drawn: a card's reveal, the helpers' recovery.
  function drawnFactor(name,content) {
    return name==='result'||name==='start'?content.reveal:name==='helpers'?content.presence:1;
  }
  // A prop whose route ends fades out with its last content. New content
  // (a new request, or the helpers' next cycle) waits until nothing of the
  // old is drawn, then fades in from zero.
  function updateProps(time) {
    for(const name of propNames){
      const slot=slots[name],key=propKey(name);
      if(slot.key!==key&&slot.ramp.value(time)*drawnFactor(name,slot.content)===0){slot.key=key;slot.ramp.reset();}
      if(key!==null&&slot.key===key){slot.content=liveContent(name);slot.ramp.retarget(1,time);}
      else slot.ramp.retarget(0,time);
    }
  }
  function inspect(time) {
    const state=route.state,alert=state==='needs_you';
    const ramp=name=>slots[name].ramp.value(time),content=name=>slots[name].content;
    const progress=clamp(ageMs/recipe.duration,0,1);
    const alertVisible=ramp('alert'),result=content('result'),start=content('start'),helpers=content('helpers');
    const resultVisible=ramp('result')*result.reveal;
    return {
      scene:{state,family:route.family,implemented:implemented.has(state),quiet:route.quiet,
        phase,variant,iteration,generation,ageMs,requestId:route.requestId,outcome:route.outcome,ctx:route.ctx,
        intent:recipe.intent,loops:route.loops,restored:quietRestored,loopDurationMs:recipe.duration,quietMix:quietMix.x,
        profile:{expression:recipe.profileExpression,performanceType:recipe.profile?.performances[variant]?.type||null,
          recoveryGesture:!route.quiet&&!sceneMoodTraits[recipe.profile?.mood]}},
      props:{
        desk:{id:'desk-1',visible:desk.x,x:.5,y:.64,screen:isDesk(state)?state:isDesk(route.baseState)?route.baseState:'working',
          contact:envelope(time,'key_contact'),side:lastContact?.kind==='key_contact'?lastContact.side:1,focus:focus(),progress,
          status:state==='waiting'?'waiting':state==='planning'?'planning':state==='searching'?'searching':state==='testing'?'testing':state==='analyzing'?'inspecting':state==='tool_use'?'invoking':'neutral'},
        // Each visible is the prop's drawn opacity. Contact envelopes (knock,
        // confirmation, key and touch pulses) are deliberate impacts.
        alert:{...content('alert'),visible:alertVisible,reveal:alertVisible,label:'NEEDS YOU',
          knock:alert?envelope(time,'screen_knock'):0,confirmation:alert?envelope(time,'alert_reveal'):0},
        result:{...result,visible:resultVisible,trophy:resultVisible>0&&result.outcome==='success'},
        start:{...start,visible:ramp('start')*start.reveal},
        helpers:{mode:helpers.mode,count:helpers.count,progress:helpers.progress,report:helpers.report,direction:helpers.direction,
          visible:ramp('helpers')*helpers.presence},
        listening:{visible:ramp('listening'),pulse:content('listening').pulse,lean:activity.lean.x},
        touch:{visible:ramp('touch'),kind:content('touch').kind,pulse:envelope(time,'body_contact')},
        lane:{top:sceneConstants.hostLaneTop}
      },
      contacts:contacts.map(contact=>({...contact})),
      activityChannels:Object.fromEntries(Object.entries(activity).map(([key,m])=>[key,{...m}]))
    };
  }
  // The gag the recipe playing carries for acting (a gesture's, an
  // occasion's), and which pass of it this is; null for none.
  function gag() {return route&&recipe?.gag?{name:recipe.gag,key:generation+':'+iteration}:null;}
  return {setRoute,advance,inspect,gag,activity,variation:variation.inspect};
}
