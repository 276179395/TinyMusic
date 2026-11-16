import { useEffect, useState } from '@lynx-js/react';

import { startAudioPolling, type AudioState } from '../native/audio.js';

export interface NowPlaying {
  status: AudioState['status'];
  position: number;
  duration: number;
  title: string;
  artist: string;
  cover: string;
}

const EMPTY: NowPlaying = {
  status: 'idle',
  position: 0,
  duration: 0,
  title: '',
  artist: '',
  cover: '',
};

/**
 * 直接读**原生播放器**的状态。
 *
 * 为什么不用 JS store：Lynx 双线程下模块级的 store 会有两份副本，
 * 某些组件拿到的不是被写入的那一份（实测迷你播放条一直显示空态）。
 * AVPlayer 的状态在原生侧只有一份，轮询它最稳。
 */
export function useNativeNowPlaying(): NowPlaying {
  const [state, setState] = useState<NowPlaying>(EMPTY);

  useEffect(() => {
    'background only';
    const stop = startAudioPolling((s: AudioState) => {
      setState((prev) => ({
        status: s.status ?? prev.status,
        position: s.position ?? prev.position,
        duration: (s.duration && s.duration > 0) ? s.duration : prev.duration,
        title: (s as unknown as { title?: string }).title ?? prev.title,
        artist: (s as unknown as { artist?: string }).artist ?? prev.artist,
        cover: (s as unknown as { cover?: string }).cover ?? prev.cover,
      }));
    }, 500);
    return stop;
  }, []);

  return state;
}
