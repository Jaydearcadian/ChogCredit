import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// viem and the QR encoder change rarely, so they get their own cacheable chunks.
export default defineConfig({
  plugins: [react()],
  server: { port: 5173, host: '127.0.0.1' },
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes('node_modules')) return undefined;
          if (/\/viem\/|abitype|ox\//.test(id)) return 'viem';
          if (/qrcode/.test(id)) return 'qr';
          return undefined;
        },
      },
    },
  },
});
