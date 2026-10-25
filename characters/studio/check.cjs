// The studio in a browser. The character's own views, for each pack: the
// tabs and their buttons, each view drawn, a mood's map and links, and a
// voice take played from the voice file. The matrix: every mood and state for each
// character, the boards' among them, only the cells on screen playing, at
// most a clip character's 60 or a live one's 12, following the scroll and a
// hovered cell, with no page errors (WebGL contexts let go as cells leave),
// and each build's WebAssembly fetched once for all its boards; a click
// opens the scene, and M comes back; and the cell a board's dbg.state
// marks. Then the board's views: a transition recorded and measured, the
// everyday transitions ranked and the jumpiest opened, and the stage's
// board back in the scene after, playing or paused as it was; a reference
// beside the board on one scrubber, its reading rendered from Markdown; a
// review item with a verdict (the server's answer stood in for, so nothing
// is saved); and the page from file://, where what needs no server works,
// a board saying in its pane that it needs the server, and Boop's three
// characters' cards two to a row. And Boop's gel board's drawer: its
// review sets, one clip recorded from the board, and its sound sketches.
// Run `node characters/studio/serve.cjs --port 4190`, then
// `node characters/studio/check.cjs`. BOOP_PLAYWRIGHT_MODULE, BOOP_QA_BROWSER
// and BOOP_QA_URL override Playwright, the browser and the page;
// BOOP_QA_SHOTS=DIR saves a screenshot of each view there.
if(process.argv.includes('--help')){console.log('node characters/studio/check.cjs (README.md, "Checking it")');process.exit(0);}
const {chromium}=require(process.env.BOOP_PLAYWRIGHT_MODULE||'playwright');
const assert=require('node:assert/strict'),path=require('node:path'),{pathToFileURL}=require('node:url');
const {summary}=require('./board.js');
const url=process.env.BOOP_QA_URL||'http://127.0.0.1:4190/',shots=process.env.BOOP_QA_SHOTS;
const browserOptions=process.env.BOOP_QA_BROWSER?{executablePath:process.env.BOOP_QA_BROWSER}:{};
const LIMIT={clip:60,live:12};
const studio=page=>page.evaluate(()=>{const s=document.getElementById('studio').studio;return {view:s.view,sel:{...s.sel},...s.matrix};});

