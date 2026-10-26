// The studio's views of the character itself (README.md): its Overview,
// Personality and Moods, its words (Signs, Diary, Voice), its tests (Evals,
// Demos) and the Stills its tests hold its faces to. Everything here is the
// pack's own, from charactergen.py's data (packs.js): the engine's lists
// only order it. studio.js makes each view with its own calls (`api`); a
// view has enter(params) and state, for browser checks, and may have card()
// for when the character changes, leave(), hash(params) and empty(), true
// when the pack has nothing for it.
(() => {
  const h = (tag, props = {}, ...children) => {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(props)) k in e ? e[k] = v : e.setAttribute(k, v);
    e.append(...children.flat().filter(c => c != null && c !== false));
    return e;
  };
  const served = location.protocol !== 'file:';
  const count = (n, one, many = one + 's') => `${n.toLocaleString()} ${n === 1 ? one : many}`;
  const sheet = (api, name) => api.root.querySelector(`[data-view="${name}"]`);
  const packOf = api => api.packs[api.sel.pack];
  // The voice's recorded takes: a take that's also a reply's words is in
  // the table again, as that reply, and counts once.
  const voiceOf = api => {
    const v = api.data.voices?.[packOf(api).voice];
    return v ? {...v, takes: v.takes.filter(t => t[2] !== 'reply')} : null;
  };
  const panel = (props, ...children) => h('section', {className: 'panel', ...props}, ...children);
  const heading = (text, about) => h('header', {className: 'panel-head'}, h('h3', {}, text), about && h('p', {}, about));
  const badge = (text, level) => h('span', {className: 'badge', ...(level ? {'data-level': level} : {})}, text);
  // A mood's chip, coloured by its family, that opens it in Moods.
  const moodChip = (api, id, props = {}) => {
    const b = h('button', {type: 'button', className: 'chip', 'data-goto-mood': id, ...props}, api.title(id));
    const hue = api.colourOf(id);
    if (hue) b.style.setProperty('--hue', hue);
    return b;
  };
  // Seconds as the page says them: "90-180" → "1½–3 min".
  function span(text) {
    const one = s => s < 60 ? `${s} s` : s < 3600 ? `${(s / 60).toString().replace('.5', '½')} min` : `${(s / 3600).toString().replace('.5', '½')} h`;
    const [lo, hi] = String(text).split('-').map(Number);
    if (!Number.isFinite(lo)) return text;
    if (!Number.isFinite(hi)) return one(lo);
    const a = one(lo), b = one(hi), unit = a.split(' ')[1];
    return unit === b.split(' ')[1] ? `${a.split(' ')[0]}–${b}` : `${a}–${b}`;
  }
  // Steering words, easier to read than the brain reads them: a paragraph
  // of many sentences as its first, then the rest as points; lists as they are.
  function readable(text) {
    return text.split(/\n\s*\n/).flatMap(block => {
      if (/^\s*[-*]\s/.test(block)) return StudioMarkdown.render(block, h);
      const sentences = block.split('\n').join(' ').split(/(?<=[.!?])\s+(?=[A-Z"])/);
      if (sentences.length < 3) return [h('p', {}, sentences.join(' '))];
      return [h('p', {}, sentences[0]), h('ul', {className: 'points'}, sentences.slice(1).map(x => h('li', {}, x)))];
    });
  }
  // The face switch for a view's own preview: the pack's previews, as the
  // Animations tab's cards are.
  function faceSwitch(api) {
    const cards = api.cards();
    if (cards.length < 2) return null;
    return h('div', {className: 'segmented small', role: 'group', 'aria-label': 'Preview'}, cards.map(c =>
      h('button', {type: 'button', 'data-card': c.id, 'aria-pressed': String(c.id === api.sel.card)}, c.label)));
  }
  // A view's live preview: one at a time, let go of when it's redrawn or left.
  function previewer(api) {
    let shown = null;
    return {
      show(thumb, selection) {
        this.drop();
        const got = api.preview(thumb, selection);
        if (got.error) thumb.append(h('p', {className: 'board-note'}, got.error));
        shown = {thumb, instance: got.instance};
      },
      drop() { if (shown) api.unpreview(shown.thumb, shown.instance); shown = null; },
    };
  }
  // The clicks every view shares: a mood chip opens it in Moods, a face switch changes the preview.
  function shared(api, root) {
    root.addEventListener('click', e => {
      const mood = e.target.closest('[data-goto-mood]'), card = e.target.closest('[data-card]'), go = e.target.closest('[data-go]');
      if (mood) api.go('moods', {mood: mood.dataset.gotoMood, face: null});
      else if (card) api.switchCard(card.dataset.card);
      else if (go) api.go(go.dataset.go);
    });
  }

  // ── Overview ────────────────────────────────────────────────────────────
  // The character on one card: its face, who it is, how much of each part
  // it has (each opens its tab), and what's missing.
  function overview(api) {
    const root = sheet(api, 'overview'), live = previewer(api);
    shared(api, root);
    function tiles() {
      const pack = packOf(api), voice = voiceOf(api);
      const stills = pack.stills.reduce((n, g) => n + g.stills.length, 0);
      const waiting = pack.review.queue.filter(i => i.status === 'in review').length;
      return [
        ['Who it is', [
          {go: 'personality', n: pack.personalities.length, label: 'Personalities', sub: (pack.talks || []).length ? `and ${count(pack.talks.length, 'talk level')}` : 'one way of talking'},
          {go: 'moods', n: pack.moods.length, label: 'Moods', sub: `in ${count(api.families().length, 'family', 'families')}`}]],
        ['How it looks', [
          {go: 'scene', n: api.cards().length, label: 'Faces', sub: api.cards().map(c => c.label).join(', ')},
          {go: 'stills', n: stills, label: 'Stills', sub: stills ? `golden frames, ${count(pack.stills.length, 'set')}` : 'no golden frames'}]],
        ['What it says', [
          {go: 'signs', n: pack.signs.length, label: 'Signs', sub: 'captions it holds up'},
          {go: 'diary', n: pack.diary.length, label: 'Diary lines', sub: 'one a day'},
          {go: 'voice', n: voice?.takes.length || 0, label: 'Voice takes', sub: !voice ? 'no voice' : pack.voice === api.sel.pack ? 'its own' : `${api.title(pack.voice)}'s voice`}]],
        ['What holds it', [
          {go: 'evals', n: pack.evals.length, label: 'Evals', sub: `${pack.evals.filter(e => e.always).length} always`},
          {go: 'demos', n: pack.demos.length, label: 'Demos', sub: 'scripted stretches of work'},
          {go: 'references', n: pack.references.length, label: 'References', sub: waiting ? `${waiting} up for review` : 'nothing up for review'}]],
      ];
    }
    // What a pack is missing, each with where to see it.
    function gaps() {
      const pack = packOf(api), ids = pack.moods.map(m => m.id), out = [];
      for (const e of pack.studio) {
        const n = Object.keys(e.wears || {}).length;
        if (n) out.push({text: `${e.label || pack.name} has art for ${ids.length - n} of ${ids.length} moods; the rest wear another's.`, go: 'matrix'});
      }
      const unsteered = ids.filter(id => !pack.steering[id]);
      if (unsteered.length) out.push({text: `${count(unsteered.length, 'mood')} ${unsteered.length === 1 ? 'has' : 'have'} no steering file, so ${unsteered.length === 1 ? 'it acts' : 'they act'} as ${api.title(pack.default_mood)}.`, go: 'moods'});
      const voice = voiceOf(api);
      if (voice) {
        const said = new Set(voice.takes.flatMap(t => t[5]));
        const mute = ids.filter(id => !said.has(id));
        if (mute.length) out.push({text: `${count(mute.length, 'mood')} ${mute.length === 1 ? 'has' : 'have'} no voice takes: ${mute.map(api.title).join(', ')}.`, go: 'voice'});
      }
      if (!pack.signs.length) out.push({text: 'No signs, so it never holds one up.', go: 'signs'});
      if (!pack.diary.length) out.push({text: 'No diary lines, so it keeps no diary.', go: 'diary'});
      const waiting = pack.review.queue.filter(i => i.status === 'in review');
      if (waiting.length) out.push({text: `${count(waiting.length, 'item')} ${waiting.length === 1 ? 'waits' : 'wait'} for your review.`, go: 'review'});
      return out;
    }
    function render() {
      live.drop();
      const pack = packOf(api), card = api.cards().find(c => c.id === api.sel.card);
      const thumb = h('div', {className: 'thumb face'});
      const fact = (term, ...text) => [h('dt', {}, term), h('dd', {}, ...text)];
      const found = gaps();
      root.replaceChildren(
        panel({className: 'panel hero'},
          h('figure', {className: 'hero-face'}, thumb,
            h('figcaption', {}, `${api.title(pack.default_mood)} · idle${card ? `, on ${card.label}` : ''}`), faceSwitch(api)),
          h('div', {className: 'hero-text'},
            h('p', {className: 'eyebrow'}, `Character pack · ${pack.id} · version ${pack.version}`),
            h('h2', {}, pack.name),
            h('p', {className: 'lead'}, pack.personalities[0]?.about || ''),
            h('dl', {className: 'facts'},
              fact('Mood', `Wakes up ${pack.startup_mood}, and settles back to ${pack.default_mood}.`),
              fact('Boards', ...Object.entries(pack.faces).flatMap(([b, f], i) => [i ? ', ' : '', h('strong', {}, f), ` on ${b}`]), '.'),
              Object.keys(pack.uses).length > 0 && fact('Borrows', Object.entries(pack.uses).map(([share, from]) => `${share.replace(/_/g, ' ')} from ${api.title(from)}`).join(', ') + '.')))),
        h('div', {className: 'tiles'}, tiles().map(([row, list]) => h('div', {className: 'tile-row'},
          h('h3', {}, row),
          list.map(t => h('button', {type: 'button', className: 'tile' + (t.n ? '' : ' none'), 'data-go': t.go},
            h('strong', {}, t.n ? t.n.toLocaleString() : '—'), h('span', {}, t.label), h('small', {}, t.sub)))))),
        panel({},
          heading('Worth a look', found.length ? 'What this character is missing, or is waiting on you.' : 'Nothing is missing.'),
          found.length > 0 && h('ul', {className: 'gaps'}, found.map(g =>
            h('li', {}, h('span', {}, g.text), h('button', {type: 'button', className: 'link', 'data-go': g.go}, 'Show'))))));
      live.show(thumb, {mood: pack.default_mood, state: 'idle'});
    }
    return {state: {}, enter: render, card: render, leave: () => live.drop()};
  }

  // ── Personality ─────────────────────────────────────────────────────────
  // Who it is: each personality with its settings in plain words, its words
  // and its examples; how much it says, picked in Settings, side by side;
  // and the guide.
  function personality(api) {
    const root = sheet(api, 'personality'), s = {id: null, all: {}};
    shared(api, root);
    const SETTINGS = {
      working_heartbeat: ['Checks in on a turn', v => `every ${span(v)}`],
      idle_heartbeat: ['Checks in while idle', v => `every ${span(v)}`],
      tool_uses: ['Tool uses it hears', v => `${v} ones`],
    };
    // An example: what happened (NOW) and, after →, what the character does.
    function example(text) {
      const [now, then] = text.split('\n→');
      return h('li', {className: 'example'},
        h('p', {className: 'when'}, now.replace(/^NOW:\s*/, '')),
        then && h('p', {className: 'then'}, '→ ', then.trim()));
    }
    function examples(key, list, shown = 6) {
      if (!list.length) return null;
      const all = s.all[key];
      return h('div', {className: 'examples-block'},
        h('h4', {}, `Examples · ${list.length}`),
        h('ol', {className: 'examples'}, (all ? list : list.slice(0, shown)).map(example)),
        list.length > shown && h('button', {type: 'button', className: 'link', 'data-more': key}, all ? 'Show fewer' : `Show all ${list.length}`));
    }
    function render() {
      const pack = packOf(api), list = pack.personalities;
      if (!list.some(p => p.id === s.id)) s.id = list[0]?.id || null;
      const p = list.find(x => x.id === s.id);
      root.replaceChildren(
        list.length > 1 && h('div', {className: 'segmented', role: 'group', 'aria-label': 'Personality'}, list.map(x =>
          h('button', {type: 'button', 'data-personality': x.id, 'aria-pressed': String(x.id === s.id)}, api.title(x.id)))),
        p ? panel({},
          h('header', {className: 'panel-head'}, h('p', {className: 'eyebrow'}, 'Personality, picked in Settings'), h('h2', {}, api.title(p.id)), h('p', {className: 'lead'}, p.about)),
          Object.keys(p.settings).length > 0 && h('div', {className: 'settings'}, Object.entries(p.settings).map(([k, v]) => {
            const [label, say] = SETTINGS[k] || [api.title(k), x => x];
            return h('div', {className: 'setting'}, h('small', {}, label), h('strong', {}, say(v)));
          })),
          h('div', {className: 'prose'}, readable(p.text)),
          examples('personality/' + p.id, p.examples))
          : panel({}, h('p', {className: 'empty-note'}, 'This pack names no personality.')),
        (pack.talks || []).length > 0 && panel({},
          heading('Talk', 'How much it says, picked in Settings: normal is the personality as written, and each of these goes on top of it.'),
          h('div', {className: 'talks'}, pack.talks.map(t => h('article', {className: 'talk'},
            h('h4', {}, api.title(t.id)),
            Object.keys(t.settings).length > 0 && h('div', {className: 'settings'}, Object.entries(t.settings).map(([k, v]) => {
              const [label, say] = SETTINGS[k] || [api.title(k), x => x];
              return h('div', {className: 'setting'}, h('small', {}, label), h('strong', {}, say(v)));
            })),
            h('div', {className: 'prose'}, readable(t.text)), examples('talk/' + t.id, t.examples, 3))))),
        pack.guide && h('details', {className: 'panel guide'},
          h('summary', {}, 'The guide', h('small', {}, ' · how it reads what happens, on every pass of the brain')),
          h('div', {className: 'prose'}, StudioMarkdown.render(pack.guide, h))));
    }
    root.addEventListener('click', e => {
      const p = e.target.closest('[data-personality]'), more = e.target.closest('[data-more]');
      if (p) { s.id = p.dataset.personality; render(); }
      if (more) { s.all[more.dataset.more] = !s.all[more.dataset.more]; render(); }
    });
    return {state: s, enter: render, card: render};
  }

  // ── Moods ───────────────────────────────────────────────────────────────
  // Every mood in its family, and the one picked: its face, the moods it can
  // move to (its map), and what its steering says it does, what moves it on
  // and when it fades.
  function moods(api) {
    const root = sheet(api, 'moods'), live = previewer(api), s = {};
    shared(api, root);
    const PARTS = [['about', 'What it is'], ['faces', 'Faces'], ['says', 'Says'], ['acts', 'How it acts'], ['stays', 'Stays through']];
    // The moods it can move to: ordinary moves on the inner ring, dramatic on the outer.
    function map(mood) {
      const W = 420, H = 330, cx = W / 2, cy = H / 2 - 4, ns = 'http://www.w3.org/2000/svg';
      const el = (tag, attrs, text) => { const e = document.createElementNS(ns, tag); for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v); if (text) e.textContent = text; return e; };
      const svg = el('svg', {viewBox: `0 0 ${W} ${H}`, class: 'map', role: 'img', 'aria-label': `The moods ${api.title(mood.id)} can move to`});
      const rings = [['ordinary', 92, 0], ['dramatic', 145, .5]];
      const nodes = [];
      for (const [kind, r, offset] of rings) {
        const ids = mood.moves?.[kind] || [];
        ids.forEach((id, i) => {
          const a = -Math.PI / 2 + (i + offset) * 2 * Math.PI / ids.length;
          nodes.push({id, kind, x: cx + Math.cos(a) * r * 1.25, y: cy + Math.sin(a) * r});
        });
      }
      for (const n of nodes) svg.append(el('line', {x1: cx, y1: cy, x2: n.x, y2: n.y, class: 'edge ' + n.kind}));
      const node = (id, x, y, big) => {
        const g = el('g', {class: 'node' + (big ? ' here' : ''), 'data-goto-mood': id, tabindex: big ? -1 : 0, role: big ? 'presentation' : 'button'});
        g.append(el('circle', {cx: x, cy: y, r: big ? 13 : 8, fill: api.colourOf(id) || 'var(--muted)'}));
        g.append(el('text', {x, y: y + (big ? 30 : 21), 'text-anchor': 'middle'}, api.title(id)));
        svg.append(g);
      };
      for (const n of nodes) node(n.id, n.x, n.y, false);
      node(mood.id, cx, cy, true);
      return svg;
    }
    function render() {
      live.drop();
      const pack = packOf(api), mood = pack.moods.find(m => m.id === api.sel.mood) || pack.moods.find(m => m.id === pack.default_mood);
      const steer = pack.steering[mood.id], family = api.families().find(f => f.moods.includes(mood));
      const from = pack.moods.filter(m => ['ordinary', 'dramatic'].some(k => m.moves?.[k]?.includes(mood.id)));
      const voice = voiceOf(api), takes = voice ? voice.takes.filter(t => t[5].includes(mood.id)).length : 0;
      const expects = pack.evals.filter(e => expectsMood(e, mood.id)).length;
      const wears = api.shows(mood.id);
      const thumb = h('div', {className: 'thumb face'});
      root.replaceChildren(h('div', {className: 'moods-grid'},
        panel({className: 'panel mood-pick'}, heading('Moods', count(pack.moods.length, 'mood') + ', in their families'),
          api.families().map(f => h('div', {className: 'group'}, h('div', {className: 'group-label'}, f.label),
            h('div', {className: 'chips'}, f.moods.map(m => moodChip(api, m.id, {'aria-pressed': String(m.id === mood.id)})))))),
        h('div', {className: 'mood-detail'},
          panel({},
            h('header', {className: 'mood-head'},
              h('span', {className: 'dot', style: `--hue:${api.colourOf(mood.id) || '#888'}`}),
              h('h2', {}, api.title(mood.id)),
              family && badge(family.label),
              mood.id === pack.default_mood && badge('resting mood'),
              mood.id === pack.startup_mood && badge('wakes up in it')),
            h('p', {className: 'lead'}, mood.meaning || ''),
            h('div', {className: 'mood-visual'},
              h('figure', {className: 'mood-face'}, thumb,
                h('figcaption', {}, wears !== mood.id ? `No art of its own here: it wears ${api.title(wears)}.` : mood.face || 'Idle, in this mood.'),
                faceSwitch(api)),
              h('figure', {className: 'mood-map'}, map(mood),
                h('figcaption', {}, h('span', {className: 'key ordinary'}), 'ordinary move ', h('span', {className: 'key dramatic'}), 'dramatic move'))),
            from.length > 0 && h('div', {className: 'from'}, h('small', {}, `Reached from ${from.length}:`), from.map(m => moodChip(api, m.id, {className: 'chip small'})))),
          steer ? panel({},
            heading('What it does', 'From its steering file, which the brain reads while it is in this mood.'),
            h('dl', {className: 'parts'}, PARTS.filter(([k]) => steer[k]).flatMap(([k, label]) => [h('dt', {}, label), h('dd', {}, steer[k])])),
            steer.leaves?.length > 0 && h('div', {className: 'leaves-block'}, h('h4', {}, 'Leaves for'),
              h('ul', {className: 'leaves'}, steer.leaves.map(l => h('li', {},
                h('span', {className: 'to'}, l.to.map(id => moodChip(api, id, {className: 'chip small'}))), h('span', {}, l.when))))),
            steer.fades && h('p', {className: 'fades'}, h('strong', {}, 'Fades. '), steer.fades.replace(/^Fades\s*/, '').replace(/^\w/, c => c.toUpperCase())))
            : panel({}, h('p', {className: 'empty-note'}, `No steering file of its own: it acts as ${api.title(pack.default_mood)}.`)),
          h('div', {className: 'row links'},
            h('button', {type: 'button', 'data-go': 'scene'}, 'See it in every state →'),
            voice && h('button', {type: 'button', 'data-voice': mood.id}, `${count(takes, 'voice take')} →`),
            h('button', {type: 'button', 'data-evals': mood.id, disabled: !expects}, `${count(expects, 'eval')} expect it →`)))));
      live.show(thumb, {mood: mood.id, state: 'idle'});
    }
    root.addEventListener('click', e => {
      const v = e.target.closest('[data-voice]'), ev = e.target.closest('[data-evals]');
      if (v) api.go('voice', null, new URLSearchParams({takes: v.dataset.voice}));
      if (ev) api.go('evals', null, new URLSearchParams({expects: ev.dataset.evals}));
    });
    root.addEventListener('keydown', e => { if (e.key === 'Enter' && e.target.closest('[data-goto-mood]')) e.target.closest('[data-goto-mood]').dispatchEvent(new MouseEvent('click', {bubbles: true})); });
    return {state: s, enter: render, card: render, leave: () => live.drop(), mood: render};
  }
  // Whether a scenario expects a mood: its react or its mood, at a step.
  const expectsMood = (scenario, id) => (scenario.steps || []).some(st => ['react', 'mood'].some(k => String(st.expect?.[k] || '').split('|').includes(id)));

  // ── Signs ───────────────────────────────────────────────────────────────
  // Each caption it may hold up, as a sign, with your words filled in, and
  // the tags the prompt's reading must have for it.
  function signs(api) {
    const root = sheet(api, 'signs'), s = {words: 'it broke', tag: ''};
    function fill(text) { return text.replaceAll('{words}', s.words).replaceAll('{WORDS}', s.words.toUpperCase()); }
    function render() {
      const list = packOf(api).signs;
      const tags = [...new Set(list.flatMap(x => x.tags))];
      if (s.tag && !tags.includes(s.tag)) s.tag = '';
      const shown = list.filter(x => !s.tag || x.tags.includes(s.tag));
      root.replaceChildren(panel({},
        heading('Signs', `What ${packOf(api).name} may hold up when it reacts to your prompt. Your own words come first, then captions whose tags all match how the prompt reads, then the rest: at most six are offered.`),
        !list.length ? h('p', {className: 'empty-note'}, 'This pack has no signs.') : [
          h('div', {className: 'controls'},
            h('label', {className: 'field'}, h('span', {}, 'Your words'), h('input', {type: 'text', value: s.words, maxLength: 18, 'data-words': ''})),
            h('div', {className: 'chips'}, ['', ...tags].map(t => h('button', {type: 'button', className: 'chip plain', 'data-tag': t, 'aria-pressed': String(t === s.tag)}, t || 'All')))),
          h('div', {className: 'placards'}, shown.map((x, i) => h('figure', {className: 'placard', style: `--tilt:${(i % 3 - 1) * 1.2}deg`},
            h('div', {className: 'sign'}, fill(x.text)),
            h('figcaption', {}, x.tags.length ? x.tags.map(t => badge(t)) : h('small', {}, 'any prompt')))))]));
    }
    root.addEventListener('input', e => { if (e.target.matches('[data-words]')) { s.words = e.target.value || 'it broke'; for (const [i, el] of root.querySelectorAll('.sign').entries()) el.textContent = fill(packOf(api).signs.filter(x => !s.tag || x.tags.includes(s.tag))[i].text); } });
    root.addEventListener('click', e => { const t = e.target.closest('[data-tag]'); if (t) { s.tag = t.dataset.tag; render(); } });
    return {state: s, enter: render, card: render, empty: () => !packOf(api).signs.length};
  }

  // ── Diary ───────────────────────────────────────────────────────────────
  // Each line it may write about yesterday, filled in for a sample day, with
  // the tags the day must have.
  function diary(api) {
    const root = sheet(api, 'diary');
    const DAY = {weekday: 'Tuesday', turns: 12, failed: 3, longest: 42, thread: 'search index', pokes: 7};
    const fill = text => text.replace(/\{(\w+)\}/g, (m, k) => k in DAY ? String(DAY[k]) : m);
    function render() {
      const list = packOf(api).diary;
      root.replaceChildren(panel({},
        heading('Diary', `The lines ${packOf(api).name} may write about yesterday, one a day, on the brain's first pass of a new day. Here they're filled in for a sample day: ${DAY.weekday}, ${DAY.turns} turns, ${DAY.failed} failed, the longest ${DAY.longest} min on "${DAY.thread}", ${DAY.pokes} pokes.`),
        !list.length ? h('p', {className: 'empty-note'}, 'This pack keeps no diary.')
          : h('ol', {className: 'diary'}, list.map(x => h('li', {title: x.text},
            h('div', {className: 'when'}, x.tags.length ? x.tags.map(t => badge(t)) : h('small', {}, 'any day')),
            h('p', {}, fill(x.text)))))));
    }
    return {state: DAY, enter: render, card: render, empty: () => !packOf(api).diary.length};
  }

  // ── Voice ───────────────────────────────────────────────────────────────
  // How many takes it has in each mood, of each kind; a cell's takes, each
  // played from the voice file, which the studio's server reads in part.
  const voiceFiles = {};
  async function bytes(url, from, to) {
    const stop = new AbortController();
    const got = await fetch(url, {headers: {Range: `bytes=${from}-${to}`}, signal: stop.signal});
    if (got.status !== 206) {
      stop.abort();  // not the whole 30 MB
      throw Error('the server sends the whole voice file, not a part of it');
    }
    return new DataView(await got.arrayBuffer());
  }
  // The voice file's index (voicegen's layout: a 64-byte header, then a
  // record per take), fetched once: each take's samples, by its id.
  function voiceIndex(url) {
    return voiceFiles[url] ??= (async () => {
      const head = await bytes(url, 0, 63), text = new TextDecoder();
      if (text.decode(new Uint8Array(head.buffer, 0, 8)) !== 'BOOPVOX1') throw Error('not a voice file');
      const n = head.getUint32(24, true), size = head.getUint32(28, true), at = head.getUint32(32, true), rate = head.getUint32(36, true);
      const index = await bytes(url, at, at + n * size - 1), takes = new Map();
      for (let i = 0; i < n; i++) {
        const o = i * size, id = new Uint8Array(index.buffer, o, 72);
        takes.set(text.decode(id.subarray(0, id.indexOf(0) < 0 ? 72 : id.indexOf(0))), {at: index.getUint32(o + 108, true), length: index.getUint32(o + 112, true)});
      }
      return {rate, takes};
    })();
  }
  function voice(api) {
    const root = sheet(api, 'voice'), s = {mood: null, kind: null, find: '', said: '', playing: null};
    let audio = null, source = null;
    async function play(id) {
      const v = voiceOf(api);
      try {
        const {rate, takes} = await voiceIndex(v.file), take = takes.get(id);
        if (!take) throw Error(`no take ${id} in the voice file`);
        const raw = await bytes(v.file, take.at, take.at + take.length - 1);
        audio ??= new AudioContext();
        const buffer = audio.createBuffer(1, take.length, rate), out = buffer.getChannelData(0);
        for (let i = 0; i < take.length; i++) out[i] = (raw.getUint8(i) - 128) / 128;
        source?.stop();
        source = audio.createBufferSource();
        source.buffer = buffer;
        source.connect(audio.destination);
        source.start();
        s.playing = id; s.said = '';
      } catch (error) {
        delete voiceFiles[v.file];
        s.said = `Couldn't play it: ${error.message}.`;
      }
      root.querySelector('[data-said]').textContent = s.said;
    }
    function render() {
      const pack = packOf(api), v = voiceOf(api);
      if (!v) { root.replaceChildren(panel({}, heading('Voice'), h('p', {className: 'empty-note'}, `${pack.name} has no voice: its reactions play faces and sound effects only.`))); return; }
      const kinds = Object.entries(v.takes.reduce((n, t) => (n[t[4]] = (n[t[4]] || 0) + 1, n), {})).sort((a, b) => b[1] - a[1]).map(([k]) => k);
      const cell = (mood, kind) => v.takes.filter(t => t[5].includes(mood) && t[4] === kind).length;
      const most = Math.max(1, ...pack.moods.flatMap(m => kinds.map(k => cell(m.id, k))));
      if (s.mood && !pack.moods.some(m => m.id === s.mood)) s.mood = null;
      const find = s.find.trim().toLowerCase();
      const shown = find ? v.takes.filter(t => t[1].toLowerCase().includes(find) || t[0].includes(find))
        : v.takes.filter(t => (!s.mood || t[5].includes(s.mood)) && (!s.kind || t[4] === s.kind));
      api.writeHash();
      const what = find ? `matching "${s.find.trim()}"` : [s.mood && api.title(s.mood), s.kind && `${s.kind}s`].filter(Boolean).join(' · ') || 'all';
      root.replaceChildren(panel({},
          heading('Voice', `${count(v.takes.length, 'recorded take')}, ${pack.voice === api.sel.pack ? 'its own' : `${api.title(pack.voice)}'s voice, which ${pack.name} uses`} (version ${v.version}). A take plays in every mood it's listed for. Pick a cell to hear its takes.`),
          h('div', {className: 'voice-layout'},
          h('div', {className: 'take-grid-scroll'}, h('table', {className: 'take-grid'},
            h('thead', {}, h('tr', {}, h('th', {}), kinds.map(k => h('th', {}, h('button', {type: 'button', className: 'link', 'data-kind': k, 'aria-pressed': String(s.kind === k && !s.mood)}, k))))),
            h('tbody', {}, api.families().flatMap(f => [
              h('tr', {}, h('th', {className: 'family', colSpan: kinds.length + 1}, f.label)),
              ...f.moods.map(m => h('tr', {}, h('th', {}, h('button', {type: 'button', className: 'link mood-row', 'data-row': m.id, 'aria-pressed': String(s.mood === m.id && !s.kind)}, api.title(m.id))), kinds.map(k => {
                const n = cell(m.id, k);
                return h('td', {}, h('button', {type: 'button', className: 'heat' + (n ? '' : ' none'), style: `--heat:${(n / most).toFixed(2)}`,
                  'data-cell': `${m.id}/${k}`, 'aria-pressed': String(s.mood === m.id && s.kind === k), title: `${api.title(m.id)}, ${count(n, k)}`}, n || '·'));
              })))])))),
          h('div', {className: 'take-column'},
          h('div', {className: 'controls'},
            h('h3', {}, `Takes · ${what} · ${shown.length.toLocaleString()}`),
            h('label', {className: 'field grow'}, h('span', {className: 'visually-hidden'}, 'Find a take'), h('input', {type: 'search', placeholder: 'Find a take by its words', value: s.find, 'data-find': ''})),
            (s.mood || s.kind) && !find && h('button', {type: 'button', 'data-clear': ''}, 'Show all')),
          h('p', {className: 'hint', 'data-said': ''}, served ? s.said : 'Opened from a file, the page can\'t read the voice file: open it from the studio\'s server to hear the takes.'),
          h('ul', {className: 'takes'}, shown.slice(0, 200).map(t => h('li', {},
            h('button', {type: 'button', className: 'icon play', 'data-play': t[0], disabled: !served, 'aria-label': `Play ${t[1]}`}, '▶'),
            h('strong', {}, t[1]),
            h('span', {className: 'kind'}, t[4]),
            h('small', {}, `${t[2]}: ${t[3]}`),
            t[6] && badge(t[6] === 'success' ? 'on a success' : 'on a failure', t[6] === 'success' ? 'approved' : 'changes'),
            h('small', {className: 'ms'}, `${(t[7] / 1000).toFixed(1)} s`)))),
          shown.length > 200 && h('p', {className: 'hint'}, `And ${(shown.length - 200).toLocaleString()} more: pick a cell or find by words.`)))));
    }
    // The picked mood's row, scrolled to in the grid.
    function reveal() {
      const box = root.querySelector('.take-grid-scroll'), row = box?.querySelector('[aria-pressed="true"]')?.closest('tr');
      if (row) box.scrollTop += row.getBoundingClientRect().top - box.getBoundingClientRect().top - box.clientHeight / 3;
    }
    root.addEventListener('click', e => {
      const c = e.target.closest('[data-cell]'), k = e.target.closest('[data-kind]'), p = e.target.closest('[data-play]'), r = e.target.closest('[data-row]');
      if (c) { [s.mood, s.kind] = c.dataset.cell.split('/'); s.find = ''; render(); }
      else if (r) { s.mood = r.dataset.row; s.kind = null; s.find = ''; render(); }
      else if (k) { s.mood = null; s.kind = k.dataset.kind; s.find = ''; render(); }
      else if (e.target.closest('[data-clear]')) { s.mood = s.kind = null; render(); }
      else if (p) play(p.dataset.play);
    });
    root.addEventListener('change', e => { if (e.target.matches('[data-find]')) { s.find = e.target.value; render(); } });
    root.addEventListener('keydown', e => { if (e.key === 'Enter' && e.target.matches('[data-find]')) { s.find = e.target.value; render(); } });
    return {
      state: s,
      // A mood's takes, from Moods or the address, and a kind of them.
      enter(params) {
        if (params?.has('takes') || params?.has('kind')) {
          const pack = packOf(api);
          s.mood = pack.moods.some(m => m.id === params.get('takes')) ? params.get('takes') : null;
          s.kind = params.get('kind') || null;
          s.find = '';
        }
        render();
        reveal();
      },
      hash(p) { if (s.mood) p.set('takes', s.mood); if (s.kind) p.set('kind', s.kind); },
      card() { s.mood = s.kind = null; render(); },
      leave() { source?.stop(); },
      empty: () => !voiceOf(api),
    };
  }

  // ── Evals ───────────────────────────────────────────────────────────────
  // Each scenario the brain is held to: what it checks, why, and its steps,
  // each event with what it expects.
  function evals(api) {
    const root = sheet(api, 'evals'), s = {find: '', only: '', mood: null, open: new Set()};
    const EXTRA = ['prompt', 'message', 'words', 'topic'];
    function step(st) {
      const said = EXTRA.filter(k => typeof st[k] === 'string').map(k => `“${st[k]}”`).join(' ');
      return h('li', {className: 'step'},
        h('span', {className: 'at'}, st.at || ''),
        h('div', {}, h('p', {}, h('strong', {}, st.event), st.failed ? ' · failed' : '', said && h('span', {className: 'said'}, ' ', said)),
          st.expect && h('div', {className: 'expect'}, Object.entries(st.expect).map(([k, v]) =>
            h('span', {className: 'pill'}, h('small', {}, k), ' ', String(v).split('|').join(' / '))))));
    }
    function render() {
      api.writeHash();
      const pack = packOf(api), find = s.find.trim().toLowerCase();
      const list = pack.evals.filter(e => (!s.only || (s.only === 'always' ? e.always : !e.always))
        && (!s.mood || expectsMood(e, s.mood)) && (!find || `${e.name} ${e.case}`.toLowerCase().includes(find)));
      root.replaceChildren(panel({},
        heading('Evals', `Each scenario plays events to the brain, with ${pack.name}'s steering, and checks what it picks. "Always" ones are its character, run three times; run them all with make eval, which needs Jev's key.`),
        !pack.evals.length ? h('p', {className: 'empty-note'}, 'This pack has no eval scenarios.') : [
          h('div', {className: 'controls'},
            h('label', {className: 'field grow'}, h('span', {className: 'visually-hidden'}, 'Find a scenario'), h('input', {type: 'search', placeholder: 'Find a scenario', value: s.find, 'data-find': ''})),
            h('div', {className: 'chips'},
              [['', 'All'], ['always', 'Always'], ['rest', 'The rest']].map(([v, t]) => h('button', {type: 'button', className: 'chip plain', 'data-only': v, 'aria-pressed': String(s.only === v)}, t)),
              s.mood && h('button', {type: 'button', className: 'chip plain', 'aria-pressed': 'true', 'data-unmood': ''}, `Expects ${api.title(s.mood)} ✕`))),
          h('p', {className: 'hint'}, `${count(list.length, 'scenario')} of ${pack.evals.length}`),
          h('div', {className: 'eval-list'}, list.map(e => h('details', {className: 'eval', open: s.open.has(e.id), 'data-eval': e.id},
            h('summary', {},
              h('span', {className: 'num'}, e.id.match(/^\d+/)?.[0] || ''),
              h('span', {className: 'name'}, e.name),
              e.always && badge('always', 'approved'),
              e.gap && badge('known gap', 'in review'),
              e.personality && badge(e.personality),
              e.talk && badge(e.talk),
              e.mood && badge(`starts ${e.mood}`),
              h('small', {}, count((e.steps || []).length, 'step'))),
            h('div', {className: 'eval-body'},
              h('p', {}, e.case),
              h('ol', {className: 'steps'}, (e.steps || []).map(step)),
              e.why && h('p', {className: 'why'}, h('strong', {}, 'Why. '), e.why),
              window.StudioPrompts?.scenarios?.[e.id] && window.StudioPrompts.pack === api.sel.pack
                && h('p', {}, h('a', {href: '#', 'data-prompts': e.id}, 'What the brain reads and answers'))))))]));
    }
    root.addEventListener('click', e => {
      const o = e.target.closest('[data-only]');
      if (o) { s.only = o.dataset.only; render(); }
      if (e.target.closest('[data-unmood]')) { s.mood = null; render(); }
      const prompts = e.target.closest('[data-prompts]');
      if (prompts) { e.preventDefault(); api.go('brain', null, new URLSearchParams({scenario: prompts.dataset.prompts})); }
    });
    root.addEventListener('toggle', e => { const d = e.target.closest?.('[data-eval]'); if (d) d.open ? s.open.add(d.dataset.eval) : s.open.delete(d.dataset.eval); }, true);
    root.addEventListener('change', e => { if (e.target.matches('[data-find]')) { s.find = e.target.value; render(); } });
    root.addEventListener('keydown', e => { if (e.key === 'Enter' && e.target.matches('[data-find]')) { s.find = e.target.value; render(); } });
    return {
      state: s,
      // The scenarios that expect a mood, from Moods or the address.
      enter(params) {
        if (params?.has('expects')) s.mood = packOf(api).moods.some(m => m.id === params.get('expects')) ? params.get('expects') : null;
        render();
      },
      hash(p) { if (s.mood) p.set('expects', s.mood); },
      card() { s.mood = null; s.open.clear(); render(); },
      empty: () => !packOf(api).evals.length,
    };
  }

  // ── Demos ───────────────────────────────────────────────────────────────
  // Each scripted stretch of work, told as its steps: the agent, you, and
  // what the brain answers.
  function demos(api) {
    const root = sheet(api, 'demos'), s = {open: null};
    function line(st) {
      const name = packOf(api).name;
      if (st.agent) {
        const what = {prompt: `You ask: “${st.text}”`, read: `Reads ${st.file}`, edit: `Edits ${st.file}`,
          run: `Runs ${st.cmd}${st.ask ? ', asking you first' : ''}${st.fails ? ', and it fails' : ''}`,
          reply: `Replies${st.fails ? ', failing' : ''}: “${st.text}”`, todo: `Writes its to-do list (${st.todos})`,
          review: `Sends a helper: ${st.task || ''}`, compact: 'Compacts its context'}[st.agent] || st.agent;
        return ['agent', 'Agent', what];
      }
      if (st.you) {
        const what = {poke: 'You poke it', press: 'You press BOOT', hold: 'You hold a finger on the screen',
          talk: `You say “${st.text}”`, back: `You come back after ${st.minutes || 60} min`}[st.you] || `You ${st.you}`;
        return ['you', 'You', what];
      }
      if (st.brain) {
        const b = st.brain, bits = [b['react.face'] && `${b['react.face']} face`, b['react.move'], b['react.intensity'],
          b['say'] && (b['say'] === 'none' ? 'in silence' : b['say'] === 'swear' ? 'swears' : `says ${b['say']}`), b['react.sign'] && `sign “${b['react.sign']}”`].filter(Boolean);
        return ['brain', `${name}`, bits.join(' · ') + (st.mood ? ` · mood → ${st.mood}` : '')];
      }
      return ['other', '', Object.entries(st).map(([k, v]) => `${k} ${typeof v === 'object' ? JSON.stringify(v) : v}`).join(' · ')];
    }
    function render() {
      const list = packOf(api).demos;
      root.replaceChildren(panel({},
        heading('Demos', 'Short scripted stretches of work it lives through: an agent at a task, you poking and talking, and what its brain answers. Each plays in the simulator, on a board, or with a real agent.'),
        !list.length ? h('p', {className: 'empty-note'}, 'This pack has no demos.')
          : h('div', {className: 'demo-list'}, list.map(d => h('details', {className: 'demo', open: s.open === d.id, 'data-demo': d.id},
            h('summary', {}, h('strong', {}, d.title), h('small', {}, `${d.id} · ${count(d.steps.length, 'step')}`), d.about && h('p', {}, d.about)),
            h('ol', {className: 'timeline'}, d.steps.map(st => { const [who, label, text] = line(st); return h('li', {'data-who': who}, h('span', {className: 'who'}, label), h('p', {}, text), st.note && badge(st.note)); })),
            h('p', {className: 'hint'}, 'Watch it with ', h('code', {}, `make demo NAME=${d.id}`), ', with this pack staged.'))))));
    }
    root.addEventListener('toggle', e => { const d = e.target.closest?.('[data-demo]'); if (d?.open) s.open = d.dataset.demo; }, true);
    return {state: s, enter: render, card: () => { s.open = null; render(); }, empty: () => !packOf(api).demos.length};
  }

  // ── Stills ──────────────────────────────────────────────────────────────
  // The frames its tests hold its faces to (tests/golden-*), by group:
  // what each face draws, occasions and gestures among them.
  function stills(api) {
    const root = sheet(api, 'stills'), s = {group: ''};
    function render() {
      const groups = packOf(api).stills, sets = new Set(groups.map(g => g.set)).size;
      const key = g => `${g.set}/${g.group}`;
      if (!groups.some(g => key(g) === s.group)) s.group = groups[0] ? key(groups[0]) : '';
      const g = groups.find(x => key(x) === s.group);
      api.writeHash();
      root.replaceChildren(panel({},
        heading('Stills', 'The frames its tests hold its faces to, checked in beside the pack: when one of these changes, the face changed.'),
        !groups.length ? h('p', {className: 'empty-note'}, 'This pack has no golden frames.') : [
          h('div', {className: 'chips'}, groups.map(x => h('button', {type: 'button', className: 'chip plain', 'data-group': key(x), 'aria-pressed': String(key(x) === s.group)},
            `${sets > 1 ? x.set + ' · ' : ''}${api.title(x.group)}`, h('span', {className: 'to'}, String(x.stills.length))))),
          h('div', {className: 'stills'}, g.stills.map(x => h('figure', {}, h('img', {src: x.path, alt: x.name, loading: 'lazy'}), h('figcaption', {}, x.name.replace(/_/g, ' ')))))]));
    }
    root.addEventListener('click', e => { const b = e.target.closest('[data-group]'); if (b) { s.group = b.dataset.group; render(); } });
    return {
      state: s,
      enter(params) { if (params?.get('group')) s.group = params.get('group'); render(); },
      card: render,
      empty: () => !packOf(api).stills.length,
      hash(p) { if (s.group) p.set('group', s.group); },
    };
  }

  window.StudioCharacterViews = {overview, personality, moods, signs, diary, voice, evals, demos, stills};
  // The Map says a personality's settings as Personality does.
  window.StudioSpan = span;
})();
