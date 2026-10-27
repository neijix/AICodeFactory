---
name: web-accessibility
description: "Use when building or reviewing any web UI that people use with a keyboard, a screen reader, zoom or a phone: a new page, form, dialog, menu, tabs, toast or icon button; when the user says accessibility, a11y, WCAG, ARIA, screen reader, VoiceOver, NVDA, keyboard navigation, focus, contrast, alt text or \"can't tab to it\"; before calling front-end work done; when asked for an accessibility audit or review. Practical WCAG 2.2 AA: semantic HTML first, keyboard, names and labels, forms, dialogs, live regions, contrast, target size, motion, reflow, and a review procedure with findings per criterion."
---

# Web accessibility (WCAG 2.2 AA, in practice)

Accessibility is mostly not extra work: it is picking the element the browser already made
accessible and not breaking what it gives you for free. Most failures in small apps are a
`<div>` that should have been a `<button>`, an input with no label, a dialog that lets focus
wander behind it, or grey-on-grey text. Fix those four and you are most of the way.

The target is **WCAG 2.2 level AA**. It is also the law in more and more places: the European
Accessibility Act applies since 28 June 2025 to e-commerce, banking, transport, e-books and
communication services sold in the EU (benchmark EN 301 549, built on WCAG 2.1 AA, being
aligned with 2.2); the US ADA and Section 508 are read against WCAG too. WCAG 3 is still a
W3C working draft: track it, do not target it. `CHECKLIST.md` next to this file lists each criterion
with the check to run; this file is the how and why. Related: the ui-craft skill (visual
design), the ui-motion skill (animation), the mobile-web skill (touch, phone viewports), the
headless-ui-smoke skill (looking at the rendered page), the ui-doctor skill (the automated
pass: alt, names, labels, contrast in both themes, targets, reflow, focus).

## 1. Semantic HTML first (the native element brings role, name, keys and focus)

- **Actions are `<button>`, navigation is `<a href>`.** A clickable `<div>` gets no focus, no
  Enter/Space, no role. If it changes the URL it is a link; otherwise a button. Buttons inside
  a form that do not submit get `type="button"`.
- **Landmarks**: one `<header>`, one `<main>`, `<nav>` (named with `aria-label` when there are
  several), `<aside>`, `<footer>`. Screen-reader users jump between them.
- **Headings in order**: one `<h1>`, then `<h2>`, `<h3>` without skipping levels. Choose the
  level by structure and restyle it with CSS, never by font size.
- **Lists are lists**: chips, a sidebar of chats, search results → `<ul>`/`<li>`; the reader
  announces "list, 12 items" for free.
- **Tables are for tabular data**, with `<th scope="col">` / `scope="row"` and a `<caption>`.
  No layout tables, no data tables faked with divs and grid.

```html
<!-- wrong: no focus, no keyboard, no role -->
<div class="icon-btn" onclick="removeRow(id)"><svg>…</svg></div>

<!-- right -->
<button type="button" class="icon-btn" aria-label="Remove row" onclick="removeRow(id)">
  <svg aria-hidden="true" focusable="false">…</svg>
</button>
```

## 2. Keyboard

Every action a mouse can do, a keyboard can do, in an order that follows the page.

- **Tab order follows the DOM.** No positive `tabindex`; reorder the markup instead.
  `tabindex="0"` makes a custom element focusable, `tabindex="-1"` focusable by script only.
- **No traps**: Tab and Shift+Tab always leave a component. The one exception is a modal
  dialog, which keeps focus inside on purpose and closes with Escape.
- **Focus is always visible.** Never `outline: none` without a replacement. Style
  `:focus-visible`, so mouse clicks stay clean and keyboard focus is obvious. WCAG 2.2 also
  wants the focused element not hidden under a sticky header: set `scroll-padding-top` on
  `html` to the header height.

```css
:focus-visible { outline: 2px solid var(--focus, #2563eb); outline-offset: 2px; }
```

- **Skip link**: the first focusable element, `<a class="skip-link" href="#main">Skip to
  content</a>`, jumps to `<main id="main">`. Move it off-screen and bring it back on `:focus`;
  never `display: none`, which removes it from the Tab order.
- **Composite widgets use a roving tabindex**: tabs, toolbars, menus, listboxes and grids are
  one Tab stop and arrow keys move inside. The active item has `tabindex="0"`, the others
  `-1`; the script moves both:

