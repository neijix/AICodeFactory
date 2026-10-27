# WCAG 2.2 AA checklist for web apps

One line per success criterion that a typical app page can fail, grouped by principle, with
the check to run. Level A and AA only. Criteria that rarely apply to a small web app (live
captions, sign language, audio description) are listed briefly at the end.

Mark each item **Pass**, **Fail** (with file:line and a fix), **N/A**, or **Not tested** (say
why). New in WCAG 2.2 are tagged *(2.2)*.

## 1. Perceivable

### 1.1 Text alternatives
- [ ] **1.1.1 Non-text Content (A)** — Every `<img>` has `alt`: descriptive when it carries
  meaning, empty when decorative. Icon-only buttons and links have a name. Meaningful SVGs
  have `role="img"` plus a name; decorative ones `aria-hidden="true"`. CAPTCHA has an
  alternative.

### 1.2 Time-based media
- [ ] **1.2.1 Audio-only and Video-only (A)** — Prerecorded audio has a transcript; silent
  video has a text or audio description.
- [ ] **1.2.2 Captions, Prerecorded (A)** — Videos with speech have captions.
- [ ] **1.2.3 / 1.2.5 Audio Description (A / AA)** — Video whose visuals matter has audio
  description or a full text alternative.

### 1.3 Adaptable
- [ ] **1.3.1 Info and Relationships (A)** — Headings are `<h1>`–`<h6>`, lists are
  `<ul>`/`<ol>`, data tables use `<th>` with `scope`, inputs have `<label>`, groups use
  `<fieldset>`/`<legend>`, landmarks (`header`, `nav`, `main`, `footer`) are present. Nothing
  that looks like structure is only styling.
- [ ] **1.3.2 Meaningful Sequence (A)** — DOM order reads in a sensible order; CSS
  (`order`, grid placement, absolute positioning) does not scramble it.
- [ ] **1.3.3 Sensory Characteristics (A)** — Instructions do not rely only on shape, place,
  colour or sound ("click the green button on the right").
- [ ] **1.3.4 Orientation (AA)** — The page works in portrait and landscape; no forced
  orientation lock.
- [ ] **1.3.5 Identify Input Purpose (AA)** — Fields about the user carry the right
  `autocomplete` token (`name`, `email`, `tel`, `street-address`, `current-password`,
  `new-password`, `one-time-code`).

### 1.4 Distinguishable
- [ ] **1.4.1 Use of Color (A)** — Errors, states, required fields, chart series and links in
  text are distinguishable without colour (icon, text, underline, pattern).
- [ ] **1.4.2 Audio Control (A)** — Audio that plays on its own for more than 3 s can be
  paused or muted.
- [ ] **1.4.3 Contrast, Minimum (AA)** — Text 4.5:1; large text (24 px, or 18.66 px bold) 3:1.
  Check placeholder text, disabled-looking-but-active text, text on images, both themes.
- [ ] **1.4.4 Resize Text (AA)** — At 200 % browser zoom nothing is cut off, overlapped or
  lost. Zoom is not disabled in the viewport meta.
- [ ] **1.4.5 Images of Text (AA)** — Text is real text, not pictures of text (logos excepted).
- [ ] **1.4.10 Reflow (AA)** — At 320 CSS px wide (1280 px at 400 %) there is no horizontal
  scrolling for text content; tables, maps and code blocks may scroll in their own box.
- [ ] **1.4.11 Non-text Contrast (AA)** — 3:1 against neighbours for input borders, toggles,
  checkboxes, focus indicators, meaningful icons and chart lines.
- [ ] **1.4.12 Text Spacing (AA)** — With line-height 1.5, paragraph spacing 2 em, letter
  spacing 0.12 em and word spacing 0.16 em applied, no text clips (no fixed `height` on text
  boxes).
- [ ] **1.4.13 Content on Hover or Focus (AA)** — Tooltips and popovers that appear on hover
  or focus can be dismissed with Escape without moving the pointer, can be hovered themselves,
  and stay until dismissed or no longer relevant.

