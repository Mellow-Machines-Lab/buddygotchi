// The Character Studio's logic with no browser (README.md): how it lists the
// pack's moves and faces, and what the board is sent for each thing the
// page shows, as [ms, message] pairs from a reset. The page (studio.js) and
// the board (board.js) use it as window.StudioLogic; under Node, tests/ do.
(() => {
  const STROKE = {t: 'dbg.touch', x: 60, y: 120, to_x: 220, to_y: 120, ms: 500};
  const WORKING = {base: 'working', busy: 1};
  // The look each move, face or Moment plays over, by its state.
  const LOOKS = {idle: {base: 'idle'}, working: WORKING, asleep: {base: 'asleep'}};
  // What the agent is doing for each activity, as the Mac says it
  // (WorkStream.doing), so the strip's term shows (render/gel/lane.cpp).
  const SAMPLE_WORDS = {tool_use: 'editing Core.swift +12', analyzing: 'reading Core.swift', searching: 'searching TODO',
    terminal: 'building', testing: 'running the tests', waiting: 'downloading', planning: 'planning',
    delegating: 'sending a helper'};
  const working = act => ({...WORKING, act, calls: [[0, 1, SAMPLE_WORDS[act] || 'Core.swift']]});
  // The states no Mac sends any more, which the board reads as plain
  // working: each is asked as the act it shows as, with its own words.
  const STANDS_IN = {planning: 'tool_use', searching: 'analyzing', testing: 'terminal', delegating: 'terminal'};
  const title = id => id.replace(/[-_]/g, ' ').replace(/^\w/, c => c.toUpperCase());

  // How the board is asked for each of the engine's states (states.json),
  // for a pack's review clips (board.js's record()), given the acts it draws
  // while working (StudioData.states.acts, which charactergen reads from the
  // firmware) and where the simulator taps (boop-simulator.js's TAP). A look
  // is a `state` message: its base, and what the agent is doing while
  // working, or needs you; a reaction is a `do` over a look; the board's own
  // are inputs, at their ms: a tap, taps in a row, a stroke across.
  //
  // wire(cell, vol) is what the board is sent to show a cell, as
  // [ms, message] pairs from when it's asked: a look's `state`, or the look
  // a reaction or input plays over (working, or idle for waking up and a
  // stroke) and then it. `after` is how long the board takes to show it
  // with nothing more said: no_app's window.
  const DOES = ['listening', 'starting', 'reply_ready', 'task_complete', 'wake_up', 'notice'];
  const NO_APP_MS = 30000;  // with no state this long, the board takes the Mac for gone (linkkit's kHostGoneMs)
  function wiring({acts, tap}) {
    const looks = {...LOOKS, no_app: WORKING, needs_you: {...WORKING, attn: {id: 1, agent: 'claude', project: 'Studio', more: 0}},
      ...Object.fromEntries(Object.entries(STANDS_IN).map(([state, act]) => [state, {...working(act), calls: [[0, 1, SAMPLE_WORDS[state]]]}])),
      ...Object.fromEntries(acts.map(act => [act, working(act)]))};
    const TOUCH = {t: 'dbg.touch', x: tap[0], y: tap[1], ms: 60};
    const INPUTS = {poked: [[0, TOUCH]], tap_spam: [[0, TOUCH], [200, TOUCH], [400, TOUCH]], gesture: [[0, STROKE]]};
    let ids = 0;
    return function wire({mood, state, outcome = 'success', context = 'new_task'}, vol = 0) {
      if (looks[state]) return {look: looks[state], after: state === 'no_app' ? NO_APP_MS : 0, steps: [[0, {t: 'state', ...looks[state], mood, vol}]]};
      const look = state === 'wake_up' || state === 'gesture' ? looks.idle : WORKING;
      const steps = [[0, {t: 'state', ...look, mood, vol}]];
      if (DOES.includes(state)) {
        const args = state === 'task_complete' ? {outcome} : state === 'starting' ? {ctx: context} : {};
        steps.push([0, {t: 'do', id: ++ids, name: state, play: 'now', args}]);
      } else if (INPUTS[state]) steps.push(...INPUTS[state]);
      else throw Error(`The board has no state ${state}`);
      return {look, after: 0, steps};
    };
  }

  // ── Moves ────────────────────────────────────────────────────────────────
  // The pack's moves (charactergen's `moves`, its rig clips) in their
  // groups, in the order charactergen gives the groups (`move_groups`),
  // those with no group last. `find` keeps the moves whose id or about has
  // every word of it.
  function moveGroups(moves, order, find = '') {
    const words = find.toLowerCase().split(/\s+/).filter(Boolean);
    const kept = moves.filter(m => words.every(w => m.id.includes(w) || m.about.toLowerCase().includes(w)));
    return [...order, null].map(id => ({id, label: id ? title(id) : 'No group', moves: kept.filter(m => (m.group || null) === id)}))
      .filter(g => g.moves.length);
  }
  // The look a move plays over when it isn't one: a work pose at work, any
  // other at rest.
  const overFor = move => move.group === 'work_poses' ? 'working' : 'idle';
  // A clip asked by name waits this long for the look under it to show.
  const CLIP_AFTER_MS = 300;
  // A move in a mood: the look it's the base of (its state, an activity's
  // `act` or a tier's tag), which the board plays by itself; else its clip by
  // name (dbg.clip) over a look (`over`).
  function moveSteps(move, {mood, over = overFor(move)}) {
    const look = move.look;
    if (look) {
      const base = look.act ? working(look.act) : LOOKS[look.state] || {base: look.state};
      return [[0, {t: 'state', ...base, ...(look.tag ? {when: [look.tag]} : {}), mood, vol: 0}]];
    }
    return [[0, {t: 'state', ...LOOKS[over], mood, vol: 0}], [CLIP_AFTER_MS, {t: 'dbg.clip', name: move.id}]];
  }

  // ── Faces ────────────────────────────────────────────────────────────────
  // Every face the board draws (charactergen's `faces`): the Mac's, which a
  // mood or a Moment's emotion asks for, then the board's own (`board`).
  const faceSheet = faces => ({mac: faces.filter(f => !f.board), board: faces.filter(f => f.board)});
  // How long the face before shows before the change to the next.
  const CHANGE_MS = 1500;
  // A face at rest, or the change to it from another.
  const faceSteps = (to, from = null) => from && from !== to
    ? [[0, {t: 'state', base: 'idle', mood: from, vol: 0}], [CHANGE_MS, {t: 'state', base: 'idle', mood: to, vol: 0}]]
    : [[0, {t: 'state', base: 'idle', mood: to, vol: 0}]];

  // ── Moments ──────────────────────────────────────────────────────────────
  // A skit's Moment as the Mac sends it (MomentOutput), by the first slot the
  // skit plays for: a turn's finish names its thread (`who`) and the tier
  // its turn reached, a win with the XP it earned; a fix holds "tests fixed"
  // low with its XP; you back is the wake-up; anything else is a face. Its
  // clip, its invite (with the pack's word for the touch, the wait every
  // invite but the very first has, and care's XP), its takes, its face
  // (the mood) and its size's loops. StudioMomentTests pins each of the
  // pack's skits against the Mac's own (tests/moments.json).
  const FINISH = {doneLong: 'success', doneVeryLong: 'success', failed: 'failure', failedVeryLong: 'failure', gaveUp: 'failure'};
  const BACK = ['back', 'backDays', 'backAfterADay'];
  const MAC = {who: {agent: 'claude', thread: 'Studio'}, turn: 1, turnXP: 5, fixXP: 5, careXP: 3, fixed: 'tests fixed', waitMs: 4000};
  // Each size's loops (MomentOutput's sizes), and the kind of take it says.
  const SIZES = [{id: 'small', loops: 1, kind: 'sound'}, {id: 'medium', loops: 2, kind: 'word'}, {id: 'big', loops: 3, kind: 'phrase'}];
  function momentOf(skit, {mood, loops = 2, take = null, then = null, words = {}}) {
    const slot = skit.slots?.[0], outcome = FINISH[slot], args = {};
    let name = 'react';
    if (outcome) {
      name = 'task_complete';
      Object.assign(args, {outcome, turn: MAC.turn}, outcome === 'success' ? {xp: MAC.turnXP} : {}, {who: {...MAC.who}});
    } else if (slot === 'checkFixed') Object.assign(args, {sign: MAC.fixed, low: true, xp: MAC.fixXP});
    else if (BACK.includes(slot)) name = 'wake_up';
    if (skit.clip) args.clip = skit.clip;
    if (skit.invite) {
      const word = words[skit.invite.touch];
      args.invite = {skit: skit.id, ...skit.invite, ...(word ? {label: word} : {}), ms: MAC.waitMs, xp: MAC.careXP};
    }
    if (take) args.say = then ? {take, then} : {take};
    return {name, args: {...args, mood, loops}};
  }
  // A skit's takes in a face (charactergen's `takes`): those its moods have,
  // the size's kind first.
  function takesFor(takes, skit, mood, kind = 'word') {
    const fit = takes.filter(t => t.skit === skit.id && t.moods.includes(mood));
    return [...fit.filter(t => t.kind === kind), ...fit.filter(t => t.kind !== kind)];
  }
  // A Moment over its look: a finish or a face over working, the wake-up at
  // rest, the `do` once the look shows.
  const MOMENT_AFTER_MS = 300;
  let ids = 0;
  function momentSteps({name, args}) {
    const look = name === 'wake_up' ? LOOKS.idle : WORKING;
    return [[0, {t: 'state', ...look, mood: args.mood, vol: 0}], [MOMENT_AFTER_MS, {t: 'do', id: ++ids, name, play: 'now', args}]];
  }
  // Answer: the invite's touch, where the simulator taps or a stroke across.
  // Miss sends nothing: the wait runs out on the board.
  const answerSteps = (touch, tap) => touch === 'tap' ? [[0, {t: 'dbg.touch', x: tap[0], y: tap[1], ms: 60}]] : [[0, STROKE]];
  // The board's `ev invite`, how an invite ended, from one of its lines, or null.
  function heard(line) {
    let m = null;
    try { m = JSON.parse(line); } catch { return null; }
    return m?.t === 'ev' && m.kind === 'invite' ? {did: m.did, ...m.data} : null;
  }

  // ── Motion ───────────────────────────────────────────────────────────────
  // The motion layer's rules (charactergen's `motion`), each on until a
  // reset. A switch is one rule's dbg.motion, "all" every one's; after a
  // reset, the rules switched off are sent again.
  const motionMessage = (rule, on) => ({t: 'dbg.motion', rule, on});
  const motionAgain = (rules, off) => off.size && off.size === rules.length ? [motionMessage('all', false)]
    : rules.filter(r => off.has(r)).map(r => motionMessage(r, false));

  const logic = {wiring, title, moveGroups, overFor, moveSteps, faceSheet, faceSteps, CHANGE_MS, SIZES, momentOf, takesFor,
    momentSteps, answerSteps, heard, motionMessage, motionAgain};
  if (typeof module !== 'undefined') module.exports = logic;
  else window.StudioLogic = logic;
})();
