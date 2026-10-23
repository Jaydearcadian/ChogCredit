// Cuts the raw walkthrough recordings into speed-ramped clips for the film: waits are sped up, taps stay real time.
import { execFileSync } from 'node:child_process';
const F = new URL('./footage/', import.meta.url).pathname, O = new URL('./demo/assets/footage/', import.meta.url).pathname;
const clips = {
  c3a: ['01-open', [[1.0, 2.4, 1], [2.8, 5.6, 1.3], [5.6, 7.6, 1], [7.6, 14.6, 5], [14.6, 17.0, 1]]],
  c3b: ['02-add', [[4.5, 10.5, 4], [10.5, 13.2, 1], [13.2, 18.5, 3], [26.0, 28.2, 1]]],
  c4: ['03-borrow', [[3.0, 5.0, 1], [5.0, 11.0, 1.5], [11.0, 13.5, 3], [13.5, 18.2, 1]]],
  c5: ['04-sell', [[3.0, 5.0, 1.2], [5.0, 9.0, 1.3], [9.0, 14.5, 3], [14.5, 18.2, 1]]],
  c6: ['05-receive', [[4.6, 9.2, 1.15], [10.6, 13.6, 1]]],
  c7: ['06-pause', [[3.4, 18.7, 1.4]]],
};
for (const [name, [src, segs]] of Object.entries(clips)) {
  const parts = segs.map(([a, b, s], i) => `[0:v]trim=${a}:${b},setpts=(PTS-STARTPTS)/${s},fps=30,scale=780:1688[v${i}]`);
  const fc = parts.join(';') + ';' + segs.map((_, i) => `[v${i}]`).join('') + `concat=n=${segs.length}:v=1:a=0[o]`;
  execFileSync('ffmpeg', ['-v', 'error', '-y', '-i', F + src + '.mp4', '-filter_complex', fc, '-map', '[o]', '-c:v', 'libx264', '-crf', '17', '-pix_fmt', 'yuv420p', '-an', '-movflags', '+faststart', O + name + '.mp4']);
  const d = execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', O + name + '.mp4']).toString().trim();
  console.log(name, (+d).toFixed(2) + 's');
}
