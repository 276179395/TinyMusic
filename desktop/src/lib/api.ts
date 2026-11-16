/**
 * 桌面端的 API 入口。
 *
 * 真正的实现与类型都在公共库 @tinymusic/shared 里（mobile 用的是同一份），
 * 这里只做两件事：注册 Tauri 传输层、把公共库的导出再抛出去，
 * 让现有组件里的 `import { api, fmtDuration } from './lib/api'` 不用改。
 */

import { setTransport } from '@tinymusic/shared/transport';

import { tauriTransport } from './tauriTransport';

setTransport(tauriTransport);

export { api } from '@tinymusic/shared/api';
export * from '@tinymusic/shared/format';
export * from '@tinymusic/shared/types';
