#!/usr/bin/env node
// VALIDATION.md: opt-in loopback capture export. Standalone because binding a
// local port may require sandbox permission; ordinary offline QA never runs it.
const assert=require('node:assert/strict'),http=require('node:http'),net=require('node:net');
const fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path');
const {spawn}=require('node:child_process');
const SPEC='VALIDATION.md: bounded local evidence export';
if(process.argv.includes('--help')){
  console.log('node tools/check-server.cjs\nTests opt-in review capture over temporary loopback ports and a temporary directory.\nRequires permission to bind 127.0.0.1; no browser, camera, external network or permanent output.');
  process.exit(0);
}
if(process.argv.length!==2){console.error('Unknown arguments; use --help');process.exit(1);}

// One 2x2 black VP8 frame, generated locally with FFmpeg. Embedding the fixture
// keeps the check Node-only; neither FFmpeg nor a media decoder is required.
const webm=Buffer.from('GkXfo59ChoEBQveBAULygQRC84EIQoKEd2VibUKHgQJChYECGFOAZwEAAAAAAAHzEU2bdLpNu4tTq4QVSalmU6yBoU27i1OrhBZUrmtTrIHWTbuMU6uEElTDZ1OsggEyTbuMU6uEHFO7a1OsggHd7AEAAAAAAABZAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVSalmsCrXsYMPQkBNgIxMYXZmNjMuMS4xMDFXQYxMYXZmNjMuMS4xMDFEiYhAj0AAAAAAABZUrmvXrgEAAAAAAABO14EBc8WIUyNHVZLGuuucgQAitZyDdW5kiIEAhoVWX1ZQOIOBASPjg4Q7msoA4JCwgQK6gQKagQJVsIRVuYEBVe6BAOwBAAAAAAAAAgAAElTDZ/pzc59jwIBnyJlFo4dFTkNPREVSRIeMTGF2ZjYzLjEuMTAxc3PVY8CLY8WIUyNHVZLGuutnyKBFo4dFTkNPREVSRIeTTGF2YzYzLjEuMTAxIGxpYnZweGfIoUWjiERVUkFUSU9ORIeTMDA6MDA6MDEuMDAwMDAwMDAwAB9DtnWn54EAo6KBAACAEAIAnQEqAgACAAvHCIWFiJmEiD+CAAwNYAD+5rUAHFO7a5G7j7OBALeK94EB8YIBsfCBAw==','base64');
const maxBytes=8*1024*1024; // Pin the documented cap, not the implementation constant.
const children=new Set();

