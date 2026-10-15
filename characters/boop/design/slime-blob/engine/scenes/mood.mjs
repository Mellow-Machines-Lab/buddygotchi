// Representative expressive intent, independent of factual outcome. The same
// request is signalled once; mood shapes the movement, never its meaning.
export const sceneMoodTraits=Object.freeze({
  happy:Object.freeze({delayMs:0,spacing:1,gain:1.05,lean:.014}),
  grumpy:Object.freeze({delayMs:-40,spacing:.86,gain:1.12,lean:.024}),
  sad:Object.freeze({delayMs:160,spacing:1.18,gain:.62,lean:-.016}),
  frightened:Object.freeze({delayMs:240,spacing:1.28,gain:.68,lean:-.018})
});
const neutral=Object.freeze({delayMs:0,spacing:1,gain:1,lean:0});
export function sceneMood(mood) {return sceneMoodTraits[mood]||neutral;}
