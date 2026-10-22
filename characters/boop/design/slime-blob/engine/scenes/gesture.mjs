// The board's own reaction to what you do to it (CONTINUITY.md, Gestures):
// one take for each gesture, in the board's order (render::Gesture). Each is
// a short scene whose contacts dent the body and sound, and a gag the acting
// layer plays with it (gesture:<id>), under a face the board borrows for it.
export const gestureNames=Object.freeze(['handoff','stroke','ruffle','nose','tickle','dizzy','pickup','putdown','startle','peekaboo']);
// The scene outlasts its gag a little, so the body settles before it ends.
export const gestureTailMs=200;
export const gestureGagName=gesture=>'gesture:'+gesture.id;
export function gestureRecipe(gestures,variant) {
  const gesture=gestures[variant]||gestures[0];
  return {duration:Math.round(gesture.duration*1000)+gestureTailMs,intent:gesture.label,lean:0,
    contacts:gesture.contacts.map(([at,kind,strength,side])=>({at:Math.round(at*1000),kind,side,strength})),
    gag:gestureGagName(gesture)};
}
// A gesture's gag: its keys and impulses; its sounds are the scene's.
export function gestureGag(gesture) {
  return {label:gesture.label,duration:gesture.duration,keys:gesture.keys,cues:gesture.cues,contacts:[]};
}
