---
version: alpha
name: Chog Credit
description: A vault and a credit line for a Chog NFT. Playful wrapper, exact numbers. Dark violet-ink app, cream landing page, one status system that never relies on colour alone.
sources:
  - https://www.chog.xyz
  - https://mint.chog.xyz
  - https://chogathon.chog.xyz
  - docs/brand/BRAND_PASS.md
  - docs/brand/CONTRAST_REPORT.md
  - Brand board (Design canvas) sections 1 to 7
notes:
  - "Evidence: colours #836EF9, #7831FF, #46188D, #E845A4, #CE437C, #FCBB00, #F3F1F8, ink #0E0B1A / #141026 / #181330 and fonts Baloo 2, Inter, JetBrains Mono, Gaegu were read from Chog's public pages on 2026-10-23. They are not from an official brand kit."
  - "Inference (mine): the ink steps above #181330, the button fill #6B52F0, the status colours, the cream steps, all component rules, the three marks, the motion, sound and haptic specs."
  - "Not cleared: use of Chog artwork and the CHOG wordmark. Until the Chog team confirms in writing, every Chog frame is the neutral placeholder."
  - "Every contrast number below was produced by scripts/brand_contrast_check.py (WCAG 2.x + APCA-W3 0.0.98G-4g + Machado colour-vision simulation). Re-run it after any palette change."
  - "All figures in mockups are SAMPLE data on a TESTNET with MOCK assets. Nothing here is a statement about live availability."

colors:
  ink-950: "#0E0B1A"        # page background (app)
  ink-900: "#141026"        # cards
  ink-850: "#181330"        # raised cards, inputs
  ink-800: "#211A40"        # modals, menus, skeleton blocks
  ink-700: "#2D2556"        # hairlines, borders, tear line
  cream-50: "#FAF9FC"       # text on ink; page on landing
  cream-100: "#F4F1E6"      # landing surface
  cream-200: "#E7E2D0"      # landing borders
  text: "{colors.cream-50}"             # 17.69:1 on ink-900 (Lc 103)
  text-muted: "#D2CCEA"                 # 11.99:1 on ink-900 (Lc 77)
  text-muted-light: "#575070"           # 6.66:1 on cream-100 (Lc 78)
  purple-500: "#836EF9"     # Monad purple: marks, strokes, focus (dark). Never a text-bearing fill
  purple-300: "#B7AAFF"     # links and focus ring on ink; 9.02:1 on ink-900
  purple-btn: "#6B52F0"     # primary button fill; cream text 4.89:1 (Lc 76)
  purple-700: "#46188D"     # deep purple: marks and focus ring on cream; cream text 11.27:1
  link-light: "#5B3FD6"     # links on cream; 6.40:1 on cream-50
  pink-500: "#E845A4"       # the stamp, stickers. Decoration only, NEVER status
  pink-300: "#FF8FD0"
  amber-400: "#FCBB00"      # highlights. Not a status colour
  testnet-pill: "#F9C230"   # TESTNET / MOCK pill fill; ink text 11.82:1
  status-safe: "#72E4BC"
  status-watch: "#F9C230"
  status-risk: "#EA7C31"
  status-danger: "#C83846"
  status-paused: "#9A93C9"
  status-safe-tint: "#22343C"
  status-watch-tint: "#3E2F1F"
  status-risk-tint: "#3E262D"
  status-danger-tint: "#3E1F32"
  status-paused-tint: "#211A40"

