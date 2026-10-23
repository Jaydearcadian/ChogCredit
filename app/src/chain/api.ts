import type { Abi, Address, Hex, PublicClient } from 'viem';
import { parseAbi, zeroAddress } from 'viem';
import vaultAbi from '../abi/AccountVault.json';
import registryAbi from '../abi/ChogAccountRegistry.json';
import escrowAbi from '../abi/ChogCreditEscrow.json';
import poolAbi from '../abi/ChogCreditPool.json';
import chogAbi from '../abi/MockChogGenesis.json';
import erc20Abi from '../abi/ERC20Mock.json';
import coordinatorAbi from '../abi/AccountTransferCoordinator.json';
import pmAbi from '../abi/PositionManager.json';
import { hasPositions, type Deployment } from './config';
import type { Wallet } from './wallet';

export const ABI = {
  vault: vaultAbi as Abi, registry: registryAbi as Abi, escrow: escrowAbi as Abi,
  pool: poolAbi as Abi, chog: chogAbi as Abi, erc20: erc20Abi as Abi, coordinator: coordinatorAbi as Abi, pm: pmAbi as Abi,
};

export type PoolAccount = {
  priceOk: boolean; debt: bigint; collateralValue: bigint; borrowPower: bigint;
  liquidationValue: bigint; healthFactorBps: bigint; availableToBorrow: bigint;
};

export type ChogState = 'novault' | 'wallet' | 'escrowed' | 'elsewhere';
export type ChogRow = { id: number; key: Hex; state: ChogState; vault: Address | null };

export type TokenRow = { symbol: string; address: Address; decimals: number; counts: boolean; accounted: bigint; waiting: bigint; wallet: bigint };

/** A Uniswap V3 position: what it is and what the pool would count it for. */
export type PositionRow = { id: bigint; pair: string; fee: number; value: bigint; valueOk: boolean; accepted: boolean; withdrawAllowed?: boolean };

export type AccountView = {
  positions: PositionRow[];
  id: number; key: Hex; vault: Address; escrowed: boolean; data: PoolAccount; tokens: TokenRow[];
  usdcWallet: bigint; borrowRateBps: bigint; poolLiquidity: bigint; releaseBlocker: number; stateNonce: bigint;
};

type Call = { address: Address; abi: Abi; functionName: string; args: unknown[] };
/** Many reads at once. JSON-RPC batching (see wallet.ts) sends them in one request, so no Multicall3 is needed (local chains lack it). */
async function many(pc: PublicClient, calls: Call[]): Promise<PromiseSettledResult<unknown>[]> {
  return Promise.allSettled(calls.map((c) => pc.readContract(c)));
}
const val = <T,>(r: PromiseSettledResult<unknown>): T => { if (r.status === 'rejected') throw r.reason; return r.value as T; };

const read = <T,>(pc: PublicClient, address: Address, abi: Abi, functionName: string, args: unknown[] = []) =>
  pc.readContract({ address, abi, functionName, args }) as Promise<T>;

/** Which Chogs does this wallet hold, or hold the key to? Scans ids 1..totalSupply (capped) with batched reads. */
export async function loadChogs(pc: PublicClient, dep: Deployment, user: Address): Promise<ChogRow[]> {
  const total = Number(await read<bigint>(pc, dep.mockChogGenesis, ABI.chog, 'totalSupply'));
  const ids = Array.from({ length: Math.min(total, 2500) }, (_, i) => i + 1);
  const owners = await many(pc, ids.map((id) => ({ address: dep.mockChogGenesis, abi: ABI.chog, functionName: 'ownerOf', args: [BigInt(id)] })));
  const candidates = ids.filter((_, i) => {
    const r = owners[i];
    if (r.status !== 'fulfilled') return false;
    const o = (r.value as string).toLowerCase();
    return o === user.toLowerCase() || o === dep.escrow.toLowerCase();
  });
  if (candidates.length === 0) return [];
  const keys = (await many(pc, candidates.map((id) => ({ address: dep.registry, abi: ABI.registry, functionName: 'accountKey', args: [dep.mockChogGenesis, BigInt(id)] })))).map((r) => val<Hex>(r));
  const vaults = (await many(pc, candidates.map((id) => ({ address: dep.registry, abi: ABI.registry, functionName: 'vaultOf', args: [dep.mockChogGenesis, BigInt(id)] })))).map((r) => val<Address>(r));
  const beneficial = await many(pc, keys.map((k) => ({ address: dep.escrow, abi: ABI.escrow, functionName: 'beneficialOwnerOf', args: [k] })));
  const rows: ChogRow[] = [];
  candidates.forEach((id, i) => {
    const owner = ((owners[ids.indexOf(id)] as PromiseFulfilledResult<string>).value).toLowerCase();
    const vault = vaults[i] === zeroAddress ? null : vaults[i];
    const inEscrow = owner === dep.escrow.toLowerCase();
    if (inEscrow) {
      const b = beneficial[i];
      if (b.status === 'fulfilled' && (b.value as string).toLowerCase() === user.toLowerCase()) rows.push({ id, key: keys[i], state: 'escrowed', vault });
    } else {
      rows.push({ id, key: keys[i], state: vault ? 'wallet' : 'novault', vault });
    }
  });
  return rows;
}

