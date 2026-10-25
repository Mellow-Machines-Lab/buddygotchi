// MOODS.md, the design's moods to read: each family's moods, with their
// meanings, faces, bodies, gestures, comedy and edges, from the graph and
// the expressions.
export function moodsDocument(graph,catalog) {
  let md='# Slime mood inventory and directed traversal\n\nGenerated from [emotion-graph.json](emotion-graph.json) and [expressions.json](expressions.json)\nby `node characters/boop/tools/slimegen/slimegen.mjs`; edit those, not this.\n\nOrdinary neighbors still require context/pacing. Dramatic neighbors require fresh\nstrong edge-specific evidence. Staying is implicit at every node. Families and\nintensity labels are static design metadata, not LLM-selected numeric controls.\nFaces are V3 review candidates; body descriptions below are choreography targets.\n\n';
  for(const group of Object.values(graph.families)){
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
  return md;
}
