// Generates index.html and compositions/*.html for the Chog Credit demo film (90 s, 1920x1080).
// Run: node build.mjs   (from video/demo). Script, translations, timings and layout live in this file.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const W = 1920, H = 1080;
// Scene slots: [id, start, duration, background]
const SC = [
  ['s1', 0, 8, 'cream'], ['s2', 8, 12, 'ink'], ['s3', 20, 18, 'cream'], ['s4', 38, 12, 'ink'],
  ['s5', 50, 11.5, 'cream'], ['s6', 61.5, 8, 'violet'], ['s7', 69.5, 11.5, 'ink'], ['s8', 81, 9, 'cream'],
];
const VO_AT = { s1: 0.35, s2: 0.6, s3: 0.5, s4: 0.5, s5: 0.4, s6: 0.4, s7: 0.4, s8: 0.5 };
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
<div id="s1-l1" class="disp" style="position:absolute;left:140px;top:150px;font-size:150px;white-space:nowrap">${chars('What if your ')}<span class="ch" style="color:var(--v700)">${[...'Chog'].map((c) => `<span class="ch" style="color:var(--v700)">${c}</span>`).join('')}</span></div>
<div id="s1-l2" class="disp" style="position:absolute;left:140px;top:320px;font-size:150px;white-space:nowrap">${chars('could do more')}</div>
<div id="s1-l3" class="disp" style="position:absolute;left:140px;top:490px;font-size:150px;white-space:nowrap">${chars('than sit in a wallet?')}</div>
<div id="s1-echo" style="position:absolute;left:140px;top:490px;font-size:150px;white-space:nowrap;pointer-events:none" class="disp"></div>
<svg id="s1-rings" viewBox="0 0 700 300" style="position:absolute;left:1140px;top:700px;width:680px;height:290px;overflow:visible" fill="none" stroke="#46188D" stroke-width="2.5">
  <circle cx="40" cy="150" r="26" pathLength="1"/><circle cx="130" cy="150" r="56" pathLength="1"/><circle cx="290" cy="150" r="86" pathLength="1"/><circle cx="520" cy="150" r="118" pathLength="1"/>
  <path d="M0 150H700M40 20V280M130 -10V310M290 -30V330" stroke-width="1.2" opacity=".5" pathLength="1"/></svg>
<div id="s1-panel" style="position:absolute;inset:0;background:var(--v700);clip-path:inset(0 100% 0 0)"></div>
<div id="s1-l4" class="disp dark" style="position:absolute;left:140px;top:340px;font-size:190px;white-space:nowrap">${chars('What if it')}<br>${chars('worked for ')}<span class="ch" style="color:#f9a8d8">${chars('you?')}</span></div>
`, `
const L=0.35; // voiceover starts here
typeIn(tl,'#s1-l1',0.5,1.55);
typeIn(tl,'#s1-l2',1.55,2.35);
typeIn(tl,'#s1-l3',2.35,3.6);
tl.fromTo('#s1-rings circle',{strokeDasharray:1,strokeDashoffset:1},{strokeDashoffset:0,duration:1.2,ease:'power2.out',stagger:.14},2.0);
tl.fromTo('#s1-rings path',{opacity:0},{opacity:.5,duration:.8},2.2);
// echo stack of the last line, fading up like a trail (the reference's repeating type)
const echo=document.getElementById('s1-echo'); for(let i=1;i<=4;i++){ const d=document.createElement('div'); d.textContent='than sit in a wallet?'; d.style.cssText='position:absolute;left:0;top:'+(i*74)+'px;opacity:0;color:#46188D'; echo.appendChild(d); tl.fromTo(d,{opacity:0},{opacity:.4-i*.08,duration:.25,ease:'power2.out'},3.7+i*.09); }
tl.to(['#s1-l1','#s1-l2','#s1-l3','#s1-echo','#s1-rings'],{opacity:0,duration:.2,ease:'power2.in'},4.7);
tl.to('#s1-panel',{clipPath:'inset(0 0% 0 0)',duration:.5,ease:'power4.inOut'},4.6);
typeIn(tl,'#s1-l4',5.1,6.9);
`);

// ---------- S2: the key, not the collateral (ink) ----------
scenes.s2 = scene('s2', 'ink', `
<div id="s2-key" style="position:absolute;left:140px;top:150px;transform-origin:0 50%">${keySvg(300)}</div>
<div id="s2-a" class="disp dark" style="position:absolute;left:480px;top:140px;font-size:190px;white-space:nowrap">${chars('The key.')}</div>
<div id="s2-b" class="disp dark" style="position:absolute;left:140px;top:420px;font-size:150px;white-space:nowrap;color:var(--v300)">${chars('Not the ')}<span style="position:relative;display:inline-block">${chars('collateral.')}<i id="s2-strike" style="position:absolute;left:0;right:0;top:56%;height:12px;background:var(--pink);transform-origin:0 50%"></i></span></div>
<div id="s2-n" class="disp dark" style="position:absolute;left:140px;top:420px;font-size:130px;line-height:1.05;white-space:nowrap;opacity:0"><div>${chars('Never priced.')}</div><div style="color:var(--v300)">${chars('Never taken.')}</div></div>
<svg id="s2-vault" viewBox="0 0 520 420" style="position:absolute;left:1180px;top:200px;width:560px;height:452px;opacity:0" fill="none" stroke="#836EF9" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">
  <rect x="30" y="40" width="460" height="340" rx="36" pathLength="1"/><circle cx="260" cy="210" r="96" pathLength="1"/><circle cx="260" cy="210" r="34" fill="#E845A4" stroke="#0E0B1A" pathLength="1"/>
  <path d="M260 114V150M260 270V306M164 210H200M320 210H356" pathLength="1"/><path d="M110 380V410M410 380V410" pathLength="1"/></svg>
