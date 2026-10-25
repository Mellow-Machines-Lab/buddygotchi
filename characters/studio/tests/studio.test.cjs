// The studio's logic with no browser (README.md, "Checking it"): board.js's
// change measure and its summary, held to the rule measure.py's test is
// (internal/tools/fluid/tests/changed.json), and how it asks the board for
// each state; and serve.cjs's review verdicts, which charactergen's review
// check takes, its files in part and the review clips it saves, in a copy
// of it beside a pack of its own; and markdown.js's rendering of a reading.
// Run: node --test
// characters/studio/tests/
const assert=require('node:assert/strict'),{test}=require('node:test'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {spawn,execFileSync}=require('node:child_process');
const studio=path.resolve(__dirname,'..'),repo=path.resolve(studio,'../..');
const {wiring,changed,summary}=require(path.join(studio,'board.js'));
const pinned=JSON.parse(fs.readFileSync(path.join(repo,'internal/tools/fluid/tests/changed.json'),'utf8'));
// charactergen's, as it writes them for the page (packs.js): the acts the board draws while working.
const python=code=>JSON.parse(execFileSync('python3',['-c',`import json,sys;sys.path.insert(0,${JSON.stringify(path.join(repo,'characters'))});import charactergen as gen;${code}`],{encoding:'utf8'}));
const acts=python('print(json.dumps(gen.firmware_acts()))');

test('a pixel changed when its difference\'s luma is over 24 levels, and a summary, as measure.py has them', () => {
  const {pairs,summaries}=pinned;
  const rgba=side=>Uint8ClampedArray.from(pairs.flatMap(p=>[...p[side],255]));
  for(const [a,b,counts] of pairs)assert.equal(changed(Uint8ClampedArray.from([...a,255]),Uint8ClampedArray.from([...b,255])),Number(counts),`${a} → ${b}`);
  assert.equal(changed(rgba(0),rgba(1)),pairs.filter(p=>p[2]).length);
  for(const {changes,...expected} of summaries)assert.deepEqual(summary(changes),expected,`${changes}: the median, the first largest and their ratio`);
});

test('Rank\'s everyday transitions are transitions.jsonl\'s, by its shots\' names, and the board is asked for each', async () => {
  const {TAP}=await import(path.join(repo,'simulator/web/boop-simulator.js'));
  const wire=wiring({acts,tap:TAP}),everyday=python('print(json.dumps(gen.everyday()))');
  const shots=fs.readFileSync(path.join(repo,'internal/tools/fluid/transitions.jsonl'),'utf8').match(/"shot": "\d+-[a-z-]+"/g)
    .map(s=>s.slice(s.indexOf('-')+1,-1).replace(/-/g,' '));
  assert.deepEqual(everyday.map(t=>t.name),[...new Set(shots)].slice(1),'each run of shots after the first');
  const facts=JSON.parse(fs.readFileSync(path.join(studio,'states.json'),'utf8')).facts;
  for(const {from,to} of everyday)for(const cell of [from,to]){
    const [mood,state,fact]=cell.split('/');
    assert.ok(wire({mood,state,...(fact?{[facts[state].name]:fact}:{})}).steps.length,cell);
  }
});

test('the board is asked for each state as the Mac asks for it', async () => {
  const {TAP}=await import(path.join(repo,'simulator/web/boop-simulator.js'));
  const wire=wiring({acts,tap:TAP});
  const states=JSON.parse(fs.readFileSync(path.join(studio,'states.json'),'utf8')).groups.flatMap(g=>g.states.map(s=>s.id));
  for(const state of states)assert.ok(wire({mood:'calm',state}).steps.length,`${state} has its messages`);
  assert.throws(()=>wire({mood:'calm',state:'dancing'}),/no state dancing/);
  const only=cell=>wire(cell).steps.map(([ms,m])=>[ms,{...m,id:undefined}]);
  assert.deepEqual(only({mood:'calm',state:'idle'}),[[0,{t:'state',base:'idle',mood:'calm',vol:0,id:undefined}]]);
  assert.deepEqual(wire({mood:'calm',state:'testing'}).steps[0][1],{t:'state',base:'working',busy:1,act:'testing',mood:'calm',vol:0},'what the agent does, while working');
  assert.deepEqual(acts.map(act=>wire({mood:'calm',state:act}).steps[0][1].act),acts,'each act the firmware draws');
  assert.equal(wire({mood:'calm',state:'needs_you'}).steps[0][1].attn.agent,'claude');
  const finish=wire({mood:'proud',state:'task_complete',outcome:'failure'}).steps;
  assert.deepEqual(finish.map(([,m])=>[m.t,m.base||m.name]),[['state','working'],['do','task_complete']],'a reaction over working');
  assert.deepEqual(finish[1][1].args,{outcome:'failure'});
  assert.deepEqual(wire({mood:'calm',state:'starting',context:'compacted'}).steps[1][1].args,{ctx:'compacted'});
  assert.equal(wire({mood:'calm',state:'wake_up'}).steps[0][1].base,'idle','waking up is over idle');
  const over={base:'asleep'},asked=(cell,under)=>wire(cell,under).steps.map(([ms,m])=>[ms,m.t,m.name,m.args]);
  assert.deepEqual(asked({mood:'calm',state:'notice'},over),[[0,'do','notice',{mood:'calm'}]],
    'a transition\'s reaction plays over its start\'s look, its state left as it was, in its own mood');
  assert.deepEqual(asked({mood:'excited',state:'task_complete'},{base:'working',busy:1}),[[0,'do','task_complete',{outcome:'success',mood:'excited'}]],
    'a finish over working in its own mood, as internal/tools/fluid/transitions.jsonl asks for one');
  assert.equal(wire({mood:'calm',state:'poked'},over).steps[0][1].base,'asleep','an input over its start\'s look');
  assert.deepEqual(wire({mood:'calm',state:'tap_spam'}).steps.slice(1).map(([ms,m])=>[ms,m.t]),[[0,'dbg.touch'],[200,'dbg.touch'],[400,'dbg.touch']],'the third tap within 3 s is tap spam');
  assert.deepEqual([wire({mood:'calm',state:'poked'}).steps[1][1].x,wire({mood:'calm',state:'poked'}).steps[1][1].y],TAP,'a tap where the simulator taps');
  assert.ok(wire({mood:'calm',state:'gesture'}).steps[1][1].to_x,'a stroke');
  assert.equal(wire({mood:'calm',state:'no_app'}).after,30000,'no app: 30 s with no state (linkkit\'s kHostGoneMs)');
});

test('serve.cjs saves a verdict charactergen takes, only from its own page, and serves files in part', async t => {
  // A copy of the server beside a pack of its own, so nothing lands in the real characters/.
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'studio-')),pack=path.join(dir,'characters','pal');
  fs.mkdirSync(path.join(dir,'characters','studio'),{recursive:true});fs.mkdirSync(path.join(pack,'review'),{recursive:true});
  fs.copyFileSync(path.join(studio,'serve.cjs'),path.join(dir,'characters','studio','serve.cjs'));
  fs.writeFileSync(path.join(pack,'character.json'),'{}');
  fs.writeFileSync(path.join(pack,'review','queue.json'),JSON.stringify([{id:'perk',title:'Notice',what:'A perk.',status:'in review'}]));
  fs.writeFileSync(path.join(pack,'clip.webm'),Buffer.from([0,1,2,3,4,5,6,7,8,9]));
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
  const [queue,notes,problems]=python(`print(json.dumps(gen.review(gen.Path(${JSON.stringify(pack)}))))`);
  assert.deepEqual([notes,problems],[lines,[]],'charactergen\'s review check takes what the server wrote');
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
  assert.equal(queue.length,1);
  // A file whole, and the parts a video seeking asks for.
  const get=async range=>{const got=await fetch(`${url}/pal/clip.webm`,{headers:range?{Range:range}:{}});
    return [got.status,got.headers.get('content-range'),[...new Uint8Array(await got.arrayBuffer())]];};
  const whole=await fetch(`${url}/pal/clip.webm`);
  assert.deepEqual([whole.status,whole.headers.get('accept-ranges'),whole.headers.get('content-type')],[200,'bytes','video/webm']);
  assert.deepEqual(await get('bytes=2-5'),[206,'bytes 2-5/10',[2,3,4,5]]);
  assert.deepEqual(await get('bytes=8-'),[206,'bytes 8-9/10',[8,9]]);
  assert.deepEqual(await get('bytes=-3'),[206,'bytes 7-9/10',[7,8,9]]);
  assert.deepEqual(await get('bytes=6-99'),[206,'bytes 6-9/10',[6,7,8,9]]);
  assert.deepEqual(await get('bytes=20-'),[416,'bytes */10',[]],'past its end');
  assert.deepEqual((await get('bytes=0-1,4-5'))[0],200,'several ranges: the whole file');
});

