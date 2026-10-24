// A small Markdown renderer for what the studio shows of a pack's own
// writing, a reference's reading (reading.md): headings, paragraphs, lists,
// tables, rules and fenced code, with `code`, **strong**, *emphasis* and
// links inline. It builds elements with the page's h(tag, props,
// ...children), so nothing it reads becomes HTML. Under Node (tests/),
// with any h.
(() => {
  const INLINE = /`([^`]+)`|\*\*(.+?)\*\*|(?<![\w*])\*(?!\s)(.+?)\*(?![\w*])|(?<!\w)_(?!\s)(.+?)_(?!\w)|\[([^\]]+)\]\(([^)\s]+)\)/g;
  const LIST = /^\s*([-*+]|\d+[.)])\s+(.*)$/, FENCE = /^\s*(```|~~~)/, HEADING = /^(#{1,6})\s+(.*?)(\s+#+)?\s*$/;
  const HR = /^\s*(-{3,}|\*{3,}|_{3,})\s*$/, ROW = /^\s*\|/, DIVIDER = /^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$/;

  function inline(text, h) {
    const out = [];
    let at = 0;
    for (const m of text.matchAll(INLINE)) {
      if (m.index > at) out.push(text.slice(at, m.index));
      const [, code, strong, star, under, label, href] = m;
      if (code != null) out.push(h('code', {}, code));
      else if (strong != null) out.push(h('strong', {}, ...inline(strong, h)));
      else if (star != null || under != null) out.push(h('em', {}, ...inline(star ?? under, h)));
      else out.push(/^https?:\/\//.test(href) ? h('a', {href, target: '_blank', rel: 'noopener'}, ...inline(label, h)) : label);
      at = m.index + m[0].length;
    }
    if (at < text.length) out.push(text.slice(at));
    return out;
  }

  const cells = row => row.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map(c => c.trim());
  const table = (line, next) => ROW.test(line) && DIVIDER.test(next || '');
  const opens = (line, next) => FENCE.test(line) || HR.test(line) || HEADING.test(line) || LIST.test(line) || table(line, next);

  // The blocks of `text`, as elements: a heading # is an h3 (a reading sits
  // under the page's own h3), ## an h4 and so on.
  function render(text, h) {
    const lines = String(text).replace(/\r\n?/g, '\n').split('\n'), out = [];
    for (let i = 0; i < lines.length;) {
      const line = lines[i];
      let m;
      if (!line.trim()) {
        i++;
      } else if ((m = line.match(FENCE))) {
        const body = [];
        for (i++; i < lines.length && !lines[i].trim().startsWith(m[1]); i++) body.push(lines[i]);
        i++;
        out.push(h('pre', {}, h('code', {}, body.join('\n'))));
      } else if (HR.test(line)) {
        out.push(h('hr', {}));
        i++;
      } else if ((m = line.match(HEADING))) {
        out.push(h(`h${Math.min(6, m[1].length + 2)}`, {}, ...inline(m[2], h)));
        i++;
      } else if (table(line, lines[i + 1])) {
        const head = cells(line), rows = [];
        for (i += 2; i < lines.length && ROW.test(lines[i]); i++) rows.push(cells(lines[i]));
        out.push(h('table', {},
          h('thead', {}, h('tr', {}, ...head.map(c => h('th', {}, ...inline(c, h))))),
          h('tbody', {}, ...rows.map(r => h('tr', {}, ...head.map((_, j) => h('td', {}, ...inline(r[j] || '', h))))))));
      } else if ((m = line.match(LIST))) {
        const ordered = /\d/.test(m[1]), items = [];
        for (; i < lines.length && lines[i].trim(); i++) {
          const item = lines[i].match(LIST);
          if (item && /\d/.test(item[1]) === ordered) items.push(item[2]);
          else if (!item && /^\s/.test(lines[i])) items[items.length - 1] += ` ${lines[i].trim()}`;
          else break;
        }
        out.push(h(ordered ? 'ol' : 'ul', {}, ...items.map(t => h('li', {}, ...inline(t, h)))));
      } else {
        const words = [line.trim()];
        for (i++; i < lines.length && lines[i].trim() && !opens(lines[i], lines[i + 1]); i++) words.push(lines[i].trim());
        out.push(h('p', {}, ...inline(words.join(' '), h)));
      }
    }
    return out;
  }

  const api = {render, inline};
  if (typeof module !== 'undefined') module.exports = api;
  if (typeof window !== 'undefined') window.StudioMarkdown = api;
})();
