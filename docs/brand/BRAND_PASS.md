# Chog Credit: Brand Pass (v1)

Status: **creative direction, not a build.** Nothing here is implemented in a UI. Product claims are limited to what exists in source today (see `docs/IMPLEMENTATION_STATUS.md`); everything runs on mock assets and a mock oracle until a testnet deployment is verified. Colour numbers come from `scripts/brand_contrast_check.py` (report: `docs/brand/CONTRAST_REPORT.md`).

Method: your Chief Brand Designer prompt, informed by ten design skills (motion, inclusive design, wireframing, icons, colour science, designer suite, frontend system rules, UX flows, brand-to-DESIGN.md, responsive craft). Direct evidence about Chog's own public look was read from chog.xyz, mint.chog.xyz and chogathon.chog.xyz on 2026-10-23.

**What I'm confident about, and what I'm not.** Confident: the structure, the tokens, the contrast and colour-vision results, the copy rules, the demo flow. Not confirmed: that Chog's team allows us to show their artwork and wordmark (still the open item), and the exact official Chog palette (read from public pages, not from a brand kit).

---

## A. Brand Core

**Name.** Chog Credit. Keep it. It says what it is, and the Chog stays the hero.

**Positioning (one line).** Chog Credit gives a Chog NFT a vault and a credit line, so it does more than sit in your wallet.

**What it actually does (say it plainly, every time).**
- A Chog is the key and identity of a small on-chain account with its own vault.
- You put supported assets in the vault (WMON, and Uniswap V3 positions) and borrow USDC from the lenders' pool against them.
- While the account holds assets or debt, the Chog stays in escrow. It is the key, not the collateral: it is never priced and never seized.
- A funded account, even one with a loan, can be sold as one package: the Chog, the vault and the debt, on terms the buyer signs.

**The fact that changes the story.** At about $110-130 per Chog (floor 5,100-6,240 MON when last checked), the NFT alone is not a big credit limit, and we must never say it is. The value is the *account*: the Chog becomes a wallet-with-a-ledger that can be traded as a package. Brand that, not "borrow against your floor".

**Personality: chaos outside, ledger inside.** Chog's own public description is "curious, mischievous, and always finding new ways to spark a little chaos." Money screens need the opposite. The brand is the friend who is genuinely good with money and still funny. Playful in the wrapper, exact in the numbers.

**Target users.**
1. Chog holders who also hold WMON or Uniswap positions and want them to work harder.
2. Monad DeFi users who like the idea of an account that can change hands.
3. Chogathon judges, who need to understand it in one breath.

**Emotional hook.** *Your Chog has a vault now.* Short, visual, a little absurd, and true.

**What makes it memorable (four things, in order of strength).**
1. **The Account Card:** the real Chog art on a credit-card-shaped object with a live health ring.
2. **The Vault Door:** when you escrow a Chog, a vault door closes around the card. The entire ritual is one 500 ms moment.
3. **The Pause Drill:** switch the (mock) price feed off and the UI says "Prices paused", Borrow locks, **Repay stays green**. No other submission will demo fail-closed behaviour. It is our strongest trust moment.
4. **Sell it with its loan:** a Chog listed as equity (vault value minus debt) with every signed bound shown in plain words.

---

## B. Naming Options

| Item | Recommendation | Why |
|---|---|---|
| Product | **Chog Credit** | Plain, searchable, judge-proof |
| The account | **Vault** | One word, physical, matches the Vault Door |
| The borrowing feature | **Credit line** | Familiar; never "mint" (PRD copy rule) |
| The risk number | **Health** | Everyone knows it from games; show it as a ring, not jargon |
| Package sale | **Sell with Vault** | Says exactly what travels with the Chog |
| Rejected | Chogfolio, Chog Positions | Cute but vague; "Position NFT" is also banned by the PRD |

**Taglines (pick one primary).**
- **Primary: "Put your Chog to work."** Already in the draft; it is friendly and true.
- "Your Chog has a vault now." (best for social, strongest hook)
- "Borrow USDC. Your Chog stays in the vault, not on the line." (explains the safety idea; too long for a hero)
- Rejected: "Unlock your Chog's value" (implies floor-price credit), "Risk-free" anything (banned).

