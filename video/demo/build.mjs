// Generates index.html and compositions/*.html for the Chog Credit demo film (90 s, 1920x1080).
// Run: node build.mjs   (from video/demo). Script, translations, timings and layout live in this file.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const W = 1920, H = 1080;
// Scene slots: [id, start, duration, background]. s3 to s7 are the real app in a large window.
const SC = [
  ['s1', 0, 5.5, 'cream'], ['s2', 5.5, 9.5, 'ink'], ['s3', 15, 18.5, 'ink'], ['s4', 33.5, 12, 'ink'],
  ['s5', 45.5, 13, 'ink'], ['s6', 58.5, 8, 'violet'], ['s7', 66.5, 14, 'ink'], ['s8', 80.5, 9.5, 'cream'],
];
const FOOTAGE = new Set(['s3', 's4', 's5', 's6', 's7']);
const VO_AT = { s1: 0.3, s2: 0.25, s3: 0.4, s4: 0.4, s5: 0.4, s6: 0.3, s7: 0.4, s8: 0.5 };
// A scene's voiceover can be split so each half lands on its action: [file, firstWord, endWord, offset in scene, start of the part in the full take].
const VO_PARTS = {
  s3: [['s3a', 0, 12, 2.6, 0], ['s3b', 12, 23, 11.4, 4.38]],
  s7: [['s7a', 0, 9, 8.5, 0], ['s7b', 9, 20, 2.8, 3.93]],
};
const partsOf = (id, n) => VO_PARTS[id] ?? [[id, 0, n, VO_AT[id], 0]];
const LANG = { es: ['ES', 'Español'], pt: ['PT', 'Português'], fr: ['FR', 'Français'], ja: ['JA', '日本語'] };

// Narration, split into caption groups with a translation each. Joined, each scene's groups equal its voiceover text.
const SCRIPT = {
  s1: ['es', [['What if your Chog could do more than sit in a wallet?', '¿Y si tu Chog pudiera hacer más que quedarse en una billetera?'], ['What if it worked for you?', '¿Y si trabajara para ti?']]],
  s2: ['pt', [['Meet Chog Credit.', 'Conheça o Chog Credit.'], ['Your Chog becomes the key to a vault. Not the collateral.', 'Seu Chog vira a chave de um cofre. Não a garantia.'], ['It is never priced. It is never taken.', 'Ele nunca recebe preço. Nunca é tomado.'], ['The vault is where the money lives.', 'O cofre é onde o dinheiro mora.']]],
  s3: ['fr', [['Pick your Chog. Open its vault.', 'Choisissez votre Chog. Ouvrez son coffre.'], ['The Chog moves in for safekeeping.', 'Le Chog y entre, en sécurité.'], ['Then add assets, like WMON,', 'Ajoutez ensuite des actifs, comme du WMON,'], ['and watch your borrowing power appear.', 'et voyez apparaître votre capacité d’emprunt.']]],
  s4: ['ja', [['Borrow USDC against what is inside.', '中身を担保に、USDCを借りられます。'], ['You see exactly what you owe, what you can still borrow,', '返す額も、あと借りられる額も、'], ['and how safe you are, in plain words. No jargon.', 'どれだけ安全かも、やさしい言葉で。専門用語なし。']]],
  s5: ['es', [['Want out?', '¿Quieres salir?'], ['Sell the whole account, loan and all.', 'Vende toda la cuenta, con el préstamo incluido.'], ['The buyer takes over the debt and gets the Chog.', 'El comprador asume la deuda y recibe el Chog.'], ['Two signatures. Two links. No server.', 'Dos firmas. Dos enlaces. Sin servidor.']]],
  s6: ['pt', [['Get paid straight to your Chog, with a link or a QR code.', 'Receba direto no seu Chog, com um link ou um QR code.'], ['Or lend USDC to the pool, and earn.', 'Ou empreste USDC ao pool e ganhe.']]],
  s7: ['fr', [['When prices pause, borrowing locks, and repaying never does.', 'Quand les prix se figent, l’emprunt se bloque, le remboursement jamais.'], ['Limits follow measured Monad liquidity,', 'Les limites suivent la liquidité mesurée de Monad,'], ['and every number is on screen.', 'et chaque chiffre est à l’écran.']]],
  s8: ['ja', [['Chog Credit.', 'Chog Credit。'], ['Live on Monad testnet.', 'Monadテストネットで公開中。'], ['Look around first, no wallet needed.', 'まず見て回れます。ウォレットは不要です。']]],
};

