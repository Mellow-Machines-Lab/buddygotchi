// Character Studio: the board's firmware on the stage, and three views of
// the pack to play on it: its moves (the rig's clips, in their groups), its
// faces (each at rest, and the change from one to another) and its moments
// (a skit's Moment as the Mac sends it, its invite answered or missed). The
// mood is one picker at the top; the motion layer's switches sit under the
// stage. The page owns the selection, the views and the URL; what the board
// is sent is logic.js's. A pack's entry for its board may add tools
// (Studio.register, README.md). charactergen.py writes the pack data this
// reads, window.StudioData (packs.js).
(() => {
  const root = document.getElementById('studio');
  const $ = selector => root.querySelector(selector), $$ = selector => [...root.querySelectorAll(selector)];
  const L = window.StudioLogic, title = L.title;
  // The pack's adapter for its board, kept under the pack whose script registered it.
  const adapters = {};
  window.Studio = {register(id, adapter) { adapters[document.currentScript.dataset.pack + '/' + id] = adapter; }};
  const data = window.StudioData;
  if (!data) { $('[data-missing]').hidden = false; $('[data-layout]').hidden = true; return; }
  const name = data.chosen, pack = data.packs[name];
  // Its board's entry: the pack's own for the face, else the board's alone.
  const entry = pack.studio.find(e => e.board);
  const families = Object.assign({}, ...pack.studio.map(e => e.families || {}));
  const VIEWS = ['moves', 'faces', 'moments'];
  const moveOf = id => pack.moves.find(m => m.id === id), skitOf = id => pack.skits.find(s => s.id === id);
  const sizeOf = id => L.SIZES.find(s => s.id === id) || L.SIZES[1];

  const sel = {view: 'moves', mood: pack.default_mood, move: pack.moves[0]?.id || '', over: '', face: pack.default_mood,
    skit: pack.skits[0]?.id || '', size: 'medium', take: ''};
  const off = new Set();  // the motion rules switched off
  let sound = false, volume = .5, instance = null;
  const ctx = {root, stage: $('#stage'), tools: $('[data-tools-body]'), get sound() { return sound; }, get volume() { return volume; },
    get selection() { return sel; }, onChange: () => onChange(), onLine: line => heardLine(line),
    motion: () => L.motionAgain(pack.motion, off), setSound: on => setSound(on)};

  // The entry's scripts and styles, each once, in order. A script carries its pack's name for register().
  async function load() {
    for (const href of entry.styles || []) { const l = document.createElement('link'); l.rel = 'stylesheet'; l.href = href; document.head.append(l); }
    for (const src of entry.scripts || []) await new Promise((ok, fail) => {
      const s = document.createElement('script'); s.src = src; s.dataset.pack = name; s.onload = ok;
      s.onerror = () => fail(Error('Could not load ' + src)); document.head.append(s);
    });
  }
  const el = (tag, text, cls) => { const e = document.createElement(tag); if (text) e.append(text); if (cls) e.className = cls; return e; };
  function group(text, items, cls = 'chips') {
    const g = el('div', '', 'group'), c = el('div', '', cls);
    c.append(...items); g.append(el('div', text, 'group-label'), c); return g;
  }
  const press = (container, test) => { for (const b of container.querySelectorAll('button')) b.setAttribute('aria-pressed', String(test(b))); };

  // ── The mood, at the top ────────────────────────────────────────────────
  function renderMoods() {
    const order = [...Object.keys(families), ...pack.moods.map(m => m.family || '')].filter((f, i, all) => all.indexOf(f) === i);
    $('[data-mood]').replaceChildren(...order.map(f => {
      const g = el('optgroup'); g.label = families[f]?.label || (f ? title(f) : 'Moods');
      g.append(...pack.moods.filter(m => (m.family || '') === f).map(m => { const o = el('option', title(m.id)); o.value = m.id; return o; }));
      return g;
    }));
    $('[data-mood]').value = sel.mood;
  }

  // ── Moves ───────────────────────────────────────────────────────────────
  let listed = [];  // the moves the list shows, in its order, for ↑ and ↓
  function renderMoves() {
    const groups = L.moveGroups(pack.moves, data.move_groups, $('[data-find]').value);
    listed = groups.flatMap(g => g.moves.map(m => m.id));
    $('[data-moves]').replaceChildren(...groups.map(g => group(g.label, g.moves.map(m => {
      const b = el('button', m.id, 'chip move'); b.type = 'button'; b.dataset.move = m.id; b.title = m.about;
      b.setAttribute('aria-pressed', String(m.id === sel.move));
      if (m.loop) b.append(el('span', '↻', 'loops'));
      return b;
    }))));
    if (!groups.length) $('[data-moves]').append(el('p', 'No move has those words.', 'hint'));
    const move = moveOf(sel.move), over = sel.over || (move ? L.overFor(move) : 'idle');
    press($('[data-over]'), b => b.dataset.value === over);
    $('[data-over]').inert = Boolean(move?.look);
    $('[data-over]').title = move?.look ? 'A base plays as its own look' : '';
  }
  // How a base is asked for: its state, an activity's or a tier's.
  const lookText = look => look.act ? `working, ${look.act.replace('_', ' ')}` : look.tag ? `working, at ${look.tag}` : look.state;
  function playMove() {
    const move = moveOf(sel.move);
    if (!move) return;
    instance?.play(L.moveSteps(move, {mood: sel.mood, ...(sel.over ? {over: sel.over} : {})}));
    const over = sel.over || L.overFor(move);
    caption(move.id, `${move.about || 'No about.'} ${move.look ? `The board's own look for ${lookText(move.look)}` : `Over ${over}`}, ${
      title(sel.mood).toLowerCase()}, ${(move.ms / 1000).toFixed(1)} s${move.loop ? ', looping' : ''}.`);
  }

  // ── Faces ───────────────────────────────────────────────────────────────
  // Each face's still, drawn once from the board at rest; a click plays the
  // change to it from the face the stage shows.
  const sheet = L.faceSheet(pack.faces);
  let stills = null, faceShown = null;
  const about = id => pack.faces.find(f => f.id === id)?.face || pack.moods.find(m => m.id === id)?.meaning || '';
  function renderFaces() {
    const tile = f => {
      const b = el('button', '', 'face'); b.type = 'button'; b.dataset.face = f.id; b.title = about(f.id);
      const c = el('canvas', '', 'still'); c.width = 502; c.height = 410;
      const label = el('span', title(f.id), 'face-name');
      if (f.family && families[f.family]) label.style.setProperty('--hue', families[f.family].colour);
      b.append(c, label);
      if (f.board) b.append(el('span', "board's own", 'badge'));
      return b;
    };
    $('[data-faces-mac]').replaceChildren(...sheet.mac.map(tile));
    $('[data-faces-board]').replaceChildren(...sheet.board.map(tile));
    pressFaces();
  }
  const pressFaces = () => $$('.face').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.face === sel.face)));
  function drawStills() {
    if (stills || !instance) return;
    const ids = [...sheet.mac, ...sheet.board].map(f => f.id);
    let done = 0;
    $('[data-faces-about]').textContent = `Drawing each face at rest on the board… 0 of ${ids.length}`;
    stills = instance.ready.then(() => instance.stills(ids, (id, picture) => {
      const c = root.querySelector(`.face[data-face="${id}"] canvas`);
      c?.getContext('2d').drawImage(picture, 0, 0, c.width, c.height);
      picture.close?.();
      $('[data-faces-about]').textContent = `Drawing each face at rest on the board… ${++done} of ${ids.length}`;
    })).then(() => { $('[data-faces-about]').textContent = facesHint; }, error => { stills = null; $('[data-faces-about]').textContent = error.message; });
  }
  const facesHint = 'Each face at rest, about life size. Click one to see the change to it from the face the board shows.';
  function playFace() {
    const from = faceShown;
    instance?.play(L.faceSteps(sel.face, from));
    faceShown = sel.face;
    const own = pack.faces.find(f => f.id === sel.face)?.board ? " One of the board's own faces." : '';
    caption(from && from !== sel.face ? `${title(from)} → ${title(sel.face)}` : title(sel.face),
      (about(sel.face) || `The ${title(sel.face).toLowerCase()} face.`) + own);
  }

  // ── Moments ─────────────────────────────────────────────────────────────
  // One skit's Moment at a time, so one invite: playing another resets the
  // board first. `moment` is the one played: its skit, what the board said
  // of its invite, and its stage now (dbg.state's `invite`).
  let moment = null, polling = 0;
  const skitText = s => [s.slots?.[0] ? `for ${s.slots[0]}` : '', s.invite ? `${s.invite.pose} pose, a ${s.invite.touch}, then ${s.invite.payoff}` : 'no invite',
    s.clip ? `clip ${s.clip}` : ''].filter(Boolean).join(' · ');
  function renderMoments() {
    $('[data-skits]').replaceChildren(...pack.skits.map(s => {
      const b = el('button', '', 'skit'); b.type = 'button'; b.dataset.skit = s.id;
      b.setAttribute('aria-pressed', String(s.id === sel.skit));
      b.append(el('strong', title(s.id)), el('small', skitText(s)));
      return b;
    }));
    if (!pack.skits.length) $('[data-skits]').append(el('p', 'The pack has no skits.', 'hint'));
    $('[data-size]').replaceChildren(...L.SIZES.map(s => { const o = el('option', title(s.id)); o.value = s.id; return o; }));
    $('[data-size]').value = sel.size;
    const takes = takesNow();
    if (sel.take !== 'none' && !takes.some(t => t.id === sel.take)) sel.take = '';
    $('[data-take]').replaceChildren(...[...takes, {id: 'none', text: takes.length ? 'No words' : `No take in ${sel.mood}`}].map(t => {
      const o = el('option', t.id === 'none' ? t.text : `${t.text} (${t.kind})`); o.value = t.id; return o;
    }));
    $('[data-take]').value = take() || 'none';
    renderInvite();
  }
  // The skit's takes in the mood, and the one it says: the one picked, the
  // first (its size's kind first) as the Mac always has one, or none.
  const takesNow = () => skitOf(sel.skit) ? L.takesFor(pack.takes, skitOf(sel.skit), sel.mood, sizeOf(sel.size).kind) : [];
  const take = () => sel.take === 'none' ? null : sel.take || takesNow()[0]?.id || null;
  function playMoment() {
    const skit = skitOf(sel.skit);
    if (!skit || !instance) return;
    const m = L.momentOf(skit, {mood: sel.mood, loops: sizeOf(sel.size).loops, take: take(), words: pack.words});
    const steps = L.momentSteps(m);
    moment = {skit, invite: m.args.invite || null, stage: null, heard: null, missing: false, at: performance.now()};
    instance.play(steps);
    $('[data-sent]').textContent = JSON.stringify(steps[steps.length - 1][1]);
    $('[data-heard]').textContent = 'Nothing yet.';
    caption(title(skit.id), `The ${skit.id} skit's Moment as the Mac sends it, in ${sel.mood}` +
      (m.args.invite ? `, then its invite: ${m.args.invite.pose}, waiting ${m.args.invite.ms / 1000} s for a ${m.args.invite.touch}.` : ', with no invite.'));
    clearTimeout(polling);
    if (moment.invite) poll();
    renderInvite();
  }
  // dbg.state's invite while one may still pay off: until the board says
  // how it ended, and through a miss's window.
  async function poll() {
    const m = moment;
    if (!m) return;
    try { m.stage = (await instance.ask({t: 'dbg.state'})).invite; } catch { m.stage = null; }
    if (m !== moment) return;
    renderInvite();
    const over = m.heard && m.heard.did !== 'missed' || m.heard?.did === 'missed' && !m.stage;
    if (!over && performance.now() - m.at < 60000) polling = setTimeout(poll, 200);
  }
  function heardLine(line) {
    const h = L.heard(line);
    if (!h || !moment) return;
    moment.heard = h;
    $('[data-heard]').textContent = line;
    renderInvite();
  }
  const answerable = () => Boolean(moment?.invite && (moment.stage?.stage === 'pose' && !moment.missing || moment.stage?.stage === 'window'));
  function renderInvite() {
    const m = moment, s = m?.stage?.stage, touch = m?.invite?.touch;
    const text = !m ? 'Play a skit to see its Moment, then answer its invite or let it pass.'
      : !m.invite ? 'This skit asks for no touch.'
      : s === 'ahead' || !s && !m.heard ? 'The Moment plays first, then the pose.'
      : s === 'pose' ? (m.missing ? 'Letting the wait run out' : `Waiting for a ${touch}`) + `: ${(m.stage.ms / 1000).toFixed(1)} of ${m.invite.ms / 1000} s.`
      : s === 'payoff' ? 'Answered: the payoff.'
      : s === 'shrug' ? 'No touch came: it shrugs.'
      : s === 'window' ? `Missed. A ${touch} in the next 30 s still pays off, late.`
      : s === 'late' ? 'Late: the payoff after all.'
      : `Done: the board said ${m.heard.did}.`;
    $('[data-invite-now]').textContent = text;
    const answer = $('[data-answer]');
    answer.disabled = !answerable();
    answer.firstChild.textContent = s === 'window' ? 'Answer late ' : 'Answer ';
    $('[data-miss]').disabled = !(m?.invite && (s === 'pose' || s === 'ahead' || !s && !m.heard) && !m.missing);
  }
  function answer() {
    if (!answerable()) return;
    instance.send(L.answerSteps(moment.invite.touch, instance.tap));
  }
  function miss() {
    if ($('[data-miss]').disabled) return;
    moment.missing = true;
    renderInvite();
  }

  // ── Motion ──────────────────────────────────────────────────────────────
  function renderMotion() {
    $('[data-motion-box]').hidden = !pack.motion.length;
    $('[data-motion]').replaceChildren(...[...pack.motion, 'all'].map(rule => {
      const b = el('button', rule === 'all' ? 'All' : rule, 'chip switch'); b.type = 'button'; b.dataset.rule = rule;
      b.setAttribute('aria-pressed', String(rule === 'all' ? !off.size : !off.has(rule)));
      b.title = rule === 'all' ? 'Every rule on, or every one off' : `The ${rule} rule: on when pressed`;
      return b;
    }));
  }
  function switchMotion(rule) {
    if (rule === 'all') {
      const on = off.size > 0;
      on ? off.clear() : pack.motion.forEach(r => off.add(r));
      instance?.send([[0, L.motionMessage('all', on)]]);
    } else {
      const on = off.has(rule);
      on ? off.delete(rule) : off.add(rule);
      instance?.send([[0, L.motionMessage(rule, on)]]);
    }
    renderMotion();
    writeHash();
  }

  // ── The selection, the views and the stage ──────────────────────────────
  function caption(text, more) { $('[data-title]').textContent = text; $('[data-caption]').textContent = more; }
  function render() {
    for (const b of $$('[data-tab]')) b.setAttribute('aria-selected', String(b.dataset.tab === sel.view));
    for (const v of $$('[data-view]')) v.hidden = v.dataset.view !== sel.view;
    $('[data-mood]').value = sel.mood;
    $('[data-mood]').disabled = sel.view === 'faces';
    $('[data-mood]').title = sel.view === 'faces' ? 'Each face is its own here' : 'The face and the timing every move and Moment plays in';
    if (sel.view === 'moves') renderMoves();
    else if (sel.view === 'faces') { pressFaces(); drawStills(); }
    else renderMoments();
    renderMotion();
    $('[data-tools]').hidden = !ctx.tools.children.length;
    writeHash();
    update();
  }
  // What the stage shows for the view: its move, face or Moment, from a reset.
  function play() {
    if (sel.view === 'moves') playMove();
    else if (sel.view === 'faces') playFace();
    else playMoment();
  }
  function change(patch, {replay = true} = {}) {
    if (busyNow()) return;
    if (patch.view && patch.view !== sel.view) { clearTimeout(polling); moment = null; if (patch.view === 'faces') faceShown = null; }
    Object.assign(sel, patch);
    render();
    if (replay) play();
  }
  function update() {
    $('[data-status]').textContent = instance ? instance.status() : '';
    const busy = busyNow();
    for (const s of ['.pick-column', '.controls', '[data-motion-box]']) $(s).inert = busy;
  }
  let pending = false;
  function onChange() { if (pending) return; pending = true; requestAnimationFrame(() => { pending = false; update(); }); }
  const busyNow = () => Boolean(instance?.busy?.());
  function setSound(on) {
    sound = on; const b = $('[data-sound]'); b.setAttribute('aria-pressed', String(on)); b.textContent = on ? 'Sound on' : 'Sound off';
    instance?.setSound(); update();
  }
  // In the list the view shows, the one `d` before or after the selection.
  function step(d) {
    const list = sel.view === 'moves' ? listed : sel.view === 'faces' ? [...sheet.mac, ...sheet.board].map(f => f.id) : pack.skits.map(s => s.id);
    const key = {moves: 'move', faces: 'face', moments: 'skit'}[sel.view];
    if (!list.length) return;
    const i = list.indexOf(sel[key]);
    change({[key]: list[(i + d + list.length) % list.length], ...(key === 'move' ? {over: ''} : {})});
    root.querySelector(`[data-${key}="${sel[key]}"]`)?.scrollIntoView({block: 'nearest'});
  }

  // ── URL ─────────────────────────────────────────────────────────────────
  // The address keeps the selection, so a link opens the same thing.
  function writeHash() {
    const p = new URLSearchParams({view: sel.view, mood: sel.mood});
    if (sel.view === 'moves') { p.set('move', sel.move); if (sel.over) p.set('over', sel.over); }
    if (sel.view === 'faces') p.set('face', sel.face);
    if (sel.view === 'moments') { p.set('skit', sel.skit); p.set('size', sel.size); if (sel.take) p.set('take', sel.take); }
    if (off.size) p.set('off', [...off].join(','));
    const hash = '#' + p.toString().replaceAll('%2C', ',');
    if (location.hash !== hash) history.replaceState(null, '', hash);
  }
  function readHash() {
    const p = new URLSearchParams(location.hash.slice(1)), out = {};
    if (VIEWS.includes(p.get('view'))) out.view = p.get('view');
    if (pack.moods.some(m => m.id === p.get('mood'))) out.mood = p.get('mood');
    if (moveOf(p.get('move'))) out.move = p.get('move');
    if (['idle', 'working', 'asleep'].includes(p.get('over'))) out.over = p.get('over');
    if (pack.faces.some(f => f.id === p.get('face'))) out.face = p.get('face');
    if (skitOf(p.get('skit'))) out.skit = p.get('skit');
    if (L.SIZES.some(s => s.id === p.get('size'))) out.size = p.get('size');
    if (p.get('take')) out.take = p.get('take');  // a take of the skit's, or none
    off.clear();
    for (const rule of (p.get('off') || '').split(',')) if (pack.motion.includes(rule)) off.add(rule);
    return out;
  }

  // ── Wiring ──────────────────────────────────────────────────────────────
  $('[data-mood]').addEventListener('change', e => change({mood: e.target.value}));
  for (const b of $$('[data-tab]')) b.addEventListener('click', () => change({view: b.dataset.tab}));
  $('[data-find]').addEventListener('input', () => renderMoves());
  $('[data-moves]').addEventListener('click', e => { const b = e.target.closest('[data-move]'); if (b) change({move: b.dataset.move, over: b.dataset.move === sel.move ? sel.over : ''}); });
  $('[data-over]').addEventListener('click', e => { const b = e.target.closest('[data-value]'); if (b) change({over: b.dataset.value}); });
  root.addEventListener('click', e => { const b = e.target.closest('[data-face]'); if (b && b.classList.contains('face')) change({face: b.dataset.face}); });
  $('[data-skits]').addEventListener('click', e => { const b = e.target.closest('[data-skit]'); if (b) change({skit: b.dataset.skit, take: ''}); });
  $('[data-size]').addEventListener('change', e => change({size: e.target.value, take: ''}, {replay: false}));
  $('[data-take]').addEventListener('change', e => change({take: e.target.value}, {replay: false}));
  $('[data-play]').addEventListener('click', () => playMoment());
  $('[data-answer]').addEventListener('click', answer);
  $('[data-miss]').addEventListener('click', miss);
  $('[data-motion]').addEventListener('click', e => { const b = e.target.closest('[data-rule]'); if (b) switchMotion(b.dataset.rule); });
  $('[data-sound]').addEventListener('click', () => setSound(!sound));
  $('[data-volume]').addEventListener('input', e => { volume = Number(e.target.value) / 100; instance?.setSound(); });
  document.addEventListener('keydown', e => {
    if (e.metaKey || e.ctrlKey || e.altKey || busyNow()) return;
    if (e.target.closest?.('input,select,textarea')) {
      if (e.key === 'Escape' || e.key === 'ArrowDown' && e.target.matches('[data-find]')) { e.target.blur(); if (e.key === 'ArrowDown') step(listed.indexOf(sel.move) < 0 ? 1 : 0); e.preventDefault(); }
      else if (e.key === 'Enter' && e.target.matches('[data-find]') && listed.length) { e.target.blur(); change({move: listed[0], over: ''}); }
      return;
    }
    const k = e.key.length === 1 ? e.key.toLowerCase() : e.key;
    if (['1', '2', '3'].includes(k)) change({view: VIEWS[Number(k) - 1]});
    else if (k === 'ArrowUp') step(-1);
    else if (k === 'ArrowDown') step(1);
    else if ((k === ' ' || k === 'Enter') && !e.target.closest?.('button')) play();
    else if (k === '/' && sel.view === 'moves') $('[data-find]').focus();
    else if (k === 'a') answer();
    else if (k === 'm') miss();
    else if (k === 's') setSound(!sound);
    else return;
    e.preventDefault();
  });
  window.addEventListener('hashchange', () => { Object.assign(sel, readHash()); render(); play(); });

  // The board loads with the address's selection, which then plays. For
  // browser checks and the console: the selection, the board's instance,
  // and the page's own buttons as calls.
  const ready = (async () => {
    Object.assign(sel, readHash());
    renderMoods();
    renderFaces();
    try { await load(); } catch (error) { $('[data-status]').textContent = error.message; }
    const key = name + '/' + entry.id;
    const made = adapters[key] || StudioBoard.adapter(name, entry.board);
    instance = made.create(ctx);
    instance.setSound();
    render();
    play();
    await instance.ready.catch(() => {});
  })();
  root.studio = {sel, ready, pack, get adapter() { return instance; }, get moment() { return moment; },
    get stills() { return stills; }, select: patch => change(patch), play, answer, miss, switchMotion};
})();