typography:
  display:
    fontFamily: "Baloo 2, ui-rounded, system-ui, sans-serif"
    fontWeight: 800
    use: "Landing and onboarding headings only"
    sizes: { hero: "clamp(52px, 7vw, 96px)", h1: "clamp(36px, 4vw, 52px)", h2: "30px", h3: "22-26px" }
    lineHeight: 1.05
    letterSpacing: "-0.01em to -0.02em"
  body:
    fontFamily: "Inter, system-ui, sans-serif"
    fontWeight: 400
    emphasisWeight: 600
    sizes: { large: "18-20px", base: "16px", small: "14px", caption: "12-13px" }
    lineHeight: 1.45-1.55
  numeric:
    fontFamily: "JetBrains Mono, ui-monospace, monospace"
    fontWeight: 600
    fontVariantNumeric: tabular-nums
    use: "Every amount, address, percentage, token id and hash"
    sizes: { hero: "44px", metric: "20-28px", inline: "13-15px" }
  hand:
    fontFamily: "Gaegu, cursive"
    fontWeight: 700
    use: "The Chog bubble only. One line. Never a label."
    sizes: { bubble: "19-26px" }

rounded:
  chip: 10-12px
  field: 14px
  button: 16px
  art-frame: 14-16px
  card: 20px
  account-card: 22-26px
  pill: 6px
  notch: "24px circle centred on the card edge"

spacing:
  base: 8px
  scale: [4, 8, 12, 16, 20, 24, 28, 32, 40, 56, 64]
  card-padding: 14-16px
  section-gap: 24-40px
  gutter: 16px
  touch-target: { minimum: 44px, money-action: 56px, primary-cta: 60px }

components:
  button-primary:
    backgroundColor: "{colors.purple-btn}"
    textColor: "{colors.cream-50}"
    height: 56px (60px for the single main CTA)
    rounded: "{rounded.button}"
    font: "Inter 600 16-17px"
  button-secondary:
    backgroundColor: transparent
    border: "2px solid {colors.purple-500}"
    textColor: "{colors.cream-50}"
    height: 56px
  button-disabled:
    backgroundColor: "{colors.ink-900}"
    border: "1px dashed {colors.ink-700}"
    textColor: "{colors.text-muted}"
    rule: "Always shows a padlock and says why ('Borrow paused'). Never just greyed out."
  card:
    backgroundColor: "{colors.ink-900}"
    border: "1px solid {colors.ink-700}"
    rounded: "{rounded.card}"
  account-card:
    backgroundColor: "{colors.ink-900}"
    border: "1px solid {colors.ink-700}"
    rounded: "{rounded.account-card}"
    notches: "two 24px circles in the page background colour, centred on the left and right edges at the tear line"
    tearLine: "2px dashed {colors.ink-700} between the Chog frame and the numbers"
  chog-frame:
    border: "2px solid {colors.purple-500}"
    rounded: "{rounded.art-frame}"
    placeholder: "diagonal hatch of ink-850 / ink-800, label 'Chog art · placeholder', token id badge in cream"
  status-chip:
    shape: "rounded {rounded.chip}, 2px border in the status colour, tinted background"
    content: "icon (status colour) + word (cream, 600)"
  field:
    height: 56px
    backgroundColor: "{colors.ink-850}"
    border: "2px solid {colors.purple-500} (error: {colors.status-risk})"
    font: "JetBrains Mono 20px"
  bubble:
    backgroundColor: "{colors.cream-50}"
    textColor: "{colors.ink-900}"
    rounded: "18-20px with a 4px tail corner at the bottom-left"
    font: "Gaegu 700"
  testnet-pill:
    backgroundColor: "{colors.testnet-pill}"
    textColor: "{colors.ink-950}"
    font: "JetBrains Mono 600 11-12px"
    rounded: 6px
  app-header:
    height: 60px
    wordmark: "Chog Credit (Baloo 2 800) + one pink square full stop"
  tab-bar:
    height: 68px
    items: [Account, Borrow, Activity, Sell, Risk]
    active: "{colors.purple-300}"
---

# Chog Credit design system

## Overview

Chog Credit puts a vault and a credit line behind a Chog NFT. The brand has **two registers with one seam**:

- **Chog register** (landing page, onboarding, empty and success states): cream and violet, rounded Baloo 2 headings, handwritten asides, pink and amber stickers. Chaos and play are allowed here.
- **Ledger register** (every screen that shows money): dark violet-ink surfaces, Inter for words, JetBrains Mono for numbers, status always icon plus word plus colour. Calm, exact, boring on purpose.
- **The seam is the Account Card.** The Chog is on top (playful), the numbers are the tear-off underneath (exact).