// Per-word start/end seconds (local to the voiceover file). Whisper's words when the count matches the script, else spread by length.
function wordTimes(key, words) {
  const raw = JSON.parse(readFileSync(`assets/vo/${key}.words.json`, 'utf8'));
  const tw = (Array.isArray(raw) ? raw : raw.words).filter((w) => /\w/.test(w.text));
  if (tw.length === words.length) return words.map((_, i) => [tw[i].start, tw[i].end]);
  const a = tw[0].start, b = tw[tw.length - 1].end, total = words.reduce((n, w) => n + w.length + 2, 0);
  let t = a; return words.map((w) => { const d = ((w.length + 2) / total) * (b - a); const r = [t, t + d]; t += d; return r; });
}

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
const FONTS = `
@font-face{font-family:'Baloo 2';font-weight:800;src:url('assets/fonts/Baloo2-800.ttf')}
@font-face{font-family:'Gaegu';font-weight:700;src:url('assets/fonts/Gaegu-700.ttf')}`;
const BASE = `
${FONTS}
:root{--cream:#F4F1E6;--cream50:#FAF9FC;--cream200:#E7E2D0;--dot:#D9D3BF;--ink:#141026;--ink950:#0E0B1A;--ink850:#181330;--ink800:#211A40;--ink700:#2D2556;--v500:#836EF9;--v300:#B7AAFF;--v700:#46188D;--pink:#E845A4;--amber:#FCBB00;--safe:#72E4BC;--muted:#575070}
#root{position:absolute;inset:0;overflow:hidden;font-family:'Inter',sans-serif;color:var(--ink)}
#root *{box-sizing:border-box}
.bg-cream{position:absolute;inset:0;background:radial-gradient(ellipse at 85% 0%,rgba(131,110,249,.2),rgba(131,110,249,0) 55%),radial-gradient(var(--dot) 2px,transparent 2px) 0 0/40px 40px,var(--cream)}
.bg-ink{position:absolute;inset:0;background:radial-gradient(ellipse at 15% 100%,rgba(131,110,249,.22),rgba(131,110,249,0) 55%),linear-gradient(rgba(131,110,249,.07) 1px,transparent 1px) 0 0/80px 80px,linear-gradient(90deg,rgba(131,110,249,.07) 1px,transparent 1px) 0 0/80px 80px,var(--ink)}
.bg-violet{position:absolute;inset:0;background:radial-gradient(ellipse at 90% 100%,rgba(232,69,164,.28),rgba(232,69,164,0) 55%),radial-gradient(rgba(250,249,252,.14) 2px,transparent 2px) 0 0/40px 40px,var(--v700)}
.disp{font-family:'Baloo 2',sans-serif;font-weight:800;letter-spacing:-.025em;line-height:.98}
.mono{font-family:'JetBrains Mono',monospace;font-weight:600}
.dark{color:var(--cream50)}
.ch{opacity:0}
.cr{display:inline-block;width:.42em;height:.42em;margin-left:.04em;background:var(--pink);opacity:0;vertical-align:baseline;position:absolute}
.phone{position:absolute;left:1180px;top:84px;width:432px;height:912px;border-radius:64px;background:var(--ink950);box-shadow:0 40px 90px rgba(20,16,38,.4),0 0 0 3px var(--ink700);transform-origin:50% 100%}
.phone .screen{position:absolute;inset:13px;border-radius:52px;overflow:hidden;background:#000}
.phone video{position:absolute;left:0;top:0;width:406px;height:886px;object-fit:cover}
.pill{display:inline-flex;align-items:center;gap:10px;padding:10px 20px;border-radius:12px;font-family:'JetBrains Mono',monospace;font-weight:600;font-size:26px;letter-spacing:.06em;text-transform:uppercase}
.callout{position:absolute;display:flex;align-items:center;gap:14px;font-family:'Gaegu',cursive;font-weight:700;font-size:44px;background:var(--cream50);color:var(--ink);border:3px solid var(--ink);border-radius:26px 26px 26px 6px;padding:8px 26px}
.pix{position:absolute;width:var(--s,18px);height:var(--s,18px);background:var(--pink)}
`;

// Typewriter text: characters are spans revealed one at a time with a pink square caret that follows.
function chars(text, cls = '') {
  return [...text].map((c) => (c === ' ' ? ' ' : `<span class="ch ${cls}">${esc(c)}</span>`)).join('');
}
// returns JS that types `sel .ch` spans between t0 and t1, caret included, plus key ticks flagged by caller
const TYPE_JS = `
function typeIn(tl, sel, t0, t1, caretSel){
  const els = document.querySelectorAll(sel + ' .ch'); const n = els.length; if(!n) return;
  const dt = (t1 - t0) / n;
  els.forEach((e, i) => tl.set(e, { opacity: 1 }, t0 + i * dt));
  if (caretSel) { const c = document.querySelector(caretSel); if (!c) return;
    tl.set(c, { opacity: 1 }, t0); els.forEach((e, i) => { if (i % 3 === 2) tl.set(c, { opacity: (i / 3) % 2 ? 1 : 0.15 }, t0 + i * dt); }); tl.set(c, { opacity: 0 }, t1 + 0.5); }
}
const rise = (tl, sel, t, y = 28, d = 0.45) => tl.fromTo(sel, { opacity: 0, y }, { opacity: 1, y: 0, duration: d, ease: 'power3.out' }, t);
`;

function scene(id, bg, body, js, extraCss = '') {
  const cls = bg === 'ink' ? 'bg-ink' : bg === 'violet' ? 'bg-violet' : 'bg-cream';
  return `<template>
<style>${BASE}${extraCss}</style>
<div id="root" data-composition-id="${id}" data-width="${W}" data-height="${H}">
<div class="${cls}"></div>
${body}
</div>
<script>
const tl = gsap.timeline({ paused: true });
${TYPE_JS}
${js}
window.__timelines["${id}"] = tl;
</script>
</template>
`;
}

