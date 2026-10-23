import { useEffect, useState } from 'react';
import { Link, Navigate } from 'react-router-dom';
import { parseAbi } from 'viem';
import { ABI, previewBorrowPowerGain } from '../chain/api';
import { fmt, fmtPlain, fmtUsdc, parseAmount } from '../chain/format';
import { AmountField } from '../components/field';
import { Shell } from '../components/parts';
import { TxStrip, useTx } from '../components/tx';
import { useApp } from '../state';
import { useAccount } from './useAccount';

/** S6 Add assets */
export default function Add() {
  const { dep, pc, wallet, test, refresh } = useApp();
  const { acct } = useAccount();
  const tx = useTx();
  const [sym, setSym] = useState('WMON');
  const [text, setText] = useState('');
  const [gain, setGain] = useState(0n);
  const token = acct?.tokens.find((t) => t.symbol === sym);
  const amount = token ? parseAmount(text, token.decimals) : null;

  useEffect(() => {
    if (!token || amount === null) { setGain(0n); return; }
    previewBorrowPowerGain(pc, dep, token.address, amount).then(setGain).catch(() => setGain(0n));
  }, [pc, dep, token, amount]);

  if (!wallet) return <Navigate to="/" replace />;
  if (!acct || !token) return <Shell><p className="muted">Loading…</p></Shell>;

  const over = amount !== null && amount > token.wallet;
  const ready = amount !== null && amount > 0n && !over && !tx.busy;
  const add = async () => {
    if (!ready || amount === null) return;
    const ok = await tx.run([
      { address: token.address, abi: ABI.erc20, functionName: 'approve', args: [acct.vault, amount] },
      { address: acct.vault, abi: ABI.vault, functionName: 'depositERC20', args: [token.address, amount] },
    ]);
    if (ok) setText('');
  };
  /** Test deployments only: the mock tokens are open to mint. USDC has a faucet, the others an open mint. */
  const faucet = async () => {
    const t = (s: string) => acct.tokens.find((x) => x.symbol === s)!.address;
    const mint = parseAbi(['function mint(address to, uint256 amount)']);
    await tx.run([
      { address: t('WMON'), abi: mint, functionName: 'mint', args: [wallet.address, 100_000n * 10n ** 18n] },
      { address: t('USDC'), abi: parseAbi(['function faucet()']), functionName: 'faucet', args: [] },
      { address: t('$CHOG'), abi: mint, functionName: 'mint', args: [wallet.address, 1_000_000n * 10n ** 18n] },
    ]);
    refresh();
  };

  return (
    <Shell>
      <h1>Add to vault</h1>
      <div className="row" role="tablist" aria-label="Token" style={{ justifyContent: 'flex-start' }}>
        {acct.tokens.map((t) => (
          <button key={t.symbol} role="tab" aria-selected={sym === t.symbol} className={`btn ${sym === t.symbol ? '' : 'secondary'}`} style={{ minHeight: 44, padding: '0 14px' }} onClick={() => { setSym(t.symbol); setText(''); }}>{t.symbol}</button>
        ))}
      </div>
      <AmountField label={`Amount · wallet ${fmt(token.wallet, token.decimals)} ${token.symbol}`} value={text} onChange={setText}
        error={over ? 'More than your wallet holds.' : null} fix={over ? `Use ${fmt(token.wallet, token.decimals)}` : undefined}
        onFix={() => setText(fmtPlain(token.wallet, token.decimals))} onMax={() => setText(fmtPlain(token.wallet, token.decimals))} />
      <div className="card">
        <div className="row"><span className="small muted">Borrow limit now</span><span className="num">{fmtUsdc(acct.data.borrowPower)} USDC</span></div>
        <div className="row"><span className="small muted">After adding</span><b className="num">{fmtUsdc(acct.data.borrowPower + gain)} USDC</b></div>
        {!token.counts && <span className="small muted">{token.symbol} is held in the vault but does not count toward borrowing.</span>}
      </div>
      <p className="small muted" style={{ margin: 0 }}>Only you can withdraw this, while the loan allows it.</p>
      <button className="btn big" disabled={!ready} onClick={add}>{amount ? `Add ${text} ${token.symbol}` : 'Add assets'}</button>
      <TxStrip stage={tx.stage} step={tx.step} message={tx.message} />
      {test && token.wallet === 0n && <button className="btn secondary" onClick={faucet} disabled={tx.busy}>Get test tokens</button>}
      <Link to="/account" className="small">Back to account</Link>
    </Shell>
  );
}
