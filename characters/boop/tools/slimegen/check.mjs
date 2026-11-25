// What the design's data must be before slimegen bakes it: a bad edit fails
import {sceneMoodTraits} from './scenes.mjs';
// here, naming what's wrong, rather than baking a slime that can't move or
// sound as it should. The board's behaviour is pinned by its own tests
// (test_gel); these are the inputs' own rules.

const fail=(what)=>{throw Error('slimegen: '+what);};

// The expressions: one for each face the pack names (character.json's
// `moods`, then its `board_faces`), of that face, before any alternate; each
// with its sound's pitch and gain, its scenes' traits unless it's a
// reviewed mood's (scenes.mjs sceneMoodTraits), and only gags that exist. Every lasting mood rests in faces that exist; and the gestures' and
// the notice takes' faces are each an expression.
function expressionRules(character,design,sound) {
  const ids=[...character.moods,...(character.board_faces||[])].map(m=>m.id);
  if(JSON.stringify(Object.keys(design.expressions).slice(0,ids.length).sort())!==JSON.stringify([...ids].sort()))fail('the first expressions aren\'t the pack\'s faces');
  for(const id of ids){
    if(design.expressions[id].mood!==id)fail(`${id} has no expression of its own`);
    if(!sound.moodProfiles[id])fail(`${id} has no sound profile`);
  }
  for(const m of character.lasting)for(const face of m.levels||[m.id])if(!ids.includes(face))fail(`${m.id} rests in no face ${face}`);
  for(const [id,e] of Object.entries(design.expressions)){
    if(!ids.includes(e.mood))fail(`${id} is of no face ${e.mood}`);
    if(!sceneMoodTraits[e.mood]&&!['delayMs','spacing','gain','lean'].every(k=>typeof e.traits?.[k]==='number'))fail(`${id} has no traits`);
    for(const gag of e.gags||[])if(!design.gags[gag])fail(`${id} names no gag ${gag}`);
  }
  for(const n of [...design.notices,...design.gestures])if(!design.expressions[n.face])fail(`${n.id} borrows no expression ${n.face}`);
}

// The pastimes' bodies: each its own id, and a gag or a recipe.
function pastimeRules(design) {
  const ids=design.pastimes.map(o=>o.id);
  if(new Set(ids).size!==ids.length)fail('two pastimes share an id');
  for(const o of design.pastimes){
    if(o.gag&&typeof o.gag!=='object')fail(`${o.id}'s gag isn't one of its own`);
    if(!o.gag&&!o.recipe)fail(`${o.id} has neither a gag nor a recipe`);
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

export function checkDesign({character,design,sound,sfx}) {
  expressionRules(character,design,sound);
  pastimeRules(design);
  soundRules(sfx);
}
