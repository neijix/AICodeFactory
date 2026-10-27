# Type and palette

Type and colour carry most of a page's character. Decide both from the brief in `SKILL.md`
(argument, scene, bold move), write them down as custom properties, and use nothing outside
them.

## Type scale

### Few sizes, far apart

Strong pages tend to use a small number of sizes with large gaps between them. Start with
three roles and add a fourth only when content needs it:

| Role | Use | Typical range |
|---|---|---|
| Display | the headline, maybe one section opener | 3.5 to 8 times the text size |
| Heading | section titles | 1.5 to 2.25 times the text size |
| Text | body copy, buttons, most UI | 1rem to 1.25rem |
| Small (optional) | captions, legal, metadata | 0.8 to 0.875 times the text size |

The gap between display and heading is where the hierarchy lives. A page whose largest size is
only twice the body size has no clear top; a page with eight sizes has no clear steps.

### Building it

1. Fix the text size first, from the reading distance in the scene: phone in hand outdoors
   wants a larger text size than a desktop reader at arm's length. 1.0625rem to 1.25rem
   covers most landing pages.
2. Pick the display size from the bold move. If the headline is the bold move, push it
   (`clamp(3.5rem, 10vw, 9rem)`); if a photograph is, keep the headline moderate so it does
   not compete.
3. Place the heading size between them, closer to the text size than to the display size.
4. Make display and heading fluid with `clamp(min, preferred-vw, max)`; keep the text size
   nearly fixed (a small `clamp` at most).

```css
:root {
  --size-small: 0.875rem;
  --size-text: clamp(1.0625rem, 0.4vw + 1rem, 1.25rem);
  --size-heading: clamp(1.75rem, 2.5vw + 1rem, 2.75rem);
  --size-display: clamp(3.25rem, 9vw, 8rem);
}
```

### Weight, case, tracking

- Use two weights per face, three at most. Contrast between regular and bold reads better
  than a ladder of medium, semibold, bold.
- Large display sizes usually want slightly tighter tracking (`letter-spacing: -0.01em` to
  `-0.03em`); small uppercase labels want slightly looser (`0.04em` to `0.08em`). Check by
  eye: tracking depends on the face.
- Uppercase is for short labels, not sentences or headlines longer than a few words.

## Choosing and pairing faces

- **Justify every face.** Name why it suits this product: the period it evokes, its letter
  shapes, its weight range, how it holds up at the display size, the scene. "It is popular
  right now" is not a reason; generated pages already overuse the fashionable few.
- **One face is often enough.** A family with a wide weight range, or with optical sizes, can
  carry both display and text. Pair only when the second face adds something the first lacks.
- **Pairing rule of thumb:** contrast in one dimension, agreement in others. A serif display
  with a sans text works when their proportions (x-height, width) are similar; two sans faces
  that differ only slightly look like a mistake.
- **System stacks are a valid choice.** A well-set system stack loads instantly and is free of
  licensing questions:

  ```css
  --font-sans: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  --font-serif: "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, serif;
  --font-mono: ui-monospace, "SF Mono", "Cascadia Mono", Consolas, monospace;
  ```

- **Licensing and loading.** Self-host only files the user has a licence for (WOFF2, a
  subset if the licence allows). Ask before using any font CDN. Declare
  `font-display: swap` and pick a fallback with similar metrics so the swap does not shift
  the layout; `size-adjust`, `ascent-override` and `descent-override` on a fallback
  `@font-face` can close the remaining gap.

## Measure and leading

- **Measure** (line length) for body text: about 60 to 75 characters on a page that is read
  (45 is fine in an app panel or on a phone). Set it with `max-width: 65ch` on the text column,
  not on the whole section.
- **Leading** (line height): body text 1.45 to 1.65; headings 1.1 to 1.25; very large display
  lines 0.9 to 1.05. The larger the size, the tighter the leading.
- **Paragraph spacing:** about one line of the text size between paragraphs; no first-line
  indent on the web unless the direction is explicitly bookish.
- **Rag and widows:** `text-wrap: balance` on headings, `text-wrap: pretty` on paragraphs
  where supported; they are progressive enhancements, nothing breaks without them.
