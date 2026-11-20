import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

export default defineConfig({
  plugins: [svelte()],
  clearScreen: false,
  // 公共库是 TS 源码（不是预编译产物），交给 vite 直接编译，避免 optimizeDeps 卡住
  optimizeDeps: {
    exclude: ['@tinymusic/shared'],
  },
  server: {
    port: 1420,
    strictPort: true,
    watch: {
      // 编辑器的「原子写入」会在源目录里临时建 .xxx.tmpdir/ 再改名，chokidar 跟上去
      // 会撞到 EBUSY 直接崩掉 dev server，所以这类临时目录/文件一律不看。
      ignored: [
        '**/target/**',
        '**/src-tauri/**',
        '**/core/**',
        '**/.*.tmpdir/**',
        '**/*.tmp',
        '**/.*.tmpdir',
      ],
    },
  },
  build: {
    target: 'safari15',
    minify: 'esbuild',
    sourcemap: false,
  },
});