<div id="s2-coin" style="position:absolute;left:1370px;top:120px;opacity:0"><svg width="130" height="130" viewBox="0 0 36 36"><circle cx="18" cy="18" r="14" fill="#FCBB00" stroke="#0E0B1A" stroke-width="2"/><path d="M18 11v14M14 14.5h6.5a2.5 2.5 0 010 5H14" fill="none" stroke="#0E0B1A" stroke-width="2.2" stroke-linecap="round"/></svg></div>
`, `
tl.fromTo('#s2-key',{opacity:0,x:-60,rotation:-14,scale:.8},{opacity:1,x:0,rotation:-4,scale:1,duration:.7,ease:'back.out(1.6)'},1.6);
typeIn(tl,'#s2-a',2.0,3.0);
typeIn(tl,'#s2-b',3.6,5.0);
tl.fromTo('#s2-strike',{scaleX:0},{scaleX:1,duration:.4,ease:'power3.out'},5.1);
tl.to(['#s2-key','#s2-a','#s2-b'],{opacity:0,y:-30,duration:.25,ease:'power2.in'},6.0);
tl.set('#s2-n',{opacity:1},6.25);
typeIn(tl,'#s2-n > div:nth-child(1)',6.3,7.0);
typeIn(tl,'#s2-n > div:nth-child(2)',7.3,8.0);
tl.fromTo('#s2-vault',{opacity:0},{opacity:1,duration:.3},8.2);
tl.fromTo('#s2-vault rect, #s2-vault circle, #s2-vault path',{strokeDasharray:1,strokeDashoffset:1},{strokeDashoffset:0,duration:1.1,ease:'power2.out',stagger:.08},8.2);
tl.fromTo('#s2-coin',{opacity:0,y:-90,scale:.6,rotation:-30},{opacity:1,y:0,scale:1,rotation:8,duration:.6,ease:'back.out(2)'},9.4);
`);

// ---------- S3: pick, open, add (cream + phone) ----------
scenes.s3 = scene('s3', 'cream', `
<div class="disp" style="position:absolute;left:140px;top:110px;font-size:62px;color:var(--v700);font-family:'JetBrains Mono';font-weight:600;letter-spacing:.1em;text-transform:uppercase;font-size:26px">Real app. Real flow.</div>
<div id="s3-r1" class="disp" style="position:absolute;left:140px;top:190px;font-size:170px"><span class="mono" style="font-size:42px;color:var(--v700);margin-right:24px;vertical-align:top;position:relative;top:16px">01</span>Pick.</div>
<div id="s3-r2" class="disp" style="position:absolute;left:140px;top:380px;font-size:170px"><span class="mono" style="font-size:42px;color:var(--v700);margin-right:24px;vertical-align:top;position:relative;top:16px">02</span>Open.</div>
<div id="s3-r3" class="disp" style="position:absolute;left:140px;top:570px;font-size:170px"><span class="mono" style="font-size:42px;color:var(--v700);margin-right:24px;vertical-align:top;position:relative;top:16px">03</span>Add.</div>
<i id="s3-bar" style="position:absolute;left:140px;top:560px;width:900px;height:3px;background:var(--ink);opacity:.15;transform-origin:0 50%"></i>
<div id="s3-c1" class="callout" style="left:760px;top:455px;opacity:0">The Chog moves in</div>
<div id="s3-c2" class="callout" style="left:790px;top:690px;opacity:0">$800 borrowing power</div>
${phone('s3', [['c3a', 0.3, 9.37], ['c3b', 9.67, 8.33]])}
`, `
${phoneIn('s3', .1)}
tl.fromTo('#s3-r1',{opacity:0,x:-50},{opacity:1,x:0,duration:.5,ease:'power3.out'},.5);
tl.fromTo('#s3-r2',{opacity:0,x:-50},{opacity:1,x:0,duration:.5,ease:'power3.out'},1.5);
tl.fromTo('#s3-r3',{opacity:0,x:-50},{opacity:1,x:0,duration:.5,ease:'power3.out'},4.9);
tl.fromTo('#s3-c1',{opacity:0,scale:.9,rotation:-4},{opacity:1,scale:1,rotation:-3,duration:.3,ease:'back.out(2)'},3.6);
tl.to('#s3-c1',{opacity:0,duration:.25},6.6);
tl.fromTo('#s3-c2',{opacity:0,scale:.9,rotation:3},{opacity:1,scale:1,rotation:2,duration:.3,ease:'back.out(2)'},15.2);
`);

// ---------- S4: borrow (ink + phone) ----------
scenes.s4 = scene('s4', 'ink', `
<div class="mono" style="position:absolute;left:140px;top:90px;font-size:26px;letter-spacing:.1em;text-transform:uppercase;color:var(--v300)">You borrowed</div>
<div id="s4-amt" class="mono dark" style="position:absolute;left:130px;top:120px;font-size:180px;line-height:1;letter-spacing:-.03em;white-space:nowrap">$<span id="s4-n">0.00</span></div>
<div id="s4-chip" class="pill" style="position:absolute;left:140px;top:340px;background:#22343c;color:var(--safe);opacity:0"><svg width="30" height="30" viewBox="0 0 20 20"><path d="M10 2l7 3v5c0 4-3 7-7 8-4-1-7-4-7-8V5z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/><path d="M6.5 10l2.5 2.5L13.5 8" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>Safe</div>
<div id="s4-rows" style="position:absolute;left:140px;top:430px;width:900px;color:var(--cream50);font-size:34px">
  <div class="kvr"><span>Assets in vault</span><span class="mono">$2,000.00</span></div>
  <div class="kvr"><span>You owe</span><span class="mono">$300.00</span></div>
  <div class="kvr"><span>You can borrow</span><span class="mono">$500.00</span></div>
  <div class="kvr"><span>Health</span><span class="mono" style="color:var(--safe)">4.33</span></div>
