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
  });
}

export async function loadDeployment(): Promise<Deployment> {
  const res = await fetch('/deployment.json', { cache: 'no-store' });
  if (!res.ok) throw new Error('No deployment.json found. Run scripts/use-local-deployment.sh or point the app at a deployment.');
  return (await res.json()) as Deployment;
}

/** Test deployments use mock assets and a mock oracle. Never show them as real money. */
export const isTestDeployment = (d: Deployment) => d.chainId !== 143;
