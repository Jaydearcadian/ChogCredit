// Gives a TEST deployment one real, healthy loan so the Lend screen shows genuine lender yield and visitors have a vault to look at.
//
//   DEPLOYER_KEY=0x... node scripts/seed-demo-loan.mjs [--deployment public/deployments/monad-testnet.json] [--chog 1] [--borrow 4000]
//
// It uses the Chog the deploy script minted to the deployer: opens its vault, escrows the Chog, adds test WMON and borrows USDC.
// The loan is real on-chain state with real interest. It is not faked data, and it is labelled as a demo in the app's tour.
import { readFileSync } from 'node:fs';
import { createPublicClient, createWalletClient, defineChain, http, parseAbi, parseUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

const arg = (n, d) => { const i = process.argv.indexOf(n); return i > 0 ? process.argv[i + 1] : d; };
const dep = JSON.parse(readFileSync(arg('--deployment', 'public/deployments/monad-testnet.json'), 'utf8'));
if (dep.chainId === 143) throw new Error('Refusing to run against mainnet.');
const id = BigInt(arg('--chog', '1')), borrow = parseUnits(arg('--borrow', '4000'), 6), wmonAmt = parseUnits(arg('--wmon', '560000'), 18);
const key = process.env.DEPLOYER_KEY; if (!key) throw new Error('Set DEPLOYER_KEY to the deployer testnet key.');
const account = privateKeyToAccount(key);
const rpc = dep.chainId === 10143 ? 'https://testnet-rpc.monad.xyz' : 'http://127.0.0.1:8545';
const chain = defineChain({ id: dep.chainId, name: 'target', nativeCurrency: { name: 'MON', symbol: 'MON', decimals: 18 }, rpcUrls: { default: { http: [rpc] } } });
const pub = createPublicClient({ chain, transport: http() }), wal = createWalletClient({ chain, account, transport: http() });
const gasPrice = dep.chainId === 10143 ? 100_000_000_000n : undefined;
const send = async (label, call) => { const h = await wal.writeContract({ ...call, ...(gasPrice ? { gasPrice } : {}) }); await pub.waitForTransactionReceipt({ hash: h }); console.log('ok  ', label); };

const registryAbi = parseAbi(['function createAccount(address,uint256) returns (address)', 'function vaultOf(address,uint256) view returns (address)', 'function accountKey(address,uint256) view returns (bytes32)']);
const chogAbi = parseAbi(['function safeTransferFrom(address,address,uint256)', 'function ownerOf(uint256) view returns (address)']);
const tokenAbi = parseAbi(['function mint(address,uint256)', 'function approve(address,uint256) returns (bool)']);
const vaultAbi = parseAbi(['function depositERC20(address,uint256)']);
const poolAbi = parseAbi(['function borrow(bytes32,uint256)', 'function debtOf(bytes32) view returns (uint256)', 'function utilizationBps() view returns (uint256)', 'function borrowRateBps() view returns (uint256)']);

const owner = await pub.readContract({ address: dep.mockChogGenesis, abi: chogAbi, functionName: 'ownerOf', args: [id] });
let vault = await pub.readContract({ address: dep.registry, abi: registryAbi, functionName: 'vaultOf', args: [dep.mockChogGenesis, id] }).catch(() => '0x0000000000000000000000000000000000000000');
const key32 = await pub.readContract({ address: dep.registry, abi: registryAbi, functionName: 'accountKey', args: [dep.mockChogGenesis, id] });
if (vault === '0x0000000000000000000000000000000000000000') {
  if (owner.toLowerCase() !== account.address.toLowerCase()) throw new Error(`Chog #${id} is held by ${owner}, not the deployer.`);
  await send('open the vault', { address: dep.registry, abi: registryAbi, functionName: 'createAccount', args: [dep.mockChogGenesis, id] });
  vault = await pub.readContract({ address: dep.registry, abi: registryAbi, functionName: 'vaultOf', args: [dep.mockChogGenesis, id] });
  await send('escrow the Chog', { address: dep.mockChogGenesis, abi: chogAbi, functionName: 'safeTransferFrom', args: [account.address, dep.escrow, id] });
  await send('mint test WMON', { address: dep.mockWmon, abi: tokenAbi, functionName: 'mint', args: [account.address, wmonAmt] });
  await send('approve the vault', { address: dep.mockWmon, abi: tokenAbi, functionName: 'approve', args: [vault, wmonAmt] });
  await send('add WMON to the vault', { address: vault, abi: vaultAbi, functionName: 'depositERC20', args: [dep.mockWmon, wmonAmt] });
}
const debt = await pub.readContract({ address: dep.pool, abi: poolAbi, functionName: 'debtOf', args: [key32] });
if (debt === 0n) await send(`borrow ${arg('--borrow', '4000')} USDC`, { address: dep.pool, abi: poolAbi, functionName: 'borrow', args: [key32, borrow] });
const [util, rate] = await Promise.all([pub.readContract({ address: dep.pool, abi: poolAbi, functionName: 'utilizationBps' }), pub.readContract({ address: dep.pool, abi: poolAbi, functionName: 'borrowRateBps' })]);
console.log(`Chog #${id} vault ${vault}: pool ${Number(util) / 100}% used, borrowers pay ${Number(rate) / 100}%, lenders earn ${(Number(rate) * Number(util) / 1e6).toFixed(2)}%`);
