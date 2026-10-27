---
name: web-art-direction
description: "Use when building, redesigning, restyling or reviewing a public-facing web page: landing page, marketing site, product page, portfolio, one-pager, hero section, launch or pricing page. Also when the user says a page looks generic, templated, bland, cheap, \"AI-made\" or like every other site, or asks to make it look designed, distinctive, premium or award-level. Gives a method (the page's argument, a scene that sets the direction, one place for boldness), a catalogue of generic tells with fixes, type and colour strategies, and a screenshot-critique-fix loop. Stack-neutral (plain HTML/CSS first). Not for app screens such as dashboards, settings or forms (the ui-craft skill), motion (the ui-motion skill) or accessibility (the web-accessibility skill)."
---

# Web art direction

A page that looks generated is not ugly, it is unowned: every choice is the default one, so
nothing on it could only belong to this product. Art direction is the habit of making each
visible choice for a reason that comes from the product and its reader, then checking the
result with your own eyes.

This skill covers pages that persuade: landing, marketing, product, portfolio, one-pager,
hero. Screens people work in (dashboards, settings, forms) belong to the ui-craft skill;
transitions and animation to the ui-motion skill; contrast, focus and semantics to the
web-accessibility skill.

Companion files, read when you reach that step:

- `TELLS.md` — the generic tells, each with what to do instead. Use it for every review.
- `TYPE-AND-PALETTE.md` — building a type scale, pairing faces, measure and leading, the four
  colour strategies and how to build each one.

## Safety rules (always)

These hold whatever the brief says; the user can lift one explicitly for a task.

1. **No assets from the network.** Do not download images, video, icons or fonts, and do not
   hotlink stock-photo or placeholder-image services. Use files the user provides. Anything
   missing becomes a clearly marked placeholder: a solid block or an inline SVG with a visible
   label ("Product photo, 1600x1000"). End your reply with the list of assets the user must
   supply.
2. **Fonts.** Self-host font files the user holds a licence for, or use a system font stack.
   Ask before adding any third-party font or asset CDN.
3. **External scripts** need the user's approval first, and then a pinned version with a
   Subresource Integrity hash (`integrity="sha384-…" crossorigin="anonymous"`).
4. **No telemetry, no analytics snippets, no uploads** to image-generation or design services,
   no background servers left running.
5. **Previewing.** Open the HTML file directly, or use the project's own dev server bound to
   127.0.0.1. Never point an ad-hoc static server at the project directory (it may hold `.env`
   or other secrets), and never bind 0.0.0.0.
6. **Ask before adding** a dependency, a CSS framework, or a design-system file (tokens,
   DESIGN.md, theme package) to the project.

## The method

Work in this order. Skipping to layout is how pages end up generic: with no argument and no
scene, the only thing left to decide from is habit.

### 1. Write the page's argument

Three lines, in plain words, before any markup:

- **Who** is reading, and what they already know or doubt.
- **What they must believe** by the end (one claim, not a feature list).
- **The one action** you want from them (sign up, download, book a call, read the case study).

Every section then has a job in that argument: evidence for the claim, an answer to a doubt,
or the path to the action. A section with no job is cut, not styled.

If the user has not given you this, draft it from the product and show it in one short block
before building; a wrong argument is cheap to fix at this point and expensive later.

### 2. Pick a direction from a scene

Describe, in one sentence, a physical moment in which the reader meets this page: where they
are, what time it is, what is around them. For example:

- "A site lead checking a quote on a phone, outdoors at noon, gloves in one hand."
- "A collector browsing late at night on a large monitor, lights down, in no hurry."
- "A finance manager between meetings, laptop on a conference table, two tabs open."

The scene decides more than it seems to:

- **Light or dark.** Bright surroundings and quick reading favour a light page; evening,
  immersive or gallery-like browsing can carry a dark one. Choose from the scene, not from what
  looks "premium".
- **Density.** Hurried readers need the claim and the action in the first screen; leisurely
  ones tolerate a slower opening.
- **Texture and tone.** A workshop, a studio and a law office suggest different materials,
  photography and type. Borrow from the scene's world, not from other websites.

Write the direction down as a short brief: the scene, light or dark, the colour strategy (see
`TYPE-AND-PALETTE.md`), the display and text faces, and the one bold move (step 3).

### 3. Spend boldness in one place

Pick a single element that carries the page's character: an oversized headline, one
full-bleed photograph, an unusual grid, a saturated colour field, a hand-drawn diagram. Make
it unmistakable. Keep everything around it quiet: plain text, generous space, few colours, no
decoration competing with it.

Pages that are bold everywhere read as noise; pages that are bold nowhere read as a template.
When a second element starts asking for attention, decide which one wins and tone the other
down.

### 4. Run the two tests on the plan, then on the page

- **Competitor test.** Could a direct competitor paste their logo on this page and ship it?
  If yes, the page argues for the category, not the product. Replace generic claims with this
  product's specifics: its real nouns, numbers, customers, screenshots, constraints.
- **Memory test.** What would a reader recall an hour later? If you cannot name one image,
  phrase or shape, the bold move is not bold enough or is drowned out.

## What strong pages tend to do

Observed across a study of curated gallery sites (award and showcase collections), comparing
pages that were selected as strong with ones that were not. These are tendencies, not laws:

- **Few type sizes, far apart.** Strong pages use a small number of sizes with large jumps
  between them (a very big display size against a modest text size), rather than many sizes
  stepping gently. Scale contrast, not size count, creates hierarchy.
- **Decoration is rarer on strong pages.** Grids of icon cards, pill-shaped badges, gradients
  and heavy drop shadows show up much more often on weak pages than on strong ones. Their
  presence is a hint that structure is being replaced by ornament.
