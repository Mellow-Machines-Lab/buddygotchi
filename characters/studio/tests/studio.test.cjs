// The studio's logic with no browser (README.md, "Checking it"): how
// board.js asks the board for each state, and the review clips the
// studio's server (simulator/web/serve.py) saves for a pack's tools, over a
// pack of its own.
// Run: node --test characters/studio/tests/
const assert=require('node:assert/strict'),{test}=require('node:test'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {spawn,execFileSync}=require('node:child_process');
const studio=path.resolve(__dirname,'..'),repo=path.resolve(studio,'../..');
const {wiring}=require(path.join(studio,'board.js'));
// charactergen's, as it writes them for the page (packs.js): the acts the board draws while working.
const python=code=>JSON.parse(execFileSync('python3',['-c',`import json,sys;sys.path.insert(0,${JSON.stringify(path.join(repo,'characters'))});import charactergen as gen;${code}`],{encoding:'utf8'}));
const acts=python('print(json.dumps(gen.firmware_acts()))');

test('the board is asked for each state as the Mac asks for it', async () => {
  const {TAP}=await import(path.join(repo,'simulator/web/boop-simulator.js'));
  const wire=wiring({acts,tap:TAP});
  const states=JSON.parse(fs.readFileSync(path.join(studio,'states.json'),'utf8')).groups.flatMap(g=>g.states.map(s=>s.id));
  for(const state of states)assert.ok(wire({mood:'calm',state}).steps.length,`${state} has its messages`);
  assert.throws(()=>wire({mood:'calm',state:'dancing'}),/no state dancing/);
  const only=cell=>wire(cell).steps.map(([ms,m])=>[ms,{...m,id:undefined}]);
  assert.deepEqual(only({mood:'calm',state:'idle'}),[[0,{t:'state',base:'idle',mood:'calm',vol:0,id:undefined}]]);
  assert.deepEqual(wire({mood:'calm',state:'testing'}).steps[0][1],{t:'state',base:'working',busy:1,act:'testing',calls:[[0,1,'running the tests']],mood:'calm',vol:0},'what the agent does, while working, and the strip says it');
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
    'a finish over working in its own mood');
  assert.equal(wire({mood:'calm',state:'poked'},over).steps[0][1].base,'asleep','an input over its start\'s look');
  assert.deepEqual(wire({mood:'calm',state:'tap_spam'}).steps.slice(1).map(([ms,m])=>[ms,m.t]),[[0,'dbg.touch'],[200,'dbg.touch'],[400,'dbg.touch']],'the third tap within 3 s is tap spam');
  assert.deepEqual([wire({mood:'calm',state:'poked'}).steps[1][1].x,wire({mood:'calm',state:'poked'}).steps[1][1].y],TAP,'a tap where the simulator taps');
  assert.ok(wire({mood:'calm',state:'gesture'}).steps[1][1].to_x,'a stroke');
  assert.equal(wire({mood:'calm',state:'no_app'}).after,30000,'no app: 30 s with no state (linkkit\'s kHostGoneMs)');
});

// The studio's server over `characters`, a folder of packs of its own, so
// nothing lands in the real characters/: a page with nothing built, and its
// USB socket in the folder beside it.
const serve=(characters,port,...args)=>{
  const dist=path.join(path.dirname(characters),'dist');fs.mkdirSync(dist,{recursive:true});fs.writeFileSync(path.join(dist,'boop-sim.wasm'),'');
  return spawn('python3',[path.join(repo,'simulator','web','serve.py'),'--port',String(port),'--characters',characters,'--dist',dist,
    '--socket',path.join(path.dirname(characters),`usb-${port}.sock`),'--voice',os.devnull,...args],{stdio:'ignore'});
};

// A clip the studio saves for a pack's tools (--capture-dir): off unless
// asked; then only from its own page with its token, a WebM by its header,
// named by a pack's `captures`, at most 8 MiB, each a new file, and an
// upload gone quiet for 15 s closed.
test('the studio\'s server saves only the review clips a pack names, from its own page, never over one', async t => {
  const http=require('node:http');
  const webm=Buffer.from('GkXfo59ChoEBQveBAULygQRC84EIQoKEd2VibUKHgQJChYECGFOAZwEAAAAAAAHzEU2bdLpNu4tTq4QVSalmU6yBoU27i1OrhBZUrmtTrIHWTbuMU6uEElTDZ1OsggEyTbuMU6uEHFO7a1OsggHd7AEAAAAAAABZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVSalmsCrXsYMPQkBNgIxMYXZmNjMuMS4xMDFXQYxMYXZmNjMuMS4xMDFEiYhAj0AAAAAAABZUrmvXrgEAAAAAAABO14EBc8WIUyNHVZLGuuucgQAitZyDdW5kiIEAhoVWX1ZQOIOBASPjg4Q7msoA4JCwgQK6gQKagQJVsIRVuYEBVe6BAOwBAAAAAAAAAgAAElTDZ/pzc59jwIBnyJlFo4dFTkNPREVSRIeMTGF2ZjYzLjEuMTAxc3PVY8CLY8WIUyNHVZLGuutnyKBFo4dFTkNPREVSRIeTTGF2YzYzLjEuMTAxIGxpYnZweGfIoUWjiERVUkFUSU9ORIeTMDA6MDA6MDEuMDAwMDAwMDAwAB9DtnWn54EAo6KBAACAEAIAnQEqAgACAAvHCIWFiJmEiD+CAAwNYAD+5rUAHFO7a5G7j7OBALeK94EB8YIBsfCBAw==','base64');
  const max=8*1024*1024;
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'studio-')),pack=path.join(dir,'characters','pal'),clips=path.join(dir,'clips');
  fs.mkdirSync(pack,{recursive:true});
  fs.writeFileSync(path.join(pack,'character.json'),JSON.stringify({studio:[{id:'board-gel',board:'gel',captures:'sets.json'}]}));
  fs.writeFileSync(path.join(pack,'sets.json'),JSON.stringify({cases:['happy.working','sad.working','grumpy.terminal','frightened.asleep'].map(id=>({id}))}));
  const servers=[];
  t.after(()=>{for(const s of servers)s.kill();fs.rmSync(dir,{recursive:true,force:true});});
  const start=async(...args)=>{
    const port=20000+Math.floor(Math.random()*20000),s=serve(path.join(dir,'characters'),port,...args);
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
