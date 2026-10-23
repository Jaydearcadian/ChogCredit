import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { Link, Navigate, useSearchParams } from 'react-router-dom';
import { isAddress, parseAbi, type Address, type Hex } from 'viem';
import { ABI, reason } from '../chain/api';
import { fmtUsdc, healthNumber, parseAmount, short } from '../chain/format';
import { buyerBounds, decode, fromStrings, linkTo, saleState, toStrings, typedData, type DebtAcceptance, type Offer, type Signed } from '../chain/sale';
import { statusOf } from '../chain/status';
import { Figure, TextField } from '../components/amount';
import { Bubble, ChogFrame, Icon } from '../components/brand';
import { Shell } from '../components/chrome';
import { FlowSkeleton } from '../components/moments';
import { Chip, Num } from '../components/status';
import { TxSteps, useTx } from '../components/tx';
import { cue } from '../feedback';
import { useApp } from '../state';
import { useAccount } from './useAccount';

const DAY = 24n * 60n * 60n;
const check = <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9" /><path d="M8 12.5l2.7 2.7L16 9.5" /></svg>;
const usd = (raw: bigint) => `$${fmtUsdc(raw)}`;

/** Equity first, in large mono: what the vault holds minus the loan (board 5). */
function Equity({ collateral, debt, title }: { collateral: bigint; debt: bigint; title: string }) {
  const equity = collateral > debt ? collateral - debt : 0n;
  return (
    <section className="card">
      <span className="small muted">{title}</span>
      <span style={{ fontSize: 36, lineHeight: 1.15 }}><Num value={usd(equity)} /></span>
      <span className="tiny muted">{usd(collateral)} in the vault{debt > 0n ? ` − ${usd(debt)} loan` : ', no loan'}</span>
    </section>
  );
}

/** What the buyer signs, in plain words. */
function WhatTheBuyerSigns({ maxDebt, minCollateral, minHealthBps, debt }: { maxDebt: bigint; minCollateral: bigint; minHealthBps: bigint; debt: boolean }) {
  return (
    <section className="card">
      <b>What the buyer signs</b>
      <ul className="signs">
        {debt && <li>{check}<span>The loan is at most <span className="num">{fmtUsdc(maxDebt)}</span> USDC</span></li>}
        <li>{check}<span>The vault holds at least <span className="num">{usd(minCollateral)}</span></span></li>
        {debt && <li>{check}<span>Health is at least <span className="num">{healthNumber(minHealthBps)}</span></span></li>}
        <li>{check}<span>Nothing is added to or taken out of the vault before the sale</span></li>
      </ul>
      <span className="tiny muted">If anything moves outside these limits before the sale goes through, it cannot complete. Nothing is lost; the buyer signs again.</span>
    </section>
  );
}

function ShareLink({ url, label, open }: { url: string; label: string; open?: string }) {
  const [copied, setCopied] = useState(false);
  const copy = async () => { try { await navigator.clipboard.writeText(url); setCopied(true); setTimeout(() => setCopied(false), 1600); } catch { /* clipboard blocked: the link is selectable */ } };
  return (
    <section className="card pop" aria-label={label}>
      <b>{label}</b>
      <div className="share"><code title={url}>{url}</code><button className="btn secondary" style={{ height: 40, padding: '0 14px' }} onClick={copy}>{copied ? 'Copied' : 'Copy'}</button></div>
      {open && <Link className="small" to={open}>Open it here</Link>}
    </section>
  );
}

function Need({ children }: { children: ReactNode }) {
  return <div className="banner watch" role="status">{Icon.alert}<div><b>Can't continue yet</b><p>{children}</p></div></div>;
}

