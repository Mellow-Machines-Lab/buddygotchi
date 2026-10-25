// What the design's data must be before slimegen bakes it: a bad edit fails
// here, naming what's wrong, rather than baking a slime that can't move or
// sound as it should. The board's behaviour is pinned by its own tests
// (test_gel); these are the inputs' own rules.
import {states} from './scenes.mjs';

const fail=(what)=>{throw Error('slimegen: '+what);};

// The mood graph: every edge goes to another mood, once, at most eight from
// any mood; the ordinary edges alone reach every mood from every other; and
// each intensity ladder climbs by ordinary edges.
function graphRules(graph) {
  const ids=Object.keys(graph.nodes);
  for(const [id,n] of Object.entries(graph.nodes)){
    const to=[...n.ordinary,...n.dramatic];
    for(const next of to)if(!ids.includes(next)||next===id)fail(`${id} → ${next} isn't an edge to another mood`);
    if(new Set(to).size!==to.length)fail(`${id} names an edge twice`);
    if(to.length>8)fail(`${id} has ${to.length} edges, more than eight`);
    const reached=new Set([id]),pending=[id];
    while(pending.length)for(const next of graph.nodes[pending.pop()].ordinary)if(!reached.has(next))reached.add(next),pending.push(next);
    if(reached.size!==ids.length)fail(`the ordinary edges from ${id} reach ${reached.size} of ${ids.length} moods`);
  }
  for(const [name,ladder] of Object.entries(graph.intensityLadders))
    for(let i=1;i<ladder.length;i++)if(!graph.nodes[ladder[i-1]].ordinary.includes(ladder[i]))fail(`the ${name} ladder's ${ladder[i-1]} → ${ladder[i]} isn't an ordinary edge`);
}

// The expressions: one for each mood, of that mood, with its three
// gestures, its sound's pitch and gain, and only gags that exist; and the
// notice takes' faces, each an expression.
function expressionRules(graph,design,sound) {
  for(const id of Object.keys(graph.nodes)){
    const e=design.expressions[id];
    if(!e||e.mood!==id)fail(`${id} has no expression of its own`);
    if(!sound.moodProfiles[id])fail(`${id} has no sound profile`);
  }
  for(const [id,e] of Object.entries(design.expressions)){
    if(e.performances.length!==3)fail(`${id} has ${e.performances.length} gestures, not three`);
    for(const gag of e.gags||[])if(!design.gags[gag])fail(`${id} names no gag ${gag}`);
  }
  for(const gag of design.idleGags)if(!design.gags[gag])fail(`idle names no gag ${gag}`);
  for(const n of design.notices)if(!design.expressions[n.face])fail(`${n.id} borrows no expression ${n.face}`);
}

// The occasions: each its own id, needing a tag or a wait, on looks the
// board has; a gag of its own, another occasion's or a recipe's, and a
// recipe only for looks other than idle.
function occasionRules(design) {
  const ids=design.occasions.map(o=>o.id);
  if(new Set(ids).size!==ids.length)fail('two occasions share an id');
  for(const o of design.occasions){
    if(!o.when.length&&!o.after)fail(`${o.id} needs neither a tag nor a wait`);
    for(const look of o.looks)if(!states.includes(look))fail(`${o.id} plays in ${look}, which isn't a state`);
    if(typeof o.gag==='string'&&!design.occasions.some(other=>other.id===o.gag&&typeof other.gag==='object'))fail(`${o.id} borrows no gag ${o.gag}`);
    if(!o.gag&&!o.recipe)fail(`${o.id} has neither a gag nor a recipe`);
    if(o.recipe&&o.looks.includes('idle'))fail(`${o.id} gives idle a recipe: idle's occasions are gags`);
  }
}

// The sound sketches the board's effects are cut from: each the same from
// the same seed, starting from silence, finite, never louder than .8, at
// most 3 s, and silent at no gain.
function soundRules(sfx) {
  for(const name of Object.keys(sfx.recipes))for(const variant of [0,1,2]){
    const a=sfx.render(name,{variant,seed:53}),b=sfx.render(name,{variant,seed:53});
    if(a.data.some((v,i)=>v!==b.data[i]))fail(`${name} ${variant} renders differently from one seed`);
    const peak=a.data.reduce((m,v)=>Math.max(m,Math.abs(v)),0);
    if(a.data[0]!==0||!a.data.every(Number.isFinite)||!(peak>0&&peak<=.8)||!(a.duration>0&&a.duration<=3))fail(`${name} ${variant} isn't a clean sketch`);
    if(!sfx.render(name,{variant,gain:0}).data.every(v=>v===0))fail(`${name} isn't silent at no gain`);
  }
}

export function checkDesign({graph,design,sound,sfx}) {
  graphRules(graph);
  expressionRules(graph,design,sound);
  occasionRules(design);
  soundRules(sfx);
}
