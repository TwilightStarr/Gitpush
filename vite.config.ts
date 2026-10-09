import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import path from 'path';
import { fileURLToPath } from 'url';
import { defineConfig, type Plugin } from 'vite';

const currentDir = import.meta.dirname ?? path.dirname(fileURLToPath(import.meta.url));

// Üretim derlemesine Content-Security-Policy ekler. Token'ın bir XSS ile dışarı
// sızdırılmasını zorlaştırır: bağlantı yalnızca kendi kaynağına ve api.github.com'a
// izinlidir, satır içi script çalıştırılamaz, eklenti/nesne yüklenemez.
// (Geliştirme sunucusunda Vite HMR satır içi script kullandığı için eklenmez.)
const CSP = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob: https://avatars.githubusercontent.com",
  "font-src 'self' data:",
  "connect-src 'self' https://api.github.com",
  "object-src 'none'",
  "base-uri 'none'",
  "form-action 'none'",
].join('; ');

function cspPlugin(): Plugin {
  return {
    name: 'gitpush-csp',
    apply: 'build',
    transformIndexHtml(html) {
      const tag = `<meta http-equiv="Content-Security-Policy" content="${CSP}" />`;
      return html.replace('<head>', `<head>\n    ${tag}`);
    },
  };
}

// Sunucu tarafında (dev/preview) uygulanabilecek güvenlik başlıkları.
// Not: X-Frame-Options / frame-ancestors, AI Studio önizlemesi iframe içinde
// çalıştığı için burada bilinçli olarak EKLENMEDİ; canlı barındırmada ekleyin
// (bkz. SECURITY.md).
const SECURITY_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), payment=()',
};

export default defineConfig(() => {
  return {
    plugins: [react(), tailwindcss(), cspPlugin()],
    resolve: {
      alias: {
        '@': path.resolve(currentDir, '.'),
      },
    },
    build: {
      // Kaynak haritaları üretimde yayınlanmaz
      sourcemap: false,
    },
    preview: {
      headers: SECURITY_HEADERS,
    },
    server: {
      headers: SECURITY_HEADERS,
      // HMR is disabled in AI Studio via DISABLE_HMR env var.
      // Do not modify - file watching is disabled to prevent flickering during agent edits.
      hmr: process.env.DISABLE_HMR !== 'true',
      // Disable file watching when DISABLE_HMR is true to save CPU during agent edits.
      watch: process.env.DISABLE_HMR === 'true' ? null : {},
    },
  };
});