// A clip the studio saves for a pack's tools (--capture-dir): off unless
// asked; then only from its own page with its token, a WebM by its header,
// named by a pack's `captures`, at most 8 MiB, each a new file, and an
// upload gone quiet for 15 s closed.
test('serve.cjs saves only the review clips a pack names, from its own page, never over one', async t => {
  const http=require('node:http');
  const webm=Buffer.from('GkXfo59ChoEBQveBAULygQRC84EIQoKEd2VibUKHgQJChYECGFOAZwEAAAAAAAHzEU2bdLpNu4tTq4QVSalmU6yBoU27i1OrhBZUrmtTrIHWTbuMU6uEElTDZ1OsggEyTbuMU6uEHFO7a1OsggHd7AEAAAAAAABZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVSalmsCrXsYMPQkBNgIxMYXZmNjMuMS4xMDFXQYxMYXZmNjMuMS4xMDFEiYhAj0AAAAAAABZUrmvXrgEAAAAAAABO14EBc8WIUyNHVZLGuuucgQAitZyDdW5kiIEAhoVWX1ZQOIOBASPjg4Q7msoA4JCwgQK6gQKagQJVsIRVuYEBVe6BAOwBAAAAAAAAAgAAElTDZ/pzc59jwIBnyJlFo4dFTkNPREVSRIeMTGF2ZjYzLjEuMTAxc3PVY8CLY8WIUyNHVZLGuutnyKBFo4dFTkNPREVSRIeTTGF2YzYzLjEuMTAxIGxpYnZweGfIoUWjiERVUkFUSU9ORIeTMDA6MDA6MDEuMDAwMDAwMDAwAB9DtnWn54EAo6KBAACAEAIAnQEqAgACAAvHCIWFiJmEiD+CAAwNYAD+5rUAHFO7a5G7j7OBALeK94EB8YIBsfCBAw==','base64');
  const max=8*1024*1024;
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'studio-')),pack=path.join(dir,'characters','pal'),clips=path.join(dir,'clips');
  fs.mkdirSync(path.join(dir,'characters','studio'),{recursive:true});fs.mkdirSync(pack);
  fs.copyFileSync(path.join(studio,'serve.cjs'),path.join(dir,'characters','studio','serve.cjs'));
  fs.writeFileSync(path.join(pack,'character.json'),JSON.stringify({studio:[{id:'board-gel',board:'gel',captures:'sets.json'}]}));
  fs.writeFileSync(path.join(pack,'sets.json'),JSON.stringify({cases:['happy.working','sad.working','grumpy.terminal','frightened.asleep'].map(id=>({id}))}));
  const servers=[];
  t.after(()=>{for(const s of servers)s.kill();fs.rmSync(dir,{recursive:true,force:true});});
  const start=async(...args)=>{
    const port=20000+Math.floor(Math.random()*20000),s=spawn(process.execPath,[path.join(dir,'characters','studio','serve.cjs'),'--port',String(port),...args],{stdio:'ignore'});
    servers.push(s);
    for(let i=0;i<100;i++){try{await fetch(`http://127.0.0.1:${port}/`);break;}catch{await new Promise(r=>setTimeout(r,50));}}
    return port;
  };
  const ask=(port,{route='/review-capture-config',method='GET',headers={},body=Buffer.alloc(0),chunked=false,stall=false}={})=>new Promise((ok,fail)=>{
    const req=http.request({hostname:'127.0.0.1',port,path:route,method,agent:false,
      headers:{Host:`127.0.0.1:${port}`,...(chunked?{}:{'Content-Length':stall?webm.length:body.length}),...headers}},res=>{
      const chunks=[];res.on('data',d=>chunks.push(d));res.once('end',()=>ok({status:res.statusCode,headers:res.headers,body:Buffer.concat(chunks)}));
    });
    req.once('error',error=>error.code==='ECONNRESET'?ok({status:'reset'}):fail(error));
    if(stall)req.write(body.subarray(0,1));  // a real start, then nothing more
    else if(chunked){for(let at=0;at<body.length;at+=65536)req.write(body.subarray(at,at+65536));req.end();}
    else req.end(body);
  });
  let port=await start();
  assert.deepEqual(JSON.parse((await ask(port)).body),{enabled:false},'off unless asked, with no token');
  assert.equal((await ask(port,{route:'/review-captures/happy.working.webm',method:'POST',body:webm})).status,405);
  port=await start('--capture-dir',clips);
  const config=await ask(port),settings=JSON.parse(config.body),origin=`http://127.0.0.1:${port}`;
  assert.deepEqual([settings.enabled,/^[a-f0-9]{64}$/.test(settings.token),settings.directory,config.headers['cache-control']],[true,true,'clips','no-store']);
  assert.equal((await ask(port,{headers:{Host:`localhost:${port}`}})).status,403,'its config to its own address only');
  const auth={Origin:origin,'X-Boop-Review-Token':settings.token,'Content-Type':'video/webm'};
  const post=(name='happy.working.webm',o={})=>({route:'/review-captures/'+name,method:'POST',headers:auth,body:webm,...o});
  for(const [why,headers] of [['no origin',{'X-Boop-Review-Token':settings.token,'Content-Type':'video/webm'}],['another site',{...auth,Origin:'https://example.invalid'}],
    ['another name for it',{...auth,Origin:`http://localhost:${port}`}],['a null origin',{...auth,Origin:'null'}],['no token',{Origin:origin,'Content-Type':'video/webm'}],
    ['the wrong token',{...auth,'X-Boop-Review-Token':'nope'}],['another Host',{...auth,Host:`localhost:${port}`}]])
    assert.equal((await ask(port,post('happy.working.webm',{headers}))).status,403,why);
  assert.equal((await ask(port,{route:'/review-captures/happy.working.webm',headers:auth})).status,405,'POST only');
  for(const name of ['other.webm','happy.idle.webm','happy.working.mp4','%2e%2e%2fescaped.webm','%2Ftmp%2Fescaped.webm','happy.working.webm%00'])
    assert.equal((await ask(port,post(name))).status,400,`not a clip the pack names: ${name}`);
  assert.equal((await ask(port,post('happy.working.webm',{headers:{...auth,'Content-Type':'application/octet-stream'}}))).status,400,'a WebM by its type');
  for(const body of [Buffer.alloc(0),Buffer.from([0x1a,0x45,0xdf]),Buffer.from('not WebM')])
    assert.equal((await ask(port,post('happy.working.webm',{body}))).status,400,'and by its header');
  const large=Buffer.alloc(max+1);webm.copy(large);
  assert.equal((await ask(port,post('sad.working.webm',{body:large,chunked:true}))).status,413,'at most 8 MiB');
  const before=performance.now(),quiet=await ask(port,post('sad.working.webm',{stall:true}));
  const waited=performance.now()-before;
  assert.ok((quiet.status===408||quiet.status==='reset')&&waited>=14500&&waited<19500,`an upload gone quiet is closed at 15 s, not ${Math.round(waited)} ms`);
  assert.deepEqual(fs.readdirSync(clips),[],'none of those saved');
  assert.equal((await ask(port,post('happy.working.webm',{headers:{...auth,'Content-Type':'video/webm;codecs=vp9'}}))).status,201);
  assert.deepEqual(fs.readFileSync(path.join(clips,'happy.working.webm')),webm,'as sent');
  assert.equal((await ask(port,post('happy.working.webm'))).status,409,'never over one already there');
  const both=await Promise.all([ask(port,post('grumpy.terminal.webm')),ask(port,post('grumpy.terminal.webm'))]);
  assert.deepEqual(both.map(r=>r.status).sort(),[201,409],'one of two at once');
  assert.equal((await ask(port,post('frightened.asleep.webm',{body:large.subarray(0,max)}))).status,201,'8 MiB exactly');
  assert.deepEqual(fs.readdirSync(clips).sort(),['frightened.asleep.webm','grumpy.terminal.webm','happy.working.webm']);
});

