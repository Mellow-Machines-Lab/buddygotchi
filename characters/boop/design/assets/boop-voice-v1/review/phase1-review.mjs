// Continuous local audition. Labels stay on screen, never synthesized into the voice.
const section=document.createElement('section');section.className='reel';section.id='continuous-review';
section.innerHTML=`<div class="reel-head"><div><span class="eyebrow">PHASE 1 / CONTINUOUS AUDITION</span><h2>The dictionary, on a roll.</h2></div><span id="reel-count">Loading recordings…</span></div>
<p class="fine">One continuous listening queue, with state → mood → keyword labels. No spoken labels, no extra generation. Filter into chapters; mark weak clips as you go. Explicit expressions are off by default.</p>
<div class="reel-filters"><label>State<select id="reel-state"><option value="">All states</option></select></label><label>Mood<select id="reel-mood"><option value="">All moods</option></select></label><label>Category<select id="reel-category"><option value="">All categories</option><option value="word">Words</option><option value="nonverbal">Mumbles / reactions</option><option value="phrase">Phrases</option></select></label><label>Review<select id="reel-review"><option value="">All recordings</option><option value="unreviewed">Unreviewed</option><option value="Keep">Keep</option><option value="Rework">Rework</option></select></label><label>Find keyword<input id="reel-search" type="search" placeholder="Go, done, hrr…"></label></div>
<div class="reel-now"><span id="reel-context">Preparing…</span><h2 id="reel-keyword">—</h2><p id="reel-script"></p><span id="reel-position"></span><span id="reel-verdict"></span></div>
<div class="actions"><button id="reel-prev">← Previous</button><button class="primary" id="reel-play">Play continuously</button><button id="reel-next">Next →</button><button id="reel-replay">Replay clip</button><button id="reel-keep">Keep · K</button><button id="reel-rework">Rework · R</button><button id="reel-clear">Clear mark</button></div>
<div class="reel-options"><label>Voice volume<input id="reel-volume" type="range" min="0" max="85" value="32"></label><label>Gap between clips<select id="reel-gap"><option value="0.35">0.35 seconds</option><option value="0.8">0.8 seconds</option><option value="1.5">1.5 seconds</option></select></label><label>Texture<select id="reel-texture"><option value="robot-soft">Soft circuit</option><option value="original">Dry / quiet</option><option value="robot-grain">More electronic</option></select></label><label class="checkbox"><input id="reel-explicit" type="checkbox"> Include adult expressions</label></div>
<label>Queue position<input id="reel-seek" type="range" min="0" max="0" value="0" step="1"></label><p id="reel-status" role="status" aria-live="polite">Ready</p>
<div class="actions"><button id="reel-export">Export review marks ↓</button><button id="reel-refresh">Refresh generated clips</button><a href="../plans/phase1.json" download>First-pass manifest ↓</a><a href="../plans/deferred.json" download>Deferred slots ↓</a></div>
<details><summary>Jump to a recording</summary><div id="reel-list"></div></details><audio id="reel-audio" preload="none"></audio>`;
document.querySelector('.hero').after(section);
const $=id=>document.getElementById('reel-'+id);
const audio=$('audio');audio.volume=.32;
let bank=[],queue=[],index=0,playing=false,timer,serial=0,marks={},summary;
const storeKey='boop-phase1-review-v1';
try{marks=JSON.parse(localStorage.getItem(storeKey)||'{}');}catch{}
const time=s=>`${Math.floor(s/60)}:${String(Math.floor(s%60)).padStart(2,'0')}`;
function pause(message='Paused'){
 playing=false;serial++;clearTimeout(timer);audio.pause();$('play').textContent='Play continuously';$('status').textContent=message;
}
function show(){
 const r=queue[index];for(const id of ['play','next','prev','replay','keep','rework','clear'])$(id).disabled=!r;
 $('seek').max=Math.max(0,queue.length-1);$('seek').value=index;
 if(!r){$('keyword').textContent='No matching recordings';$('context').textContent='Try clearing a filter';$('position').textContent='';$('script').textContent='';return;}
 $('keyword').textContent=r.keyword;$('context').textContent=`${$('state').value||r.states[0]}  /  ${r.mood}  /  ${r.category}${r.explicit?' / EXPLICIT':''}`;
 $('script').textContent=r.script;
 $('position').textContent=`${index+1} / ${queue.length} · ${r.seconds.toFixed(2)} s · eligible states: ${r.states.join(', ')}`;
 $('verdict').textContent=marks[r.performance]?.verdict||'Not reviewed';
 $('list').querySelector('[aria-current="true"]')?.removeAttribute('aria-current');
 $('list').querySelector(`[data-index="${index}"]`)?.setAttribute('aria-current','true');
 try{localStorage.setItem('boop-phase1-last-slot',r.performance);}catch{}
}
async function play(fromStart=false){
 const r=queue[index];if(!r)return;
 document.dispatchEvent(new CustomEvent('boop-reel-start'));
 clearTimeout(timer);const token=++serial;playing=true;$('play').textContent='Pause';show();
 const src=r.files[$('texture').value];
 if(audio.getAttribute('src')!==src){audio.src=src;audio.currentTime=0;}else if(fromStart)audio.currentTime=0;
 try{await audio.play();if(token!==serial)return;$('status').textContent=`Playing ${index+1} of ${queue.length}. K keeps; R flags for rework; arrows skip.`;}
 catch(e){if(token===serial)pause('Playback stopped: '+e.message);}
}
function jump(next,autoplay=playing){
 pause('Ready');index=Math.max(0,Math.min(queue.length-1,next));audio.removeAttribute('src');audio.load();show();if(autoplay)play(true);
}
function mark(verdict){
 const r=queue[index];if(!r)return;
 if(verdict)marks[r.performance]={verdict,performance:r.performance,takeId:r.id,entry:r.entry,mood:r.mood,masterSha256:r.master_sha256,texture:$('texture').value,at:new Date().toISOString()};else delete marks[r.performance];
 try{localStorage.setItem(storeKey,JSON.stringify(marks));show();}catch{pause('Review could not be saved. Export your marks before leaving.');}
}
function rebuild(restore=false){
 pause('Ready');const q=$('search').value.trim().toLowerCase(),state=$('state').value,mood=$('mood').value,category=$('category').value,review=$('review').value;
 queue=bank.filter(r=>(!state||r.states.includes(state))&&(!mood||r.mood===mood)&&(!category||r.category===category)&&($('explicit').checked||!r.explicit)&&(!q||[r.keyword,r.script,r.entry].join(' ').toLowerCase().includes(q))&&(!review||(review==='unreviewed'?!marks[r.performance]:marks[r.performance]?.verdict===review)));
 queue.sort((a,b)=>(a.states[0]+'|'+a.mood+'|'+a.keyword).localeCompare(b.states[0]+'|'+b.mood+'|'+b.keyword));
 let last;try{last=localStorage.getItem('boop-phase1-last-slot');}catch{}
 index=restore?Math.max(0,queue.findIndex(r=>r.performance===last)):0;audio.removeAttribute('src');audio.load();
 $('count').textContent=`${bank.length.toLocaleString()} / ${summary.selected.toLocaleString()} ready · ${queue.length.toLocaleString()} in queue · ~${time(queue.reduce((s,r)=>s+r.seconds+Number($('gap').value),0))}`;
 $('list').replaceChildren();const frag=document.createDocumentFragment();
 queue.forEach((r,i)=>{const b=document.createElement('button');b.type='button';b.dataset.index=i;b.textContent=`${i+1}. ${r.states[0]} / ${r.mood} / ${r.keyword} · ${r.seconds.toFixed(1)}s`;b.addEventListener('click',()=>jump(i,true));frag.append(b);});$('list').append(frag);show();
}
async function load(){
 pause('Loading…');try{
  const response=await fetch('phase1-audio.json',{cache:'no-store'});if(!response.ok)throw Error('The generation batch is not rendered yet. Refresh here shortly.');
  const data=await response.json();bank=data.recorded;summary=data.summary;
  for(const [id,values] of [['state',[...new Set(bank.flatMap(r=>r.states))].sort()],['mood',[...new Set(bank.map(r=>r.mood))].sort()]]){
   const old=$(id).value;while($(id).options.length>1)$(id).remove(1);for(const v of values){const o=document.createElement('option');o.value=v;o.textContent=v;$(id).append(o);}$(id).value=values.includes(old)?old:'';
  }rebuild(true);
 }catch(e){pause(e.message);$('count').textContent='Waiting for rendered clips';}
}
audio.addEventListener('ended',()=>{if(!playing)return;if(index+1>=queue.length){pause('Queue complete. Export your review marks when ready.');return;}timer=setTimeout(()=>jump(index+1,true),Number($('gap').value)*1000);});
audio.addEventListener('error',()=>{if(audio.getAttribute('src'))pause('Audio file could not be loaded. Refresh clips or skip this recording.');});
$('play').addEventListener('click',()=>playing?pause():play());$('prev').addEventListener('click',()=>jump(index-1,true));$('next').addEventListener('click',()=>jump(index+1,true));$('replay').addEventListener('click',()=>play(true));
$('keep').addEventListener('click',()=>mark('Keep'));$('rework').addEventListener('click',()=>mark('Rework'));$('clear').addEventListener('click',()=>mark(null));
$('volume').oninput=()=>{audio.volume=Number($('volume').value)/100;};$('texture').onchange=()=>jump(index,false);$('seek').oninput=()=>jump(Number($('seek').value),playing);
for(const id of ['state','mood','category','review','explicit','gap'])$(id).onchange=()=>rebuild();$('search').oninput=()=>rebuild();$('refresh').addEventListener('click',load);
$('export').addEventListener('click',()=>{const blob=new Blob([JSON.stringify({version:1,voice_id:'rErOatUrNIU3vfNcLl6Z',phase:'phase1',marks},null,2)],{type:'application/json'});const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='boop-phase1-review.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);});
document.addEventListener('keydown',e=>{if(e.target.closest('input,select,textarea')||!section.matches(':hover')&&!playing)return;
 if(e.key===' '&&e.target.closest('button'))return;
 if(['ArrowRight','ArrowLeft',' ','k','K','r','R'].includes(e.key))e.preventDefault();
 if(e.key==='ArrowRight')jump(index+1,true);if(e.key==='ArrowLeft')jump(index-1,true);if(e.key===' ')playing?pause():play();if(e.key.toLowerCase()==='k')mark('Keep');if(e.key.toLowerCase()==='r')mark('Rework');});
document.addEventListener('boop-scene-start',()=>pause('Paused for scene audition'));
document.addEventListener('visibilitychange',()=>{if(document.hidden)pause('Paused while away');});addEventListener('pagehide',()=>pause());
await load();
