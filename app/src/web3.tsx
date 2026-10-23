import '@rainbow-me/rainbowkit/styles.css';
import { connectorsForWallets, darkTheme, RainbowKitProvider, type Theme } from '@rainbow-me/rainbowkit';
import { coinbaseWallet, injectedWallet, metaMaskWallet, phantomWallet, rabbyWallet, rainbowWallet, walletConnectWallet } from '@rainbow-me/rainbowkit/wallets';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useMemo, type ReactNode } from 'react';
import { createConfig, http, WagmiProvider } from 'wagmi';
import { chainFor, type Deployment } from './chain/config';

/**
 * RainbowKit on wagmi. Browser-extension wallets and Coinbase Wallet need no key. Wallets that connect over
 * WalletConnect (phone wallets by QR code or deep link) need a WalletConnect Cloud projectId: RainbowKit throws
 * without one, so they are only listed when VITE_WALLETCONNECT_PROJECT_ID is set.
 */
const projectId = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID as string | undefined;
export const walletConnectEnabled = !!projectId;

const theme: Theme = (() => {
  const t = darkTheme({ accentColor: '#6B52F0', accentColorForeground: '#FAF9FC', borderRadius: 'large', overlayBlur: 'small' });
  t.colors.modalBackground = '#141026';
  t.colors.modalBorder = '#2D2556';
  t.colors.profileForeground = '#141026';
  t.colors.actionButtonSecondaryBackground = '#181330';
  t.colors.generalBorder = '#2D2556';
  t.colors.menuItemBackground = '#211A40';
  t.colors.modalText = '#FAF9FC';
  t.colors.modalTextSecondary = '#D2CCEA';
  t.fonts.body = "'Inter', system-ui, sans-serif";
  return t;
})();

const queryClient = new QueryClient();

export function Web3({ dep, children }: { dep: Deployment; children: ReactNode }) {
  const config = useMemo(() => {
    const chain = chainFor(dep.chainId);
    const groups = projectId
      ? [{ groupName: 'Popular', wallets: [metaMaskWallet, rabbyWallet, phantomWallet, coinbaseWallet, rainbowWallet, walletConnectWallet] }, { groupName: 'Other', wallets: [injectedWallet] }]
      : [{ groupName: 'Wallets', wallets: [injectedWallet, rabbyWallet, phantomWallet, coinbaseWallet] }];
    const connectors = connectorsForWallets(groups, { appName: 'Chog Credit', projectId: projectId ?? '' });
    return createConfig({ chains: [chain], connectors, transports: { [chain.id]: http() }, ssr: false });
  }, [dep.chainId]);
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider theme={theme} modalSize="compact" appInfo={{ appName: 'Chog Credit', disclaimer: Disclaimer }}>
          {children}
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}

function Disclaimer({ Text }: { Text: React.FC<{ children: ReactNode }> }) {
  return <Text>Testnet only. Connecting signs nothing. You can look around without a wallet.</Text>;
}