```js
function onArrow(list, e) {
  const items = [...list.querySelectorAll('[role="tab"]')];
  const step = { ArrowRight: 1, ArrowLeft: -1 }[e.key];
  if (step === undefined) return;
  const i = items.indexOf(document.activeElement);
  const next = items[(i + step + items.length) % items.length];
  items.forEach((el) => el.setAttribute('tabindex', el === next ? '0' : '-1'));
  next.focus();
  e.preventDefault();
}
```

  Follow the WAI-ARIA Authoring Practices pattern for the widget (keys, roles, states); do not
  invent a keyboard model.

## 3. Names and labels (every control has one, matching what is on screen)

- **Inputs**: a visible `<label for="id">`. A placeholder is not a label: it disappears and is
  usually low contrast.
- **`aria-label` only when there is no visible text** (an icon button). When visible text
  exists, the name must contain it (WCAG 2.5.3) so voice users can say what they see.
- **Icon buttons**: the name on the button, `aria-hidden="true"` on the SVG. A tooltip alone
  is not a name.
- `aria-labelledby` points at existing visible text (a heading naming a region).
- Links say where they go: not "click here", not five bare "Read more".

## 4. Forms

- Group related controls in `<fieldset>` with a `<legend>` (radio groups, an address).
- Use the right `type` and `autocomplete` (`email`, `tel`, `current-password`,
  `one-time-code`): browsers fill the field, which helps people with motor or memory
  difficulties (WCAG 1.3.5).
- **Errors are text, tied to the field**, never colour alone:

```html
<label for="email">Email</label>
<input id="email" type="email" autocomplete="email"
       aria-invalid="true" aria-describedby="email-error">
<p id="email-error" class="field-error">Enter an address like name@example.com.</p>
```

  Set `aria-invalid` only after a failed check and remove it once fixed. On a failed submit,
  move focus to the first invalid field or to an error summary linking to each field.
- **Do not disable the submit button silently.** A greyed button gives no reason and drops out
  of the Tab order. Keep it enabled and say what is missing when pressed, or show the reason
  next to it.
- Do not ask for the same information twice in one flow (3.3.7). Never block paste into
  password or code fields, so password managers work (3.3.8).

## 5. Dialogs

Use native `<dialog>` with `showModal()`: it makes the rest of the page inert, keeps focus
inside, closes on Escape and draws a `::backdrop`.

```html
<button type="button" id="open-settings">Settings</button>
<dialog id="settings" aria-labelledby="settings-title">
  <h2 id="settings-title">Settings</h2>
  …
  <button type="button" data-close>Close</button>
</dialog>
```
```js
const dlg = document.getElementById('settings');
const opener = document.getElementById('open-settings');
opener.addEventListener('click', () => dlg.showModal());
dlg.querySelector('[data-close]').addEventListener('click', () => dlg.close());
dlg.addEventListener('close', () => opener.focus()); // focus goes back where it came from
```

- Focus lands on the first meaningful control (`autofocus` on it), or on the title for a long
  read. On close it returns to the opener; if the opener is gone, to a sensible neighbour,
  never `<body>`.
- A custom drawer or sheet that is not a `<dialog>`: set `inert` on everything else while it
  is open, and handle Escape yourself.

## 6. Status messages and toasts

Async results (saved, copied, 3 results, upload failed) are announced without moving focus
(WCAG 4.1.3).

- Put an **empty live region in the page at load**
  (`<div id="announcer" role="status" class="visually-hidden"></div>`) and write into it
  later; a region inserted together with its text is often not announced.
- `role="status"` (polite) for success and progress; `role="alert"` only for errors that need
  attention now.
- **Toasts never take focus** and stay long enough to read (about 5 s or more, paused on hover
  and focus). An action in a toast ("Undo") must also be reachable another way.
- A streaming chat reply is announced once when it finishes ("Reply ready"), not per token.

```js
function announce(text) {
  const el = document.getElementById('announcer');
  el.textContent = '';
  requestAnimationFrame(() => { el.textContent = text; });
}
```

## 7. Colour, contrast, target size

- **Contrast**: 4.5:1 for normal text; 3:1 for large text (24 px, or 18.66 px bold) and for UI
  parts that carry meaning (input borders, focus ring, icons, chart lines). Check both themes.
- **Never colour alone**: an error is red *and* has an icon or text; a selected tab is coloured
  *and* underlined or bold; links in running text are underlined.
- **Target size**: at least 24 x 24 CSS px, or spaced so a 24 px circle around each target
  does not touch its neighbour (2.5.8). On touch layouts aim for 44 px (the mobile-web skill).

