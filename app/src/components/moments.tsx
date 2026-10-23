import { useEffect, useState } from 'react';
import { Slip } from './brand';

/** 1. Vault Door: the halves close over the frame and the stamp pulses once. Reduced motion: a static closed door. */
export const VaultDoor = () => <div className="door" aria-hidden="true"><i /><i /><b /></div>;

/** Debt-free: one burst of sparkles around the bubble. */
export function Sparkles() {
  const star = (pos: React.CSSProperties, fill: string, size: number) => (
    <svg className="spark" width={size} height={size} viewBox="0 0 36 36" aria-hidden="true" style={pos}>
      <path d="M18 3l3.2 9.8L31 14l-7.5 6.2L26 30l-8-5.6L10 30l2.5-9.8L5 14l9.8-1.2z" fill={fill} stroke="#0E0B1A" strokeWidth="2" strokeLinejoin="round" />
    </svg>
  );
  return <span aria-hidden="true" style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>{star({ left: -10, top: -16 }, '#E845A4', 26)}{star({ right: -12, top: -20 }, '#FCBB00', 30)}{star({ right: 30, bottom: -14 }, '#E845A4', 18)}</span>;
}

/** Skeletons appear only after 100 ms, so quick loads never flash. */
export function Skel({ h, r }: { h: number; r?: number }) {
  const [on, setOn] = useState(false);
  useEffect(() => { const t = setTimeout(() => setOn(true), 100); return () => clearTimeout(t); }, []);
  return <div className="skel" style={{ height: h, borderRadius: r, opacity: on ? 1 : 0, transition: 'opacity var(--dur-quick) var(--ease)' }} />;
}
export function AccountSkeleton() {
  return (
    <div className="stack" role="status" aria-label="Loading your account" aria-busy="true">
      <Skel h={176} r={16} /><Skel h={20} r={8} /><Skel h={140} /><div className="pair"><Skel h={56} r={16} /><Skel h={56} r={16} /></div>
    </div>
  );
}
export function FlowSkeleton() {
  return <div className="stack" role="status" aria-label="Loading" aria-busy="true"><Skel h={22} r={8} /><Skel h={60} r={12} /><Skel h={44} r={22} /><Skel h={170} /></div>;
}

const TORN = 'chog-credit:torn';
export const tearSeen = () => { try { return localStorage.getItem(TORN) === '1'; } catch { return true; } };
const markTear = () => { try { localStorage.setItem(TORN, '1'); } catch { /* storage blocked: the moment may repeat, which is harmless */ } };

/** 12. Once ever: after the first borrow the Slip's stub tears away. A flourish, not a reward. */
export function TearOff() {
  useEffect(() => { markTear(); }, []);
  return (
    <div className="card" role="img" aria-label="Your first credit slip. The stub tears off." style={{ flexDirection: 'row', alignItems: 'center', gap: 16 }}>
      <Slip size={84} stub />
      <div className="stack" style={{ gap: 2 }}><b>Your first slip.</b><span className="small muted">Borrowed. Repay any time.</span></div>
    </div>
  );
}