Personality in one line: *chaos outside, ledger inside.* Never let the playful style touch a balance.

Product facts the design must never contradict:
- The Chog is the **key, not the collateral**. It is never priced, and never taken.
- Only the assets in the vault back the loan. A Uniswap position counts at the oracle price; the Chog token counts as zero.
- If prices are unavailable, Borrow and withdrawing are off and **Repay still works**.
- Say "borrow USDC from the pool". Never "mint". Never "risk-free", "guaranteed", or "your floor is your limit".
- Every non-live number wears a label: `TESTNET`, `MOCK ORACLE`, `SAMPLE`.

## Colors

Dark theme is the product. The cream theme is for the landing page only, because the status colours can only be told apart reliably on dark (see Status).

| Role | Value | Notes |
|---|---|---|
| Page / card / raised / modal | ink-950 / 900 / 850 / 800 | elevation is a lighter surface step, not a shadow |
| Border | ink-700 `#2D2556` | 1 px; the tear line is 2 px dashed |
| Text | cream-50 `#FAF9FC` | 17.69:1 on ink-900 |
| Muted text | `#D2CCEA` | 11.99:1 on ink-900; passes APCA Lc 75 for small text |
| Brand mark, stroke, focus (dark) | purple-500 `#836EF9` | 4.92:1 against ink-900 as a stroke |
| Primary button | purple-btn `#6B52F0` | cream text 4.89:1, Lc 76; fill vs surface 3.61:1 |
| Link (dark) | purple-300 `#B7AAFF` | 9.02:1 |
| Stamp, stickers | pink-500 `#E845A4` | never status, never text |
| Landing | cream-50 / cream-100 | text ink-900 16 to 17:1; muted `#575070` 6.66:1; links `#5B3FD6` 6.40:1 |

**Why the button is not Monad purple.** Cream text on `#836EF9` is 3.60:1 and fails. Ink text passes WCAG (5.14:1) but is weak on APCA (Lc 39). A deeper fill passes both. Monad purple stays for marks, strokes and focus rings.

**Proportions.** 60 percent ink surfaces, 30 percent cream and muted text, 10 percent purple, pink and amber accents.

**Colour tokens are semantic.** Components use roles (`surface`, `text`, `accent`, `status-*`), never raw hexes. Palette values live in one reference layer. Derive hover and pressed states from the base token (for example `color-mix(in oklab, <base>, white 12%)`) instead of hand-picking a second hex.

### Status system

The only place red, orange, green and amber appear. Colour is carried by the **icon and border**; the label is always cream on a tinted chip (12 to 14:1).

| State | Icon colour | Tint | Icon | Word | Meaning |
|---|---|---|---|---|---|
| Safe | `#72E4BC` (11.96:1) | `#22343C` | check in circle | Safe | comfortably within the limit |
| Watch | `#F9C230` (11.30:1) | `#3E2F1F` | eye | Watch | getting close; nothing to do yet |
| At risk | `#EA7C31` (6.56:1) | `#3E262D` | triangle | At risk | add assets or repay soon |
| Liquidatable | `#C83846` (3.63:1) | `#3E1F32` | octagon | Liquidatable | others may repay your debt and take assets |
| Prices paused | `#9A93C9` (6.53:1) | `#211A40` | pause bars | Prices paused | no price, so Borrow is locked; Repay works |

Verified: the four main states stay at least dE 0.143 apart (OKLab) under normal vision, protanopia, deuteranopia and tritanopia. Safe and Watch share lightness (0.841), so the icon and the word are required to tell them apart. Pink is never a status colour. Status UI is dark-only in v1: the light theme cannot separate the four as well (closest pair dE 0.054 under protanopia).

## Typography

