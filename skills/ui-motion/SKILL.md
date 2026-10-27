---
name: ui-motion
description: "Use when an animation, transition or motion effect is added to or fixed in a web UI (CSS, WAAPI, View Transitions, a React motion library); when the user says an animation is janky, choppy, stutters or drops frames; when asked to make a page or component \"feel alive\", smoother or more polished; when reviewing or auditing existing motion, or looking for places that should or should not animate; when the user describes an effect without knowing its name. Two modes: BUILD (writes the motion, cheapest tool first, with concrete easings and durations, reduced-motion and performance handled) and REVIEW (read-only audit with file:line findings, exact fix values and a verdict). Plain HTML/CSS/JS first; React only as an aside."
---

# UI motion

Motion is a tool for explaining change: where a thing came from, that an action was received,
what is still loading. Used for decoration it slows people down. Most of the craft is deciding
**not** to animate, and making the few remaining animations short, interruptible and cheap.

Two modes. Pick one from the request and say which:

- **BUILD**: add motion, or fix motion that feels wrong, stutters or ignores reduced motion.
  Writes code.
- **REVIEW**: audit existing motion, or list places that should (and should not) animate.
  **Read-only** until the user asks to apply the findings. Checklist and report template:
  [REVIEW.md](REVIEW.md).

The user describes an effect loosely ("the bouncy popover thing", "the iOS stretch")? Name it
first with [VOCABULARY.md](VOCABULARY.md), then build or review.

## Recon first (two minutes, both modes)

Learn what the project already has:

```bash
rg -n "transition|@keyframes|animation:|cubic-bezier|linear\(" --glob "*.{css,scss,html,js,ts,jsx,tsx}"
rg -n "prefers-reduced-motion|startViewTransition|view-transition|\.animate\(|requestAnimationFrame"
rg -n "\-\-(ease|duration|motion)" --glob "*.{css,scss}"            # existing motion tokens
rg -n "\"(framer-motion|motion|gsap|animejs|@react-spring/web|auto-animate)\"" package.json
```

Write down: the easing and duration tokens in use (reuse them; add tokens only if none exist),
any animation library already installed, whether reduced motion is handled anywhere, and the
product's tone. A dense tool UI (dashboards, settings, chat logs) wants calm, quick motion; a
landing page can afford more. Match what is there unless it is the problem.

## BUILD: the decisions, in order

### 1. Should it animate at all?

