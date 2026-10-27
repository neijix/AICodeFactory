# ui-motion: vocabulary

Reverse lookup: what people say, the term to use, and the plain CSS/JS way to get it. Name the
effect first, then decide with SKILL.md whether it should exist at all.

## Entering, leaving, swapping

| They say | Term | How |
|---|---|---|
| "the bouncy popover open" | Scale-in with overshoot (pop-in) | `scale(0.95)` → `1` with a spring, or `linear()` / `cubic-bezier(0.34, 1.56, 0.64, 1)`; origin at the trigger |
| "it just fades in" | Fade-in | `opacity` 0 → 1, 120–200 ms ease-out; `@starting-style` for elements that just appeared |
| "slides in from the side" | Slide-in | `translateX(100%)` → `0` on a panel, ease-out ~250 ms; leaves the same way, faster |
| "rises up a little as it appears" | Fade-up (rise-in) | `opacity` + `translateY(8px)` → `0`, 160–220 ms ease-out |
| "the menu grows out of the button" | Origin-aware scale | `transform-origin` on the side facing the trigger + scale 0.96 → 1 |
| "the old one fades while the new appears" | Crossfade | stack both, swap `opacity`; across a DOM swap, `document.startViewTransition()` |
| "the picture flies into its full page" | Shared element transition | `view-transition-name: hero` on both states + `startViewTransition`; or FLIP with WAAPI |
| "one shape turns into another" | Morph | View Transitions on a shared name; SVG path morph only with matching point counts |
| "the panel unfolds" / "accordion" | Expand / collapse (disclosure) | `interpolate-size: allow-keywords` + `height: auto`, or `grid-template-rows: 0fr` → `1fr` |
| "items appear one after another" | Stagger | per-item `transition-delay: calc(var(--i) * 30ms)`, capped at ~8 items |
| "the sheet from the bottom on phones" | Bottom sheet | `translateY(100%)` → `0`, drag to dismiss with velocity hand-off |
| "the toast pops up then goes away" | Toast enter/exit | slide + fade from the edge it lives on; exit shorter; pause timer on hover/focus |
| "background dims behind the dialog" | Scrim / backdrop fade | `dialog::backdrop` opacity transition with `allow-discrete` on `display`/`overlay` |
| "the page changes smoothly between links" | Cross-document view transition | `@view-transition { navigation: auto; }` on both pages |
| "content jumps when items are removed" | Layout animation / FLIP | measure First, apply Last, Invert with `transform`, Play to `none` (WAAPI) |

## Loading and progress

| They say | Term | How |
|---|---|---|
| "grey boxes with a shine moving over" | Skeleton shimmer | a gradient on a pseudo-element, `translateX` keyframes, linear ~1.5 s; static under reduced motion |
| "the gentle breathing placeholder" | Skeleton pulse | `opacity` 0.6 ↔ 1 keyframes, ease-in-out ~1.2 s alternate |
| "the spinning circle" | Spinner | `rotate` keyframes, linear, infinite; show only after ~150–300 ms of waiting |
| "the three bouncing dots" | Typing indicator | three dots, `translateY` or `opacity` keyframes with staggered `animation-delay` |
| "the bar that fills" | Determinate progress | `transform: scaleX(var(--p))` with `transform-origin: left`, not `width` |
| "the bar that slides back and forth" | Indeterminate progress | a segment translated across with linear keyframes |
| "numbers roll up to the total" | Count-up / number ticker | `requestAnimationFrame` on text, `font-variant-numeric: tabular-nums`; not for live data |
| "text appears letter by letter" | Typewriter / streaming reveal | append text as it arrives; fake typing only on non-repeating marketing copy |

## Feedback and attention

| They say | Term | How |
|---|---|---|
| "the button squishes when clicked" | Press feedback | `:active { transform: scale(0.97) }`, 100 ms ease-out |
| "it lifts when I hover" | Hover lift | `translateY(-2px)` + shadow pseudo-element opacity, under `(hover: hover) and (pointer: fine)` |
| "the field shakes when wrong" | Shake (error wiggle) | short `translateX` keyframes ±4px, ~300 ms, once; plus a text error message |
| "the dot keeps pulsing" | Pulse | `scale`/`opacity` ring keyframes on a pseudo-element; stop after a few cycles |
| "it glows to get my eye" | Highlight / attention glow | fade a background or outline in, hold, fade out once |
| "the row flashes when it updates" | Change highlight (yellow fade) | background colour transition from accent to transparent, ~1 s, only on meaningful changes |
| "the check mark draws itself" | Stroke draw | SVG `stroke-dasharray` + `stroke-dashoffset` → 0, ~250 ms ease-out |
| "the icon swaps with a little turn" | Icon swap (crossfade + rotate/scale) | two icons stacked, `opacity` + `scale(0.8)` swap, ~150 ms |
| "the tab underline slides" | Moving indicator | one indicator element, `transform: translateX() scaleX()` to the active tab's box |
| "the switch knob slides" | Toggle thumb transition | `translateX` on the thumb, 150 ms ease-out; colour transition on the track |