</div>
${phone('s4', [['c4', 0.3, 11.7]])}
`, `
${phoneIn('s4', .1, -2)}
tl.fromTo('#s4-amt',{opacity:0,y:30},{opacity:1,y:0,duration:.5,ease:'power3.out'},.6);
const o={v:0}; tl.to(o,{v:300,duration:1.3,ease:'power3.out',onUpdate:()=>{document.getElementById('s4-n').textContent=o.v.toFixed(2).replace(/\\B(?=(\\d{3})+(?!\\d))/g,',');}},6.0);
tl.fromTo('#s4-chip',{opacity:0,y:16},{opacity:1,y:0,duration:.35,ease:'power3.out'},7.6);
document.querySelectorAll('#s4-rows .kvr').forEach((r,i)=>tl.fromTo(r,{opacity:0,x:-30},{opacity:1,x:0,duration:.4,ease:'power3.out'},4.2+i*.35));
`, `#s4-rows .kvr{display:flex;justify-content:space-between;padding:12px 0;border-bottom:2px dashed var(--ink700);opacity:0}#s4-rows .kvr span.mono{font-size:36px}`);

// ---------- S5: sell with the loan (cream + phone + handshake) ----------
scenes.s5 = scene('s5', 'cream', `
<div class="disp" style="position:absolute;left:140px;top:90px;font-size:112px;line-height:1">Sell it<br><span style="color:var(--v700)">with the loan.</span></div>
<div id="s5-seller" class="card5" style="left:140px;top:360px"><b>Seller</b><span class="mono">signs the offer</span></div>
<div id="s5-buyer" class="card5" style="left:640px;top:360px"><b>Buyer</b><span class="mono">signs back</span></div>
<svg id="s5-links" viewBox="0 0 1000 360" style="position:absolute;left:100px;top:540px;width:1000px;height:300px;overflow:visible" fill="none">
  <path id="s5-p1" d="M170 20 C170 120 330 120 330 20" stroke="#46188D" stroke-width="4" stroke-dasharray="12 12" opacity="0"/>
  <path id="s5-p2" d="M590 20 C590 150 330 150 330 20" stroke="#E845A4" stroke-width="4" stroke-dasharray="12 12" opacity="0"/></svg>
<div id="s5-l1" class="pill" style="position:absolute;left:260px;top:580px;background:var(--ink);color:#f9c230;opacity:0">Offer link</div>
<div id="s5-l2" class="pill" style="position:absolute;left:500px;top:665px;background:var(--ink);color:#f9c230;opacity:0">Signed link</div>
<div id="s5-done" class="pill" style="position:absolute;left:140px;top:730px;font-size:26px;background:var(--v700);color:var(--cream50);opacity:0">Sold. Loan, vault and Chog move together.</div>
<div id="s5-pk1" class="pix" style="left:270px;top:550px;opacity:0"></div><div id="s5-pk2" class="pix" style="left:690px;top:550px;opacity:0"></div>
${phone('s5', [['c5', 0.3, 11.2]])}
`, `
${phoneIn('s5', .1)}
tl.fromTo('#s5-seller',{opacity:0,y:30},{opacity:1,y:0,duration:.45,ease:'power3.out'},1.6);
tl.fromTo('#s5-buyer',{opacity:0,y:30},{opacity:1,y:0,duration:.45,ease:'power3.out'},2.1);
tl.set('#s5-p1',{opacity:1},3.4); tl.fromTo('#s5-p1',{strokeDashoffset:80},{strokeDashoffset:0,duration:.9,ease:'power2.out'},3.4);
tl.fromTo('#s5-l1',{opacity:0,scale:.8},{opacity:1,scale:1,duration:.3,ease:'back.out(2)'},3.9);
tl.set('#s5-pk1',{opacity:1},3.6); tl.to('#s5-pk1',{x:160,duration:.8,ease:'power2.inOut'},3.6); tl.to('#s5-pk1',{opacity:0,duration:.1},4.4);
tl.set('#s5-p2',{opacity:1},5.6); tl.fromTo('#s5-p2',{strokeDashoffset:80},{strokeDashoffset:0,duration:.9,ease:'power2.out'},5.6);
tl.fromTo('#s5-l2',{opacity:0,scale:.8},{opacity:1,scale:1,duration:.3,ease:'back.out(2)'},6.1);
tl.set('#s5-pk2',{opacity:1},5.8); tl.to('#s5-pk2',{x:-260,duration:.8,ease:'power2.inOut'},5.8); tl.to('#s5-pk2',{opacity:0,duration:.1},6.6);
tl.fromTo('#s5-done',{opacity:0,y:20},{opacity:1,y:0,duration:.45,ease:'power3.out'},7.6);
`, `.card5{position:absolute;width:340px;height:150px;border-radius:24px;background:var(--ink);color:var(--cream50);border:2px solid var(--v500);padding:24px 28px;display:flex;flex-direction:column;justify-content:center;gap:6px;opacity:0}.card5 b{font-family:'Baloo 2';font-weight:800;font-size:54px;line-height:1}.card5 span{color:var(--v300);font-size:24px}`);