const phone = (id, vids, start = 0.4, tilt = 2) => `
<div class="phone" id="${id}-phone"><div class="screen">${vids.map(([n, s, d], i) => `<video id="${id}-v${i}" class="clip" src="assets/footage/${n}.mp4" data-start="${s}" data-duration="${d}" muted playsinline></video>`).join('')}</div></div>`;
const phoneIn = (id, t = 0.2, tilt = 2) => `tl.fromTo('#${id}-phone',{opacity:0,y:140,rotation:${tilt + 5},scale:.96},{opacity:1,y:0,rotation:${tilt},scale:1,duration:.8,ease:'power4.out'},${t});`;
const keySvg = (w = 96) => `<svg viewBox="0 0 96 48" width="${w}" height="${w / 2}" shape-rendering="crispEdges"><g fill="#836EF9"><rect x="0" y="0" width="32" height="8"/><rect x="0" y="8" width="8" height="16"/><rect x="24" y="8" width="8" height="16"/><rect x="0" y="24" width="32" height="8"/><rect x="32" y="8" width="64" height="16"/><rect x="64" y="24" width="8" height="16"/><rect x="88" y="24" width="8" height="24"/></g><rect x="8" y="8" width="16" height="16" fill="#E845A4"/></svg>`;

const scenes = {};

// ---------- S1: the hook (cream, kinetic type) ----------
scenes.s1 = scene('s1', 'cream', `
<div id="s1-l1" class="disp" style="position:absolute;left:140px;top:140px;font-size:150px;white-space:nowrap">${chars('What if your ')}${[...'Chog'].map((c) => `<span class="ch" style="color:var(--v700)">${c}</span>`).join('')}</div>
<div id="s1-l2" class="disp" style="position:absolute;left:140px;top:300px;font-size:150px;white-space:nowrap">${chars('could do more')}</div>
<div id="s1-l3" class="disp" style="position:absolute;left:140px;top:460px;font-size:150px;white-space:nowrap">${chars('than sit in a ')}<span style="position:relative;display:inline-block">${chars('wallet?')}<i id="s1-hl" style="position:absolute;left:-.06em;right:-.06em;bottom:.06em;height:.3em;background:#E845A4;opacity:.35;z-index:-1;transform-origin:0 50%"></i></span></div>
<svg id="s1-rings" viewBox="0 0 700 300" style="position:absolute;left:1180px;top:690px;width:640px;height:274px;overflow:visible" fill="none" stroke="#46188D" stroke-width="2.5">
  <circle cx="40" cy="150" r="26" pathLength="1"/><circle cx="130" cy="150" r="56" pathLength="1"/><circle cx="290" cy="150" r="86" pathLength="1"/><circle cx="520" cy="150" r="118" pathLength="1"/>
  <path d="M0 150H700M40 20V280M130 -10V310M290 -30V330" stroke-width="1.2" opacity=".5" pathLength="1"/></svg>
<div id="s1-panel" style="position:absolute;inset:0;background:var(--v700)"></div>
<div id="s1-l4" class="disp dark" style="position:absolute;left:140px;top:300px;font-size:200px;line-height:1;white-space:nowrap">${chars('What if it')}<br>${chars('worked for ')}<span style="display:inline-block" id="s1-you">${[...'you?'].map((c) => `<span class="ch" style="color:#f9a8d8">${c}</span>`).join('')}</span></div>
`, `
typeIn(tl,'#s1-l1',0.35,1.15);
typeIn(tl,'#s1-l2',1.2,1.85);
typeIn(tl,'#s1-l3',1.9,2.9);
tl.fromTo('#s1-hl',{scaleX:0},{scaleX:1,duration:.3,ease:'power3.out'},2.85);
tl.fromTo('#s1-rings circle',{strokeDasharray:1,strokeDashoffset:1},{strokeDashoffset:0,duration:1.0,ease:'power2.out',stagger:.12},1.2);
tl.fromTo('#s1-rings path',{opacity:0},{opacity:.5,duration:.6},1.4);
tl.fromTo('#s1-panel',{clipPath:'inset(0 100% 0 0)'},{clipPath:'inset(0 0% 0 0)',duration:.42,ease:'power4.inOut'},3.0);
typeIn(tl,'#s1-l4',3.2,4.0);
tl.fromTo('#s1-you',{y:0},{y:-14,duration:.16,ease:'power2.out',yoyo:true,repeat:1},4.05);
`);

