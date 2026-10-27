---
name: mobile-web
description: "Use when a web app is built for or reviewed on a phone or tablet: something works on the desktop but feels wrong on a phone (hover stuck after a tap, grey flash on tap, page zooms into an input, layout jumps when the address bar moves, content under the notch or home bar, pull-to-refresh fires inside a sheet, long-press selects button text, carousel drags the page sideways); when adding a viewport meta, theme-color, a PWA manifest, a bottom sheet, a carousel, a full-screen layout or a form for touch; when the user wants to test on a real iPhone or Android device. CSS, meta and small JS fixes plus safe device testing."
---

# Mobile web: make a web app feel native on a phone

A page can be responsive and still feel like a website squeezed onto a phone: a button that
stays highlighted after a tap, a grey flash on every tap, a form that zooms in, a bottom bar
under the home indicator. Each has a small, known fix. This skill lists them, then says how to
check them on a real device without exposing the dev server. Examples are plain
HTML/CSS/JS; the same rules apply in React.

Related: the web-accessibility skill (zoom, target size, gesture alternatives), the ui-motion
skill (sheet and press animations), the ui-craft skill (visual design), the headless-ui-smoke
skill (phone-size screenshots), the launch-and-deploy skill (any LAN exposure).

## 1. The viewport meta

```html
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
```

- `viewport-fit=cover` lets the page draw under the notch and home bar; pad with
  `env(safe-area-inset-*)` (section 6).
- **Never** add `maximum-scale=1` or `user-scalable=no`. Blocking zoom fails accessibility, and
  input zoom has a better fix (section 4).

## 2. Hover only where hover exists

On a touch screen a `:hover` style sticks after a tap until the next tap elsewhere. Gate it
behind a query that only matches a real pointer:

```css
@media (hover: hover) and (pointer: fine) {
  .row:hover { background: var(--row-hover); }
}
```

Never hide an action behind hover alone (a delete icon that appears on row hover): on a phone
it does not exist. Show it, or put it in a menu.

## 3. Tap feedback and tap delay

The default tap flash looks like a browser, not an app. Remove it and give a real pressed state
so taps still feel acknowledged; keep the `:focus-visible` styles for keyboards:

```css
button, a, [role="button"] { -webkit-tap-highlight-color: transparent; }
button:active { transform: scale(0.97); background: var(--btn-pressed); }
```

`touch-action: manipulation` turns off double-tap-to-zoom on controls, so the browser never
waits for a second tap, and quick double taps on steppers or keypads do not zoom:

```css
button, a, input, label, select, textarea { touch-action: manipulation; }
```

## 4. Inputs that zoom the page, and the right keyboard

iOS Safari zooms into a focused field whose font size is below 16 px, and stays zoomed. Fix the
font size, never the zoom:

```css
input, select, textarea { font-size: max(16px, 1rem); }
```

Tell the keyboard what to show and what Return does:

```html
<input type="email" autocomplete="email" enterkeyhint="next">
<input type="text" inputmode="numeric" autocomplete="one-time-code" enterkeyhint="done">
<input type="search" enterkeyhint="search">
<textarea enterkeyhint="send"></textarea>
```

- `inputmode` (`numeric`, `decimal`, `tel`, `email`, `url`, `search`) picks the keyboard; `type`
  decides validation. Use `inputmode` when the two differ (a PIN is text, not a number).
- `autocomplete` fills names, addresses, SMS one-time codes and saved passwords.
- `autocapitalize="off"` and `spellcheck="false"` on usernames, codes and URLs.

## 5. Viewport height: the 100vh bug

On phones `100vh` is the height with the browser bars **hidden**, so a `100vh` screen is taller
than what is visible while they show, and the bottom button sits under them. Use the newer
units:

| Unit | Means | Use for |
|---|---|---|
| `dvh` | visible height right now, follows the bars | app shells, chat layouts |
| `svh` | smallest (bars shown) | sections that must fit without re-layout on scroll |
| `lvh` | largest (bars hidden) | backgrounds that must never show a gap |

```css
.app { min-height: 100vh; min-height: 100dvh; } /* fallback first */
```

## 6. Notch, home bar and safe areas

With `viewport-fit=cover`, pad fixed bars by the insets so they clear the notch, the rounded
corners and the home indicator:

```css
.top-bar    { padding-top: max(12px, env(safe-area-inset-top)); }
.bottom-bar { padding-bottom: max(12px, env(safe-area-inset-bottom)); }
.page       { padding-inline: max(16px, env(safe-area-inset-left), env(safe-area-inset-right)); }
```

Check landscape: the notch moves to one side and the left or right inset becomes non-zero.

## 7. Scroll chaining, pull-to-refresh, carousels

When a sheet, modal or chat pane hits the end of its scroll, the next swipe scrolls the page
behind it or fires pull-to-refresh. Contain it, and lock the page (`overflow: hidden` on
`html`) while a modal is open:

```css
.sheet-body, .modal-body, .chat-log { overscroll-behavior: contain; }
body.app-shell { overscroll-behavior-y: none; } /* only if the app offers its own refresh */
```

Horizontal carousels snap, and keep sideways swipes away from the page:

```css
.carousel {
  display: flex; gap: 12px; overflow-x: auto;
  scroll-snap-type: x mandatory; overscroll-behavior-x: contain; scrollbar-width: none;
}
.carousel > * { flex: 0 0 85%; scroll-snap-align: start; }
```

