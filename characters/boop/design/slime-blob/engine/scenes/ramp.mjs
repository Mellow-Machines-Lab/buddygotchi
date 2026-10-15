// CONTINUITY.md, Representative activity scenes: a prop's visibility ramp.
// A cubic Hermite from the current value and slope to the target over a fixed
// window: from rest it is a smoothstep; a reversal keeps the current slope,
// so it is continuous in value and velocity. The end is exact.
export function createRamp(durationMs) {
  let from=0,to=0,tangent=0,start=0,active=false;
  function state(time) {
    const elapsed=time-start;
    if(!active||elapsed>=durationMs)return {value:to,tangent:0};
    const s=elapsed/durationMs,s2=s*s,s3=s2*s;
    const value=(2*s3-3*s2+1)*from+(s3-2*s2+s)*tangent+(3*s2-2*s3)*to;
    const slope=(6*s2-6*s)*from+(3*s2-4*s+1)*tangent+(6*s-6*s2)*to;
    return {value:Math.min(1,Math.max(0,value)),tangent:slope};
  }
  return {
    value:time=>state(time).value,
    // Only when nothing it scales is drawn: starts the next fade-in from zero.
    reset() {from=to=tangent=0;active=false;},
    retarget(next,time) {
      if(next===to)return;
      const current=state(time);
      from=current.value;tangent=current.tangent;to=next;start=time;active=true;
    }
  };
}
