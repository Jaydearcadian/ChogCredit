import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { Link, Navigate, useNavigate } from 'react-router-dom';
import { parseAbi } from 'viem';
import { ABI, maxWithdrawable, previewBorrowPowerGain, type AccountView } from '../chain/api';
import { fmt, fmtUsdc, healthNumber, parseAmount } from '../chain/format';
import { statusOf, type Status } from '../chain/status';
import { Amount } from '../components/amount';
import { Bubble, ChogFrame, Icon } from '../components/brand';
import { Shell } from '../components/chrome';
import { FlowSkeleton, Sparkles, TearOff, tearSeen } from '../components/moments';
import { Chip, Num, Swap } from '../components/status';
import { TxSteps, useTx } from '../components/tx';
import { useApp } from '../state';
import { useAccount } from './useAccount';

/** Health a change would leave: liquidation value over the new debt. */
function healthAfter(a: AccountView, debtAfter: bigint, liquidationValue = a.data.liquidationValue): { status: Status; label: string } {
  if (debtAfter <= 0n) return { status: 'nodebt', label: '\u221e' };
  const bps = (liquidationValue * 10_000n) / debtAfter;
  return { status: statusOf({ priceOk: a.data.priceOk, debt: debtAfter, healthFactorBps: bps }), label: healthNumber(bps) ?? '--' };
}

function HealthAfter({ h }: { h: { status: Status; label: string } }) {
  return (
    <div className="kv rule"><span>Health after</span>
      <span className="row" style={{ gap: 8 }}>
        {h.status !== 'nodebt' && <Num value={h.label} />}
        <Swap k={h.status}><Chip status={h.status} size="sm" /></Swap>
      </span>
    </div>
  );
}

/** A focused flow: Back and the screen's name in the header, no tab bar, the main action at the bottom (board 4, phone 2). */
function Flow({ title, children }: { title: string; children: ReactNode }) {
  const { wallet } = useApp();
  if (!wallet) return <Navigate to="/" replace />;
  return <Shell tabs={false} title={title} back="/account">{children}</Shell>;
}
function Bottom({ children }: { children: ReactNode }) {
  return <div className="stack" style={{ marginTop: 'auto', gap: 6, paddingTop: 8 }}>{children}</div>;
}
const Cancel = () => <Link to="/account" viewTransition className="btn link block">Cancel</Link>;
const Done = ({ label = 'Back to account' }: { label?: string }) => <Link to="/account" viewTransition className="btn cta block">{label}</Link>;
const Busy = () => <><span className="spin" aria-hidden="true" />Check your wallet</>;

