# UI craft — review checklist

Walk it on the rendered screen (desktop width and ~400px, light and dark), not on the CSS
alone. Each unchecked line that applies is a finding: `Pri | Where (file:line) | Problem |
Fix`, with P0–P3 as defined in `SKILL.md`. Skip lines that do not apply to the screen; say
which states you could not reach.

## Before you start

- [ ] I know what the screen is for and what the user does most often on it.
- [ ] I found the project's tokens (`:root` custom properties) and shared components, and I
      judge against them first.
- [ ] I ran the ui-doctor skill (static, and `--url` on the running screen) and took its
      `FIX` / `WARN` rows as located findings.
- [ ] I have screenshots of the states I can reach: default, empty, loading, error, long
      list, dialog open, narrow width, dark mode.

## 1. Hierarchy

- [ ] The thing the user came for is the most prominent element, early in reading order.
- [ ] Each region (dialog, form, toolbar, card) has at most one filled accent button.
- [ ] Destructive actions are not styled as the primary unless that is the dialog's purpose.
- [ ] Groups are separated by clearly more space than items inside them.
- [ ] No surface inside a surface inside a surface (no cards in cards).
- [ ] Borders, dividers and backgrounds each earn their place; spacing alone was tried first.
- [ ] Secondary information (timestamps, IDs, counts) is muted, not competing with content.
- [ ] Headings step down in a clear order; no two adjacent levels look the same.

## 2. Spacing and alignment

- [ ] Every gap, padding and margin is on the 4px-based scale (4, 8, 12, 16, 24, 32, 48, 64).
- [ ] Siblings are spaced with `gap`; components set no outer margin of their own.
- [ ] Nested rounded shapes use inner radius = outer radius − padding.
- [ ] Left edges of labels, inputs, headings and text in a column line up.
- [ ] Icons are optically centred on the first line of their text.
- [ ] Numeric columns are right-aligned; their headers align with them.
- [ ] Flex and grid children holding text have `min-width: 0`; nothing overflows the viewport.
- [ ] Nothing jumps when data, images, fonts or badges arrive (reserved space, aspect-ratio).
- [ ] Buttons whose label changes (Save → Saving…) keep their width.
- [ ] Scroll containers use `scrollbar-gutter: stable` where overflow comes and goes.
- [ ] Forms and prose sit in a readable column; wide screens do not stretch inputs edge to edge.

## 3. Typography

- [ ] One family (system stack or one self-hosted face), plus a mono for code and IDs.
- [ ] Five or six sizes at most, in rem, by role; body 16px (14px only in dense tables).
- [ ] No text below 12px.
- [ ] Running text is 45–75 characters wide.
- [ ] Line height fits the size: ~1.5 body, tighter for large headings.
- [ ] Two weights do most of the work; bold is not everywhere.
- [ ] Changing or aligned digits use `tabular-nums`.
- [ ] Headings use `text-wrap: balance`; paragraphs `text-wrap: pretty`.
- [ ] Real characters: `…`, `–` in ranges, `×` in dimensions, curly quotes, non-breaking space
      before units.
- [ ] Fonts are served from the app's origin, with `font-display: swap` and a metric-matched
      fallback (no visible reflow on load).

## 4. Colour

- [ ] Components use role tokens only; no raw hex or rgb in component CSS.
- [ ] The accent marks the primary action, selection and links — and little else.
- [ ] Neutrals are slightly tinted and come from one ramp; no stray fifth grey.
- [ ] Text meets 4.5:1, large text 3:1; input borders, meaningful icons and focus ring 3:1.
- [ ] No meaning carried by colour alone (errors, status, chart series).
- [ ] Dark mode: dark grey background, lighter raised surfaces, off-white text, borders still
      visible, accent adjusted, every state re-checked.
- [ ] `color-scheme` is set; form controls and scrollbars match the theme.
- [ ] `<meta name="theme-color">` matches the top of the page in each scheme.
- [ ] Hand the full contrast and colour-vision audit to the web-accessibility skill.

## 5. Every state

Controls:

- [ ] Default, hover, pressed, focus-visible, disabled, loading, selected and invalid all
      exist and look related.
- [ ] Hover styles sit inside `@media (hover: hover) and (pointer: fine)`.
- [ ] Disabled controls still read as controls, and the reason is discoverable.

Data:

- [ ] First load shows a skeleton or indicator at the final layout.
- [ ] Refresh keeps the old data visible while loading.
- [ ] Empty on first use explains what goes here and offers the first action.
- [ ] Empty because of a filter or search says so and offers to clear it.
- [ ] Error says what failed and offers retry; the rest of the screen still works.
- [ ] Partial results say how many failed or were left out.
- [ ] One item looks intentional, not like a broken list.
- [ ] Many items: count shown, pagination or virtual scroll, header stays usable.
- [ ] Long values truncate with the full value reachable (title, tooltip, detail view).

Page:

- [ ] Offline or server unreachable is a designed message, not a blank panel or raw error.
- [ ] No access / signed out says which and what to do next.
- [ ] Not found and stale data have a message (stale shows its age).
- [ ] Tab, filters, sort, search and the open item live in the URL; reload and back keep them.

## 6. Forms

- [ ] Every field has a visible label bound with `for` / `id`.
- [ ] Placeholders show example formats only, never the label.
- [ ] `type`, `inputmode` and `autocomplete` are set to what the field holds.
- [ ] Paste works everywhere, including codes and passwords.
- [ ] Validation runs on blur; a field with an error re-validates as the user types.
- [ ] Submit shows every error and focuses the first invalid field.
- [ ] Errors sit next to the field, linked with `aria-describedby`, and say how to fix it.
- [ ] Submit is disabled only while the request is in flight; double submit is blocked.
- [ ] Leaving with unsaved changes asks first — and only when something changed.
- [ ] Optional fields are marked "(optional)"; required is the default.

