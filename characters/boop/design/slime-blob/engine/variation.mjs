// One deterministic three-entry shuffle bag per mood/state/outcome. A bag is
// consumed only by the scene's recovery boundary, never by a draw or retarget.
export function createVariations(rand) {
  const bags=new Map();
  return {
    next(key) {
      let entry=bags.get(key);
      if(!entry){entry={bag:[],last:-1};bags.set(key,entry);}
      if(!entry.bag.length){
        entry.bag=[0,1,2];
        for(let i=entry.bag.length-1;i>0;i--){const j=Math.floor(rand()*(i+1));[entry.bag[i],entry.bag[j]]=[entry.bag[j],entry.bag[i]];}
        if(entry.bag[0]===entry.last)[entry.bag[0],entry.bag[1]]=[entry.bag[1],entry.bag[0]];
      }
      const variant=entry.bag.shift();entry.last=variant;
      return variant;
    },
    inspect() {return Object.fromEntries([...bags].map(([key,entry])=>[key,{last:entry.last,remaining:[...entry.bag]}]));}
  };
}