/** S8 Borrow, before you sign. */
export function Borrow() {
  const { dep } = useApp();
  const { acct } = useAccount();
  const tx = useTx();
  const [text, setText] = useState('');
  const [firstSlip, setFirstSlip] = useState(false);
  if (!acct) return <Flow title="Borrow USDC"><FlowSkeleton /></Flow>;
  const d = acct.data;
  const max = d.priceOk ? (d.availableToBorrow < acct.poolLiquidity ? d.availableToBorrow : acct.poolLiquidity) : 0n;
  const amount = parseAmount(text, 6);
  const owedAfter = d.debt + (amount ?? 0n);
  const h = healthAfter(acct, owedAfter);
  const done = tx.stage === 'confirmed' || tx.stage === 'final';
  const error = !d.priceOk ? null : amount !== null && amount > max ? `Over your limit by ${fmtUsdc(amount - max)}. Most: ${fmtUsdc(max)}.` : null;
  const ready = amount !== null && amount > 0n && !error && d.priceOk && !tx.busy;

  const go = async () => {
    if (!ready || amount === null) return;
    const first = !tearSeen();
    if (await tx.run([{ address: dep.pool, abi: ABI.pool, functionName: 'borrow', args: [acct.key, amount] }])) setFirstSlip(first);
  };

  if (done) {
    return (
      <Flow title="Borrow USDC">
        <h1>Borrowed {text} USDC</h1>
        {firstSlip ? <TearOff /> : <Bubble>Done. Don't spend it all at once.</Bubble>}
        <TxSteps title={`Borrow ${text} USDC`} tx={tx} />
        <div className="card"><div className="kv"><span>You owe now</span><Num value={`${fmtUsdc(d.debt)} USDC`} /></div><HealthAfter h={healthAfter(acct, d.debt)} /></div>
        <Bottom><Done /></Bottom>
      </Flow>
    );
  }
  return (
    <Flow title="Borrow USDC">
      {!d.priceOk && <div className="banner paused" role="status">{Icon.pause}<div><b>Prices are paused</b><p>Borrowing is off until prices are back. Repaying still works.</p></div></div>}
      <Amount label="How much do you want to borrow?" unit="USDC" decimals={6} max={max} value={text} onChange={setText}
        maxLabel={`Most you can borrow: ${fmtUsdc(max)}`} disabled={!d.priceOk} error={error} fixLabel={`Use ${fmtUsdc(max)}`} onFix={() => setText((Number(max) / 1e6).toFixed(2))} />
      <div className="card">
        <div className="kv"><span>Interest rate</span><span className="num">{(Number(acct.borrowRateBps) / 100).toFixed(2)}% a year</span></div>
        <div className="kv"><span>You would owe</span><Num value={`${fmtUsdc(owedAfter)} USDC`} /></div>
        <div className="kv"><span>Pool has available</span><span className="num">{fmtUsdc(acct.poolLiquidity)} USDC</span></div>
        <HealthAfter h={h} />
      </div>
      <div className="note">{Icon.lock()}<span>Your Chog stays in its vault while you owe. If prices fall enough, others can repay your debt and take assets from the vault.</span></div>
      <TxSteps title={`Borrow ${text || '0'} USDC`} tx={tx} />
      <Bottom>
        <button className="btn cta block" disabled={!ready} onClick={go}>{tx.busy ? <Busy /> : amount ? `Borrow ${fmtUsdc(amount)} USDC` : 'Borrow'}</button>
        <Cancel />
      </Bottom>
    </Flow>
  );
}

/** S9 Repay. Works even while prices are paused. */
export function Repay() {
  const { dep } = useApp();
  const { acct } = useAccount();
  const tx = useTx();
  const [text, setText] = useState('');
  const [full, setFull] = useState(false);
  if (!acct) return <Flow title="Repay"><FlowSkeleton /></Flow>;
  const d = acct.data;
  const max = d.debt < acct.usdcWallet ? d.debt : acct.usdcWallet;
  const amount = parseAmount(text, 6);
  const isAll = amount !== null && amount >= d.debt && d.debt > 0n;
  const h = healthAfter(acct, isAll ? 0n : d.debt - (amount ?? 0n));
  const done = tx.stage === 'confirmed' || tx.stage === 'final';
  const error = amount !== null && amount > acct.usdcWallet ? `More than your wallet holds. Wallet: ${fmtUsdc(acct.usdcWallet)}.` : amount !== null && amount > d.debt ? `More than you owe. You owe ${fmtUsdc(d.debt)}.` : null;
  const ready = amount !== null && amount > 0n && !error && !tx.busy;

  const go = async (all = false) => {
    const pay = all ? d.debt : amount;
    if (pay === null || pay === 0n) return;
    const approve = all ? d.debt + d.debt / 100n + 1_000n : pay; // interest keeps accruing while the wallet signs
    const ok = await tx.run([
      { address: dep.mockUsdc, abi: ABI.erc20, functionName: 'approve', args: [dep.pool, approve] },
      { address: dep.pool, abi: ABI.pool, functionName: 'repay', args: [acct.key, all || pay >= d.debt ? 2n ** 256n - 1n : pay] },
    ], all || pay >= d.debt ? 'repaid' : 'confirmed');
    if (ok) setFull(all || pay >= d.debt);
  };

  if (done) {
    return (
      <Flow title="Repay">
        <h1>{full ? 'Debt-free.' : `Repaid ${text} USDC`}</h1>
        {full
          ? <div style={{ position: 'relative', alignSelf: 'flex-start', margin: '14px 0 6px' }}><Sparkles /><Bubble>Debt-free. Look at you.</Bubble></div>
          : null}
        <TxSteps title={full ? 'Repay all' : `Repay ${text} USDC`} tx={tx} />
        <div className="card"><div className="kv"><span>You owe now</span><Num value={`${fmtUsdc(d.debt)} USDC`} /></div><HealthAfter h={healthAfter(acct, d.debt)} /></div>
        <Bottom>{full ? <><Link to="/release" viewTransition className="btn cta block">Get your Chog back</Link><Link to="/account" viewTransition className="btn link block">Back to account</Link></> : <Done />}</Bottom>
      </Flow>
    );
  }
  if (d.debt === 0n) return <Flow title="Repay"><h1>Nothing to repay</h1><Bubble>Hm, what's in here?</Bubble><Bottom><Done /></Bottom></Flow>;
  return (
    <Flow title="Repay">
      <Amount label="How much do you want to repay?" unit="USDC" decimals={6} max={max} value={text} onChange={setText}
        maxLabel={`Most you can repay: ${fmtUsdc(max)}`} error={error} fixLabel={`Use ${fmtUsdc(max)}`} onFix={() => setText((Number(max) / 1e6).toFixed(2))} />
      <div className="card">
        <div className="kv"><span>You owe now</span><Num value={`${fmtUsdc(d.debt)} USDC`} /></div>
        <div className="kv"><span>Includes interest so far</span><span className="num">{(Number(acct.borrowRateBps) / 100).toFixed(2)}% a year</span></div>
        <div className="kv"><span>In your wallet</span><span className="num">{fmtUsdc(acct.usdcWallet)} USDC</span></div>
        <HealthAfter h={h} />
      </div>
      <TxSteps title={`Repay ${text || '0'} USDC`} tx={tx} />
      <Bottom>
        <button className="btn cta block" disabled={!ready} onClick={() => go(false)}>{tx.busy ? <Busy /> : amount ? `Repay ${fmtUsdc(amount)} USDC` : 'Repay'}</button>
        {acct.usdcWallet >= d.debt && <button className="btn secondary block" disabled={tx.busy} onClick={() => go(true)}>Repay all ({fmtUsdc(d.debt)} USDC)</button>}
        <Cancel />
      </Bottom>
    </Flow>
  );
}

function TokenSegment({ tokens, value, onChange }: { tokens: string[]; value: string; onChange(s: string): void }) {
  const i = Math.max(0, tokens.indexOf(value));
  return (
    <div className="segment" role="tablist" aria-label="Asset">
      <span className="thumb" aria-hidden="true" style={{ width: `calc((100% - 8px - ${(tokens.length - 1) * 4}px) / ${tokens.length})`, transform: `translateX(calc(${i * 100}% + ${i * 4}px))` }} />
      {tokens.map((t) => <button key={t} role="tab" aria-selected={t === value} onClick={() => onChange(t)}>{t}</button>)}
    </div>
  );
}

/** S6 Add assets. */
export function Add() {
  const { dep, pc, wallet, test } = useApp();
  const { acct } = useAccount();
  const tx = useTx();
  const faucetTx = useTx(); // its own tracker, so getting test tokens never looks like the deposit finished
  const [sym, setSym] = useState('WMON');
  const [text, setText] = useState('');
  const [gain, setGain] = useState(0n);
  const token = acct?.tokens.find((t) => t.symbol === sym);
  const amount = token ? parseAmount(text, token.decimals) : null;
  useEffect(() => {
    if (!token || amount === null) { setGain(0n); return; }
    let live = true;
    previewBorrowPowerGain(pc, dep, token.address, amount).then((g) => live && setGain(g)).catch(() => live && setGain(0n));
    return () => { live = false; };
  }, [pc, dep, token?.address, amount]); // eslint-disable-line react-hooks/exhaustive-deps
  if (!acct || !token || !wallet) return <Flow title="Add assets"><FlowSkeleton /></Flow>;

  const done = tx.stage === 'confirmed' || tx.stage === 'final';
  const error = amount !== null && amount > token.wallet ? `More than your wallet holds. Wallet: ${fmt(token.wallet, token.decimals)}.` : null;
  const ready = amount !== null && amount > 0n && !error && !tx.busy;
  const add = async () => {
    if (!ready || amount === null) return;
    if (await tx.run([
      { address: token.address, abi: ABI.erc20, functionName: 'approve', args: [acct.vault, amount] },
      { address: acct.vault, abi: ABI.vault, functionName: 'depositERC20', args: [token.address, amount] },
    ])) setText('');
  };
  const faucet = () => {
    const a = (s: string) => acct.tokens.find((x) => x.symbol === s)!.address;
    const mint = parseAbi(['function mint(address to, uint256 amount)']);
    return faucetTx.run([
      { address: a('WMON'), abi: mint, functionName: 'mint', args: [wallet.address, 100_000n * 10n ** 18n] },
      { address: a('USDC'), abi: parseAbi(['function faucet()']), functionName: 'faucet', args: [] },
      { address: a('$CHOG'), abi: mint, functionName: 'mint', args: [wallet.address, 1_000_000n * 10n ** 18n] },
    ]);
  };

  return (
    <Flow title="Add assets">
      <TokenSegment tokens={acct.tokens.map((t) => t.symbol)} value={sym} onChange={(s) => { setSym(s); setText(''); tx.reset(); }} />
      <Amount key={sym} label={`How much ${token.symbol} do you want to add?`} unit={token.symbol} decimals={token.decimals} max={token.wallet} value={text} onChange={setText}
        maxLabel={`In your wallet: ${fmt(token.wallet, token.decimals)}`} error={error} fixLabel="Use all" onFix={() => setText(String(Number(token.wallet) / 10 ** token.decimals))} />
      <div className="card">
        <div className="kv"><span>Borrow limit now</span><span className="num">{fmtUsdc(d0(acct))} USDC</span></div>
        <div className="kv"><span>After adding</span><Num value={`${fmtUsdc(d0(acct) + gain)} USDC`} /></div>
        {!token.counts && <div className="note small">{Icon.lock()}<span>{token.symbol} is held in the vault and travels with the Chog, but it does not count toward borrowing.</span></div>}
        {token.counts && <span className="tiny muted">An estimate. Per-account caps can count less.</span>}
      </div>
      <div className="note">{Icon.lock()}<span>Only you can take it back out, while the loan allows it.</span></div>
      <TxSteps title={done ? 'Added' : `Add ${text || '0'} ${token.symbol}`} tx={tx} />
      <Bottom>
        {test && token.wallet === 0n && <button className="btn secondary block" disabled={faucetTx.busy} onClick={faucet}>{faucetTx.busy ? <Busy /> : 'Get test tokens'}</button>}
        {done
          ? <Done />
          : <><button className="btn cta block" disabled={!ready} onClick={add}>{tx.busy ? <Busy /> : amount ? `Add ${fmt(amount, token.decimals)} ${token.symbol}` : 'Add assets'}</button><Cancel /></>}
      </Bottom>
    </Flow>
  );
}
const d0 = (a: AccountView) => a.data.borrowPower;

/** S10 Withdraw. The pool says how much may leave; the screen says why when it is less. */
export function Withdraw() {
  const { dep, pc, wallet } = useApp();
  const { acct } = useAccount();
  const tx = useTx();
  const held = useMemo(() => acct?.tokens.filter((t) => t.accounted > 0n) ?? [], [acct]);
  const [sym, setSym] = useState<string | null>(null);
  const token = held.find((t) => t.symbol === sym) ?? held[0];
  const [text, setText] = useState('');
  const [max, setMax] = useState<bigint | null>(null);
  useEffect(() => {
    if (!acct || !token) { setMax(null); return; }
    let live = true;
    maxWithdrawable(pc, dep, acct.key, token.address, token.accounted).then((m) => live && setMax(m));
    return () => { live = false; };
  }, [pc, dep, acct, token]);
  if (!acct || !wallet) return <Flow title="Withdraw"><FlowSkeleton /></Flow>;
  if (!token) return <Flow title="Withdraw"><h1>Nothing in the vault</h1><Bubble>Hm, what's in here?</Bubble><Bottom><Link to="/add" viewTransition className="btn cta block">Add assets</Link></Bottom></Flow>;

  const amount = parseAmount(text, token.decimals);
  const done = tx.stage === 'confirmed' || tx.stage === 'final';
  const limit = max ?? 0n;
  const error = amount !== null && max !== null && amount > limit
    ? (limit < token.accounted ? `That would leave the loan under-covered. Most you can take: ${fmt(limit, token.decimals)}.` : `More than the vault holds.`) : null;
  const ready = amount !== null && amount > 0n && !error && !tx.busy && max !== null;
  const go = async () => {
    if (!ready || amount === null) return;
    if (await tx.run([{ address: acct.vault, abi: ABI.vault, functionName: 'withdrawERC20', args: [token.address, amount, wallet.address] }])) setText('');
  };

  return (
    <Flow title="Withdraw">
      {held.length > 1 && <TokenSegment tokens={held.map((t) => t.symbol)} value={token.symbol} onChange={(s) => { setSym(s); setText(''); tx.reset(); }} />}
      <Amount key={token.symbol} label={`How much ${token.symbol} do you want to take out?`} unit={token.symbol} decimals={token.decimals} max={limit} value={text} onChange={setText}
        maxLabel={max === null ? 'Checking…' : `Most you can take: ${fmt(limit, token.decimals)}`} error={error} fixLabel="Use the most" onFix={() => setText(String(Number(limit) / 10 ** token.decimals))} />
      <div className="card">
        <div className="kv"><span>In the vault</span><span className="num">{fmt(token.accounted, token.decimals)} {token.symbol}</span></div>
        <div className="kv"><span>You owe</span><span className="num">{fmtUsdc(acct.data.debt)} USDC</span></div>
        {max !== null && max < token.accounted && <div className="note small">{Icon.lock()}<span>Part of it backs your loan. Repay some first to take more.</span></div>}
      </div>
      <TxSteps title={done ? 'Taken out' : `Withdraw ${text || '0'} ${token.symbol}`} tx={tx} />
      <Bottom>{done ? <Done /> : <><button className="btn cta block" disabled={!ready} onClick={go}>{tx.busy ? <Busy /> : amount ? `Withdraw ${fmt(amount, token.decimals)} ${token.symbol}` : 'Withdraw'}</button><Cancel /></>}</Bottom>
    </Flow>
  );
}

/** S11 Get your Chog back: zero debt and an empty vault, then release. */
export function Release() {
  const { dep, wallet } = useApp();
  const { acct, id } = useAccount();
  const tx = useTx();
  const nav = useNavigate();
  if (!acct || id === null || !wallet) return <Flow title="Release"><FlowSkeleton /></Flow>;
  const held = acct.tokens.filter((t) => t.accounted > 0n);
  const debt = acct.data.debt;
  const ready = debt === 0n && held.length === 0;
  const withdrawAll = () => tx.run(held.map((t) => ({ address: acct.vault, abi: ABI.vault, functionName: 'withdrawERC20', args: [t.address, t.accounted, wallet.address] })));
  const release = async () => {
    if (await tx.run([{ address: dep.escrow, abi: ABI.escrow, functionName: 'release', args: [dep.mockChogGenesis, BigInt(id), wallet.address] }])) {
      setTimeout(() => nav('/pick', { viewTransition: true }), 900);
    }
  };
  return (
    <Flow title="Release">
      <ChogFrame id={id} height={150} morph prop={ready ? 'key' : 'lock'} />
      <h1>Get your Chog back</h1>
      <div className="card">
        <div className="kv"><span>You owe</span><span className="row" style={{ gap: 8 }}><span className="num">{fmtUsdc(debt)} USDC</span>{debt === 0n && Icon.safeCheck()}</span></div>
        <div className="kv"><span>Still in the vault</span><span className="row" style={{ gap: 8 }}><span className="num">{held.length ? held.map((t) => `${fmt(t.accounted, t.decimals, 0)} ${t.symbol}`).join(', ') : 'Nothing'}</span>{held.length === 0 && Icon.safeCheck()}</span></div>
      </div>
      <div className="note">{Icon.lock()}<span>The Chog leaves its vault when you owe nothing and the vault is empty. The vault stays, ready for next time.</span></div>
      <TxSteps title="Release" tx={tx} />
      <Bottom>
        {debt > 0n && <Link to="/repay" viewTransition className="btn cta block">Repay first</Link>}
        {debt === 0n && held.length > 0 && <button className="btn cta block" disabled={tx.busy} onClick={withdrawAll}>{tx.busy ? <Busy /> : 'Withdraw all'}</button>}
        <button className={`btn block ${ready ? 'cta' : 'secondary'}`} disabled={tx.busy || !ready} onClick={release}>{ready ? 'Release Chog' : <>{Icon.lock()}Release Chog</>}</button>
        <Cancel />
      </Bottom>
    </Flow>
  );
}
