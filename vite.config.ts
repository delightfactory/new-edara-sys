import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      // ── Strategy: injectManifest — full SW control for ERP ──
      strategies: 'injectManifest',
      srcDir: 'src',
      filename: 'sw.ts',

      // prompt = we control timing; SW notifies via BroadcastChannel, auto-reloads between pages
      registerType: 'prompt',
      injectRegister: 'auto',

      // SW enabled in dev mode to support Push Notifications testing.
      // Uses type:'module' to avoid duplicate React instance issues.
      devOptions: {
        enabled: true,
        type: 'module',
        navigateFallback: 'index.html',
      },

      includeAssets: [
        'favicon.ico',
        'logo.svg',
        'apple-touch-icon-180x180.png',
        'pwa-*.png',
        'maskable-icon-*.png',
      ],

      // ── Web App Manifest (colors from tokens.css) ──
      manifest: {
        name: 'إدارة — نظام التوزيع',
        short_name: 'إدارة',
        description: 'نظام إدارة شركات التوزيع المتكامل',
        theme_color: '#2563eb',         // --color-primary from tokens.css
        background_color: '#f0f2f5',   // --bg-app (light) from tokens.css
        display: 'standalone',
        orientation: 'portrait-primary',
        dir: 'rtl',
        lang: 'ar',
        start_url: '/?source=pwa',
        scope: '/',
        // ── Manifest identity (W3C + Chrome best practice for WebAPK) ──
        id: '/',                              // Stable identity — never changes even if start_url changes
        prefer_related_applications: false,   // Always prefer PWA over any native app

        categories: ['business', 'productivity'],
        icons: [
          {
            src: 'pwa-64x64.png',
            sizes: '64x64',
            type: 'image/png',
          },
          {
            src: 'pwa-192x192.png',
            sizes: '192x192',
            type: 'image/png',
          },
          {
            src: 'pwa-512x512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'any',
          },
          {
            src: 'maskable-icon-512x512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable',
          },
          {
            src: 'apple-touch-icon-180x180.png',
            sizes: '180x180',
            type: 'image/png',
          },
        ],
        screenshots: [
          {
            src: 'screenshots/wide.png',
            sizes: '1280x800',
            type: 'image/png',
            // @ts-ignore — form_factor is valid manifest field
            form_factor: 'wide',
            label: 'لوحة القيادة',
          },
          {
            src: 'screenshots/narrow.png',
            sizes: '390x844',
            type: 'image/png',
            // @ts-ignore
            form_factor: 'narrow',
            label: 'واجهة الموبايل',
          },
        ],
      },

      // Workbox config (for precaching + cache cleanup)
      workbox: {
        globPatterns: ['**/*.{js,css,html,ico,png,svg,woff2}'],
        cleanupOutdatedCaches: true,
        navigateFallback: 'index.html',
        navigateFallbackDenylist: [/^\/api\//],
      },
    }),
  ],

  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
})