**Opinion.** Do not name features after finance jargon (LTV, collateral factor, health factor) in the headline UI. Show the words in plain language and put the term in a tooltip.

---

## C. Recommended Brand Direction

**Concept: two registers with one seam.**
- **Chog Register** (landing, onboarding, empty states, success): cream and violet world, rounded Baloo 2 headings, handwritten asides, pink and amber stickers. Chaotic energy, but only here.
- **Ledger Register** (every screen that shows money): dark violet-ink surfaces, Inter for words, JetBrains Mono for numbers, status always icon plus text plus colour. Calm, exact, boring on purpose.
- **The seam is the Account Card.** The Chog art (playful) sits on top, the numbers (exact) sit underneath. The same component bridges both registers, and that is the identity.

**Direct evidence for the palette (public Chog pages, 2026-10-23).**
- chog.xyz: Monad purple `#836EF9`; navy ink `#121B32`; stone cream `#D8D6C7`; magenta `#CE437C`; fonts Galindo, Gaegu, Convergence.
- mint.chog.xyz: violets `#7831FF` / `#46188D`; ink `#1B1533`; hot pink `#E845A4`; light `#F3F1F8` / `#FAF9FC`; amber `#FCBB00`; fonts Baloo 2, Press Start 2P, Inter.
- chogathon.chog.xyz: ink `#0E0B1A` / `#141026` / `#181330`; peach `#FF9B9B`; amber `#FFCF7A`; lavender `#9A93C9`; sky `#7CC6FF`; fonts Koulen, Inter, JetBrains Mono.
- Inference (mine): violet-ink, cream and hot pink are Chog's world; the old mint-on-green prototype is not.

**Tell-it-straight critique of the existing prototype (`index.html`).** The mint-on-dark-green look is generic crypto-fintech. It could be any lending app, and it says nothing about Chog. It also shows sample dollar figures as if real. The new direction replaces it entirely and labels every non-live number.

**Design rules distilled from the skills (the ones that bite).**
1. Colour never carries status alone: icon plus text plus colour, always.
2. Motion: Premium archetype for anything with money; Playful only on non-financial stickers and the Chog bubble.
3. Errors answer what happened, why, and what to do next, and never blame.
4. Every consequential action has a preview with exact figures.
5. `prefers-reduced-motion` is a first-class mode, not an afterthought.
6. Touch targets 44 px minimum, 56 px for money actions; actions fire on release.
7. Mobile-first, fluid type with `clamp()`, container queries for components.

---

## D. Logo Direction

**Rule one: Chog's character and wordmark lead, ours supports.** We do not draw, redraw or "improve" Chog. Where the official art or wordmark is not yet cleared, the UI shows a neutral frame with the token id (see F).

**Decided: three marks, three jobs (A, B and D).** The first proposal (a C-shaped ring gauge) was retired as overused. Round two (brand board, section 6) produced the system below.

| Mark | Job | Where it appears | Never |
|---|---|---|---|
| **A. The Slip** | Brand logo | Lockup, app icon, favicon, social, deck cover, the shape of the Account Card | In the app's top bar |
| **D. The Full Stop** | Top-bar wordmark | App header and website nav: the words "Chog Credit" with one pink full stop; "cc." is the monogram for tiny spaces | As the app icon or favicon |
| **B. The Pixel Key** | Prop | Stickers, the Chog bubble's "browsing" state, empty states, social | As a logo or an icon |

Dropped: the C-Ring (overused ring gauge) and C, The Brackets. The Health Ring stays as the plain gauge inside the app and is never a logo.

**Why the Slip.** A credit slip is a ticket stub or an IOU: it says "credit" and "you can hand this over" at once, it is playful, and it gives the product a signature shape. The pink square is the stamp; the dashed line is the tear line.

**The Slip is also the Account Card.** The card takes the Slip's silhouette: two notches (24 px, centred on the card edge, filled with the page background) and a 2 px dashed tear line between the Chog above and the ledger numbers below. The Chog is on top; the numbers are the tear-off.

**Lockup.** `[official CHOG wordmark]` + `Credit` in Baloo 2 ExtraBold, one cap-height apart, with the Slip to the left. Never place our marks over Chog art.