Add previous and next buttons too: a swipe is a gesture, and gestures need a tap alternative.

## 8. Text selection and touch targets

A long press on a button selects its label and opens the callout. Turn selection off on
**controls only**, never on `body`, messages, code or anything a person may copy:

```css
button, [role="button"], .tab, .chip { -webkit-user-select: none; user-select: none; }
```

Touch targets are **44 x 44 px** (WCAG's floor is 24; fingers need 44), with at least 8 px
between neighbours and destructive actions away from the thumb's resting spot. A small icon
keeps its look and grows its hit area:

```css
.icon-btn { min-width: 44px; min-height: 44px; display: inline-grid; place-items: center; }
```

## 9. Bottom sheets

Build the sheet on `<dialog>` (focus, Escape and the inert page come free), then add touch:

- **Drag and snap**: follow the finger with `transform: translateY()` on `pointermove`
  (`touch-action: none` on the handle only); on release snap to the nearest point, using the
  velocity so a quick flick closes it. Keep a close button: dragging needs a single-tap
  alternative (WCAG 2.5.7).
- **Scroll inside**: `overscroll-behavior: contain` on the body; start a drag-to-close only
  when the content is scrolled to the top.
- **Keyboard avoiding**: the on-screen keyboard covers the bottom of the sheet. Lift it by the
  part of the layout viewport the visual viewport no longer shows:

```js
const sheet = document.querySelector('.sheet');
function avoidKeyboard() {
  const vv = window.visualViewport;
  const covered = window.innerHeight - vv.height - vv.offsetTop;
  sheet.style.setProperty('--keyboard', `${Math.max(0, covered)}px`);
}
window.visualViewport?.addEventListener('resize', avoidKeyboard);
window.visualViewport?.addEventListener('scroll', avoidKeyboard);
```
```css
.sheet { bottom: var(--keyboard, 0px); padding-bottom: env(safe-area-inset-bottom); }
```

## 10. Status bar colour and install

`theme-color` tints the browser bar and status bar. Give one per scheme, matching the page's
top bar rather than an accent colour:

```html
<meta name="theme-color" content="#ffffff" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#111317" media="(prefers-color-scheme: dark)">
<meta name="color-scheme" content="light dark">
<link rel="manifest" href="/manifest.webmanifest">
<link rel="apple-touch-icon" href="/icons/icon-180.png">
```

The manifest, only if the app should be installable:

```json
{
  "name": "My App", "short_name": "MyApp", "start_url": "/", "scope": "/",
  "display": "standalone", "background_color": "#111317", "theme_color": "#111317",
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png" },
    { "src": "/icons/maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ]
}
```

Installing needs HTTPS. In standalone mode there is no back button or address bar: the app
needs its own navigation, and the safe-area insets matter even more.

## 11. Test on real hardware

Device emulation in desktop Chrome, or a phone-size run of the headless-ui-smoke skill
(`--size 390x844`), catches layout breaks. It does not reproduce iOS input zoom, bars resizing
the viewport, the on-screen keyboard, safe areas, sticky hover, scroll momentum or tap feel.
**Do a pass on a real phone before calling mobile work done**, and say so in the report when you
could not.

### Device testing safety rules

1. **The dev server stays on `127.0.0.1`.** Do not change its bind address to reach a phone.
2. **Use USB remote debugging with port forwarding**, so nothing listens on the LAN:
   - **Android**: turn on USB debugging on the phone and plug it in; in desktop Chrome open
     `chrome://inspect` → **Port forwarding**, map device port `8000` (the app's port) to
     `127.0.0.1:8000`. The phone opens `http://localhost:8000` through the cable, and the
     page's **inspect** link gives DevTools for the phone's tab.
   - **iOS**: turn on Web Inspector (Settings › Safari › Advanced), plug the iPhone into a Mac,
     then Safari › Develop › the device › the page. iOS has no built-in port forwarding: test a
     deployed HTTPS preview, or ask the user how they want the phone to reach the server.
3. **Never bind `0.0.0.0` or open a firewall port on your own.** If the user wants Wi-Fi access
   from the phone, ask first, then follow the launch-and-deploy skill: an IP allowlist for that
   one device, a firewall rule scoped to it, both removed afterwards.
4. **Localhost is not a trust boundary.** A page or process is not trusted because it is local
   or forwarded; never hand it secrets, tokens or cookies on that basis.
5. Headless emulation is a first pass, not a substitute for the device.

### What to try on the device

- Tap every control: no flash, a visible pressed state, no hover left behind.
- Focus each input: no zoom, the right keyboard, the right Return key.
- Scroll to the bottom with the bars shown and hidden: nothing hidden under them.
- Rotate to landscape: content clears the notch.
- Over-scroll an open sheet or modal: the page behind stays still, no pull-to-refresh.
- Swipe the carousel: it snaps and the page does not move sideways.
- Long-press a button: no text selection.
- Turn on Reduce Motion and larger text in the OS: the layout still works.

## Review output

One finding per problem: the symptom, file:line, the fix, and whether it was seen on hardware.

Background: distilled from Emil Kowalski's mobile-native skill and platform docs (WebKit, web.dev); rewritten, nothing copied.
