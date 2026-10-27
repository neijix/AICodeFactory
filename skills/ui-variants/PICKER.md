# Variant picker

A small floating switcher for comparing design variants during development. Vanilla JS, no
dependency, no host CSS needed. It is temporary: it is deleted together with the losing
variants.

## What it does

- The current variant comes from `?variant=` in the URL, else from `sessionStorage` (per tab and
  per path), else the first variant.
- It sets `data-variant` on `<html>` before the page renders, and fires a `variantchange` event
  on `document` when the user switches, so the app re-renders without a reload.
- It writes the choice back to the URL (`history.replaceState`, no new history entry), so a
  link or a headless screenshot can ask for a variant directly.
- Keys `1` to `4` pick a variant, `[` and `]` step through them. Keys are ignored while the
  focus is in an input, a textarea, a select or an editable element, while an IME is composing,
  and when Ctrl, Cmd or Alt is held.
- A fixed bottom-right toolbar of buttons (with `aria-pressed`) does the same with the mouse.
- It does nothing unless the page set the dev flag `window.APP_DEV = true`.

## Serve it only in development

The server, not the script, is the first gate. In a small Python app:

```python
IS_DEV = os.environ.get("APP_DEV") == "1"   # off unless set
DEV_HEAD = (
    '<script>window.APP_DEV = true;</script>'
    '<script src="/dev/variant-picker.js"></script>'
    if IS_DEV else ""
)
```

Put `DEV_HEAD` in `<head>`, before the app's own scripts, without `defer`, so `data-variant` is
set before the first render. Serve the `/dev/` folder only when `IS_DEV` is true.

## The script

```js
// dev/variant-picker.js: development only. Delete it with the losing variants.
(() => {
  if (window.APP_DEV !== true) return;

  const VARIANTS = ['a', 'b', 'c'];                        // the variants being compared
  const LABELS = { a: 'A rows', b: 'B cards', c: 'C split' };
  const PARAM = 'variant';
  const STORE_KEY = 'variant-picker:' + location.pathname;

  function initial() {
    const fromUrl = new URLSearchParams(location.search).get(PARAM);
    if (VARIANTS.includes(fromUrl)) return fromUrl;
    const saved = sessionStorage.getItem(STORE_KEY);
    return VARIANTS.includes(saved) ? saved : VARIANTS[0];
  }

  let current = initial();
  document.documentElement.dataset.variant = current;     // before the app renders
  // An app that rendered before this script loaded (a dynamic import) re-reads the variant.
  document.dispatchEvent(new CustomEvent('variantchange', { detail: { variant: current } }));

  function select(id) {
    if (!VARIANTS.includes(id) || id === current) return;
    current = id;
    document.documentElement.dataset.variant = id;
    sessionStorage.setItem(STORE_KEY, id);
    const url = new URL(location.href);
    url.searchParams.set(PARAM, id);
    history.replaceState(history.state, '', url);
    document.dispatchEvent(new CustomEvent('variantchange', { detail: { variant: id } }));
    syncButtons();
  }

  function isTyping(target) {
    if (!(target instanceof Element)) return false;
    return target.isContentEditable || target.closest('input, textarea, select') !== null;
  }

  document.addEventListener('keydown', (event) => {
    if (event.defaultPrevented || event.isComposing) return;
    if (event.ctrlKey || event.metaKey || event.altKey) return;
    if (isTyping(event.target)) return;
    const step = { '[': -1, ']': 1 }[event.key];
    if (step) {
      const i = VARIANTS.indexOf(current);
      select(VARIANTS[(i + step + VARIANTS.length) % VARIANTS.length]);
    } else if (/^[1-4]$/.test(event.key)) {
      select(VARIANTS[Number(event.key) - 1]);
    }
  });

  const bar = document.createElement('div');
  bar.setAttribute('role', 'toolbar');
  bar.setAttribute('aria-label', 'Design variant (dev only)');
  bar.style.cssText =
    'position:fixed;right:12px;bottom:12px;z-index:2147483647;display:flex;gap:4px;' +
    'padding:4px;border-radius:8px;background:#111;box-shadow:0 2px 8px rgba(0,0,0,.35);' +
    'font:12px/1.2 system-ui,sans-serif';

  const buttons = VARIANTS.map((id, i) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = LABELS[id] || id.toUpperCase();
    button.title = `Variant ${id.toUpperCase()} (key ${i + 1})`;
    button.style.cssText =
      'border:0;border-radius:6px;padding:6px 10px;cursor:pointer;font:inherit;';
    button.addEventListener('click', () => select(id));
    bar.append(button);
    return button;
  });

  function syncButtons() {
    buttons.forEach((button, i) => {
      const isOn = VARIANTS[i] === current;
      button.setAttribute('aria-pressed', String(isOn));
      button.style.background = isOn ? '#fff' : 'transparent';
      button.style.color = isOn ? '#111' : '#ddd';
    });
  }

  syncButtons();
  if (document.body) document.body.append(bar);
  else document.addEventListener('DOMContentLoaded', () => document.body.append(bar));
})();
```

The app side is a map from variant to render function plus one listener (see SKILL.md, step
3). Without the picker, `data-variant` is absent and the map falls back to the first variant,
so the page still works if the dev flag is off.

To screenshot a variant headlessly, open the page with `?variant=b`; the picker reads it
before the first render.

## React

Read the variant with a small hook and mount the toolbar only in development:

```jsx
const getVariant = () => document.documentElement.dataset.variant ?? 'a';
const subscribe = (cb) => { document.addEventListener('variantchange', cb);
  return () => document.removeEventListener('variantchange', cb); };
export const useVariant = () => useSyncExternalStore(subscribe, getVariant);
// In the component: const variant = useVariant(); return variant === 'b' ? <Cards /> : <Rows />;
```

Load the vanilla script only when `import.meta.env.DEV` (or
`process.env.NODE_ENV !== 'production'`) is true, with a dynamic import in the entry file, so the
production bundle never contains it. Set the dev flag first: the script does nothing without it.

```js
if (import.meta.env.DEV) {
  window.APP_DEV = true;
  import('./dev/variant-picker.js');
}
```

## Removal checklist

Run through this once the user has picked:

- [ ] Delete `dev/variant-picker.js` (or the React import and hook).
- [ ] Remove the `DEV_HEAD` tags, or just the picker's tag if the dev flag serves other tools.
- [ ] Delete the losing render functions or components, their CSS, and helpers only they used.
- [ ] Replace the variant map and `useVariant()` with a direct call to the winner.
- [ ] Remove every `variantchange` listener.
- [ ] Drop the `[data-variant="x"]` prefixes from the winner's CSS and rename its letter-suffixed
      functions and classes to plain names.
- [ ] Search the project for `variant-picker`, `data-variant`, `variantchange` and `?variant=`
      (docs and tests included): no hits left.
- [ ] Load the page with and without the dev flag: same single design, no toolbar, no console
      errors.
- [ ] Run the tests and take one final screenshot, then make the one commit.
