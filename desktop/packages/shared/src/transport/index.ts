//! 传输层抽象：命令名 + JSON 进，JSON 出。
//!
//! 桌面实现是 Tauri IPC（transport/tauri），mobile 实现是本地 HTTP（transport/http）。
//! 业务实现只有一份（Rust 的 crates/app::dispatch），这里只抹平传输差异。

/** 进度回调的负载类型由调用方解释（Progress / S3FixProgress） */
export type ProgressCallback = (payload: unknown) => void;

export interface Transport {
  /** 调一个后端命令（crates/app::dispatch 里的名字） */
  call<T>(cmd: string, args?: Record<string, unknown>): Promise<T>;
  /**
   * 调带进度的命令。桌面用 Tauri Channel 真推送；
   * mobile 用「先拿 task id，再轮询 /api/progress」模拟同一条回调。
   */
  startTask<T>(cmd: string, args: Record<string, unknown>, onProgress: ProgressCallback): Promise<T>;
  /** 只在桌面壳里实现的能力（登录窗口、托盘、窗口主题、打开下载目录） */
  shell<T>(cmd: string, args?: Record<string, unknown>): Promise<T>;
}

let current: Transport | null = null;

export function setTransport(t: Transport): void {
  current = t;
}

export function getTransport(): Transport {
  if (!current) throw new Error('传输层还没注册：先调用 setTransport()');
  return current;
}

export function invoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  return getTransport().call<T>(cmd, args);
}

export function invokeTask<T>(
  cmd: string,
  args: Record<string, unknown>,
  onProgress: ProgressCallback
): Promise<T> {
  return getTransport().startTask<T>(cmd, args, onProgress);
}

export function shellInvoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  return getTransport().shell<T>(cmd, args);
}
