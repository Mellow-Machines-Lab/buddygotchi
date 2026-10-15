#!/usr/bin/env node
// internal/VERIFICATION.md §2: mirror interruption preserves the persistent springs;
// hidden popovers discard transients instead of replaying old reactions.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {createSlime} from '../../design/slime-blob/engine/index.mjs';
import {sceneScale} from '../../design/slime-blob/render/webgl.mjs';
if(process.argv.includes('--help')) { console.log('Usage: node characters/boop/tools/slimegen/check-mirror.mjs\nCheck mirror interruption, persistent body state, and offline silent resources.');process.exit(0); }
const base=new URL('../../design/slime-blob/',import.meta.url);
const read=file=>JSON.parse(fs.readFileSync(new URL(file,base)));
const catalog={...read('expressions.json'),graph:read('emotion-graph.json')};
for(const moment of [{name:'task_complete',args:{mood:'excited',outcome:'success',loops:4}},
                    {name:'react',args:{mood:'sad',loops:4}},{name:'listening'}]) {
  const engine=createSlime({catalog,seed:53});engine.setFacts({base:'working',act:'terminal'});engine.setMood('grumpy');
  engine.step(0);engine.oneShot({id:1,...moment});
  for(let t=16;t<=640;t+=16)engine.step(t);
  const before=engine.inspect();engine.clearTransient();const after=engine.inspect();
  assert.ok(before.modes?.lean);assert.deepEqual(after.modes,before.modes);assert.deepEqual(after.grab.pull,before.grab.pull);assert.equal(after.scene.state,'terminal');assert.equal(after.mood,'grumpy');
  engine.setFacts({base:'working',attn:{id:7,agent:'codex',project:'Boop'}});engine.clearTransient();
  assert.equal(engine.inspect().scene.state,'needs_you');
}
const html=fs.readFileSync(new URL('./mirror.html',import.meta.url),'utf8');
assert.ok(html.includes("connect-src 'none'"));assert.ok(html.includes("media-src 'none'"));
const js=fs.readFileSync(new URL('./mirror.mjs',import.meta.url),'utf8');
assert.ok(!/AudioContext|createPlayer|postMessage|fetch\(/.test(js));

// The shipped mirror draws nothing while the popover is
// closed, draws at once when it opens, and draws at most 60 frames a second.
// No DOM here, so the page runs on stubs and the Canvas fallback.
const anything=new Proxy(function(){},{get:(_,key)=>key===Symbol.toPrimitive?()=>0:anything,set:()=>true,apply:()=>anything});
const element=()=>({width:0,height:0,style:{},dataset:{},getContext:type=>type==='2d'?anything:null,
  setAttribute(){},getAttribute:()=>'',replaceWith(){},append(){},getBoundingClientRect:()=>({width:46,height:46})});
let callbacks=[];
const page={document:{hidden:false,documentElement:{dataset:{}},getElementById:element,createElement:element},
  devicePixelRatio:2,ResizeObserver:class{observe(){}},requestAnimationFrame:callback=>callbacks.push(callback)};
page.window=page;vm.createContext(page);
vm.runInContext(fs.readFileSync(new URL('../../mac/mirror/slime.js',import.meta.url),'utf8'),page);
// Each refresh runs one second of display refreshes at hz.
let clock=0;
const slime=page.BoopSlime,refresh=hz=>{for(let i=1;i<=hz;i++){const due=callbacks;callbacks=[];for(const callback of due)callback(clock+i*1000/hz);}clock+=1000;};
assert.equal(page.document.documentElement.dataset.ready,'true');
for(const message of [{kind:'state',value:{base:'working',act:'terminal',mood:'happy'}},{kind:'moment',value:{id:1,name:'react',args:{mood:'sad'}}},
                      {kind:'listening',value:true},{kind:'reduced',value:false},{kind:'visibility',value:false}])slime.feed(message);
refresh(120);assert.equal(slime.frames,0,'A closed popover must not draw');
slime.feed({kind:'visibility',value:true});assert.equal(slime.frames,1,'Opening draws at once');
refresh(120);const promotion=slime.frames-1;assert.ok(promotion>=59&&promotion<=60,'120 Hz drew '+promotion+' frames in a second');
refresh(60);const standard=slime.frames-1-promotion;assert.ok(standard>=59&&standard<=60,'60 Hz drew '+standard+' frames in a second');
const before=slime.frames;slime.feed({kind:'visibility',value:false});slime.feed({kind:'state',value:{base:'idle',mood:'calm'}});refresh(120);
assert.equal(slime.frames,before,'Closing stops drawing');
// Supersampling. The popover's 46-pt face (92 px) gets
// 4× up to a 1024² scene, a 640×480-pt snapshot 2× up to 4096×2048 pixels.
assert.equal(sceneScale(92,92,16384),4);assert.equal(sceneScale(256,256,16384),4);assert.equal(sceneScale(257,256,16384),2);
assert.equal(sceneScale(1280,960,16384),2);assert.equal(sceneScale(2048,1024,16384),2);assert.equal(sceneScale(2049,1024,16384),1);
assert.equal(sceneScale(92,92,300),2,'4× must fit the GPU');assert.equal(sceneScale(92,92,150),1);
console.log('MAC MIRROR PASS: transient clearing, preserved springs/attention, offline silent resource policy, no drawing while closed, 60 Hz cap, supersampling tiers');