// ---------- S6: receive and lend (violet + phone) ----------
const qr = (() => { let s = 7, r = []; const n = 21; const rnd = () => (s = (s * 1664525 + 1013904223) >>> 0) / 4294967296;
  const fin = (x, y) => (x < 7 && y < 7) || (x > n - 8 && y < 7) || (x < 7 && y > n - 8);
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) { let on = fin(x, y) ? ((x % (n - 7) < 7 && y % (n - 7) < 7) && (x % (n - 7) === 0 || x % (n - 7) === 6 || y % (n - 7) === 0 || y % (n - 7) === 6 || (x % (n - 7) > 1 && x % (n - 7) < 5 && y % (n - 7) > 1 && y % (n - 7) < 5))) : rnd() > .52; if (on) r.push(`<i class="q" style="left:${x * 22}px;top:${y * 22}px"></i>`); }
  return r.join(''); })();
scenes.s6 = scene('s6', 'violet', `
<div id="s6-qr" style="position:absolute;left:140px;top:150px;width:462px;height:462px;background:var(--cream50);border-radius:28px;padding:0;overflow:hidden"><div style="position:absolute;left:0;top:0;width:462px;height:462px;transform:scale(1)"><div style="position:absolute;inset:0;transform:translate(0,0)">${qr}</div></div></div>
<div id="s6-a" class="disp dark" style="position:absolute;left:660px;top:190px;font-size:118px">Get paid.</div>
<div id="s6-b" class="disp" style="position:absolute;left:660px;top:330px;font-size:118px;color:#f9a8d8">Or earn.</div>
<div id="s6-chips" style="position:absolute;left:660px;top:500px;display:flex;gap:14px;flex-wrap:wrap;width:480px"><span class="pill" style="background:var(--cream50);color:var(--ink)">Link</span><span class="pill" style="background:var(--cream50);color:var(--ink)">QR</span><span class="pill" style="background:var(--cream50);color:var(--ink)">Vault address</span><span class="pill" style="background:var(--pink);color:var(--ink950)">USDC only</span></div>
${phone('s6', [['c6', 0.3, 7.7]])}
`, `
${phoneIn('s6', .1, -2)}
tl.fromTo('#s6-qr',{opacity:0,scale:.85,rotation:-6},{opacity:1,scale:1,rotation:-2,duration:.6,ease:'back.out(1.5)'},.5);
tl.fromTo('#s6-qr .q',{opacity:0},{opacity:1,duration:.02,stagger:{each:.0035,from:'random'}},.9);
tl.fromTo('#s6-a',{opacity:0,x:-40},{opacity:1,x:0,duration:.45,ease:'power3.out'},1.1);
tl.fromTo('#s6-b',{opacity:0,x:-40},{opacity:1,x:0,duration:.45,ease:'power3.out'},3.9);
tl.fromTo('#s6-chips span',{opacity:0,scale:.8},{opacity:1,scale:1,duration:.3,ease:'back.out(2)',stagger:.12},2.0);
`, `.q{position:absolute;width:22px;height:22px;background:var(--ink950)}`);

