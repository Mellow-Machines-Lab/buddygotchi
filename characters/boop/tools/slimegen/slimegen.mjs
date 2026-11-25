#!/usr/bin/env node
// Design JSON is the source. Generated shipping files never import internal code.
import fs from 'node:fs';
import {firmwareCatalog} from './catalog.mjs';
import {artCatalog} from './art.mjs';
import {meshCatalog} from './mesh.mjs';
import {checkDesign} from './check.mjs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
// The slime's pack, this script's own.
const pack=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
if(process.argv.includes('--help')) {console.log('node tools/slimegen/slimegen.mjs [--check] (from the pack)\nCheck the slime design, then generate the native gel catalogs from it.');process.exit(0);}
const design=path.join(pack,'design/slime-blob');
const read=name=>JSON.parse(fs.readFileSync(path.join(design,name)));
const catalog=read('expressions.json');
checkDesign({character:JSON.parse(fs.readFileSync(path.join(pack,'character.json'))),design:catalog,sound:read('sound/sound-plan.json'),sfx:createRequire(import.meta.url)(path.join(design,'sound/sfx.js'))});
// The faces and the lasting moods are the pack's (character.json,
// characters/CHARACTER.md §5); the design has each face's art, body and sound.
const character=JSON.parse(fs.readFileSync(path.join(pack,'character.json')));
const outputs = new Map([['firmware/include/slime.h',firmwareCatalog(pack,character)]]);
outputs.set('firmware/include/slime_art.h',artCatalog(catalog.expressions));
outputs.set('firmware/include/slime_mesh.h',meshCatalog());
for(const [name,content] of outputs) {
  const target=path.join(pack,name);
  if(process.argv.includes('--check')) {if(fs.readFileSync(target,'utf8')!==content)throw Error('Stale '+name);}
  else {fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,content);}
}
console.log((process.argv.includes('--check')?'SLIMEGEN PASS: fresh':'Generated')+' native gel ('+outputs.size+' files)');