/** Sell tab: the seller writes the offer. Nothing is sent on chain here. */
export function SellSetup() {
  const { wallet, dep, chogs } = useApp();
  const { acct, id } = useAccount();
  const [price, setPrice] = useState('');
  const [buyer, setBuyer] = useState('');
  const [payoff, setPayoff] = useState(false);
  const [repayText, setRepayText] = useState('');
  const [link, setLink] = useState<string | null>(null);
  if (!wallet) return <Navigate to="/" replace />;
  if (chogs && id === null) return <Shell><h1>Sell with Vault</h1><div className="card"><b>No Chog in a vault yet.</b><span className="small muted">Open a vault first; then the whole vault can be sold with the Chog.</span><Link to="/pick" className="btn">Pick a Chog</Link></div></Shell>;
  if (!acct || id === null) return <Shell enter={false}><FlowSkeleton /></Shell>;

  const d = acct.data;
  const hasDebt = d.debt > 0n;
  const status = statusOf(d);
  const p = parseAmount(price, 6);
  const repay = hasDebt && payoff ? parseAmount(repayText, 6) ?? 0n : 0n;
  const bounds = buyerBounds(d, repay);
  const buyerErr = buyer === '' ? null : !isAddress(buyer) ? 'That is not a wallet address.' : buyer.toLowerCase() === wallet.address.toLowerCase() ? 'The buyer has to be someone else.' : null;
  const repayErr = repay > d.debt ? `More than the loan (${fmtUsdc(d.debt)}).` : p !== null && repay > p ? 'More than the price.' : null;
  const blocked = hasDebt && !d.priceOk ? 'Prices are paused. A sale with a loan needs live prices, so it waits.' : status === 'danger' ? 'This account can be liquidated right now, so it cannot be sold. Repay or add assets first.' : null;
  const ready = !blocked && p !== null && p > 0n && isAddress(buyer) && !buyerErr && !repayErr;

  const make = () => {
    if (!ready || p === null) return;
    const offer: Offer = {
      v: 1, chainId: dep.chainId, coordinator: dep.transferCoordinator, key: acct.key, id, seller: wallet.address, buyer: buyer as Address,
      paymentToken: dep.mockUsdc, price: p.toString(), debtRepay: repay.toString(),
      deadline: (BigInt(Math.floor(Date.now() / 1000)) + DAY).toString(), salt: BigInt(Math.floor(Math.random() * 2 ** 48)).toString(),
    };
    setLink(linkTo('/sell/sign', 'o', offer));
    cue('bubble');
  };

  return (
    <Shell>
      <h1>{hasDebt ? 'Sell this Chog with its loan' : 'Sell this Chog with its vault'}</h1>
      <ChogFrame id={id} height={120} morph />
      <Equity collateral={d.collateralValue} debt={d.debt} title="The buyer gets the equity" />
      {blocked && <Need>{blocked}</Need>}
      <Figure label="Price the buyer pays" unit="USDC" value={price} onChange={(v) => { setPrice(v); setLink(null); }} hint="Your call. We never suggest a price." />
      <TextField label="Buyer's wallet" placeholder="0x…" value={buyer} onChange={(v) => { setBuyer(v); setLink(null); }} error={buyerErr} />
      {hasDebt && (
        <section className="card">
          <div className="toggle-row"><span>Pay off part of the loan from the price</span><button role="switch" aria-checked={payoff} aria-label="Pay off part of the loan from the price" className="switch" onClick={() => { setPayoff(!payoff); setLink(null); }} /></div>
          {payoff && <Figure label="Goes to repay the loan" unit="USDC" value={repayText} onChange={(v) => { setRepayText(v); setLink(null); }} error={repayErr} />}
          <div className="kv rule"><span>Price the buyer pays</span><span className="num">{fmtUsdc(p ?? 0n)} USDC</span></div>
          {payoff && <div className="kv"><span>Goes to repay the loan</span><span className="num">− {fmtUsdc(repay)} USDC</span></div>}
          <div className="kv"><span>You receive</span><Num value={`${fmtUsdc((p ?? 0n) > repay ? (p ?? 0n) - repay : 0n)} USDC`} /></div>
          <div className="kv"><span>Loan the buyer takes over</span><Num value={`${fmtUsdc(bounds.debtAfter)} USDC`} /></div>
        </section>
      )}
      <WhatTheBuyerSigns maxDebt={bounds.maxDebt} minCollateral={bounds.minCollateralValue} minHealthBps={bounds.minHealthBps} debt={hasDebt} />
      {hasDebt && <div className="note">{Icon.lock()}<span>The buyer will take over a loan. If prices fall enough, others can repay it and take assets from this vault. The Chog never leaves its vault in the sale.</span></div>}
      <div className="note">{Icon.lock()}<span>Your account is not frozen. Adding or taking out anything voids the buyer's signature, and they sign again.</span></div>
      {link
        ? <ShareLink url={link} label="Send this link to the buyer" open={import.meta.env.DEV ? link.replace(location.origin, '') : undefined} />
        : <button className="btn cta block" disabled={!ready} onClick={make}>Ask the buyer to sign</button>}
      {chogs && <span className="tiny muted">The link holds the terms only. The buyer signs, then sends you a link back to complete the sale.</span>}
    </Shell>
  );
}