// ---------- S7: pause drill, limits (ink + phone) ----------
scenes.s7 = scene('s7', 'ink', `
<div id="s7-lock" style="position:absolute;left:140px;top:120px"><svg width="220" height="220" viewBox="0 0 36 36"><rect x="7" y="15" width="22" height="16" rx="4" fill="#E845A4" stroke="#0E0B1A" stroke-width="1.6"/><path id="s7-sh" d="M12 15v-4a6 6 0 0112 0v4" fill="none" stroke="#B7AAFF" stroke-width="2.4" stroke-linecap="round"/><circle cx="18" cy="23" r="2.2" fill="#0E0B1A"/></svg></div>
<div id="s7-t" class="disp dark" style="position:absolute;left:400px;top:120px;font-size:112px;line-height:1.02">Borrow<br>pauses.</div>
<div id="s7-r" class="disp" style="position:absolute;left:400px;top:360px;font-size:112px;color:var(--safe)">Repay never.</div>
<div id="s7-rows" style="position:absolute;left:140px;top:520px;width:900px;font-size:32px;color:var(--cream50)">
  <div class="kvr"><span>Borrow up to</span><span class="mono">40% of value</span></div>
  <div class="kvr"><span>Sold off below</span><span class="mono">65% of value</span></div>
  <div class="kvr"><span>Pool lends at most</span><span class="mono">$15,000</span></div></div>
${phone('s7', [['c7', 0.3, 11.2]])}
`, `
${phoneIn('s7', .1)}
tl.fromTo('#s7-lock',{opacity:0,scale:.7},{opacity:1,scale:1,duration:.4,ease:'back.out(1.6)'},.5);
tl.fromTo('#s7-sh',{y:-5},{y:0,duration:.3,ease:'power2.out'},2.4);
tl.fromTo('#s7-t',{opacity:0,x:-40},{opacity:1,x:0,duration:.45,ease:'power3.out'},1.0);
tl.fromTo('#s7-r',{opacity:0,x:-40},{opacity:1,x:0,duration:.45,ease:'power3.out'},3.2);
document.querySelectorAll('#s7-rows .kvr').forEach((r,i)=>tl.fromTo(r,{opacity:0,x:-30},{opacity:1,x:0,duration:.4,ease:'power3.out'},5.0+i*.45));
`, `#s7-rows .kvr{display:flex;justify-content:space-between;padding:12px 0;border-bottom:2px dashed var(--ink700);opacity:0}#s7-rows .mono{font-size:34px}`);