- Left-align body text. Centre only short display lines.

## Colour strategies

Pick one strategy on purpose and write it in the brief. Most generic pages are generic because
nobody picked: a neutral page with a framework-blue button is a default, not Restrained.

### Restrained: neutrals and one accent

- **What it is:** the page is ink on paper; one accent colour marks the action and maybe one
  highlight. Character comes from type, space and imagery.
- **When:** products whose material should speak (photography, product screenshots, work
  samples); serious or technical audiences; pages where the bold move is typographic.
- **Build:** choose the paper and ink with a slight tint toward the accent's hue (pure grey
  looks dead next to a colour). Use the accent only on the primary action and at most one
  other element. Two or three neutral steps for surfaces and borders.

### Committed: one colour carries the brand

- **What it is:** one brand colour appears on large surfaces (a hero block, a section
  background, the footer), not just buttons; neutrals do the rest.
- **When:** a brand that owns a colour or should; consumer products; pages that need to be
  recognisable at a glance.
- **Build:** pick the brand colour, then derive a lighter tint for quiet surfaces and a
  darker shade for text on light backgrounds. Decide the text colour that sits on the brand
  surface and check its contrast there. The action button must still stand out on and off
  the brand surface; it may need its own colour or an inverted style.

### Full palette: several colours with roles

- **What it is:** three to five colours, each with a job (categories, sections, product
  lines, illustrations).
- **When:** playful, educational or multi-product pages; content that is genuinely
  categorical.
- **Build:** fix the roles before the colours. Keep lightness and chroma similar across the
  set so no colour shouts by accident (OKLCH makes this easy: vary hue, hold L and C close).
  Keep one neutral pair for text and surfaces. Never let colour be the only signal of a role.

### Drenched: one saturated colour floods the page

- **What it is:** the background itself is a strong colour, across most of the page; text
  and images sit on it.
- **When:** launch pages, events, portfolios, one-pagers whose bold move is the colour
  itself. Rarely right for long reading.
- **Build:** choose the flood colour and one text colour (often near-white or near-black
  tinted toward the flood hue). Add at most one contrasting accent. Test photographs on the
  flood: they may need a frame or a neutral band. Watch contrast for small text especially.

### OKLCH for building palettes

`oklch(L C H)` takes lightness (0 to 100%), chroma (0 to about 0.37) and hue (0 to 360).
Because lightness is perceptual, you can step it evenly and get even-looking steps, and swap
hues without changing how light a colour feels.

```css
:root {
  /* Restrained: neutrals tinted toward the accent hue (35) */
  --paper:   oklch(98.5% 0.006 35);
  --surface: oklch(95%   0.010 35);
  --line:    oklch(88%   0.012 35);
  --muted:   oklch(50%   0.015 35);
  --ink:     oklch(20%   0.015 35);
  --accent:  oklch(55%   0.17  35);
  --accent-ink: oklch(99% 0.005 35); /* text on the accent: about 5:1, check yours */
}
```

- Shades of one colour: hold H, step L, lower C toward the light and dark ends (very light
  and very dark colours cannot carry high chroma; the browser clips them).
- A set of colours with equal weight: hold L and C, vary H.
- Older browsers ignore `oklch()`; if the project must support them, put a hex fallback on
  the line before.

## Light or dark

Decide from the reader's scene (see `SKILL.md`), not from what looks premium:

- Bright surroundings, quick checks, long reading: light.
- Evening, immersive, gallery-like or media-first: dark can work.
- On dark, avoid pure black and pure white: use a dark tinted surface and an off-white ink,
  and lower the accent's chroma a little so it does not vibrate.
- Supporting both is a product decision; if you do, define both palettes as custom
  properties and switch with `prefers-color-scheme` (and a toggle if the user wants one),
  checking each strategy in both.

## Contrast reminder

Taste never overrides legibility. Body text needs at least 4.5:1 against its background,
large text (about 24px, or 19px bold) and essential icons and borders at least 3:1. Check
every text colour on every surface it actually sits on, especially text on the brand colour
(Committed), on the flood (Drenched) and over photographs. The web-accessibility skill covers
the full rules and how to test them.