## 2. Operable

### 2.1 Keyboard accessible
- [ ] **2.1.1 Keyboard (A)** — Every action works with the keyboard: buttons, menus, drag and
  drop (offer a non-drag alternative), sliders, custom widgets. No clickable `<div>`/`<span>`.
- [ ] **2.1.2 No Keyboard Trap (A)** — Tab and Shift+Tab leave every component; embedded
  editors and iframes document how to leave. A modal dialog keeps focus inside but closes with
  Escape.
- [ ] **2.1.4 Character Key Shortcuts (A)** — Single-letter shortcuts can be turned off or
  remapped, or only work while the relevant control has focus.

### 2.2 Enough time
- [ ] **2.2.1 Timing Adjustable (A)** — Session timeouts warn and allow extending; toasts that
  carry information stay long enough or can be reopened.
- [ ] **2.2.2 Pause, Stop, Hide (A)** — Carousels, tickers, auto-refreshing feeds and
  animations longer than 5 s can be paused.

### 2.3 Seizures and physical reactions
- [ ] **2.3.1 Three Flashes or Below Threshold (A)** — Nothing flashes more than three times a
  second.

### 2.4 Navigable
- [ ] **2.4.1 Bypass Blocks (A)** — A skip link to `<main>`, and landmarks.
- [ ] **2.4.2 Page Titled (A)** — `<title>` names the page and the app; single-page apps update
  it on view change.
- [ ] **2.4.3 Focus Order (A)** — Tab order follows the visual and logical order; no positive
  `tabindex`; focus moves into opened dialogs and back to the opener on close.
- [ ] **2.4.4 Link Purpose, In Context (A)** — Link text, with its sentence or list item, says
  where it goes.
- [ ] **2.4.5 Multiple Ways (AA)** — In a multi-page site, more than one way to find a page
  (navigation plus search or a site map).
- [ ] **2.4.6 Headings and Labels (AA)** — Headings and labels describe their content and
  purpose.
- [ ] **2.4.7 Focus Visible (AA)** — Keyboard focus is always visible; no `outline: none`
  without a `:focus-visible` replacement.
- [ ] **2.4.11 Focus Not Obscured, Minimum (AA)** *(2.2)* — The focused element is not fully
  hidden by a sticky header, footer, cookie banner or chat widget (`scroll-padding`).

### 2.5 Input modalities
- [ ] **2.5.1 Pointer Gestures (A)** — Pinch, swipe or multi-point gestures have a single-tap
  alternative (buttons for a carousel, zoom controls for a map).
- [ ] **2.5.2 Pointer Cancellation (A)** — Actions fire on release (`click`), not on
  `pointerdown`; moving off the target before release cancels.
- [ ] **2.5.3 Label in Name (A)** — The accessible name contains the visible label text, in
  the same words.
- [ ] **2.5.4 Motion Actuation (A)** — Shake or tilt features have an on-screen alternative and
  can be turned off.
- [ ] **2.5.7 Dragging Movements (AA)** *(2.2)* — Anything done by dragging (reorder, slider,
  sheet, split pane) can also be done with single taps or clicks (move up/down buttons,
  arrow keys, tap to snap).
- [ ] **2.5.8 Target Size, Minimum (AA)** *(2.2)* — Pointer targets are at least 24 x 24 CSS
  px, or spaced so a 24 px circle around each does not touch another target. Inline links in
  text are exempt.

## 3. Understandable

### 3.1 Readable
- [ ] **3.1.1 Language of Page (A)** — `<html lang="en">` (or the right language).
- [ ] **3.1.2 Language of Parts (AA)** — Passages in another language carry their own `lang`.

### 3.2 Predictable
- [ ] **3.2.1 On Focus (A)** — Focusing a control does not submit, navigate or open a new
  window.
- [ ] **3.2.2 On Input (A)** — Changing a select or checkbox does not navigate or submit
  unexpectedly, unless the user was told beforehand.
