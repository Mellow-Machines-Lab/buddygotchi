// One deterministic shuffle bag per mood/state/outcome. A bag is
// consumed only by the scene's recovery boundary, never by a draw or retarget.
// Its first round deals the key's first three takes, the ones every state has
// always had; from the second round on it deals every take, the comedy ones
// too. So a fresh bag opens as it always has, and the joke comes once the
// straight takes have been seen.
export function createVariations(rand) {
  const bags=new Map();
  return {
    next(key,takes=3) {
      let entry=bags.get(key);
      if(!entry){entry={bag:[],last:-1,dealt:false};bags.set(key,entry);}
      if(!entry.bag.length){
        const count=entry.dealt?takes:Math.min(takes,3);entry.dealt=true;
        entry.bag=Array.from({length:count},(_,i)=>i);
        for(let i=entry.bag.length-1;i>0;i--){const j=Math.floor(rand()*(i+1));[entry.bag[i],entry.bag[j]]=[entry.bag[j],entry.bag[i]];}
        if(entry.bag[0]===entry.last)[entry.bag[0],entry.bag[1]]=[entry.bag[1],entry.bag[0]];
      }
      const variant=entry.bag.shift();entry.last=variant;
      return variant;
    },
    inspect() {return Object.fromEntries([...bags].map(([key,entry])=>[key,{last:entry.last,remaining:[...entry.bag]}]));}
  };
}
