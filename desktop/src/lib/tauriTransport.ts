//! 桌面实现：Tauri IPC。
//!
//! 命令面统一走 `tm_invoke`；带进度的 6 个命令仍是类型化命令（Channel 不能塞进 args）。

import { Channel, invoke as tauriInvoke } from '@tauri-apps/api/core';

import type { ProgressCallback, Transport } from '@tinymusic/shared/transport';

export const tauriTransport: Transport = {
  call: <T>(cmd: string, args?: Record<string, unknown>) =>
    tauriInvoke<T>('tm_invoke', { cmd, args: args ?? {} }),

  startTask: <T>(cmd: string, args: Record<string, unknown>, onProgress: ProgressCallback) => {
    const ch = new Channel<unknown>();
    ch.onmessage = (p) => onProgress(p);
    return tauriInvoke<T>(cmd, { ...args, onProgress: ch });
  },

  shell: <T>(cmd: string, args?: Record<string, unknown>) => tauriInvoke<T>(cmd, args ?? {}),
};