// ---------- S2: the key, not the collateral (ink) ----------
scenes.s2 = scene('s2', 'ink', `
<div id="s2-meet" class="disp dark" style="position:absolute;left:140px;top:120px;font-size:96px">${chars('Meet Chog Credit')}<span id="s2-dot" style="display:inline-block;width:.12em;height:.12em;background:var(--pink);margin-left:.04em"></span></div>
<div id="s2-key" style="position:absolute;left:140px;top:330px;transform-origin:0 50%">${keySvg(260)}</div>
<div id="s2-a" class="disp dark" style="position:absolute;left:450px;top:300px;font-size:170px;white-space:nowrap">${chars('The key.')}</div>
<div id="s2-b" class="disp" style="position:absolute;left:140px;top:520px;font-size:130px;white-space:nowrap;color:var(--v300)">${chars('Not the ')}<span style="position:relative;display:inline-block">${chars('collateral.')}<i id="s2-strike" style="position:absolute;left:0;right:0;top:56%;height:12px;background:var(--pink);transform-origin:0 50%"></i></span></div>
<div id="s2-n" style="position:absolute;left:140px;top:250px;opacity:0">
  <div class="disp dark" style="font-size:150px;line-height:1.02"><span id="s2-n1">${chars('Never priced.')}</span></div>
  <div class="disp" style="font-size:150px;line-height:1.02;color:var(--v300)"><span id="s2-n2">${chars('Never taken.')}</span></div></div>
<svg id="s2-vault" viewBox="0 0 520 420" style="position:absolute;left:1220px;top:230px;width:520px;height:420px;opacity:0" fill="none" stroke="#836EF9" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">
  <rect x="30" y="40" width="460" height="340" rx="36" pathLength="1"/><circle cx="260" cy="210" r="96" pathLength="1"/><circle cx="260" cy="210" r="34" fill="#E845A4" stroke="#0E0B1A" pathLength="1"/>
  <path d="M260 114V150M260 270V306M164 210H200M320 210H356" pathLength="1"/><path d="M110 380V410M410 380V410" pathLength="1"/></svg>
<div id="s2-coin" style="position:absolute;left:1410px;top:150px;opacity:0"><svg width="120" height="120" viewBox="0 0 36 36"><circle cx="18" cy="18" r="14" fill="#FCBB00" stroke="#0E0B1A" stroke-width="2"/><path d="M18 11v14M14 14.5h6.5a2.5 2.5 0 010 5H14" fill="none" stroke="#0E0B1A" stroke-width="2.2" stroke-linecap="round"/></svg></div>
`, `
typeIn(tl,'#s2-meet',0.3,1.1);
tl.fromTo('#s2-dot',{scale:0},{scale:1,duration:.3,ease:'back.out(3)'},1.15);
tl.fromTo('#s2-key',{opacity:0,x:-60,rotation:-14,scale:.8},{opacity:1,x:0,rotation:-4,scale:1,duration:.6,ease:'back.out(1.6)'},1.5);
typeIn(tl,'#s2-a',2.0,2.9);
typeIn(tl,'#s2-b',3.6,4.7);
tl.fromTo('#s2-strike',{scaleX:0},{scaleX:1,duration:.35,ease:'power3.out'},4.75);
tl.to(['#s2-meet','#s2-key','#s2-a','#s2-b'],{opacity:0,y:-30,duration:.22,ease:'power2.in'},5.05);
tl.set('#s2-n',{opacity:1},5.25);
typeIn(tl,'#s2-n1',5.3,5.9);
typeIn(tl,'#s2-n2',6.25,6.9);
tl.fromTo('#s2-vault',{opacity:0},{opacity:1,duration:.25},6.9);
tl.fromTo('#s2-vault rect, #s2-vault circle, #s2-vault path',{strokeDasharray:1,strokeDashoffset:1},{strokeDashoffset:0,duration:1.0,ease:'power2.out',stagger:.07},6.9);
tl.fromTo('#s2-coin',{opacity:0,y:-90,scale:.6,rotation:-30},{opacity:1,y:0,scale:1,rotation:8,duration:.55,ease:'back.out(2)'},8.1);
tl.fromTo('#s2-n',{x:0},{x:-20,duration:3,ease:'none'},5.25);
`);

