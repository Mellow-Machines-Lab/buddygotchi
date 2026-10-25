// The studio's views of what the character does and why (README.md): the
// Map, everything that puts something on the screen, by what sets it off
// and who decides it (behavior.json, which charactergen fills with the
// numbers from their code and the brain's wakes), and the Brain, what Jev
// is asked and reads, pass by pass, in each eval scenario (prompts.js,
// which `boopdev prompts` writes). Both are the engine's: the pack fills in
// only its personalities' settings and its scenarios. studio.js makes each
// view with its own calls (`api`); a view has enter(params) and state, for
// browser checks, and may have card(), hash(params) and empty().
(() => {
  const h = (tag, props = {}, ...children) => {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(props)) k in e ? e[k] = v : e.setAttribute(k, v);
    e.append(...children.flat(Infinity).filter(c => c != null && c !== false));
    return e;
  };
  const sheet = (api, name) => api.root.querySelector(`[data-view="${name}"]`);
  const packOf = api => api.packs[api.sel.pack];
  const panel = (props, ...children) => h('section', {className: 'panel', ...props}, ...children);
  const heading = (text, about) => h('header', {className: 'panel-head'}, h('h3', {}, text), about && h('p', {}, about));
  const MAP = window.StudioData?.behavior || null;

  // A number as the page says it: milliseconds in the largest unit that keeps it whole or a half.
  function amount({value, unit}) {
    if (unit !== 'ms') return {count: String(value), share: String(value), '%': `${value}%`}[unit] ?? `${value} ${unit}`;
    for (const [size, name] of [[3_600_000, 'h'], [60_000, 'min'], [1000, 's']]) {
      const n = value / size;
      if (n >= 1 && Number.isInteger(n * 2)) return `${String(n).replace('.5', '½')} ${name}`;
    }
    return `${value} ms`;
  }
  const number = n => h('span', {className: 'pill', title: `${n.in}: ${n.name || 'its table'}`}, h('small', {}, n.what), ' ', amount(n));
  const decider = id => MAP.deciders.find(d => d.id === id);
  const who = id => h('span', {className: 'who', 'data-decides': id, title: decider(id)?.about || ''}, decider(id)?.label || id);
  // A state that plays, which opens it in Animations: its fact (task complete's outcome…) too.
  function stateChip(api, cell) {
    const [state, fact] = cell.split('/'), facts = api.data.states.facts[state];
    const label = api.stateInfo[state]?.label || state;
    const option = fact && facts?.options.find(o => o.id === fact);
    const b = h('button', {type: 'button', className: 'chip state', 'data-open-state': cell, title: api.stateInfo[state]?.about || ''},
      option ? `${label} · ${option.label.toLowerCase()}` : label);
    return b;
  }
  function brainLine(brain) {
    if (!brain) return null;
    const text = brain.wake == null ? 'The brain hears it in a line, but it never wakes it.'
      : `Wakes the brain${brain.wake ? `, ahead of anything with a lower wake (${brain.wake})` : ''}.`;
    return h('p', {className: 'brain-line'}, h('strong', {}, 'Brain '), text, brain.note ? ' ' + brain.note : '');
  }

  // ── Map ─────────────────────────────────────────────────────────────────
  // The screen's layers, top first, then each thing that sets something
  // off: what it is, who decides, what plays, what the brain makes of it,
  // its numbers, and what else the same moment sets off.
  function behavior(api) {
    const root = sheet(api, 'behavior'), s = {only: '', find: '', row: null};
    function setting(name) {
      const pack = packOf(api), span = window.StudioSpan || (x => x);
      // Each personality's, then each talk level's laid over it.
      const values = [...pack.personalities, ...(pack.talks || [])].filter(p => p.settings?.[name] != null);
      if (!values.length) return null;
      return h('span', {className: 'pill', title: `Each personality's ${name}, and each talk level's over it`}, h('small', {}, name.replace(/_/g, ' ')), ' ',
        values.map(p => `${p.id} ${/^\d+-\d+$/.test(p.settings[name]) ? span(p.settings[name]) : p.settings[name]}`).join(' · '));
    }
    function row(api, r, names) {
      return h('article', {className: 'behavior-row', 'data-row': r.id, id: `behavior-${r.id}`, 'aria-current': String(s.row === r.id)},
        h('header', {}, h('h4', {}, r.when), h('div', {className: 'whos'}, r.decides.map(who))),
        r.plays?.length ? h('div', {className: 'chips'}, r.plays.map(c => stateChip(api, c))) : null,
        h('p', {}, r.does),
        brainLine(r.brain),
        (r.numbers?.length || r.setting) ? h('div', {className: 'pills'}, (r.numbers || []).map(number), r.setting && setting(r.setting)) : null,
        r.also?.length ? h('p', {className: 'also'}, 'The same moment also sets off ',
          r.also.map((id, i) => [i ? (i === r.also.length - 1 ? ' and ' : ', ') : '', h('a', {href: `#behavior-${id}`, 'data-row-link': id}, names[id])]), '.') : null);
    }
    function render() {
      api.writeHash();
      if (!MAP) {
        root.replaceChildren(panel({}, heading('Behavior'), h('p', {className: 'empty-note'}, 'No behaviour map: run python3 characters/charactergen.py, then reload.')));
        return;
      }
      const rows = MAP.groups.flatMap(g => g.rows), names = Object.fromEntries(rows.map(r => [r.id, r.when]));
      const find = s.find.trim().toLowerCase();
      const fits = r => (!s.only || (s.only === 'several' ? r.decides.length > 1 : r.decides.includes(s.only)))
        && (!find || `${r.when} ${r.does} ${(r.plays || []).join(' ')}`.toLowerCase().includes(find));
      const shown = rows.filter(fits).length;
      root.replaceChildren(
        panel({},
          heading('The screen, top first', 'When several want the screen, the higher one shows. Each state opens in Animations.'),
          h('ol', {className: 'layers'}, MAP.layers.map(l => h('li', {'data-layer': l.id},
            h('header', {}, h('strong', {}, l.label), who(l.decides)),
            h('p', {}, l.about),
            h('div', {className: 'chips'}, l.states.map(c => stateChip(api, c))),
            l.numbers?.length ? h('div', {className: 'pills'}, l.numbers.map(number)) : null))),
          h('div', {className: 'deciders'}, h('p', {}, MAP.about), MAP.deciders.map(d => h('p', {}, who(d.id), ' ', d.about)))),
        panel({},
          h('div', {className: 'controls'},
            h('label', {className: 'field grow'}, h('span', {className: 'visually-hidden'}, 'Find'), h('input', {type: 'search', placeholder: 'Find what sets something off', value: s.find, 'data-find': ''})),
            h('div', {className: 'chips'}, [['', 'All'], ...MAP.deciders.map(d => [d.id, d.label]), ['several', 'Several decide']].map(([v, t]) =>
              h('button', {type: 'button', className: 'chip plain', 'data-only': v, 'aria-pressed': String(s.only === v)}, t)))),
          h('p', {className: 'hint'}, `${shown} of ${rows.length}`)),
        ...MAP.groups.map(g => {
          const list = g.rows.filter(fits);
          return list.length ? panel({'data-group': g.id}, heading(g.label, g.about), h('div', {className: 'behavior-rows'}, list.map(r => row(api, r, names)))) : null;
        }).filter(Boolean));
      if (s.row) root.querySelector(`[data-row="${s.row}"]`)?.scrollIntoView({block: 'center'});
    }
    root.addEventListener('click', e => {
      const o = e.target.closest('[data-only]'), state = e.target.closest('[data-open-state]'), link = e.target.closest('[data-row-link]');
      if (o) { s.only = o.dataset.only; render(); }
      if (state) {
        const [id, fact] = state.dataset.openState.split('/'), facts = api.data.states.facts[id];
        api.open({state: id, ...(fact && facts ? {[facts.name]: fact} : {})});
      }
      if (link) { e.preventDefault(); s.only = ''; s.find = ''; s.row = link.dataset.rowLink; render(); }
    });
    root.addEventListener('change', e => { if (e.target.matches('[data-find]')) { s.find = e.target.value; render(); } });
    root.addEventListener('keydown', e => { if (e.key === 'Enter' && e.target.matches('[data-find]')) { s.find = e.target.value; render(); } });
    return {
      state: s,
      enter(params) { if (params?.get('row')) s.row = params.get('row'); render(); },
      hash(p) { if (s.row) p.set('row', s.row); },
      card: render,
    };
  }

  // ── Brain ───────────────────────────────────────────────────────────────
  // What Jev is asked, when and about what: how it's paced (the map's
  // numbers, and what wakes it, from its rows), and an eval scenario's
  // passes, each the prompt it read, in its sections, and every question
  // with its options and the answer the scenario expects.
  function brain(api) {
    const root = sheet(api, 'brain'), s = {scenario: null, pass: 0};
    const P = () => window.StudioPrompts || null;
    // A head's sections: the guide, then each part a heading line (PERSONALITY, MOOD) starts.
    function sections(head) {
      const out = [{title: 'Guide', text: ''}];
      for (const line of head.split('\n')) {
        if (/^[A-Z][A-Z ]+[A-Z]$/.test(line.trim())) out.push({title: line.trim(), text: ''});
        else out[out.length - 1].text += line + '\n';
      }
      return out.filter(x => x.text.trim());
    }
    function question(q, answer) {
      return h('details', {className: 'question', 'data-question': q.key},
        h('summary', {}, h('code', {}, q.key), ' ', q.text, answer && h('span', {className: 'badge', 'data-level': 'approved'}, answer)),
        h('p', {className: 'hint'}, `About ${q.about}; judged by ${q.judge_by}.`),
        h('ol', {className: 'options'}, q.options.map(o => h('li', {'data-picked': String(o.name === answer)},
          h('strong', {}, o.name), ' ', o.what, o.not_for && h('span', {className: 'not-for'}, ' Not for: ', o.not_for)))));
    }
    function wakes() {
      const rows = MAP ? MAP.groups.flatMap(g => g.rows).filter(r => r.brain) : [];
      const by = new Map();
      for (const r of rows) {
        const key = r.brain.wake == null ? 'never' : String(r.brain.wake);
        by.set(key, [...(by.get(key) || []), r]);
      }
      const order = [...by.keys()].sort((a, b) => (b === 'never' ? -1 : Number(b)) - (a === 'never' ? -1 : Number(a)));
      return h('dl', {className: 'meaning wakes'}, order.flatMap(k => [
        h('dt', {}, k === 'never' ? 'Never wakes it' : `Wake ${k}`),
        h('dd', {}, by.get(k).map((r, i) => [i ? ' · ' : '', h('a', {href: '#', 'data-to-row': r.id}, r.when)]))]));
    }
    function render() {
      api.writeHash();
      const pack = packOf(api), prompts = P();
      const scenarios = prompts ? Object.keys(prompts.scenarios).sort((a, b) => (parseInt(a) || 0) - (parseInt(b) || 0)) : [];
      if (!scenarios.includes(s.scenario)) s.scenario = scenarios[0] || null;
      const passes = s.scenario ? prompts.scenarios[s.scenario] : [];
      s.pass = Math.max(0, Math.min(s.pass, passes.length - 1));
      const pass = passes[s.pass], evalOf = id => pack.evals.find(e => e.id === id);
      root.replaceChildren(
        panel({},
          heading('When it\'s asked', MAP?.brain?.about),
          MAP?.brain?.numbers && h('div', {className: 'pills'}, MAP.brain.numbers.map(number)),
          wakes()),
        panel({},
          heading('What it reads and answers', 'Each pass of an eval scenario, run with the brain that answers as the scenario expects: the prompt as Jev reads it, in its sections, and every question with its options, that brain\'s answer marked (a question the scenario doesn\'t check gets a stand-in).'),
          !prompts ? h('p', {className: 'empty-note'}, 'No prompts yet. From the repository root, build boopdev (make -C internal app), run ', h('code', {}, '.build/debug/boopdev prompts'), ', then reload. make dev writes them for you.')
            : prompts.pack !== api.sel.pack ? h('p', {className: 'empty-note'}, `The prompts are ${api.packs[prompts.pack]?.name || prompts.pack}'s, from its eval scenarios: open that character to read them.`)
              : [
                h('div', {className: 'controls'},
                  h('label', {className: 'field grow'}, h('span', {}, 'Scenario '), h('select', {'data-scenario': ''}, scenarios.map(id =>
                    h('option', {value: id, selected: id === s.scenario}, `${id.match(/^\d+/)?.[0] || ''} ${evalOf(id)?.name || id}`))))),
                evalOf(s.scenario)?.case && h('p', {className: 'hint'}, evalOf(s.scenario).case),
                !passes.length ? h('p', {className: 'empty-note'}, 'Nothing in this scenario wakes the brain.') : [
                  h('ol', {className: 'passes'}, passes.map((p, i) => h('li', {},
                    h('button', {type: 'button', className: 'chip plain', 'data-pass': String(i), 'aria-pressed': String(i === s.pass)},
                      h('small', {}, `step ${p.step}`), ' ', p.line || '(no line)', p.held ? ` · held: ${p.held}` : '')))),
                  pass && h('div', {className: 'pass'},
                    pass.held ? h('p', {className: 'note'}, `Held: ${pass.held}. Nothing was asked.`) : [
                      h('h4', {}, 'The prompt'),
                      sections(prompts.heads[pass.head]).map(x => h('details', {className: 'prompt-part'}, h('summary', {}, x.title), h('pre', {}, x.text.trim()))),
                      h('pre', {className: 'prompt-now'}, pass.rest),
                      h('h4', {}, 'The questions'),
                      pass.questions.map(i => question(prompts.questions[i], pass.answers?.[prompts.questions[i].key]))])]]));
    }
    root.addEventListener('click', e => {
      const p = e.target.closest('[data-pass]'), row = e.target.closest('[data-to-row]');
      if (p) { s.pass = Number(p.dataset.pass); render(); }
      if (row) { e.preventDefault(); api.go('behavior', null, new URLSearchParams({row: row.dataset.toRow})); }
    });
    root.addEventListener('change', e => { if (e.target.matches('[data-scenario]')) { s.scenario = e.target.value; s.pass = 0; render(); } });
    return {
      state: s,
      enter(params) {
        if (params?.get('scenario')) { s.scenario = params.get('scenario'); s.pass = Math.max(0, (Number(params.get('pass')) || 1) - 1); }
        render();
      },
      hash(p) { if (s.scenario) { p.set('scenario', s.scenario); if (s.pass) p.set('pass', String(s.pass + 1)); } },
      card: render,
    };
  }

  window.StudioBehaviorViews = {behavior, brain};
})();
