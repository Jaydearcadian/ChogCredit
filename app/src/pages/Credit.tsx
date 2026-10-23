import { useEffect, useState } from 'react';
import { Link, Navigate, useNavigate } from 'react-router-dom';
import { ABI, maxWithdrawable } from '../chain/api';
import { fmt, fmtPlain, fmtUsdc, healthNumber, parseAmount } from '../chain/format';
import { statusOf, type Status } from '../chain/status';
import { HealthRing } from '../components/brand';
import { AmountField } from '../components/field';
import { LockNote, Shell, StatusChip, ArtBox } from '../components/parts';
import { TxStrip, useTx } from '../components/tx';
import { useApp } from '../state';
import { useAccount } from './useAccount';

function healthAfter(liquidationValue: bigint, debtAfter: bigint, priceOk: boolean) {
  if (debtAfter === 0n) return { status: 'nodebt' as Status, bps: 2n ** 255n };
  const bps = (liquidationValue * 10_000n) / debtAfter;
  return { status: statusOf({ priceOk, debt: debtAfter, healthFactorBps: bps }), bps };
}

function Preview({ status, bps }: { status: Status; bps: bigint }) {
  const label = status === 'nodebt' ? 'No loan' : (healthNumber(bps) ?? '--');
  return (
    <div className="row">
      <HealthRing fill={status === 'nodebt' ? 1 : Math.min(1, Number(bps) / 25_000)} label={label} paused={status === 'paused'} />
      <div className="stack" style={{ flex: 1, paddingLeft: 12, gap: 6 }}>
        <span className="small muted">Health after</span>
        {status === 'nodebt' ? <span className="muted">Debt-free</span> : <StatusChip status={status} />}
      </div>
    </div>
  );
}