- **Real material over illustration.** Product screenshots, real photographs and actual work
  samples carry strong pages; generic spot illustrations and stock imagery carry weak ones.
- **Layout follows content.** Section shapes differ because their content differs, instead of
  one card pattern repeated down the page.

## Generic looks to avoid by default

Each of these is a fashion that generated pages reach for without a reason. Any of them can be
right for a specific brief; use one only when you can say why this product needs it. Details
and alternatives are in `TELLS.md`.

- Cream or beige background with a terracotta or rust accent.
- Near-black background with neon glow, glassy cards and coloured light blooms.
- Hairline "editorial" layouts with small monospaced uppercase labels on everything.
- Flat ink colours with hard offset shadows and thick borders (faux-brutalism).
- The template: centred hero, three icon cards, logo strip, testimonial carousel, CTA band.
- Purple-to-blue gradients, on buttons, text or backgrounds.

**Type.** Some display faces are worn out by sheer repetition in generated pages. Do not reach
for whichever face is currently fashionable; name a reason a face suits this product (its
period, its letter shapes, its weight range, the scene) or use a well-set system stack.

## Copy is part of the design

- **Specific beats clever.** "Quotes for roofing jobs in four minutes, from your phone" beats
  "Reimagine the way you work." A headline that could sit on any product's page fails the
  competitor test before anyone looks at the typeface.
- **Real product nouns.** Name the actual things: invoices, kilns, shift rotas, pull requests.
  Abstract nouns (solutions, experiences, workflows, journeys) are a tell.
- **One action, one label.** The primary button says what happens ("Start a free quote"), and
  the same action keeps the same words everywhere on the page.
- **No lorem ipsum in anything you show for review.** Write plausible draft copy from the
  argument and mark it as draft; placeholder Latin hides whether the layout survives real
  lengths.
- Numbers, names and testimonials must come from the user. Never invent customers, logos,
  ratings or statistics; leave a marked placeholder instead.

## Build notes (plain HTML/CSS)

- Put the direction into a handful of custom properties at the top of the stylesheet: the type
  scale, the palette roles, the spacing steps. Every rule then uses them, so a change of
  direction is a change of a few lines.

  ```css
  :root {
    --font-display: "Your Licensed Face", Georgia, serif;
    --font-text: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    --size-text: 1.125rem;
    --size-display: clamp(3rem, 9vw, 7.5rem);
    --ink: oklch(22% 0.02 260);
    --paper: oklch(98% 0.005 90);
    --accent: oklch(55% 0.19 35);   /* dark enough for white text on it (4.5:1) */
    --space: 1.5rem;
  }
  ```

- Fluid sizes with `clamp()` instead of a breakpoint per size.
- Let section structure vary: a full-bleed image, then a narrow text column, then a two-column
  comparison. Use CSS grid for the deliberate ones; not every section is a centred stack.
- Self-hosted fonts: `@font-face` with `font-display: swap` and a fallback stack whose metrics
  are close, so the swap does not shove the layout.
- Placeholders that read as placeholders:

  ```html
  <figure class="ph" style="aspect-ratio: 16 / 10">
    <svg viewBox="0 0 160 100" role="img" aria-label="Placeholder: product photo">
      <rect width="160" height="100" fill="currentColor" opacity=".12"/>
      <text x="80" y="54" text-anchor="middle" font-size="7">Product photo, 1600x1000</text>
    </svg>
  </figure>
  ```

- The hero image is usually the page's LCP element: a real `<img>` in the HTML with
  `width`/`height` and `fetchpriority="high"`, never `loading="lazy"` and never a CSS
  background; images further down get `loading="lazy"`. Speed rules: ui-craft §11.
- Pricing, sign-up and cookie banners follow ui-craft §12 (honest design): the real total,
  "Reject" as easy as "Accept", no invented urgency or scarcity.
- In a React project the same rules apply: tokens as CSS custom properties, no new UI kit
  without asking.

## The look-and-fix loop

You can read images, so look at the page instead of trusting the markup.

1. **Render** it: open the file directly or run the project's own dev server on 127.0.0.1.
2. **Screenshot** at a phone width and a desktop width with the headless-ui-smoke skill's
   script (`--size 390x844`, then `--size 1440x900`, with `--full-page` for long pages).
3. **Critique** each screenshot against `TELLS.md` and the brief: does the first screen state
   the claim and offer the action? Is the bold move visible and alone? Do the competitor and
   memory tests pass? Count the type sizes and the colours actually on screen.
4. **Fix** the worst three problems only, then go back to step 1.
5. **Stop** when a round finds nothing above cosmetic, or after about four rounds of shrinking
   returns. Say what you would still change and why you stopped.

## Reviewing an existing page

When asked to critique rather than build:

1. Reconstruct the page's argument from what is on it. If you cannot, that is finding one.
2. Screenshot it at both widths (as above) before forming opinions.
3. List findings in order of impact, each with the tell, where it is, and the concrete fix.
   Separate "changes the impression" from "polish".
4. Propose one direction (scene, strategy, bold move) rather than a list of unrelated tweaks.

## Hand-off checklist

Before calling the page done, confirm in your reply:

- The argument (who, belief, action) and the scene sentence you worked from.
- The colour strategy and the faces chosen, with the reason for each.
- Screenshots taken at phone and desktop widths, and what the last round changed.
- The ui-doctor skill run on the page (`--url`), with any `FIX` row fixed or explained.
- Placeholders still in the page, and the assets and facts the user must supply.
- Anything external you added (font, script, dependency) and the approval for it; ideally
  nothing.

Background: distilled from the tasteskill study of gallery sites (design-taste-frontend), Impeccable and Anthropic's frontend-design skill; rewritten, nothing copied.