(async()=>{
  const browser=await chromium.launch({...browserOptions,headless:true,args:['--use-angle=swiftshader','--enable-unsafe-swiftshader']});
  try{
    const page=await browser.newPage({viewport:{width:1400,height:900}});
    const errors=[];page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
    let fetched={};page.on('request',r=>{const name=new URL(r.url()).pathname;if(name.endsWith('.wasm'))fetched[name]=(fetched[name]||0)+1;});
    const packs=await (async()=>{await page.goto(url);await page.evaluate(()=>document.getElementById('studio').studio.ready);
      return page.evaluate(()=>Object.entries(document.getElementById('studio').studio.packs).map(([id,p])=>({id,cards:p.studio.map(e=>e.id),boards:p.studio.filter(e=>e.board).map(e=>e.id),moods:p.moods.length})));})();
    const states=await page.evaluate(()=>window.StudioData.states.groups.flatMap(g=>g.states).length);
    for(const pack of packs)for(const card of pack.cards){
      fetched={};
      await page.goto(`${url}#pack=${pack.id}&c=${card}&view=matrix`);
      await page.evaluate(()=>document.getElementById('studio').studio.ready);
      await page.waitForTimeout(1500);
      let m=await studio(page);
      assert.equal(m.view,'matrix',`${card}: the URL's view=matrix opens the matrix`);
      assert.equal(m.cells,pack.moods*states,`${card}: a cell for every mood and state`);
      const limit=LIMIT[m.transport];
      assert.ok(m.playing>0&&m.playing<=limit,`${card}: ${m.playing} cells play, at most ${limit}`);
      // The first cells wholly on screen: under the sticky state row, right of the sticky mood column.
      const visible=()=>page.evaluate(()=>{const box=document.querySelector('[data-matrix-scroll]').getBoundingClientRect();
        const top=box.top+document.querySelector('.matrix thead').getBoundingClientRect().height,left=box.left+document.querySelector('.matrix th[scope=row]').getBoundingClientRect().width;
        return [...document.querySelectorAll('.cell')].filter(c=>{const r=c.getBoundingClientRect();return r.top>=top&&r.bottom<=box.bottom&&r.left>=left&&r.right<=box.right;})
          .slice(0,4).map(c=>!c.querySelector('.thumb').classList.contains('idle'));});
      assert.ok((await visible()).every(Boolean),`${card}: the first cells in full view play`);
      await page.evaluate(()=>{const e=document.querySelector('[data-matrix-scroll]');e.scrollLeft=1500;e.scrollTop=1500;});
      await page.waitForTimeout(1200);
      m=await studio(page);
      assert.ok(m.playing>0&&m.playing<=limit,`${card}: after scrolling, ${m.playing} play`);
      assert.ok((await visible()).every(Boolean),`${card}: the playing cells follow the scroll`);
      const far=page.locator('.cell').last();await far.scrollIntoViewIfNeeded();await far.hover();await page.waitForTimeout(600);
      assert.equal(await far.evaluate(c=>c.querySelector('.thumb').classList.contains('idle')),false,`${card}: a hovered cell plays`);
      if(pack.boards.includes(card))assert.deepEqual(Object.values(fetched),[1],`${card}: its build's WebAssembly fetched once for all its boards, not ${JSON.stringify(fetched)}`);
    }
    const cell=page.locator('.cell[data-mood="grumpy"][data-state="testing"]');
    await cell.scrollIntoViewIfNeeded();await cell.click();await page.waitForTimeout(400);
    let m=await studio(page);
    assert.deepEqual([m.view,m.sel.mood,m.sel.state,m.playing],['scene','grumpy','testing',0],'a click opens its scene and stops the cells');
    assert.ok((await page.evaluate(()=>location.hash)).includes('view=scene'),'the scene\'s URL says so');
    await page.keyboard.press('m');await page.waitForTimeout(800);
    m=await studio(page);
    assert.equal(m.view,'matrix','M opens the matrix');
    // The cell a board's dbg.state shows: no app and needs you first, then a reaction, then the look.
    const cellFor=d=>page.evaluate(d=>document.getElementById('studio').studio.boardCell(d),d);
    const face={screen:'face',base:'working',act:'testing',mood:'grumpy',variant:2,look_variant:3,moment:null,expr:null};
    assert.deepEqual(await cellFor(face),{mood:'grumpy',state:'testing',variant:3},'working shows its activity');
    assert.deepEqual(await cellFor({...face,act:null}),{mood:'grumpy',state:'working',variant:3});
    assert.deepEqual(await cellFor({...face,base:'idle'}),{mood:'grumpy',state:'idle',variant:3},'act counts only while working');
    assert.deepEqual(await cellFor({...face,moment:{anim:'task_complete',left_ms:900,variant:2},expr:'proud'}),{mood:'proud',state:'task_complete',variant:2},'a reaction, in the face it wears');
    assert.deepEqual(await cellFor({...face,screen:'needs_you',moment:{anim:'poked',left_ms:100,variant:1}}),{mood:'grumpy',state:'needs_you',variant:3},'needs you before a reaction');
    assert.deepEqual(await cellFor({...face,screen:'no_app'}),{mood:'grumpy',state:'no_app',variant:3});
    assert.deepEqual(errors,[],'no page errors');
    console.log(`STUDIO MATRIX PASS: ${packs.map(p=>p.cards.join(', ')).join('; ')}`);

    // The board's views, on Boop's gel board. Each view's state is root.studio.views[name].
    const view=name=>page.evaluate(name=>{const v=document.getElementById('studio').studio.views[name];return JSON.parse(JSON.stringify(v,(k,x)=>k==='image'?undefined:x));},name);
    const until=async(name,done,what,s=30)=>{for(let i=0;i<s*4;i++){const v=await view(name);if(done(v))return v;await page.waitForTimeout(250);}throw Error(`${name}: ${what}, not in ${s} s`);};
    const shoot=async name=>{if(shots)await page.screenshot({path:path.join(shots,`studio-${name}.png`),fullPage:true});};
    await page.goto(`${url}#pack=boop&c=board-gel&view=transitions&from=calm/working&to=happy/working`);
    await page.evaluate(()=>document.getElementById('studio').studio.ready);
    let t=await until('transitions',v=>v.frames.length,'a recording');
    assert.equal(t.frames.length,106,'5 frames before the change and 100 after, 40 ms apart');
    assert.deepEqual(t.frames.slice(0,6).map(f=>f.ms),[-200,-160,-120,-80,-40,0]);
    assert.ok(Math.max(...t.changes)>0&&t.changes[0]===0,'each frame\'s change from the one before');
    assert.deepEqual(await page.evaluate(()=>[document.querySelectorAll('[data-graph] rect').length,document.querySelectorAll('[data-strip] button').length]),[106,106],'a bar and a frame for each');
    assert.match(await page.evaluate(()=>location.hash),/view=transitions.*from=calm\/working&to=happy\/working/,'the address keeps the pair');
    // Rank: the everyday transitions recorded on the board, listed as they come, the jumpiest first.
    await page.click('[data-view="transitions"] [data-rank]');
    let partway=null;
    t=await until('transitions',v=>{if(v.ranking&&v.ranked.length)partway??=v.ranked.length;return !v.ranking&&v.ranked.length;},'the everyday transitions ranked',120);
    assert.ok(partway&&partway<t.ranked.length,`listed as they come (${partway} of ${t.ranked.length} partway)`);
    assert.ok(t.ranked.length>=5&&t.ranked.every(j=>j.from&&j.to&&j.ratio>=0),'each with its start, end and ratio');
    assert.deepEqual(t.ranked.map(j=>j.ratio),[...t.ranked.map(j=>j.ratio)].sort((a,b)=>b-a),'the jumpiest first');
    assert.match(t.rankSaid,/jumpiest first/);
    await shoot('transitions');
    const j=t.ranked[0];
    await page.click(`[data-jumpiest] [data-name="${j.name}"]`);
    t=await until('transitions',v=>v.frames.length&&v.to.state===j.to.state&&v.from.state===j.from.state&&v.status.startsWith('106'),'the jumpiest one recorded');
    assert.deepEqual([t.from.mood,t.to.mood],[j.from.mood,j.to.mood],'clicking one of the jumpiest records it');
    assert.equal(summary(t.changes.slice(1)).ratio,j.ratio,'recorded again, it measures as it ranked');
    // The views recorded on the stage's board; back in the scene, it plays the selection again.
    const stage=()=>page.evaluate(()=>{const c=document.querySelector('#stage canvas'),s=document.getElementById('studio').studio;
      return {paused:s.adapter.paused,drawn:c.getContext('2d').getImageData(0,0,c.width,c.height).data.some((v,i)=>i%4!==3&&v>0)};});
    await page.evaluate(()=>{const c=document.querySelector('#stage canvas');c.getContext('2d').clearRect(0,0,c.width,c.height);});
    assert.deepEqual(await stage(),{paused:true,drawn:false},'the stage rests while a view records on its board');
    await page.evaluate(()=>document.getElementById('studio').studio.setView('scene'));
    await page.waitForTimeout(800);
    assert.deepEqual(await stage(),{paused:false,drawn:true},'back in the scene, the stage\'s board plays again');
    // Paused in the scene, then recorded on in a view: back in the scene, the stage still takes its board back, paused.
    await page.evaluate(()=>{const s=document.getElementById('studio').studio;s.adapter.setPaused(true);s.setView('transitions');});
    await until('transitions',v=>v.status.startsWith('106'),'a recording from a paused stage');
    await page.evaluate(()=>{const c=document.querySelector('#stage canvas');c.getContext('2d').clearRect(0,0,c.width,c.height);});
    await page.evaluate(()=>document.getElementById('studio').studio.setView('scene'));
    await page.waitForTimeout(800);
    assert.deepEqual(await stage(),{paused:true,drawn:true},'paused, recorded on, and back: the stage shows its board again, paused');
    const ref=(await page.evaluate(()=>document.getElementById('studio').studio.packs.boop.references))[0];
    await page.goto(`${url}#pack=boop&c=board-gel&view=references&ref=${ref.id}`);
    let r=await until('references',v=>v.board.length,'the board recorded beside the reference');
    assert.equal(r.board.length,Math.max(ref.media[0].frames,25),'a board frame for each of the reference\'s');
    await page.evaluate(()=>{const s=document.querySelector('[data-view="references"] [data-scrub]');s.value='12';s.dispatchEvent(new Event('input'));});
    assert.deepEqual(await page.evaluate(()=>[document.querySelector('[data-view="references"] [data-media] img').getAttribute('src').split('/').pop(),
      document.querySelector('[data-view="references"] [data-at]').textContent]),['0012.png','480 ms'],'one scrubber moves both');
    assert.ok(await page.evaluate(()=>{const c=document.querySelector('[data-view="references"] [data-board]');return c.getContext('2d').getImageData(0,0,c.width,c.height).data.some((v,i)=>i%4!==3&&v>0);}),'the board drawn beside it');
    // Its reading, rendered from its Markdown: a heading for each, a table for each, its code, and no marks left.
    const lines=ref.reading.split('\n'),read=await page.evaluate(()=>{const r=document.querySelector('[data-view="references"] [data-reading]');
      return {headings:r.querySelectorAll('h3,h4,h5,h6').length,tables:r.querySelectorAll('table').length,heads:[...r.querySelectorAll('table:first-of-type th')].map(e=>e.textContent),
        code:r.querySelectorAll('code').length,text:r.innerText};});
    assert.equal(read.headings,lines.filter(l=>/^#{1,6} /.test(l)).length,'a heading for each of the reading\'s');
    assert.equal(read.tables,lines.filter(l=>/^\s*\|?\s*:?-{3,}:?\s*\|/.test(l)).length,'a table for each');
    assert.deepEqual(read.heads,['ms','Beat','What happens'],'the first table\'s header row, as cells');
    assert.ok(read.code>0,'its code as code');
    assert.ok(!read.text.split('\n').some(l=>/^\s*(#{1,6} |\|)/.test(l)),'no Markdown marks left');
    await shoot('references');
    // A verdict, through the page; the server's answer stood in for, so notes.jsonl is left alone.
    await page.route(u=>new URL(u).pathname==='/review',route=>route.request().method()==='POST'
      ?route.fulfill({status:201,contentType:'application/json',body:JSON.stringify({at:new Date().toISOString(),...JSON.parse(route.request().postData()),pack:undefined})})
      :route.continue());
    await page.goto(`${url}#pack=boop&c=board-gel&view=review`);
    await page.waitForTimeout(800);
    const item=page.locator('[data-view="review"] [data-item]').first();
    assert.ok(await item.evaluate(a=>[...a.querySelectorAll('img')].every(i=>i.naturalWidth>0)),'before and after shown');
    const before=(await view('review')).notes.length;
    await item.locator('textarea').fill('Hop higher at 560 ms.');
    await item.getByRole('button',{name:'Ask for a change'}).click();
    await page.waitForTimeout(400);
    assert.equal((await view('review')).notes.length,before+1,'the verdict shows with the item\'s notes');
    assert.match(await page.locator('[data-view="review"] [data-item]').first().textContent(),/Change asked.*Hop higher at 560 ms\./);
    await shoot('review');
    await page.unroute(u=>new URL(u).pathname==='/review');
    // The character's own views, for each pack: the page opens on its
    // overview; each tab opens its first view, and a tab with several shows
    // their buttons, leaving out a view the pack has nothing for; each view
    // draws something of the pack's own.
    for(const pack of ['boop','pixel']){
      await page.goto(`${url}#pack=${pack}`);await page.evaluate(()=>document.getElementById('studio').studio.ready);
      const tabs=await page.evaluate(()=>document.getElementById('studio').studio.tabs);
      assert.equal((await studio(page)).view,'overview',`${pack}: the page opens on the overview`);
      assert.equal(await page.isVisible('[data-cards]'),false,`${pack}: the cards are the Animations tab's`);
      for(const tab of tabs){
        await page.click(`[data-tabs] [data-tab="${tab.id}"]`);await page.waitForTimeout(300);
        assert.equal((await studio(page)).view,tab.views[0],`${pack}: ${tab.id} opens on ${tab.views[0]}`);
        const buttons=await page.$$eval('[data-view-choice] button',b=>b.map(e=>e.dataset.value));
        if(tab.views.length>1)assert.deepEqual(buttons,tab.shown,`${pack}: ${tab.id}'s buttons`);
        for(const name of tab.shown){
          if(['scene','matrix','transitions','references','review'].includes(name))continue;
          await page.evaluate(n=>document.getElementById('studio').studio.setView(n),name);await page.waitForTimeout(200);
          assert.ok(await page.$eval(`[data-view="${name}"]`,e=>e.textContent.trim().length>40),`${pack}: ${name} draws something`);
        }
      }
      assert.equal(tabs.find(t=>t.id==='animations').shown.includes('stills'),pack==='boop',`${pack}: Stills shows only for a pack with golden frames`);
    }
    // Moods: a mood's map opens a mood it moves to, and its links open its voice takes and the evals that expect it.
    await page.goto(`${url}#pack=boop&view=moods&mood=calm`);await page.evaluate(()=>document.getElementById('studio').studio.ready);
    const moves=await page.$$eval('[data-view="moods"] .map .node:not(.here)',n=>n.map(e=>e.dataset.gotoMood));
    await page.click(`[data-view="moods"] .map .node[data-goto-mood="${moves[0]}"]`);await page.waitForTimeout(300);
    assert.equal((await studio(page)).sel.mood,moves[0],'a node on the map opens its mood');
    assert.match(await page.textContent('[data-view="moods"] .mood-head h2'),new RegExp(moves[0],'i'));
    await page.click('[data-view="moods"] [data-voice]');await page.waitForTimeout(300);
    let v=await view('voice');
    assert.deepEqual([(await studio(page)).view,v.mood,v.kind],['voice',moves[0],null],'its voice takes, every kind');
    assert.match(await page.evaluate(()=>location.hash),new RegExp(`takes=${moves[0]}`),'the address keeps the mood');
    await page.click('[data-view="voice"] [data-play]');
    v=await until('voice',x=>x.playing||x.said,'a take played');
    assert.equal(v.said,'','a take plays from the voice file, read in part');
    await page.goto(`${url}#pack=boop&view=moods&mood=grumpy`);await page.evaluate(()=>document.getElementById('studio').studio.ready);
    await page.click('[data-view="moods"] [data-evals]');await page.waitForTimeout(300);
    const shown=await page.$$eval('[data-view="evals"] [data-eval]',e=>e.length);
    assert.ok(shown>0&&shown<(await page.evaluate(()=>window.StudioData.packs.boop.evals.length)),`the evals that expect grumpy, not ${shown}`);
    await shoot('character');
    // Boop's gel board's drawer: its two review sets, a clip of the first case
    // recorded from the board (stopped after it), and its sound sketches.
    await page.goto(`${url}#pack=boop&c=board-gel&view=scene`);
    await page.evaluate(()=>document.getElementById('studio').studio.ready);
    await page.click('[data-tools] summary');
    assert.deepEqual(await page.$$eval('[data-review-set] option',o=>o.map(e=>e.value)),['activities','bridges'],'the review sets');
    assert.equal(await page.locator('[data-sketches] button').count(),12,'eleven sketches and a stop');
    await page.selectOption('[data-review-set]','bridges');
    await page.click('[data-record]');
    await page.waitForFunction(()=>/^Recording 1\//.test(document.querySelector('[data-record-status]').textContent));
    await page.click('[data-record]');  // stop: after the clip being recorded
    await page.waitForFunction(()=>/clips, from the board/.test(document.querySelector('[data-record-status]').textContent),null,{timeout:120000});
    assert.equal(await page.textContent('[data-record-status]'),'1 of 13 clips, from the board. Art review is pending.');
    assert.equal(await page.textContent('[data-review-gallery] article p'),'edge.calm-to-curious');
    assert.ok(await page.$eval('[data-review-gallery] video',v=>new Promise(ok=>v.readyState>=1?ok(v.videoWidth):v.addEventListener('loadedmetadata',()=>ok(v.videoWidth))))===960,'a 960-wide clip');
    await shoot('review-clips');
    // From a file, with no server: what needs none works, and the rest says how.
    const file=pathToFileURL(path.join(__dirname,'index.html')).href;
    await page.goto(`${file}#pack=boop&c=board-gel&view=review`);
    await page.evaluate(()=>document.getElementById('studio').studio.ready);
    assert.ok(await page.isVisible('[data-view="review"] [data-file]'),'from a file, it says to use the server to comment');
    assert.ok(await page.locator('[data-view="review"] button[value="approve"]').first().isDisabled());
    await page.goto(`${file}#pack=boop&c=board-gel&view=references&ref=${ref.id}`);
    await page.waitForTimeout(500);
    assert.ok(await page.evaluate(()=>document.querySelector('[data-view="references"] [data-reading] table')),'the reading, from packs.js, rendered');
    assert.ok(await page.isVisible('[data-view="references"] .screen .board-note'),'the board says in its pane that it needs the server');
    assert.match(await page.textContent('[data-view="references"] .screen .board-note'),/serve\.cjs/);
    assert.equal(await page.textContent('[data-view="references"] [data-board-caption]'),'','and not again under it');
    await page.goto(`${file}#pack=boop&view=signs`);
    await page.evaluate(()=>document.getElementById('studio').studio.ready);
    assert.ok(await page.locator('[data-view="signs"] .sign').count()>10,'the character\'s own views, from packs.js');
    await page.goto(`${file}#pack=boop&c=board-gel&view=scene`);
    await page.evaluate(()=>document.getElementById('studio').studio.ready);
    await page.waitForTimeout(500);
    assert.match(await page.textContent('#stage .board-note'),/serve\.cjs/,'the stage\'s board says so in its pane too');
    assert.doesNotMatch(await page.textContent('[data-status]'),/serve\.cjs/,'and not again under it');
    // Boop's three characters' cards sit two to a row: its gel board first.
    const rows=await page.evaluate(()=>[...document.querySelectorAll('[data-cards] .character')].map(c=>Math.round(c.getBoundingClientRect().top)));
    assert.deepEqual([rows.length,new Set(rows).size,rows[0]===rows[1]],[3,2,true],`the cards two to a row, not ${rows}`);
    assert.equal(await page.getAttribute('[data-cards] .character','data-character'),'board-gel','Boop opens on its gel board');
    await shoot('file');
    assert.deepEqual(errors,[],'no page errors');
    console.log('STUDIO VIEWS PASS: the character\'s views, transitions, references, review, file://');
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});
