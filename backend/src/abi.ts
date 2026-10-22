export const creditAbi = [
  { type: "function", name: "availableLiquidity", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "uint256" }] },
  { type: "function", name: "totalOutstandingPrincipal", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "uint256" }] },
  { type: "function", name: "maxLtvBps", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "uint256" }] },
  { type: "function", name: "liquidationThresholdBps", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "uint256" }] },
  { type: "function", name: "annualInterestRateBps", stateMutability: "view", inputs: [], outputs: [{ name: "", type: "uint256" }] },
  { type: "function", name: "collateralOf", stateMutability: "view", inputs: [{ name: "accountId", type: "uint256" }], outputs: [{ name: "", type: "uint256" }] },
  { type: "function", name: "debtOf", stateMutability: "view", inputs: [{ name: "accountId", type: "uint256" }], outputs: [{ name: "", type: "uint256" }] },
  { type: "function", name: "collateralValueUsdc", stateMutability: "view", inputs: [{ name: "accountId", type: "uint256" }], outputs: [{ name: "", type: "uint256" }] },
  { type: "function", name: "maxBorrowUsdc", stateMutability: "view", inputs: [{ name: "accountId", type: "uint256" }], outputs: [{ name: "", type: "uint256" }] },
  { type: "function", name: "availableBorrowUsdc", stateMutability: "view", inputs: [{ name: "accountId", type: "uint256" }], outputs: [{ name: "", type: "uint256" }] },
  { type: "function", name: "healthFactorBps", stateMutability: "view", inputs: [{ name: "accountId", type: "uint256" }], outputs: [{ name: "", type: "uint256" }] },
] as const;

export const positionNftAbi = [
  { type: "function", name: "ownerOf", stateMutability: "view", inputs: [{ name: "tokenId", type: "uint256" }], outputs: [{ name: "", type: "address" }] },
] as const;