- **Frequency.** Something seen hundreds of times a day (a menu opened by shortcut, a list
  row's hover, a tab switch in a tool) gets little or no motion: 100 ms of opacity at most.
  Anything triggered from the keyboard should feel instant.
- **Density.** Data-dense screens stay still. Numbers that update every second do not flash
  or slide on each tick; highlight a change only when it matters to the reader.
- **First load.** Content the user came for appears at once; no staged entrance on a work
  screen.

If the honest answer is "it would just look nice", leave it static and say so.

### 2. Name its purpose

One of: **orientation** (where did this panel come from, where did it go), **feedback** (the
press, the save, the copy registered), **continuity** (the same object across two states or
pages), **attention** (one thing needs a look now). No purpose, no animation. The purpose
picks the motion: orientation moves along the axis of origin, feedback is small and fast,
continuity morphs, attention is brief and never loops.

### 3. Cheapest tool that does the job

1. **CSS transition** between two states (class, attribute, `:hover`, `:popover-open`).
   Retargets on its own when the state flips mid-flight.
2. **`@starting-style` + `transition-behavior: allow-discrete`** to animate entering and
   leaving `display: none`, popovers and `<dialog>` without JavaScript (example below).
3. **`@keyframes`** for one-shot sequences or a loop (a spinner). Do not use them for state
   that can flip back: they restart instead of reversing.
4. **Web Animations API** (`el.animate(keyframes, options)`) when JS decides the values (a
   measured height, a FLIP delta) or needs `await anim.finished`.
5. **View Transitions API** (`document.startViewTransition(update)`) for crossfades and
   shared-element morphs across a DOM swap; feature-detect and call `update()` directly if
   missing.
6. **A JS library** only if one is already in the project, or the user agrees to add it
   (gesture physics with velocity, complex orchestration). Never add one silently.

### 4. Properties: transform and opacity

Animate `transform` (translate, scale, rotate) and `opacity`; they skip layout and paint.
Write the transitioned properties explicitly — **never `transition: all`**, which animates
whatever changes next (colour from a theme switch, `height` from new content) and costs
layout.

Set `transform-origin` to where the element comes from. A dropdown under its trigger grows
from `top` (or `top left` when left-aligned); a menu opening upward grows from `bottom`; a
modal centred on screen scales from its centre. A popover that grows from its own centre
looks detached from the button that opened it.

### 5. Curve and duration

| Situation | Easing | Duration |
|---|---|---|
| Enters, or responds to input | ease-out | 120–200 ms small UI, 200–300 ms panels/sheets |
| Moves from A to B while on screen | ease-in-out | 200–300 ms |
| Leaves | ease-out or `ease`, shorter | ~70% of the entrance (e.g. 200 → 140 ms) |
| Press / hover feedback | ease-out | 80–150 ms |
| Constant motion (spinner, progress) | linear | as needed |

Avoid **ease-in** for UI: it starts slow, exactly when the user is waiting for a response. Keep
frequent actions under ~300 ms. If the project has no tokens, these are good defaults:

```css
:root {
  --ease-out: cubic-bezier(0.22, 1, 0.36, 1);
  --ease-in-out: cubic-bezier(0.65, 0, 0.35, 1);
  --dur-fast: 120ms;   /* feedback */
  --dur-base: 180ms;   /* popovers, tooltips */
  --dur-slow: 260ms;   /* panels, sheets */
}
```

**Springs** fit gesture-driven motion: the element keeps the finger's velocity when released
and settles naturally. CSS has no physical spring; `linear()` can approximate a fixed spring
curve for a non-gesture entrance, while real velocity hand-off needs JS (a library already
present, or a small damped-spring step function on `requestAnimationFrame`). Keep overshoot
subtle (a few percent) in product UI.

### 6. Interruption

People click again before an animation ends. Transitions retarget from the current value;
keyframe animations jump back to their start. So anything that toggles (open/close, expand,
hover) is a transition, not a pair of keyframe animations. With WAAPI, start the next
animation from `getComputedStyle(el).transform` of the running one, then cancel the old.

### 7. Enter, exit, and lists

The popover and dialog pattern, no JS, exit faster than entrance:

```css
.menu[popover] {
  transform-origin: top left;
  opacity: 0;
  transform: scale(0.96) translateY(-4px);
  /* closed state: these timings drive the EXIT */
  transition: opacity 120ms ease-out, transform 120ms ease-out,
              overlay 120ms allow-discrete, display 120ms allow-discrete;
}
.menu[popover]:popover-open {
  opacity: 1;
  transform: none;
  /* open state: these timings drive the ENTRANCE */
  transition-duration: 180ms;
  transition-timing-function: var(--ease-out, ease-out);
}
@starting-style {
  .menu[popover]:popover-open { opacity: 0; transform: scale(0.96) translateY(-4px); }
}
```

The same shape works for `dialog[open]` (add `::backdrop` with its own opacity transition) and
for any element toggled between `display: none` and visible. Browsers that lack
`@starting-style` simply show the element without the entrance, which is an acceptable
fallback.

**Stagger** list entrances by 20–40 ms per item and cap it: past 6–8 items, the rest arrive
together, so the whole sequence stays under ~300 ms. Never stagger on every re-render or
filter keystroke.

**Height to auto**: prefer `interpolate-size: allow-keywords` (progressive; no animation where
unsupported) or the `grid-template-rows: 0fr → 1fr` wrapper. Both run layout per frame; fine
for one accordion, not for fifty rows.

## Interaction details

```css
@media (hover: hover) and (pointer: fine) {
  .card:hover { transform: translateY(-2px); }
}
.button { transition: transform 120ms var(--ease-out, ease-out); }
.button:active { transform: scale(0.97); }
```

Gate hover effects so touch screens do not keep a stuck hover after a tap. Press feedback at
`scale(0.97)` reads as "pressed" without looking squashed; skip it on large surfaces (a whole
card list) where it feels like the page moved. Disabled controls do not animate.

## Reduced motion

`prefers-reduced-motion: reduce` means **less movement**, not no feedback. Replace translation,
scaling, parallax and morphs with an opacity fade or an instant change; keep state changes
visible (an open menu still has to look open).

```css
@media (prefers-reduced-motion: reduce) {   /* after the rules above: it also wins in @starting-style */
  .menu[popover], .menu[popover]:popover-open { transform: none; }
  ::view-transition-group(*), ::view-transition-old(*), ::view-transition-new(*) {
    animation-duration: 1ms;
  }
}
```

- **The 0 s trap.** A transition whose duration and delay are both 0 never starts, so
  `transitionend` never fires and code waiting for it hangs (a panel never unmounts). Use
  `1ms` instead of `0s`, or do not depend on the event: WAAPI's `finished` promise resolves
  either way, and a fallback timer covers the rest.
- In JS: `matchMedia('(prefers-reduced-motion: reduce)').matches`, and listen for `change`.
- Anything that moves on its own for more than 5 seconds (carousel, marquee, looping
  background) needs a visible pause/stop control (WCAG 2.2.2). Default: no autoplay loops.
- No more than three flashes per second, ever.

## Performance

A frame has 16.7 ms at 60 Hz and 8.3 ms at 120 Hz, shared with your JavaScript. The browser
runs style → layout → paint → composite; the later the first stage a property touches, the
cheaper it is.

- Layout every frame: `width`, `height`, `top`/`left`, `margin`, `padding`, font size. Use
  `transform` instead (scale a box, translate a position; FLIP for reflows).
- Paint every frame: `box-shadow`, `background`, `color`, `filter: blur()` and
  `backdrop-filter` on large areas. Fade a pseudo-element that carries the shadow instead of
  animating the shadow; keep blurred areas small and static.
- Animating a CSS custom property on a parent restyles every descendant that inherits it.
  Register it as non-inherited, or animate the child directly:
  `@property --progress { syntax: "<number>"; inherits: false; initial-value: 0; }`
- `will-change: transform` only on a few elements, only shortly before and during the
  animation, removed afterwards. Leaving it everywhere costs memory and can blur text.
- When the main thread is busy (a stream rendering, a big list), CSS and WAAPI animations of
  transform/opacity keep running on the compositor; `requestAnimationFrame` loops do not.

**Diagnose in this order**: reproduce with DevTools CPU throttling (4×); record in the
Performance panel and look for long tasks and purple Layout / Recalculate Style blocks during
the animation; turn on Rendering › Paint flashing and Layer borders; slow the animation in the
Animations panel (10–25%) to see the curve itself. Fix the property first, then the JS doing
work per frame, and only then reach for `will-change`.

React aside: never `setState` on every frame or pointer move; that re-renders the tree 60
times a second. Write to a ref or a motion value (Motion/framer-motion's `useMotionValue`,
`useSpring`) and let the library update the style. A `transform` written as one string can be
handed to the compositor more readily than separate `x`/`y` values.

## Preview and check

- Run it on the project's own dev server on 127.0.0.1 or open the file via `file://`. Nothing
  is sent anywhere; no new dependency without asking; no git worktrees.
- Screenshots show end states only. To inspect mid-flight with the headless-ui-smoke skill,
  trigger the state, then freeze every animation at a known time before the shot:
  `--eval "document.getAnimations().forEach(a => { a.pause(); a.currentTime = 60 }); 0"`.
  The same `document.getAnimations()` lists each running animation's duration and easing,
  which makes a cheap assertion.
- Check once with reduced motion on (DevTools › Rendering › Emulate
  `prefers-reduced-motion`), once at 4× CPU throttling, and on a real phone when touch or
  gestures are involved.
- Accessibility beyond motion (focus, roles, contrast) belongs to the web-accessibility skill;
  visual polish beyond motion to the ui-craft skill.

## Report

BUILD: what animates now, its purpose, the values, reduced-motion behaviour and how you checked
it. REVIEW: the report from [REVIEW.md](REVIEW.md). Say plainly what you could not run.

Background: distilled from Emil Kowalski's animation skills and Vercel's web-interface-guidelines; rewritten, nothing copied.
