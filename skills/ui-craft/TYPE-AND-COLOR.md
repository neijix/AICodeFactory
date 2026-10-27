# UI craft — type, colour and surface reference

Starter values for a project that has none. When the project already has tokens, keep its
values and borrow only the structure (role names, scale steps). The system font stack is the
default for app screens: no download, no reflow, native rendering.

## Font stacks

```css
:root {
  --font-ui: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial,
             sans-serif, "Apple Color Emoji", "Segoe UI Emoji";
  --font-mono: ui-monospace, "SF Mono", "Cascadia Code", Menlo, Consolas, monospace;
}
body { font-family: var(--font-ui); }
code, kbd, samp, .id { font-family: var(--font-mono); font-size: 0.875em; }
```

## One self-hosted face

When the app has a brand face: one family, ideally a variable `woff2`, served from the app's
own static folder (check the licence; OFL fonts may be bundled). No third-party font CDN.

```css
@font-face {
  font-family: "Brand";
  src: url("/static/fonts/brand-var.woff2") format("woff2");
  font-weight: 100 900;
  font-display: swap;
}
/* A local fallback tuned to Brand's metrics, so the swap does not reflow the page.
   The percentages are placeholders: compute them from the two fonts' metrics. */
@font-face {
  font-family: "Brand Fallback"; src: local("Arial");
  size-adjust: 105%; ascent-override: 92%; descent-override: 24%; line-gap-override: 0%;
}
:root { --font-ui: "Brand", "Brand Fallback", system-ui, sans-serif; }
```

Preload only the one file used above the fold, with `crossorigin` even on the same origin
(fonts are always fetched in CORS mode; without it the file downloads twice):
`<link rel="preload" href="/static/fonts/brand-var.woff2" as="font" type="font/woff2" crossorigin>`.

## Role scale

| Role | Size | Line height | Weight | Use |
|---|---|---|---|---|
| caption | 0.75rem (12px) | 1rem (1.33) | 400–500 | timestamps, table footers, badges |
| small | 0.875rem (14px) | 1.25rem (1.43) | 400 | secondary text, dense tables, helper text |
| body | 1rem (16px) | 1.5rem (1.5) | 400 | default text, inputs, buttons |
| heading | 1.125rem (18px) | 1.5rem (1.33) | 600 | section and card titles, dialog titles |
| title | 1.5rem (24px) | 1.875rem (1.25) | 600 | the page's one `h1` |
| display | 2rem (32px) | 2.25rem (1.13) | 600 | a key number on a dashboard, sparingly |

```css
:root {
  --text-caption: 0.75rem;  --text-small: 0.875rem; --text-body: 1rem;
  --text-heading: 1.125rem; --text-title: 1.5rem;   --text-display: 2rem;
}
html { -webkit-text-size-adjust: 100%; text-size-adjust: 100%; }
body { font-size: var(--text-body); line-height: 1.5; }
h1, h2, h3 { text-wrap: balance; }
p, li, dd { text-wrap: pretty; max-width: 65ch; }
```

Buttons and inputs use the body size: 16px inputs also keep phones from zooming on focus.

## Leading and tracking by size

| Size | Line height | Letter spacing |
|---|---|---|
| 12px | 1.33–1.4 | +0.01em |
| 14px | 1.43 | 0 |
| 16px | 1.5 | 0 |
| 18–20px | 1.33–1.4 | −0.005em |
| 24px | 1.25 | −0.01em |
| 32px and up | 1.1–1.15 | −0.02em |
| Uppercase label (12px, 600) | 1.33 | +0.06em, and use it rarely |

Light text on dark looks bolder: if body text feels heavy in dark mode, drop a weight step.

## Numbers

```css
.num, .timer, .count, .price { font-variant-numeric: tabular-nums lining-nums; text-align: end; }
.id-code { font-variant-numeric: tabular-nums slashed-zero; }
```

```js
const locale = navigator.language;
new Intl.NumberFormat(locale).format(12345.6);                          // 12,345.6
new Intl.NumberFormat(locale, { notation: "compact" }).format(1520000); // 1.5M
new Intl.NumberFormat(locale, { style: "unit", unit: "megabyte" }).format(12); // 12 MB
new Intl.RelativeTimeFormat(locale, { numeric: "auto" }).format(-1, "day");  // yesterday
new Intl.DateTimeFormat(locale, { dateStyle: "medium", timeStyle: "short" }).format(new Date());
const plural = new Intl.PluralRules(locale);
const files = (n) => `${n} ${plural.select(n) === "one" ? "file" : "files"}`;
```