// ---------- S8: close (cream) ----------
scenes.s8 = scene('s8', 'cream', `
<div id="s8-word" class="disp" style="position:absolute;left:0;right:0;top:210px;text-align:center;font-size:260px">Chog Credit<span id="s8-dot" style="display:inline-block;width:.1em;height:.1em;background:var(--pink);margin-left:.04em"></span></div>
<div id="s8-key" style="position:absolute;left:1380px;top:150px;transform:rotate(12deg)">${keySvg(180)}</div>
<div id="s8-sub" class="mono" style="position:absolute;left:0;right:0;top:560px;text-align:center;font-size:36px;letter-spacing:.12em;text-transform:uppercase;color:var(--v700)">Live on Monad testnet</div>
<div id="s8-url" class="mono" style="position:absolute;left:0;right:0;top:640px;text-align:center;font-size:64px;color:var(--ink)">${chars('chog-credit.vercel.app')}</div>
<div id="s8-tag" class="pill" style="position:absolute;left:0;right:0;margin:0 auto;top:760px;width:max-content;background:var(--ink);color:#f9c230">Look around first. No wallet needed.</div>
`, `
tl.fromTo('#s8-word',{opacity:0,y:50,scale:.96},{opacity:1,y:0,scale:1,duration:.7,ease:'power4.out'},.3);
tl.fromTo('#s8-dot',{scale:0},{scale:1,duration:.4,ease:'back.out(3)'},1.0);
tl.fromTo('#s8-key',{opacity:0,y:-40,rotation:30},{opacity:1,y:0,rotation:12,duration:.6,ease:'back.out(1.8)'},1.2);
tl.fromTo('#s8-sub',{opacity:0,y:20},{opacity:1,y:0,duration:.45,ease:'power3.out'},1.8);
typeIn(tl,'#s8-url',2.8,4.4);
tl.fromTo('#s8-tag',{opacity:0,y:20},{opacity:1,y:0,duration:.45,ease:'power3.out'},4.2);
tl.to('#root',{opacity:0,duration:.8,ease:'power2.in'},8.1);
`);

