// The Mac's mirror of the board (a character pack's mac/mirror/board.js,
// firmware/tools/mirror.sh) as a program that does what the native
// simulator's frozen build does on its stdin and stdout (simulator/core/
// main.cpp): each line the board's USB, a pass of its loop after each it
// handles, and what it says written out. So `boopctl mirror` plays the
// scenarios on it as it plays them on the simulator.
//
//   node internal/tools/boopctl_lib/mirror_board.mjs characters/boop/mac/mirror/board.js
import {createRequire} from 'node:module';
import path from 'node:path';
import readline from 'node:readline';

const make = createRequire(import.meta.url)(path.resolve(process.argv[2]));
const core = await make();
const usb = core.cwrap('mirror_send', 'number', ['string']);
const said = () => {
  const at = core._mirror_said();
  if (at) process.stdout.write(core.UTF8ToString(at));
};
core._mirror_power();  // on a frozen clock, as the simulator's build starts
for await (const line of readline.createInterface({input: process.stdin})) {
  const handled = usb(line + '\n');
  said();
  if (!handled) continue;
  core._mirror_tick();
  said();
}
