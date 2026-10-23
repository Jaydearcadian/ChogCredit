import QRCode from 'qrcode';
import { useEffect, useState } from 'react';

/** A QR code drawn as an SVG so it stays sharp. Dark on cream, with a quiet zone. */
export function Qr({ text, size = 168, label }: { text: string; size?: number; label: string }) {
  const [svg, setSvg] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    QRCode.toString(text, { type: 'svg', margin: 1, color: { dark: '#141026', light: '#faf9fc' }, errorCorrectionLevel: 'M' }).then((s) => live && setSvg(s)).catch(() => live && setSvg(null));
    return () => { live = false; };
  }, [text]);
  if (!svg) return <div className="skel" style={{ width: size, height: size }} />;
  return <div role="img" aria-label={label} style={{ width: size, height: size, borderRadius: 14, overflow: 'hidden', background: '#faf9fc', flex: 'none' }} dangerouslySetInnerHTML={{ __html: svg.replace('<svg ', `<svg width="${size}" height="${size}" `) }} />;
}
