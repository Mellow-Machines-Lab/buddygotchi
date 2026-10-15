import {createVariations} from './variation.mjs';

const clamp=(x,lo,hi)=>Math.min(hi,Math.max(lo,x));

// Authored gesture recipes and their original additive spring parameters.
// Retargeting cancels future recipe cues; it never replaces these springs.
export function createActing({profiles,rand,reduced,initialEmotion}) {
  const channels={lean:{x:0,v:0},squash:{x:0,v:0},ripple:{x:0,v:0},lift:{x:0,v:0},roll:{x:0,v:0},forward:{x:0,v:0}};
  const automaticVariants=createVariations(rand);
  let emotion=initialEmotion,actor=null,nextPerformance=1,performanceCount=0;
  let chosenPerformance='auto',suppressed=false;
  function perform(time,index) {
    if(suppressed)return false;
    const choices=profiles[emotion].performances;
    let selected=index===undefined?(chosenPerformance==='auto'?automaticVariants.next(emotion+':idle'):Number(chosenPerformance)):Number(index);
    if(!Number.isInteger(selected))throw new TypeError('performance index must be an integer');
    selected=clamp(selected,0,2);
    actor={...choices[selected],index:selected,start:time,cursor:0,expression:emotion};
    performanceCount++;
    nextPerformance=time+actor.duration+7+rand()*8;
    return true;
  }
  return {
    channels,perform,
    setMood(value,time) {emotion=value;actor=null;nextPerformance=time+.4;},
    setPerformance(value) {
      if(!['auto','0','1','2'].includes(String(value)))throw new RangeError('unknown performance selection');
      chosenPerformance=String(value);
    },
    deferUntil(time) {nextPerformance=Math.max(nextPerformance,time);},
    setSuppressed(value,time) {
      value=Boolean(value);if(value===suppressed)return;
      suppressed=value;actor=null;
      if(!value)nextPerformance=Math.max(nextPerformance,time+.4);
    },
    advance(dt,time,grabActive) {
      if(!suppressed&&!grabActive&&time>=nextPerformance)perform(time);
      if(!suppressed&&actor&&actor.expression===emotion){
        const age=time-actor.start;
        while(actor.cursor<actor.cues.length&&age>=actor.cues[actor.cursor][0]){
          const [,channel,velocity]=actor.cues[actor.cursor++];
          channels[channel].v+=velocity*(reduced.matches?.18:1);
        }
      }
      for(const [name,m] of Object.entries(channels)){
        let left=dt;const frequency=name==='lift'?11:name==='roll'?10:9;
        while(left>0){const h=Math.min(left,1/240);m.v+=(-frequency*frequency*m.x-6.4*m.v)*h;m.x+=m.v*h;left-=h;}
        const limit=name==='lift'?.24:name==='roll'?.12:name==='forward'?.18:.42;
        m.x=clamp(m.x,-limit,limit);m.v=clamp(m.v,-5,5);
      }
    },
    inspect(time) {
      return {performanceCount,nextPerformance,actingSuppressed:suppressed,performance:actor?{label:actor.label,type:actor.type,index:actor.index,
        expression:actor.expression,age:time-actor.start,duration:actor.duration}:null,
        actorChannels:Object.fromEntries(Object.entries(channels).map(([name,m])=>[name,{x:m.x,v:m.v}]))};
    }
  };
}