/** The buyer's screen: live account, what they take on, approve the payment, sign. */
export function SellSign() {
  const { wallet, dep, pc, connect, test } = useApp();
  const [params] = useSearchParams();
  const offer = useMemo(() => decode<Offer>(params.get('o')), [params]);
  const tx = useTx();
  const faucetTx = useTx();
  const [live, setLive] = useState<Awaited<ReturnType<typeof saleState>> | null>(null);
  const [funds, setFunds] = useState<{ bal: bigint; allowance: bigint } | null>(null);
  const [signed, setSigned] = useState<string | null>(null);
  const [signErr, setSignErr] = useState<string | null>(null);
  const [signing, setSigning] = useState(false);

  useEffect(() => {
    if (!offer || !wallet) return;
    let on = true;
    const load = async () => {
      const s = await saleState(pc, dep, offer.key);
      const [bal, allowance] = await Promise.all([
        pc.readContract({ address: offer.paymentToken, abi: ABI.erc20, functionName: 'balanceOf', args: [wallet.address] }) as Promise<bigint>,
        pc.readContract({ address: offer.paymentToken, abi: ABI.erc20, functionName: 'allowance', args: [wallet.address, offer.coordinator] }) as Promise<bigint>,
      ]);
      if (on) { setLive(s); setFunds({ bal, allowance }); }
    };
    load().catch(() => undefined);
    const t = setInterval(() => load().catch(() => undefined), 5000);
    return () => { on = false; clearInterval(t); };
  }, [offer, wallet, pc, dep, tx.stage, faucetTx.stage]);

  const title = 'Buy a Chog with its vault';
  if (!offer) return <Shell tabs={false} title="Offer"><Need>This link is not a valid offer. Ask the seller for a new one.</Need></Shell>;
  if (offer.chainId !== dep.chainId || offer.coordinator.toLowerCase() !== dep.transferCoordinator.toLowerCase()) return <Shell tabs={false} title="Offer"><Need>This offer is for a different network or deployment.</Need></Shell>;
  if (!wallet) return (
    <Shell tabs={false} title="Offer">
      <h1>{title}</h1>
      <p className="muted">Chog #{offer.id}. Connect the buyer's wallet ({short(offer.buyer)}) to review and sign.</p>
      <button className="btn cta block" onClick={connect}>Connect wallet</button>
    </Shell>
  );
  if (wallet.address.toLowerCase() !== offer.buyer.toLowerCase()) return <Shell tabs={false} title="Offer"><Need>This offer is for {short(offer.buyer)}. You are connected as {short(wallet.address)}.</Need></Shell>;
  if (!live || !funds) return <Shell tabs={false} title="Offer" enter={false}><FlowSkeleton /></Shell>;

  const d = live.data;
  const price = BigInt(offer.price), repay = BigInt(offer.debtRepay), deadline = BigInt(offer.deadline);
  const hasDebt = d.debt > 0n;
  const b = buyerBounds(d, repay);
  const status = hasDebt ? statusOf({ priceOk: d.priceOk, debt: b.debtAfter, healthFactorBps: b.healthAfter }) : 'nodebt';
  const expired = BigInt(Math.floor(Date.now() / 1000)) > deadline;
  const problem = live.owner.toLowerCase() !== offer.seller.toLowerCase() ? 'The seller no longer holds this Chog.'
    : expired ? 'This offer ran out of time. Ask the seller for a new one.'
    : hasDebt && !d.priceOk ? 'Prices are paused. A sale with a loan needs live prices; try again when they are back.'
    : hasDebt && d.healthFactorBps < 10_000n ? 'This account can be liquidated right now, so it cannot be sold.'
    : repay > d.debt ? 'The offer repays more than the loan. Ask the seller for a new one.' : null;
  const short_ = funds.bal < price;
  const needsApproval = funds.allowance < price;

  const approve = () => tx.run([{ address: offer.paymentToken, abi: ABI.erc20, functionName: 'approve', args: [offer.coordinator, price] }]);
  const faucet = () => faucetTx.run([{ address: offer.paymentToken, abi: parseAbi(['function faucet()']), functionName: 'faucet', args: [] }]);
  const sign = async () => {
    setSignErr(null); setSigning(true);
    try {
      const base = { key: offer.key, seller: offer.seller, buyer: offer.buyer, paymentToken: offer.paymentToken, price, stateNonce: live.nonce, epoch: live.epoch, deadline, salt: BigInt(offer.salt) };
      const kind = hasDebt ? 'debt' : 'plain';
      const message = hasDebt ? { ...base, pool: dep.pool, maxDebt: b.maxDebt, minCollateralValue: b.minCollateralValue, minHealthBps: b.minHealthBps, debtRepay: repay } : base;
      const sig = (await wallet.client.signTypedData({ account: wallet.account, ...typedData(dep.chainId, offer.coordinator, kind, message) } as never)) as Hex;
      const payload: Signed = { v: 1, chainId: dep.chainId, coordinator: offer.coordinator, id: offer.id, kind, a: toStrings(message), sig };
      setSigned(linkTo('/sell/complete', 's', payload));
      cue('confirmed');
    } catch (e) { setSignErr(reason(e)); cue('error'); } finally { setSigning(false); }
  };

  return (
    <Shell tabs={false} title="Offer">
      <h1>{hasDebt ? 'Buy a Chog with its loan' : title}</h1>
      <ChogFrame id={offer.id} height={120} />
      {!signed && <Bubble>Let's check the numbers.</Bubble>}
      <Equity collateral={d.collateralValue} debt={d.debt} title="You get the equity" />
      {problem && <Need>{problem}</Need>}
      <section className="card">
        <div className="kv"><span>You pay</span><span className="num">{fmtUsdc(price)} USDC</span></div>
        {repay > 0n && <div className="kv"><span>Of that, repays the loan</span><span className="num">{fmtUsdc(repay)} USDC</span></div>}
        <div className="kv"><span>You take on</span><Num value={hasDebt ? `${fmtUsdc(b.debtAfter)} USDC loan` : 'No loan'} /></div>
        <div className="kv"><span>From</span><span className="num">{short(offer.seller)}</span></div>
        {hasDebt && <div className="kv rule"><span>Health after</span><span className="row" style={{ gap: 8 }}><span className="num">{healthNumber(b.healthAfter)}</span><Chip status={status} size="sm" /></span></div>}
      </section>
      <WhatTheBuyerSigns maxDebt={b.maxDebt} minCollateral={b.minCollateralValue} minHealthBps={b.minHealthBps} debt={hasDebt} />
      {hasDebt && <div className="note">{Icon.lock()}<span>You will take over a loan. If prices fall enough, others can repay it and take assets from this vault.</span></div>}
      <div className="note">{Icon.lock()}<span>Signing costs nothing and moves nothing. Your USDC only moves if the seller completes the sale, on exactly these terms, before {new Date(Number(deadline) * 1000).toLocaleString()}.</span></div>

      {signed ? (
        <>
          <ShareLink url={signed} label="Signed. Send this link back to the seller" open={import.meta.env.DEV ? signed.replace(location.origin, '') : undefined} />
        </>
      ) : (
        <>
          <TxSteps title="Approve the payment" tx={tx} />
          {short_ && test && <button className="btn secondary block" disabled={faucetTx.busy} onClick={faucet}>Get test USDC</button>}
          {short_ && !test && <Need>Your wallet holds {fmtUsdc(funds.bal)} USDC. The price is {fmtUsdc(price)}.</Need>}
          {signErr && <div className="banner danger" role="alert">{Icon.alert}<div><b>Not signed</b><p>{signErr}</p></div></div>}
          <div className="stack" style={{ gap: 8 }}>
            {needsApproval
              ? <button className="btn cta block" disabled={!!problem || short_ || tx.busy} onClick={approve}>{tx.busy ? 'Check your wallet' : `1 · Allow ${fmtUsdc(price)} USDC for this sale`}</button>
              : <button className="btn cta block" disabled={!!problem || short_ || signing} onClick={sign}>{signing ? 'Check your wallet' : '2 · Sign these terms'}</button>}
            <span className="tiny muted">{needsApproval ? 'Step 1 lets the sale contract take the price, only when the seller completes the sale.' : 'Step 2 is a signature, not a transaction.'}</span>
          </div>
        </>
      )}
    </Shell>
  );
}

/** The seller's last step: check the buyer's signature against the live account, then complete the sale. */
export function SellComplete() {
  const { wallet, dep, pc, connect, refresh } = useApp();
  const [params] = useSearchParams();
  const s = useMemo(() => decode<Signed>(params.get('s')), [params]);
  const tx = useTx();
  const [live, setLive] = useState<{ st: Awaited<ReturnType<typeof saleState>>; used: boolean; bal: bigint; allowance: bigint } | null>(null);
  const a = useMemo(() => (s ? fromStrings(s.kind, s.a) : null), [s]);

  useEffect(() => {
    if (!s || !a) return;
    let on = true;
    const load = async () => {
      const st = await saleState(pc, dep, a.key);
      const digest = (await pc.readContract({ address: s.coordinator, abi: ABI.coordinator, functionName: s.kind === 'plain' ? 'hashAcceptance' : 'hashDebtAcceptance', args: [a] })) as Hex;
      const [used, bal, allowance] = await Promise.all([
        pc.readContract({ address: s.coordinator, abi: ABI.coordinator, functionName: 'used', args: [digest] }) as Promise<boolean>,
        pc.readContract({ address: a.paymentToken, abi: ABI.erc20, functionName: 'balanceOf', args: [a.buyer] }) as Promise<bigint>,
        pc.readContract({ address: a.paymentToken, abi: ABI.erc20, functionName: 'allowance', args: [a.buyer, s.coordinator] }) as Promise<bigint>,
      ]);
      if (on) setLive({ st, used, bal, allowance });
    };
    load().catch(() => undefined);
    const t = setInterval(() => load().catch(() => undefined), 5000);
    return () => { on = false; clearInterval(t); };
  }, [s, a, pc, dep, tx.stage]);

  if (!s || !a) return <Shell tabs={false} title="Complete sale"><Need>This link is not a valid signed offer.</Need></Shell>;
  if (s.chainId !== dep.chainId) return <Shell tabs={false} title="Complete sale"><Need>This signature is for a different network.</Need></Shell>;
  if (!wallet) return <Shell tabs={false} title="Complete sale"><h1>Complete the sale</h1><p className="muted">Connect the seller's wallet ({short(a.seller)}).</p><button className="btn cta block" onClick={connect}>Connect wallet</button></Shell>;
  if (wallet.address.toLowerCase() !== a.seller.toLowerCase()) return <Shell tabs={false} title="Complete sale"><Need>Only the seller ({short(a.seller)}) can complete this sale. You are {short(wallet.address)}.</Need></Shell>;
  const done = tx.stage === 'confirmed' || tx.stage === 'final';
  if (!live && !done) return <Shell tabs={false} title="Complete sale" enter={false}><FlowSkeleton /></Shell>;

  if (done) {
    return (
      <Shell tabs={false} title="Sold">
        <ChogFrame id={s.id} height={150} prop="key" />
        <h1>Done. Chog #{s.id} has a new keeper.</h1>
        <section className="card">
          <div className="kv"><span>You received</span><span className="num">{fmtUsdc(a.price - (s.kind === 'debt' ? (a as DebtAcceptance).debtRepay : 0n))} USDC</span></div>
          <div className="kv"><span>The buyer</span><span className="num">{short(a.buyer)}</span></div>
        </section>
        <TxSteps title="Sale" tx={tx} />
        <div style={{ marginTop: 'auto' }}><Link to="/pick" viewTransition className="btn cta block" onClick={() => refresh()}>Back to your Chogs</Link></div>
      </Shell>
    );
  }

  const { st } = live!;
  const now = BigInt(Math.floor(Date.now() / 1000));
  const debtTerms = s.kind === 'debt' ? (a as DebtAcceptance) : null;
  const checks: [boolean, string, string][] = [
    [st.owner.toLowerCase() === a.seller.toLowerCase(), 'You still hold this Chog', 'This Chog changed hands.'],
    [st.nonce === a.stateNonce, 'The vault is as the buyer saw it', 'The vault changed after the buyer signed. Ask them to sign again.'],
    [st.epoch === a.epoch, 'Ownership has not moved since', 'Ownership moved since the buyer signed.'],
    [now <= a.deadline, 'The offer is in time', 'The offer ran out of time.'],
    [!live!.used, 'The signature is unused', 'This signature was already used or cancelled.'],
    [live!.bal >= a.price && live!.allowance >= a.price, "The buyer's payment is ready", "The buyer's wallet has not allowed or does not hold the price."],
  ];
  if (debtTerms) {
    const d = st.data;
    const after = d.debt > debtTerms.debtRepay ? d.debt - debtTerms.debtRepay : 0n;
    checks.push([d.priceOk, 'Prices are live', 'Prices are paused.']);
    checks.push([after <= debtTerms.maxDebt, 'The loan is within what the buyer agreed', 'The loan is above what the buyer agreed.']);
    checks.push([d.collateralValue >= debtTerms.minCollateralValue, 'The vault value is within what the buyer agreed', 'The vault is worth less than the buyer agreed.']);
  }
  const failing = checks.filter(([ok]) => !ok);
  const execute = () => tx.run([{ address: s.coordinator, abi: ABI.coordinator, functionName: s.kind === 'plain' ? 'executeSale' : 'executeDebtSale', args: [a, s.sig] }]);

  return (
    <Shell tabs={false} title="Complete sale">
      <h1>The buyer signed</h1>
      <ChogFrame id={s.id} height={120} />
      <section className="card">
        <div className="kv"><span>Price</span><span className="num">{fmtUsdc(a.price)} USDC</span></div>
        {debtTerms && debtTerms.debtRepay > 0n && <div className="kv"><span>Goes to repay the loan</span><span className="num">− {fmtUsdc(debtTerms.debtRepay)} USDC</span></div>}
        <div className="kv"><span>You receive</span><span className="num">{fmtUsdc(a.price - (debtTerms?.debtRepay ?? 0n))} USDC</span></div>
        <div className="kv"><span>Buyer</span><span className="num">{short(a.buyer)}</span></div>
      </section>
      <section className="card">
        <b>Checked just now</b>
        <ul className="signs">
          {checks.map(([ok, yes, no]) => <li key={yes} style={ok ? undefined : { color: 'var(--risk)' }}>{ok ? check : Icon.alert}<span style={{ color: 'var(--text)' }}>{ok ? yes : no}</span></li>)}
        </ul>
      </section>
      <TxSteps title="Sale" tx={tx} />
      <div className="stack" style={{ marginTop: 'auto', gap: 6 }}>
        <button className="btn cta block" disabled={failing.length > 0 || tx.busy} onClick={execute}>{tx.busy ? 'Check your wallet' : `Complete sale · get ${fmtUsdc(a.price - (debtTerms?.debtRepay ?? 0n))} USDC`}</button>
        <Link to="/account" viewTransition className="btn link block">Not now</Link>
      </div>
    </Shell>
  );
}
