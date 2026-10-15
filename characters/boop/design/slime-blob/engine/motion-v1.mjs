// Accepted V1 source is kept byte-for-byte between the markers. Dependencies
// formerly supplied by the preview closure are injected into this pure actor.
export const deformationGLSL = `
  // BOOP_MOTION_V1_BEGIN deformation
  vec3 shape(vec2 uv){
        float t=uv.x, p=uv.y;
        float sy=sin(t), cy=cos(t);
        float raw=.56+.91*cy;
        float y=.5*(raw+sqrt(raw*raw+.0032))+.019;
        float sx=1.0/sqrt(max(.76,1.0+uModes.y*.52));
        float radius=sy*(1.10-.07*cy);
        float x=radius*cos(p),z=radius*.77*sin(p);
        float h=y/1.49;
        float organic=.015*sin(p*3.0+cy*2.0)*sy;
        x*=1.0+organic;
        float ripple=uModes.z*.055*sy*sin(p*3.0+t*2.5);
        x=(x+ripple*cos(p))*sx;
        z=(z+ripple*sin(p))*sx;
        y*=1.0+uModes.y*.52;
        x+=uModes.x*.34*h*h;
        z+=uModes.x*.09*h;
        float front=smoothstep(.35,.9,sin(p));
        vec2 samplePoint=vec2(sy*cos(p),cy);
        vec2 distanceToContact=(samplePoint-uContact)*vec2(3.9,3.1);
        float dent=exp(-dot(distanceToContact,distanceToContact));
        z-=uModes.w*.12*dent*front;
        x+=uModes.w*.025*x*front;
        return vec3(x,y,z);
      }
  // BOOP_MOTION_V1_END deformation
`;

export function createMotionV1({rand, reduced, emotions, initialEmotion, onAdvance=()=>{}, onDraw=()=>{}}) {
  // BOOP_MOTION_V1_BEGIN configuration
  const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));
  const spring = (frequency, damping) => ({x:0, v:0, frequency, damping});
  const modes = {lean:spring(11,4.6), squash:spring(13,4.5), ripple:spring(18,5.3), dent:spring(16,6.0)};
  // BOOP_MOTION_V1_END configuration
  let emotion=initialEmotion;
  const weights=new Float32Array(emotions.length);
  weights[emotions.indexOf(emotion)]=1;
  let time=0,lastTime=0,contact={x:0,y:.20};
  let nextBlink=2.8,blinkAt=-10,gaze=0,gazeTarget=0,nextLook=4.5;
  let frames=0,hidden=false,paused=false;
  function advance(dt) {
    time+=dt;
  // BOOP_MOTION_V1_BEGIN integration
  for(const m of Object.values(modes)){
      let left = dt;
      while(left>0){const h=Math.min(left,1/240);m.v+=(-m.frequency*m.frequency*m.x-m.damping*m.v)*h;m.x+=m.v*h;left-=h;}
      m.x=clamp(m.x,-.72,.72);m.v=clamp(m.v,-9,9);
    }
  // BOOP_MOTION_V1_END integration
  // BOOP_MOTION_V1_BEGIN face-timing
  if(time>nextBlink){blinkAt=time;nextBlink=time+3+rand()*4;}
    if(time>nextLook){gazeTarget=(rand()-.5)*.028;nextLook=time+3.2+rand()*4;}
    gaze+=(gazeTarget-gaze)*(1-Math.exp(-dt*3));
    const smoothing=1-Math.exp(-dt*(reduced.matches?35:14));
    for(let i=0;i<weights.length;i++)weights[i]+=(Number(emotions[i]===emotion)-weights[i])*smoothing;
  // BOOP_MOTION_V1_END face-timing
    onAdvance(dt);
  }
  // BOOP_MOTION_V1_BEGIN idle-pose
  function blink(){
    const age=time-blinkAt;
    return age>=0&&age<.24 ? Math.pow(Math.sin(Math.PI*age/.24),2) : 0;
  }
  function pose(){
    const breathe=reduced.matches?0:Math.sin(time*1.65)*.011;
    return [modes.lean.x, modes.squash.x+breathe, modes.ripple.x, modes.dent.x];
  }
  // BOOP_MOTION_V1_END idle-pose
  function impulse(kind,x=0,y=.2) {
  // BOOP_MOTION_V1_BEGIN excitation
  contact={x:clamp(x,-.85,.85),y:clamp(y,-.25,.65)};
    const strength=reduced.matches?.25:1;
    modes.lean.v=clamp(modes.lean.v+(kind==='shake'?4.5:(x>=0?-2.6:2.6))*strength,-8,8);
    modes.squash.v=clamp(modes.squash.v-(kind==='shake'?2.6:3.5)*strength,-8,8);
    modes.ripple.v=clamp(modes.ripple.v+(kind==='shake'?5:3.5)*strength,-8,8);
    modes.dent.v=clamp(modes.dent.v+(kind==='shake'?0:4.8)*strength,-8,8);
  // BOOP_MOTION_V1_END excitation
  }
  const draw=()=>onDraw();
  function frame(stamp) {
  // BOOP_MOTION_V1_BEGIN frame-step
  const dt=lastTime?clamp((stamp-lastTime)/1000,0,.045):0;lastTime=stamp;
    if(!hidden&&!paused){advance(dt);draw();frames++;}
  // BOOP_MOTION_V1_END frame-step
  }
  return {
    frame,pose,blink,impulse,
    setEmotion(value) { emotion=value; },
    setPaused(value) { paused=Boolean(value); },
    setHidden(value) { hidden=Boolean(value); },
    get time() { return time; },
    get gaze() { return gaze; },
    get weights() { return weights; },
    inspect() {
      return {time,frames,gaze,blink:blink(),contact:{...contact},weights:Array.from(weights),
        modes:Object.fromEntries(Object.entries(modes).map(([name,m])=>[name,{x:m.x,v:m.v}]))};
    }
  };
}
