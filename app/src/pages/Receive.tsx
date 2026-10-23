import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { type Address } from 'viem';
import { ABI } from '../chain/api';
import { fmt, fmtUsdc, short } from '../chain/format';
import { Bubble, ChogFrame, Icon } from '../components/brand';
import { ConnectGate, Shell } from '../components/chrome';
import { FlowSkeleton, Skel } from '../components/moments';
import { Qr } from '../components/qr';
import { Num } from '../components/status';
import { TxSteps, useTx } from '../components/tx';
import { useApp } from '../state';
import { useAccount } from './useAccount';

function CopyRow({ value, label }: { value: string; label: string }) {
  const [copied, setCopied] = useState(false);
  const copy = async () => { try { await navigator.clipboard.writeText(value); setCopied(true); setTimeout(() => setCopied(false), 1600); } catch { /* clipboard blocked: the text is selectable */ } };
  return (
    <div className="share" aria-label={label}><code title={value}>{value}</code><button className="btn secondary" style={{ height: 40, padding: '0 14px' }} onClick={copy}>{copied ? 'Copied' : 'Copy'}</button></div>
  );
}

/** S22 Get paid: a link and QR that let anyone pay USDC to this Chog's vault, and one tap to count what arrived. */
export default function Receive() {
  const { wallet, test } = useApp();
  const { acct, id, loading, browsing } = useAccount();
  const tx = useTx();
  if (loading || !acct || id === null) return <Shell enter={false}><FlowSkeleton /></Shell>;
  const link = `${location.origin}/pay/${id}`;
  const waiting = acct.tokens.filter((t) => t.waiting > 0n);
  const done = tx.stage === 'confirmed' || tx.stage === 'final';
  const claim = (address: Address) => tx.run([{ address: acct.vault, abi: ABI.vault, functionName: 'claimReceived', args: [address] }]);
  const gain = (sym: string) => (sym === 'WMON' ? 'It counts toward your limit.' : 'It is held in the vault. It does not count toward your limit.');

  return (
    <Shell>
      <h1>Get paid</h1>
      <p className="muted" style={{ margin: 0 }}>Anyone can pay USDC to Chog #{id}'s vault from any wallet or exchange. You decide what counts, with one tap.</p>
      <section className="card" style={{ alignItems: 'stretch' }}>
        <div className="row" style={{ justifyContent: 'flex-start', gap: 16, alignItems: 'center' }}>
          <Qr text={link} label={`QR code for the payment page of Chog ${id}`} />
          <div className="stack" style={{ gap: 6 }}>
            <b>Pay Chog #{id}</b>
            <span className="small muted">Share the link or the QR. It opens a page that shows where to send.</span>
          </div>
        </div>
        <CopyRow value={link} label="Payment link" />
        <span className="tiny muted">Vault address</span>
        <CopyRow value={acct.vault} label="Vault address" />
      </section>
      <div className="banner paused" role="note" style={{ borderStyle: 'dashed' }}>{Icon.lock()}<div><b>USDC only</b><p>Other tokens can't be counted. Native MON can't be sent to a vault at all. Anything else that arrives stays unaccounted until you take it back.</p></div></div>

      {browsing && <ConnectGate action="add what arrived" back="/account" />}
      {!browsing && (
        <>
          <h2>Waiting to add</h2>
          {waiting.length === 0 && !done && <div className="card dashed"><span className="small muted">Nothing waiting. When a payment arrives it shows here.</span></div>}
          {waiting.map((t) => (
            <section className="card" key={t.symbol}>
              <div className="row"><b>{t.symbol}</b><span className="small muted">arrived, not counted yet</span></div>
              <Num value={`${t.decimals === 6 ? fmtUsdc(t.waiting) : fmt(t.waiting, t.decimals)} ${t.symbol}`} />
              <span className="tiny muted">{gain(t.symbol)} Adding it changes the vault, so an open sale offer will need the buyer's signature again.</span>
              <button className="btn cta block" disabled={tx.busy} onClick={() => claim(t.address)}>{tx.busy ? 'Check your wallet' : `Add to vault`}</button>
            </section>
          ))}
          <TxSteps title="Add to vault" tx={tx} />
          {done && <Bubble>Counted. Check your limit on the account.</Bubble>}
          {test && wallet && <p className="tiny muted" style={{ margin: 0 }}>Test deployment: to try it, send some mock USDC to the vault address from another wallet.</p>}
        </>
      )}
      <Link to="/account" viewTransition className="small">Back to account</Link>
    </Shell>
  );
}

/** S25 The payer's page: where to send, and what they are paying. No wallet needed to look. */
export function Pay() {
  const { dep, pc } = useApp();
  const id = Number(useParams().id);
  const [info, setInfo] = useState<{ address: Address; open: boolean } | null>(null);
  useEffect(() => {
    let live = true;
    (async () => {
      const [vault, predicted] = await Promise.all([
        pc.readContract({ address: dep.registry, abi: ABI.registry, functionName: 'vaultOf', args: [dep.mockChogGenesis, BigInt(id)] }) as Promise<Address>,
        pc.readContract({ address: dep.registry, abi: ABI.registry, functionName: 'predictVault', args: [dep.mockChogGenesis, BigInt(id)] }) as Promise<Address>,
      ]);
      const open = vault !== '0x0000000000000000000000000000000000000000';
      if (live) setInfo({ address: open ? vault : predicted, open });
    })().catch(() => live && setInfo(null));
    return () => { live = false; };
  }, [pc, dep, id]);
  const usdc = dep.mockUsdc;
  return (
    <Shell tabs={false} register="chog" title="Pay a Chog" back="/">
      <h1 className="display" style={{ fontSize: 40 }}>Pay Chog #{id}</h1>
      <ChogFrame id={id} height={110} />
      {info === null ? <Skel h={220} /> : (
        <section className="card" style={{ alignItems: 'stretch' }}>
          <div className="kv"><span>Send</span><b>USDC</b></div>
          <div className="kv"><span>On</span><b>{dep.chainId === 143 ? 'Monad' : dep.chainId === 10143 ? 'Monad testnet' : 'Local chain'}</b></div>
          <span className="tiny muted">To this address</span>
          <CopyRow value={info.address} label="Address to send to" />
          <div className="row" style={{ justifyContent: 'center', padding: '8px 0' }}><Qr text={info.address} label={`QR code for the address ${short(info.address)}`} size={176} /></div>
          <span className="tiny muted">USDC token on this network: <span className="num">{short(usdc)}</span></span>
        </section>
      )}
      <div className="card">
        <div className="note small">{Icon.lock()}<span>This pays whoever holds Chog #{id}'s vault. {info?.open === false ? "The vault isn't open yet; the address is fixed, so a payment sent now is kept for whoever opens it." : 'If the Chog changes hands, payments go to the new keeper.'}</span></div>
        <div className="note small">{Icon.alert}<span>Send only USDC on this network. Other tokens may not be recoverable. Native MON can't be sent here.</span></div>
      </div>
      <Link to="/explore" className="small">Look at the Chog's vault</Link>
    </Shell>
  );
}
