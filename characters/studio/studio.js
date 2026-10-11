// Character Studio: one page for any character pack's moods, states and sounds.
// The page owns the selection, the pickers and the URL. A pack that declares
// a `studio` entry in its character.json brings its own preview: scripts that
// call Studio.register(id, adapter) with the entry's id (README.md, "Writing
// an adapter").
// charactergen.py writes the pack data this reads, window.StudioData (packs.js).
(() => {
  const root=document.getElementById('studio');
  const $=selector=>root.querySelector(selector),$$=selector=>[...root.querySelectorAll(selector)];
  const title=id=>id.replaceAll('_',' ').replace(/^\w/,c=>c.toUpperCase());
  // Each pack's adapters by its entry's id, kept under the pack whose script registered it.
  const adapters={};
  window.Studio={register(id,adapter){adapters[document.currentScript.dataset.pack+'/'+id]=adapter;}};
  const data=window.StudioData;
  if(!data){$('[data-missing]').hidden=false;$('.layout').hidden=true;return;}
  const packs=data.packs;

  // The engine's states, fixed for every character (states.json).
  const stateGroups=data.states.groups,facts=data.states.facts;
  const stateInfo=Object.fromEntries(stateGroups.flatMap(g=>g.states.map(s=>[s.id,{...s,label:s.label||title(s.id)}])));
  const stateIds=Object.keys(stateInfo);

  // A pack's cards: one for each preview it declares, by the entry's id, or the pack alone.
  const cardsOf=pack=>packs[pack].studio.length?packs[pack].studio.map(e=>e.id):[pack];
  const entryOf=(pack,card)=>packs[pack].studio.find(e=>e.id===card);
  const label=card=>entryOf(sel.pack,card)?.label||packs[sel.pack].name;
  const moodOf=id=>packs[sel.pack].moods.find(m=>m.id===id);
  // What a card plays for one of the pack's moods: the mood, else its fallback, else nothing.
  function shows(card,mood,state){
    const covers=entryOf(sel.pack,card)?.covers;
    if(!covers)return mood.id;
    for(const id of [mood.id,mood.fallback])if(id&&covers[id]?.includes(state))return id;
    return null;
  }
  const familyMeta=()=>Object.assign({},...packs[sel.pack].studio.map(e=>e.families||{}));
  function families(){
    const pack=packs[sel.pack],meta=familyMeta();
    // In the order the studio entry lists the families, then any it leaves out.
    const order=Object.keys(meta).filter(f=>pack.moods.some(m=>m.family===f));
    for(const m of pack.moods){const f=m.family||'';if(!order.includes(f))order.push(f);}
    return order.map(f=>({id:f,label:meta[f]?.label||(f?title(f):'Moods'),colour:meta[f]?.colour,moods:pack.moods.filter(m=>(m.family||'')===f)}));
  }
  const colourOf=mood=>familyMeta()[moodOf(mood)?.family||'']?.colour;

  const sel={pack:data.chosen,card:'',mood:'',face:null,state:'idle',outcome:'success',context:'new_task',variant:0};
  let sound=false,volume=.5,started=false,adapter=null,instance=null,info=null,loads={};
  const ctx={root,stage:$('#stage'),tools:$('[data-tools-body]'),get sound(){return sound;},get volume(){return volume;},
    get loop(){return $('[data-loop]').checked;},get selection(){return sel;},onChange:()=>onChange()};

  // A preview's scripts and styles, each once, in order. A script carries its pack's name for register().
  function load(pack,card){
    const entry=entryOf(pack,card);
    if(!entry)return Promise.resolve();
    return loads[pack+'/'+card]??=(async()=>{
      for(const href of entry.styles||[]){const l=document.createElement('link');l.rel='stylesheet';l.href=href;document.head.append(l);}
      for(const src of entry.scripts||[])await new Promise((ok,fail)=>{const s=document.createElement('script');s.src=src;s.dataset.pack=pack;s.onload=ok;s.onerror=()=>fail(Error('Could not load '+src));document.head.append(s);});
    })();
  }

  // ── Pickers ─────────────────────────────────────────────────────────────
  function chip(text,{pressed,hue,borrowed,to,data}){
    const b=document.createElement('button');b.type='button';b.className='chip';b.setAttribute('aria-pressed',String(pressed));
    if(hue)b.style.setProperty('--hue',hue);
    b.append(text);
    if(borrowed){b.classList.add('borrowed');const t=document.createElement('span');t.className='to';t.textContent='→ '+(to?title(to):'none');b.append(t);
      b.title=to?`No art of its own here: ${label(sel.card)} shows ${title(to)}`:`${label(sel.card)} has nothing to show for this mood`;}
    Object.assign(b.dataset,data);return b;
  }
  function group(text,chips){
    const g=document.createElement('div');g.className='group';
    const l=document.createElement('div');l.className='group-label';l.textContent=text;
    const c=document.createElement('div');c.className='chips';c.append(...chips);g.append(l,c);return g;
  }
  function renderCards(){
    const ids=Object.keys(packs);
    $('[data-pack-choice]').hidden=ids.length<2;
    $('[data-pack]').replaceChildren(...ids.map(id=>{const o=document.createElement('option');o.value=id;o.textContent=packs[id].name;return o;}));
    $('[data-pack]').value=sel.pack;
    $('[data-cards]').replaceChildren(...cardsOf(sel.pack).map(id=>{
      const b=document.createElement('button');b.type='button';b.setAttribute('role','tab');b.className='character';b.dataset.character=id;
      b.setAttribute('aria-selected',String(id===sel.card));
      const art=document.createElement('span');art.className='character-art';art.setAttribute('aria-hidden','true');
      const e=entryOf(sel.pack,id);
      if(e?.icon){const img=document.createElement('img');img.src=e.icon;img.alt='';art.append(img);}else art.textContent=packs[sel.pack].name[0];
      const text=document.createElement('span');text.className='character-text';
      const strong=document.createElement('strong');strong.textContent=label(id);
      const small=document.createElement('small');small.textContent=[e?.about,`${e?.covers?Object.keys(e.covers).length:packs[sel.pack].moods.length} moods`].filter(Boolean).join(' · ');
      text.append(strong,small);b.append(art,text);return b;
    }));
  }
  function renderMoods(){
    let borrowed=false;
    $('[data-moods]').replaceChildren(...families().map(f=>group(f.label,f.moods.map(m=>{
      const to=shows(sel.card,m,sel.state),other=to!==m.id;borrowed||=other;
      return chip(title(m.id),{pressed:m.id===sel.mood,hue:f.colour,borrowed:other,to,data:{mood:m.id}});
    }))));
    $('[data-legend]').hidden=!borrowed;
  }
  function renderStates(){
    $('[data-states]').replaceChildren(...stateGroups.map(g=>group(g.label,g.states.map(s=>{
      const b=chip(stateInfo[s.id].label,{pressed:s.id===sel.state,data:{state:s.id}});b.classList.add('state');b.title=s.about;return b;
    }))));
  }
  function renderFacts(){
    const fact=facts[sel.state],row=$('[data-facts]');
    row.hidden=!fact;if(!fact){row.replaceChildren();return;}
    const seg=document.createElement('div');seg.className='segmented';seg.setAttribute('role','group');seg.setAttribute('aria-label',fact.label);seg.dataset.fact=fact.name;
    seg.append(...fact.options.map(o=>{const b=document.createElement('button');b.type='button';b.dataset.value=o.id;b.textContent=o.label;b.setAttribute('aria-pressed',String(sel[fact.name]===o.id));return b;}));
    row.replaceChildren(seg);
  }
  function setSegment(container,value){for(const b of container.querySelectorAll('button'))b.setAttribute('aria-pressed',String(b.dataset.value===value));}

  // ── Applying the selection ─────────────────────────────────────────────
  function render({autoplay=false}={}){
    if(!moodOf(sel.mood))sel.mood=packs[sel.pack].default_mood;
    const mood=moodOf(sel.mood),plays=shows(sel.card,mood,sel.state);
    renderCards();renderMoods();renderStates();renderFacts();

    const faces=instance?.faces?.(plays)||[];
    if(sel.face&&!faces.some(f=>f.id===sel.face))sel.face=null;
    $('[data-faces]').hidden=faces.length<2;
    $('[data-face-choice]').replaceChildren(...faces.map(f=>{const b=document.createElement('button');b.type='button';b.dataset.value=f.id;b.textContent=f.label;return b;}));
    setSegment($('[data-face-choice]'),sel.face||plays);

    info=null;
    const empty=!instance?(adapter?'':`${label(sel.card)} has no preview: its pack declares no studio entry.`):!plays?`${label(sel.card)} has nothing to show for ${title(sel.mood)} while ${stateInfo[sel.state].label.toLowerCase()}.`:'';
    if(instance&&plays)info=instance.select({mood:plays,face:sel.face,state:sel.state,outcome:sel.outcome,context:sel.context,variant:sel.variant});
    $('[data-empty]').hidden=!empty;$('[data-empty]').textContent=empty;
    const variants=info?.variants||[];
    sel.variant=Math.max(0,Math.min(sel.variant,variants.length-1));
    $('[data-variants]').hidden=variants.length<2;
    const select=$('[data-variation]');
    select.replaceChildren(...variants.map((text,i)=>{const o=document.createElement('option');o.value=String(i);o.textContent=text;return o;}));
    select.value=String(sel.variant);
    const word=adapter?.variantLabel||'Variation';
    $('[data-variation-label]').textContent=word;
    $('[data-prev]').setAttribute('aria-label','Previous '+word.toLowerCase());$('[data-next]').setAttribute('aria-label','Next '+word.toLowerCase());

    const fact=facts[sel.state],detail=fact?` (${fact.options.find(o=>o.id===sel[fact.name]).label.toLowerCase()})`:'';
    $('[data-title]').style.setProperty('--hue',colourOf(sel.mood)||'#888');
    $('[data-title]').textContent=`${title(sel.mood)} · ${stateInfo[sel.state].label}${detail}`;
    $('[data-caption]').textContent=info?.caption||'';$('[data-caption]').hidden=!info?.caption;
    $('[data-mood-term]').textContent=title(sel.mood);$('[data-mood-describe]').textContent=mood.meaning||'';
    $('[data-state-term]').textContent=stateInfo[sel.state].label;$('[data-state-describe]').textContent=stateInfo[sel.state].about;
    const note=$('[data-note]');note.hidden=!plays||plays===sel.mood;
    if(!note.hidden)note.textContent=`${label(sel.card)} has no ${title(sel.mood).toLowerCase()} art. It shows ${title(plays).toLowerCase()} instead, which is what plays here.`;

    const transport=info?adapter.transport:null;
    for(const el of $$('[data-transport]'))el.hidden=el.dataset.transport!==transport;
    for(const name of ['replay','poke','shake'])$(`[data-${name}]`).hidden=!instance?.[name];
    if(transport==='clip'){$('[data-seek]').max=instance.duration||0;if(autoplay&&started)instance.play();}
    $('[data-tools]').hidden=!ctx.tools.children.length;
    writeHash();update();
  }
  function update(){
    $('[data-status]').textContent=info?instance.status():'';
    if(info&&adapter.transport==='clip'){
      $('[data-play]').textContent=instance.playing?'Stop':'Play';
      if(instance.playing||document.activeElement!==$('[data-seek]'))$('[data-seek]').value=instance.time();
      $('[data-time]').textContent=instance.time().toFixed(1)+' / '+(instance.duration||0).toFixed(1)+' s';
    }else if(info)$('[data-pause]').textContent=instance.paused?'Resume':'Pause';
    $('[data-start]').hidden=started||!info||adapter.transport!=='clip';
    const busy=busyNow();$('.pick-column').inert=busy;$('[data-faces]').inert=busy;$('[data-facts]').inert=busy;$('[data-cards]').inert=busy;
  }
  let pending=false;
  function onChange(){if(pending)return;pending=true;requestAnimationFrame(()=>{pending=false;if(instance)update();});}
  const busyNow=()=>Boolean(instance?.busy?.());

  let switching=0;
  async function switchCard(pack,card,variant=0){
    if(pack===sel.pack&&card===sel.card||busyNow())return;
    const ticket=++switching;
    instance?.destroy();instance=adapter=null;ctx.stage.replaceChildren();ctx.tools.replaceChildren();
    sel.pack=pack;sel.card=cardsOf(pack).includes(card)?card:cardsOf(pack)[0];sel.variant=variant;
    ctx.stage.dataset.kind=sel.card;
    try{await load(sel.pack,sel.card);}catch(error){$('[data-status]').textContent=error.message;}
    if(ticket!==switching)return;
    adapter=adapters[sel.pack+'/'+sel.card]||null;
    if(entryOf(sel.pack,sel.card)&&!adapter)$('[data-status]').textContent=`${label(sel.card)}'s scripts didn't register an adapter.`;
    instance=adapter?adapter.create(ctx):null;
    instance?.setSound();
    render({autoplay:true});
  }
  function change(patch,{resetVariant=false}={}){
    if(busyNow())return;
    Object.assign(sel,patch);if(resetVariant)sel.variant=0;
    render({autoplay:true});
  }

  // ── URL ────────────────────────────────────────────────────────────────
  function writeHash(){
    const p=new URLSearchParams({pack:sel.pack,c:sel.card,mood:sel.face||sel.mood,state:sel.state});
    const fact=facts[sel.state];if(fact)p.set(fact.name,sel[fact.name]);
    if(sel.variant)p.set('v',String(sel.variant+1));
    const hash='#'+p.toString().replaceAll('%3A',':');
    if(location.hash!==hash)history.replaceState(null,'',hash);
  }
  function readHash(){
    const p=new URLSearchParams(location.hash.slice(1));
    const pack=packs[p.get('pack')]?p.get('pack'):packs[p.get('c')]?p.get('c'):data.chosen;
    let mood=p.get('mood')||'',face=null;
    if(mood.includes(':')){face=mood;mood=mood.split(':')[0];}
    const out={pack,card:cardsOf(pack).includes(p.get('c'))?p.get('c'):cardsOf(pack)[0],mood,face,
      state:stateIds.includes(p.get('state'))?p.get('state'):'idle',variant:Math.max(0,(Number(p.get('v'))||1)-1)};
    for(const fact of Object.values(facts)){const v=p.get(fact.name);out[fact.name]=fact.options.some(o=>o.id===v)?v:fact.options[0].id;}
    return out;
  }

  // ── Wiring ─────────────────────────────────────────────────────────────
  function start(){if(started)return;started=true;update();}
  const resetOnState=()=>adapter?.transport==='clip';
  // Any press counts as the gesture browsers need before sound; the Start button plays itself.
  root.addEventListener('pointerdown',e=>{if(!e.target.closest('[data-start]'))start();},{capture:true});
  $('[data-cards]').addEventListener('click',e=>{const b=e.target.closest('[data-character]');if(b)switchCard(sel.pack,b.dataset.character);});
  $('[data-pack]').addEventListener('change',e=>switchCard(e.target.value,''));
  $('[data-moods]').addEventListener('click',e=>{const b=e.target.closest('[data-mood]');if(b)change({mood:b.dataset.mood,face:null},{resetVariant:!resetOnState()});});
  $('[data-states]').addEventListener('click',e=>{const b=e.target.closest('[data-state]');if(b){if(b.dataset.state===sel.state)instance?.replay?.();change({state:b.dataset.state},{resetVariant:resetOnState()});}});
  $('[data-facts]').addEventListener('click',e=>{const b=e.target.closest('button'),seg=e.target.closest('[data-fact]');if(b&&seg)change({[seg.dataset.fact]:b.dataset.value},{resetVariant:true});});
  $('[data-face-choice]').addEventListener('click',e=>{const b=e.target.closest('button');if(b)change({face:b.dataset.value.includes(':')?b.dataset.value:null},{resetVariant:true});});
  $('[data-variation]').addEventListener('change',e=>change({variant:Number(e.target.value)}));
  function step(d){const n=$('[data-variation]').options.length;if(n)change({variant:(sel.variant+d+n)%n});}
  $('[data-prev]').addEventListener('click',()=>step(-1));$('[data-next]').addEventListener('click',()=>step(1));
  function playPause(){if(!info)return;start();if(adapter.transport==='clip')instance.playing?instance.stop():instance.play();else instance.setPaused(!instance.paused);update();}
  $('[data-play]').addEventListener('click',playPause);
  $('[data-start]').addEventListener('click',()=>{start();instance?.play();});
  $('[data-loop]').addEventListener('change',()=>{if(instance?.playing)instance.play();});
  $('[data-seek]').addEventListener('input',e=>instance?.seek(Number(e.target.value)));
  $('[data-pause]').addEventListener('click',playPause);
  $('[data-replay]').addEventListener('click',()=>instance?.replay());
  $('[data-poke]').addEventListener('click',()=>instance?.poke());
  $('[data-shake]').addEventListener('click',()=>instance?.shake());
  function setSound(on){sound=on;const b=$('[data-sound]');b.setAttribute('aria-pressed',String(on));b.textContent=on?'Sound on':'Sound off';instance?.setSound();}
  ctx.setSound=setSound;
  $('[data-sound]').addEventListener('click',()=>setSound(!sound));
  $('[data-volume]').addEventListener('input',e=>{volume=Number(e.target.value)/100;instance?.setSound();});

  document.addEventListener('keydown',e=>{
    if(e.metaKey||e.ctrlKey||e.altKey||busyNow()||e.target.closest?.('input,select,textarea'))return;
    const i=stateIds.indexOf(sel.state);
    if(e.key==='ArrowLeft')step(-1);
    else if(e.key==='ArrowRight')step(1);
    else if(e.key==='ArrowUp')change({state:stateIds[(i+stateIds.length-1)%stateIds.length]},{resetVariant:resetOnState()});
    else if(e.key==='ArrowDown')change({state:stateIds[(i+1)%stateIds.length]},{resetVariant:resetOnState()});
    else if(e.key===' '&&!e.target.closest?.('button'))playPause();
    else if(e.key==='s'||e.key==='S')setSound(!sound);
    else if((e.key==='p'||e.key==='P')&&instance?.poke)instance.poke();
    else return;
    started=true;e.preventDefault();
  });
  window.addEventListener('hashchange',()=>{
    const next=readHash();
    if(next.pack!==sel.pack||next.card!==sel.card){Object.assign(sel,next,{pack:sel.pack,card:sel.card});switchCard(next.pack,next.card,next.variant);}
    else{Object.assign(sel,next);render();}
  });

  // For browser checks and the console: select by fields, or by a scene id the adapter knows.
  const ready=(async()=>{const first=readHash();Object.assign(sel,first,{pack:'',card:''});await switchCard(first.pack,first.card,first.variant);})();
  root.studio={sel,ready,packs,get adapter(){return instance;},
    async select({pack,character,...patch}){if(pack||character)await switchCard(pack||sel.pack,character||sel.card);change(patch);},
    async selectAsset(id,card=sel.card){
      await switchCard(sel.pack,card);const found=instance?.find?.(id);if(!found)throw Error('No scene '+id);
      Object.assign(sel,{face:null,...found});render();
    }};
})();
