#!/usr/bin/env node
// Design JSON is the source. Generated shipping files never import internal code.
import fs from 'node:fs';
import {firmwareCatalog} from './catalog.mjs';
import {artCatalog} from './art.mjs';
import {meshCatalog} from './mesh.mjs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../../..');
const g=JSON.parse(fs.readFileSync(path.join(root,'characters/boop/design/slime-blob/emotion-graph.json')));
if(process.argv.includes('--help')) {console.log('node characters/boop/tools/slimegen/slimegen.mjs [--check]\nGenerate the host graph and native gel catalogs from the slime catalog.');process.exit(0);}
// The host graph goes into Boop's character pack (characters/CHARACTER.md
// §4-5): its `moods`' ids, meanings and families. Other keys, and keys a mood
// has that the design doesn't set (`face`), are kept as they are. A mood's
// `moves` are the pack's own: the design's edges are what the gel draws a
// transition for, and they seed a mood the pack doesn't have yet. The
// design's pixel `fallback` stays in the design: a pack has every mood. Its
// `hostPolicy` and `brief` markers stay in the design too: the pack's pacing
// is its steering's.
const characterPath='characters/boop/character.json';
const character=JSON.parse(fs.readFileSync(path.join(root,characterPath)));
const owned=['id','meaning','family'];
const before=new Map((character.moods||[]).map(m=>[m.id,m]));
character.moods=Object.entries(g.nodes).map(([id,n])=>({id,meaning:n.meaning,family:n.family,moves:{ordinary:n.ordinary,dramatic:n.dramatic},
  ...Object.fromEntries(Object.entries(before.get(id)||{}).filter(([k])=>!owned.includes(k)))}));
const outputs = new Map([[characterPath,JSON.stringify(character,null,2)+'\n'],['characters/boop/firmware/include/slime.h',firmwareCatalog(root)]]);
const design=path.join(root,'characters/boop/design/slime-blob');
const catalog=JSON.parse(fs.readFileSync(path.join(design,'expressions.json')));
outputs.set('characters/boop/firmware/include/slime_art.h',artCatalog(catalog.expressions));
outputs.set('characters/boop/firmware/include/slime_mesh.h',meshCatalog());
for(const [name,content] of outputs) {
  const target=path.join(root,name);
  if(process.argv.includes('--check')) {if(fs.readFileSync(target,'utf8')!==content)throw Error('Stale '+name);}
  else {fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,content);}
}
console.log((process.argv.includes('--check')?'SLIMEGEN PASS: fresh':'Generated')+' host graph and native gel ('+outputs.size+' files)');
