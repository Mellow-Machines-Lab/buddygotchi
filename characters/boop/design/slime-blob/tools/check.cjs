const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),vm=require('node:vm'),crypto=require('node:crypto');
if(process.argv.includes('--help')){console.log('node tools/check.cjs\nOffline graph/coverage/export/motion/sound/link checks; no browser or production runtime.');process.exit(0);}
const root=path.resolve(__dirname,'..'),read=name=>JSON.parse(fs.readFileSync(path.join(root,name),'utf8'));
const g=read('emotion-graph.json'),c=read('expressions.json'),s=read('state-plan.json'),cov=read('coverage.json'),trans=read('transitions.json'),sound=read('sound/sound-plan.json');
const review=JSON.parse(require('node:child_process').execFileSync(process.execPath,[path.join(__dirname,'check-scenes.mjs'),'--coverage'],{encoding:'utf8'}));
const exercised=new Set(review.cells);
assert.equal(exercised.size,42*25,'Every cell needs executed reference-scene coverage');
const bridgeReview=JSON.parse(require('node:child_process').execFileSync(process.execPath,[path.join(__dirname,'check-bridges.mjs'),'--coverage'],{encoding:'utf8'}));
const verifiedEdges=new Map(bridgeReview.edges.map(edge=>[edge.id,edge]));
assert.equal(verifiedEdges.size,295,'Every directed edge needs executed bridge coverage');
const ids=Object.keys(g.nodes);
assert.equal(ids.length,42);assert.equal(Object.keys(c.expressions).length,44);assert.equal(c.referenceMapping.length,19);
assert.equal(g.holdAlwaysAvailable,true);assert.equal(g.maxEdgesPerDecision,1);assert.equal(g.maxDestinationChoices,8);
assert.equal(g.implementation.runtimeChanged,true);assert.equal(g.implementation.productionEnumsChanged,true);
assert.deepEqual([...g.schema.stateNames].sort(),s.states.map(v=>v.id).sort());assert.equal(new Set(s.states.map(v=>v.id)).size,25);
assert.equal(g.retainedMoodIds.length,13);
assert.equal(g.deletedMoodIds.length,0);assert.equal(g.newMoodIds.length,29);
assert.deepEqual(Object.keys(sound.moodProfiles).sort(),[...ids].sort());
const expectedEdges=new Map();let ordinary=0,dramatic=0;
for(const [id,n] of Object.entries(g.nodes)){
  assert.ok(g.retainedMoodIds.includes(n.fallback));assert.equal(n.brief,g.pacingDraft.briefNodes.includes(id));
  const destinations=[...n.ordinary,...n.dramatic];assert.equal(new Set(destinations).size,destinations.length);assert.ok(destinations.length<=8);
  for(const category of ['ordinary','dramatic'])for(const to of n[category]){
    assert.ok(ids.includes(to));assert.notEqual(to,id);expectedEdges.set(id+'->'+to,category);category==='ordinary'?ordinary++:dramatic++;
  }
  const reached=new Set([id]),pending=[id];while(pending.length)for(const next of g.nodes[pending.pop()].ordinary)if(!reached.has(next)){reached.add(next);pending.push(next);}
  assert.equal(reached.size,42,'Ordinary graph not strongly connected from '+id);
  assert.equal(c.expressions[id].mood,id);assert.equal(c.expressions[id].performances.length,3);assert.ok(c.expressions[id].art.note.length>10);
  for(const gag of c.expressions[id].gags||[])assert.ok(c.gags[gag],'Unknown gag '+gag+' for '+id);
}
assert.equal(expectedEdges.size,295);assert.equal(trans.edges.length,expectedEdges.size);assert.equal(new Set(trans.edges.map(v=>v.id)).size,295);
for(const e of trans.edges){assert.equal(expectedEdges.get(e.id),e.category);assert.equal(e.variants.length,3);assert.equal(e.status,'implemented');assert.deepEqual(e.variants,verifiedEdges.get(e.id).primitives);}
for(const ladder of Object.values(g.intensityLadders))for(let i=1;i<ladder.length;i++)assert.ok(g.nodes[ladder[i-1]].ordinary.includes(ladder[i]));
assert.equal(cov.cells.length,42*25);assert.equal(new Set(cov.cells.map(v=>v.id)).size,cov.cells.length);
for(const row of cov.cells){
  const state=s.states.find(v=>v.id===row.state);assert.ok(ids.includes(row.mood)&&state);assert.equal(row.id,row.mood+'.'+row.state);
  // Three takes each, but idle's six (its gags), asleep's four (a snore) and
  // a gesture's ten;
  // a successful finish has a fourth, its hiccups.
  assert.equal(row.variations.length,{idle:6,asleep:4,gesture:10}[row.state]??3);assert.deepEqual(row.requiredHostFacts,s.hostFacts[row.state]||{});
  assert.deepEqual(row.factVariations,state.factVariations||{});
  for(const [fact,choices] of Object.entries(row.factVariations))for(const [value,variations] of Object.entries(choices)){
    const takes=fact==='outcome'&&value==='success'?4:3;assert.equal(variations.length,takes);assert.equal(new Set(variations).size,takes);}
  assert.equal(row.status,exercised.has(row.id)?(state.scene==='rest'?'quiet-alias':'implemented'):(state.scene==='rest'?'planned-shared-rest':'planned-state-layer'));assert.equal(row.audioPolicy,state.audioPolicy);
  assert.deepEqual(row.variationAudio,state.variationAudio||{});
  for(const variation of Object.keys(row.variationAudio))assert.ok(state.variations.includes(variation),'Audio for an unknown variation '+variation);
  if(state.scene==='rest'){assert.equal(row.mode,'explicit-quiet-alias');assert.equal(row.audioPolicy,'silent');}
}
const script=fs.readFileSync(path.join(root,'preview/slime.bundle.js'),'utf8');new vm.Script(script);
assert.equal(script,require('./bundle.cjs').bundle(path.join(root,'preview/character.mjs')),'Run tools/build.cjs: stale engine bundle');
assert.ok(!script.includes('window.openai'),'Standalone preview must not depend on conversation host');
const sandbox={window:{}};vm.runInNewContext(fs.readFileSync(path.join(root,'preview/catalog.js'),'utf8'),sandbox);
assert.equal(JSON.stringify(sandbox.window.SlimeCatalog),JSON.stringify({...c,graph:g,sound}),'Run tools/build.cjs: stale preview catalogue');
vm.runInNewContext(fs.readFileSync(path.join(root,'preview/script-catalog.js'),'utf8'),sandbox);
assert.equal(JSON.stringify(sandbox.window.SlimeReview),JSON.stringify(review),'Run tools/build.cjs: stale review manifest');
assert.equal(JSON.stringify(sandbox.window.SlimeBridgeReview),JSON.stringify(bridgeReview),'Run tools/build.cjs: stale bridge review manifest');
assert.deepEqual(read('preview/review-cases.json'),{cases:[...review.cases,...bridgeReview.cases]},'Run tools/build.cjs: stale capture case allowlist');
const scripts=Object.fromEntries(fs.readdirSync(path.join(root,'scripts')).filter(file=>file.endsWith('.jsonl')).sort().map(file=>[file,fs.readFileSync(path.join(root,'scripts',file),'utf8').trim().split(/\r?\n/).filter(Boolean).map(line=>JSON.parse(line))]));
assert.equal(JSON.stringify(sandbox.window.SlimeScripts),JSON.stringify(scripts),'Run tools/build.cjs: stale event scripts');
const shader=fs.readFileSync(path.join(root,'render/webgl.mjs'),'utf8').match(/const fs=`([\s\S]*?)`;/)[1];
const provenance=read('contracts/source-provenance.json');assert.equal(crypto.createHash('sha256').update(shader).digest('hex'),provenance.materialFragmentSha256,'Export changed original gel material');
require('./check-motion.cjs');
require('node:child_process').execFileSync(process.execPath,[path.join(__dirname,'check-engine.mjs')],{stdio:'inherit'});
require('node:child_process').execFileSync(process.execPath,[path.join(__dirname,'check-scenes.mjs')],{stdio:'inherit'});
require('node:child_process').execFileSync(process.execPath,[path.join(__dirname,'check-bridges.mjs')],{stdio:'inherit'});
require('node:child_process').execFileSync(process.execPath,[path.join(__dirname,'check-cues.mjs')],{stdio:'inherit'});
const fx=require('../sound/sfx.js');let soundRenders=0,maxPeak=0;
for(const name of Object.keys(fx.recipes))for(const variant of [0,1,2]){
  const a=fx.render(name,{variant,seed:53}),b=fx.render(name,{variant,seed:53});assert.deepEqual(a.data,b.data,'Seed must replay');
  assert.ok(a.duration>0&&a.duration<=3);assert.ok(a.data.length>100);assert.ok(a.data[0]===0);
  assert.ok(a.data.every(Number.isFinite));const peak=a.data.reduce((m,n)=>Math.max(m,Math.abs(n)),0);assert.ok(peak>0&&peak<=.8);maxPeak=Math.max(maxPeak,peak);soundRenders++;
  assert.ok(fx.render(name,{gain:0}).data.every(v=>v===0),'Mute must be silence');
}
assert.throws(()=>fx.render('not-a-recipe'),RangeError);
const walk=dir=>fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):[path.join(dir,e.name)]);
for(const file of walk(root)){
  const text=fs.readFileSync(file,'utf8');assert.ok(!text.includes('/Users/'+'work/')&&!text.includes('/var/'+'folders/'),'Workstation path leaked: '+file);
  if(file.endsWith('.md'))for(const match of text.matchAll(/\]\(([^)]+)\)/g)){
    const href=match[1];if(/^(https?:|mailto:|#)/.test(href))continue;
    const target=path.resolve(path.dirname(file),decodeURIComponent(href.split('#')[0]));assert.ok(fs.existsSync(target),'Broken link '+href+' in '+file);
  }
}
console.log(JSON.stringify({status:'OFFLINE PACKAGE PASS',moods:42,expressions:44,states:25,cells:cov.cells.length,edges:expectedEdges.size,ordinary,dramatic,soundRenders,maxPeak,links:'pass'}));
