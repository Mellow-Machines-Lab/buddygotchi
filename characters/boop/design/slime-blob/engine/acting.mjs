import {createVariations} from './variation.mjs';

const clamp=(x,lo,hi)=>Math.min(hi,Math.max(lo,x));
const smooth=x=>{const t=clamp(x,0,1);return t*t*(3-2*t);};
// A gag's own channels, beside the six gesture springs: the dome's slide
// across the screen, and how far its lids are closed (critically damped).
export const gagSprings=Object.freeze({slide:Object.freeze({frequency:10,damping:9,limit:.7,velocity:5}),
  lids:Object.freeze({frequency:24,damping:48,limit:1,velocity:20})});
// A gag's keys set a channel's target: from (0, 0) at its start, a smoothstep
// to each of the channel's keys in turn, then its last value.
export function keyed(keys,channel,age) {
  let from=0,value=0;
  for(const [at,name,next] of keys){
    if(name!==channel)continue;
    if(age<at)return value+(next-value)*smooth((age-from)/(at-from));
    from=at;value=next;
  }
  return value;
}

// Authored gesture recipes and their original additive spring parameters.
// Retargeting cancels future recipe cues; it never replaces these springs.
// Idle's takes are the expression's three gestures, then its own gags and
// every expression's idle gags: comedy that adds keyed targets and contacts
// that sound to the same springs.
export function createActing({profiles,gags={},idleGags=[],rand,reduced,initialEmotion}) {
  const channels={lean:{x:0,v:0},squash:{x:0,v:0},ripple:{x:0,v:0},lift:{x:0,v:0},roll:{x:0,v:0},forward:{x:0,v:0}};
  const own={slide:{x:0,v:0},lids:{x:0,v:0}},springs={...channels,...own};
  const automaticVariants=createVariations(rand);
  let emotion=initialEmotion,actor=null,nextPerformance=1,performanceCount=0;
  let chosenPerformance='auto',suppressed=false,gagged=false,contacts=[];
  function takes(id) {
    const profile=profiles[id];
    return [...profile.performances,...[...(profile.gags||[]),...idleGags].map(name=>({...gags[name],type:name}))];
  }
  function perform(time,index) {
    if(suppressed)return false;
    const choices=takes(emotion);
    let selected=index===undefined?(chosenPerformance==='auto'?automaticVariants.next(emotion+':idle',choices.length):Number(chosenPerformance)):Number(index);
    if(!Number.isInteger(selected))throw new TypeError('performance index must be an integer');
    selected=clamp(selected,0,choices.length-1);
    actor={...choices[selected],index:selected,start:time,cursor:0,contactCursor:0,expression:emotion};
    if(actor.keys)gagged=true;
    performanceCount++;
    nextPerformance=time+actor.duration+7+rand()*8;
    return true;
  }
  return {
    channels,perform,takes,
    setMood(value,time) {emotion=value;actor=null;nextPerformance=time+.4;},
    setPerformance(value) {
      if(String(value)!=='auto'&&!/^\d+$/.test(String(value)))throw new RangeError('unknown performance selection');
      chosenPerformance=String(value);
    },
    deferUntil(time) {nextPerformance=Math.max(nextPerformance,time);},
    setSuppressed(value,time) {
      value=Boolean(value);if(value===suppressed)return;
      suppressed=value;actor=null;
      if(!value)nextPerformance=Math.max(nextPerformance,time+.4);
    },
    advance(dt,time,grabActive) {
      contacts=[];
      if(!suppressed&&!grabActive&&time>=nextPerformance)perform(time);
      const target={},scale=reduced.matches?.18:1;
      if(!suppressed&&actor&&actor.expression===emotion){
        const age=time-actor.start;
        while(actor.cursor<actor.cues.length&&age>=actor.cues[actor.cursor][0]){
          const [,channel,velocity]=actor.cues[actor.cursor++];
          springs[channel].v+=velocity*scale;
        }
        if(actor.keys)for(const name of Object.keys(springs)){
          const value=keyed(actor.keys,name,age);
          if(value)target[name]=name==='lids'?value:value*scale;
        }
        // A gag's contacts are its sounds; they move nothing themselves.
        while(actor.contacts&&actor.contactCursor<actor.contacts.length&&age>=actor.contacts[actor.contactCursor][0]){
          const index=actor.contactCursor++,[,kind,strength]=actor.contacts[index];
          contacts.push({id:'gag:'+performanceCount+':0:'+index,kind,requestId:'gag',generation:performanceCount,iteration:0,index,
            timeMs:time*1000,side:0,strength});
        }
      }
      for(const [name,m] of Object.entries(channels)){
        let left=dt;const frequency=name==='lift'?11:name==='roll'?10:9,goal=target[name]||0;
        while(left>0){const h=Math.min(left,1/240);m.v+=(-frequency*frequency*(m.x-goal)-6.4*m.v)*h;m.x+=m.v*h;left-=h;}
        const limit=name==='lift'?.24:name==='roll'?.12:name==='forward'?.18:.42;
        m.x=clamp(m.x,-limit,limit);m.v=clamp(m.v,-5,5);
      }
      for(const [name,m] of Object.entries(own)){
        const spring=gagSprings[name],goal=target[name]||0;let left=dt;
        while(left>0){const h=Math.min(left,1/240);m.v+=(spring.frequency*spring.frequency*(goal-m.x)-spring.damping*m.v)*h;m.x+=m.v*h;left-=h;}
        m.x=clamp(m.x,-spring.limit,spring.limit);m.v=clamp(m.v,-spring.velocity,spring.velocity);
      }
    },
    // The gag's channels as drawn: the slide, and the lids' closure.
    slide() {return own.slide.x;},
    lids() {return clamp(own.lids.x,0,1);},
    get gagged() {return gagged;},
    get contacts() {return contacts;},
    inspect(time) {
      // A gag's channels join what's inspected once one has played, so a
      // trace without comedy keeps its columns.
      return {performanceCount,nextPerformance,actingSuppressed:suppressed,performance:actor?{label:actor.label,type:actor.type,index:actor.index,
        expression:actor.expression,age:time-actor.start,duration:actor.duration}:null,
        actorChannels:Object.fromEntries(Object.entries(gagged?springs:channels).map(([name,m])=>[name,{x:m.x,v:m.v}]))};
    }
  };
}
