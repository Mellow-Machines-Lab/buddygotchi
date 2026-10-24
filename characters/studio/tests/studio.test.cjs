// The studio's logic with no browser (README.md, "Checking it"): board.js's
// change measure, held to the pixels measure.py's test is
// (internal/tools/fluid/tests/changed.json), and how it asks the board for
// each state; and serve.cjs's review verdicts, in a copy of it beside a
// pack of its own. Run: node --test characters/studio/tests/
const assert=require('node:assert/strict'),{test}=require('node:test'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),{spawn}=require('node:child_process');
const studio=path.resolve(__dirname,'..'),repo=path.resolve(studio,'../..');
const {wire,changed,summary}=require(path.join(studio,'board.js'));

test('a pixel changed when its difference\'s luma is over 24 levels, as measure.py counts', () => {
  const {pairs}=JSON.parse(fs.readFileSync(path.join(repo,'internal/tools/fluid/tests/changed.json'),'utf8'));
  const rgba=side=>Uint8ClampedArray.from(pairs.flatMap(p=>[...p[side],255]));
  for(const [a,b,counts] of pairs)assert.equal(changed(Uint8ClampedArray.from([...a,255]),Uint8ClampedArray.from([...b,255])),Number(counts),`${a} → ${b}`);
  assert.equal(changed(rgba(0),rgba(1)),pairs.filter(p=>p[2]).length);
  assert.deepEqual(summary([1,1,57,1]),{median:1,largest:57,at:2,ratio:57},'measure.py\'s median, largest and ratio');
});

test('the board is asked for each state as the Mac asks for it', () => {
  const states=JSON.parse(fs.readFileSync(path.join(studio,'states.json'),'utf8')).groups.flatMap(g=>g.states.map(s=>s.id));
  for(const state of states)assert.ok(wire({mood:'calm',state}).steps.length,`${state} has its messages`);
  assert.throws(()=>wire({mood:'calm',state:'dancing'}),/no state dancing/);
  const only=cell=>wire(cell).steps.map(([ms,m])=>[ms,{...m,id:undefined}]);
  assert.deepEqual(only({mood:'calm',state:'idle'}),[[0,{t:'state',base:'idle',mood:'calm',vol:0,id:undefined}]]);
  assert.deepEqual(wire({mood:'calm',state:'testing'}).steps[0][1],{t:'state',base:'working',busy:1,act:'testing',mood:'calm',vol:0},'what the agent does, while working');
  assert.equal(wire({mood:'calm',state:'needs_you'}).steps[0][1].attn.agent,'claude');
  const finish=wire({mood:'proud',state:'task_complete',outcome:'failure'}).steps;
  assert.deepEqual(finish.map(([,m])=>[m.t,m.base||m.name]),[['state','working'],['do','task_complete']],'a reaction over working');
  assert.deepEqual(finish[1][1].args,{outcome:'failure'});
  assert.deepEqual(wire({mood:'calm',state:'starting',context:'compacted'}).steps[1][1].args,{ctx:'compacted'});
  assert.equal(wire({mood:'calm',state:'wake_up'}).steps[0][1].base,'idle','waking up is over idle');
  const over={base:'asleep'};
  assert.equal(wire({mood:'calm',state:'notice'},over).steps[0][1].base,'asleep','a transition\'s reaction plays over its start\'s look');
  assert.deepEqual(wire({mood:'calm',state:'tap_spam'}).steps.slice(1).map(([ms,m])=>[ms,m.t]),[[0,'dbg.touch'],[200,'dbg.touch'],[400,'dbg.touch']],'the third tap within 3 s is tap spam');
  assert.ok(wire({mood:'calm',state:'gesture'}).steps[1][1].to_x,'a stroke');
  assert.equal(wire({mood:'calm',state:'no_app'}).after,30000,'no app: 30 s with no state (linkkit\'s kHostGoneMs)');
});

test('serve.cjs saves a verdict on a review item, and only from its own page', async t => {
  // A copy of the server beside a pack of its own, so nothing lands in the real characters/.
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'studio-')),pack=path.join(dir,'characters','pal');
  fs.mkdirSync(path.join(dir,'characters','studio'),{recursive:true});fs.mkdirSync(path.join(pack,'review'),{recursive:true});
  fs.copyFileSync(path.join(studio,'serve.cjs'),path.join(dir,'characters','studio','serve.cjs'));
  fs.writeFileSync(path.join(pack,'character.json'),'{}');
  fs.writeFileSync(path.join(pack,'review','queue.json'),JSON.stringify([{id:'perk'}]));
  const port=20000+Math.floor(Math.random()*20000),url=`http://127.0.0.1:${port}`;
  const server=spawn(process.execPath,[path.join(dir,'characters','studio','serve.cjs'),'--port',String(port)],{stdio:'ignore'});
  t.after(()=>{server.kill();fs.rmSync(dir,{recursive:true,force:true});});
  for(let i=0;i<100;i++){try{await fetch(url);break;}catch{await new Promise(r=>setTimeout(r,50));}}
  const post=(body,headers={})=>fetch(`${url}/review`,{method:'POST',body:JSON.stringify(body),headers:{'Content-Type':'application/json',Origin:url,...headers}});
  const saved=await post({pack:'pal',id:'perk',verdict:'change',text:' Hop higher. '});
  assert.equal(saved.status,201);
  const note=await saved.json();
  assert.deepEqual([note.id,note.verdict,note.text],['perk','change','Hop higher.']);
  assert.ok(!Number.isNaN(Date.parse(note.at)),'with when');
  assert.equal((await post({pack:'pal',id:'perk',verdict:'approve',text:''})).status,201);
  const lines=fs.readFileSync(path.join(pack,'review','notes.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
  assert.deepEqual(lines.map(n=>n.verdict),['change','approve'],'appended, a line each');
  assert.deepEqual(await (await fetch(`${url}/review?pack=pal`)).json(),lines,'and read back as they are');
  assert.deepEqual(await (await fetch(`${url}/review?pack=nobody`)).json(),[]);
  for(const [body,why] of [[{pack:'pal',id:'hop',verdict:'approve',text:''},'an item that isn\'t in the queue'],
    [{pack:'pal',id:'perk',verdict:'maybe',text:''},'a verdict that isn\'t one'],
    [{pack:'pal',id:'perk',verdict:'change',text:' '},'a change with nothing said'],
    [{pack:'../pal',id:'perk',verdict:'approve',text:''},'a pack that isn\'t a name']])
    assert.equal((await post(body)).status,400,why);
  assert.equal((await post({pack:'pal',id:'perk',verdict:'approve',text:''},{Origin:'http://example.com'})).status,403,'another site');
  assert.equal((await post({pack:'pal',id:'perk',verdict:'approve',text:''},{'Content-Type':'text/plain'})).status,403,'a form, which needs no preflight');
  assert.equal(fs.readFileSync(path.join(pack,'review','notes.jsonl'),'utf8').trim().split('\n').length,2,'none of those saved');
});
