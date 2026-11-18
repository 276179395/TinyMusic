import { pluginReactLynx } from '@lynx-js/react-rsbuild-plugin';
import { defineConfig } from '@lynx-js/rspeedy';

/**
 * 不显式指定 engineVersion：当前 rspeedy 的主线程字节码编码器只支持
 * bundle 版本 1.0–3.9，而宿主引擎是 Lynx 4.2.0（向后兼容 3.9 的 bundle）。
 * 等编码器放开 4.x 后再把 engineVersion 提到对应版本。
 */
export default defineConfig({
  plugins: [pluginReactLynx()],
  source: {
    entry: {
      main: './src/index.tsx',
    },
  },
});
