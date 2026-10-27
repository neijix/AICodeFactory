// In-page half of ui_doctor.py: evaluated inside the page over the DevTools protocol, it returns
// plain JSON. Each check is a bucket {count, items: [{sel, text, detail}]} capped at opts.limit.
// opts.pass picks what runs: "main" (desktop viewport), "contrast" (rerun under an emulated
// colour scheme), "phone" (narrow viewport), "motion"
// (after prefers-reduced-motion: reduce is emulated), "focus" (moves focus: run it last).
(async function uiAudit(opts) {
  const limit = opts.limit || 8;
  const bucket = () => ({ count: 0, items: [] });
  const sel = (el) => {
    const parts = [];
    for (let e = el; e && e.nodeType === 1 && parts.length < 3; e = e.parentElement) {
      if (e.id) { parts.unshift(`#${CSS.escape(e.id)}`); break; }
      const cls = [...e.classList].slice(0, 2).map((c) => `.${CSS.escape(c)}`).join('');
      parts.unshift(e.localName + cls);
    }
    return parts.join(' > ');
  };
  const snippet = (el) => String(el.innerText || el.value || el.getAttribute('aria-label') || el.getAttribute('src') || '')
    .trim().replace(/\s+/g, ' ').slice(0, 50);
  const add = (b, el, detail) => {
    b.count += 1;
    if (b.items.length < limit) b.items.push({ sel: sel(el), text: snippet(el), detail: detail || '' });
  };
  const visible = (el) => {
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) return false;
    const s = getComputedStyle(el);
    return s.visibility !== 'hidden' && s.display !== 'none';
  };
  const all = (selector) => [...document.querySelectorAll(selector)].filter(visible);

  const { rgba, over, ratio, backdrop, opacity } = colourKit();

  // Any CSS colour (rgb, oklch, color-mix…) → sRGB bytes + alpha, through a 1×1 canvas.
  function colourKit() {
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = 1;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    const colours = new Map();
    const rgba = (colour) => {
      if (!colours.has(colour)) {
        ctx.clearRect(0, 0, 1, 1);
        ctx.fillStyle = '#000';
        ctx.fillStyle = colour;
        ctx.fillRect(0, 0, 1, 1);
        const [r, g, b, a] = ctx.getImageData(0, 0, 1, 1).data;
        colours.set(colour, [r, g, b, a / 255]);
      }
      return colours.get(colour);
    };
    const over = (top, base) => [0, 1, 2].map((i) => top[i] * top[3] + base[i] * (1 - top[3]));
    const luminance = (c) => {
      const lin = c.map((v) => { const s = v / 255; return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; });
      return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2];
    };
    const ratio = (a, b) => {
      const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
      return (hi + 0.05) / (lo + 0.05);
    };
    const canvasColour = () => {
      const scheme = getComputedStyle(document.documentElement).colorScheme || '';
      const dark = /dark/.test(scheme) && (!/light/.test(scheme) || matchMedia('(prefers-color-scheme: dark)').matches);
      return dark ? [18, 18, 18] : [255, 255, 255];
    };
    // The colour behind an element: its own and its ancestors' backgrounds, composited. null when
    // an image or gradient is in the way (the contrast is then unknown, not failed).
    const backdrop = (el) => {
      const layers = [];
      for (let e = el; e; e = e.parentElement) {
        const s = getComputedStyle(e);
        if (s.backgroundImage !== 'none') return null;
        const c = rgba(s.backgroundColor);
        if (c[3] > 0) layers.push(c);
        if (c[3] >= 1) break;
      }
      return layers.reverse().reduce((base, layer) => over(layer, base), canvasColour());
    };
    const opacity = (el) => {
      let o = 1;
      for (let e = el; e; e = e.parentElement) o *= Number(getComputedStyle(e).opacity);
      return o;
    };
    return { rgba, over, ratio, backdrop, opacity };
  }

  function contrast() {
    const b = bucket();
    const seen = new Set();
    const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT);
    while (walker.nextNode() && seen.size < 3000) {
      const el = walker.currentNode.parentElement;
      if (!el || seen.has(el) || !walker.currentNode.nodeValue.trim()) continue;
      seen.add(el);
      if (!visible(el) || el.closest('script, style, noscript, [disabled], [aria-disabled="true"]')) continue;
      const bg = backdrop(el);
      if (!bg) continue;
      const s = getComputedStyle(el);
      const fg = rgba(s.color);
      const shown = over([fg[0], fg[1], fg[2], fg[3] * opacity(el)], bg);
      const size = parseFloat(s.fontSize);
      const large = size >= 24 || (size >= 18.66 && Number(s.fontWeight) >= 700);
      const value = ratio(shown, bg);
      if (value < (large ? 3 : 4.5)) add(b, el, `${value.toFixed(2)}:1, needs ${large ? 3 : 4.5}:1`);
    }
    return b;
  }

  const nameOf = (el) => {
    const labelled = (el.getAttribute('aria-labelledby') || '').split(/\s+/).filter(Boolean)
      .map((id) => (document.getElementById(id) || {}).textContent || '').join(' ');
    const images = [...el.querySelectorAll('img[alt], svg title')].map((i) => i.getAttribute('alt') || i.textContent).join(' ');
    return [el.getAttribute('aria-label'), labelled, el.innerText, el.getAttribute('title'), images,
      ['submit', 'button', 'reset'].includes(el.type) ? el.value : ''].join(' ').trim();
  };

  function controls() {
    const out = { unnamed: bucket(), noAlt: bucket(), unlabelled: bucket(), smallTargets: bucket() };
    for (const el of all('a[href], button, [role="button"], [role="link"], [role="tab"], [role="menuitem"]')) {
      if (!nameOf(el)) add(out.unnamed, el, el.localName === 'a' ? 'link has no name' : 'button has no name');
    }
    for (const el of all('img:not([alt])')) add(out.noAlt, el);
    const fields = 'input:not([type="hidden"]):not([type="submit"]):not([type="button"]):not([type="reset"]):not([type="image"]), select, textarea';
    for (const el of all(fields)) {
      const named = [...(el.labels || [])].some((l) => l.innerText.trim()) || el.getAttribute('aria-label')
        || el.getAttribute('aria-labelledby') || el.getAttribute('title');
      if (!named) add(out.unlabelled, el, el.placeholder ? 'only a placeholder' : 'no label');
    }
    const targets = 'a[href], button, input:not([type="hidden"]), select, textarea, summary, [role="button"], [role="checkbox"], [role="tab"], [role="menuitem"]';
    for (const el of all(targets)) {
      const r = el.getBoundingClientRect();
      if (r.width >= 24 && r.height >= 24) continue;
      const label = el.closest('label');
      if (label && label.getBoundingClientRect().height >= 24) continue;
      const parent = el.parentElement;
      const inline = getComputedStyle(el).display === 'inline' && parent && parent.innerText.trim().length > el.innerText.trim().length;
      if (!inline) add(out.smallTargets, el, `${Math.round(r.width)}×${Math.round(r.height)}px`);
    }
    return out;
  }

  function headings() {
    const out = { h1: 0, skipped: bucket() };
    let previous = 0;
    for (const el of all('h1, h2, h3, h4, h5, h6, [role="heading"]')) {
      const level = Number(el.getAttribute('aria-level')) || Number(el.localName.slice(1)) || 2;
      if (level === 1) out.h1 += 1;
      if (previous && level > previous + 1) add(out.skipped, el, `h${previous} → h${level}`);
      previous = level;
    }
    return out;
  }

  function text() {
    const out = { devWords: bucket(), dots: bucket() };
    for (const el of all('body *')) {
      const own = [...el.childNodes].filter((n) => n.nodeType === 3).map((n) => n.nodeValue).join(' ');
      if (/\b(undefined|NaN)\b|\[object Object\]/.test(own)) add(out.devWords, el);
      if (/\w\.\.\.(\s|$)/.test(own)) add(out.dots, el, 'use … (U+2026)');
    }
    return out;
  }

  const observe = (type, reduce, start) => new Promise((resolve) => {
    let value = start;
    try {
      new PerformanceObserver((list) => { for (const e of list.getEntries()) value = reduce(value, e); })
        .observe({ type, buffered: true });
    } catch (_) { resolve(null); return; }
    setTimeout(() => resolve(value), 150);
  });

  async function vitals() {
    const cls = await observe('layout-shift', (sum, e) => (e.hadRecentInput ? sum : sum + e.value), 0);
    const lcp = await observe('largest-contentful-paint', (_, e) => e.startTime, null);
    return { cls, lcp };
  }

  function phone() {
    const out = { overflow: bucket(), smallInputs: bucket(), width: window.innerWidth };
    if (document.documentElement.scrollWidth > window.innerWidth + 1) {
      for (const el of all('body *')) {
        const r = el.getBoundingClientRect();
        if (r.right > window.innerWidth + 1 && r.left < window.innerWidth) add(out.overflow, el, `right edge at ${Math.round(r.right)}px`);
      }
      if (!out.overflow.count) add(out.overflow, document.documentElement, `scrollWidth ${document.documentElement.scrollWidth}px`);
    }
    for (const el of all('input:not([type="hidden"]):not([type="checkbox"]):not([type="radio"]), select, textarea')) {
      const size = parseFloat(getComputedStyle(el).fontSize);
      if (size < 16) add(out.smallInputs, el, `${size}px`);
    }
    return out;
  }

  function motion() {
    const b = bucket();
    for (const a of document.getAnimations()) {
      const timing = a.effect && a.effect.getComputedTiming();
      const target = a.effect && a.effect.target;
      if (a.playState === 'running' && timing && timing.iterations === Infinity && target && target.nodeType === 1) {
        add(b, target, a.animationName || a.transitionProperty || 'infinite animation');
      }
    }
    return b;
  }

  const look = (el) => {
    const s = getComputedStyle(el);
    return [s.outlineStyle, s.outlineWidth, s.outlineColor, s.boxShadow, s.backgroundColor, s.borderColor, s.color, s.textDecorationLine].join('|');
  };
  // Focus each tabbable control and compare its look (and its parent's) before and after.
  function focus() {
    const b = bucket();
    const tabbable = all('a[href], button:not([disabled]), input:not([type="hidden"]):not([disabled]), select:not([disabled]), textarea:not([disabled]), summary, [tabindex]:not([tabindex="-1"])');
    const scroll = [window.scrollX, window.scrollY];
    for (const el of tabbable.slice(0, 40)) {
      const parent = el.parentElement || el;
      const before = look(el) + look(parent);
      el.focus({ preventScroll: true });
      if (document.activeElement === el && el.matches(':focus-visible') && look(el) + look(parent) === before) add(b, el, 'looks the same focused');
      el.blur();
    }
    window.scrollTo(scroll[0], scroll[1]);
    return b;
  }

  if (opts.pass === 'contrast') return contrast();
  if (opts.pass === 'phone') return phone();
  if (opts.pass === 'motion') return motion();
  if (opts.pass === 'focus') return focus();
  return {
    lang: document.documentElement.getAttribute('lang') || '',
    title: document.title.trim(),
    contrast: contrast(),
    ...controls(),
    headings: headings(),
    ...text(),
    vitals: await vitals(),
  };
})
