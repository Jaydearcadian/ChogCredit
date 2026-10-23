import type { Address, Hex, PublicClient } from 'viem';
import { ABI } from './api';
import type { Deployment } from './config';

/**
 * Selling a Chog with its vault (docs/DEBT_BEARING_SALES_SPEC.md). There is no server: the parties pass two links.
 *   1. The seller writes an OFFER (price, buyer, optional payoff) and sends the offer link.
 *   2. The buyer opens it, sees the live account, approves the payment and SIGNS the acceptance (EIP-712), then sends
 *      the signed link back.
 *   3. The seller opens the signed link and executes. The coordinator checks everything again on chain.
 * The links carry no secrets. A signature only lets this seller sell this account to this buyer on these exact terms.
 */
export type Offer = {
  v: 1; chainId: number; coordinator: Address; key: Hex; id: number; seller: Address; buyer: Address;
  paymentToken: Address; price: string; debtRepay: string; deadline: string; salt: string;
};
export type Acceptance = {
  key: Hex; seller: Address; buyer: Address; paymentToken: Address; price: bigint; stateNonce: bigint; epoch: bigint; deadline: bigint; salt: bigint;
};
export type DebtAcceptance = Acceptance & { pool: Address; maxDebt: bigint; minCollateralValue: bigint; minHealthBps: bigint; debtRepay: bigint };
export type Signed = { v: 1; chainId: number; coordinator: Address; id: number; kind: 'plain' | 'debt'; a: Record<string, string>; sig: Hex };

const b64 = (s: string) => btoa(unescape(encodeURIComponent(s))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64 = (s: string) => decodeURIComponent(escape(atob(s.replace(/-/g, '+').replace(/_/g, '/'))));
export const encode = (o: unknown) => b64(JSON.stringify(o, (_, v) => (typeof v === 'bigint' ? v.toString() : v)));
export function decode<T>(s: string | null): T | null { if (!s) return null; try { return JSON.parse(unb64(s)) as T; } catch { return null; } }
export const linkTo = (path: string, param: string, payload: unknown) => `${location.origin}${path}?${param}=${encode(payload)}`;

const ACCEPTANCE = [
  { name: 'key', type: 'bytes32' }, { name: 'seller', type: 'address' }, { name: 'buyer', type: 'address' },
  { name: 'paymentToken', type: 'address' }, { name: 'price', type: 'uint256' }, { name: 'stateNonce', type: 'uint256' },
  { name: 'epoch', type: 'uint256' }, { name: 'deadline', type: 'uint256' }, { name: 'salt', type: 'uint256' },
] as const;
const DEBT_ACCEPTANCE = [
  ...ACCEPTANCE, { name: 'pool', type: 'address' }, { name: 'maxDebt', type: 'uint256' },
  { name: 'minCollateralValue', type: 'uint256' }, { name: 'minHealthBps', type: 'uint256' }, { name: 'debtRepay', type: 'uint256' },
] as const;

export function typedData(chainId: number, coordinator: Address, kind: 'plain' | 'debt', message: Acceptance | DebtAcceptance) {
  const domain = { name: 'ChogCreditTransfer', version: '1', chainId, verifyingContract: coordinator } as const;
  return kind === 'plain'
    ? { domain, types: { Acceptance: ACCEPTANCE }, primaryType: 'Acceptance' as const, message }
    : { domain, types: { DebtAcceptance: DEBT_ACCEPTANCE }, primaryType: 'DebtAcceptance' as const, message };
}

/** Live facts both screens need: the vault's nonce, the escrow epoch, who holds the Chog, and the account's numbers. */
export async function saleState(pc: PublicClient, dep: Deployment, key: Hex) {
  const info = (await pc.readContract({ address: dep.registry, abi: ABI.registry, functionName: 'accountInfo', args: [key] })) as { vault: Address };
  const [nonce, epoch, owner, data] = await Promise.all([
    pc.readContract({ address: info.vault, abi: ABI.vault, functionName: 'stateNonce' }) as Promise<bigint>,
    pc.readContract({ address: dep.escrow, abi: ABI.escrow, functionName: 'epochOf', args: [key] }) as Promise<bigint>,
    pc.readContract({ address: dep.escrow, abi: ABI.escrow, functionName: 'beneficialOwnerOf', args: [key] }) as Promise<Address>,
    pc.readContract({ address: dep.pool, abi: ABI.pool, functionName: 'accountData', args: [key] }) as Promise<{ priceOk: boolean; debt: bigint; collateralValue: bigint; healthFactorBps: bigint; liquidationValue: bigint }>,
  ]);
  return { vault: info.vault, nonce, epoch, owner, data };
}

/**
 * The buyer's protection, from the live numbers at signing time:
 *  - the loan after any payoff is at most today's figure plus 1 percent (interest keeps running until the seller acts),
 *  - the vault's counted value is at least 97 percent of today's (prices move a little),
 *  - health is at least 90 percent of today's figure after payoff, and never below 1.00.
 */
export function buyerBounds(d: { debt: bigint; collateralValue: bigint; liquidationValue: bigint }, debtRepay: bigint) {
  const debtAfter = d.debt > debtRepay ? d.debt - debtRepay : 0n;
  const maxDebt = debtAfter + debtAfter / 100n + 1n;
  const minCollateralValue = (d.collateralValue * 97n) / 100n;
  const healthAfter = debtAfter === 0n ? 10n ** 30n : (d.liquidationValue * 10_000n) / debtAfter;
  const minHealthBps = healthAfter >= 10n ** 29n ? 10_000n : (healthAfter * 90n) / 100n < 10_000n ? 10_000n : (healthAfter * 90n) / 100n;
  return { debtAfter, maxDebt, minCollateralValue, minHealthBps, healthAfter };
}

export const toStrings = (o: Record<string, unknown>) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, typeof v === 'bigint' ? v.toString() : String(v)]));
export function fromStrings(kind: 'plain' | 'debt', a: Record<string, string>): Acceptance | DebtAcceptance {
  const big = (k: string) => BigInt(a[k]);
  const base: Acceptance = { key: a.key as Hex, seller: a.seller as Address, buyer: a.buyer as Address, paymentToken: a.paymentToken as Address, price: big('price'), stateNonce: big('stateNonce'), epoch: big('epoch'), deadline: big('deadline'), salt: big('salt') };
  return kind === 'plain' ? base : { ...base, pool: a.pool as Address, maxDebt: big('maxDebt'), minCollateralValue: big('minCollateralValue'), minHealthBps: big('minHealthBps'), debtRepay: big('debtRepay') };
}
