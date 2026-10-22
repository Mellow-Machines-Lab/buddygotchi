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
  // What a card plays for one of the pack's moods: the mood, or the one whose art it wears (its entry's `wears`).
  const shows=(card,mood)=>entryOf(sel.pack,card)?.wears?.[mood.id]||mood.id;
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
    if(borrowed){b.classList.add('borrowed');const t=document.createElement('span');t.className='to';t.textContent='→ '+title(to);b.append(t);
      b.title=`No art of its own here: ${label(sel.card)} shows ${title(to)}`;}
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
      const small=document.createElement('small');small.textContent=[e?.about,`${packs[sel.pack].moods.length} moods`].filter(Boolean).join(' · ');
      text.append(strong,small);b.append(art,text);return b;
    }));
  }
  function renderMoods(){
    let borrowed=false;
    $('[data-moods]').replaceChildren(...families().map(f=>group(f.label,f.moods.map(m=>{
      const to=shows(sel.card,m),other=to!==m.id;borrowed||=other;
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
    const mood=moodOf(sel.mood),plays=shows(sel.card,mood);
    renderCards();renderMoods();renderStates();renderFacts();

    const faces=instance?.faces?.(plays)||[];
    if(sel.face&&!faces.some(f=>f.id===sel.face))sel.face=null;
    $('[data-faces]').hidden=faces.length<2;
    $('[data-face-choice]').replaceChildren(...faces.map(f=>{const b=document.createElement('button');b.type='button';b.dataset.value=f.id;b.textContent=f.label;return b;}));
    setSegment($('[data-face-choice]'),sel.face||plays);

    info=null;
    const empty=!instance?(adapter?'':`${label(sel.card)} has no preview: its pack declares no studio entry.`):'';
    if(instance)info=instance.select({mood:plays,face:sel.face,state:sel.state,outcome:sel.outcome,context:sel.context,variant:sel.variant});
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
    const note=$('[data-note]');note.hidden=plays===sel.mood;
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
    if(view==='matrix'){clearMatrix();rested=false;if(adapter?.transport==='live'){instance.setPaused(true);rested=true;}buildMatrix();fillSoon();}
    render({autoplay:view==='scene'});
  }
  function change(patch,{resetVariant=false}={}){
    if(busyNow())return;
    Object.assign(sel,patch);if(resetVariant)sel.variant=0;
    render({autoplay:true});
  }

  // ── Matrix ─────────────────────────────────────────────────────────────
  // Every mood and state at once, for the card shown. Each cell is the
  // character's own preview, made by its adapter as the stage's is, silent,
  // and looping where the adapter can (`preview()`). Only cells on screen
  // play, at most LIMIT at once, a hovered cell first: a live character's
  // each holds a WebGL context, and a page gets about 16. A cell opens its scene.
  const LIMIT={clip:60,live:12};
  let view='scene';
  const matrix={table:$('[data-matrix-table]'),key:'',cells:[],playing:new Map(),seen:new Set(),hovered:null,observer:null,timer:0};
  function buildMatrix(){
    const key=sel.pack+'/'+sel.card+'/'+Boolean(adapter);
    if(matrix.key===key)return;
    clearMatrix();matrix.key=key;
    const cell=(tag,text,cls)=>{const c=document.createElement(tag);if(text)c.append(text);if(cls)c.className=cls;return c;};
    const head=document.createElement('tr');head.append(cell('th'));
    for(const g of stateGroups)g.states.forEach((s,i)=>{const th=cell('th');th.append(cell('small',i?'':g.label),stateInfo[s.id].label);th.title=s.about;head.append(th);});
    const thead=document.createElement('thead'),tbody=document.createElement('tbody');thead.append(head);
    for(const f of families()){
      const row=document.createElement('tr');row.append(cell('th',f.label,'family'));tbody.append(row);
      for(const m of f.moods){
        const tr=document.createElement('tr'),th=cell('th'),to=shows(sel.card,m);th.scope='row';
        th.append(chip(title(m.id),{pressed:false,hue:f.colour,borrowed:to!==m.id,to,data:{}}));tr.append(th);
        for(const id of stateIds){
          const b=cell('button','','cell'+(to!==m.id?' borrowed':''));b.type='button';
          b.dataset.mood=m.id;b.dataset.state=id;b.title=`${title(m.id)} · ${stateInfo[id].label}`;
          const thumb=cell('div','','thumb idle');if(f.colour)thumb.style.setProperty('--hue',f.colour);
          b.append(thumb,cell('small','\u00a0'));
          const td=cell('td');td.append(b);tr.append(td);matrix.cells.push(b);
        }
        tbody.append(tr);
      }
    }
    matrix.table.replaceChildren(thead,tbody);
    // On screen is under the sticky state row and right of the sticky mood column, and half a cell at least.
    const top=thead.getBoundingClientRect().height,left=tbody.querySelector('th[scope=row]')?.getBoundingClientRect().width||0;
    matrix.observer=new IntersectionObserver(entries=>{
      for(const e of entries)e.isIntersecting?matrix.seen.add(e.target):matrix.seen.delete(e.target);
      fillSoon();
    },{root:$('[data-matrix-scroll]'),rootMargin:`-${Math.ceil(top)}px 0px 0px -${Math.ceil(left)}px`,threshold:.5});
    for(const c of matrix.cells)matrix.observer.observe(c);
    if(board.shows)markBoard(board.shows,'');
    const n=packs[sel.pack].moods.length;
    $('[data-matrix-about]').textContent=adapter
      ?`${label(sel.card)}: ${n} moods × ${stateIds.length} states. The cells on screen play, silently, up to ${LIMIT[adapter.transport]||LIMIT.clip} at once; hover one to play it. Click one to open it.`
      :`${label(sel.card)} has no preview, so the matrix is empty.`;
  }
  function fillSoon(){if(!matrix.timer)matrix.timer=setTimeout(()=>{matrix.timer=0;fill();},80);}
  function fill(){
    if(view!=='matrix'||!adapter)return;
    const first=matrix.hovered?[matrix.hovered]:[];
    const want=[...first,...matrix.cells.filter(c=>matrix.seen.has(c)&&c!==matrix.hovered)].slice(0,LIMIT[adapter.transport]||LIMIT.clip);
    for(const c of [...matrix.playing.keys()])if(!want.includes(c))unmount(c);
    for(const c of want)if(!matrix.playing.has(c))mount(c);
  }
  function mount(cell){
    const thumb=cell.querySelector('.thumb'),note=cell.querySelector('small');
    const s={mood:shows(sel.card,moodOf(cell.dataset.mood)),face:null,state:cell.dataset.state,outcome:'success',context:'new_task',variant:0};
    // A cell's own context: no sound, no drawer, nothing to redraw.
    const own={root,stage:thumb,tools:document.createElement('div'),sound:false,volume:0,loop:true,selection:s,onChange(){},setSound(){}};
    thumb.classList.remove('idle');
    try{
      const instance=adapter.create(own);matrix.playing.set(cell,instance);
      const got=instance.select(s);
      note.textContent=got?.variants?.length>1?got.variants[0]:got?.caption||'\u00a0';
      instance.preview?.();
    }catch(error){note.textContent=error.message;}
  }
  function unmount(cell){
    const instance=matrix.playing.get(cell),thumb=cell.querySelector('.thumb');matrix.playing.delete(cell);
    const canvases=[...thumb.querySelectorAll('canvas')];
    try{instance?.destroy();}catch{}
    // A destroyed preview's WebGL context lives on until it's collected, and
    // the page's few run out as the matrix scrolls: let each go now.
    for(const c of canvases)for(const kind of ['webgl2','webgl'])c.getContext(kind)?.getExtension('WEBGL_lose_context')?.loseContext();
    thumb.replaceChildren();thumb.classList.add('idle');
  }
  function clearMatrix(){
    for(const c of [...matrix.playing.keys()])unmount(c);
    matrix.observer?.disconnect();matrix.cells=[];matrix.seen.clear();matrix.hovered=null;matrix.key='';matrix.table.replaceChildren();
    board.cell=null;
  }
  // What the simulated board shows, marked: `make simulator` serves this page
  // beside the board, and its link names the board to ask (&board=/board, or
  // /board/NAME for one of several), which answers with the board's dbg.state.
  const BOARD_MS=1000,BOARD_URL=/^\/board(\/[a-z0-9][a-z0-9_-]{0,15})?$/;
  const board={timer:0,url:null,cell:null,shows:null};
  // The cell for a dbg.state: no app and needs you first, then a reaction
  // playing, then the look, the agents' activity while working.
  function boardCell(d){
    const mood=d.expr||d.mood;
    if(d.screen==='no_app'||d.screen==='needs_you')return {mood,state:d.screen,variant:d.look_variant};
    if(d.moment?.anim&&stateInfo[d.moment.anim])return {mood,state:d.moment.anim,variant:d.moment.variant};
    return {mood,state:d.base==='working'?d.act||'working':d.base,variant:d.look_variant};
  }
  async function askBoard(){
    board.timer=0;
    if(view!=='matrix'||!board.url)return;
    let shows=null,text='';
    try{
      const reply=await fetch(board.url,{cache:'no-store'});
      const said=reply.ok?await reply.json():null;
      shows=said&&boardCell(said);
      if(!shows)text='The simulator has no board right now: open its page.';
    }catch{text='The simulator stopped.';}
    markBoard(shows,text);
    board.timer=setTimeout(askBoard,BOARD_MS);
  }
  function markBoard(shows,text){
    board.shows=shows;
    const cell=shows&&matrix.cells.find(c=>c.dataset.mood===shows.mood&&c.dataset.state===shows.state)||null;
    if(board.cell!==cell){board.cell?.classList.remove('board');cell?.classList.add('board');board.cell=cell;}
    if(cell)cell.dataset.variant=String(Math.max(0,(shows.variant||1)-1));
    $('[data-board-now]').hidden=!shows&&!text;
    $('[data-board-show]').hidden=!cell;
    $('[data-board-text]').textContent=shows?`The simulator shows ${title(shows.mood)} · ${stateInfo[shows.state]?.label||shows.state}`+(shows.variant?`, variation ${shows.variant}`:'')+(cell?'':' (not a cell here)')+'.':text;
  }

  // The stage's own preview rests while the matrix shows: a live one is one of the page's WebGL contexts.
  let rested=false;
  function setView(next){
    if(next===view||busyNow())return;
    view=next;
    $('.layout').hidden=view==='matrix';$('[data-matrix]').hidden=view!=='matrix';
    setSegment($('[data-view-choice]'),view);
    if(view==='matrix'){
      if(adapter?.transport==='live'&&!instance.paused){instance.setPaused(true);rested=true;}
      else if(instance?.playing)instance.stop();
      buildMatrix();fillSoon();
      if(!board.timer)askBoard();
    }else{
      clearTimeout(board.timer);board.timer=0;
      for(const c of [...matrix.playing.keys()])unmount(c);
      if(rested){instance?.setPaused(false);rested=false;}
    }
    writeHash();
  }

  // ── URL ────────────────────────────────────────────────────────────────
  function writeHash(){
    const p=new URLSearchParams({pack:sel.pack,c:sel.card,mood:sel.face||sel.mood,state:sel.state});
    const fact=facts[sel.state];if(fact)p.set(fact.name,sel[fact.name]);
    if(sel.variant)p.set('v',String(sel.variant+1));
    if(view==='matrix')p.set('view','matrix');
    if(board.url)p.set('board',board.url);
    const hash='#'+p.toString().replaceAll('%3A',':');
    if(location.hash!==hash)history.replaceState(null,'',hash);
  }
  function readHash(){
    const p=new URLSearchParams(location.hash.slice(1));
    const pack=packs[p.get('pack')]?p.get('pack'):packs[p.get('c')]?p.get('c'):data.chosen;
    let mood=p.get('mood')||'',face=null;
    if(mood.includes(':')){face=mood;mood=mood.split(':')[0];}
    const out={pack,card:cardsOf(pack).includes(p.get('c'))?p.get('c'):cardsOf(pack)[0],mood,face,
      state:stateIds.includes(p.get('state'))?p.get('state'):'idle',variant:Math.max(0,(Number(p.get('v'))||1)-1),
      view:p.get('view')==='matrix'?'matrix':'scene',board:BOARD_URL.test(p.get('board')||'')?p.get('board'):null};
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
  $('[data-view-choice]').addEventListener('click',e=>{const b=e.target.closest('button');if(b)setView(b.dataset.value);});
  $('[data-board-show]').addEventListener('click',()=>board.cell?.scrollIntoView({block:'center',inline:'center',behavior:'smooth'}));
  matrix.table.addEventListener('pointerover',e=>{const c=e.target.closest('.cell');if(c&&c!==matrix.hovered){matrix.hovered=c;fillSoon();}});
  matrix.table.addEventListener('click',e=>{const c=e.target.closest('.cell');if(!c)return;
    setView('scene');change({mood:c.dataset.mood,face:null,state:c.dataset.state,variant:Number(c.dataset.variant||0)});});
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
    if(e.key==='m'||e.key==='M'){setView(view==='matrix'?'scene':'matrix');e.preventDefault();return;}
    if(view==='matrix')return;
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
    const {view:nextView,board:url,...next}=readHash();board.url=url;setView(nextView);
    if(next.pack!==sel.pack||next.card!==sel.card){Object.assign(sel,next,{pack:sel.pack,card:sel.card});switchCard(next.pack,next.card,next.variant);}
    else{Object.assign(sel,next);render();}
  });

  // For browser checks and the console: select by fields, or by a scene id the adapter knows.
  const ready=(async()=>{const {view:firstView,board:url,...first}=readHash();board.url=url;Object.assign(sel,first,{pack:'',card:''});await switchCard(first.pack,first.card,first.variant);setView(firstView);})();
  root.studio={sel,ready,packs,get adapter(){return instance;},get view(){return view;},setView,
    get matrix(){return {cells:matrix.cells.length,playing:matrix.playing.size,transport:adapter?.transport||null,board:board.shows};},
    boardCell,
    async select({pack,character,...patch}){if(pack||character)await switchCard(pack||sel.pack,character||sel.card);change(patch);},
    async selectAsset(id,card=sel.card){
      await switchCard(sel.pack,card);const found=instance?.find?.(id);if(!found)throw Error('No scene '+id);
      Object.assign(sel,{face:null,...found});render();
    }};
})();