// ---------- The real app, in a large window with a camera that pushes in on what matters ----------
const WX = 160, WY = 92, VW = 1600, VH = 900, BAR = 40;
function camJS(id, keys) {
  // keys: [time, scale, focusX 0..1, focusY 0..1, duration]. The view is translated so the focus sits centred, clamped to the frame.
  return keys.map(([t, s, fx, fy, d], i) => {
    let x = VW / 2 - fx * VW * s, y = VH / 2 - fy * VH * s;
    x = Math.min(0, Math.max(VW - VW * s, x)); y = Math.min(0, Math.max(VH - VH * s, y));
    const to = `{scale:${s},x:${x.toFixed(1)},y:${y.toFixed(1)},duration:${d},ease:'power3.inOut'}`;
    return i === 0 ? `tl.fromTo('#${id}-cam',{scale:${s},x:${x.toFixed(1)},y:${y.toFixed(1)},transformOrigin:'0 0'},{scale:${s},duration:0.01},${t});` : `tl.to('#${id}-cam',${to},${t});`;
  }).join('\n');
}
function walk(id, bg, { vids, chapters, cam, overlays = '', js = '', css = '' }) {
  const body = `
<div class="chap" id="${id}-chap">${chapters.map(([t, n, label], i) => `<div class="chapi" id="${id}-ch${i}"><b>${n}</b><span>${label}</span></div>`).join('')}</div>
<div class="win" id="${id}-win"><div class="bar"><i></i><i></i><i></i><span>Chog Credit · test build</span></div>
  <div class="view"><div class="cam" id="${id}-cam">${vids.map(([n, st, d], i) => `<video id="${id}-v${i}" class="clip" src="assets/footage/${n}.mp4" data-start="${st}" data-duration="${d}" muted playsinline></video>`).join('')}</div><div class="scrim"></div></div></div>
${overlays}`;
  const cjs = `
tl.fromTo('#${id}-win',{scale:.97,y:18},{scale:1,y:0,duration:.5,ease:'power3.out'},0);
${chapters.map(([t], i) => `tl.fromTo('#${id}-ch${i}',{opacity:0,x:-24},{opacity:1,x:0,duration:.35,ease:'power3.out'},${t});` + (chapters[i + 1] ? `tl.to('#${id}-ch${i}',{opacity:0,x:24,duration:.2,ease:'power2.in'},${chapters[i + 1][0] - 0.2});` : '')).join('\n')}
${camJS(id, cam)}
${js}`;
  return scene(id, bg, body, cjs, `
.win{position:absolute;left:${WX}px;top:${WY}px;width:${VW}px;height:${VH + BAR}px;border-radius:22px;overflow:hidden;background:#0E0B1A;box-shadow:0 40px 100px rgba(0,0,0,.45),0 0 0 2px #2D2556}
.bar{position:absolute;left:0;right:0;top:0;height:${BAR}px;display:flex;align-items:center;gap:9px;padding:0 18px;background:#181330;border-bottom:1px solid #2D2556}
.bar i{width:12px;height:12px;border-radius:50%;background:#2D2556}.bar i:first-child{background:#E845A4}
.bar span{margin-left:14px;font-family:'JetBrains Mono',monospace;font-size:16px;color:#9a93c9}
.view{position:absolute;left:0;top:${BAR}px;width:${VW}px;height:${VH}px;overflow:hidden}
.cam{position:absolute;left:0;top:0;width:${VW}px;height:${VH}px}
.cam video{position:absolute;left:0;top:0;width:${VW}px;height:${VH}px;object-fit:cover}
.scrim{position:absolute;left:0;right:0;bottom:0;height:340px;background:linear-gradient(rgba(14,11,26,0),rgba(14,11,26,.96) 62%)}
.chap{position:absolute;left:${WX}px;top:26px;height:50px}
.chapi{position:absolute;left:0;top:0;display:flex;align-items:center;gap:16px;white-space:nowrap;opacity:0}
.chapi b{font-family:'JetBrains Mono',monospace;font-weight:600;font-size:22px;color:#0E0B1A;background:#E845A4;border-radius:6px;padding:4px 10px}
.chapi span{font-family:'Baloo 2';font-weight:800;font-size:40px;color:var(--cream50);letter-spacing:-.01em}
.badge{position:absolute;opacity:0;background:var(--cream50);color:var(--ink);border:3px solid var(--ink);border-radius:22px;padding:14px 26px;box-shadow:0 18px 40px rgba(0,0,0,.35)}
.badge .k{font-family:'JetBrains Mono',monospace;font-weight:600;font-size:20px;letter-spacing:.1em;text-transform:uppercase;color:var(--v700)}
.badge .v{font-family:'JetBrains Mono',monospace;font-weight:600;font-size:56px;line-height:1.05}
.sticky{position:absolute;opacity:0;font-family:'Gaegu',cursive;font-weight:700;font-size:44px;background:var(--cream50);color:var(--ink);border:3px solid var(--ink);border-radius:26px 26px 26px 6px;padding:6px 24px}
${css}`);
}
const pop = (sel, t, rot = -3) => `tl.fromTo('${sel}',{opacity:0,scale:.85,rotation:${rot - 4}},{opacity:1,scale:1,rotation:${rot},duration:.32,ease:'back.out(2.2)'},${t});`;
const out = (sel, t) => `tl.to('${sel}',{opacity:0,y:-10,duration:.2,ease:'power2.in'},${t});`;

// s3: open a vault (d3a content 9.73 s: landing 0, pick 2.2, open 4.0, waiting 6.0, account 7.13), then add WMON (d3b: add page 0, taps 1.3, tracker 4.8, account 6.32)
scenes.s3 = walk('s3', 'ink', {
  vids: [['d3a', 0, 9.73], ['d3b', 9.73, 8.77]],
  chapters: [[0.1, '01', 'Pick a Chog, open its vault'], [9.73, '02', 'Add assets']],
  cam: [[0, 1, .5, .5, 0], [0.4, 1.12, .38, .45, 1.6], [2.2, 1.25, .37, .3, .6], [4.0, 1.25, .37, .55, .6], [7.13, 1.0, .5, .5, .5], [7.6, 1.08, .5, .4, 1.6],
        [9.73, 1, .5, .5, .01], [10.9, 1.4, .3, .25, .6], [14.5, 1.3, .3, .62, .5], [16.05, 1, .5, .5, .5], [16.5, 1.08, .55, .35, 1.6]],
  overlays: `<div id="s3-o1" class="sticky" style="left:1240px;top:170px">The Chog moves in</div>
<div id="s3-o2" class="badge" style="left:1420px;top:128px"><div class="k">You can borrow</div><div class="v">$800.00</div></div>`,
  js: `${pop('#s3-o1', 7.4)}${out('#s3-o1', 9.5)}${pop('#s3-o2', 16.3, 2)}`,
});

// s4: borrow 300 (d4: account 0, form 1.2, wait 6.34, success 6.94, account 10.54)
scenes.s4 = walk('s4', 'ink', {
  vids: [['d4', 0, 12]],
  chapters: [[0.1, '03', 'Borrow USDC']],
  cam: [[0, 1, .5, .5, 0], [1.3, 1.45, .3, .2, .6], [4.6, 1.25, .32, .68, .5], [6.94, 1.4, .3, .28, .6], [10.54, 1, .5, .5, .5], [10.9, 1.08, .55, .35, 1.0]],
  overlays: `<div id="s4-o1" class="badge" style="left:1420px;top:128px"><div class="k">Borrowed</div><div class="v">$<span id="s4-n">0.00</span></div></div>
<div id="s4-o2" class="pill" style="position:absolute;left:1420px;top:300px;background:#22343c;color:var(--safe);opacity:0;font-size:28px"><svg width="30" height="30" viewBox="0 0 20 20"><path d="M10 2l7 3v5c0 4-3 7-7 8-4-1-7-4-7-8V5z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/><path d="M6.5 10l2.5 2.5L13.5 8" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>Safe · health 4.33</div>`,
  js: `${pop('#s4-o1', 7.1, 2)}
const o={v:0}; tl.fromTo(o,{v:0},{v:300,duration:1.2,ease:'power3.out',onUpdate:()=>{document.getElementById('s4-n').textContent=o.v.toFixed(2);}},7.25);
tl.fromTo('#s4-o2',{opacity:0,y:14},{opacity:1,y:0,duration:.3,ease:'power3.out'},8.5);`,
});

