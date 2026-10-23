// Copies the ABIs the app needs out of the Foundry build (run `forge build` in ../contracts first).
import { readFileSync, writeFileSync } from 'node:fs';
const names = ['AccountVault', 'ChogAccountRegistry', 'ChogCreditEscrow', 'ChogCreditPool', 'AccountTransferCoordinator', 'MockChogGenesis', 'MockTokens'];
const pick = { MockTokens: 'MockUSDC' };
for (const n of names) {
  const file = n === 'MockTokens' ? 'MockTokens.sol/MockUSDC.json' : `${n}.sol/${n}.json`;
  const j = JSON.parse(readFileSync(`../contracts/out/${file}`, 'utf8'));
  const out = n === 'MockTokens' ? 'ERC20Mock' : n;
  writeFileSync(`src/abi/${out}.json`, JSON.stringify(j.abi));
  console.log(out, j.abi.length, 'entries');
}