- [ ] **3.2.3 Consistent Navigation (AA)** — Navigation repeated across pages keeps the same
  order.
- [ ] **3.2.4 Consistent Identification (AA)** — The same function has the same name and icon
  everywhere ("Delete" is not "Remove" on the next page).
- [ ] **3.2.6 Consistent Help (A)** *(2.2)* — Help (contact link, chat, FAQ) sits in the same
  place on every page that has it.

### 3.3 Input assistance
- [ ] **3.3.1 Error Identification (A)** — Errors are described in text and the field is
  marked (`aria-invalid="true"`, message linked with `aria-describedby`).
- [ ] **3.3.2 Labels or Instructions (A)** — Every input has a visible label; required fields
  and formats are stated before the user types, not only after an error.
- [ ] **3.3.3 Error Suggestion (AA)** — The message says how to fix it ("Use 8 or more
  characters"), not just "Invalid".
- [ ] **3.3.4 Error Prevention, Legal/Financial/Data (AA)** — Deleting data, payments and
  submissions that matter can be reviewed, confirmed or undone.
- [ ] **3.3.7 Redundant Entry (A)** *(2.2)* — Information already given in the same process is
  filled in or selectable, not asked again.
- [ ] **3.3.8 Accessible Authentication, Minimum (AA)** *(2.2)* — Sign-in does not depend on
  remembering or transcribing: paste is allowed in password and code fields, password managers
  work (`autocomplete`), no puzzle-only CAPTCHA.

## 4. Robust

- [ ] **4.1.2 Name, Role, Value (A)** — Every control exposes a role, a name, and its current
  state (`aria-expanded`, `aria-pressed`, `aria-selected`, `aria-checked`, `aria-current`),
  kept in sync by the script. Native elements first; custom widgets follow the WAI-ARIA
  Authoring Practices pattern. Nothing focusable sits inside `aria-hidden="true"`.
- [ ] **4.1.3 Status Messages (AA)** — Saved, copied, results-count, upload-failed and
  reply-finished messages are announced through a live region already in the DOM
  (`role="status"`, `role="alert"` for errors) without moving focus.

(4.1.1 Parsing was removed in WCAG 2.2; duplicate ids still break `for` and `aria-*`
references, so keep ids unique anyway.)

## Beyond the criteria (good practice, not a WCAG failure on its own)

- [ ] `prefers-reduced-motion: reduce` removes large movement, parallax and auto-scrolling.
- [ ] `prefers-contrast: more` and `forced-colors: active` keep borders, focus rings and
  icons visible (use real `border`/`outline`, `currentColor`, system colours).
- [ ] Touch targets are 44 x 44 px on phone layouts (WCAG 2.5.5 AAA level; worth meeting).
- [ ] Dialogs use native `<dialog>` + `showModal()`; custom overlays set `inert` on the page.
- [ ] Toasts never take focus; destructive "Undo" toasts have another route to the action.
- [ ] Submit buttons are not disabled without a visible reason.
- [ ] Streaming text (chat replies) is announced once on completion, not per token.
- [ ] Headings form an outline with no skipped levels; one `<h1>`.
- [ ] Every page passes a keyboard-only run and a five-minute screen-reader smoke test.

## Rarely relevant for a small app (check if the page has the content)

- 1.2.4 Captions, Live (AA) — live video with speech.
- 1.4.2 Audio Control — any auto-playing sound.
- 2.3.1 Three Flashes — video, games, animated warnings.

## Recording results

```
Page: /settings (static/settings.html, static/settings.js)
Tested: keyboard, VoiceOver (Safari 18), headless AX tree, 200 % zoom, 320 px
Not tested: NVDA (no Windows machine), forced colours

[Serious] 2.4.7 Focus Visible — static/style.css:12
  `button { outline: none }` removes focus everywhere.
  Fix: delete it; add a `:focus-visible` outline (2 px, 3:1 against the background).
```