// ---------- Captions: English karaoke plus an animated translation line ----------
function captionsScene() {
  let html = '', js = `const hide=(sel,t0,t1)=>{tl.to(sel,{opacity:0,duration:.14,ease:'power2.in'},t1-.14);tl.set(sel,{opacity:0,visibility:'hidden'},t1);};\n`;
  let gi = 0;
  for (const [id, start] of SC.map((s) => [s[0], s[1]])) {
    const [lang, groups] = SCRIPT[id]; const dark = SC.find((s) => s[0] === id)[3] !== 'cream';
    const all = groups.flatMap((g) => g[0].split(/\s+/)); const wt = wordTimes(id, all);
    let wi = 0; const t0 = start + VO_AT[id];
    groups.forEach(([en, tr], k) => {
      const ws = en.split(/\s+/); const a = wt[wi][0], b = wt[wi + ws.length - 1][1]; const gs = t0 + a; let ge = t0 + b + (k === groups.length - 1 ? 0.8 : 0.35); if (k < groups.length - 1) { const nb = wt[wi + ws.length][0] + t0; ge = Math.min(ge, nb - 0.08); }
      const gid = `cap${gi++}`; const jp = lang === 'ja';
      html += `<div id="${gid}" class="capg ${dark ? 'dk' : 'lt'}" style="opacity:0;visibility:hidden"><div class="en">${ws.map((w, j) => `<span id="${gid}w${j}" class="w">${esc(w)}</span>`).join(' ')}</div><div class="tr${jp ? ' jp' : ''}"><span class="tag">${LANG[lang][0]}</span><span id="${gid}t" class="tx">${esc(tr)}</span></div></div>\n`;
      js += `tl.fromTo('#${gid}',{opacity:0,y:18,visibility:'visible'},{opacity:1,y:0,duration:.22,ease:'power3.out'},${(gs - 0.05).toFixed(3)});\n`;
      ws.forEach((w, j) => { const [s0] = wt[wi + j]; js += `tl.fromTo('#${gid}w${j}',{color:'${dark ? '#B9B1D6' : '#7a7391'}'},{color:'${dark ? '#FAF9FC' : '#141026'}',duration:.12},${(t0 + s0).toFixed(3)});\n`; });
      js += `tl.fromTo('#${gid}t',{clipPath:'inset(0 100% 0 0)'},{clipPath:'inset(0 0% 0 0)',duration:${Math.max(0.5, Math.min(1.4, (b - a) * 0.7)).toFixed(2)},ease:'power2.out'},${(gs + 0.1).toFixed(3)});\n`;
      js += `hide('#${gid}',${gs.toFixed(3)},${ge.toFixed(3)});\n`;
      wi += ws.length;
    });
  }
  return `<template>
<style>
${FONTS}
#root{position:absolute;inset:0;font-family:'Inter',sans-serif}
.capg{position:absolute;left:140px;bottom:92px;width:1000px;display:flex;flex-direction:column;gap:12px}
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
const vo = SC.map(([id, s]) => { const d = readWavDuration(`assets/vo/${id}.wav`); return `<audio id="vo-${id}" src="assets/vo/${id}.wav" data-start="${(s + VO_AT[id]).toFixed(2)}" data-duration="${(d + 0.05).toFixed(2)}" data-volume="1" data-track-index="5"></audio>`; }).join('\n  ');
// cuts get a whoosh; the typed lines get keys; badges pop; one riser into the closing mark
const SFX = [
  ...SC.slice(1).map(([id, s], i) => [`whoosh${i}`, 'whoosh', s - 0.15, 0.5]),
  ['tick1', 'tick', 0.5, 0.5], ['tick2', 'tick', 1.55, 0.4], ['tick3', 'tick', 2.4, 0.4], ['tick4', 'tick', 5.1, 0.5],
  ['pop1', 'pop', 10.1, 0.6], ['pop2', 'pop', 13.0, 0.5], ['pop3', 'pop', 14.9, 0.5],
  ['pop4', 'pop', 24.6, 0.5], ['pop5', 'pop', 36.2, 0.55], ['pop6', 'pop', 45.6, 0.55],
  ['pop7', 'pop', 54.0, 0.5], ['pop8', 'pop', 56.6, 0.5], ['pop9', 'pop', 57.6, 0.5], ['pop10', 'pop', 68.5, 0.5], ['pop11', 'pop', 74.0, 0.5], ['click1', 'click', 77.5, 0.6],
  ['riser', 'riser', 78.8, 0.7], ['pop12', 'pop', 82.0, 0.7],
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
