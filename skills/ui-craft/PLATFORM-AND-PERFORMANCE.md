# UI craft — speed and the platform

Detail for `SKILL.md` §11 (speed) and §9 "native elements first". Browser support moves every
month: check Baseline on [webstatus.dev](https://webstatus.dev) before relying on anything in
part 2 without a fallback.

## 1. Speed: the three Core Web Vitals

Measured at the 75th percentile of real visits, phones and desktops apart:

| Vital | Good | Poor | Measures |
|---|---|---|---|
| **LCP** Largest Contentful Paint | ≤ 2.5 s | > 4 s | when the main content shows |
| **INP** Interaction to Next Paint | ≤ 200 ms | > 500 ms | how fast every tap, click and key answers (replaced FID in 2024) |
| **CLS** Cumulative Layout Shift | ≤ 0.1 | > 0.25 | how much the page jumps |

A lab run (Lighthouse, DevTools, the ui-doctor skill) finds causes; only field data (CrUX,
or the `web-vitals` library sending to the app's own endpoint) says whether users get a good
page. INP in particular cannot be measured by a scripted page load.

### LCP: get the main thing on screen

- The LCP element (hero image, first heading, main chart) is in the **HTML the server sends**:
  not a `data-src` swapped by script, not a CSS `background-image`, not rendered after a fetch.
- The LCP image has `fetchpriority="high"` and **never** `loading="lazy"`; images below the
  fold get `loading="lazy"` and `decoding="async"`.
- Fast first byte: cache the HTML, serve static files with long `Cache-Control` and hashed names.
- Fonts: preload the one face used above the fold, `font-display: swap`, a metric-matched
  fallback (`size-adjust`, `ascent-override`) so the swap does not shift text.
- **Back/forward cache**: no `unload` handler (use `pagehide`), no `Cache-Control: no-store`
  on pages that do not hold secrets; a back navigation is then instant.
- Multi-page sites: Speculation Rules can prerender the likely next page.

```html
<script type="speculationrules">
{ "prerender": [{ "where": { "href_matches": "/docs/*" }, "eagerness": "moderate" }] }
</script>
```

### INP: answer every input within a frame

- **Feedback first, work after.** Paint the pressed or pending state, then yield, then do the
  heavy part:

```js
button.addEventListener('click', async () => {
  button.setAttribute('aria-busy', 'true');                  // visible at the next frame
  await (globalThis.scheduler?.yield?.() ?? new Promise((r) => setTimeout(r, 0)));
  await recalculateEverything();                              // long work after the paint
});
```

- Break long loops into chunks that yield every ~50 ms; move parsing and crunching to a Web
  Worker.
- Ship less script: split by route, load third-party tags after the page is usable, delete
  libraries that one small function could replace.
- Keep the DOM small (a few thousand nodes): virtualize lists and tables beyond a few hundred
  rows, render closed tabs and menus lazily, `content-visibility: auto` with
  `contain-intrinsic-size` on long off-screen sections.
- Debounce typing-driven work (search, validation) to ~150 ms; never re-render a whole list
  per keystroke.

### CLS: nothing moves unless the user moved it

- `width` and `height` attributes (or `aspect-ratio`) on every `<img>`, `<video>`, `<iframe>`.
- Space reserved for what arrives late: banners, ads, embeds, toasts that push content (they
  should overlay instead), web fonts (fallback metrics above).
- Animate `transform` and `opacity`, never `top`, `height` or `margin` (the ui-motion skill).
- Content inserted above what the user is reading only in answer to their action.

## 2. The platform: native before custom

Native elements bring keyboard handling, focus management, the top layer and the
accessibility tree for free. Rebuild one only when it truly cannot do the job, and when a
newer feature is used, make the page still work without it.

| Need | Use | Notes |
|---|---|---|
| Menu, picker, toggletip | `popover` + `popovertarget` | Baseline. Light dismiss and Escape built in; `popover="hint"` (hover cards, with `interestfor`) is newer: enhancement only |
| Modal | `<dialog>` + `showModal()` | Focus is trapped and returned, background is inert. `closedby="any"` adds click-outside dismiss where supported |
| Open/close without JS | `command` / `commandfor` on a `<button>` | `show-modal`, `close`, `toggle-popover`; keep a JS fallback while support is partial |
| Styled select | `appearance: base-select` + `<selectedcontent>` | Keeps the real `<select>` (forms, keyboard, mobile pickers); unsupported browsers show the native one |
| Position a menu next to its button | CSS anchor positioning (`anchor-name`, `position-anchor`, `position-try`) | Replaces a positioning library; fall back to a static placement |
| Component adapts to its slot | container queries (`container-type: inline-size`, `@container`) | Baseline; style queries are newer |
| Auto-growing textarea | `field-sizing: content` | Falls back to a fixed height |
| Disclosure | `<details>` / `<summary>` | `name` on several makes an exclusive accordion |
| Page and view changes | View Transitions | Same-document is Baseline; design rules in the ui-motion skill |
| Text colour on a dynamic background | `contrast-color()` | Interop 2026 focus area: compute a fallback |

Check before use:

```css
@supports (appearance: base-select) { select { appearance: base-select; } }
@supports not (anchor-name: --a) { .menu { position: absolute; top: 100%; left: 0; } }
```
