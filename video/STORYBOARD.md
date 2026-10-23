# Chog Credit demo film: storyboard (90 s)

**Reference:** IBM Think kinetic typography (typewriter with a caret, echoing text stacks, line-art circles and grids, hard cuts between flat colour fields). Colours are Chog Credit's own: cream, ink, violet, and one pink square.

**Footage** is the real app, recorded by `app/e2e/footage.mjs` against a fresh local chain running the same contracts as testnet. Waits are sped up by `video/clips.mjs`. Taps stay in real time with a pink pixel cursor and a violet ripple.

**Sound:** local Kokoro voiceover (`hyperframes tts`), a synthesized D minor ambient pad as the bed, bundled effects (whoosh on cuts, soft ticks on typing, pops on badges, one riser into the closing mark). Stereo.

**Subtitles:** English word-by-word karaoke, plus an animated translation line per scene (ES, PT, FR, JA).

| # | Time | Scene | Look | Voiceover |
| --- | --- | --- | --- | --- |
| 1 | 0:00 | Hook | Cream. Typewriter headline, line-art rings, echo trail, wipe to violet. | What if your Chog could do more than sit in a wallet? What if it worked for you? |
| 2 | 0:08 | The key | Ink. Pixel Key, strike through "collateral", "Never priced. Never taken.", vault drawn in line art, coin drops. | Meet Chog Credit. Your Chog becomes the key to a vault. Not the collateral. It is never priced. It is never taken. The vault is where the money lives. |
| 3 | 0:20 | Pick, open, add | Cream with phone. Real footage of opening a vault and adding WMON. | Pick your Chog. Open its vault. The Chog moves in for safekeeping. Then add assets, like WMON, and watch your borrowing power appear. |
| 4 | 0:38 | Borrow | Ink with phone. Count-up to $300.00, Safe chip, exact numbers. | Borrow USDC against what is inside. You see exactly what you owe, what you can still borrow, and how safe you are, in plain words. No jargon. |
| 5 | 0:50 | Sell with the loan | Cream with phone. Handshake diagram: offer link, signed link. | Want out? Sell the whole account, loan and all. The buyer takes over the debt and gets the Chog. Two signatures. Two links. No server. |
| 6 | 1:01 | Get paid, lend | Violet with phone. QR assembling, Receive screen. | Get paid straight to your Chog, with a link or a QR code. Or lend USDC to the pool, and earn. |
| 7 | 1:09 | Pause Drill, limits | Ink with phone. Padlock closes, Repay stays, the real numbers. | When prices pause, borrowing locks, and repaying never does. Limits follow measured Monad liquidity, and every number is on screen. |
| 8 | 1:21 | Close | Cream. Wordmark with the pink full stop, URL typed in. | Chog Credit. Live on Monad testnet. Look around first, no wallet needed. |

Rebuild: `node app/e2e/footage.mjs` (after `app/e2e/reset.sh`), `node video/clips.mjs`, `cd video/demo && node build.mjs && npx hyperframes render -o renders/chog-credit-demo.mp4`.

Generated assets (not committed, about 25 MB): `video/demo/assets/` holds the voiceover WAVs (`npx hyperframes tts "<line>" -o assets/vo/sN.wav -v am_adam -s 0.98`, then `npx hyperframes transcribe` for word timings), the ambient bed and trimmed effects (ffmpeg, from the bundled `media-use` effects), the Baloo 2 and Gaegu fonts from Google Fonts, and `gsap.min.js`. The script lines are in the table above.