**Construction (100-unit grid, drawn as SVG on the brand board).**
- *Slip:* body x 8 to 92, y 26 to 74, corner radius 8; side notches radius 7 at mid-height; pink stamp 18 by 18 (radius 4) at x 19, y 41; text bars in cream; dashed perforation at x 66. At 32 px or smaller drop the text bars; at 16 px drop the perforation too (body + stamp only). Clear space = the notch diameter (14 units). Minimum size 16 px.
- *Full Stop:* the words "Chog Credit" in Baloo 2 ExtraBold with a square pink full stop (radius about a quarter of its width) sitting on the baseline, about 0.3 of the cap height. The "cc." monogram is the same lettering with the stop; use it only where the full name cannot fit. It is text, so it needs no artwork, and the stop is `aria-hidden`.
- *Pixel Key:* 12 by 6 pixel grid (96 by 48 units), one pixel = 8 units, pink 2 by 2 gem in the bow. Not drawn below 48 px wide.

**Variants.** Purple on ink (default), deep purple `#46188D` on cream, mono cream on `#2D2556`. App icon: the Slip on a violet-ink rounded square with a 2 px Monad-purple border. Generate launcher sets (Android and iOS) with the icon-generator skill once the Slip artwork is final.

**Do not.** Add a hedgehog or any new creature; put any mark over the Chog's face; use pink for status; put the Slip and the wordmark side by side in one top bar; recolour a mark by risk.

---

## E. Color + Typography System

### Tokens (dark app theme is the product; cream is for the landing page)

| Role | Token | Value | Notes |
|---|---|---|---|
| Surface 0 | ink-950 | `#0E0B1A` | page background |
| Surface 1 | ink-900 | `#141026` | cards (default) |
| Surface 2 | ink-850 | `#181330` | raised cards |
| Surface 3 | ink-800 | `#211A40` | modals, menus |
| Border | ink-700 | `#2D2556` | hairlines |
| Text | cream-50 | `#FAF9FC` | 17.7:1 on ink-900 (Lc 103) |
| Text muted | muted | `#D2CCEA` | 12.0:1 (Lc 77): passes small-text APCA |
| Brand mark / focus | purple-500 | `#836EF9` | Monad purple. Marks, strokes, focus ring. Not a text-bearing fill |
| Link | purple-300 | `#B7AAFF` | 9.0:1 on ink-900 |
| Primary button fill | purple-btn | `#6B52F0` | cream text 4.89:1 (Lc 76); fill vs surface 3.61:1 |
| Sticker | pink-500 / pink-300 | `#E845A4` / `#FF8FD0` | decoration only; never status |
| Highlight | amber-400 | `#FCBB00` | highlights, not status |
| Landing surface | cream-50 / cream-100 | `#FAF9FC` / `#F4F1E6` | light theme, marketing only |

**Why the primary button is `#6B52F0`, not Monad purple.** Cream text on `#836EF9` fails WCAG (3.60:1). Ink text on it passes WCAG (5.14:1) but is weak by APCA (Lc 39). The two standards disagree, so a slightly deeper fill that passes both is the right answer. Monad purple stays for marks and strokes. (Both rejected pairs are in the report.)

### Status system (the only place red/orange/green/amber appear)

| State | Colour | Icon | Label (always shown) | Meaning |
|---|---|---|---|---|
| Safe | `#72E4BC` mint | check-in-ring | **Safe** | comfortably within the limit |
| Watch | `#F9C230` amber | eye | **Watch** | getting close; nothing needed yet |
| At risk | `#EA7C31` orange | triangle | **At risk** | add collateral or repay soon |
| Liquidatable | `#C83846` red | octagon | **Liquidatable** | others may repay your debt and take collateral |

**Verified.** The four are separated by at least dE 0.143 (OKLab) under normal vision, protanopia, deuteranopia and tritanopia (previous set: 0.063). Safe and Watch share lightness (both 0.841), so they differ by hue, shape and word; that is why the icon and label are mandatory. Status colour is used for icon and border only (3:1 or better against the surface); the label text is always cream on a tinted chip (12-14:1). The light theme cannot separate the four as well, so **status UI is dark-only in v1.**

