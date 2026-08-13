import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// https://vite.dev/config/
export default defineConfig({
  // Must match the IIS app path: https://hsac.in/mhari-panchayat/
  // Trailing slash matters: import.meta.env.BASE_URL is used verbatim
  // (Vite doesn't normalize a missing one), and code across the app
  // (VillagePhotoBanner, arcgisSetup) concatenates paths onto it assuming
  // it already ends in '/' — without the slash here those become malformed
  // URLs that silently 404 into the SPA fallback instead of the real asset.
  base: '/mhari-panchayat/',
  plugins: [react(), tailwindcss()],
  server: {
    port: 5173,
    host: '0.0.0.0',
  },
})

