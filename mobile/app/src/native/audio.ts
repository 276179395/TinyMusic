/**
 * 原生播放器的 JS 封装（Swift 侧 TmAudioModule）。
 *
 * 通信方式是**轮询**：每 400ms 调一次 state(cb)，拿回
 * { status, position, duration, ended?, error?, command? }。
 * 这样绕开了「原生主线程回调 → Lynx JS 线程」的线程限制。
 */

export interface AudioState {
  status?: 'idle' | 'loading' | 'playing' | 'paused' | 'buffering';
  position?: number;
  duration?: number;
  ended?: boolean;
  error?: string;
  command?: { name?: string; value?: number };
}

interface TmAudioModule {
  load(url: string, title: string, artist: string, cover: string, duration: number): void;
  play(): void;
  pause(): void;
  seek(seconds: number): void;
  setVolume(v: number): void;
  stop(): void;
  state(cb: (json: string) => void): void;
}

let cached: TmAudioModule | null = null;

function module(): TmAudioModule | null {
  if (cached) return cached;
  // 1) 文档写法：引擎注入的全局
  try {
    const g = globalThis as unknown as { NativeModules?: Record<string, TmAudioModule> };
    if (g.NativeModules && g.NativeModules.TmAudio) {
      cached = g.NativeModules.TmAudio;
      return cached;
    }
  } catch {
    /* 某些线程没有这个全局 */
  }
  // 2) ReactLynx 里全局往往没挂，但原生 app 上的模块代理一定有
  try {
    const l = lynx as unknown as {
      getNativeApp?: () => { nativeModuleProxy?: Record<string, TmAudioModule> };
    };
    const proxy = l.getNativeApp?.()?.nativeModuleProxy;
    if (proxy && proxy.TmAudio) {
      cached = proxy.TmAudio;
      return cached;
    }
  } catch {
    /* 忽略 */
  }
  return null;
}

export function audioAvailable(): boolean {
  const m = module();
  return !!m && typeof m.load === 'function';
}

export const audio = {
  load(url: string, title: string, artist: string, cover: string, duration: number): void {
    module()?.load(url, title, artist, cover, duration);
  },
  play(): void {
    module()?.play();
  },
  pause(): void {
    module()?.pause();
  },
  seek(seconds: number): void {
    module()?.seek(seconds);
  },
  setVolume(v: number): void {
    module()?.setVolume(v);
  },
  stop(): void {
    module()?.stop();
  },
};

/**
 * 开始轮询播放状态；返回停止函数。同一时刻只保留一个轮询。
 */
export function startAudioPolling(onState: (s: AudioState) => void, intervalMs = 400): () => void {
  let stopped = false;
  let timer: ReturnType<typeof setTimeout> | null = null;

  const tick = () => {
    if (stopped) return;
    const m = module();
    if (m && typeof m.state === 'function') {
      try {
        m.state((json: string) => {
          'background only';
          try {
            const parsed = JSON.parse(json) as AudioState;
            onState(parsed);
          } catch {
            /* 忽略坏数据 */
          }
        });
      } catch {
        /* 忽略单次失败 */
      }
    }
    timer = setTimeout(tick, intervalMs);
  };

  tick();
  return () => {
    stopped = true;
    if (timer) clearTimeout(timer);
  };
}
