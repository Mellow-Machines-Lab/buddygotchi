// The studio's matrix in a browser: every mood and state for each character,
// only the cells on screen playing, at most a clip character's 60 or a live
// one's 12, following the scroll and a hovered cell, with no page errors
// (WebGL contexts let go as cells leave); a click opens the scene, and M comes
// back; and the cell a board's dbg.state marks. Run
// `node characters/studio/serve.cjs --port 4190`, then
// `node characters/studio/check.cjs`. BOOP_PLAYWRIGHT_MODULE, BOOP_QA_BROWSER
// and BOOP_QA_URL override Playwright, the browser and the page.
if(process.argv.includes('--help')){console.log('node characters/studio/check.cjs (README.md, "Checking it")');process.exit(0);}
const {chromium}=require(process.env.BOOP_PLAYWRIGHT_MODULE||'playwright');
const assert=require('node:assert/strict');
const url=process.env.BOOP_QA_URL||'http://127.0.0.1:4190/';
const browserOptions=process.env.BOOP_QA_BROWSER?{executablePath:process.env.BOOP_QA_BROWSER}:{};
const LIMIT={clip:60,live:12};
const studio=page=>page.evaluate(()=>{const s=document.getElementById('studio').studio;return {view:s.view,sel:{...s.sel},...s.matrix};});

(async()=>{
  const browser=await chromium.launch({...browserOptions,headless:true,args:['--use-angle=swiftshader','--enable-unsafe-swiftshader']});
  try{
    const page=await browser.newPage({viewport:{width:1400,height:900}});
    const errors=[];page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
    const packs=await (async()=>{await page.goto(url);await page.evaluate(()=>document.getElementById('studio').studio.ready);
      return page.evaluate(()=>Object.entries(document.getElementById('studio').studio.packs).map(([id,p])=>({id,cards:p.studio.map(e=>e.id),moods:p.moods.length})));})();
    const states=await page.evaluate(()=>window.StudioData.states.groups.flatMap(g=>g.states).length);
    for(const pack of packs)for(const card of pack.cards){
      await page.goto(`${url}#pack=${pack.id}&c=${card}&view=matrix`);
      await page.evaluate(()=>document.getElementById('studio').studio.ready);
      await page.waitForTimeout(1500);
      let m=await studio(page);
      assert.equal(m.view,'matrix',`${card}: the URL's view=matrix opens the matrix`);
      assert.equal(m.cells,pack.moods*states,`${card}: a cell for every mood and state`);
      const limit=LIMIT[m.transport];
      assert.ok(m.playing>0&&m.playing<=limit,`${card}: ${m.playing} cells play, at most ${limit}`);
      const visible=()=>page.evaluate(()=>{const box=document.querySelector('[data-matrix-scroll]').getBoundingClientRect();
        return [...document.querySelectorAll('.cell')].filter(c=>{const r=c.getBoundingClientRect();return r.top>=box.top+60&&r.bottom<=box.bottom&&r.left>=box.left+200&&r.right<=box.right;})
          .slice(0,4).map(c=>!c.querySelector('.thumb').classList.contains('idle'));});
      assert.ok((await visible()).every(Boolean),`${card}: the first cells in full view play`);
      await page.evaluate(()=>{const e=document.querySelector('[data-matrix-scroll]');e.scrollLeft=1500;e.scrollTop=1500;});
      await page.waitForTimeout(1200);
      m=await studio(page);
      assert.ok(m.playing>0&&m.playing<=limit,`${card}: after scrolling, ${m.playing} play`);
      assert.ok((await visible()).every(Boolean),`${card}: the playing cells follow the scroll`);
      const far=page.locator('.cell').last();await far.scrollIntoViewIfNeeded();await far.hover();await page.waitForTimeout(600);
      assert.equal(await far.evaluate(c=>c.querySelector('.thumb').classList.contains('idle')),false,`${card}: a hovered cell plays`);
    }
    const cell=page.locator('.cell[data-mood="grumpy"][data-state="testing"]');
    await cell.scrollIntoViewIfNeeded();await cell.click();await page.waitForTimeout(400);
    let m=await studio(page);
    assert.deepEqual([m.view,m.sel.mood,m.sel.state,m.playing],['scene','grumpy','testing',0],'a click opens its scene and stops the cells');
    assert.ok(!(await page.evaluate(()=>location.hash)).includes('view='),'the scene has no view= in its URL');
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
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});