Keep the same number of decimals within a column; show a real minus sign for negatives in
financial columns; put the unit in the column header when every row shares it.

## Typographic characters

| Character | Name | Use for | Instead of | HTML |
|---|---|---|---|---|
| … | ellipsis | in progress ("Saving…"), opens a further step ("Rename…"), truncation | `...` | `&hellip;` |
| – | en dash | ranges: 9–17h, pages 4–8 | `-` | `&ndash;` |
| — | em dash | a break in a sentence | `--` | `&mdash;` |
| × | multiplication | dimensions 1920×1080, "3× faster" | `x` | `&times;` |
| − | minus | negative numbers in tables | `-` | `&minus;` |
| ’ | apostrophe | can’t, user’s | `'` | `&rsquo;` |
| “ ” | quotes (EN) | quoted text | `"…"` | `&ldquo;` `&rdquo;` |
| « » | guillemets (FR) | quoted text in French, with a narrow no-break space inside | `"…"` | `&laquo;` `&raquo;` |
| (no-break space) | non-breaking space | between number and unit (12&nbsp;MB), after "No." | a normal space | `&nbsp;` |
| (narrow no-break space) | narrow no-break space | French: before `; : ! ?` and inside « » | a normal space | `&#8239;` |
| → | arrow | "Settings → Models" breadcrumbs in text | `->` | `&rarr;` |
| ⌘ ⇧ ⌥ ⌃ | modifier symbols | macOS shortcut hints; spell out Ctrl / Shift / Alt elsewhere | `Cmd+` | `&#8984;` `&#8679;` `&#8997;` `&#8963;` |

Write invisible characters as entities or escapes in source, never as raw characters: they
are impossible to review in a diff.

## Colour tokens (OKLCH)

Neutrals carry a trace of the accent's hue (here 255, a blue) at very low chroma. For a
neutral, OKLCH lightness cubed is the relative luminance, so contrast can be estimated by
hand: `(L1³ + 0.05) / (L2³ + 0.05)`. Verify chromatic pairs with a contrast tool.

```css
:root {
  color-scheme: light dark;
  --bg:            oklch(98.5% 0.003 255);
  --surface:       oklch(100% 0 0);
  --surface-2:     oklch(96.5% 0.004 255);   /* sunken wells, hover rows, table headers */
  --border:        oklch(90% 0.006 255);     /* dividers, card edges (decorative) */
  --border-strong: oklch(62% 0.01 255);      /* input borders: 3:1 against the surface */
  --text:          oklch(22% 0.01 255);
  --text-muted:    oklch(45% 0.012 255);
  --text-subtle:   oklch(54% 0.01 255);      /* the floor for small text */
  --accent:        oklch(53% 0.17 255);
  --on-accent:     oklch(100% 0 0);
  --accent-soft:   oklch(95% 0.03 255);      /* selected row, tinted button */
  --danger:        oklch(53% 0.19 27);
  --success:       oklch(50% 0.12 150);
  --warning:       oklch(50% 0.11 75);       /* as text; a fill can be lighter */
  --focus:         oklch(56% 0.18 255);
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg:            oklch(17% 0.006 255);
    --surface:       oklch(21% 0.007 255);   /* raised = lighter */
    --surface-2:     oklch(25% 0.008 255);   /* raised further: menus, dialogs */
    --border:        oklch(30% 0.008 255);
    --border-strong: oklch(54% 0.01 255);
    --text:          oklch(93% 0.005 255);   /* off-white, not #fff */
    --text-muted:    oklch(75% 0.01 255);
    --text-subtle:   oklch(66% 0.01 255);
    --accent:        oklch(72% 0.14 255);    /* lighter, less saturated */
    --on-accent:     oklch(17% 0.02 255);
    --accent-soft:   oklch(30% 0.05 255);
    --danger:        oklch(72% 0.16 27);
    --success:       oklch(74% 0.14 150);
    --warning:       oklch(80% 0.13 75);
    --focus:         oklch(75% 0.14 255);
  }
}
```

