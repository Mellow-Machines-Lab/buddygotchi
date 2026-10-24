// Loopback-only server for the studio: characters/ at /, and the simulator's
// build (simulator/web/dist/) at /simulator/, for the board's own previews,
// each file streamed, in part for a Range (a video seeking), and never cached.
// Writing is limited to two things: the clip names the packs' studio entries
// allow (`captures`, a JSON file of {cases:[{id}]}, each saved as <id>.webm,
// with --capture-dir), and a verdict on an item of a pack's review queue,
// appended to its review/notes.jsonl (POST /review).
const http=require('node:http'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
if(process.argv.includes('--help')){console.log('node characters/studio/serve.cjs [--port 4190] [--capture-dir DIR]\nServes characters/ on 127.0.0.1, and simulator/web/dist/ at /simulator/; / opens the studio.\nPOST /review appends a verdict to a pack\'s review/notes.jsonl.\n--capture-dir lets the packs\' tools save their named review clips there; never overwrites.');process.exit(0);}
const args=process.argv.slice(2);
for(let i=0;i<args.length;i+=2)if(!['--port','--capture-dir'].includes(args[i])||!args[i+1]||args[i+1].startsWith('--')||args.indexOf(args[i])!==i)throw Error('Use --help for arguments.');
const port=args.includes('--port')?Number(args[args.indexOf('--port')+1]):4190;
if(!Number.isInteger(port)||port<1024||port>65535)throw Error('Port must be an integer between 1024 and 65535.');
const root=path.resolve(__dirname,'..'),simulator=path.resolve(root,'..','simulator','web','dist');
const captureDir=args.includes('--capture-dir')?path.resolve(args[args.indexOf('--capture-dir')+1]):null;
const token=crypto.randomBytes(32).toString('hex'),origin='http://127.0.0.1:'+port;
const captureNames=new Set();
for(const pack of fs.readdirSync(root)){
  const file=path.join(root,pack,'character.json');if(!fs.existsSync(file))continue;
  for(const entry of JSON.parse(fs.readFileSync(file,'utf8')).studio||[]){
    const list=entry.captures;if(!list)continue;
    const cases=JSON.parse(fs.readFileSync(path.join(root,pack,list),'utf8')).cases;
    if(!Array.isArray(cases)||cases.some(item=>!/^[a-z][a-z0-9_.-]{1,80}$/.test(item.id)))throw Error(`Invalid capture allowlist ${pack}/${list}.`);
    for(const item of cases)captureNames.add(item.id+'.webm');
  }
}
const maxCaptureBytes=8*1024*1024; // VALIDATION.md: bounded local evidence export.
if(captureDir)fs.mkdirSync(captureDir,{recursive:true});
// A pack's folder by its name, or null for a name that isn't one.
const packFolder=pack=>typeof pack==='string'&&/^[a-z0-9][a-z0-9_-]*$/.test(pack)?path.join(root,pack):null;
// A verdict on one of a pack's review items (characters/CHARACTER.md §16): the line notes.jsonl gets, or why not.
// charactergen.py's review() checks the notes it writes (tests/studio.test.cjs holds the two together).
const maxNoteBytes=16*1024;
function verdict({pack,id,verdict,text}){
  const folder=packFolder(pack),queue=folder&&path.join(folder,'review','queue.json');
  const ids=queue&&fs.existsSync(queue)?JSON.parse(fs.readFileSync(queue,'utf8')).map(item=>item.id):[];
  if(!ids.includes(id))throw Error('No such review item');
  if(!['approve','change'].includes(verdict))throw Error('A verdict is approve or change');
  if(typeof text!=='string'||text.length>4000||(verdict==='change'&&!text.trim()))throw Error('A change needs a comment, at most 4000 characters');
  return {file:path.join(folder,'review','notes.jsonl'),note:{at:new Date().toISOString(),id,verdict,text:text.trim()}};
}
// The bytes a request's Range asks for, as a video seeks: {start, end} (end
// included), the whole file for none or one this doesn't read (several
// ranges), or null for one past its end.
function span(range,size){
  const asked=/^bytes=(\d*)-(\d*)$/.exec(range||'');
  if(!asked||!asked[1]&&!asked[2])return {start:0,end:size-1,whole:true};
  const [start,end]=asked[1]?[Number(asked[1]),asked[2]?Math.min(Number(asked[2]),size-1):size-1]:[Math.max(0,size-Number(asked[2])),size-1];
  return start<=end&&start<size?{start,end,whole:false}:null;
}
const types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json; charset=utf-8','.md':'text/plain; charset=utf-8',
  '.svg':'image/svg+xml','.png':'image/png','.jpg':'image/jpeg','.jpeg':'image/jpeg','.webp':'image/webp','.gif':'image/gif','.mp4':'video/mp4','.m4v':'video/mp4','.mov':'video/quicktime','.webm':'video/webm','.wasm':'application/wasm'};
