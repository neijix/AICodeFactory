---
name: ui-stress-test
description: "Use when the user asks to stress-test, break, or find edge cases in a component or screen; says \"try the worst case\", \"what if the name is really long\", \"what about zero items\" or \"does it work in Arabic\"; reports text overflowing, overlapping, cut off or pushing a button off-screen; or before calling done a list, card, table, header, badge or form that shows user-supplied data. Feeds the UI worst-case fake data (long and unbreakable strings, empty and missing fields, huge counts, RTL and non-Latin scripts, emoji, extreme dates, numbers and images, slow or failed loads) behind a dev-only toggle, screenshots it narrow and wide with headless Chrome, and reports every break with its CSS or JS fix."
compatibility: Screenshots use the headless-ui-smoke skill (Chrome, Edge, Chromium or Brave, plus uv). Plain HTML/CSS/JS first; React notes included.
---

# UI stress test

A layout built against tidy sample data ("Jane Doe", 3 items, "$12.00") looks finished until the
first real user arrives with a 40-character surname, an email with no break opportunity, 1 284 917
unread messages or a name written right to left. This skill feeds a component its worst cases on
purpose, looks at the result in a real browser, and fixes what breaks while it is cheap.

The work is: list what the UI shows, pick the nastiest plausible value for each field, render
those values through the real rendering code, screenshot, report, fix.

## Ground rules

- **Fake data only, made on this machine.** Every value comes from `CATALOG.md` (next to this
  file) or is invented on the spot. Never copy rows from a real database, a log, a support ticket
  or a production API "because they are realistic", and never send the fake data anywhere.
- **No network for sample data.** No lorem-ipsum services, no random-user APIs, no placeholder
  image hosts. Images are generated locally (inline SVG or a canvas data URL).
