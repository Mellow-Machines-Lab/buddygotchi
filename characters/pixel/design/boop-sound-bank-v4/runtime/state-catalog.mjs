import {moods} from './visual/base.mjs';

export const stateOrder=['no_app','asleep','idle','listening','starting','planning','working','terminal','tool_use','searching','analyzing','testing','delegating','helper_return','waiting','needs_you','reply_ready','task_complete','error','stopped','poked','tap_spam'];
export const sustainedStates=['working','idle','asleep','no_app','planning','terminal','tool_use','searching','analyzing','testing','waiting'];
// Seven named characters, not a new intensity axis. Timing is authored per mood.
export const acting={
  happy:{pace:1,gain:.70,pitch:1.04,lift:4,character:'Bouncy, open-hearted and a little distractible.'},
  excited:{pace:.78,gain:.72,pitch:1.08,lift:8,character:'XD delight; rushes, overshoots and catches up.'},
  proud:{pace:1.12,gain:.65,pitch:.96,lift:3,character:'Smirking show-off; poised reveals and deliberate holds.'},
  curious:{pace:1.08,gain:.60,pitch:1.03,lift:3,character:'Alternating big/small eyes; peers, compares and probes.'},
  determined:{pace:.92,gain:.70,pitch:1,lift:2,character:'Upward brows; steady, square and methodical.'},
  grumpy:{pace:.76,gain:.84,pitch:.94,lift:5,character:'Anger mark; compressed windups, sharp impacts, flying square fragments.'},
  sad:{pace:1.28,gain:.48,pitch:.98,lift:2,character:'Hesitant but still doing the job; blue cube tears and soft landings.'}
};
const definitions=[
 ['starting',1,'start-card','New task, coming through','Flip NEW TASK, then unfold the keyboard.',3.8,{startContext:'new_task'}],
 ['starting',2,'ready-card','Ready at the desk','READY is a connection greeting, not a new task.',3.8,{startContext:'session'}],
 ['starting',3,'continue-card','Back to it','CONTINUE; reopen the workstation.',3.8,{startContext:'continuation'}],
 ['starting',4,'compact-card','Squeezed and back','COMPACTED is the context made smaller; the work goes on.',3.8,{startContext:'compacted'}],
 ['planning',1,'step-route','A plan in three blocks','Lay out numbered steps, reconsider the middle card, then restore the stack.',4.8],
 ['terminal',1,'spy-console','Tiny terminal operator','Rhythmic mechanical typing, green toy code and chunky binary rain.',3.8],
 ['tool_use',1,'socket-toolbox','The right tool for the job','Unlatch the toolbox, seat a plug and work the chunky lever.',4.4],
 ['searching',1,'outbound-search','Out into the world','Sweep a big magnifier over a globe; send a query tile, receive material.',4.8],
 ['analyzing',1,'evidence-desk','Let me look at that','Compare incoming cards, magnify their patterns and group the clues.',4.8],
 ['testing',1,'test-gate','Through the test gate','Feed three blocks through an amber inspection gate; no invented pass result.',4.4],
 ['delegating',1,'helper-hatch','Little helpers, launch','Open a hatch and dispatch three tiny robots with work cubes.',4.4],
 ['delegating',2,'helper-drill','Squad, move out','Salute with one soft pad; GO! card and a toy-robot formation.',4.8],
 ['helper_return',1,'helper-courier','Delivery from a helper','A courier slides in with a REPORT card; Boop catches the delivery.',4.2],
 ['helper_return',2,'helper-report','Reporting for duty','Returning helpers line up, salute, hand over REPORT and stand down.',4.8],
 ['waiting',1,'hourglass-lean','Still waiting on the machine','Lean beside a broad hourglass; grains fall, then a slow flip.',6.2],
 ['reply_ready',1,'answer-tray','An answer for you','Unfold a page and push an ANSWER tray forward; no celebration.',4.2],
 ['error',1,'jam-recoil','That did not work','Try a stuck mechanism twice; it spits out block fragments. ERROR, not task over.',3.8],
 ['stopped',1,'brake-settle','Putting the tools down','Brake a conveyor; the loose blocks settle beneath STOPPED.',4.2],
 ['poked',1,'squash-hello','Oh, hello there','A broad screen contact, a squash and a mood-shaped rebound.',2.8],
 ['tap_spam',1,'cushion-shield','Easy, easy!','Contacts arrive from several sides; Boop ducks behind a soft EASY! shield.',3.8],
 ['task_complete',4,'complete-card','Complete, with ceremony','Hold COMPLETE under a trophy, square fireworks and a full victory accent.',5.8,{outcome:'success'}],
 ['task_complete',5,'failed-card','The task fell apart','Brace a failing work block; it separates. Hold FAILED, then settle. No victory.',5.2,{outcome:'failure'}]
];
export const additions=definitions.flatMap(([state,variation,action,name,caption,baseSeconds,extra={}])=>moods.map(mood=>({
  id:`${mood}.${state}.${String(variation).padStart(2,'0')}`,mood,state,variation,action,name,caption,
  seconds:Number((baseSeconds*(state==='task_complete'?1:acting[mood].pace)).toFixed(3)),
  renderer:'state-v3',approval:'Review candidate',...extra
})));