http.createServer((req,res)=>{
  let name;
  try{name=decodeURIComponent(new URL(req.url,'http://localhost').pathname);}catch{res.writeHead(400);res.end();return;}
  if(name==='/review'){
    if(req.method==='GET'){  // ?pack=P: its verdicts so far, which packs.js has only as charactergen last saw them
      const folder=packFolder(new URL(req.url,'http://localhost').searchParams.get('pack')),file=folder&&path.join(folder,'review','notes.jsonl');
      const notes=(file&&fs.existsSync(file)?fs.readFileSync(file,'utf8'):'').split('\n').flatMap(line=>{try{return [JSON.parse(line)];}catch{return [];}});
      res.writeHead(200,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(notes));return;
    }
    if(req.method!=='POST'){res.writeHead(405);res.end();return;}
    if(req.headers.host!=='127.0.0.1:'+port||req.headers.origin!==origin||!/^application\/json(?:;|$)/.test(req.headers['content-type']||'')){res.writeHead(403);res.end();return;}
    let body='';req.setEncoding('utf8');
    req.on('data',chunk=>{body+=chunk;if(body.length>maxNoteBytes&&!res.writableEnded){res.writeHead(413);res.end();req.destroy();}});
    req.on('end',()=>{
      if(res.writableEnded)return;
      let saved;try{saved=verdict(JSON.parse(body));}catch(error){res.writeHead(400);res.end(error.message);return;}
      fs.appendFile(saved.file,JSON.stringify(saved.note)+'\n',error=>{res.writeHead(error?500:201,{'Content-Type':'application/json'});res.end(error?'Not saved':JSON.stringify(saved.note));});
    });
    return;
  }
  if(name==='/review-capture-config'||name.startsWith('/review-captures/')){
    if(req.headers.host!=='127.0.0.1:'+port){res.writeHead(403);res.end();return;}
    res.setHeader('Cache-Control','no-store');
    if(name==='/review-capture-config'&&req.method==='GET'){
      res.setHeader('Content-Type','application/json');res.end(JSON.stringify(captureDir?{enabled:true,token,directory:path.basename(captureDir)}:{enabled:false}));return;
    }
    if(!captureDir||req.method!=='POST'){res.writeHead(405);res.end();return;}
    if(req.headers.origin!==origin||req.headers['x-boop-review-token']!==token){res.writeHead(403);res.end();return;}
    const filename=name.slice('/review-captures/'.length);
    if(!captureNames.has(filename)||!/^video\/webm(?:;|$)/.test(req.headers['content-type']||'')){res.writeHead(400);res.end();return;}
    req.setTimeout(15000,()=>{if(!res.writableEnded){res.writeHead(408);res.end();}req.destroy();});
    let size=0,chunks=[],rejected=false;
    req.on('data',chunk=>{if(rejected)return;size+=chunk.length;if(size>maxCaptureBytes){rejected=true;chunks=[];res.writeHead(413);res.end();}else chunks.push(chunk);});
    req.on('end',()=>{
      if(rejected)return;const data=Buffer.concat(chunks);
      if(data.length<4||data.readUInt32BE(0)!==0x1a45dfa3){res.writeHead(400);res.end('Expected WebM');return;}
      fs.writeFile(path.join(captureDir,filename),data,{flag:'wx'},error=>{res.writeHead(error?(error.code==='EEXIST'?409:500):201);res.end(error?'Clip not saved':'Saved');});
    });
    req.on('error',()=>{if(!res.writableEnded){res.writeHead(400);res.end();}});return;
  }
  if(!['GET','HEAD'].includes(req.method)){res.writeHead(405);res.end();return;}
  if(name.endsWith('/favicon.ico')){res.writeHead(204);res.end();return;}
  if(name==='/'){res.writeHead(302,{'Location':'/studio/'});res.end();return;}
  const [base,rel]=name.startsWith('/simulator/')?[simulator,name.slice('/simulator'.length)]:[root,name];
  const file=path.resolve(base,'.'+rel+(rel.endsWith('/')?'index.html':''));
  if(!file.startsWith(base+path.sep)){res.writeHead(403);res.end();return;}
  const stat=fs.statSync(file,{throwIfNoEntry:false});
  if(stat?.isDirectory()&&!name.endsWith('/')){res.writeHead(302,{'Location':name+'/'});res.end();return;}
  if(!stat?.isFile()){res.writeHead(404);res.end('Not found');return;}
  // Streamed, and in part when a Range asks: a video seeks by its bytes.
  const part=span(req.headers.range,stat.size);
  if(!part){res.writeHead(416,{'Content-Range':`bytes */${stat.size}`});res.end();return;}
  res.writeHead(part.whole?200:206,{'Content-Type':types[path.extname(file)]||'application/octet-stream','Cache-Control':'no-store','X-Content-Type-Options':'nosniff',
    'Accept-Ranges':'bytes','Content-Length':String(part.end-part.start+1),...(part.whole?{}:{'Content-Range':`bytes ${part.start}-${part.end}/${stat.size}`})});
  if(req.method==='HEAD'||!stat.size){res.end();return;}
  fs.createReadStream(file,{start:part.start,end:part.end}).on('error',()=>res.destroy()).pipe(res);
}).listen(port,'127.0.0.1',()=>console.log('Character Studio: http://127.0.0.1:'+port+'/'));