- **The toggle is dev-only.** It is off unless a development flag is on, it is never the
  default, and before the commit it is either deleted or provably gated (see "Before you
  commit").
- **Real render path.** Inject the fake data where real data enters the view (the fetch result,
  the store, the props), so the same templates, formatters and CSS run. A separate "demo page"
  that re-implements the markup tests nothing.
- **Fix with agreement.** Report first. Apply fixes when the user asked for them up front, or
  after they say which to take. Some truncation choices are product decisions.

## 1. Inventory the data

Read the component and write down every value it displays or depends on. For each, note:

| Field | Type | Where shown | Container | Current assumption |
|---|---|---|---|---|
| `name` | text | card header, avatar alt | flex row with a menu button | short, one line |
| `email` | text | under the name | fixed-width column | has dots to break on |
| `unread` | integer | badge | 20 px circle | 0 to 99 |
| `items` | list | body | grid | 1 to 10 entries |
| `avatar` | image URL | header | 40 px box | square, loads fast |

Do not forget the values people overlook: button and tab labels (they get translated), dates
and their time zone, currency and its locale, the empty list, the "still loading" moment and
the failed request.

## 2. Pick the worst cases

For each field, take the matching categories in `CATALOG.md`. A good set for one screen is
usually 5 to 8 records, each record stressing several fields at once, plus one record that is
perfectly ordinary so you can see the baseline next to the extremes. Always include:

- one very long value and one unbreakable value for every text field;
- one empty and one missing (`null`, absent key) value;
- the counts 0, 1 and something huge;
- one right-to-left record and one emoji-heavy record;
- the empty list, the loading state and the error state.

## 3. Render behind a dev-only toggle

One query parameter drives it: `?demo=worst` (and `?demo=empty`, `?demo=loading`,
`?demo=error` for the states). It only works when the page knows it runs in development.

The server decides the flag. In a small Python app, render the dev script tag only when a
setting is on, so the file never reaches a production page:

```python
IS_DEV = os.environ.get("APP_DEV") == "1"   # off unless set
DEV_TAGS = '<script src="/dev/worst-case.js"></script>' if IS_DEV else ""
```

Serve `/dev/` only when `IS_DEV` is true as well. The script itself checks again:

```js
// dev/worst-case.js: development only, never served in production
window.DemoData = (() => {
  const mode = new URLSearchParams(location.search).get('demo'); // worst | empty | loading | error
  const never = new Promise(() => {});
  return {
    mode,
    // Wrap the one function that loads the view's data.
    wrap(load) {
      if (!mode) return load;
      return async (...args) => {
        if (mode === 'loading') return never;
        if (mode === 'error') throw new Error('Demo: the request failed');
        if (mode === 'empty') return [];
        if (mode === 'worst') return worstCaseItems(); // built from CATALOG.md
        return load(...args);
      };
    },
  };
})();
```

```js
// app.js: the only change in app code, and it is a no-op without the dev script
const loadItems = window.DemoData ? window.DemoData.wrap(fetchItems) : fetchItems;
```

**React or another framework**: read the parameter once in the data layer (the query function,
the loader, the store's fetch) and guard it with the bundler's dev constant
(`import.meta.env.DEV`, or `process.env.NODE_ENV !== 'production'`) so the production build
drops the branch. Do not thread a `demo` prop through components.

### Mark overflow automatically

Eyes miss a 3 px overflow. While `demo` is set, outline anything whose content spills out of
its box and report it through `console.error`, which the headless-ui-smoke script turns into a
`FAIL` line:

```js
window.markOverflow = () => {
  const found = [];
  for (const el of document.body.querySelectorAll('*')) {
    const style = getComputedStyle(el);
    if (el.clientWidth === 0 || style.overflowX !== 'visible') continue; // scrollers are fine
    if (el.scrollWidth > el.clientWidth + 1) {
      el.style.outline = '2px solid red';
      found.push(el.tagName.toLowerCase() + (el.className ? '.' + [...el.classList].join('.') : ''));
    }
  }
  if (document.documentElement.scrollWidth > innerWidth) found.unshift('page scrolls sideways');
  if (found.length) console.error('[worst-case] overflow:', found.join(', '));
  return found.length;
};
```

## 4. Screenshot narrow and wide

Use the headless-ui-smoke skill's script. Start the app on a free port with throwaway data and
the dev flag on, then shoot every mode at a phone width and a desktop width (add a middle width
such as 768 px if the layout has a breakpoint there):

```bash
SMOKE=~/.agents/skills/headless-ui-smoke/scripts/cdp_smoke.py
for size in 320x720 1440x900; do
  uv run "$SMOKE" "http://127.0.0.1:8765/?demo=worst" \
    --wait-for "document.querySelectorAll('.item').length > 0" \
    --eval "markOverflow()" \
    --forbid-text "undefined" --forbid-text "NaN" --forbid-text "[object Object]" \
    --full-page --shot "/tmp/worst-$size.png" --size "$size"
done
```

Repeat with `?demo=empty`, `?demo=loading` and `?demo=error` (for `loading`, the wait-for
condition is the spinner or skeleton being present). Keep the PNGs in a temp folder, not in the
repository. Then **open every screenshot and look at it**: the overflow marker finds spills, not
a clipped badge, an unreadable contrast, a misaligned column or a blank card.

## 5. Report each break

One entry per problem, worst first. Severity: **broken** (content unreadable, unreachable or
wrong), **ugly** (readable but clearly unfinished), **acceptable** (say why).

```text
1. broken: long name pushes the "..." menu out of the card
   Where: .card-header, 320 px, record "long multi-word name"
   Shot:  /tmp/worst-320x720.png (first card, top right)
   Cause: .title is a flex item with the default min-width: auto
   Fix:   .title { min-width: 0; overflow-wrap: anywhere; }
```

End with what held up ("the table survived every record at 1440 px") so the user knows what was
actually tested.

## 6. Fix

| Symptom | Fix |
|---|---|
| A flex or grid child refuses to shrink and pushes siblings out | `min-width: 0` on the item; in grid use `minmax(0, 1fr)` instead of `1fr` |
| An email, URL, hash or path runs past its box | `overflow-wrap: anywhere` (keeps normal words whole, breaks the unbreakable) |
| A one-line field in a fixed row gets too long | `white-space: nowrap; overflow: hidden; text-overflow: ellipsis` and a `title` with the full value |
| A description grows the card without limit | clamp it: `display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 3; overflow: hidden` (plus `line-clamp: 3`) |
| Numbers jump around or misalign in a column | `font-variant-numeric: tabular-nums`, right-aligned |
| A huge count breaks a badge | `Intl.NumberFormat` with `notation: 'compact'`, exact value in `title` |
| "1 items", "0 file" | `Intl.PluralRules` (below), never `n + ' items'` |
| The empty list is a blank area | an empty state: what this is, why it is empty, the one action that fills it |
| Nothing shows while loading, or a failure is silent | a loading state that keeps the layout's size, an error state with a retry |
| A missing field prints `undefined`, `null` or a dangling separator | fall back to a dash or hide the row, and drop the separator with it |
| RTL text scrambles punctuation or numbers around it | `dir="auto"` on the element holding user text; inline, wrap it in `<bdi>` |
| A user image is huge, tiny or the wrong shape | fixed box: `width`/`height` attributes, `aspect-ratio`, `object-fit: cover`, `max-width: 100%` |
| A long button or tab label wraps into a mess | let the group wrap (`flex-wrap: wrap`), use `min-width` not `width`, overflow tabs into a scroller or a "More" menu |
| JS truncation cuts an emoji or an accent in half | truncate by grapheme with `Intl.Segmenter`, or let CSS do it |
| Dates shift by a day or show the server's zone | format with `Intl.DateTimeFormat` and an explicit `timeZone` |

```js
const compact = new Intl.NumberFormat(undefined, { notation: 'compact', maximumFractionDigits: 1 });
badge.textContent = compact.format(count);       // 1284917 -> "1.3M"
badge.title = count.toLocaleString();            // full value on hover

const plural = new Intl.PluralRules('en');
const FILES = { one: 'file', other: 'files' };
label.textContent = `${count} ${FILES[plural.select(count)] ?? FILES.other}`;

const graphemes = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
function truncate(text, max) {
  const parts = Array.from(graphemes.segment(text), (s) => s.segment);
  return parts.length <= max ? text : parts.slice(0, max - 1).join('') + '…';
}
```

Accessibility follows from many of these fixes (a truncated label still needs its full text for
assistive tech, via `title` or visually hidden text); the web-accessibility skill covers that
side, and the ui-craft skill covers the visual polish once nothing breaks.

After fixing, run the same screenshots again and compare: every entry in the report should be
gone or moved to "acceptable" with a reason.

## Before you commit

- The toggle is gone, or it cannot turn on in production: the dev script is only served with
  the dev flag, the flag defaults to off, and the production build or page does not contain it.
  Check: load the page without the flag and with `?demo=worst`; it must show real data.
- No fake record leaked into fixtures, seed files or snapshots the app ships.
- Screenshots stay out of the repository.
- If the project keeps a worst-case fixture for its tests (a good idea), it lives under the
  test folder, not in the app bundle.

## Pitfalls

- **Only testing one width.** Most breaks appear only at 320 px or only at a wide width where a
  max-width is missing. Shoot both, always.
- **Fixing with `overflow: hidden` everywhere.** It hides the symptom and the content with it.
  Decide per field: wrap, truncate with the full value reachable, or clamp.
- **`word-break: break-all`.** It breaks ordinary words mid-word too. `overflow-wrap: anywhere`
  only breaks where it must.
- **Testing the formatter, not the screen.** A unit test of `formatCount(1e6)` does not show
  the badge it lands in. Look at the screenshot.
- **Forgetting the states.** Empty, loading and error are part of the worst case; they are
  usually the least finished screens of an app.

Background: distilled from Emil Kowalski's break-ui skill; rewritten, nothing copied.
