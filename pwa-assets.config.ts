import { defineConfig, minimalPreset } from '@vite-pwa/assets-generator/config'

export default defineConfig({
  // Generate all icon sizes from a single SVG source
  preset: {
    ...minimalPreset,
    apple: {
      sizes: [180],
      // The 180x180 apple-touch-icon for iOS
      padding: 0.1,
    },
    maskable: {
      sizes: [512],
      // Android adaptive icon with safe zone padding
      padding: 0.2,
    },
  },
  images: ['public/logo.svg'],
})
