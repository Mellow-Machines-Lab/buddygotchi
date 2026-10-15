// Pixel in the Character Studio (characters/studio/): the animation bank's
// player, design/boop-sound-bank-v4/dist/boop-runtime.js (window.Boop), plays
// each mood and state's recorded-length variations.
Studio.register('pixel',{
  transport:'clip',
  variantLabel:'Variation',
  create(ctx){
    const Boop=window.Boop,lower=s=>s.replace(/^\w/,c=>c.toLowerCase());
    const mount=document.createElement('div');mount.className='pixel-stage';ctx.stage.append(mount);
    let scene=null,playing=false,progress=null,error='',seen=null;
    const player=Boop.createBoopPlayer({mount,volume:0,
      onStatus:({phase,message})=>{playing=phase==='preparing'||phase==='playing';if(phase==='finished')progress=null;error=phase==='error'?message:'';ctx.onChange();},
      onProgress:p=>{progress=p;ctx.onChange();}});
    const coverage=document.createElement('section');coverage.append(document.createElement('h4'),document.createElement('p'));
    coverage.firstChild.textContent='Coverage';ctx.tools.append(coverage);
    function variants(s){
      let l=Boop.catalog.filter(a=>a.mood===s.mood&&a.state===s.state);
      const by=(key,value)=>{const f=l.filter(a=>a[key]===value);if(f.length)l=f;};
      if(s.state==='task_complete')by('outcome',s.outcome);
      if(s.state==='starting')by('startContext',s.context);
      return l;
    }
    return {
      select(s){
        const list=variants(s),asset=list[Math.min(s.variant,list.length-1)];
        if(scene?.asset.id!==asset.id){player.stop({notify:false});playing=false;scene=player.show(asset.id);progress=null;}
        if(seen!==s.mood){seen=s.mood;
          coverage.lastChild.textContent=`${s.mood} has ${Boop.catalog.filter(a=>a.mood===s.mood).length} performances across the states. All ${Boop.moods.length} moods together have ${Boop.catalog.length}. Sleep and no-Mac are shared and silent. The art and its sounds are generated from code, so nothing here is a recording.`;}
        return {variants:list.map((a,i)=>`${i+1} of ${list.length} · ${a.name}`),caption:`${asset.name}: ${lower(asset.caption)}`};
      },
      play(){if(!scene)return;error='';player.setVolume(ctx.sound?ctx.volume*.8:0);
        player.playVariation(scene.asset.id,{cycles:ctx.loop?Infinity:1}).catch(e=>{error=e.message;ctx.onChange();});},
      stop(){player.stop();progress=null;},
      get playing(){return playing;},
      get scene(){return scene;},
      get duration(){return scene?.asset.seconds||0;},
      seek(t){player.stop({notify:false});playing=false;const svg=mount.querySelector('svg');if(svg){svg.pauseAnimations();svg.setCurrentTime(t);}
        progress={elapsed:t,duration:scene.asset.seconds,label:'Frame inspection · silent'};ctx.onChange();},
      time(){return progress&&scene?progress.elapsed%scene.asset.seconds:0;},
      setSound(){player.setVolume(ctx.sound?ctx.volume*.8:0);},
      status(){
        if(error)return 'Playback error: '+error;
        if(!scene)return '';
        const seconds=scene.asset.seconds;
        if(!progress)return `${scene.asset.id} · ${seconds.toFixed(1)} s · ${scene.score.policy==='silent'?'silent by design':'press Play'}`;
        return `${scene.asset.id} · ${(progress.elapsed%seconds).toFixed(1)} / ${seconds.toFixed(1)} s · ${progress.label}`;
      },
      find(id){
        const a=Boop.getAsset(id);if(!a)return null;
        const s={mood:a.mood,state:a.state,outcome:a.outcome||'success',context:a.startContext||'new_task'};
        return {...s,variant:variants(s).findIndex(v=>v.id===id)};
      },
      destroy(){player.dispose();mount.remove();coverage.remove();}
    };
  }
});