### Typography
- **Display:** Baloo 2 (700/800), the rounded face Chog's mint page already uses. Landing and onboarding only.
- **Interface:** Inter (400/500/600).
- **Numbers:** JetBrains Mono with tabular figures, for every amount, address and percentage.
- **Handwriting accent:** Gaegu, only for the Chog bubble (one line, never a label). Optional, drop it if it hurts legibility.
- All four are open-licence Google Fonts. Fluid scale with `clamp()`; body 16-18 px; money figures 28-44 px mono.
- Amounts: 6-decimal USDC shown to 2 decimals with the full value in a tooltip; wallet addresses shortened (`0xA4D1...e9C2`) with a copy button and a full-address screen-reader label.

### Layout system
- 8 px grid; mobile-first; app shell is a bottom tab bar on phones and a left rail from 900 px. Components respond to their container (the Account Card works in a sidebar or full width).
- Cards: 20 px radius, 1 px ink-700 border, no heavy shadows (elevation = lighter surface step).
- Icons: 2 px rounded-stroke line icons, 24 px grid; one set only.

### Motion identity (from the motion skill)
- **Archetype:** Premium for money; Playful accent only on stickers and the Chog bubble.
- **Signature easing:** `cubic-bezier(0.4, 0, 0.2, 1)`. Durations: **150 / 300 / 500 ms.** One entrance pattern: rise 12 px and fade, hero first, total stagger under 400 ms.
- **Vault Door (500 ms):** two door halves slide shut over the card, the stamp pulses once. Success only.
- **Borrow/repay confirmed:** one scale pop (1.0 to 1.04 to 1.0) plus a tick draw; the number counts up in 300 ms.
- **Warning/danger:** a firm 300 ms horizontal shake, no overshoot, plus chip text. Never motion alone.
- **Pending:** determinate steps ("1 of 2: approve USDC") with the dot travelling the Health Ring; Monad's speculative finality means we show **Submitted, then Confirmed, then Final** as three distinct states.
- **Reduced motion:** fades only, no shake, no count-up, no door slide (a static closed-door state), no ambient loops. No parallax and no flashing anywhere.

**Motion moments (live demos on brand board 7).** Vault Door 500 ms; health dot 300 ms; Confirmed pop plus tick draw 300 ms; number change (only changed digits roll) 300 ms; button press under 100 ms with a 200 ms settle, firing on release; Safe-to-Watch chip swap 300 ms; error shake 3 x 9 px in 300 ms with the message staying; the **Pause Drill** (Borrow locks while Repay does not move) 300 ms; transaction steps that fill only when the state is truly reached; skeleton loading 1.4 s shimmer after 100 ms; screen entrance 300 ms per item, 60 ms apart, under 400 ms total; the Chog bubble (250 ms, the only overshoot, 4%); an optional once-ever tear-off of the Slip's stub on the first borrow; and the landing hero (entrance under 500 ms, then a 6 px, 6 s card float as the only ambient loop). Each has a reduced-motion form.

### Sound and haptics

One sonic idea: **a stamp**. Sounds are warm sine and triangle tones, quiet (peak about 14 dB below full scale), none longer than 400 ms, two notes at most for a confirmation. Nothing is an alarm, and nothing is the only signal: every sound and buzz repeats something already visible and available as text to screen readers.

| Moment | Heard (if sound is on) | Felt (ms on, off, on) |
|---|---|---|
| Chog goes in the vault | soft low thunk, 160 ms | 25 |
| Submitted | nothing, on purpose | 8 |
| Confirmed | two rising notes, about 250 ms | 15, 40, 15 |
| Final | one quiet ping, 140 ms | 12 |
| Repaid, debt-free | three-note rise, about 300 ms | 10, 30, 10, 30, 20 |
| Error | two soft falling notes, 250 ms | 30, 50, 30 |
| At risk (risk sounds on) | two low pulses, 270 ms | 20, 60, 20 |
| Liquidatable (risk sounds on) | three low pulses, once | 40, 60, 40, 60, 40 |
| Prices paused | two soft falling notes | 10 |
| Chog bubble | tiny bloop, 80 ms | none |