export async function loadAccount(pc: PublicClient, dep: Deployment, user: Address, id: number): Promise<AccountView> {
  const key = await read<Hex>(pc, dep.registry, ABI.registry, 'accountKey', [dep.mockChogGenesis, BigInt(id)]);
  const vault = await read<Address>(pc, dep.registry, ABI.registry, 'vaultOf', [dep.mockChogGenesis, BigInt(id)]);
  const tokenDefs = [
    { symbol: 'WMON', address: dep.mockWmon, counts: true, decimals: 18 },
    { symbol: 'USDC', address: dep.mockUsdc, counts: false, decimals: 6 },
    { symbol: '$CHOG', address: dep.mockChogToken, counts: false, decimals: 18 },
  ];
  const [escrowed, data, rate, liquidity, blocker, nonce, ...rest] = await Promise.all([
    read<boolean>(pc, dep.escrow, ABI.escrow, 'isEscrowed', [key]),
    read<PoolAccount>(pc, dep.pool, ABI.pool, 'accountData', [key]),
    read<bigint>(pc, dep.pool, ABI.pool, 'borrowRateBps'),
    read<bigint>(pc, dep.pool, ABI.pool, 'availableLiquidity'),
    read<number>(pc, dep.registry, ABI.registry, 'releaseBlocker', [key]),
    read<bigint>(pc, vault, ABI.vault, 'stateNonce'),
    ...tokenDefs.flatMap((t) => [
      read<bigint>(pc, vault, ABI.vault, 'accounted', [t.address]),
      read<bigint>(pc, t.address, ABI.erc20, 'balanceOf', [vault]),
      read<bigint>(pc, t.address, ABI.erc20, 'balanceOf', [user]),
    ]),
  ]);
  const tokens: TokenRow[] = tokenDefs.map((t, i) => {
    const accounted = rest[i * 3] as bigint, held = rest[i * 3 + 1] as bigint, wallet = rest[i * 3 + 2] as bigint;
    return { ...t, accounted, waiting: held > accounted ? held - accounted : 0n, wallet };
  });
  const positions = hasPositions(dep) ? await loadVaultPositions(pc, dep, key, vault) : [];
  return {
    positions,
    id, key, vault, escrowed, data, tokens, usdcWallet: tokens[1].wallet,
    borrowRateBps: rate, poolLiquidity: liquidity, releaseBlocker: Number(blocker), stateNonce: nonce,
  };
}

/** Where a transaction is. Monad can show a result before it is final, so the app tells all three apart. */
export type TxStage = 'signing' | 'submitted' | 'confirmed' | 'final' | 'failed' | 'rejected';
export type TxCall = { address: Address; abi: Abi; functionName: string; args: unknown[] };

/**
 * Sends one transaction and resolves once it is CONFIRMED (in a block). `finality` resolves later, when the block is
 * final, so a multi-step flow does not wait on finality between steps and the UI can show each stage honestly.
 */
