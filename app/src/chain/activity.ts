import type { Abi, AbiEvent, Address, Hex, PublicClient } from 'viem';
import { ABI } from './api';
import type { Deployment } from './config';
import { fmt, short } from './format';

export type Row = { id: string; block: bigint; hash: Hex; time: number; action: string; amount: string; final: boolean };

const ev = (abi: Abi, names: string[]) => abi.filter((e): e is AbiEvent => e.type === 'event' && names.includes(e.name));

/** The widest eth_getLogs range this node accepts. Public Monad RPCs allow 100 blocks; a local chain allows anything. */
let rangeCap = 50_000n;

/** Reads logs in windows no wider than the node allows, several windows at a time. */
async function logsInRange(pc: PublicClient, address: Address[], events: AbiEvent[], from: bigint, to: bigint) {
  const get = (f: bigint, t: bigint) => pc.getLogs({ address, events, fromBlock: f, toBlock: t });
  for (;;) {
    const windows: [bigint, bigint][] = [];
    for (let s = from; s <= to; s += rangeCap) windows.push([s, s + rangeCap - 1n > to ? to : s + rangeCap - 1n]);
    try {
      const out = [];
      for (let i = 0; i < windows.length; i += 8) out.push(...(await Promise.all(windows.slice(i, i + 8).map(([f, t]) => get(f, t)))).flat());
      return out;
    } catch (e) {
      const m = /limited to a (\d+) range/.exec(String((e as Error).message ?? e));
      const next = m ? BigInt(m[1]) : rangeCap / 10n;
      if (next >= rangeCap || next < 10n) throw e;
      rangeCap = next;
    }
  }
}

/** Everything that happened to one account, newest first. Status is Final once the block is below the finalized tag. */
export async function loadActivity(pc: PublicClient, dep: Deployment, key: Hex, vault: Address, me: Address, span: bigint): Promise<{ rows: Row[]; from: bigint; complete: boolean }> {
  const latest = await pc.getBlockNumber();
  const floor = BigInt(dep.deployBlock ?? 0);
  const from = latest - span > floor ? latest - span : floor;
  const sym = (t: string) => {
    const k = t.toLowerCase();
    if (k === dep.mockUsdc.toLowerCase()) return ['USDC', 6] as const;
    if (k === dep.mockWmon.toLowerCase()) return ['WMON', 18] as const;
    if (k === dep.mockChogToken.toLowerCase()) return ['$CHOG', 18] as const;
    return [short(t), 18] as const;
  };
  const amt = (t: string, v: bigint) => { const [s, d] = sym(t); return `${fmt(v, d)} ${s}`; };

  const keyed = await logsInRange(pc, [dep.registry, dep.escrow, dep.pool, dep.transferCoordinator], [
    ...ev(ABI.registry, ['AccountCreated']), ...ev(ABI.escrow, ['Escrowed', 'Released', 'BeneficialOwnerChanged']),
    ...ev(ABI.pool, ['Borrowed', 'Repaid', 'Liquidated']), ...ev(ABI.coordinator, ['SaleExecuted', 'DebtSaleExecuted']),
  ], from, latest);
  const vaulted = await logsInRange(pc, [vault], ev(ABI.vault, ['Deposited', 'Withdrawn', 'Received', 'Seized', 'PositionDeposited', 'PositionWithdrawn', 'PositionUnwound']), from, latest);

  const rows: Omit<Row, 'time' | 'final'>[] = [];
  for (const l of [...keyed, ...vaulted]) {
    const a = (l as unknown as { args: Record<string, unknown>; eventName: string }).args;
    const name = (l as unknown as { eventName: string }).eventName;
    if ('key' in a && (a.key as string).toLowerCase() !== key.toLowerCase()) continue;
    const base = { id: `${l.transactionHash}-${l.logIndex}`, block: l.blockNumber!, hash: l.transactionHash! };
    const v = (k: string) => a[k] as bigint;
    switch (name) {
      case 'AccountCreated': rows.push({ ...base, action: 'Vault opened', amount: '' }); break;
      case 'Escrowed': rows.push({ ...base, action: 'Chog went into its vault', amount: '' }); break;
      case 'Released': rows.push({ ...base, action: 'Chog came back', amount: '' }); break;
      case 'BeneficialOwnerChanged': {
        const to = (a.to as string).toLowerCase() === me.toLowerCase();
        rows.push({ ...base, action: to ? `Bought from ${short(a.from as string)}` : `Sold to ${short(a.to as string)}`, amount: '' });
        break;
      }
      case 'SaleExecuted': case 'DebtSaleExecuted': rows.push({ ...base, action: 'Sale price', amount: amt(a.paymentToken as string, v('price')) }); break;
      case 'Borrowed': rows.push({ ...base, action: 'Borrow', amount: amt(dep.mockUsdc, v('amount')) }); break;
      case 'Repaid': rows.push({ ...base, action: 'Repay', amount: amt(dep.mockUsdc, v('amount')) }); break;
      case 'Liquidated': rows.push({ ...base, action: 'Liquidation repaid', amount: amt(dep.mockUsdc, v('repaid')) }); break;
      case 'Deposited': rows.push({ ...base, action: `Add ${sym(a.token as string)[0]}`, amount: amt(a.token as string, v('amount')) }); break;
      case 'Withdrawn': rows.push({ ...base, action: `Withdraw ${sym(a.token as string)[0]}`, amount: amt(a.token as string, v('amount')) }); break;
      case 'Received': rows.push({ ...base, action: 'Payment counted', amount: amt(a.token as string, v('amount')) }); break;
      case 'Seized': rows.push({ ...base, action: 'Taken in liquidation', amount: amt(a.token as string, v('amount')) }); break;
      case 'PositionDeposited': rows.push({ ...base, action: `Add pool position #${v('tokenId')}`, amount: '' }); break;
      case 'PositionWithdrawn': rows.push({ ...base, action: `Withdraw pool position #${v('tokenId')}`, amount: '' }); break;
      case 'PositionUnwound': rows.push({ ...base, action: `Pool position #${v('tokenId')} unwound`, amount: '' }); break;
    }
  }
  let finalized = 0n;
  try { finalized = (await pc.getBlock({ blockTag: 'finalized' })).number; } catch { finalized = latest > 2n ? latest - 2n : 0n; }
  if (dep.chainId === 31337) finalized = latest > 2n ? latest - 2n : 0n; // a local chain has no finality tag worth trusting
  const blocks = [...new Set(rows.map((r) => r.block))];
  const times = new Map((await Promise.all(blocks.map((n) => pc.getBlock({ blockNumber: n })))).map((b) => [b.number, Number(b.timestamp)]));
  const out = rows
    .map((r) => ({ ...r, time: times.get(r.block) ?? 0, final: r.block <= finalized }))
    .sort((x, y) => (x.block === y.block ? (x.id < y.id ? 1 : -1) : x.block < y.block ? 1 : -1));
  return { rows: out, from, complete: from <= floor };
}
