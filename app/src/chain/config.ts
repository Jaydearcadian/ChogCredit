import { defineChain, type Address } from 'viem';

/** What the app needs to know about one deployment. Produced from contracts/deployments/*.json. */
export type Deployment = {
  chainId: number;
  environment: string;
  registry: Address;
  escrow: Address;
  pool: Address;
  transferCoordinator: Address;
  mockChogGenesis: Address;
  mockChogToken: Address;
  mockUsdc: Address;
  mockWmon: Address;
  /** Test deployments: hands one mock Chog to each address. */
  chogFaucet?: Address;
  /** First block to read history from. */
  deployBlock?: number;
};

const RPC: Record<number, string> = {
  31337: 'http://127.0.0.1:8545',
  10143: 'https://testnet-rpc.monad.xyz',
  143: 'https://rpc.monad.xyz',
};

export function chainFor(chainId: number) {
  const url = RPC[chainId] ?? RPC[31337];
  return defineChain({
    id: chainId,
    name: chainId === 143 ? 'Monad' : chainId === 10143 ? 'Monad testnet' : 'Local chain',
    nativeCurrency: { name: 'MON', symbol: 'MON', decimals: 18 },
    rpcUrls: { default: { http: [url] } },
    // Monad has the canonical Multicall3; a local Anvil chain does not.
    ...(chainId === 31337 ? {} : { contracts: { multicall3: { address: '0xcA11bde05977b3631167028862bE2a173976CA11' as const } } }),
  });
}

export async function loadDeployment(): Promise<Deployment> {
  // A hosted build points at a committed manifest (VITE_DEPLOYMENT); local work uses public/deployment.json.
  const res = await fetch(import.meta.env.VITE_DEPLOYMENT ?? '/deployment.json', { cache: 'no-store' });
  if (!res.ok) throw new Error('No deployment.json found. Run scripts/use-local-deployment.sh or point the app at a deployment.');
  return (await res.json()) as Deployment;
}

/** Test deployments use mock assets and a mock oracle. Never show them as real money. */
export const isTestDeployment = (d: Deployment) => d.chainId !== 143;
