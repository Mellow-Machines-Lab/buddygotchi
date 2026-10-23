import {catalog as legacyCatalog} from './legacy-catalog.mjs';
import {moodAdditions,newMoods} from './mood-catalog.mjs';
import {wakeAdditions} from './wake-art.mjs';
import {comedyAdditions} from './comedy-art.mjs';
import {occasionAdditions} from './occasion-art.mjs';
import {gestureAdditions} from './gesture-art.mjs';
import {noticeAdditions} from './notice-art.mjs';
export const moods=['happy','excited','proud','curious','determined','grumpy','sad',...newMoods];
export const catalog=[...legacyCatalog,...moodAdditions,...wakeAdditions,...comedyAdditions,...occasionAdditions,...gestureAdditions,...noticeAdditions];
export function getAsset(id){const asset=catalog.find(a=>a.id===id);if(!asset)throw new Error('Unknown Boop variation: '+id);return asset;}
