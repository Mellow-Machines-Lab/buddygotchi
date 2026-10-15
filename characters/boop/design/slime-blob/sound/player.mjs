// The output backend owns audio buffers, never the animation clock or motion.
export const playerPolicy=Object.freeze({lateMs:150,voices:4,fadeSeconds:.004,routineDuck:.25});
export function createPlayer({sfx,makeContext=()=>new (window.AudioContext||window.webkitAudioContext)()}) {
  let context=null,muted=true,volume=1,voiceActive=false,generation=null,lastId=null,expression=null;
  const active=[],seen=new Set();
  function stop(handle,immediate=false) {
    const at=context.currentTime,fade=immediate?0:playerPolicy.fadeSeconds;
    handle.level.gain.cancelScheduledValues(at);handle.level.gain.setValueAtTime(handle.level.gain.value,at);
    handle.level.gain.linearRampToValueAtTime(0,at+fade);handle.source.stop(at+fade);handle.stopping=true;
    if(immediate){const index=active.indexOf(handle);if(index>=0)active.splice(index,1);}
  }
  function stopAll(immediate=false){for(const handle of [...active])stop(handle,immediate);}
  function gain(handle){return volume*(voiceActive&&!handle.protected?playerPolicy.routineDuck:1);}
  return {
    async enable(){context=context||makeContext();await context.resume();muted=false;},
    setMix(value={}) {
      if(value.muted!==undefined)muted=Boolean(value.muted);
      if(value.volume!==undefined)volume=Math.max(0,Math.min(1,Number.isFinite(value.volume)?value.volume:0));
      if(value.voiceActive!==undefined)voiceActive=Boolean(value.voiceActive);
      if(muted||volume===0)stopAll(true);
      else if(context)for(const handle of active.filter(handle=>!handle.stopping))handle.level.gain.setValueAtTime(gain(handle),context.currentTime);
    },
    stop(){stopAll();},
    reset(){stopAll(true);generation=null;expression=null;seen.clear();lastId=null;},
    consume({channels,cues}) {
      const next=channels.scene.generation;
      if(generation!==next){stopAll();generation=next;seen.clear();}
      else if(expression!==channels.expression)for(let i=active.length-1;i>=0;i--)if(!active[i].protected&&!active[i].stopping)stop(active[i]);
      expression=channels.expression;
      for(const cue of cues){
        if(seen.has(cue.id))continue;seen.add(cue.id);lastId=cue.id;
        // Consume even when muted/suspended: unlocking audio never catches up.
        if(muted||volume===0||!context||context.state!=='running'||channels.time*1000-cue.timeMs>playerPolicy.lateMs)continue;
        const clip=sfx.render(cue.recipe,{...cue,sampleRate:context.sampleRate});
        const buffer=context.createBuffer(1,clip.data.length,clip.sampleRate);buffer.copyToChannel(clip.data,0);
        const source=context.createBufferSource(),level=context.createGain();
        const handle={source,level,protected:cue.protected};source.buffer=buffer;source.connect(level);level.connect(context.destination);
        level.gain.setValueAtTime(gain(handle),context.currentTime);
        if(active.length>=playerPolicy.voices)stop(active[0],true);active.push(handle);
        source.onended=()=>{const index=active.indexOf(handle);if(index>=0)active.splice(index,1);source.disconnect();level.disconnect();};
        source.start();
      }
    },
    inspect(){return {enabled:!muted,active:active.filter(handle=>!handle.stopping).length,lastId,volume,voiceActive};}
  };
}
