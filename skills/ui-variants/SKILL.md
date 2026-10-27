---
name: ui-variants
description: "Use when the user runs /ui-variants or asks to see several designs of one component or screen side by side before choosing: \"show me 2 or 3 versions\", \"try a few layouts\", \"A/B this header\", \"cards or a table?\", \"I can't decide how this should look\", \"give me options for the settings page\". Agrees on the question and 2 to 4 meaningfully different variants, builds them in the real app with real data behind a dev-only switcher (?variant=a|b|c, keys 1-4 and [ ]), screenshots each with headless Chrome, presents a short comparison, then deletes the losers and the switcher and leaves one clean implementation. No worktrees, no branch per variant, no new dependency without asking."
disable-model-invocation: true
compatibility: Screenshots use the headless-ui-smoke skill (Chrome, Edge, Chromium or Brave, plus uv). Plain HTML/CSS/JS first; a React note is in PICKER.md.
---

# UI variants

Arguing about a design in prose is slow; clicking between three working versions on real data
settles it in a minute. This skill builds a few alternatives of one component or screen inside
the real app, lets the user flip between them, and then cleans up so only the chosen one is
left.

## Rules

- **In the working tree, nowhere else.** No git worktree, no branch per variant, no copied
  project folder. All variants live side by side in the same files for the length of the task.
- **One commit at the end**, after the losers and the switcher are gone. If the project's own
  rules require a checkpoint commit in between, make it a `wip:` commit whose message says the
  switcher is still in and which variants exist.
- **No new dependency** (UI kit, animation library, icon set) without asking first. A variant
  that needs one is a question for the user, not a quiet `npm install`.
- **Same real data for every variant**, loaded the same way. If the real data is private or
  thin, use the app's dev fixtures; the comparison is only fair if every variant shows the same
  records.
- **Dev-only switcher.** It appears only when the app's development flag is on and is never on
  by default in a production page.

## 1. Agree on the question

Write the decision as one sentence and get a yes before building:

> "Should the agent list be dense rows with inline actions, or cards with a details panel?"

Also pin what stays fixed (the data, the actions available, the surrounding page) so the
variants differ only where the question is.

## 2. Choose 2 to 4 variants that really differ

Each variant gets a letter, a short name and a one-line thesis. They must differ in something
that changes how the screen is used:

- **structure**: table vs cards vs list with a detail pane;
- **density**: everything visible vs progressive disclosure;
- **hierarchy**: what the eye lands on first, what is secondary;
- **interaction**: inline editing vs a dialog, tabs vs one long scroll, hover actions vs a menu.

Colour, radius, shadow or font-size tweaks are not variants; they are polish on whichever one
wins (the ui-craft skill covers that). Two variants is fine when the question is binary; more
than four becomes hard to judge. Propose the list, and let the user add, drop or rename before
any code is written.

## 3. Build them in the real app

Share everything except the part being decided:

- one data load, one state object, one set of event handlers;
- one render function per variant, chosen from a map:

```js
const LIST_VARIANTS = { a: renderRows, b: renderCards, c: renderSplit };

function renderAgentList(state) {
  const id = document.documentElement.dataset.variant;
  (LIST_VARIANTS[id] || LIST_VARIANTS.a)(listEl, state);
}
document.addEventListener('variantchange', () => renderAgentList(state));
```

- CSS for each variant scoped under its attribute, so nothing bleeds between them:

```css
[data-variant="b"] .agent-list { display: grid; grid-template-columns: repeat(auto-fill, minmax(16rem, 1fr)); gap: 1rem; }
[data-variant="c"] .agent-list { display: grid; grid-template-columns: minmax(14rem, 1fr) 2fr; }
```

Plain scripts without modules share one global scope: name every variant's helpers with its
letter (`renderCardsB`, not a second `renderItem`), or a later file silently replaces an
earlier one.

Give every variant the same care: the empty state, the loading state and a long value (the
ui-stress-test skill's worst cases are a quick check). A polished variant next to a rough one
is not a fair comparison. Keep each variant keyboard-usable; the web-accessibility skill has
the checks.

## 4. Add the switcher

Use the vanilla picker in `PICKER.md` (next to this file): it reads and writes `?variant=`,
remembers the choice in `sessionStorage`, switches with keys 1 to 4 and `[` / `]` (ignored
while typing in a field), sits in a fixed corner, and only exists when the dev flag is on.
For React, the same file has a short hook.

## 5. Screenshot each variant

With the headless-ui-smoke skill, at the same viewport sizes for every variant (a phone width
and a desktop width at least), against a throwaway instance with the dev flag on:

```bash
SMOKE=~/.agents/skills/headless-ui-smoke/scripts/cdp_smoke.py
for v in a b c; do
  for size in 390x844 1440x900; do
    uv run "$SMOKE" "http://127.0.0.1:8765/agents?variant=$v" \
      --wait-for "document.querySelectorAll('.agent-list > *').length > 0" \
      --size "$size" --shot "/tmp/variant-$v-$size.png"
  done
done
```

Open every PNG and look at it before presenting; fix anything broken in a variant first.
Screenshots stay in a temp folder, not the repository.

## 6. Present a short comparison

| | Thesis | Good at | Costs | Shots |
|---|---|---|---|---|
| **A** Rows | everything at a glance | scanning 50 agents, keyboard use | crowded at 390 px | `/tmp/variant-a-*.png` |
| **B** Cards | each agent stands alone | status is obvious, touch-friendly | 6 per screen, more scrolling | `/tmp/variant-b-*.png` |
| **C** Split | list plus detail | editing without a dialog | needs a wide screen | `/tmp/variant-c-*.png` |

Add one recommendation with its reason, then tell the user how to try them live
(`?variant=b`, or keys 1 to 3 on the page) and ask which to keep. A hybrid ("A's rows with C's
detail pane") is a valid answer: build it as the final version, not as a fifth variant, unless
the user wants to compare it too.

## 7. Clean up the winner

Follow the removal checklist in `PICKER.md`. In short:

- delete the losing render functions, their CSS, and any helper only they used;
- delete the switcher script, its tag or mount, and the `variantchange` listener;
- replace the variant map with a direct call to the winner;
- rename the winner's names and selectors to plain ones (no `B` suffixes, no
  `[data-variant="b"]` prefix);
- search the project for `variant`, `data-variant` and the picker's storage key: nothing left;
- run the tests, take one last screenshot, then make the single commit.

The diff should read as if the chosen design had been written directly.

## Pitfalls

- **Variants that are the same design in three colours.** Go back to step 2.
- **State lost on switch.** Keep state outside the render functions so flipping variants keeps
  the selection, the scroll position and any typed text.
- **Comparing at different sizes or with different data.** Same viewport, same records.
- **Leaving the switcher in "for later".** It is deleted with the losers; a later comparison
  starts again from this skill.

Background: distilled from Emil Kowalski's prototype skill; rewritten, nothing copied.
