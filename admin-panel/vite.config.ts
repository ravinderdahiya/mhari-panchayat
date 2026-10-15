import { existsSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// The mobile app links to these static pages (Terms of Service, Privacy Policy)
// under the same /mhari-panchayat/ path the admin SPA is served from. A page
// that isn't deployed there falls through to the SPA's index.html, so the link
// "opens the admin panel". Shipping them inside the admin build guarantees they
// exist wherever the admin panel is. The single source of truth stays in
// backend/public - they are copied at build time, not duplicated in the repo.
const LEGAL_PAGES = ['terms-of-service.html', 'privacy-policy.html', 'harsac-logo.png']

function legalPages(): Plugin {
  return {
    name: 'legal-pages',
    apply: 'build',
    generateBundle() {
      for (const file of LEGAL_PAGES) {
        const source = resolve(__dirname, '../backend/public', file)
        if (!existsSync(source)) {
          this.error(`legal-pages: ${source} not found`)
        }
        this.emitFile({ type: 'asset', fileName: file, source: readFileSync(source) })
      }
    },
  }
}

// https://vite.dev/config/
export default defineConfig({
  // Must match the IIS app path: https://hsac.in/mhari-panchayat/
  // Trailing slash matters: import.meta.env.BASE_URL is used verbatim
  // (Vite doesn't normalize a missing one), and code across the app
  // (VillagePhotoBanner, arcgisSetup) concatenates paths onto it assuming
  // it already ends in '/' — without the slash here those become malformed
  // URLs that silently 404 into the SPA fallback instead of the real asset.
  base: '/mhari-panchayat/',
  plugins: [react(), tailwindcss(), legalPages()],
  server: {
    port: 5173,
    host: '0.0.0.0',
  },
})