## Physics and gestures

| They say | Term | How |
|---|---|---|
| "springy" / "physical" | Spring | stiffness + damping (or duration + bounce); JS step function or library; `linear()` for a fixed curve |
| "keeps going after I let go" | Momentum (inertia) | carry release velocity, decay it each frame (or native scroll) |
| "the iOS rubber-band" | Rubber-banding (overscroll resistance) | past the edge, move by `limit * (1 - 1 / (d * 0.55 / limit + 1))` instead of `d` |
| "flick it away to close" | Swipe to dismiss | dismiss if distance or release velocity crosses a threshold, else spring back |
| "it snaps to the nearest one" | Snap points | CSS `scroll-snap-type` / `scroll-snap-align`; for drags, settle to the nearest point |
| "follows my finger exactly" | Direct manipulation (1:1 tracking) | Pointer Events + `setPointerCapture`, write `transform` in rAF, no transition while dragging |
| "the throw keeps the speed of my hand" | Velocity hand-off | measure velocity from the last pointer samples and pass it as the spring's initial velocity |

## Scroll

| They say | Term | How |
|---|---|---|
| "background moves slower than the page" | Parallax | `animation-timeline: scroll()` on `translateY`, behind `@supports`; off under reduced motion |
| "things animate as I scroll to them" | Scroll-triggered reveal | `IntersectionObserver` toggles a class once; or `animation-timeline: view()` |
| "animation tied to the scroll position" | Scroll-driven animation | `animation-timeline: scroll()` / `view()` with `animation-range`; static fallback |
| "the progress bar at the top as you read" | Scroll progress indicator | `scaleX` driven by `animation-timeline: scroll(root)` |
| "the header shrinks when I scroll" | Condensing / sticky header | `position: sticky` + a scroll-driven or class-toggled `transform`/`opacity` change |
| "scroll moves the page in big jumps" | Scroll-jacking | avoid; native scroll + `scroll-snap` if sections must align |
| "smooth scroll to the section" | Smooth scrolling | `scroll-behavior: smooth` inside `prefers-reduced-motion: no-preference` |

## Loops and text

| They say | Term | How |
|---|---|---|
| "logos scrolling endlessly" | Marquee (ticker) | duplicate the track, `translateX(-50%)` linear infinite; pause on hover and a visible pause control |
| "text cycles through words" | Rotating text | crossfade or `translateY` per word on a timer; pausable, stops under reduced motion |
| "slowly shifting colour background" | Gradient drift (ambient) | animate `background-position` on a small area, or a transformed oversize layer; pausable |

## Animation principles and easing names

| They say | Term | How |
|---|---|---|
| "a little pull back before it moves" | Anticipation | keyframe that moves slightly opposite first, or `cubic-bezier` with a negative first y |
| "it overshoots and settles" | Follow-through / overshoot | spring with low damping, or `cubic-bezier(.., >1, .., ..)` |
| "parts lag behind the main motion" | Overlapping action (offset) | children with a small extra delay or softer spring |
| "starts fast, ends gently" | Ease-out (deceleration) | `cubic-bezier(0.22, 1, 0.36, 1)` |
| "starts slow, ends fast" | Ease-in (acceleration) | `cubic-bezier(0.55, 0, 1, 0.45)`; only for things leaving for good |
| "slow, fast, slow" | Ease-in-out | `cubic-bezier(0.65, 0, 0.35, 1)` |
| "same speed throughout" | Linear | `linear`; spinners, progress, marquees |
| "steps like a flipbook" | Stepped easing | `steps(n)` for sprite sheets or a ticking clock hand |
| "a custom curve with bounces" | `linear()` easing | `linear(0, 1.1 60%, 0.98 80%, 1)`-style point lists, generated from a spring |
| "how long it waits before starting" | Delay | `transition-delay`; keep under ~100 ms except for stagger and hover-intent |