// s5: sell with the loan (d5: account 0, form 1.2, link 7.09)
scenes.s5 = walk('s5', 'ink', {
  vids: [['d5', 0, 13]],
  chapters: [[0.1, '04', 'Sell it, loan and all']],
  cam: [[0, 1, .5, .5, 0], [1.4, 1.3, .33, .35, .6], [4.9, 1.3, .33, .62, .5], [7.09, 1.0, .5, .5, .4], [7.6, 1.3, .4, .85, .6]],
  overlays: `<div id="s5-hs" class="hs" style="left:1190px;top:150px">
  <div class="hc" id="s5-c1"><b>Seller</b><span>signs the offer</span></div>
  <svg width="120" height="40" viewBox="0 0 120 40"><path id="s5-l1" d="M4 20H116" stroke="#E845A4" stroke-width="4" stroke-dasharray="10 10" fill="none"/></svg>
  <div class="hc" id="s5-c2"><b>Buyer</b><span>signs back</span></div></div>
<div id="s5-done" class="pill" style="position:absolute;left:1190px;top:330px;background:var(--v700);color:var(--cream50);opacity:0;font-size:24px">Loan, vault and Chog move together</div>`,
  css: `.hs{position:absolute;display:flex;align-items:center;gap:6px}.hc{width:220px;border-radius:18px;background:var(--cream50);color:var(--ink);border:3px solid var(--ink);padding:14px 18px;opacity:0}.hc b{display:block;font-family:'Baloo 2';font-weight:800;font-size:40px;line-height:1}.hc span{font-family:'JetBrains Mono';font-size:18px;color:var(--v700)}`,
  js: `tl.fromTo('#s5-c1',{opacity:0,y:20},{opacity:1,y:0,duration:.35,ease:'power3.out'},2.6);
tl.fromTo('#s5-l1',{strokeDashoffset:120,opacity:0},{strokeDashoffset:0,opacity:1,duration:.8,ease:'power2.out'},3.0);
tl.fromTo('#s5-c2',{opacity:0,y:20},{opacity:1,y:0,duration:.35,ease:'power3.out'},3.5);
tl.fromTo('#s5-done',{opacity:0,y:14},{opacity:1,y:0,duration:.35,ease:'power3.out'},6.1);`,
});

// s6: get paid, then lend (d6: get paid 0, lend 5)
scenes.s6 = walk('s6', 'violet', {
  vids: [['d6', 0, 8]],
  chapters: [[0.1, '05', 'Get paid, or lend and earn']],
  cam: [[0, 1, .5, .5, 0], [0.3, 1.5, .2, .44, .7], [3.0, 1.3, .32, .6, .5], [5.0, 1, .5, .5, .4], [5.5, 1.3, .35, .32, .6]],
  overlays: `<div id="s6-o1" class="sticky" style="left:1250px;top:170px">Pay a Chog, even before its vault exists</div>`,
  css: `#s6-o1{max-width:470px;font-size:40px;line-height:1.05}`,
  js: `${pop('#s6-o1', 1.2)}${out('#s6-o1', 4.8)}`,
});

// s7: Pause Drill and the numbers (d7: account 0, risk 2.4, numbers 3.8, paused account 8.2)
scenes.s7 = walk('s7', 'ink', {
  vids: [['d7', 0, 14]],
  chapters: [[0.1, '06', 'Every number on screen'], [8.2, '07', 'Prices pause. Repay never does.']],
  cam: [[0, 1, .5, .5, 0], [2.6, 1.25, .35, .35, .6], [6.6, 1.35, .35, .4, .6], [8.2, 1, .5, .5, .4], [8.9, 1.32, .62, .5, .7]],
  overlays: `<div id="s7-o1" class="badge" style="left:1300px;top:150px;width:380px"><div class="k">Pool limits</div><div class="v" style="font-size:34px;line-height:1.35">40% to borrow<br>65% to sell off<br>$15,000 cap</div></div>
<div id="s7-o2" class="pill" style="position:absolute;left:1300px;top:150px;background:var(--pink);color:#0E0B1A;opacity:0;font-size:28px"><svg width="28" height="28" viewBox="0 0 36 36"><rect x="7" y="15" width="22" height="16" rx="4" fill="#0E0B1A"/><path d="M12 15v-4a6 6 0 0112 0v4" fill="none" stroke="#0E0B1A" stroke-width="3" stroke-linecap="round"/></svg>Borrow paused · Repay works</div>`,
  js: `${pop('#s7-o1', 4.2, 2)}${out('#s7-o1', 8.0)}tl.fromTo('#s7-o2',{opacity:0,y:14},{opacity:1,y:0,duration:.32,ease:'back.out(2)'},9.4);`,
});

