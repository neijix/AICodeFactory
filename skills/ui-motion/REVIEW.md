# ui-motion: REVIEW mode

Read-only. Do not edit, format or "quickly fix" anything until the user asks to apply the
findings. The output is a report the user (or another agent) can act on without rereading
the code.

## Scope it

- **Audit**: the motion that exists (a diff, a component, a page, the whole app).
- **Opportunities**: places that change state abruptly and might benefit from motion, and
  places that animate but should not.
- Usually both. State which, and which files or screens you covered.

Run the recon from SKILL.md first. Then open the app on its own dev server (127.0.0.1) or via
`file://` if you can; reading CSS alone misses what actually moves. If you cannot run it, say
so in the report and mark findings that need a visual check.

## Inventory

List every animation you found before judging any of them, one line each:

```
file:line  element / trigger  ->  properties  duration  easing  tool (transition / keyframes / WAAPI / VT / library)
```

Also note the motion tokens (or their absence), the library in use, and whether
`prefers-reduced-motion` is handled anywhere.

## Checklist by category

### Purpose and frequency
- [ ] Each animation has a nameable purpose: orientation, feedback, continuity or attention.
- [ ] Nothing seen hundreds of times a day carries more than a brief fade.
- [ ] Keyboard-triggered UI (command palette, shortcut menus, focus moves) feels instant.
- [ ] Data-dense screens are calm: no per-tick slides, flashes or count-ups on live numbers.
- [ ] No staged entrance on a work screen's first paint.
- [ ] Attention effects (pulse, shake, glow) are one-shot and reserved for something urgent.

### Tool choice
- [ ] The cheapest tool that works: transition before keyframes before WAAPI before a library.
- [ ] State that can flip back uses transitions (retargets), not keyframe pairs (restart).
- [ ] Enter/exit of `display: none`, popovers and dialogs uses `@starting-style` with
      `transition-behavior: allow-discrete` rather than JS class juggling with timeouts.
- [ ] View Transitions are feature-detected with a direct fallback.
- [ ] No library added for something CSS does; no second library next to an existing one.

### Properties and performance
- [ ] Only `transform` and `opacity` animate on anything large or frequent.
- [ ] No `transition: all` (and no `transition` without a property list in a shared class).
- [ ] No animated `width`, `height`, `top`, `left`, `margin`, `padding` on more than a single
      small element; reflows use FLIP or transform.
- [ ] No animated `box-shadow`, `filter: blur()` or `backdrop-filter` on large areas.
- [ ] `will-change` is temporary and on few elements, not in a global stylesheet rule.
- [ ] No inherited custom property animated on a large subtree (or it is `@property` with
      `inherits: false`).
- [ ] JS animation loops do no layout reads after writes in the same frame (no thrashing),
      and stop when the element is gone or hidden.
- [ ] React: no `setState` per frame or per pointer move; refs or motion values instead.

### Easing and duration
- [ ] Entering and responding motion is ease-out; on-screen moves are ease-in-out.
- [ ] No ease-in on UI that responds to input.
- [ ] Small feedback 80–200 ms, panels 200–300 ms, frequent actions under ~300 ms.
- [ ] Exits shorter than entrances.
- [ ] Linear only for constant motion (spinners, progress, marquee).
- [ ] Values come from shared tokens, not a scatter of one-off numbers.
- [ ] Springs (if any) settle quickly with little overshoot in product UI.

### Origin and direction
- [ ] Popovers, menus and tooltips grow from their trigger (`transform-origin` on the side
      facing it), not from their own centre.
- [ ] Panels and sheets move along the axis they come from and leave the same way.
- [ ] Scale-in starts near full size (0.9–0.97), never from 0.
- [ ] Direction is consistent: the same kind of thing always enters from the same side.

### Interruption and state
- [ ] Clicking again mid-animation reverses smoothly from where it is.
- [ ] Rapid toggling does not queue animations or leave elements half-visible.
- [ ] Nothing depends on `transitionend` / `animationend` without a fallback (the event may
      never fire: zero duration, element removed, property not actually changing).
- [ ] Unmount waits for the exit, but a new open cancels a pending unmount.