async function freePort(){
  const probe=net.createServer();
  await new Promise((resolve,reject)=>{probe.once('error',reject);probe.listen(0,'127.0.0.1',resolve);});
  const port=probe.address().port;
  await new Promise((resolve,reject)=>probe.close(error=>error?reject(error):resolve()));
  return port;
}
async function stop(child){
  if(child.exitCode!==null||child.signalCode!==null){children.delete(child);return;}
  await new Promise(resolve=>{
    let force,deadline;
    const done=()=>{clearTimeout(force);clearTimeout(deadline);resolve();};
    child.once('exit',done);child.kill('SIGTERM');
    force=setTimeout(()=>child.kill('SIGKILL'),1000);
    deadline=setTimeout(()=>{child.removeListener('exit',done);resolve();},2000);
  });
  children.delete(child);
}
async function server(captureDir){
  for(let attempt=0;attempt<3;attempt++){
    const port=await freePort(),args=[path.join(__dirname,'../../../../studio/serve.cjs'),'--port',String(port)];
    if(captureDir)args.push('--capture-dir',captureDir);
    const child=spawn(process.execPath,args,{stdio:['ignore','pipe','pipe']});children.add(child);
    let log='';
    try{
      await new Promise((resolve,reject)=>{
        const timer=setTimeout(()=>done(Error('Server did not become ready within 5 seconds: '+log)),5000);
        function done(error){clearTimeout(timer);child.removeListener('error',failed);child.removeListener('exit',exited);error?reject(error):resolve();}
        function failed(error){done(error);}
        function exited(code,signal){done(Error(`Server exited ${code??signal}: ${log}`));}
        child.once('error',failed);child.once('exit',exited);
        child.stderr.on('data',data=>{log+=data;});
        child.stdout.on('data',data=>{log+=data;if(log.includes(`http://127.0.0.1:${port}/`))done();});
      });
      return {port,origin:`http://127.0.0.1:${port}`,child};
    }catch(error){await stop(child);if(attempt<2&&log.includes('EADDRINUSE'))continue;throw error;}
  }
}
function request(s,{route='/review-capture-config',method='GET',headers={},body=Buffer.alloc(0),chunked=false}={}){
  return new Promise((resolve,reject)=>{
    const req=http.request({hostname:'127.0.0.1',port:s.port,path:route,method,agent:false,
      headers:{Host:`127.0.0.1:${s.port}`,...(!chunked?{'Content-Length':body.length}:{}),...headers}},res=>{
      const chunks=[];res.on('data',data=>chunks.push(data));res.once('error',reject);
      res.once('end',()=>resolve({status:res.statusCode,headers:res.headers,body:Buffer.concat(chunks)}));
    });
    req.setTimeout(5000,()=>req.destroy(Error('Request exceeded 5 seconds')));req.once('error',reject);
    if(chunked){for(let offset=0;offset<body.length;offset+=65536)req.write(body.subarray(offset,offset+65536));req.end();}
    else req.end(body);
  });
}
function stalledUpload(s,headers){
  return new Promise((resolve,reject)=>{
    const start=performance.now();let finished=false;
    const req=http.request({hostname:'127.0.0.1',port:s.port,path:'/review-captures/sad.terminal.webm',method:'POST',agent:false,
      headers:{Host:`127.0.0.1:${s.port}`,...headers,'Content-Length':webm.length}},res=>{
      res.resume();res.once('end',()=>done(null,res.statusCode));res.once('error',error=>done(error));
    });
    const timer=setTimeout(()=>done(Error('Inactive upload was not closed within 20 seconds')),20000);
    function done(error,status){
      if(finished)return;finished=true;clearTimeout(timer);req.destroy();
      if(error&&error.code!=='ECONNRESET')reject(error);
      else resolve({status:status??'connection-reset',elapsedMs:performance.now()-start});
    }
    req.once('error',error=>done(error));
    // Send a real partial body, then deliberately never end it. The server's
    // inactivity timer, rather than any client deadline, must close it.
    req.write(webm.subarray(0,1));
  });
}

