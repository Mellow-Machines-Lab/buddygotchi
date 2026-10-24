import {palette as P,rect,at} from './visual/base.mjs';
import {newMoods} from './mood-catalog.mjs';
import {round} from './mood-art.mjs';
import {oldMoods,ownFace} from './wake-art.mjs';

// What the variations drawn on top of the bank share (comedy-art,
// occasion-art, gesture-art): every mood, a design's entry, its steps, the
// mood's resting face, and a few small props.

export const moods=[...oldMoods,...newMoods];
// A design's entry, for `renderer`: `mood.state.NN`, at its seconds.
export const design=renderer=>(mood,state,variation,action,name,caption,seconds,extra={})=>({
 id:`${mood}.${state}.${String(variation).padStart(2,'0')}`,mood,state,variation,action,name,caption,
 seconds:Number(seconds.toFixed(3)),renderer,approval:'Review candidate',...extra
});
// Each step is one pose and the cue that goes with it, if any:
// [when (of the loop), pose, cue, cue's gain].
export function steps(a,list){
 return list.map(([u,pose,effect=null,gain=0])=>({at:round(u*a.seconds),pose,effect,gain}));
}
// The mood's resting face, moved by dx, dy.
export const own=(dx=0,dy=0)=>a=>at(dx,dy,ownFace(a.mood,false));
export const heart=(x,y,c=P.red)=>rect(x,y,6,6,c)+rect(x+10,y,6,6,c)+rect(x-2,y+4,20,6,c)+rect(x,y+10,16,4,c)+rect(x+4,y+14,8,4,c);
// An exclamation mark.
export const bang=(x,y,c=P.amber)=>rect(x,y,6,16,c)+rect(x,y+20,6,6,c);