export async function runTx(w: Wallet, pc: PublicClient, call: TxCall, onStage: (s: TxStage, detail?: string) => void, onHash?: (h: Hex) => void): Promise<{ finality: Promise<void> }> {
  onStage('signing');
  let hash: Hex;
  try {
    // A wallet on another network is asked to switch first, so the transaction never goes to the wrong chain.
    const want = pc.chain?.id;
    if (w.kind === 'injected' && want && (await w.client.getChainId()) !== want) await w.client.switchChain({ id: want });
    hash = await w.client.writeContract({ ...call, account: w.account, chain: w.client.chain } as never);
  } catch (e) {
    const msg = String((e as Error).message ?? e);
    onStage(/reject|denied|user rejected/i.test(msg) ? 'rejected' : 'failed', reason(e));
    throw e;
  }
  onHash?.(hash);
  onStage('submitted');
  const receipt = await pc.waitForTransactionReceipt({ hash });
  if (receipt.status !== 'success') { onStage('failed', 'The transaction reverted.'); throw new Error('reverted'); }
  onStage('confirmed');
  return { finality: untilFinal(pc, receipt.blockNumber, w.client.chain?.id === 31337) };
}

async function untilFinal(pc: PublicClient, block: bigint, local: boolean) {
  for (let i = 0; i < 120; i++) {
    try {
      if (local) { if ((await pc.getBlockNumber()) >= block + 2n) return; } // a local chain has no finality tag worth trusting
      else if ((await pc.getBlock({ blockTag: 'finalized' })).number >= block) return;
    } catch {
      if ((await pc.getBlockNumber()) >= block + 2n) return; // no finalized tag on this node: two blocks on top
    }
    await new Promise((r) => setTimeout(r, 800));
  }
}

/** A short, plain reason. Raw selectors never lead the message. */
/** The vault contract's own limit on pool positions held at once (AccountVault.MAX_POSITIONS). */
export const MAX_POSITIONS = 2;

export function reason(e: unknown): string {
  const m = String((e as { shortMessage?: string; message?: string }).shortMessage ?? (e as Error).message ?? e);
  const known: [RegExp, string][] = [
    [/NotController/, 'Only the keeper of this Chog can do that.'],
    [/WithdrawalBlocked/, 'That would leave the loan under-covered. Repay some first, or take less.'],
    [/PriceUnavailable|priceOk/i, 'Prices are paused right now.'],
    [/ExceedsAccounted/, 'More than the vault holds.'],
    [/TooManyPositions/, `A vault holds up to ${MAX_POSITIONS} pool positions. Withdraw one first.`],
    [/PositionNotAccepted/, "That position's pool is not on the allowed list."],
    [/BorrowCapExceeded/, 'The pool has reached its borrow limit for now.'],
    [/NothingToClaim/, 'Nothing has arrived to add.'],
    [/AssetsNotAccepted/, 'Lock the Chog in escrow first.'],
    [/insufficient allowance|ERC20InsufficientAllowance/i, 'Approve the token first.'],
    [/ERC20InsufficientBalance|exceeds balance/i, 'Not enough in your wallet.'],
    [/user rejected|denied/i, 'You rejected it in the wallet. Nothing changed.'],
    [/StateChanged/, 'The vault changed after the buyer signed. Ask them to sign again.'],
    [/EpochChanged|SellerNotBeneficialOwner/, 'This Chog changed hands after the buyer signed.'],
    [/Expired/, 'The offer ran out of time. Make a new one.'],
    [/AlreadyUsed/, 'This signature was already used or cancelled.'],
    [/InvalidSignature/, "The buyer's signature does not match these terms."],
    [/HasLiabilities/, 'The account has a loan, so it needs the sale-with-loan path.'],
    [/AlreadyLiquidatable/, 'The account can be liquidated right now, so it cannot be sold.'],
    [/DebtAboveCeiling/, "The loan is now above the most the buyer agreed to."],
    [/CollateralBelowFloor/, 'The vault is now worth less than the buyer agreed to.'],
    [/HealthBelowFloor/, 'Health is now below what the buyer agreed to.'],
    [/PaymentShortfall/, "The buyer's payment did not arrive in full."],
  ];
  for (const [re, text] of known) if (re.test(m)) return text;
  return m.split('\n')[0].slice(0, 160);
}

/** Rough extra borrowing power from adding `amount` of `token` (ignores the per-account cap, so it is an estimate). */
export async function previewBorrowPowerGain(pc: PublicClient, dep: Deployment, token: Address, amount: bigint): Promise<bigint> {
  if (amount === 0n) return 0n;
  const count = Number(await read<bigint>(pc, dep.pool, ABI.pool, 'collateralCount'));
  for (let i = 0; i < count; i++) {
    const c = await read<{ token: Address; ltvBps: number }>(pc, dep.pool, ABI.pool, 'collateralAt', [BigInt(i)]);
    if (c.token.toLowerCase() === token.toLowerCase()) {
      const oracle = await read<Address>(pc, dep.pool, ABI.pool, 'oracle');
      const value = await read<bigint>(pc, oracle, [{ type: 'function', name: 'quote', stateMutability: 'view', inputs: [{ name: 'token', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ type: 'uint256' }] }] as Abi, 'quote', [token, amount]);
      return (value * BigInt(c.ltvBps)) / 10_000n;
    }
  }
  return 0n; // not collateral: held, but adds nothing
}