(async()=>{
  const temp=await fs.mkdtemp(path.join(os.tmpdir(),'boop-slime-capture-check-'));
  let assertions=0,report;
  const status=async(s,options,expected,label)=>{const response=await request(s,options);assert.equal(response.status,expected,`${SPEC}: ${label}`);assertions++;return response;};
  try{
    const disabled=await server();
    const config=await status(disabled,{},200,'capture config is readable');
    assert.deepEqual(JSON.parse(config.body),{enabled:false},`${SPEC}: saving defaults off and exposes no token`);assertions++;
    await status(disabled,{route:'/review-captures/happy.working.webm',method:'POST',body:webm},405,'writes disabled by default');
    await stop(disabled.child);

    const directory=path.join(temp,'clips'),enabled=await server(directory);
    const configured=await status(enabled,{},200,'opt-in capture config');
    const settings=JSON.parse(configured.body);
    assert.equal(settings.enabled,true);assert.match(settings.token,/^[a-f0-9]{64}$/);assert.equal(settings.directory,'clips');
    assert.equal(configured.headers['cache-control'],'no-store');assertions+=4;
    const auth={Origin:enabled.origin,'X-Boop-Review-Token':settings.token,'Content-Type':'video/webm'};
    const post=(filename='happy.working.webm',overrides={})=>({route:'/review-captures/'+filename,method:'POST',headers:auth,body:webm,...overrides});
    await status(enabled,{headers:{Host:'localhost:'+enabled.port}},403,'config rejects other Host');
    for(const [label,headers] of [
      ['missing origin',{'X-Boop-Review-Token':settings.token,'Content-Type':'video/webm'}],
      ['foreign origin',{...auth,Origin:'https://example.invalid'}],
      ['wrong loopback origin',{...auth,Origin:'http://localhost:'+enabled.port}],
      ['null origin',{...auth,Origin:'null'}],
      ['missing token',{Origin:enabled.origin,'Content-Type':'video/webm'}],
      ['wrong token',{...auth,'X-Boop-Review-Token':'not-the-token'}],
      ['wrong Host',{...auth,Host:'localhost:'+enabled.port}],
    ])await status(enabled,post('happy.working.webm',{headers}),403,label);
    await status(enabled,{route:'/review-captures/happy.working.webm',method:'GET',headers:auth},405,'capture endpoint is POST-only');
    for(const filename of ['other.webm','happy.idle.webm','happy.working.mp4','%2e%2e%2fescaped.webm','%2Ftmp%2Fescaped.webm','happy.working.webm%00']){
      await status(enabled,post(filename),400,'reject unsafe/non-whitelisted filename '+filename);
    }
    await status(enabled,post('happy.working.webm',{headers:{...auth,'Content-Type':'application/octet-stream'}}),400,'requires WebM content type');
    for(const body of [Buffer.alloc(0),Buffer.from([0x1a,0x45,0xdf]),Buffer.from('not WebM')]){
      await status(enabled,post('happy.working.webm',{body}),400,'reject missing/truncated/wrong EBML signature');
    }
    const large=Buffer.alloc(maxBytes+1);webm.copy(large);
    await status(enabled,post('sad.working.webm',{body:large,chunked:true}),413,'streaming capture larger than 8 MiB rejected');
    const idle=await stalledUpload(enabled,auth);
    assert.ok(idle.status===408||idle.status==='connection-reset',`${SPEC}: inactive upload closes with timeout`);
    assert.ok(idle.elapsedMs>=14500&&idle.elapsedMs<19500,`${SPEC}: documented 15-second inactivity timeout, measured ${Math.round(idle.elapsedMs)} ms`);assertions+=2;
    assert.deepEqual(await fs.readdir(directory),[],`${SPEC}: rejected captures create no files`);assertions++;
    await status(enabled,post('happy.working.webm',{headers:{...auth,'Content-Type':'video/webm;codecs=vp9'}}),201,'valid capture saved');
    assert.deepEqual(await fs.readFile(path.join(directory,'happy.working.webm')),webm,`${SPEC}: saved bytes equal upload`);assertions++;
    await status(enabled,post('happy.working.webm'),409,'never overwrites an existing capture');
    assert.deepEqual(await fs.readFile(path.join(directory,'happy.working.webm')),webm,`${SPEC}: conflict preserves existing bytes`);assertions++;
    const races=await Promise.all([request(enabled,post('grumpy.terminal.webm')),request(enabled,post('grumpy.terminal.webm'))]);
    assert.deepEqual(races.map(r=>r.status).sort(),[201,409],`${SPEC}: concurrent writes are exclusive`);assertions++;
    await status(enabled,post('frightened.asleep.webm',{body:large.subarray(0,maxBytes)}),201,'exactly 8 MiB accepted');
    assert.equal((await fs.stat(path.join(directory,'frightened.asleep.webm'))).size,maxBytes,`${SPEC}: cap is inclusive`);assertions++;
    assert.deepEqual((await fs.readdir(directory)).sort(),['frightened.asleep.webm','grumpy.terminal.webm','happy.working.webm']);assertions++;
    await stop(enabled.child);
    report={status:'CAPTURE SERVER PASS',assertions,maxCaptureBytes:maxBytes,inactiveUploadMs:Math.round(idle.elapsedMs),default:'disabled',output:'temporary directory removed'};
  }finally{
    await Promise.all([...children].map(stop));
    await fs.rm(temp,{recursive:true,force:true});
  }
  console.log(JSON.stringify(report));
})().catch(error=>{console.error(error);process.exitCode=1;});