## 8. Motion and user preferences

- Honour `prefers-reduced-motion`: drop parallax, large slides and zooms; keep short fades.
  Anything that moves, blinks or auto-updates for more than 5 s needs a pause control. The
  design of motion itself belongs to the ui-motion skill.
- Write the reduced version per component, so a slide becomes a fade instead of nothing. A
  blanket `* { transition-duration: 0.01ms !important }` reset is a last resort for code you
  cannot change: it removes the fades too.

```css
.toast { transition: transform 200ms ease-out, opacity 200ms ease-out; }
@media (prefers-reduced-motion: reduce) {
  .toast { transition-property: opacity; }      /* position jumps, the fade stays */
  .hero-parallax { animation: none; }
  html { scroll-behavior: auto; }
}
```

- `prefers-contrast: more`: strengthen borders and muted text. `forced-colors: active`
  (Windows High Contrast): backgrounds and box-shadows vanish, so custom controls and focus
  need a real `border` or `outline`.

## 9. Zoom, reflow, images

- Never block zoom (`maximum-scale=1`, `user-scalable=no`). At **200 %** text does not clip
  or overlap; at **320 CSS px** wide content reflows to one column with no horizontal scroll
  (tables, maps and code may scroll in their own box). Size text in `rem`, use `min-height`
  rather than `height` on text boxes.
- **Images**: informative → `alt` says what it conveys (not "image of"); decorative →
  `alt=""`; the only content of a link or button → `alt` names the action; a chart → short
  `alt` plus the data or a summary nearby. Inline SVG icons next to text get
  `aria-hidden="true"`; a standalone meaningful SVG gets `role="img"` and a name.

## 10. ARIA rules

1. **No ARIA is better than bad ARIA.** Use a native element whenever one exists.
2. **Do not override native roles**: no `role="button"` on `<a>`, no `role="heading"` on
   `<button>`.
3. **A role is a promise**: `role="tab"` means arrow keys, `aria-selected` and a linked
   tabpanel. If you will not build those, do not add the role.
4. Never put `aria-hidden="true"` on something focusable or on its ancestor.
5. Keep states in sync with the UI: `aria-expanded`, `aria-pressed`, `aria-selected`,
   `aria-current="page"`.

## Review procedure (in order: each finds what the others miss)

1. **Keyboard-only pass.** From the address bar, Tab through the whole page: every action
   reachable, focus always visible, order logical, Escape closes overlays, focus returns
   after a dialog.
2. **Screen-reader smoke test** (five minutes, not an audit):
   - macOS VoiceOver: Cmd+F5 toggles it; VO = Ctrl+Option. VO+U opens the rotor (headings,
     landmarks, form controls); VO+Right reads the next item.
   - Windows NVDA (free): H jumps headings, D landmarks, F form fields, Tab controls;
     Insert+F7 lists elements; Insert+Space switches browse and focus mode.
   - Listen for unnamed buttons, unlabelled inputs, a dialog that is not announced, a status
     that is never spoken.
3. **Accessibility tree in headless Chrome** via the headless-ui-smoke skill: dump roles and
   names (DevTools `Accessibility.getFullAXTree`, or a query through its `--eval` flag) and
   look for unnamed buttons, links and inputs and a missing `main`.
4. **Automated pass.** Run the ui-doctor skill (no dependency to add: sources, then `--url`
   on the running page); if the project already has axe-core, Lighthouse or pa11y, run it too.
   **Ask before adding a dependency.** Tools cover about a third of the criteria and about
   half of real issues by volume; a clean run is not a pass.
5. **Contrast and zoom**: both themes; 200 % zoom; 320 px wide.

## Report format (one finding per problem, worst first)

```
[Blocker] 2.1.1 Keyboard — static/app.js:142
  "Delete chat" is a <div> with a click handler: unreachable by keyboard.
  Fix: <button type="button" aria-label="Delete chat">.
[Serious] 1.4.3 Contrast (Minimum) — static/style.css:58
  .muted #9aa0a6 on #ffffff is 2.6:1 (needs 4.5:1). Fix: #5f6368 (6.0:1); check dark theme.
```

Severity: **Blocker** (a task cannot be completed), **Serious** (completed with real
difficulty), **Moderate** (annoying, a workaround exists), **Minor** (polish). Say what you
could not test (no screen reader, no device) instead of passing it.

Background: distilled from W3C WAI guidance, Vercel's web-interface-guidelines and mgifford's accessibility-skills; rewritten, nothing copied.
