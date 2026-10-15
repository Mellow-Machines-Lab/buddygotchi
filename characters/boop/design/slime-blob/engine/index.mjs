import {createClock} from './clock.mjs';
import {createPRNG} from './prng.mjs';
import {createCues} from './cues.mjs';
import {createActor} from './actor.mjs';

export function createSlime({seed=1729,catalog,reducedMotion=false}={}) {
  const candidate=catalog?.expressions;
  const profiles=candidate?.expressions||candidate;
  if(!profiles||!profiles.calm?.art)throw new TypeError('catalog.expressions must contain the expression profiles');
  const clock=createClock(),reduced={matches:Boolean(reducedMotion)};
  const cues=createCues({seed,plan:catalog.sound});
  const actor=createActor({profiles,graph:catalog.graph,rand:createPRNG(seed),reduced});
  return {
    setMood:actor.setMood,setFacts:actor.setFacts,poke:actor.poke,shake:actor.shake,
    clearTransient:actor.clearTransient,holdExpression:actor.holdExpression,oneShot:actor.oneShot,setLinkTimedOut:actor.setLinkTimedOut,
    perform:actor.perform,setPerformance:actor.setPerformance,
    dragStart:actor.dragStart,dragMove:actor.dragMove,dragEnd:actor.dragEnd,
    setPaused:actor.setPaused,setHidden:actor.setHidden,
    setReducedMotion:actor.setReducedMotion,
    inspect:actor.inspect,
    step(ms) {actor.frame(clock.stamp(ms));const channels=actor.channels();return {channels,cues:cues.consume(channels)};}
  };
}
