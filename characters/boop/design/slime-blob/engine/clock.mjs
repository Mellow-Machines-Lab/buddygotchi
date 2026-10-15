// The caller supplies monotonic milliseconds. Normalizing the origin to one
// keeps the locked RAF driver's zero sentinel distinct from a real first frame.
export function createClock() {
  let origin=null,previous=null;
  return {
    stamp(ms) {
      if(!Number.isFinite(ms)||ms<0)throw new RangeError('step requires nonnegative finite milliseconds');
      if(previous!==null&&ms<previous)throw new RangeError('presentation clock cannot run backwards');
      if(origin===null)origin=ms;
      previous=ms;
      return 1+ms-origin;
    }
  };
}
