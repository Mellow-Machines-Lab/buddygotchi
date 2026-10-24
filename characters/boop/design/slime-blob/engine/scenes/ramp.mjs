// CONTINUITY.md, Representative activity scenes: a prop's visibility ramp.
// A cubic Hermite from the current value and slope to the target over a fixed
// window: from rest it is a smoothstep; a reversal keeps the current slope,
// so it is continuous in value and velocity. The end is exact. Held within
// [0, 1], it's flat where it's held: the cubic's own slope there would bring
// back, at a retarget, what it held at zero (a faded art, at about 3%).
export function hermite({from,tangent,to},s) {
  if(s>=1)return {value:to,slope:0};
  const s2=s*s,s3=s2*s;
  const value=(2*s3-3*s2+1)*from+(s3-2*s2+s)*tangent+(3*s2-2*s3)*to;
  const slope=(6*s2-6*s)*from+(3*s2-4*s+1)*tangent+(6*s-6*s2)*to;
  return value<0||value>1?{value:Math.min(1,Math.max(0,value)),slope:0}:{value,slope};
}
export function createRamp(durationMs) {
  let from=0,to=0,tangent=0,start=0,windowMs=durationMs,active=false;
  const state=time=>active?hermite({from,tangent,to},(time-start)/windowMs):{value:to,slope:0};
  return {
    value:time=>state(time).value,
    // Only when nothing it scales is drawn: starts the next fade-in from zero.
    reset() {from=to=tangent=0;active=false;},
    // Toward next from `time`, over its own window or `overMs`; the slope it
    // has carries over into the new window.
    retarget(next,time,overMs=durationMs) {
      if(next===to)return;
      const current=state(time);
      from=current.value;tangent=current.slope*(overMs/windowMs);to=next;start=time;windowMs=overMs;active=true;
    }
  };
}
