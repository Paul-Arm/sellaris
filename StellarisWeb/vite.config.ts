import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  build: {
    rollupOptions: { output: { manualChunks: { renderer: ['three'], react: ['react', 'react-dom'] } } },
  },
  server: {
    port: 5173,
    proxy: {
      '/ws': { target: 'ws://127.0.0.1:3001', ws: true },
      '/api': 'http://127.0.0.1:3001',
      '/v1': { target: 'http://127.0.0.1:3001', ws: true },
    },
  },
});