**Defaults and controls.**
- **Sound is off by default.** It is offered once, in one sentence ("Want tiny sounds?"), after the first confirmed transaction. Never on page load, never a modal, never autoplay.
- **Risk-alert sounds are a separate switch, also off.** Even when on, they play once and never repeat.
- **Haptics are on where supported, and off when the device asks for reduced motion.** Maximum 250 ms in total, only on confirmations, errors and warnings, never on taps in lists.
- Each is a plain setting with a clear label, kept per device.
- Borrowing is not celebrated: Confirmed is a neutral two-note chime. The bright three-note rise is reserved for being debt-free.

**Honest limits.** The browser Vibration API works on Android Chrome but not on iPhone Safari or desktop, so there the pattern is only shown, not felt. A wrapped native app could use the system's success, warning and error haptics instead; that has not been tested. The demo sounds are synthesised in the browser as a specification; production sounds are short audio files (a few KB each), loudness-checked.

### Data visualisation
- The **Health Ring** is the hero chart: 270 degrees, ticks at the Watch / At risk / Liquidatable thresholds, the dot shows today. Always paired with the number and the label.
- Collateral vs debt: a single stacked bar with a threshold marker; never a pie.
- Interest/utilisation: line charts with 2 px lines, direct labels, and a data-table fallback for screen readers. Chart elements get borders because three colours cannot all hold 3:1 against each other.

---

## F. Mascot Concept

**The mascot is the Chog the user owns.** We introduce no new character. The collection is the character system, and the brand's job is to frame it.

**Three components that never touch the art:**
1. **Chog Frame.** A 2 px purple border around the artwork, plus the token id in mono. The art inside is unaltered.
2. **Chog Bubble.** A one-line handwritten speech bubble beside the card that reads the account state in text. The ring and chip repeat it, so nothing depends on the bubble alone.
3. **Chog Stickers.** Flat pink and amber props (a coin, a padlock, sparkles, a tiny key) that sit around the frame, never on the face. They are props, not a character.

**Expressions as state (bubble copy, not new art).**

| Moment | Bubble | Prop | Motion |
|---|---|---|---|
| Browsing | "Hm, what's in here?" | key | none |
| Reviewing a credit offer | "Let's check the numbers." | none | none |
| Borrow confirmed | "Done. Don't spend it all at once." | coin | one pop |
| Repaid | "Debt-free. Look at you." | sparkles | one pop |
| Health: Watch | "Keep an eye on me." | none | none |
| Health: At risk | "I'd add some collateral." | padlock | gentle |
| Oracle paused | "Prices are napping. Repay still works." | none | none |

**Honesty rule.** These are interface expressions. The Chog's mood never implies that a particular Chog is more creditworthy, and the bubble never gives financial advice beyond the neutral prompts above.

**Where it appears.** Account Card, empty states, success screens, social cards, the pitch deck. In the deck and socials the Chog appears **only as official art** (supplied by the team) inside the Frame.

**IP rule.** Until the Chog team confirms in writing how we may use the art and wordmark, ship every screen with the neutral frame (silhouette outline plus token id). Do not generate a Chog lookalike with an image model, ever.

---

## G. Product UX Flow

### The nine required screens (from the PRD) and their one job
1. **Pick your Chog:** your Chogs from the allowlisted collection, with provenance (collection address, network, "test collection" if mock).
2. **Account overview (the Account Card):** art, token id, state ("In vault" with the door closed), then three numbers: *Assets in vault*, *You owe*, *You can borrow*, and the Health Ring.
3. **Collateral detail:** each accepted asset with amount, value, price source, freshness ("updated 12 s ago"), how much counts toward your limit, and how to take it out. For a Uniswap position: range bar, the oracle-vs-pool price gap, and "fees are not counted".
4. **Credit preview:** the amount slider, rate, pool cash available, *health after*, and the sentence "Your Chog stays in the vault while you owe."
5. **Borrow / Repay:** one action per screen, exact figures on the button ("Borrow 500 USDC"), then Submitted / Confirmed / Final, with the hash.
6. **Market use:** deferred (no approved destinations yet); the screen says so instead of faking it.
7. **Activity:** a real table (captioned, with headers) of contract events with hashes and block times.
8. **Transfer / Sell with Vault:** debt-free package sale; and the debt-bearing version (below).
9. **Risk & terms:** liquidation explained in four sentences, eligibility, pool liquidity limits, mock/testnet status, "no audit yet".