## 7. Feedback and latency

- [ ] Every press shows a pressed state at once, before any network call.
- [ ] Waits of 100 ms–1 s show a small delayed indicator that never flickers.
- [ ] Waits of 1–10 s show a skeleton, or a spinner with text.
- [ ] Waits over 10 s show progress and a Cancel.
- [ ] Optimistic updates roll back visibly with a message when the server says no.
- [ ] Reversible actions offer Undo instead of a confirm dialog.
- [ ] Confirm dialogs name the thing and the verb ("Delete 3 files").
- [ ] Toasts report background results; errors about the current action are inline.
- [ ] Toast region is `aria-live="polite"`; toasts with an action stay long enough to use.

## 8. Interface copy

- [ ] Buttons are verb + object; dialog buttons repeat the dialog's verb.
- [ ] One noun per concept across the whole app.
- [ ] Sentence case for labels, buttons, headings and menu items.
- [ ] Errors say what happened, why if known, and what to do now; no bare codes, no "Oops".
- [ ] Numbers, dates, relative times, plurals and lists go through `Intl`.
- [ ] Ellipsis only for in-progress states and items that open a further step.
- [ ] No developer words in the UI (null, undefined, NaN, payload, 500, stack traces).

## 9. Details

- [ ] Shadows are layered and consistent with the elevation tokens.
- [ ] Hit targets are at least 24×24px, 44×44px on touch.
- [ ] One icon family, one stroke width, sized to the adjacent text.
- [ ] Every interactive element shows a visible `:focus-visible` ring.
- [ ] Dialogs, drawers, menus and chat logs use `overscroll-behavior: contain`.
- [ ] Native elements (`<dialog>`, `<details>`, `<select>`, popover) are used before custom ones.
- [ ] Content people copy (IDs, messages, errors) is selectable.
- [ ] `cursor: pointer` only on things that act.
- [ ] Nothing looks browser-default by accident (a lone unstyled select, a blue visited link,
      a light scrollbar on a dark panel).
- [ ] Native `<select>` has explicit `color` and `background-color` (Windows dark theme).
- [ ] Brand names, code, IDs and file names carry `translate="no"`.
- [ ] Anchored headings have `scroll-margin-top` clear of the sticky header.
- [ ] `autofocus` only where typing is clearly the first step, never on phones.
- [ ] Looping animations are short muted `<video>`, not GIFs.

## 10. Restraint

- [ ] I tried removing a border, background, divider or icon before adding anything.
- [ ] Count on screen: ≤ 6 font sizes, ≤ 4 text colours, ≤ 3 radii, ≤ 3 shadow levels.
- [ ] One detail has character; everything else is quiet.

## 11. Speed

- [ ] The main content and the LCP image are in the first HTML; the LCP image has
      `fetchpriority="high"` and no `loading="lazy"`; images below the fold are lazy.
- [ ] Every press paints feedback in the next frame; long work yields or runs in a worker.
- [ ] Every image, video and iframe has `width`/`height` or `aspect-ratio`; late content has
      reserved space or overlays.
- [ ] Lists beyond a few hundred rows are virtualized; hidden panels render lazily.
- [ ] No `unload` handler; no `Cache-Control: no-store` on pages without secrets.
- [ ] Field numbers if the app has them (CrUX, `web-vitals`): LCP ≤ 2.5 s, INP ≤ 200 ms,
      CLS ≤ 0.1 at p75. Say so when only lab numbers exist.

## 12. Honest design

- [ ] Reject is as visible and as easy as accept; nothing pre-ticked.
- [ ] Cancelling, unsubscribing and deleting the account take about as many steps as signing up.
- [ ] The first price shown includes mandatory fees; a trial says when it ends and the price after.
- [ ] No fake urgency or scarcity, no confirmshaming, no trick questions.

## When it feels off but nothing above fails

Ask these on the screenshot, one at a time. Each "no" usually points to one fix.

1. **Squint**: blur your eyes (or the image). Is the first thing you see the thing the user
   came for? If a sidebar, a badge or a border wins, turn it down.
2. **Where would you click first?** If two places compete, one of them is not primary.
3. **Do groups read as groups?** Cover the borders with your thumb: would spacing alone still
   tell you what belongs together?
4. **Trace the edges.** Run a line down the left edge of the main column. How many distinct
   x positions does text start at? Each extra one needs a reason.
5. **How many greys?** Sample the text colours. More than three or four is noise.
6. **Does one colour do too many jobs?** If the accent is links, buttons, badges, selection,
   charts and icons, take it off all but two.
7. **Is anything default by accident?** A native select in a styled form, a system scrollbar
   on a dark panel, a focus ring in a colour from nowhere.
8. **Press everything.** Does each control answer at once? Does anything blink, jump or
   reflow when it answers?
9. **Read the labels aloud.** Would a new user know what each button does, and do two names
   mean the same thing?
10. **Switch to dark mode.** Does it look designed, or inverted? Are borders and raised
    surfaces still visible?
11. **Empty it, then fill it.** Clear the data, then load ten times more. Does the screen
    still look intended at both ends?
12. **What is the one memorable detail?** If there is none, the screen is correct but
    anonymous; if there are five, keep the best one.