// ---------- S8: close (cream) ----------
scenes.s8 = scene('s8', 'cream', `
<div id="s8-word" class="disp" style="position:absolute;left:0;right:0;top:200px;text-align:center;font-size:260px">Chog Credit<span id="s8-dot" style="display:inline-block;width:.1em;height:.1em;background:var(--pink);margin-left:.04em"></span></div>
<div id="s8-key" style="position:absolute;left:1380px;top:140px">${keySvg(180)}</div>
<div id="s8-sub" class="mono" style="position:absolute;left:0;right:0;top:550px;text-align:center;font-size:36px;letter-spacing:.12em;text-transform:uppercase;color:var(--v700)">Live on Monad testnet</div>
<div id="s8-url" class="mono" style="position:absolute;left:0;right:0;top:630px;text-align:center;font-size:64px;color:var(--ink)">${chars('chog-credit.vercel.app')}</div>
<div id="s8-tag" class="pill" style="position:absolute;left:0;right:0;margin:0 auto;top:750px;width:max-content;background:var(--ink);color:#f9c230">Look around first. No wallet needed.</div>
`, `
tl.fromTo('#s8-word',{opacity:0,y:50,scale:.96},{opacity:1,y:0,scale:1,duration:.6,ease:'power4.out'},.2);
tl.fromTo('#s8-dot',{scale:0},{scale:1,duration:.4,ease:'back.out(3)'},.8);
tl.fromTo('#s8-key',{opacity:0,y:-40,rotation:40},{opacity:1,y:0,rotation:12,duration:.6,ease:'back.out(1.8)'},1.0);
tl.fromTo('#s8-sub',{opacity:0,y:20},{opacity:1,y:0,duration:.4,ease:'power3.out'},1.5);
typeIn(tl,'#s8-url',2.2,3.6);
tl.fromTo('#s8-tag',{opacity:0,y:20},{opacity:1,y:0,duration:.4,ease:'power3.out'},3.5);
tl.fromTo('#s8-word',{scale:1},{scale:1.03,duration:5,ease:'none'},.8);
tl.to('#root',{opacity:0,duration:.7,ease:'power2.in'},8.7);
`);

// ---------- Captions: English karaoke plus an animated translation line ----------
function captionsScene() {
  let html = '', js = `const hide=(sel,t0,t1)=>{tl.to(sel,{opacity:0,duration:.14,ease:'power2.in'},t1-.14);tl.set(sel,{opacity:0,visibility:'hidden'},t1);};\n`;
  let gi = 0;
  for (const [id, start] of SC.map((s) => [s[0], s[1]])) {
    const [lang, groups] = SCRIPT[id]; const dark = SC.find((s) => s[0] === id)[3] !== 'cream'; const inWin = FOOTAGE.has(id);
    const all = groups.flatMap((g) => g[0].split(/\s+/)); const raw = wordTimes(id, all);
    // absolute start/end of every word, through whichever voiceover part carries it
    const abs = raw.map(([a, b], i) => { const pt = partsOf(id, all.length).find(([, f, e]) => i >= f && i < e); const sh = start + pt[3] - pt[4]; return [a + sh, b + sh]; });
    let wi = 0; const gs_ = [];
    groups.forEach(([en, tr]) => { const ws = en.split(/\s+/); gs_.push({ en, tr, ws, i0: wi, gs: abs[wi][0], end: abs[wi + ws.length - 1][1] }); wi += ws.length; });
    gs_.sort((x, y) => x.gs - y.gs);
    gs_.forEach((g, k) => {
      const nx = gs_[k + 1]; let ge = g.end + (nx ? 0.35 : 0.8); if (nx) ge = Math.min(ge, nx.gs - 0.08);
      const gid = `cap${gi++}`; const jp = lang === 'ja';
      html += `<div id="${gid}" class="capg ${dark ? 'dk' : 'lt'}${inWin ? ' fw' : ''}" style="opacity:0;visibility:hidden"><div class="en">${g.ws.map((w, j) => `<span id="${gid}w${j}" class="w">${esc(w)}</span>`).join(' ')}</div><div class="tr${jp ? ' jp' : ''}"><span class="tag">${LANG[lang][0]}</span><span id="${gid}t" class="tx">${esc(g.tr)}</span></div></div>\n`;
      js += `tl.fromTo('#${gid}',{opacity:0,y:18,visibility:'visible'},{opacity:1,y:0,duration:.22,ease:'power3.out'},${(g.gs - 0.05).toFixed(3)});\n`;
      g.ws.forEach((w, j) => { js += `tl.fromTo('#${gid}w${j}',{color:'${dark ? '#B9B1D6' : '#7a7391'}'},{color:'${dark ? '#FAF9FC' : '#141026'}',duration:.12},${abs[g.i0 + j][0].toFixed(3)});\n`; });
      js += `tl.fromTo('#${gid}t',{clipPath:'inset(0 100% 0 0)'},{clipPath:'inset(0 0% 0 0)',duration:${Math.max(0.5, Math.min(1.4, (g.end - g.gs) * 0.7)).toFixed(2)},ease:'power2.out'},${(g.gs + 0.1).toFixed(3)});\n`;
      js += `hide('#${gid}',${g.gs.toFixed(3)},${ge.toFixed(3)});\n`;
    });
  }
  return `<template>
<style>
${FONTS}
#root{position:absolute;inset:0;font-family:'Inter',sans-serif}
.capg{position:absolute;left:140px;bottom:92px;width:1100px;display:flex;flex-direction:column;gap:10px}
.capg.fw{left:210px;bottom:84px}
.capg .en{font-size:52px;font-weight:600;line-height:1.18;letter-spacing:-.01em}
.capg.lt .en{text-shadow:0 0 0 transparent}
.capg .tr{display:flex;align-items:flex-start;gap:14px;font-size:34px;font-weight:500;color:var(--c);}
.capg.lt .tr{--c:#46188D}.capg.dk .tr{--c:#B7AAFF}
.capg .tag{margin-top:5px;font-family:'JetBrains Mono',monospace;font-weight:600;font-size:20px;letter-spacing:.08em;padding:4px 10px;border-radius:6px;background:#E845A4;color:#0E0B1A}
.capg .jp{font-family:'Noto Sans JP','Inter',sans-serif}
.capg .tx{display:block;max-width:900px;line-height:1.3}
.w{display:inline-block}
</style>
<div id="root" data-composition-id="captions" data-width="${W}" data-height="${H}">
${html}</div>
<script>
const tl = gsap.timeline({ paused: true });
${js}
window.__timelines["captions"] = tl;
</script>
</template>
`;
}

