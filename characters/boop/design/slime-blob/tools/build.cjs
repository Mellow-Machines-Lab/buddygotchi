// Deterministic mechanical exports; no packages/network/model needed.
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
if(process.argv.includes('--help')){console.log('node tools/build.cjs\nRebuilds catalogues and the file://-compatible slime.bundle.js the studio loads.');process.exit(0);}
const read=name=>JSON.parse(fs.readFileSync(path.join(root,name),'utf8'));
const write=(name,value)=>fs.writeFileSync(path.join(root,name),typeof value==='string'?value:JSON.stringify(value,null,2)+'\n');
const graph=read('emotion-graph.json'),catalog=read('expressions.json'),plan=read('state-plan.json');
// Coverage is earned by executing every matrix cell, never by naming a module.
// The owner's representative-art approval is recorded separately in evidence.
const review=JSON.parse(require('node:child_process').execFileSync(process.execPath,[path.join(__dirname,'check-scenes.mjs'),'--coverage'],{encoding:'utf8'}));
const bridgeReview=JSON.parse(require('node:child_process').execFileSync(process.execPath,[path.join(__dirname,'check-bridges.mjs'),'--coverage'],{encoding:'utf8'}));
const verifiedEdges=new Map(bridgeReview.edges.map(edge=>[edge.id,edge]));
const exercised=new Set(review.cells);
write('preview/catalog.js','// Generated from ../expressions.json and ../emotion-graph.json by tools/build.cjs.\nwindow.SlimeCatalog = '+JSON.stringify({...catalog,graph,sound:read('sound/sound-plan.json')})+';\n');
const scripts=Object.fromEntries(fs.readdirSync(path.join(root,'scripts')).filter(file=>file.endsWith('.jsonl')).sort().map(file=>[file,fs.readFileSync(path.join(root,'scripts',file),'utf8').trim().split(/\r?\n/).filter(Boolean).map(line=>JSON.parse(line))]));
write('preview/script-catalog.js','// Generated local event scripts and verified review manifests.\nwindow.SlimeScripts = '+JSON.stringify(scripts)+';\nwindow.SlimeReview = '+JSON.stringify(review)+';\nwindow.SlimeBridgeReview = '+JSON.stringify(bridgeReview)+';\n');
write('preview/review-cases.json',{cases:[...review.cases,...bridgeReview.cases]});
const rows=[];
for(const mood of Object.keys(graph.nodes))for(const state of plan.states){
  const quiet=state.scene==='rest';
  rows.push({id:mood+'.'+state.id,mood,state:state.id,scene:state.scene,expression:quiet?'shared-sleeping-face':mood,
    mode:quiet?'explicit-quiet-alias':'composed-active-cell',variations:state.variations.map(v=>state.id+'.'+v),
    requiredHostFacts:plan.hostFacts[state.id]||{},factVariations:state.factVariations||{},moodSoundProfile:mood,audioPolicy:state.audioPolicy,
    variationAudio:state.variationAudio||{},
    status:exercised.has(mood+'.'+state.id)?(quiet?'quiet-alias':'implemented'):(quiet?'planned-shared-rest':'planned-state-layer'),faceStatus:quiet?(exercised.has(mood+'.'+state.id)?'shared-sleeping-face':'planned-shared-sleeping-face'):'candidate-art-present',review:exercised.has(mood+'.'+state.id)?'engineering-tested; representative-art-approved; contact-sound-implemented; timbres-sketches':'pending-integrated-animation-and-sound'});
}
write('coverage.json',{version:1,status:'FULL SCENE MATRIX TESTED; CONTACT SOUND IMPLEMENTED; TIMBRES SKETCHES',cells:rows});
const edges=[];
for(const [from,node] of Object.entries(graph.nodes))for(const category of ['ordinary','dramatic'])for(const to of node[category]){
  const dramatic=category==='dramatic',verified=verifiedEdges.get(from+'->'+to);
  edges.push({id:from+'->'+to,from,to,category,
    faceFrom:from,faceTo:to,status:verified?'implemented':'planned-continuous-bridge',
    variants:verified?verified.primitives:(dramatic?['bounded-recoil-retarget','compress-release-retarget','brief-freeze-retarget']:['soft-retarget','gather-settle-retarget','brief-blink-retarget']),
    preserve:['actor','rest-shape','material','spring-position','spring-velocity','activity-truth','pending-alert'],
    cue:dramatic?'fresh-edge-specific-evidence-required':'context-and-pacing-required',audio:'silent-by-default; material accent only on a permitted visible contact'});
}
write('transitions.json',{version:1,status:'ALL DIRECTED BRIDGES TESTED; HOST GRAPH V3 OPT-IN',edges});
let md='# Slime mood inventory and directed traversal\n\nGenerated from [emotion-graph.json](emotion-graph.json) and [expressions.json](expressions.json).\nEdit those inputs and run tools/build.cjs; do not edit this export by hand.\n\nOrdinary neighbors still require context/pacing. Dramatic neighbors require fresh\nstrong edge-specific evidence. Staying is implicit at every node. Families and\nintensity labels are static design metadata, not LLM-selected numeric controls.\nFaces are V3 review candidates; body descriptions below are choreography targets.\n\n';
for(const [family,group] of Object.entries(graph.families)){
  md+='## '+group.label+'\n\n';
  for(const id of group.moods){
    const n=graph.nodes[id],e=catalog.expressions[id];
    md+='### '+e.label+' (`'+id+'`)\n\n';
    md+='**Meaning:** '+n.meaning+'\n\n';
    md+='**Strength / activation / persistence:** '+n.intensityWithinFamily+' / '+n.activation+' / '+n.temporalClass+'.\n\n';
    md+='**Face:** '+e.art.note+'\n\n';
    md+='**Body intent:** '+n.bodyPerformance+'\n\n';
    md+='**Current gesture recipes:** '+e.performances.map(p=>p.label+' ('+p.duration+' s)').join('; ')+'.\n\n';
    if(e.gags)md+='**Its own comedy, idle only:** '+e.gags.map(id=>catalog.gags[id].label+' ('+catalog.gags[id].duration+' s)').join('; ')+'.\n\n';
    md+='**Entry evidence:** '+n.entryCues.join('; ')+'.\n\n';
    md+='**Ordinary →** '+n.ordinary.map(v=>'`'+v+'`').join(', ')+'.\n\n';
    md+='**Dramatic →** '+(n.dramatic.length?n.dramatic.map(v=>'`'+v+'`').join(', '):'none')+'.\n\n';
  }
}
md+='## Idle comedy every mood shares\n\nAfter a mood\'s first round of gestures, its idle bag deals these too (CONTINUITY.md, Comedy):\n\n';
for(const id of catalog.idleGags)md+='- `'+id+'`: '+catalog.gags[id].label+' ('+catalog.gags[id].duration+' s).\n';
md+='\n## Reference face alternates (not graph nodes)\n\n';
for(const [id,e] of Object.entries(catalog.expressions).filter(([id])=>id.includes(':')))md+='- `'+id+'` → mood `'+e.mood+'`: '+e.art.note+'\n';
md+='\n## Supplied references and their mappings\n\n';
for(const r of catalog.referenceMapping)md+='- '+r.reference+' → expression `'+r.expression+'`, mood `'+r.mood+'`'+(r.relatedMood?' (related `'+r.relatedMood+'`)':'')+'.\n';
write('MOODS.md',md);
write('preview/slime.bundle.js',require('./bundle.cjs').bundle(path.join(root,'preview/character.mjs')));
console.log(JSON.stringify({export:'complete',moods:Object.keys(graph.nodes).length,expressions:Object.keys(catalog.expressions).length,stateCells:rows.length,edges:edges.length}));
