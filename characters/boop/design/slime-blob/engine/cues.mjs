import {createPRNG} from './prng.mjs';

// sound/README.md, Synchronized reference cues. No separate sound timer.
const silent=new Set(['idle','asleep','no_app','listening','waiting']);
const routine=new Set(['working','planning','terminal','tool_use','searching','analyzing','testing']);
const recipes={key_contact:'keyboard',body_contact:'squish',screen_knock:'knock',alert_reveal:'ding',
  success_reveal:'complete',failure_reveal:'failed',error_reveal:'failed',start_reveal:'squish',
  helper_reveal:'squish',reply_ready_reveal:'squish',stopped_reveal:'squish',
  sneeze_contact:'sneeze',breath_contact:'breath',zoom_contact:'bounce'};
// Comedy's contacts (idle's sneeze, excited's zoomies, asleep's snore) sound
// even in a quiet state, each with the routine chance.
export const comedyKinds=Object.freeze(new Set(['sneeze_contact','breath_contact','zoom_contact']));
export function createCues({seed,plan}) {
  const rand=createPRNG((seed^0xa511e9b3)>>>0),seen=new Set(),revealed=new Set();
  let cycle=null,count=0;
  return {
    consume(channels) {
      if(!plan)return [];
      const scene=channels.scene,key=[scene.requestId,scene.generation,scene.iteration].join(':');
      if(key!==cycle){cycle=key;count=0;seen.clear();}
      const result=[];
      for(const contact of channels.contacts){
        if(seen.has(contact.id))continue;
        seen.add(contact.id);
        const kind=contact.kind,recipe=recipes[kind];
        if(!recipe)continue;
        const protectedCue=scene.state==='needs_you'||scene.state==='task_complete'||scene.state==='error';
        if(comedyKinds.has(kind)){if(rand()>=plan.mix.routineContactProbability)continue;}
        else {
          if(silent.has(scene.state))continue;
          const reveal=protectedCue&&kind.endsWith('_reveal'),identity=contact.requestId+':'+kind;
          if(reveal){if(revealed.has(identity))continue;revealed.add(identity);}
          if(routine.has(scene.state)){
            if(scene.loopDurationMs<plan.mix.shortLoopMinimumSeconds*1000&&scene.iteration%plan.mix.shortLoopSoundEvery!==0)continue;
            if(count>=plan.mix.maxRoutineGesturesPerCycle||rand()>=plan.mix.routineContactProbability)continue;
            count++;
          }else if(scene.iteration!==0)continue;
        }
        const profile=plan.moodProfiles[channels.mood]||plan.moodProfiles.calm;
        const invariant=recipe==='ding';
        result.push({...contact,id:'sound:'+contact.id,contactId:contact.id,recipe,
          mood:channels.mood,protected:protectedCue,variant:invariant?0:Math.floor(rand()*3),seed:invariant?53:Math.floor(rand()*4294967296),
          pitch:invariant?1:profile.pitch*(plan.seededVariation.pitch[0]+rand()*(plan.seededVariation.pitch[1]-plan.seededVariation.pitch[0])),
          gain:invariant?.45:Math.min(.8,profile.gain*contact.strength*(plan.seededVariation.gain[0]+rand()*(plan.seededVariation.gain[1]-plan.seededVariation.gain[0])))});
      }
      return result;
    }
  };
}
