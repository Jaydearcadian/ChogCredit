import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { parseAbi, type Address } from 'viem';
import { ABI } from '../chain/api';
import { short } from '../chain/format';
import { devWalletAllowed } from '../chain/wallet';
import { Shell } from '../components/chrome';
import { TxSteps, useTx } from '../components/tx';
import { cue, getPrefs, onPrefs, setPrefs } from '../feedback';
import { useApp } from '../state';

function Setting({ label, hint, on, set }: { label: string; hint: string; on: boolean; set(v: boolean): void }) {
  return (
    <div className="setting">
      <div className="stack" style={{ gap: 2 }}><span>{label}</span><span className="small muted">{hint}</span></div>
      <button role="switch" aria-checked={on} aria-label={label} className="switch" onClick={() => set(!on)} />
    </div>
  );
}

/** S20 Settings: sound off by default, risk sounds a separate switch, haptics on where the device supports them. */
export default function Settings() {
  const { wallet, dep, pc, test, disconnect } = useApp();
  const tx = useTx();
  const [p, setP] = useState(getPrefs());
  useEffect(() => onPrefs(() => setP(getPrefs())), []);
  const oracle = async (fn: string, args: unknown[]) => {
    const address = (await pc.readContract({ address: dep.pool, abi: ABI.pool, functionName: 'oracle' })) as Address;
    await tx.run([{ address, abi: parseAbi(['function setDown(bool d)', 'function setPrice(address token, uint256 priceRaw)']), functionName: fn, args }]);
  };
  return (
    <Shell>
      <h1>Settings</h1>
      <div className="card">
        <Setting label="Sound" hint="A tiny stamp for confirmations. Off by default." on={p.sound} set={(v) => { setPrefs({ sound: v, offered: true }); if (v) cue('bubble'); }} />
        <Setting label="Risk alert sounds" hint="Plays once when a loan gets risky. Off by default." on={p.riskSound} set={(v) => setPrefs({ riskSound: v })} />
        <Setting label="Haptics" hint="A short buzz on confirmations, errors and warnings, where supported. Off when your device asks for reduced motion." on={p.haptics} set={(v) => setPrefs({ haptics: v })} />
      </div>
      <div className="card">
        <div className="kv"><span>Network</span><span>{dep.chainId === 143 ? 'Monad' : dep.chainId === 10143 ? 'Monad testnet' : 'Local chain'}</span></div>
        <div className="kv"><span>Wallet</span><span className="num">{wallet ? short(wallet.address) : 'Not connected'}</span></div>
        {test && <span className="tiny muted">Test deployment: mock assets and a mock oracle.</span>}
      </div>
      {devWalletAllowed(dep.chainId) && (
        <div className="card dashed">
          <b>Test controls</b>
          <span className="small muted">Local chain only. Moves the mock oracle so the Pause Drill and the health states can be seen.</span>
          <div className="pair"><button className="btn quiet" onClick={() => oracle('setDown', [true])}>Pause prices</button><button className="btn quiet" onClick={() => oracle('setDown', [false])}>Resume prices</button></div>
          <div className="pair"><button className="btn quiet" onClick={() => oracle('setPrice', [dep.mockWmon, 9_000n])}>WMON price down</button><button className="btn quiet" onClick={() => oracle('setPrice', [dep.mockWmon, 20_000n])}>Reset price</button></div>
          <TxSteps title="Oracle" tx={tx} />
        </div>
      )}
      {wallet && <button className="btn secondary block" onClick={disconnect}>Disconnect wallet</button>}
      <Link to="/account" viewTransition className="small">Back to account</Link>
    </Shell>
  );
}
