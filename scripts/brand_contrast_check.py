#!/usr/bin/env python3
"""Verifies the Chog Credit brand palette: WCAG 2.x contrast, APCA Lc, and colour-vision-deficiency separation of
the status colours. Pure standard library. Run: python3 -I scripts/brand_contrast_check.py"""
import math

def h2rgb(h):
    h = h.lstrip('#'); return [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
def lin(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def unlin(c): return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
def lum(h):
    r, g, b = [lin(c) for c in h2rgb(h)]; return 0.2126 * r + 0.7152 * g + 0.0722 * b
def wcag(a, b):
    la, lb = lum(a), lum(b); hi, lo = max(la, lb), min(la, lb); return (hi + 0.05) / (lo + 0.05)

def apca(text, bg):
    """APCA-W3 0.0.98G-4g. Returns Lc (signed: positive = dark text on light bg)."""
    def y(h):
        r, g, b = h2rgb(h); return 0.2126729 * r ** 2.4 + 0.7151522 * g ** 2.4 + 0.0721750 * b ** 2.4
    yt, yb = y(text), y(bg)
    yt = yt if yt > 0.022 else yt + (0.022 - yt) ** 1.414
    yb = yb if yb > 0.022 else yb + (0.022 - yb) ** 1.414
    if abs(yb - yt) < 0.0005: return 0.0
    if yb > yt:
        s = (yb ** 0.56 - yt ** 0.57) * 1.14; return 0.0 if s < 0.1 else (s - 0.027) * 100
    s = (yb ** 0.65 - yt ** 0.62) * 1.14; return 0.0 if s > -0.1 else (s + 0.027) * 100

def to_oklab(h):
    r, g, b = [lin(c) for c in h2rgb(h)]
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, m, s = l ** (1 / 3), m ** (1 / 3), s ** (1 / 3)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
def oklch(h):
    L, a, b = to_oklab(h); return L, math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360
def dE(h1, h2):
    a, b = to_oklab(h1), to_oklab(h2); return math.dist(a, b)

# Machado et al. 2009, severity 1.0, applied in linear RGB
CVD = {
    'protanopia':   [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
    'deuteranopia': [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
    'tritanopia':   [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
}
def sim(h, m):
    v = [lin(c) for c in h2rgb(h)]
    o = [max(0, min(1, sum(m[i][j] * v[j] for j in range(3)))) for i in range(3)]
    return '#' + ''.join('%02x' % round(unlin(c) * 255) for c in o)

INK = {'ink-950': '#0E0B1A', 'ink-900': '#141026', 'ink-850': '#181330', 'ink-800': '#211A40', 'ink-700': '#2D2556'}
CREAM = {'cream-50': '#FAF9FC', 'cream-100': '#F4F1E6', 'cream-200': '#E7E2D0'}
BRAND = {'purple-500': '#836EF9', 'purple-300': '#B7AAFF', 'purple-700': '#46188D',
         'pink-500': '#E845A4', 'pink-300': '#FF8FD0', 'amber-400': '#FCBB00'}
STATUS_DARK = {'safe': '#72E4BC', 'watch': '#F9C230', 'risk': '#EA7C31', 'danger': '#C83846'}
STATUS_LIGHT = {'safe': '#3F7F4F', 'watch': '#5E522A', 'risk': '#B65329', 'danger': '#AC1828'}

def row(name, fg, bg, need=4.5):
    c = wcag(fg, bg); lc = abs(apca(fg, bg)); ok = 'PASS' if c >= need else 'FAIL'
    return f"| {name} | `{fg}` on `{bg}` | {c:5.2f}:1 | Lc {lc:4.0f} | {ok} (>= {need}) |"

if __name__ == '__main__':
    print('## Text pairs (dark theme)')
    print('| Pair | Colours | WCAG | APCA | Result |\n|---|---|---|---|---|')
    for bgn in ('ink-900', 'ink-850', 'ink-800'):
        bg = INK[bgn]
        print(row(f'cream-50 text on {bgn}', CREAM['cream-50'], bg))
        print(row(f'muted text (#D2CCEA) on {bgn}', '#D2CCEA', bg))
        print(row(f'purple-300 link on {bgn}', BRAND['purple-300'], bg))
        print(row(f'pink-300 on {bgn}', BRAND['pink-300'], bg))
        for k, v in STATUS_DARK.items(): print(row(f'status {k} ICON/BORDER on {bgn}', v, bg, 3.0))
    print('\n## Status chips: cream text on a status-tinted surface (status colour is the icon/border, never the label)')
    print('| Chip | Surface | WCAG | APCA | Icon/border vs ink-900 (non-text, >= 3:1) |\n|---|---|---|---|---|')
    def mix(a, b, t):
        ra, rb = h2rgb(a), h2rgb(b)
        return '#' + ''.join('%02x' % round((x * t + y * (1 - t)) * 255) for x, y in zip(ra, rb))
    for k, v in STATUS_DARK.items():
        surf = mix(v, INK['ink-900'], 0.18)
        print(f"| {k} | `{surf}` | {wcag(CREAM['cream-50'], surf):5.2f}:1 | Lc {abs(apca(CREAM['cream-50'], surf)):4.0f} | {wcag(v, INK['ink-900']):5.2f}:1 |")
    print('\n## Brand/accent text')
    print(row('PRIMARY BUTTON: cream-50 on #6B52F0', CREAM['cream-50'], '#6B52F0'))
    print(row('rejected: cream-50 on Monad purple-500 #836EF9', CREAM['cream-50'], BRAND['purple-500']))
    print(row('rejected: ink-950 on Monad purple-500 (APCA too low)', INK['ink-950'], BRAND['purple-500']))
    print(row('primary button fill edge vs ink-900 (non-text 3:1)', '#6B52F0', INK['ink-900'], 3.0))
    print(row('on-accent: ink-950 on pink-500 sticker', INK['ink-950'], BRAND['pink-500']))
    print(row('on-accent: ink-950 on amber-400', INK['ink-950'], BRAND['amber-400']))
    print(row('purple-500 UI edge on ink-900 (non-text 3:1)', BRAND['purple-500'], INK['ink-900'], 3.0))
    print('\n## Text pairs (light "cream" theme)')
    print('| Pair | Colours | WCAG | APCA | Result |\n|---|---|---|---|---|')
    for bgn in ('cream-50', 'cream-100'):
        bg = CREAM[bgn]
        print(row(f'ink-900 text on {bgn}', INK['ink-900'], bg))
        print(row(f'muted text (#575070) on {bgn}', '#575070', bg))
        print(row(f'purple link (#5B3FD6) on {bgn}', '#5B3FD6', bg))
        if bgn == 'cream-50':  # light status tokens are only specified on the lightest cream
            for k, v in STATUS_LIGHT.items(): print(row(f'status {k} on {bgn}', v, bg))
    print(row('cream-50 on purple-700 button', CREAM['cream-50'], BRAND['purple-700']))
    print('\n## Status colours under colour-vision deficiency (OKLab distance; >= 0.08 reads as clearly different)')
    for theme, st in (('dark', STATUS_DARK), ('light', STATUS_LIGHT)):
        names = list(st)
        for kind in ['normal'] + list(CVD):
            cols = {n: (st[n] if kind == 'normal' else sim(st[n], CVD[kind])) for n in names}
            pairs = [(a, b, dE(cols[a], cols[b])) for i, a in enumerate(names) for b in names[i + 1:]]
            worst = min(pairs, key=lambda p: p[2])
            print(f"- {theme}/{kind}: closest pair {worst[0]}~{worst[1]} dE={worst[2]:.3f}", 'OK' if worst[2] >= 0.08 else 'TOO CLOSE (needs icon + text, which the design already requires)')
    print('\n## Lightness steps of status (OKLab L) for the greyscale test')
    for theme, st in (('dark', STATUS_DARK), ('light', STATUS_LIGHT)):
        print(theme, {n: round(oklch(v)[0], 3) for n, v in st.items()})
    print('\n## OKLCH of key brand colours')
    for n, v in {**INK, **CREAM, **BRAND, **{'s-' + k: v for k, v in STATUS_DARK.items()}}.items():
        L, C, H = oklch(v); print(f"- {n} {v}: oklch({L*100:.1f}% {C:.3f} {H:.0f})")
