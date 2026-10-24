import { useEffect, useState } from 'react';
import { parseAbi } from 'viem';
import { ABI, loadLend, sharesFor, type LendView } from '../chain/api';
import { fmtPlain, fmtUsdc, parseAmount } from '../chain/format';
import { Amount } from '../components/amount';
import { Bubble, Icon } from '../components/brand';
import { ConnectGate, Shell } from '../components/chrome';
import { Skel } from '../components/moments';
import { Num } from '../components/status';
import { TxSteps, useTx } from '../components/tx';
import { useApp } from '../state';

const pct = (bps: bigint) => `${(Number(bps) / 100).toFixed(2)}%`;

/** S19 Lend: put USDC in the pool and earn the interest borrowers pay; take it back when the pool has cash. */
export default function Lend() {
  const { dep, pc, wallet, tick, test } = useApp();
  const [v, setV] = useState<LendView | null>(null);
  const [mode, setMode] = useState<'supply' | 'withdraw'>('supply');
  const [text, setText] = useState('');
  const tx = useTx();
  const faucet = useTx();

  useEffect(() => {
    let live = true;
    const load = () => loadLend(pc, dep, wallet?.address ?? null).then((r) => live && setV(r)).catch(() => undefined);
    load();
    const t = setInterval(load, 8000);
    return () => { live = false; clearInterval(t); };
  }, [pc, dep, wallet?.address, tick, tx.stage, faucet.stage]);

  if (!v) return <Shell enter={false}><h1>Lend USDC</h1><Skel h={150} /><Skel h={200} /></Shell>;

  // Interest is paid by borrowers and shared by everyone who lends, so the lender rate is the borrow rate times utilization.
  const lenderRate = (v.borrowRateBps * v.utilizationBps) / 10_000n;
  const amount = parseAmount(text, 6);
  const room = v.supplyCap > v.totalAssets ? v.supplyCap - v.totalAssets : 0n;
  const supplyMax = v.usdcWallet < room ? v.usdcWallet : room;
  const withdrawMax = v.maxRedeem === v.shares ? v.position : (v.position * v.maxRedeem) / (v.shares || 1n);
  const max = mode === 'supply' ? supplyMax : withdrawMax;
  const error = amount !== null && amount > max
    ? mode === 'supply'
      ? amount > v.usdcWallet ? `More than your wallet holds (${fmtUsdc(v.usdcWallet)}).` : `The pool is nearly full. Room for ${fmtUsdc(room)} more.`
      : withdrawMax < v.position ? `The pool has ${fmtUsdc(v.liquidity)} in cash right now, because the rest is lent out. You can take ${fmtUsdc(withdrawMax)} now.` : `More than you have in the pool (${fmtUsdc(v.position)}).`
    : null;
  const ready = !!wallet && amount !== null && amount > 0n && !error && !tx.busy;
  const done = tx.stage === 'confirmed' || tx.stage === 'final';

  const go = async () => {
    if (!ready || amount === null) return;
    const ok = mode === 'supply'
      ? await tx.run([
          { address: dep.mockUsdc, abi: ABI.erc20, functionName: 'approve', args: [dep.pool, amount] },
          { address: dep.pool, abi: ABI.pool, functionName: 'supply', args: [amount] },
        ])
      : await tx.run([{ address: dep.pool, abi: ABI.pool, functionName: 'redeem', args: [amount >= withdrawMax ? v.maxRedeem : await sharesFor(pc, dep, amount)] }]);
    if (ok) setText('');
  };
  const getUsdc = () => faucet.run([{ address: dep.mockUsdc, abi: parseAbi(['function faucet()']), functionName: 'faucet', args: [] }]);

  return (
    <Shell>
      <h1>Lend USDC</h1>
      <p className="muted" style={{ margin: 0 }}>Lenders fund the pool that borrowers draw from, and earn the interest they pay.</p>

      <section className="card">
        <div className="kv"><span>Pool deposits</span><Num value={`${fmtUsdc(v.totalAssets)} USDC`} /></div>
        <div className="kv"><span>Borrowed out</span><Num value={`${fmtUsdc(v.totalDebt)} USDC`} /></div>
        <div className="kv"><span>Cash in the pool</span><Num value={`${fmtUsdc(v.liquidity)} USDC`} /></div>
        <div className="kv rule"><span>Used by borrowers</span><span className="num">{pct(v.utilizationBps)}</span></div>
        <div className="kv"><span>Borrowers pay</span><span className="num">{pct(v.borrowRateBps)} a year, variable</span></div>
        <div className="kv"><span>Lenders earn</span><span className="num">{pct(lenderRate)} a year, variable</span></div>
        {test && dep.demoChog !== undefined && v.totalDebt > 0n && <span className="tiny muted">On this test network, some of what is borrowed is a demo loan: Chog #{dep.demoChog}, a vault we opened so the lender yield is visible. It is real on-chain interest, not a real market.</span>}
      </section>

      {wallet ? (
        <section className="card">
          <div className="kv"><span>Your deposit</span><Num value={`${fmtUsdc(v.position)} USDC`} /></div>
          <span className="tiny muted">Grows as borrowers pay interest. The number above is what you could take out if the pool had the cash.</span>
        </section>
      ) : <ConnectGate action="lend" back="/lend" />}

      {wallet && (
        <>
          <div className="segment" role="tablist" aria-label="Lend or withdraw">
            <span className="thumb" aria-hidden="true" style={{ width: 'calc(50% - 4px)', transform: `translateX(${mode === 'supply' ? 0 : 100}%)` }} />
            {(['supply', 'withdraw'] as const).map((m) => <button key={m} role="tab" aria-selected={mode === m} onClick={() => { setMode(m); setText(''); tx.reset(); }}>{m === 'supply' ? 'Lend' : 'Withdraw'}</button>)}
          </div>
          <Amount key={mode} label={mode === 'supply' ? 'How much do you want to lend?' : 'How much do you want to take out?'} unit="USDC" decimals={6} max={max} value={text} onChange={setText}
            maxLabel={mode === 'supply' ? `In your wallet: ${fmtUsdc(v.usdcWallet)}` : `You can take out now: ${fmtUsdc(withdrawMax)}`} error={error}
            fixLabel={`Use ${fmtUsdc(max)}`} onFix={() => setText(fmtPlain(max, 6))} />
          {mode === 'supply' && v.usdcWallet === 0n && test && <button className="btn secondary block" disabled={faucet.busy} onClick={getUsdc}>{faucet.busy ? 'Check your wallet' : 'Get test USDC'}</button>}
          <div className="note">{Icon.alert}<span>{mode === 'supply' ? 'If a loan goes bad and its collateral cannot cover it, lenders share the loss. You can only take your money out while the pool has cash; the rest is lent out.' : 'Withdrawing needs cash in the pool. If most of it is lent out, you can take part now and the rest as borrowers repay.'}</span></div>
          <TxSteps title={mode === 'supply' ? `Lend ${text || '0'} USDC` : `Withdraw ${text || '0'} USDC`} tx={tx} />
          {done && <Bubble>{mode === 'supply' ? 'Thanks for filling the pool.' : 'Taken out.'}</Bubble>}
          <button className="btn cta block" disabled={!ready} onClick={go}>{tx.busy ? 'Check your wallet' : amount ? `${mode === 'supply' ? 'Lend' : 'Withdraw'} ${fmtUsdc(amount)} USDC` : mode === 'supply' ? 'Lend' : 'Withdraw'}</button>
        </>
      )}
    </Shell>
  );
}