### Journey (first session)
1. **Connect.** One button. If the wallet is on the wrong network: "Switch to Monad Testnet" with one tap.
2. **Pick a Chog.** Empty state if none: "No Chog in this wallet. Chog Credit works with Chog Genesis. [Get one on OpenSea]".
3. **Open its Vault.** "This creates a vault for Chog #123. It costs one transaction." Preview, then sign.
4. **Escrow the Chog.** Vault Door closes. Copy: "Chog #123 is now in its vault. It stays there while the vault holds assets or you owe money."
5. **Add assets.** Approve, then deposit, shown as steps ("1 of 2").
6. **See your limit.** The Health Ring appears with *You can borrow 340 USDC*.
7. **Borrow.** Preview, sign, confirmed pop. The USDC lands in your wallet, and the screen says so.
8. **Come back.** Health, interest and repay are on the first screen.

### Microcopy rules (from the plain-language and UX-writing skills)
- Buttons name the action and the amount: "Borrow 500 USDC", "Repay all (512.40 USDC)", "Add WMON".
- Say "borrow USDC from the pool". Never "mint". Never "risk-free", "guaranteed", or "your floor price is your limit".
- Sentences under 20 words; jargon defined inline once ("Health: how far you are from being liquidated").
- Every non-live number wears a label: `TESTNET`, `MOCK ORACLE`, `SAMPLE`.

### Errors (what happened / why / what now)
- Oracle down: "Prices are paused, so borrowing is off. Repaying and adding assets still work."
- Over the limit: "That's 12 USDC over your limit. The most you can borrow is 340 USDC. [Use 340]"
- Wrong network: "You're on Ethereum. Chog Credit runs on Monad Testnet. [Switch network]"
- Rejected in wallet: "You cancelled it in your wallet. Nothing was sent."
- Transaction reverted: show the decoded reason in words and the hash; keep every field filled in.
- Never auto-dismiss an error; never clear what the user typed.

### Empty and success states
- No assets yet: "Your vault is empty. Add WMON or a Uniswap position to get a credit line."
- No debt: "You owe nothing. Your Chog can leave its vault whenever the vault is empty."
- Repaid: "Debt-free." Chog bubble and sparkles, one pop, then the next useful action.

### Debt-bearing sale (a screen of its own, because the stakes are higher)
- Headline: **"Sell this Chog with its loan."** Equity in large type (assets minus debt), then the three lines a buyer signs, in plain words: *at most* X debt, *at least* Y of assets, *health at least* Z.
- The buyer sees: "You will take over a loan of X USDC. If the price falls enough, others can repay it and take assets from this vault." plus the optional payoff.
- The seller sees what they'll receive, and that a price move before execution can cancel the sale.

### Judge demo (3 minutes, scripted; real testnet transactions, mock assets labelled)
1. (20 s) Connect, pick Chog, the vault opens, the door closes.
2. (40 s) Deposit WMON; the ring appears; borrow 300 USDC; confirmed pop.
3. (30 s) Open a Uniswap position as collateral; show the oracle-vs-pool gap.
4. (40 s) **Pause Drill:** turn the mock oracle off. Borrow locks, Repay stays green.
5. (40 s) Price drop: Health goes Safe, Watch, At risk; a second wallet liquidates; the Chog is never touched.
6. (30 s) **Sell this Chog with its loan:** equity, bounds, signed, atomic.
Fallback if the chain is slow: the same script on a local fork, labelled as such.

---

## H. Landing Page Direction

**Structure (mobile-first, one scroll).**
1. **Hero.** Headline *Put your Chog to work.* Sub: *A vault and a credit line for your Chog Genesis NFT.* The live Account Card (testnet numbers, labelled) beside two buttons: **Open a vault** and **See how it works**. Cream background, violet ink text, pink sticker in the corner.
2. **How it works (3 steps).** Pick a Chog, add assets, borrow USDC. Each step a small animation with a caption.
3. **Your Chog is the key, not the collateral.** The honesty section: it stays in the vault; lenders can't take it; only vault assets back the loan.
4. **What's in the vault.** WMON and Uniswap positions, with the real limits.
5. **Sell the whole thing.** The package-sale idea, one diagram.
6. **Safety you can see.** Fail-closed prices, the Pause Drill clip, test counts and the mainnet-fork evidence (linked to `docs/evidence/`), and the plain statement: *testnet, mock assets, not audited*.
7. **FAQ and terms.** Plain language, including liquidation.
8. **Footer.** Official Chog attribution, links, the network and contract addresses.