/** Largest amount of `token` that may leave the vault right now (the pool says yes or no, so we search). */
export async function maxWithdrawable(pc: PublicClient, dep: Deployment, key: Hex, token: Address, accounted: bigint): Promise<bigint> {
  const ok = (a: bigint) => read<boolean>(pc, dep.registry, ABI.registry, 'withdrawAllowed', [key, token, a]);
  if (accounted === 0n) return 0n;
  if (await ok(accounted)) return accounted;
  let lo = 0n, hi = accounted;
  for (let i = 0; i < 24 && hi - lo > 1n; i++) {
    const mid = (lo + hi) / 2n;
    if (await ok(mid)) lo = mid; else hi = mid;
  }
  return lo;
}

/** Every Chog that has a vault, from public chain data, so anyone can look around without a wallet. */
export async function loadPublicChogs(pc: PublicClient, dep: Deployment): Promise<{ id: number; escrowed: boolean }[]> {
  const total = Number(await read<bigint>(pc, dep.mockChogGenesis, ABI.chog, 'totalSupply'));
  const ids = Array.from({ length: Math.min(total, 2500) }, (_, i) => i + 1);
  const vaults = await many(pc, ids.map((id) => ({ address: dep.registry, abi: ABI.registry, functionName: 'vaultOf', args: [dep.mockChogGenesis, BigInt(id)] })));
  const withVault = ids.filter((_, i) => vaults[i].status === 'fulfilled' && (vaults[i] as PromiseFulfilledResult<string>).value !== zeroAddress);
  const owners = await many(pc, withVault.map((id) => ({ address: dep.mockChogGenesis, abi: ABI.chog, functionName: 'ownerOf', args: [BigInt(id)] })));
  return withVault.map((id, i) => ({ id, escrowed: owners[i].status === 'fulfilled' && (owners[i] as PromiseFulfilledResult<string>).value.toLowerCase() === dep.escrow.toLowerCase() }));
}

export type LendView = {
  totalAssets: bigint; totalDebt: bigint; liquidity: bigint; utilizationBps: bigint; borrowRateBps: bigint; supplyCap: bigint;
  shares: bigint; position: bigint; maxRedeem: bigint; usdcWallet: bigint; allowance: bigint; sharePrice: bigint;
};

/** The lender's side: pool totals, rates, and this wallet's share (zeros when no wallet is connected). */
export async function loadLend(pc: PublicClient, dep: Deployment, user: Address | null): Promise<LendView> {
  const me = user ?? zeroAddress;
  const p = (fn: string, args: unknown[] = []) => read<bigint>(pc, dep.pool, ABI.pool, fn, args);
  const [totalAssets, totalDebt, liquidity, utilizationBps, borrowRateBps, supplyCap, shares, maxRedeem, usdcWallet, allowance, sharePrice] = await Promise.all([
    p('totalAssets'), p('totalDebt'), p('availableLiquidity'), p('utilizationBps'), p('borrowRateBps'), p('supplyCap'),
    p('sharesOf', [me]), p('maxRedeem', [me]),
    read<bigint>(pc, dep.mockUsdc, ABI.erc20, 'balanceOf', [me]),
    read<bigint>(pc, dep.mockUsdc, ABI.erc20, 'allowance', [me, dep.pool]),
    p('convertToAssets', [10n ** 12n]),
  ]);
  const position = shares === 0n ? 0n : await p('convertToAssets', [shares]);
  return { totalAssets, totalDebt, liquidity, utilizationBps, borrowRateBps, supplyCap, shares, position, maxRedeem, usdcWallet, allowance, sharePrice };
}

export const sharesFor = (pc: PublicClient, dep: Deployment, assets: bigint) => read<bigint>(pc, dep.pool, ABI.pool, 'convertToShares', [assets]);