- **Baloo 2** 800 for display (landing and onboarding only). **Inter** 400/500/600 for every sentence in the app. **JetBrains Mono** 600 with tabular figures for every number. **Gaegu** 700 for the Chog bubble only.
- All four are open-licence Google Fonts. Fluid headings with `clamp()`; body 16 to 18 px; money figures 28 to 44 px mono.
- Amounts: USDC shown to 2 decimals, full precision in a tooltip. Addresses shortened (`0xA4D1…e9C2`) with a copy button and the full address announced to screen readers.
- Inputs use at least 16 px so iOS does not zoom.
- Sentences under 20 words; one idea per sentence; jargon explained inline once (for example "Health: how far you are from being liquidated").

## Layout

- 8 px grid. Mobile-first with `min-width` queries, fluid sizing with `clamp()`, and **container queries** for components (the Account Card behaves the same in a sidebar or full width). Media queries only for page structure.
- Phone: bottom tab bar (68 px). From about 900 px: left rail. Use `svh`/`dvh`, never `100vh`; honour safe-area insets.
- Cards: 20 px radius, 1 px ink-700 border. The Account Card is 22 to 26 px with the Slip's notches.
- Test by dragging from 280 to 2560 px. Long text and addresses must not overflow flex children (`min-width: 0`).
- Z-index uses a small tiered scale (base, sticky, overlay, modal, toast); no `9999`.

## Components

**Account Card (the hero component).** From top: Chog Frame (2 px purple border, token id badge, art unaltered), status chip, Health Ring and the three numbers (*Assets in vault*, *You owe*, *You can borrow*), then the Chog bubble. A 2 px dashed tear line with notches separates the Chog from the numbers. Five variants: Safe, Watch, At risk, Liquidatable, Prices paused (dashed outer border, dashed ring, "--" in place of unavailable values).

**Health Ring.** 270 degrees opening at the bottom, radius 52 in a 120 box, stroke 10, track ink-700, progress purple-500, one pink dot at the end. The ring **never changes colour**; the chip beside it does. Centre shows the number (mono 24) and "Health".

**Buttons.** Primary, secondary, disabled-with-reason. Money actions 56 px; the main CTA 60 px; text names the action and the amount ("Borrow 340.00 USDC", "Repay all (512.40 USDC)"). Actions fire on release. Destructive actions are never adjacent to the primary action.

**Fields and errors.** Label above, never placeholder-only. On error: border in the risk colour, a persistent message (`role="alert"`, `aria-describedby`) that says what happened, why, and what to do, with a one-tap fix ("Use 340.00"). Never clear what the user typed; never auto-dismiss an error.

