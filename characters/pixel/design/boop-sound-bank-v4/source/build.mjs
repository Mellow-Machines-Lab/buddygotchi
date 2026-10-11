import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {gzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {catalog,moods} from '../runtime/catalog.mjs';
import {moodAdditions,newMoods} from '../runtime/mood-catalog.mjs';
import {stateOrder} from '../runtime/state-catalog.mjs';
import {makeScene} from '../runtime/bank.mjs';
import {voiceWindows} from '../runtime/mood-art.mjs';
if(process.argv.includes('--help')){console.log('Usage: node characters/pixel/design/boop-sound-bank-v4/source/build.mjs [--svg]\nBuilds the portable runtime and manifests (the studio, ../../studio/, plays the runtime). --svg also exports all 795 SVG selections; sound remains code-based. No network or API calls.');process.exit(0);}
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
for(const d of ['dist','qa'])fs.mkdirSync(path.join(root,d),{recursive:true});
const walk=p=>fs.readdirSync(p,{withFileTypes:true}).flatMap(x=>x.isDirectory()?walk(path.join(p,x.name)):[path.join(p,x.name)]);
const paths=walk(path.join(root,'runtime')).filter(p=>p.endsWith('.mjs')).sort();
const modules=paths.map(file=>{
 const id=path.relative(path.join(root,'runtime'),file).split(path.sep).join('/');let code=fs.readFileSync(file,'utf8');
 const exported=[...code.matchAll(/^export (?:async )?(?:function|const|let|class) (\w+)/gm)].map(m=>m[1]);
 code=code.replace(/^export \{([^}]+)\};?\s*$/gm,(_,names)=>{exported.push(...names.split(',').map(s=>s.trim()));return '';});
 code=code.replace(/^import \{([^}]+)\} from ['"]([^'"]+)['"];?\s*$/gm,(_,names,spec)=>{
  const target=path.posix.normalize(path.posix.join(path.posix.dirname(id),spec));
  return `const {${names.replace(/\b(\w+)\s+as\s+(\w+)/g,'$1:$2')}}=load(${JSON.stringify(target)});`;
 }).replace(/^export /gm,'');
 if(/^import |^export /m.test(code))throw new Error('Unhandled module syntax '+id);
 return `${JSON.stringify(id)}:()=>{\n${code}\nreturn {${[...new Set(exported)].join(',')}};}`;
});
const factory=`(()=>{const modules={${modules.join(',\n')}};const cache={};function load(id){if(!cache[id]){if(!modules[id])throw new Error('Missing module '+id);cache[id]=modules[id]();}return cache[id];}return {...load('bank.mjs'),...load('catalog.mjs'),...load('player.mjs'),...load('state-catalog.mjs'),...load('mood-catalog.mjs'),...load('mood-art.mjs'),states:load('state-catalog.mjs').stateOrder};})()`;
const bundle='// Boop V4 procedural SVG + audio. No recordings, network, or API keys.\nglobalThis.Boop='+factory+';\n';
fs.writeFileSync(path.join(root,'dist/boop-runtime.js'),bundle);
let expandedSVGBytes=0;
const assets=catalog.map(a=>{
 const scene=makeScene(a.id);expandedSVGBytes+=Buffer.byteLength(scene.svg);
 if(process.argv.includes('--svg')){
  const dir=path.join(root,'dist/svg');fs.mkdirSync(dir,{recursive:true});fs.writeFileSync(path.join(dir,a.id+'.svg'),scene.svg);
 }
 return {...a,score:scene.score,...(a.renderer==='mood-v4'?{voiceWindow:voiceWindows(a)}:{})};
});
const storage={runtimeSourceBytes:paths.reduce((sum,p)=>sum+fs.statSync(p).size,0),bundleBytes:Buffer.byteLength(bundle),bundleGzipBytes:gzipSync(bundle).length,expandedSVGBytesIfAllExported:expandedSVGBytes,audioAssetBytes:0};
const coverage={moods:moods.length,states:stateOrder.length,pairs:moods.length*stateOrder.length,total:catalog.length,preservedV3:308,newPerformances:moodAdditions.length,newMoods,newPerMood:Object.fromEntries(newMoods.map(m=>[m,moodAdditions.filter(a=>a.mood===m).length])),perPair:Object.fromEntries(moods.map(m=>[m,Object.fromEntries(stateOrder.map(s=>[s,catalog.filter(a=>a.mood===m&&a.state===s).length]))]))};
fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify({revision:4,status:'New moods and variations await visual/auditory user approval; prior V3 performances preserved',scope:'Local code-generated SVG/SFX bank; not app graph integration or ElevenLabs recordings',coverage,storage,assets},null,2)+'\n');
fs.writeFileSync(path.join(root,'storage-report.json'),JSON.stringify(storage,null,2)+'\n');
fs.writeFileSync(path.join(root,'coverage.json'),JSON.stringify(coverage,null,2)+'\n');
fs.writeFileSync(path.join(root,'source-hashes.json'),JSON.stringify(Object.fromEntries(paths.map(p=>[path.relative(root,p),createHash('sha256').update(fs.readFileSync(p)).digest('hex')])),null,2)+'\n');
console.log(JSON.stringify({coverage:{...coverage,perPair:undefined},storage},null,2));