const SYMBOL: Record<string, string> = {};
async function pairOf(pc: PublicClient, a: Address, b: Address) {
  const sym = async (t: Address) => SYMBOL[t.toLowerCase()] ??= await read<string>(pc, t, parseAbi(['function symbol() view returns (string)']) as Abi, 'symbol').catch(() => `${t.slice(0, 6)}…`);
  return `${(await sym(a)).replace(/^m/, '')} / ${(await sym(b)).replace(/^m/, '')}`;
}

async function describePosition(pc: PublicClient, dep: Deployment, id: bigint): Promise<PositionRow> {
  const pmAddr = dep.mockPositionManager!;
  const pos = (await read<unknown[]>(pc, pmAddr, ABI.pm, 'positions', [id])) as unknown[];
  // positions(): nonce, operator, token0, token1, fee, tickLower, tickUpper, liquidity, ...
  const [token0, token1, fee] = [pos[2] as Address, pos[3] as Address, Number(pos[4])];
  const [accepted, value, pair] = await Promise.all([
    read<boolean>(pc, dep.pool, ABI.pool, 'positionAccepted', [id]).catch(() => false),
    read<[boolean, bigint]>(pc, dep.pool, ABI.pool, 'positionValue', [id]).catch(() => [false, 0n] as [boolean, bigint]),
    pairOf(pc, token0, token1),
  ]);
  return { id, pair, fee, value: value[1], valueOk: value[0], accepted };
}

/** Positions in a wallet, listed through the position manager's enumeration (the real one has it too). */
export async function loadWalletPositions(pc: PublicClient, dep: Deployment, user: Address): Promise<PositionRow[]> {
  if (!hasPositions(dep)) return [];
  const n = Number(await read<bigint>(pc, dep.mockPositionManager!, ABI.pm, 'balanceOf', [user]));
  const ids = await Promise.all(Array.from({ length: Math.min(n, 20) }, (_, i) => read<bigint>(pc, dep.mockPositionManager!, ABI.pm, 'tokenOfOwnerByIndex', [user, BigInt(i)])));
  return Promise.all(ids.map((id) => describePosition(pc, dep, id)));
}

async function loadVaultPositions(pc: PublicClient, dep: Deployment, key: Hex, vault: Address): Promise<PositionRow[]> {
  const n = Number(await read<bigint>(pc, vault, ABI.vault, 'positionCount'));
  const ids = await Promise.all(Array.from({ length: n }, (_, i) => read<bigint>(pc, vault, ABI.vault, 'positionAt', [BigInt(i)])));
  return Promise.all(ids.map(async (id) => ({
    ...(await describePosition(pc, dep, id)),
    withdrawAllowed: await read<boolean>(pc, dep.registry, ABI.registry, 'positionWithdrawAllowed', [key, id]).catch(() => false),
  })));
}

export type RiskView = {
  collaterals: { token: Address; symbol: string; ltvBps: number; thresholdBps: number; bonusBps: number }[];
  borrowCap: bigint; accountDebtCap: bigint; supplyCap: bigint; closeFactorBps: number; totalDebt: bigint;
};

/** The numbers behind the Risk page, read from the pool so the page can never disagree with the contract. */
export async function loadRisk(pc: PublicClient, dep: Deployment): Promise<RiskView> {
  const p = <T,>(fn: string, args: unknown[] = []) => read<T>(pc, dep.pool, ABI.pool, fn, args);
  const [n, borrowCap, accountDebtCap, supplyCap, closeFactorBps, totalDebt] = await Promise.all([
    p<bigint>('collateralCount'), p<bigint>('borrowCap'), p<bigint>('accountDebtCap'), p<bigint>('supplyCap'),
    p<number>('closeFactorBps'), p<bigint>('totalDebt'),
  ]);
  const sym = parseAbi(['function symbol() view returns (string)']) as Abi;
  const collaterals = await Promise.all(Array.from({ length: Number(n) }, async (_, i) => {
    const c = (await p<{ token: Address; ltvBps: number; thresholdBps: number; bonusBps: number }>('collateralAt', [BigInt(i)]));
    const symbol = (await read<string>(pc, c.token, sym, 'symbol').catch(() => 'token')).replace(/^m/, '');
    return { token: c.token, symbol, ltvBps: Number(c.ltvBps), thresholdBps: Number(c.thresholdBps), bonusBps: Number(c.bonusBps) };
  }));
  return { collaterals, borrowCap, accountDebtCap, supplyCap, closeFactorBps: Number(closeFactorBps), totalDebt };
}
