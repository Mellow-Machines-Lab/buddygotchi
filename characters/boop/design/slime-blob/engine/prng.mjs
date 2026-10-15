// The audition's LCG, owned by each actor. No process-global random state.
export function createPRNG(seed=1729) {
  if(!Number.isFinite(seed))throw new TypeError('seed must be finite');
  let state=seed>>>0;
  return () => {state=(Math.imul(state,1664525)+1013904223)>>>0;return state/4294967296;};
}