**Background.** Cream with a very soft violet gradient, a faint dotted "ledger paper" grid, and two or three pink and amber stickers. No video, no parallax.

**Cards.** Ink-900 cards on cream for numbers; cream cards for explanations. Cards rise 12 px and fade in, staggered under 400 ms; under reduced motion they just appear.

**Buttons.** Primary: `#6B52F0` fill, cream text, 56 px high, 14 px radius. Secondary: transparent with a 2 px purple border. Destructive actions are never next to the primary action.

**Responsive.** Fluid type; the hero card stacks under the headline below 700 px; tap targets 44 px or larger; test by dragging from 280 to 2560 px; use `svh`, not `100vh`; safe-area insets; 16 px minimum input font so iOS doesn't zoom.

---

## I. Pitch Deck Visual Direction

**Rubric to design for (Chogathon, from the public page).** Novelty 30%, Fun 20%, Retention 20%, Clarity 15%, $CHOG bonus (optional). Requirement: the Chog NFT must be essential. Prizes are for 50 winners.

**Answering "is the Chog essential?"** Yes, structurally: no Chog, no vault. The Chog is the account's identity, its key, and the handle by which the whole package is sold.

**Slide by slide (ten slides, dark ink background, one idea each).**
1. **Title.** "Chog Credit. Put your Chog to work." Real Chog art in the Frame, the Slip logo.
2. **The problem.** A Chog is a picture. It has an identity but no financial life. One sentence, one image.
3. **The idea.** "Your Chog has a vault now." The Account Card, animated once.
4. **How it works.** Vault, credit line, health, in three icons.
5. **Why it's novel (30%).** The Chog is the key and the sale handle. The package (Chog + vault + debt) is the new primitive. Diagram, no bullets.
6. **Watch it work (Fun, 20%).** The demo screenshot strip: door, ring, pop.
7. **Why people come back (Retention, 20%).** Health to watch, interest to see, positions to manage. Be honest that notifications and a weekly report are roadmap, not built.
8. **Clarity (15%).** "Borrow USDC. Chog stays in the vault, never on the line." One screenshot with annotations.
9. **Proof.** 279 tests, 37 + 21 mutants caught, a real mainnet-fork liquidation, a real debt-bearing sale with real Chog holders. Honest footer: testnet, mock assets, no audit.
10. **The ask / what's next.** Testnet deployment, audit, the marketplace adapter, then mainnet.

**The $CHOG bonus, honestly.** $CHOG cannot be collateral (its pool is too thin). What we did build: a vault can hold $CHOG, worth zero credit, so it travels with the Chog in a package sale (Gate E3). That is a small, honest integration; do not present it as more. A fee discount paid in $CHOG is not built.

**Final wow moment.** The Pause Drill: the presenter flips the (mock) oracle off live, Borrow greys out, Repay stays green, and the Chog bubble says "Prices are napping. Repay still works." Then flips it back. It shows safety, personality and craft in 10 seconds.

**Visual style.** Dark ink slides, one huge number or one huge Account Card per slide, cream text, pink stickers in a single corner, mono numerals. Maximum 20 words per slide. No stock photography, no gradient soup.

---

## J. Image Generation Prompts

**Hard constraints for every prompt.** Do **not** depict Chog or any creature, and do not imitate Chog's art. Official Chog art is composited in afterwards by us. Output is for backgrounds, textures and props only. Always say: "no text, no logos, no characters, no faces".

1. **Landing background (cream).**
   *"Soft cream paper background (#F4F1E6) with a very faint dotted ledger grid, a subtle violet gradient glow (#836EF9 at 8% opacity) in the top right corner, large empty space on the left for a headline, flat vector style, no text, no logos, no characters, no faces."*
2. **App background (dark).**
   *"Deep violet-black background (#0E0B1A) with a barely visible radial glow (#2D2556) behind the centre, extremely subtle fine grain, empty space, no text, no logos, no characters."*
