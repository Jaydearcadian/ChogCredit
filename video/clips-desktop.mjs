// Cuts the desktop recordings (1920x1200, app at 1280x800 CSS) into 1920x1080 clips for the film.
// Each segment: [from, to, speed, framing]. A = tight on the account card (top-left 1460x821), B = the full app width.
import { execFileSync } from 'node:child_process';
const F = new URL('./footage/desktop/', import.meta.url).pathname, O = new URL('./demo/assets/footage/', import.meta.url).pathname;
const CROP = { A: 'crop=1460:821:0:0', B: 'crop=1920:1080:0:0' };
const clips = {
  d3a: ['01-open', [[1.4, 3.6, 1, 'B'], [3.8, 5.6, 1, 'B'], [6.2, 8.2, 1, 'B'], [8.2, 15.0, 6, 'B'], [15.4, 18.0, 1, 'A']]],
  d3b: ['02-add', [[5.0, 11.5, 5, 'B'], [11.5, 15.0, 1, 'B'], [15.0, 18.8, 2.5, 'B'], [27.0, 27.8, 0.4, 'A']]],
  d4: ['03-borrow', [[4.4, 5.6, 1, 'A'], [5.6, 12.8, 1.4, 'B'], [12.8, 14.0, 2, 'B'], [14.0, 17.6, 1, 'B'], [17.8, 18.7, 0.6, 'A']]],
  d5: ['04-sell', [[4.4, 5.6, 1, 'A'], [5.6, 10.9, 0.9, 'B'], [10.9, 12.8, 0.6, 'B']]],
  d6: ['05-receive', [[5.6, 10.6, 1, 'B'], [10.8, 12.1, 0.6, 'B']]],
  d7: ['06-pause', [[4.2, 6.6, 1, 'A'], [6.6, 8.0, 1, 'B'], [8.0, 12.4, 1, 'B'], [12.4, 17.6, 1, 'A']]],
};
for (const [name, [src, segs]] of Object.entries(clips)) {
  const parts = segs.map(([a, b, s, c], i) => `[0:v]trim=${a}:${b},setpts=(PTS-STARTPTS)/${s},fps=30,${CROP[c]},scale=1920:1080:flags=lanczos,setsar=1[v${i}]`);
  const fc = parts.join(';') + ';' + segs.map((_, i) => `[v${i}]`).join('') + `concat=n=${segs.length}:v=1:a=0,tpad=stop_mode=clone:stop_duration=3[o]`;
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-i', F + src + '.mp4', '-filter_complex', fc, '-map', '[o]', '-c:v', 'libx264', '-crf', '15', '-pix_fmt', 'yuv420p', '-an', '-movflags', '+faststart', O + name + '.mp4']);
  let t = 0; const marks = segs.map(([a, b, s]) => { const r = +(t).toFixed(2); t += (b - a) / s; return r; });
  console.log(name, 'content', t.toFixed(2) + 's', 'segment starts', marks.join(' '));
}
