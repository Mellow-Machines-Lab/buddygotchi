// The studio's logic with no browser (README.md, "Checking it"): the pack's
// moves, faces and moments as logic.js lists them and asks the board for
// them, a Moment's invite answered and missed on the board's own firmware
// (the simulator's build, when simulator/web/build.sh has made it), the
// motion switches, and the review clips the studio's server
// (simulator/web/serve.py) saves for a pack's tools, over a pack of its own.
// Run: node --test characters/studio/tests/
const assert=require('node:assert/strict'),{test}=require('node:test'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {spawn,execFileSync}=require('node:child_process');
const studio=path.resolve(__dirname,'..'),repo=path.resolve(studio,'../..');
const L=require(path.join(studio,'logic.js'));
// charactergen's, as it writes them for the page (packs.js): the acts the board draws while working, and Boop's pack.
const python=code=>JSON.parse(execFileSync('python3',['-c',`import json,sys;sys.path.insert(0,${JSON.stringify(path.join(repo,'characters'))});import charactergen as gen;${code}`],{encoding:'utf8',maxBuffer:64<<20}));
const acts=python('print(json.dumps(gen.firmware_acts()))');
const data=python('p=gen.CHARACTERS/"boop";print(json.dumps(gen.studio_data([p],p)))'),boop=data.packs.boop;
const pack=path.join(repo,'characters/boop'),character=JSON.parse(fs.readFileSync(path.join(pack,'character.json'),'utf8'));
const dist=path.join(repo,'simulator/web/dist'),unbuilt=fs.existsSync(path.join(dist,'boop-sim.wasm'))?false:'the simulator isn\'t built: simulator/web/build.sh';
const fixture=JSON.parse(fs.readFileSync(path.join(__dirname,'moments.json'),'utf8')).moments;

test('the board is asked for each state as the Mac asks for it, for a review clip', async () => {
  const {TAP}=await import(path.join(repo,'simulator/web/boop-simulator.js'));
  const wire=L.wiring({acts,tap:TAP});
  const states=JSON.parse(fs.readFileSync(path.join(studio,'states.json'),'utf8')).groups.flatMap(g=>g.states.map(s=>s.id));
  for(const state of states)assert.ok(wire({mood:'calm',state}).steps.length,`${state} has its messages`);
  assert.throws(()=>wire({mood:'calm',state:'dancing'}),/no state dancing/);
  const only=cell=>wire(cell).steps.map(([ms,m])=>[ms,{...m,id:undefined}]);
  assert.deepEqual(only({mood:'calm',state:'idle'}),[[0,{t:'state',base:'idle',mood:'calm',vol:0,id:undefined}]]);
  assert.deepEqual(wire({mood:'calm',state:'terminal'}).steps[0][1],{t:'state',base:'working',busy:1,act:'terminal',calls:[[0,1,'building']],mood:'calm',vol:0},'what the agent does, while working, and the strip says it');
  assert.deepEqual(wire({mood:'calm',state:'testing'}).steps[0][1],{t:'state',base:'working',busy:1,act:'terminal',calls:[[0,1,'running the tests']],mood:'calm',vol:0},'a state no Mac sends, as the act it shows as');
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

// Each clip of the pack's rig/ is one move, under the group its file names,
// in charactergen's order of the groups; a base is its own look, any other
// is asked by name over a look; finding keeps a move by its id or its about.
test('the moves are the pack\'s rig clips, in the groups the pack gives them', () => {
  const clips=fs.readdirSync(path.join(pack,'rig/clips')).filter(f=>f.endsWith('.json')).map(f=>[f.slice(0,-5),JSON.parse(fs.readFileSync(path.join(pack,'rig/clips',f),'utf8'))]);
  const groups=L.moveGroups(boop.moves,data.move_groups);
  assert.deepEqual(groups.flatMap(g=>g.moves.map(m=>m.id)).sort(),clips.map(([id])=>id).sort(),'every clip, once');
  for(const g of groups)for(const m of g.moves)assert.equal(m.group,Object.fromEntries(clips)[m.id].group,`${m.id}'s group is its file's`);
  assert.deepEqual(groups.map(g=>g.id),data.move_groups.filter(id=>clips.some(([,c])=>c.group===id)),'in the order charactergen gives');
  assert.deepEqual(data.move_groups,['bases','work_poses','moments','touch_answers','pastimes','with_you']);
  assert.deepEqual(groups.map(g=>g.label),['Bases','Work poses','Moments','Touch answers','Pastimes','With you']);
  const none=L.moveGroups([...boop.moves,{id:'new-one',about:'',ms:1,loop:false,group:null}],data.move_groups);
  assert.deepEqual([none.at(-1).label,none.at(-1).moves.map(m=>m.id)],['No group',['new-one']],'a clip with no group, last');
  assert.deepEqual(L.moveGroups(boop.moves,data.move_groups,'palm miss').flatMap(g=>g.moves.map(m=>m.id)),['invite-palm-miss'],'found by its words');
  // A base plays as its look: idle's, an activity's while working, a tier's; any other by name, over a look.
  const move=id=>boop.moves.find(m=>m.id===id);
  assert.deepEqual(L.moveSteps(move('breathe'),{mood:'calm'}),[[0,{t:'state',base:'idle',mood:'calm',vol:0}]]);
  assert.deepEqual(L.moveSteps(move('work-running'),{mood:'calm'})[0][1].act,'terminal');
  assert.deepEqual(L.moveSteps(move('work-easy'),{mood:'calm'})[0][1].when,['tier1']);
  assert.deepEqual(L.moveSteps(move('hop'),{mood:'happy'}),[[0,{t:'state',base:'idle',mood:'happy',vol:0}],[300,{t:'dbg.clip',name:'hop'}]]);
  assert.equal(L.overFor(move('work-waiting')),'working');
  assert.equal(L.moveSteps(move('to-work'),{mood:'calm',over:'asleep'})[0][1].base,'asleep','over the look you pick');
});

// The 24 the board draws: the Mac's 18, then the board's own 6, marked.
test('the faces sheet has every face the board draws, the board\'s own marked', () => {
  const sheet=L.faceSheet(boop.faces);
  assert.deepEqual(sheet.mac.map(f=>f.id),character.moods.map(m=>m.id));
  assert.deepEqual(sheet.board.map(f=>f.id),character.board_faces.map(m=>m.id));
  assert.deepEqual([sheet.mac.length,sheet.board.length],[18,6]);
  assert.ok(sheet.board.every(f=>f.board)&&sheet.mac.every(f=>!f.board));
  assert.deepEqual(L.faceSteps('deadpan'),[[0,{t:'state',base:'idle',mood:'deadpan',vol:0}]],'at rest');
  assert.deepEqual(L.faceSteps('deadpan','calm').map(([ms,m])=>[ms,m.mood]),[[0,'calm'],[L.CHANGE_MS,'deadpan']],'the change from one to the other');
});

// What the page sends for a skit is the Mac's own: tests/moments.json,
// which StudioMomentTests checks against MomentOutput.
test('a skit\'s Moment is the do the Mac sends for it', () => {
  assert.deepEqual(fixture.map(m=>m.skit).sort(),character.skits.map(s=>s.id).sort(),'every skit of the pack');
  for(const want of fixture){
    const skit=boop.skits.find(s=>s.id===want.skit);
    assert.deepEqual(L.momentOf(skit,{mood:want.mood,loops:want.loops,words:boop.words}),{name:want.name,args:want.args},want.skit);
  }
  const win=boop.skits.find(s=>s.id==='win'),[take]=L.takesFor(boop.takes,win,'happy');
  assert.ok(take&&take.moods.includes('happy')&&take.skit==='win','a take of the skit, in its face');
  assert.deepEqual(L.momentOf(win,{mood:'happy',take:take.id}).args.say,{take:take.id});
  const upset=boop.skits.find(s=>s.id==='upset');
  assert.ok(L.takesFor(boop.takes,upset,'sad').every(t=>t.skit==='upset'&&t.moods.includes('sad')),'only the skit\'s, in the face');
  assert.deepEqual(L.takesFor([{id:'a',skit:'upset',moods:['sad'],kind:'sound'},{id:'b',skit:'upset',moods:['sad'],kind:'word'}],upset,'sad','word').map(t=>t.id),['b','a'],'the size\'s kind first');
  const [look,does]=L.momentSteps(L.momentOf(win,{mood:'happy',words:boop.words}));
  assert.deepEqual([look[1].t,look[1].base,does[0],does[1].t,does[1].name,does[1].play],['state','working',300,'do','task_complete','now']);
  assert.equal(L.momentSteps(L.momentOf(boop.skits.find(s=>s.id==='back'),{mood:'happy'}))[0][1].base,'idle','the wake-up at rest');
  assert.deepEqual(L.heard('{"t":"ev","kind":"invite","did":"missed","data":{"skit":"win","touch":"tap","ms":4000}}'),{did:'missed',skit:'win',touch:'tap',ms:4000});
  assert.equal(L.heard('{"t":"ev","kind":"tap"}'),null);
});

test('the motion switches send dbg.motion, and those off again after a reset', () => {
  assert.deepEqual(boop.motion,['stretch','settle','drag','face','hands'],'the gel\'s rules, from its firmware');
  assert.deepEqual(L.motionMessage('drag',false),{t:'dbg.motion',rule:'drag',on:false});
  assert.deepEqual(L.motionAgain(boop.motion,new Set()),[]);
  assert.deepEqual(L.motionAgain(boop.motion,new Set(['face','drag'])),[L.motionMessage('drag',false),L.motionMessage('face',false)],'in the rules\' order');
  assert.deepEqual(L.motionAgain(boop.motion,new Set(boop.motion)),[L.motionMessage('all',false)]);
});

// The board's own firmware, on its frozen clock as a scenario steps it: what
// the page sends, then the clock on a step at a time, its lines kept.
async function firmware(){
  const {default:make}=await import(path.join(dist,'boop-sim.js'));
  const core=await make(),usb=core.cwrap('sim_usb',null,['string']),lines=[];
  const b={lines,send:m=>usb(JSON.stringify(m)+'\n'),
    tick(){core._sim_tick();const said=core._sim_usb_out();if(said)for(const l of core.UTF8ToString(said).split('\n'))if(l.startsWith('{'))lines.push(l);},
    // Its answer to a message, on the clock as it is.
    ask(m){const n=lines.length;b.send(m);for(let i=0;i<4;i++)b.tick();return JSON.parse(lines.slice(n).find(l=>l.startsWith(`{"t":"${m.t}"`)));},
    // Steps from a reset, the clock 40 ms at a time to `ms`; `each(t)` at every step.
    play(steps,ms,each=()=>{}){
      b.send({t:'dbg.reset'});b.tick();
      const due=[...steps].sort((x,y)=>x[0]-y[0]);
      for(let t=0;t<=ms;t+=40){
        while(due.length&&due[0][0]<=t)b.send(due.shift()[1]);
        b.send({t:'dbg.clock',freeze:t});b.tick();b.tick();each(t);
      }
    }};
  core._sim_power(1);
  b.tick();
  return b;
}

test('a Moment\'s invite, answered and missed, as the board reports it', {skip:unbuilt}, async () => {
  const {TAP}=await import(path.join(dist,'boop-simulator.js'));
  const b=await firmware(),heard=()=>b.lines.map(L.heard).filter(Boolean);
  for(const skit of boop.skits.filter(s=>s.invite)){
    const moment=()=>L.momentSteps(L.momentOf(skit,{mood:'happy',words:boop.words}));
    // Answer: the touch once the pose has come and waits for it. (A
    // stroke in the back pose's first half second, as it turns, hangs the
    // firmware today: the touch waits a second.)
    let answered=null,start=b.lines.length;
    b.play(moment(),20000,t=>{const i=answered===null&&b.ask({t:'dbg.state'}).invite;
      if(i?.stage==='pose'&&i.ms>=1000){answered=t;L.answerSteps(skit.invite.touch,TAP).forEach(([,m])=>b.send(m));}});
    assert.ok(answered!==null,`${skit.id}: its pose waited`);
    assert.deepEqual(b.lines.slice(start).map(L.heard).filter(Boolean).map(h=>[h.did,h.skit,h.touch]),[['answered',skit.id,skit.invite.touch]],`${skit.id}: answered`);
    // Miss: nothing sent, and the wait runs out.
    start=b.lines.length;
    b.play(moment(),20000);
    assert.deepEqual(b.lines.slice(start).map(L.heard).filter(Boolean).map(h=>[h.did,h.skit,h.ms]),[['missed',skit.id,4000]],`${skit.id}: missed`);
  }
  assert.ok(heard().length>=4);
  // Each motion rule the page shows is one the board switches; another isn't.
  for(const rule of [...boop.motion,'all'])assert.equal(b.ask(L.motionMessage(rule,false)).ok,true,rule);
  assert.equal(b.ask(L.motionMessage('wobble',false)).ok,false);
  // Each move asked by name is a clip the board plays.
  for(const m of boop.moves.filter(m=>!m.look))assert.equal(b.ask({t:'dbg.clip',name:m.id}).ok,true,m.id);
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