**Tables.** Real `<table>` with `<caption>`, `<th scope>`. Activity columns: Time, Action, Amount, Status (icon + word). Status words for transactions: **Submitted**, **Confirmed**, **Final** (three different facts; Monad's speculative finality means "seen" is not "final").

**Banners.** Persistent, inline, never a toast for anything the user must act on. Prices-paused banner: pause icon, "Prices are paused", one sentence saying Borrow and withdrawing are off and Repay and adding assets still work.

**Chog bubble.** One line of handwritten text beside the card, reading the account state in words. It repeats what the chip says and never gives advice beyond the neutral prompts in the brand pass.

**Navigation.** App header 60 px with the wordmark and the TESTNET pill. Tab bar: Account, Borrow, Activity, Sell, Risk. Active tab purple-300 with an icon and a bold label.

**Sell with Vault.** Equity first (assets minus loan) in large mono; then "What the buyer signs" in plain words (the loan is *at most* X, the vault holds *at least* Y, health is *at least* Z); an optional payoff block that shows exactly what the seller receives and the loan the buyer takes over; and a warning sentence about liquidation. Primary action: "Ask the buyer to sign".

### Iconography

2 px stroke, round caps and joins, 24 px grid, one set only. No emoji. Icon-only buttons have an `aria-label`; decorative icons are `aria-hidden`.

## Imagery

- **Chog artwork is official art only**, supplied by the Chog team, shown unaltered inside the Chog Frame. Until permission is confirmed, use the placeholder frame. Do not generate, redraw or imitate a Chog.
- Illustrations and stickers are flat vector, thick rounded outlines, limited to pink, amber, cream and violet. Props sit **around** the frame, never on the Chog.
- Backgrounds: cream paper with a faint dotted ledger grid and a soft violet glow (landing); deep violet-black with a barely visible radial glow (app). No stock photography, no video backgrounds.
- Image-generation prompts must say "no characters, no faces, no text, no logos".

## Logo And Usage

Three marks, three jobs.

| Mark | Job | Where | Never |
|---|---|---|---|
| **A. The Slip** | Brand logo | Lockup, app icon, favicon, social, deck cover, the Account Card's shape | In the app's top bar |
| **D. The Full Stop** | Top-bar wordmark | App header and website nav: "Chog Credit" with one pink square full stop; "cc." where space is tiny | As the app icon or favicon |
| **B. The Pixel Key** | Prop | Stickers, the bubble's "browsing" state, empty states, social | As a logo or an icon |

Retired: the C-Ring (overused ring gauge) and the Brackets.

- **Slip construction (100-unit grid):** body x 8 to 92, y 26 to 74, corner 8; side notches radius 7 at mid-height; pink stamp 18 by 18 (radius 4) at x 19, y 41; cream text bars; dashed perforation at x 66. At 32 px or smaller drop the text bars; at 16 px drop the perforation. Clear space = the notch diameter. Minimum 16 px.
- **Lockup:** `[official CHOG wordmark]` + "Credit" in Baloo 2 800, one cap-height apart, the Slip to the left.
- **Colours:** purple-500 on ink; `#46188D` on cream; mono cream on `#2D2556`.
- **Pixel Key:** 12 by 6 pixel grid, 8 units per pixel, 2 by 2 pink gem; not drawn below 48 px wide.
- Never put any mark over a Chog; never place the Slip and the wordmark side by side in one bar; never recolour a mark by risk.

## Motion

Archetype: **Premium** for anything with money; **Playful** only on the Chog bubble and stickers. Live demos with reduced-motion previews are on brand board 7.

- Tokens: `--ease: cubic-bezier(0.4, 0, 0.2, 1)`; `--ease-pop: cubic-bezier(0.34, 1.56, 0.64, 1)` (bubble only); `--dur-quick: 150ms`, `--dur-standard: 300ms`, `--dur-slow: 500ms`; `--rise: 12px`; `--stagger: 60ms`.
- Entrances rise 12 px and fade, hero first, whole stagger under 400 ms; entrances run 30 to 50 percent longer than exits.
- Moments: Vault Door 500 ms; health dot 300 ms; Confirmed pop + tick draw 300 ms; changed digits roll 300 ms; button press under 100 ms with a 200 ms settle; chip swap 300 ms; error shake 3 x 9 px in 300 ms; **Pause Drill**: Borrow locks while Repay does not move, 300 ms; transaction steps fill only when truly reached; skeleton shimmer 1.4 s after 100 ms; bubble 250 ms with 4 percent overshoot; optional once-ever tear-off 500 ms; landing hero entrance under 500 ms plus a 6 px, 6 s float as the only ambient loop.
- Rules: animate only `transform` and `opacity`; at most 20 animated elements per screen; no more than a third of the elements move at once; never linear for movement; loops over 5 s need a pause control; no flashing (3 Hz limit); information is never carried by motion alone.
- Context: phones about 0.8x durations, stagger cut by a third, no ambient loops; dark theme about 15 percent less intensity.
- **Reduced motion** (from the OS setting): remove movement, keep opacity, halve durations or more, no loops, no auto-play, static closed vault door, no shake (message only), numbers swap.

## Sound and haptics

One sonic idea: **a stamp**. Warm sine and triangle tones, quiet (peak about 14 dB under full scale), none over 400 ms, two notes at most for a confirmation. Nothing is an alarm and nothing is the only signal.

| Moment | Heard | Felt (ms) |
|---|---|---|
| Chog goes in the vault | soft low thunk, 160 ms | 25 |
| Submitted | nothing | 8 |
| Confirmed | two rising notes, about 250 ms | 15, 40, 15 |
| Final | one quiet ping, 140 ms | 12 |
| Repaid, debt-free | three-note rise, about 300 ms | 10, 30, 10, 30, 20 |
| Error | two soft falling notes | 30, 50, 30 |
| At risk (risk sounds on) | two low pulses | 20, 60, 20 |
| Liquidatable (risk sounds on) | three low pulses, once | 40, 60, 40, 60, 40 |
| Prices paused | two soft falling notes | 10 |
| Chog bubble | tiny bloop, 80 ms | none |

- **Sound is off by default.** Offered once in one sentence ("Want tiny sounds?") after the first confirmed transaction. Never on page load, never a modal, never autoplay.
- **Risk-alert sounds are a separate switch, also off,** and play once.
- **Haptics are on where supported and off when the device asks for reduced motion;** at most 250 ms, only on confirmations, errors and warnings.
- Borrowing is not celebrated: Confirmed is neutral. The brighter rise is only for being debt-free.
- Limits: the browser Vibration API works on Android Chrome but not on iPhone Safari or desktop; native system haptics are untested.

## Accessibility

- **Focus:** a 3 px solid ring with a 3 px gap, so its contrast is measured against the surface, not the element. Dark theme `#B7AAFF` (9.02:1 on ink-900). **Cream theme `#46188D` (11.27:1 on cream-50); the lavender ring is only 1.96:1 there and must not be used.**
- **Contrast:** text 4.5:1 (WCAG) and, for small text, APCA Lc 75 or more; non-text and icons 3:1. Muted text `#D2CCEA` was chosen to meet Lc 75.
- **Never colour alone:** every status has an icon and a word; charts have borders, direct labels and a table fallback.
- **Screen readers:** status changes announced (`aria-live="polite"`, errors `role="alert"`); real buttons, links, labels, tables with captions and headers; icon-only controls named; addresses read in full.
- **Touch targets:** 44 px minimum, 56 px for money actions; 8 px minimum gap; no double-tap, no gesture-only actions.
- **Cognition:** one job per screen, previews before every consequential action with exact figures, safest option as default, undo wherever the chain allows it, plain language.
- **Motion:** see Reduced motion. No parallax, scroll-jacking or full-screen zoom.

## Do's and Don'ts

**Do**
- Show the Chog, then the ledger. Keep the two registers apart.
- Put the amount on the button. Show *health after* before anyone signs.
- Say the quiet part: "Your Chog is the key, not the collateral." "Testnet. Mock assets. Not audited."
- Keep Repay visible and active when everything else is locked.
- Use semantic tokens; derive states from a base token.
- Label every sample, testnet and mock value.

**Don't**
- Don't draw, redraw, recolour or imitate a Chog, and don't put a mark over one.
- Don't use pink or Monad purple for status, or Monad purple as a text-bearing fill.
- Don't use motion, sound or colour as the only carrier of information.
- Don't celebrate borrowing, gamify debt, or use streaks.
- Don't claim "risk-free", "guaranteed", "mint USDC", or that a floor price is a limit.
- Don't use a toast for anything the user must act on, or auto-dismiss an error.
- Don't ship a status chip without its icon and word.

## Verification

```
python3 -I scripts/brand_contrast_check.py      # WCAG + APCA + colour-blind separation
```
Before release also check by hand: every screen at 280, 390, 768, 1440 and 2560 px; keyboard-only through the borrow, repay and sell flows; a screen reader on the status and error states; reduced-motion on; greyscale. The brand board contains no verified accessibility audit; it is a visual draft.

## Open items

1. Written permission from the Chog team for artwork and wordmark use (blocks any real Chog on screen).
2. Final launcher icon set for the Slip (icon-generator skill) and a hand-built 16 px favicon grid.
3. Production sound files (loudness-checked) to replace the synthesised specification.
4. A tested native-haptics mapping if the product ships as an app.
5. Real thresholds for Watch / At risk / Liquidatable from the pool's settings (the board's numbers are illustrative).
