// Loopback-only server for the studio. Writing is opt-in and limited to the
// clip names the packs' studio entries allow (`captures`, a JSON file of
// {cases:[{id}]}): each becomes <id>.webm.
const http=require('node:http'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
if(process.argv.includes('--help')){console.log('node characters/studio/serve.cjs [--port 4190] [--capture-dir DIR]\nServes characters/ on 127.0.0.1; / opens the studio.\n--capture-dir lets the packs\' tools save their named review clips there; never overwrites.');process.exit(0);}
const args=process.argv.slice(2);
for(let i=0;i<args.length;i+=2)if(!['--port','--capture-dir'].includes(args[i])||!args[i+1]||args[i+1].startsWith('--')||args.indexOf(args[i])!==i)throw Error('Use --help for arguments.');
const port=args.includes('--port')?Number(args[args.indexOf('--port')+1]):4190;
if(!Number.isInteger(port)||port<1024||port>65535)throw Error('Port must be an integer between 1024 and 65535.');
const root=path.resolve(__dirname,'..');
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
const types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json; charset=utf-8','.md':'text/plain; charset=utf-8','.svg':'image/svg+xml','.png':'image/png'};
http.createServer((req,res)=>{
  let name;
  try{name=decodeURIComponent(new URL(req.url,'http://localhost').pathname);}catch{res.writeHead(400);res.end();return;}
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
  const file=path.resolve(root,'.'+name+(name.endsWith('/')?'index.html':''));
  if(!file.startsWith(root+path.sep)){res.writeHead(403);res.end();return;}
  if(!name.endsWith('/')&&fs.statSync(file,{throwIfNoEntry:false})?.isDirectory()){res.writeHead(302,{'Location':name+'/'});res.end();return;}
  fs.readFile(file,(error,data)=>{
    if(error){res.writeHead(404);res.end('Not found');return;}
    res.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
    res.end(req.method==='HEAD'?undefined:data);
  });
}).listen(port,'127.0.0.1',()=>console.log('Character Studio: http://127.0.0.1:'+port+'/'));
