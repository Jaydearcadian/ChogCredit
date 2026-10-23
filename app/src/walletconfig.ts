/** Read at startup so the app can decide how to offer sign-in without loading the wallet libraries. */
export const walletConnectProjectId = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID as string | undefined;
export const walletConnectEnabled = !!walletConnectProjectId;