3. **Vault door sprite (two halves, for the escrow animation).**
   *"Flat vector vault door cut vertically in two halves on a transparent background, rounded corners, violet (#46188D to #836EF9) with cream (#F4F1E6) bolts and a small pink (#E845A4) dial, thick 2 px outline in #2D2556, side view, clean shapes, no text, no characters."*
4. **Sticker set (props only).**
   *"A sheet of flat vector sticker props on a transparent background: a coin, a padlock, a small key, sparkles, a lightning spark. Colours limited to pink #E845A4, amber #FCBB00, cream #F4F1E6 and violet #836EF9. Thick rounded outlines, slight offset shadow, playful but clean. No text, no characters, no faces."*
5. **Social card background (1200x630).**
   *"Dark violet-ink (#141026) background with a large soft violet glow on the right half, thin pink diagonal accent line, wide empty area on the left, crisp vector style, no text, no logos, no characters."*
6. **Empty-state illustration (empty vault).**
   *"An empty open vault box, front view, flat vector, violet and cream, cobweb-free, friendly, a single pink sparkle inside, plain transparent background, no characters, no text."*
7. **Pitch-deck section divider.**
   *"Minimal abstract composition: a large thick C-shaped ring (violet #836EF9) with a pink dot in its gap on a deep ink background, generous empty space, flat vector, no text."*

**Figma prompt.** *"Create a Figma file 'Chog Credit' with local variables for the tokens in BRAND_PASS section E, light/dark modes only for the landing page, a component 'Account Card' (Chog Frame, token id, three metrics, Health Ring, status chip) with variants Safe/Watch/At risk/Liquidatable/Paused, and frames for the nine screens at 390 and 1440 px, 8 px grid."*

**Landing-page prompt (for a coding agent).** *"Build a mobile-first landing page from BRAND_PASS section H using the tokens in section E. Semantic HTML, visible focus, prefers-reduced-motion support, container queries for the Account Card, no 100vh, fonts Baloo 2 / Inter / JetBrains Mono, copy exactly as given, every non-live number labelled TESTNET."*

**Deck prompt.** *"Make a 10-slide dark deck from section I: one idea per slide, max 20 words, cream text on #141026, official Chog art inside the Chog Frame, mono numerals, pink sticker in one corner."*

**Icons and app icon.** The Slip and Pixel Key are already drawn as SVG on the brand board (section 6), and the Full Stop is plain text; export launcher sets for the Slip with the icon-generator skill.

---

## K. Final Creative Recommendation

**Do this.**
1. **Brand it as "Your Chog has a vault now."** Hook, headline, social, and the opening of the pitch.
2. **Build the Account Card first.** It is the identity, the demo, the landing hero and the deck cover. If the time is short, build only this and the borrow flow.
3. **Make the Pause Drill the wow moment.** It is distinctive and honest.
4. **Two registers, one seam.** Chaos in the wrapper, ledger in the numbers. Never let the playful style touch a balance.
5. **Dark-only app, cream landing.** Verified status colours need the dark theme.

**Say this out loud, always.** Testnet. Mock assets. Mock oracle. Not audited. The Chog is the key, not the collateral.

**Weak spots, called out.**
- Without cleared Chog art the product looks anonymous. This is the first thing to resolve.
- A Chog's floor is small. If anyone reads "credit against your NFT", they'll expect more than we offer. Our copy must keep saying the value is the vault.
- Retention is our thinnest rubric item. Health watching and interest are real reasons to return, but alerts and a weekly report are not built, and I'd rather say so than invent streaks. Gamifying debt is a trap.
- The `$CHOG` bonus is not claimed.
- Fonts and the marks are my proposals, not Chog's official assets.

**Decisions I need from you.**
1. ~~Logo direction~~ Decided: the Slip (A) for the brand, the Full Stop (D) in the top bar, the Pixel Key (B) as a prop.
2. Approve dark-only for the app and cream for the landing page?
3. Baloo 2 plus Inter plus JetBrains Mono, with Gaegu only for the bubble: yes?
4. Who contacts the Chog team about art and wordmark permission?

**Next steps once you approve.**
1. Write `DESIGN.md` (tokens and component rules in the Google Labs format) and the screen-by-screen user-flow diagrams with Mermaid.
2. Low-fidelity wireframes of the nine screens plus the sale and Pause Drill flows, to test the flow before any styling.
3. Then, and only then, build the app.