/** S8 Borrow and S9 Repay */
export function Borrow() {
  const { dep, wallet } = useApp();
  const { acct } = useAccount();
  const tx = useTx();
  const [mode, setMode] = useState<'borrow' | 'repay'>('borrow');
  const [text, setText] = useState('');
  if (!wallet) return <Navigate to="/" replace />;
  if (!acct) return <Shell><p className="muted">Loading…</p></Shell>;

  const d = acct.data;
  const amount = parseAmount(text, 6);
  const maxBorrow = d.priceOk ? d.availableToBorrow : 0n;
  const maxRepay = d.debt < acct.usdcWallet ? d.debt : acct.usdcWallet;
  const rate = (Number(acct.borrowRateBps) / 100).toFixed(1);
  const owedAfter = amount === null ? d.debt : mode === 'borrow' ? d.debt + amount : d.debt - (amount > d.debt ? d.debt : amount);
  const prev = healthAfter(d.liquidationValue, owedAfter, d.priceOk);

  let blocked: string | null = null;
  if (mode === 'borrow') {
    if (!d.priceOk) blocked = 'Borrowing is paused while prices are unavailable.';
    else if (amount !== null && amount > maxBorrow) blocked = `Over your limit. You can borrow up to ${fmtUsdc(maxBorrow)} USDC.`;
    else if (amount !== null && amount > acct.poolLiquidity) blocked = 'The pool is short of USDC right now. Try a smaller amount.';
  } else if (amount !== null && amount > acct.usdcWallet) blocked = 'More than your wallet holds.';
  const ready = amount !== null && amount > 0n && !blocked && !tx.busy;

  const go = async () => {
    if (!ready || amount === null) return;
    const ok = mode === 'borrow'
      ? await tx.run([{ address: dep.pool, abi: ABI.pool, functionName: 'borrow', args: [acct.key, amount] }])
      : await tx.run([
          { address: dep.mockUsdc, abi: ABI.erc20, functionName: 'approve', args: [dep.pool, amount] },
          { address: dep.pool, abi: ABI.pool, functionName: 'repay', args: [acct.key, amount >= d.debt ? 2n ** 256n - 1n : amount] },
        ], amount >= d.debt ? 'repaid' : 'confirmed');
    if (ok) setText('');
  };
  const repayAll = async () => {
    const buffer = d.debt + d.debt / 100n + 1_000n; // interest keeps accruing while the wallet signs
    await tx.run([
      { address: dep.mockUsdc, abi: ABI.erc20, functionName: 'approve', args: [dep.pool, buffer] },
      { address: dep.pool, abi: ABI.pool, functionName: 'repay', args: [acct.key, 2n ** 256n - 1n] },
    ], 'repaid');
  };

  return (
    <Shell>
      <h1>{mode === 'borrow' ? 'Borrow USDC' : 'Repay'}</h1>
      <div className="row" role="tablist" style={{ justifyContent: 'flex-start' }}>
        {(['borrow', 'repay'] as const).map((m) => (
          <button key={m} role="tab" aria-selected={mode === m} className={`btn ${mode === m ? '' : 'secondary'}`} style={{ minHeight: 44, padding: '0 18px' }} onClick={() => { setMode(m); setText(''); tx.reset(); }}>{m === 'borrow' ? 'Borrow' : 'Repay'}</button>
        ))}
      </div>
      {mode === 'repay' && (
        <div className="card">
          <div className="row"><span className="small muted">You owe</span><b className="num">{fmtUsdc(d.debt)} USDC</b></div>
          <span className="small muted">Includes interest so far.</span>
        </div>
      )}
      {mode === 'borrow' && !d.priceOk && <LockNote>Borrowing is paused while prices are unavailable.</LockNote>}
      <AmountField
        label={`Amount · ${mode === 'borrow' ? `up to ${fmtUsdc(maxBorrow)}` : `wallet ${fmtUsdc(acct.usdcWallet)}`} USDC`}
        value={text} onChange={setText} error={amount !== null ? blocked : null} disabled={mode === 'borrow' && !d.priceOk}
        fix={mode === 'borrow' && amount !== null && amount > maxBorrow ? `Use ${fmtUsdc(maxBorrow)}` : undefined}
        onFix={() => setText(fmtPlain(maxBorrow, 6))}
        onMax={() => setText(fmtPlain(mode === 'borrow' ? maxBorrow : maxRepay, 6))}
      />
      <Preview status={prev.status} bps={prev.bps} />
      {mode === 'borrow' && (
        <div className="card">
          <div className="row"><span className="small muted">Interest</span><span className="num">{rate}% a year, variable</span></div>
          <div className="row"><span className="small muted">You will owe</span><b className="num">{fmtUsdc(owedAfter)} USDC</b></div>
          <span className="small muted">While you owe, the Chog stays locked. Repay in full to release it.</span>
        </div>
      )}
      <button className="btn big" disabled={!ready} onClick={go}>{amount ? `${mode === 'borrow' ? 'Borrow' : 'Repay'} ${text} USDC` : mode === 'borrow' ? 'Borrow' : 'Repay'}</button>
      {mode === 'repay' && d.debt > 0n && acct.usdcWallet >= d.debt && <button className="btn secondary" disabled={tx.busy} onClick={repayAll}>Repay all · {fmtUsdc(d.debt)}</button>}
      <TxStrip stage={tx.stage} step={tx.step} message={tx.message} />
      <Link to="/account" className="small">Back to account</Link>
    </Shell>
  );
}