### Interaction
- [ ] Hover effects sit under `@media (hover: hover) and (pointer: fine)`.
- [ ] Press feedback is subtle (`:active` scale about 0.97, 80–150 ms) and absent on huge
      surfaces and disabled controls.
- [ ] Drag and swipe follow the pointer 1:1, then hand the release velocity to the settle.
- [ ] Past a boundary, drags rubber-band (resistance) instead of stopping dead or going free.
- [ ] Focus moves do not wait for an animation to finish.

### Accessibility
- [ ] `prefers-reduced-motion: reduce` replaces movement with a fade or an instant change,
      and the state change stays visible.
- [ ] Reduced motion uses a tiny duration (1 ms), not `0s`, where code awaits an end event.
- [ ] Anything moving on its own for more than 5 s has a visible pause/stop (WCAG 2.2.2).
- [ ] No autoplay loops by default; no parallax or scroll-jacking without a reduced-motion
      opt-out.
- [ ] Nothing flashes more than three times per second.
- [ ] Content is readable and operable before and during the animation (no invisible-but-
      focusable elements left at `opacity: 0`).

### Code hygiene
- [ ] Motion values live in one place (tokens or a small module), not copied per component.
- [ ] Listeners, observers, `requestAnimationFrame` loops and timers are cleaned up.
- [ ] Scroll-driven animations (`animation-timeline`) sit behind `@supports` with a static
      fallback.

## Opportunity hunt

Look for abrupt state changes that lose the user:

- A panel, accordion or details block that snaps open or closed.
- A dialog, popover, toast or menu that pops in with no entrance (or vanishes with no exit).
- List items inserted or removed so that everything below jumps (FLIP or a short height
  collapse).
- A tab or segmented control whose active indicator teleports (slide the indicator).
- Loading → content swaps that flash (crossfade, or a skeleton with the same layout).
- A copy, save or send button with no confirmation (a short icon swap or check mark).
- Drag interactions where the item does not follow the pointer.

**Reject** candidates as deliberately as you accept them, and list the rejects in the report:
table rows and log lines that render by the hundred, keyboard navigation, text inputs and
caret moves, live numbers, anything on a screen the user stares at all day, decorative motion
on first load, and anything whose only argument is "it would look nice".

## Severity

- **blocker**: harms use or access. Ignores reduced motion for large movement, autoplay over
  5 s without pause, flashing, motion that hides or delays content or focus, visible jank on a
  common action, an end-event dependency that can leave UI stuck.
- **should**: wrong feel or avoidable cost. Ease-in on a response, durations over ~300 ms on
  frequent actions, wrong `transform-origin`, keyframes on a toggle, `transition: all`,
  layout properties animated, hover without the media gate, exits as slow as entrances.
- **nice**: polish. Token consolidation, a missing subtle exit, stagger tuning, an
  opportunity that would add continuity.

## Report template

```markdown
# Motion review: <scope>

Mode: audit | opportunities | both. Covered: <files / screens>. Ran the app: yes (<url>) | no (<why>).
Tone: <calm tool UI | expressive marketing | ...>. Tokens: <found / none>. Library: <name / none>.
Reduced motion handled: <where / nowhere>.

## Inventory
| Where | Trigger | Properties | Duration | Easing | Tool |
|---|---|---|---|---|---|
| src/menu.css:12 | menu open | opacity, transform | 180ms | ease-out | transition |

## Findings
### [blocker] <one-line title>
- Where: path/to/file.css:42
- What happens: <observed or read behaviour>
- Why it matters: <user impact>
- Fix: <exact values, e.g. `transition: opacity 150ms var(--ease-out), transform 150ms var(--ease-out)`>

### [should] ...
### [nice] ...

## Opportunities (proposed, not applied)
- path:line: <state change> -> <motion, properties, duration, easing>, purpose: <orientation | feedback | continuity | attention>

## Left static on purpose
- path:line: <candidate>, rejected because <frequency / density / keyboard / no purpose>

## Verdict
<ship | ship after the "should" fixes | blocked by N blocker(s)>. Next step: <apply all / apply blockers / nothing>.
```

Keep every finding tied to a file and line, give the exact replacement value rather than
"make it faster", and say which findings you saw running versus inferred from the code.