With a manual theme switch, repeat the dark values under `:root[data-theme="dark"]` with
`color-scheme: dark`, and pin `:root[data-theme="light"]` to `color-scheme: light` and the
light values, so the chosen theme beats the system's in both directions.

```html
<meta name="color-scheme" content="light dark">
<meta name="theme-color" content="#f9fafc" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0f1114" media="(prefers-color-scheme: dark)">
```

## Contrast minimums (WCAG 2.2 AA)

| What | Minimum | Starter tokens (approx., on `--bg` / `--surface`) |
|---|---|---|
| Body and small text | 4.5:1 | light: text 17:1, muted 7:1, subtle 4.8:1; dark: text 15:1, muted 8:1, subtle 5.5:1 |
| Large text (≥ 24px, or ≥ 18.66px bold) | 3:1 | any text token |
| Input borders, meaningful icons, chart marks | 3:1 | `--border-strong`; not `--border` |
| Focus ring | 3:1 against what surrounds it | `--focus` |
| Text on the accent | 4.5:1 | `--on-accent` on `--accent`, both schemes |
| Disabled controls | exempt | still keep them legible (~3:1) |
| Placeholder text | 4.5:1 if it carries information | better: carry none |

A floor for building; the audit belongs to the web-accessibility skill.

## Dark-mode notes

- Elevation is lightness: each level up is a few points of L lighter. Shadows barely show;
  keep a 1px border or a faint top highlight on raised surfaces.
- Lower the chroma of large tinted areas and chart series; saturated colours vibrate on dark.
- Re-check every state: hover tints, selected rows, disabled text, skeletons and focus rings
  are the usual casualties. Images with white backgrounds need a frame or a dark variant.

## Shadows and radii

```css
:root {
  --shadow-1: 0 1px 1px oklch(20% 0.02 255 / 0.05), 0 1px 3px oklch(20% 0.02 255 / 0.06);
  --shadow-2: 0 1px 2px oklch(20% 0.02 255 / 0.06), 0 4px 10px oklch(20% 0.02 255 / 0.07);
  --shadow-3: 0 2px 4px oklch(20% 0.02 255 / 0.06), 0 10px 24px oklch(20% 0.02 255 / 0.10),
              0 24px 48px oklch(20% 0.02 255 / 0.08);

  --r-sm: 4px;    /* chips, checkboxes, inner elements */
  --r-md: 8px;    /* buttons, inputs, menus */
  --r-lg: 12px;   /* cards, dialogs, panels */
  --r-full: 999px; /* pills, avatars, toggles */
}
@media (prefers-color-scheme: dark) {
  :root {
    --shadow-1: 0 0 0 1px oklch(100% 0 0 / 0.06);
    --shadow-2: 0 0 0 1px oklch(100% 0 0 / 0.07), 0 4px 12px oklch(0% 0 0 / 0.4);
    --shadow-3: 0 0 0 1px oklch(100% 0 0 / 0.08), 0 16px 40px oklch(0% 0 0 / 0.5);
  }
}
```

Use `--shadow-1` for cards that need it at all, `--shadow-2` for menus and popovers,
`--shadow-3` for dialogs. Inner radius = outer radius − padding.

## Focus and hit targets

```css
:focus-visible { outline: 2px solid var(--focus); outline-offset: 2px; }
input:focus-visible, textarea:focus-visible, select:focus-visible {
  outline-offset: 0; border-color: var(--focus);
}
```

Use `outline`, not `box-shadow`, for the ring: outlines survive Windows high-contrast
(forced colours) mode, box-shadows are removed.

```css
.icon-btn {
  position: relative; display: inline-grid; place-items: center;
  min-width: 24px; min-height: 24px; padding: 4px; border-radius: var(--r-sm);
}
.icon-btn svg { width: 16px; height: 16px; }
/* Grow the target, not the icon. Keep neighbours far enough apart that areas do not overlap. */
.icon-btn::after { content: ""; position: absolute; inset: -6px; }
@media (pointer: coarse) { .icon-btn, .btn { min-width: 44px; min-height: 44px; } }
@media (hover: hover) and (pointer: fine) { .icon-btn:hover { background: var(--surface-2); } }
```