// ---------- Root ----------
mkdirSync('compositions', { recursive: true });
for (const [id, html] of Object.entries(scenes)) writeFileSync(`compositions/${id}.html`, html);
writeFileSync('compositions/captions.html', captionsScene());

const dur = (id) => JSON.parse(execDur(id));
function execDur(id) { return String(readWavDuration(`assets/vo/${id}.wav`)); }
function readWavDuration(p) { const b = readFileSync(p); const rate = b.readUInt32LE(24), ch = b.readUInt16LE(22), bits = b.readUInt16LE(34); let off = 12, dataLen = 0; while (off < b.length - 8) { const tag = b.toString('ascii', off, off + 4), len = b.readUInt32LE(off + 4); if (tag === 'data') { dataLen = len; break; } off += 8 + len; } return dataLen / (rate * ch * (bits / 8)); }

const hosts = SC.map(([id, s, d]) => `<div id="${id}" data-composition-id="${id}" data-composition-src="compositions/${id}.html" data-start="${s}" data-duration="${d}" data-track-index="1" data-track-kind="graphics" data-width="${W}" data-height="${H}"></div>`).join('\n  ');
const vo = SC.flatMap(([id, s]) => partsOf(id, 0).map(([f, , , off]) => { const d = readWavDuration(`assets/vo/${f}.wav`); return `<audio id="vo-${f}" src="assets/vo/${f}.wav" data-start="${(s + off).toFixed(2)}" data-duration="${(d + 0.05).toFixed(2)}" data-volume="1" data-track-index="5"></audio>`; })).join('\n  ');
// cuts get a whoosh; the typed lines get keys; badges pop; one riser into the closing mark
const SFX = [
  ...SC.slice(1).map(([id, s], i) => [`whoosh${i}`, 'whoosh', s - 0.15, 0.5]),
  ['tick1', 'tick', 0.35, 0.45], ['tick2', 'tick', 1.2, 0.35], ['tick3', 'tick', 1.9, 0.35], ['tick4', 'tick', 3.2, 0.45],
  ['tick5', 'tick', 5.8, 0.4], ['pop1', 'pop', 7.0, 0.5], ['tick6', 'tick', 7.5, 0.35], ['pop2', 'pop', 10.25, 0.5], ['tick7', 'tick', 10.8, 0.35], ['pop3', 'pop', 13.6, 0.55],
  ['pop4', 'pop', 22.5, 0.45], ['pop5', 'pop', 31.5, 0.55], ['pop6', 'pop', 40.6, 0.55], ['pop7', 'pop', 42.0, 0.4],
  ['pop8', 'pop', 48.1, 0.4], ['pop9', 'pop', 49.0, 0.4], ['pop10', 'pop', 51.6, 0.45], ['pop11', 'pop', 59.7, 0.45],
  ['pop12', 'pop', 70.7, 0.45], ['pop13', 'pop', 75.9, 0.5], ['riser', 'riser', 77.7, 0.6], ['pop14', 'pop', 81.3, 0.6], ['tick8', 'tick', 82.7, 0.35],
];
const SD = { click: 0.37, whoosh: 1.3, pop: 0.72, tick: 0.9, riser: 3.2 };
const sfx = SFX.map(([id, f, t, v], i) => `<audio id="sfx-${id}" src="assets/sfx/${f}.wav" data-start="${t.toFixed(2)}" data-duration="${SD[f]}" data-volume="${v}" data-track-index="${10 + i}"></audio>`).join('\n  ');

writeFileSync('index.html', `<!doctype html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=${W}, height=${H}">
<script src="assets/gsap.min.js"></script>
<style>
*{margin:0;padding:0;box-sizing:border-box}
html,body{margin:0;width:${W}px;height:${H}px;overflow:hidden;background:#141026}
</style>
</head>
<body>
<div id="root" data-composition-id="main" data-start="0" data-duration="90" data-width="${W}" data-height="${H}">
  ${hosts}
  <div id="captions" data-composition-id="captions" data-composition-src="compositions/captions.html" data-start="0" data-duration="90" data-track-index="2" data-track-kind="captions" data-width="${W}" data-height="${H}"></div>
  <audio id="bed" src="assets/sfx/bed.wav" data-start="0" data-duration="90" data-volume="0.9" data-fade-in="2" data-fade-out="3" data-track-index="4"></audio>
  ${vo}
  ${sfx}
</div>
<script>
const tl = gsap.timeline({ paused: true });
window.__timelines["main"] = tl;
tl.seek(0);
</script>
</body>
</html>
`);
console.log('built', Object.keys(scenes).length, 'scenes + captions');