test('a reading\'s Markdown, as elements: headings, paragraphs, lists, tables and code', () => {
  const {render}=require(path.join(studio,'markdown.js'));
  // h as plain objects, and back to a compact form to compare.
  const h=(tag,props,...children)=>({tag,props,children});
  const show=n=>typeof n==='string'?n:`<${n.tag}${n.props.href?` ${n.props.href}`:''}>${n.children.map(show).join('')}`;
  const md=['# Notice: the reading','','Read from `sheets/perk.gif.png`, **slowly**,','then *again*. See [the bank](https://example.com) or [here](frames/).',
    '','## Beats','','| ms | Beat |','| --- | --- |','| 0–160 | Dozing |','| 200 | The `!` |','',
    '- Resting squash','  is flat.','- Perk: tall','','1. one','2. two','','```','a | b','# not a heading','```','---','| a lone bar'].join('\n');
  assert.deepEqual(render(md,h).map(show),[
    '<h3>Notice: the reading',
    '<p>Read from <code>sheets/perk.gif.png, <strong>slowly, then <em>again. See <a https://example.com>the bank or here.',
    '<h4>Beats',
    '<table><thead><tr><th>ms<th>Beat<tbody><tr><td>0–160<td>Dozing<tr><td>200<td>The <code>!',
    '<ul><li>Resting squash is flat.<li>Perk: tall',
    '<ol><li>one<li>two',
    '<pre><code>a | b\n# not a heading',
    '<hr>',
    '<p>| a lone bar',
  ]);
  assert.deepEqual(render('',h),[]);
  assert.deepEqual(render('snake_case_name and 2*3*4',h).map(show),['<p>snake_case_name and 2*3*4'],'no emphasis inside words');
});
