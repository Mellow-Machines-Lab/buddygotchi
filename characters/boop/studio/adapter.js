// The gel slime in the Character Studio (characters/studio/). The slime's
// preview, design/slime-blob/preview/character.mjs (window.SlimeStudio),
// owns the engine, renderer, sound and pointer input; this maps the studio's
// selection onto it and fills the drawer with the slime's own tools.
Studio.register('boop',{
  transport:'live',
  variantLabel:'Gesture',
  create(ctx){
    const profiles=window.SlimeCatalog.expressions,title=id=>id.replaceAll('_',' ').replace(/^\w/,c=>c.toUpperCase());
    ctx.tools.insertAdjacentHTML('beforeend',`
    <section>
      <h4>Event scripts</h4>
      <p>A scripted stretch of a working day: the facts, moods and taps the device would receive.</p>
      <div class="row">
        <label class="grow"><span class="visually-hidden">Event script</span><select data-script></select></label>
        <button type="button" data-play-script>Play script</button>
        <button type="button" data-stop-script>Stop</button>
      </div>
      <p class="hint" data-script-status>Each run starts a fresh seeded slime.</p>
    </section>
    <section>
      <h4>Review clips</h4>
      <p>Records silent clips of the representative scenes or the mood-to-mood bridges, straight from the canvas.</p>
      <div class="row">
        <label class="grow"><span class="visually-hidden">Review set</span><select data-review-set><option value="activities">Representative activities</option><option value="bridges">Directed mood bridges</option></select></label>
        <button type="button" data-record>Record review set</button>
        <button type="button" data-save-review disabled>Save review clips locally</button>
      </div>
      <p class="hint" data-record-status>Saving needs the studio's server started with --capture-dir.</p>
      <div class="gallery" data-review-gallery></div>
    </section>
    <section>
      <h4>Sound sketches</h4>
      <p>Each of the slime's sounds on its own. Playing one mutes the animation's sound.</p>
      <div class="row wrap" data-sketches></div>
      <p class="hint" data-sketch-status aria-live="polite">Silent until you pick one.</p>
    </section>`);
    const $=selector=>ctx.tools.querySelector(selector);
    const slime=window.SlimeStudio.create({root:ctx.root,stage:ctx.stage,onChange:ctx.onChange});
    let face=null,fact='',choice=null,run=slime.runs;

    for(const name of Object.keys(window.SlimeScripts||{})){const o=document.createElement('option');o.value=name;o.textContent=name.replace('.jsonl','').replaceAll('-',' ');$('[data-script]').append(o);}
    $('[data-play-script]').addEventListener('click',()=>slime.playScript($('[data-script]').value));
    $('[data-stop-script]').addEventListener('click',()=>{slime.stopScript();$('[data-script-status]').textContent='Script stopped. The slime keeps its last facts.';});
    const sketches={squish:'Gel squish',bounce:'Soft landing',wobble:'Elastic wobble',poke:'Tiny poke',keyboard:'Crisp key',tear:'Tear plip',knock_ding:'Knock → ding',complete:'Success swell',failed:'Failure cue',sneeze:'Little sneeze',breath:'Snore breath'};
    let sketchCount=0;
    for(const [name,label] of Object.entries(sketches)){
      const b=document.createElement('button');b.type='button';b.textContent=label;
      b.addEventListener('click',async()=>{
        try{ctx.setSound(false);const result=await SlimeSFX.play(name,{variant:sketchCount++%3,seed:1729+sketchCount});$('[data-sketch-status]').textContent=`${label} · sketch ${result.variant+1} · ${result.duration.toFixed(2)} s`;}
        catch(error){$('[data-sketch-status]').textContent=error.message;}
      });
      $('[data-sketches]').append(b);
    }
    const stopSketch=document.createElement('button');stopSketch.type='button';stopSketch.textContent='Stop sound';
    stopSketch.addEventListener('click',()=>{SlimeSFX.stop();$('[data-sketch-status]').textContent='Sound stopped.';});$('[data-sketches]').append(stopSketch);
    const onHidden=()=>{if(document.hidden)SlimeSFX.stop();};document.addEventListener('visibilitychange',onHidden);

    return {
      slime,
      select(s){
        const want=s.face||s.mood;
        // A script or review run rebuilt the slime; apply the whole selection again.
        if(run!==slime.runs){run=slime.runs;face=fact=choice=null;}
        if(want!==face){face=want;slime.setFace(want);choice='auto';}
        const key=[s.state,s.outcome,s.context].join('/');
        if(key!==fact){fact=key;slime.setState(s.state,{outcome:s.outcome,context:s.context});}
        // Idle's takes: the mood's three gestures, then its comedy (its own
        // gags and every mood's idle gags), as the engine deals them.
        const catalog=window.SlimeCatalog,gags=[...(profiles[want].gags||[]),...(catalog.idleGags||[])].map(name=>catalog.gags[name]);
        const takes=[...profiles[want].performances,...gags];
        const next=s.variant===0?'auto':String(Math.min(s.variant,takes.length)-1);
        if(next!==choice){choice=next;slime.perform(next);}
        return {variants:['Any gesture, at its own pace',...takes.map((p,i)=>`${i<3?'Gesture':'Comedy'} ${i+1} · ${p.label}`)],caption:''};
      },
      faces(mood){
        const ids=Object.keys(profiles).filter(id=>id.includes(':')&&profiles[id].mood===mood);
        return [{id:mood,label:'Standard'},...ids.map(id=>({id,label:title(id.split(':')[1])}))];
      },
      get paused(){return slime.paused;},
      setPaused(on){slime.setPaused(on);},
      replay(){const s=ctx.selection;slime.setState(s.state,{outcome:s.outcome,context:s.context});},
      poke(){slime.poke();},
      shake(){slime.shake();},
      busy(){return slime.review.active;},
      setSound(){slime.setVolume(ctx.volume);if(ctx.sound)slime.enableSound().catch(()=>{});else slime.muteSound();},
      status(){
        const script=slime.script;
        if(script)$('[data-script-status]').textContent=`Playing ${script.name.replace('.jsonl','')} · ${script.seconds.toFixed(1)} s`;
        return `${profiles[slime.expression]?.label||''} · ${slime.activity()} · ${slime.sceneText()}`+(script?` · script ${script.name} ${script.seconds.toFixed(1)} s`:'');
      },
      destroy(){slime.destroy();SlimeSFX.stop();document.removeEventListener('visibilitychange',onHidden);ctx.tools.replaceChildren();}
    };
  }
});
