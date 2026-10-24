// The studio's views beside the scene and the matrix (README.md): Transitions
// and References, on the board's own engine (board.js), and Review. studio.js
// makes each with its own calls (`api`); a view has enter(params) and state,
// for browser checks, and may have card() for when the character changes,
// leave(), and hash(params) for the address.
(() => {
  const h = (tag, props = {}, ...children) => {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(props)) k in e ? e[k] = v : e.setAttribute(k, v);
    e.append(...children.flat().filter(c => c != null && c !== false));
    return e;
  };
  const FRAME_MS = StudioBoard.FRAME_MS, served = location.protocol !== 'file:';
  const time = ms => `${ms > 0 ? '+' : ''}${ms} ms`;
  // The everyday transitions, which Transitions' Rank records on the board
  // and lists by their ratio, the jumpiest first: internal/tools/fluid/
  // transitions.jsonl's, so the two measures compare. Each a name, a start
  // and an end, as the address has them (mood/state, and /fact for a state
  // with one); a finish over working is asked in its own mood, as the
  // recording's is.
  const EVERYDAY = [
    ['to working', 'calm/idle', 'calm/working'],
    ['a mood change', 'calm/working', 'happy/working'],
    ['a finish', 'happy/working', 'excited/task_complete/success'],
    ['back to idle', 'excited/task_complete/success', 'happy/idle'],
    ['a poke', 'happy/idle', 'happy/poked'],
    ['a stroke', 'happy/idle', 'happy/gesture'],
    ['to asleep', 'happy/idle', 'happy/asleep'],
  ];

  // A transport: Play steps `show(i)` through n frames, 40 ms apart, looping; the range scrubs.
  function transport(root, show) {
    const [play, seek, label] = ['[data-go]', '[data-scrub]', '[data-at]'].map(s => root.querySelector(s));
    let n = 0, at = 0, timer = 0;
    const go = i => { at = i; seek.value = String(i); label.textContent = show(i) || ''; };
    const stop = () => { clearInterval(timer); timer = 0; play.textContent = 'Play'; };
    play.addEventListener('click', () => {
      if (timer) return stop();
      play.textContent = 'Stop';
      timer = setInterval(() => go((at + 1) % n), FRAME_MS);
    });
    seek.addEventListener('input', () => { stop(); go(Number(seek.value)); });
    return {stop, go, set length(count) { n = count; seek.max = String(Math.max(0, count - 1)); play.disabled = seek.disabled = count < 2; }};
  }
  // A board view's recordings: start() takes a turn and returns live(), true
  // until a newer turn starts or stop() (leaving the view) ends them all.
  function turns() {
    let n = 0;
    return {start() { const mine = ++n; return () => mine === n; }, stop() { n++; }};
  }
  // A board view's leave(): its recordings and its player stop.
  const leave = (player, ...all) => () => { for (const t of all) t.stop(); player.stop(); };
  // Recorded frames' pictures, let go of once they're replaced.
  const release = frames => { for (const f of frames) f.image?.close(); };
  // Why the board can't run (from file://, or with no build), inside its
  // pane, where the board would be; none to clear it.
  function paneNote(screen, text = '') {
    const note = screen.querySelector('.board-note') || screen.appendChild(h('p', {className: 'board-note'}));
    note.textContent = text;
    note.hidden = !text;
  }

  // The pickers for a cell: the pack's moods in their families, and the
  // board's states, one option for each fact a state has (success or failure…).
  function cellPicker(api, root) {
    const [mood, state] = root.querySelectorAll('select');
    const facts = api.data.states.facts;
    return {
      fill() {
        mood.replaceChildren(...api.families().map(f => h('optgroup', {label: f.label}, f.moods.map(m => h('option', {value: m.id}, api.title(m.id))))));
        state.replaceChildren(...api.stateGroups.map(g => h('optgroup', {label: g.label}, g.states.flatMap(s => facts[s.id]
          ? facts[s.id].options.map(o => h('option', {value: `${s.id}/${o.id}`}, `${api.stateInfo[s.id].label} · ${o.label.toLowerCase()}`))
          : [h('option', {value: s.id}, api.stateInfo[s.id].label)]))));
      },
      get() {
        const [id, fact] = state.value.split('/');
        return {mood: mood.value, state: id, ...(fact ? {[facts[id].name]: fact} : {})};
      },
      set(cell) {
        mood.value = cell.mood;
        const fact = facts[cell.state];
        state.value = fact ? `${cell.state}/${cell[fact.name] || fact.options[0].id}` : cell.state;
      },
    };
  }
  // A cell in the address: mood/state, and /fact for a state with one.
  const cellText = (api, c) => [c.mood, c.state, c[api.data.states.facts[c.state]?.name]].filter(Boolean).join('/');
  function cellFrom(api, text) {
    const [mood, state, fact] = (text || '').split('/'), f = api.data.states.facts[state];
    if (!api.packs[api.sel.pack].moods.some(m => m.id === mood) || !api.stateIds.includes(state)) return null;
    return {mood, state, ...(f && f.options.some(o => o.id === fact) ? {[f.name]: fact} : {})};
  }

  // The board these views run on: the character's, when it's a board, else
  // the pack's first, which entering picks.
  function onBoard(api, status) {
    const face = api.entry()?.board;
    if (face) return face;
    const first = api.boardCards()[0];
    if (first) api.switchCard(first);
    else status(`${api.packs[api.sel.pack].name} has no board face to run.`);
    return null;
  }

  // ── Transitions ─────────────────────────────────────────────────────────
  // A start and an end on the board: its frames 40 ms apart across the
  // change, and how much each changed from the one before; and Rank, the
  // everyday transitions recorded and ranked, the jumpiest first.
  function transitions(api) {
    const root = api.root.querySelector('[data-view="transitions"]'), $ = s => root.querySelector(s);
    const from = cellPicker(api, $('[data-from]')), to = cellPicker(api, $('[data-to]'));
    const s = {from: null, to: null, frames: [], changes: [], status: '', ranked: [], ranking: false, rankSaid: '', face: null};
    const status = text => { s.status = text; $('[data-said]').textContent = text; };
    const [strip, graphed] = [$('[data-strip]'), $('[data-graph]')], runs = turns(), ranks = turns();
    let shown = -1;  // the frame marked in the strip and the graph
    const player = transport($('[data-player]'), i => {
      const f = s.frames[i];
      if (!f) return '';
      StudioBoard.draw($('[data-frame]'), f.image);
      for (const list of [strip, graphed]) { list.children[shown]?.classList.remove('on'); list.children[i]?.classList.add('on'); }
      shown = i;
      return `${time(f.ms)} · ${f.change} px changed`;
    });
    const pair = (a, b) => `${api.title(a.mood)} · ${api.title(a.state)} → ${api.title(b.mood)} · ${api.title(b.state)}`;
    let filled = '';

    function graph() {
      const max = Math.max(1, ...s.changes), n = s.changes.length, zero = s.frames.findIndex(f => f.ms === 0);
      graphed.setAttribute('viewBox', `0 0 ${n} 100`);
      graphed.replaceChildren(...s.changes.map((c, i) => {
        const bar = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
        const height = Math.max(c ? 1 : 0, c / max * 96);
        Object.entries({x: i + .1, width: .8, y: 100 - height, height, 'data-i': i}).forEach(([k, v]) => bar.setAttribute(k, v));
        bar.classList.toggle('change', i === zero);
        bar.append(Object.assign(document.createElementNS('http://www.w3.org/2000/svg', 'title'), {textContent: `${time(s.frames[i].ms)}: ${c} px`}));
        return bar;
      }));
    }
    async function run() {
      const face = onBoard(api, status);
      if (!face) return;
      s.from = from.get(), s.to = to.get();
      api.writeHash();
      const live = runs.start(), what = `${pair(s.from, s.to)} on the ${face} board`;
      player.stop();
      status(`Recording ${what}…`);
      paneNote($('.screen'));
      let frames, n = 0;
      try {
        frames = await api.record({from: s.from, to: s.to, before: 5, after: 100, live,
          heard: () => { if (++n % 10 === 0 && live()) status(`Recording ${what}: ${n} of 106 frames…`); }});
      } catch (error) {
        if (live()) { status(''); paneNote($('.screen'), error.message); }
        return;
      }
      if (!live()) return release(frames || []);
      release(s.frames);
      s.frames = frames;
      s.changes = frames.map(f => f.change);
      const m = StudioBoard.summary(s.changes.slice(1));
      status(`${frames.length} frames, ${FRAME_MS} ms apart. Largest change ${m.largest} px at ${time(frames[m.at + 1].ms)}, ` +
        `median ${m.median} px: ${m.ratio.toFixed(1)}× the median.`);
      strip.replaceChildren(...frames.map((f, i) => h('button', {type: 'button', title: time(f.ms), 'data-i': i},
        StudioBoard.draw(h('canvas'), f.image, 72), h('small', {}, time(f.ms)))));
      graph();
      shown = -1;
      player.length = frames.length;
      player.go(frames.findIndex(f => f.ms === 0));
    }

    // Rank: each everyday transition recorded on the board, changes only,
    // and listed by its ratio as it comes, the jumpiest first.
    let ranking = () => false;  // the ranking's live(), while one runs
    function ranked() {
      $('[data-rank-said]').textContent = s.rankSaid;
      Object.assign($('[data-rank-progress]'), {hidden: !s.ranking, max: EVERYDAY.length, value: s.ranked.length});
      $('[data-jumpiest]').replaceChildren(...s.ranked.map(j => h('li', {},
        h('button', {type: 'button', 'data-name': j.name},
          h('strong', {}, `${j.ratio.toFixed(1)}×`), ` ${j.name}`,
          h('small', {}, `${cellText(api, j.from)} → ${cellText(api, j.to)}, the largest frame at ${time(j.at)}`)))));
    }
    async function rank() {
      const face = onBoard(api, status);
      if (!face) return;
      const live = ranking = ranks.start(), list = EVERYDAY.map(([name, a, b]) => ({name, from: cellFrom(api, a), to: cellFrom(api, b)}));
      const done = said => { Object.assign(s, {ranking: false, rankSaid: said}); ranked(); };
      Object.assign(s, {ranked: [], ranking: true, face});
      for (const [i, t] of list.entries()) {
        s.rankSaid = `Recording ${i + 1} of ${list.length} on the ${face} board: ${t.name}…`;
        ranked();
        let frames;
        try { frames = await api.record({from: t.from, to: t.to, before: 5, after: 100, live, pictures: false}); }
        catch (error) { if (live()) done(error.message); return; }
        if (!live()) return;
        const m = StudioBoard.summary(frames.slice(1).map(f => f.change));
        s.ranked = [...s.ranked, {...t, ...m, at: frames[m.at + 1].ms}].sort((a, b) => b.ratio - a.ratio);
      }
      done(`The everyday transitions on the ${face} board, the jumpiest first. Click one to record it here.`);
    }

    for (const select of root.querySelectorAll('[data-from] select, [data-to] select')) select.addEventListener('change', run);
    $('[data-rank]').addEventListener('click', rank);
    root.addEventListener('click', e => {
      const frame = e.target.closest('[data-strip] [data-i], [data-graph] [data-i]');
      if (frame) { player.stop(); player.go(Number(frame.dataset.i)); }
      const name = e.target.closest('[data-jumpiest] [data-name]')?.dataset.name, j = s.ranked.find(x => x.name === name);
      if (j) { from.set(j.from); to.set(j.to); run(); }
    });
    return {
      state: s,
      enter(params) {
        if (filled !== api.sel.pack) { from.fill(); to.fill(); filled = api.sel.pack; }
        from.set(cellFrom(api, params?.get('from')) || s.from || {mood: api.sel.mood, state: api.sel.state});
        to.set(cellFrom(api, params?.get('to')) || s.to || {mood: api.sel.mood, state: 'task_complete'});
        this.card();
      },
      card() {
        if (filled !== api.sel.pack) return this.enter();
        const face = onBoard(api, status);
        if (!face) return;
        if (s.face !== face) {
          ranks.stop();
          Object.assign(s, {ranked: [], ranking: false, face, rankSaid: `Rank records the everyday transitions on the ${face} board and ranks them by their largest frame against their median.`});
        } else if (s.ranking && !ranking()) Object.assign(s, {ranking: false, rankSaid: 'Ranking stopped when the view was left: Rank to start again.'});
        ranked();
        run();
      },
      leave: leave(player, runs, ranks),
      hash(p) { if (s.from) { p.set('from', cellText(api, s.from)); p.set('to', cellText(api, s.to)); } },
    };
  }

  // ── References ──────────────────────────────────────────────────────────
  // Each of the pack's references (CHARACTER.md §16): its status, kind,
  // note, reading and what it became; its media beside the board playing
  // its `show`, one scrubber for both, frame for frame (a video not yet
  // cut into frames seeks to the frame's time).
  function references(api) {
    const root = api.root.querySelector('[data-view="references"]'), $ = s => root.querySelector(s);
    const s = {id: null, file: 0, board: [], status: ''};
    const ref = () => api.packs[api.sel.pack].references.find(r => r.id === s.id), runs = turns();
    const status = text => { s.status = text; $('[data-board-caption]').textContent = text; };
    const player = transport($('[data-player]'), i => {
      const r = ref(), m = r?.media[s.file];
      if (!m) return '';
      if (m.frames) $('[data-media] img').src = `${r.path}frames/${m.file}/${String(Math.min(i, m.frames - 1)).padStart(4, '0')}.png`;
      else if (m.kind === 'video') $('[data-media] video').currentTime = i * FRAME_MS / 1000;
      const b = s.board[Math.min(i, s.board.length - 1)];
      if (b) StudioBoard.draw($('[data-board]'), b.image);
      return `${i * FRAME_MS} ms`;
    });

    function list() {
      const refs = api.packs[api.sel.pack].references;
      $('[data-list]').replaceChildren(...refs.map(r => h('button', {type: 'button', className: 'ref-card', 'aria-pressed': String(r.id === s.id), 'data-ref': r.id},
        h('strong', {}, r.id), h('span', {className: 'badge', 'data-level': r.status}, r.status), h('small', {}, `${r.kind} · ${r.note}`))));
      $('[data-none]').hidden = refs.length > 0;
      $('[data-detail]').hidden = !ref();
    }
    async function show() {
      list();
      const r = ref();
      if (!r) return;
      api.writeHash();
      $('[data-heading]').textContent = r.id;
      $('[data-kind]').textContent = r.kind === 'direct' ? 'Direct: make this' : 'Inspiration';
      $('[data-ref-note]').textContent = r.note;
      $('[data-reading]').replaceChildren(...(r.reading ? StudioMarkdown.render(r.reading, h)
        : [h('p', {}, 'Not read yet: boopctl reference read, then the reading in reading.md.')]));
      $('[data-became]').replaceChildren(...(r.became.length ? r.became.map(b => api.stateInfo[b.id]
        ? h('button', {type: 'button', className: 'chip', 'data-open': b.id}, `${b.what} ${b.id}`) : h('span', {className: 'chip'}, `${b.what} ${b.id}`)) : ['Nothing yet']));
      const showing = r.show || {mood: api.packs[api.sel.pack].default_mood, state: 'idle'};
      $('[data-show]').textContent = `${api.title(showing.mood)} · ${api.stateInfo[showing.state].label}` + (showing.anim ? `, then ${api.stateInfo[showing.anim].label}` : '');
      $('[data-files]').replaceChildren(...(r.media.length > 1 ? r.media.map((m, i) => h('button', {type: 'button', 'aria-pressed': String(i === s.file), 'data-file': i}, m.file)) : []));
      const m = r.media[s.file] || r.media[0], src = `${r.path}${m.file}`;
      $('[data-media]').replaceChildren(m.frames ? h('img', {alt: `${m.file}, frame by frame`})
        : m.kind === 'video' ? h('video', {src, controls: true, muted: true, preload: 'auto'}) : h('img', {src, alt: m.file}));
      $('[data-media-caption]').textContent = m.frames ? `${m.file}: ${m.frames} frames, ${FRAME_MS} ms apart` : `${m.file}, not cut into frames yet (boopctl reference read)`;
      release(s.board);
      s.board = [];
      $('[data-board]').getContext('2d').clearRect(0, 0, $('[data-board]').width, $('[data-board]').height);
      player.length = m.frames;
      player.go(0);
      const face = onBoard(api, status), live = runs.start();
      if (!face) return;
      status(`Recording it on the ${face} board…`);
      paneNote($('.screen'));
      let board;
      try {
        board = await api.record({from: {mood: showing.mood, state: showing.state},
          to: showing.anim ? {mood: showing.mood, state: showing.anim} : null, before: 0, after: Math.max(m.frames, 25) - 1, live});
      } catch (error) {
        if (live()) { status(''); paneNote($('.screen'), error.message); }
        return;
      }
      if (!live()) return release(board || []);
      s.board = board;
      status(`The ${face} board${showing.anim ? `, asked for ${api.stateInfo[showing.anim].label.toLowerCase()} at 0 ms` : ''}: ${s.board.length} frames, ${FRAME_MS} ms apart`);
      player.length = Math.max(m.frames, s.board.length);
      player.go(0);
    }

    $('[data-list]').addEventListener('click', e => { const b = e.target.closest('[data-ref]'); if (b) { s.id = b.dataset.ref; s.file = 0; show(); } });
    $('[data-files]').addEventListener('click', e => { const b = e.target.closest('[data-file]'); if (b) { s.file = Number(b.dataset.file); show(); } });
    $('[data-became]').addEventListener('click', e => {
      const b = e.target.closest('[data-open]'), r = ref();
      if (b) api.open({mood: r.show?.mood || api.sel.mood, state: b.dataset.open});
    });
    return {
      state: s,
      enter(params) {
        const refs = api.packs[api.sel.pack].references, id = params?.get('ref');
        s.id = refs.some(r => r.id === id) ? id : refs.some(r => r.id === s.id) ? s.id : refs[0]?.id || null;
        show();
      },
      card() { this.enter(); },
      leave: leave(player, runs),
      hash(p) { if (s.id) p.set('ref', s.id); },
    };
  }

  // ── Review ──────────────────────────────────────────────────────────────
  // What agents put up for review (review/queue.json), before and after,
  // with the verdicts so far; approve or ask for a change, which the
  // studio's server appends to review/notes.jsonl for the agents.
  function review(api) {
    const root = api.root.querySelector('[data-view="review"]'), $ = s => root.querySelector(s);
    const s = {notes: [], saving: false, drafts: {}, said: {}};
    const when = at => new Date(at).toLocaleString([], {dateStyle: 'medium', timeStyle: 'short'});

    function render() {
      const {queue} = api.packs[api.sel.pack].review;
      $('[data-none]').hidden = queue.length > 0;
      $('[data-file]').hidden = served;
      $('[data-items]').replaceChildren(...queue.map(item => {
        const notes = s.notes.filter(n => n.id === item.id);
        return h('article', {className: 'review-item', 'data-item': item.id},
          h('header', {}, h('h3', {}, item.title), h('span', {className: 'badge', 'data-level': item.status}, item.status), h('code', {}, item.id)),
          h('p', {}, item.what),
          h('div', {className: 'before-after'}, ['before', 'after'].map(k => item[k] && h('figure', {},
            h('img', {src: item[k], alt: `${item.title}, ${k}`}), h('figcaption', {}, k[0].toUpperCase() + k.slice(1))))),
          h('ol', {className: 'notes'}, notes.map(n => h('li', {'data-verdict': n.verdict},
            h('strong', {}, n.verdict === 'approve' ? 'Approved' : 'Change asked'), ` · ${when(n.at)}`, n.text && h('p', {}, n.text)))),
          h('form', {className: 'verdict'},
            h('label', {}, h('span', {className: 'visually-hidden'}, 'Comment'), h('textarea', {rows: 2, value: s.drafts[item.id] || '',
              placeholder: 'A comment for the agent: what to change, or why it works', disabled: !served})),
            h('div', {className: 'row'},
              h('button', {type: 'submit', className: 'primary', value: 'approve', disabled: !served || s.saving}, 'Approve'),
              h('button', {type: 'submit', value: 'change', disabled: !served || s.saving}, 'Ask for a change'),
              h('span', {className: 'said'}, s.said[item.id] || ''))));
      }));
    }
    async function load() {
      s.notes = api.packs[api.sel.pack].review.notes;
      render();
      if (!served) return;
      try {
        const got = await fetch(`/review?pack=${encodeURIComponent(api.sel.pack)}`, {cache: 'no-store'});
        if (got.ok) s.notes = await got.json();
      } catch { /* packs.js's notes, as charactergen last saw them */ }
      render();
    }
    root.addEventListener('input', e => { const item = e.target.closest('[data-item]'); if (item) s.drafts[item.dataset.item] = e.target.value; });
    root.addEventListener('submit', async e => {
      e.preventDefault();
      const item = e.target.closest('[data-item]').dataset.item, verdict = e.submitter.value, text = e.target.querySelector('textarea').value;
      if (verdict === 'change' && !text.trim()) { s.said[item] = 'Say what to change.'; return render(); }
      s.saving = true;
      render();
      try {
        const got = await fetch('/review', {method: 'POST', headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({pack: api.sel.pack, id: item, verdict, text})});
        if (!got.ok) throw Error(await got.text() || got.statusText);
        s.notes = [...s.notes, await got.json()];
        s.drafts[item] = '';
        s.said[item] = `Saved to characters/${api.sel.pack}/review/notes.jsonl.`;
      } catch (error) {
        s.said[item] = `Not saved (${error.message}): the studio's own server saves verdicts, node characters/studio/serve.cjs.`;
      }
      s.saving = false;
      render();
    });
    return {state: s, enter: load, card: load};
  }

  window.StudioViews = {transitions, references, review};
})();