/** S10 Withdraw */
export function Withdraw() {
  const { dep, pc, wallet } = useApp();
  const { acct } = useAccount();
  const tx = useTx();
  const [sym, setSym] = useState<string | null>(null);
  const [text, setText] = useState('');
  const [max, setMax] = useState<bigint | null>(null);
  const held = acct?.tokens.filter((t) => t.accounted > 0n) ?? [];
  const token = held.find((t) => t.symbol === sym) ?? held[0];

  useEffect(() => {
    if (!acct || !token) { setMax(null); return; }
    let live = true;
    maxWithdrawable(pc, dep, acct.key, token.address, token.accounted).then((m) => live && setMax(m));
    return () => { live = false; };
  }, [pc, dep, acct, token]);

  if (!wallet) return <Navigate to="/" replace />;
  if (!acct) return <Shell><p className="muted">Loading…</p></Shell>;
  if (!token) return <Shell><h1>Withdraw</h1><div className="card"><b>Nothing in the vault.</b><span className="small muted">Add assets first.</span></div><Link to="/add" className="btn">Add assets</Link></Shell>;

  const amount = parseAmount(text, token.decimals);
  const over = amount !== null && max !== null && amount > max;
  const ready = amount !== null && amount > 0n && !over && !tx.busy;
  const go = async () => {
    if (!ready || amount === null) return;
    if (await tx.run([{ address: acct.vault, abi: ABI.vault, functionName: 'withdrawERC20', args: [token.address, amount, wallet.address] }])) setText('');
  };

  return (
    <Shell>
      <h1>Withdraw</h1>
      <div className="row" role="tablist" style={{ justifyContent: 'flex-start' }}>
        {held.map((t) => <button key={t.symbol} role="tab" aria-selected={token.symbol === t.symbol} className={`btn ${token.symbol === t.symbol ? '' : 'secondary'}`} style={{ minHeight: 44, padding: '0 14px' }} onClick={() => { setSym(t.symbol); setText(''); }}>{t.symbol}</button>)}
      </div>
      <div className="card"><div className="row"><b>{token.symbol}</b><span className="num">{fmt(token.accounted, token.decimals)} in vault</span></div></div>
      <AmountField label={`Amount of ${token.symbol} to take out`} value={text} onChange={setText}
        error={over ? 'Taking out that much would leave the loan under-covered. Repay some first, or take less.' : null}
        fix={over && max !== null ? `Use ${fmt(max, token.decimals)}` : undefined} onFix={() => max !== null && setText(fmtPlain(max, token.decimals))}
        onMax={() => max !== null && setText(fmtPlain(max, token.decimals))} />
      {max !== null && (
        <div className="card"><span>You can take {fmt(max, token.decimals)} {token.symbol} out right now.</span></div>
      )}
      <button className="btn big" disabled={!ready} onClick={go}>{amount ? `Withdraw ${text} ${token.symbol}` : 'Withdraw'}</button>
      <TxStrip stage={tx.stage} step={tx.step} message={tx.message} />
      <Link to="/account" className="small">Back to account</Link>
    </Shell>
  );
}

/** S11 Release the Chog */
export function Release() {
  const { dep, wallet } = useApp();
  const { acct, id } = useAccount();
  const tx = useTx();
  const nav = useNavigate();
  if (!wallet) return <Navigate to="/" replace />;
  if (!acct || id === null) return <Shell><p className="muted">Loading…</p></Shell>;
  const held = acct.tokens.filter((t) => t.accounted > 0n);
  const debt = acct.data.debt;
  const releaseCall = { address: dep.escrow, abi: ABI.escrow, functionName: 'release', args: [dep.mockChogGenesis, BigInt(id), wallet.address] };
  const withdrawAll = () => tx.run(held.map((t) => ({ address: acct.vault, abi: ABI.vault, functionName: 'withdrawERC20', args: [t.address, t.accounted, wallet.address] })));
  const release = async () => { if (await tx.run([releaseCall])) nav('/pick'); };

  return (
    <Shell>
      <ArtBox id={id} height={120} />
      <h1>{debt === 0n ? 'Get your Chog back' : 'Release the Chog'}</h1>
      <div className="card">
        <div className="row"><span className="small muted">Owed</span><b className="num">{fmtUsdc(debt)} USDC</b></div>
        <div className="row"><span className="small muted">Still in vault</span><span className="num">{held.length ? held.map((t) => `${fmt(t.accounted, t.decimals, 0)} ${t.symbol}`).join(', ') : 'nothing'}</span></div>
      </div>
      <p className="small muted" style={{ margin: 0 }}>To get your Chog back, repay everything and take everything out. The vault must be empty.</p>
      {debt > 0n && <Link to="/borrow" className="btn">Repay first</Link>}
      {debt === 0n && held.length > 0 && <button className="btn big" disabled={tx.busy} onClick={withdrawAll}>Withdraw all</button>}
      <button className={`btn ${debt === 0n && held.length === 0 ? 'big' : 'secondary'}`} disabled={tx.busy || debt > 0n || held.length > 0} onClick={release}>Release Chog</button>
      <TxStrip stage={tx.stage} step={tx.step} message={tx.message} />
      <Link to="/account" className="small">Back to account</Link>
    </Shell>
  );
}
