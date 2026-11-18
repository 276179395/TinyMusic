import { useEffect, useState } from '@lynx-js/react';
import { api } from '@tinymusic/shared/api';
import type { DownloadRow, LyricLine, Quality, Track } from '@tinymusic/shared/types';
import { nextIndexManual, nextIndexOnEnded, prevIndexManual, type RepeatMode } from '@tinymusic/shared/player/queue';

import { audio, startAudioPolling, type AudioState } from '../native/audio.js';

export type PlayStatus = 'idle' | 'loading' | 'playing' | 'paused' | 'error';

export interface PlayerSnapshot {
  queue: Track[];
  index: number;
  current: Track | null;
  status: PlayStatus;
  position: number;
  duration: number;
  volume: number;
  shuffle: boolean;
  repeat: RepeatMode;
  error: string;
  /** 当前选择的音质；切歌/切音质都会走同一个取流口 */
  quality: Quality;
  /** 这首能播哪些档位（列表接口给的 MINFO） */
  availableQualities: Quality[];
  /** 歌词（详情接口拿） */
  lyrics: LyricLine[];
  lyricsLoading: boolean;
  lyricsError: string;
}

type Listener = () => void;

/**
 * 播放器状态机（mobile）。
 *
 * 与桌面共用同一套队列规则（packages/shared/player/queue），
 * 但音频引擎不同：这里通过原生 TmAudio，桌面是 <audio> + Web Audio。
 */
class PlayerStore {
  private state: PlayerSnapshot = {
    queue: [],
    index: -1,
    current: null,
    status: 'idle',
    position: 0,
    duration: 0,
    volume: 0.9,
    shuffle: false,
    repeat: 'off',
    error: '',
    quality: 'super',
    availableQualities: [],
    lyrics: [],
    lyricsLoading: false,
    lyricsError: '',
  };

  private listeners = new Set<Listener>();
  private playToken = 0;
  private stopPolling: (() => void) | null = null;

  constructor() {
    this.stopPolling = startAudioPolling((s) => this.onAudioState(s));
  }

  snapshot(): PlayerSnapshot {
    return { ...this.state, queue: [...this.state.queue] };
  }

  subscribe(fn: Listener): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  private notify(): void {
    const snap = this.snapshot();
    for (const fn of this.listeners) fn();
    void snap;
  }

  private patch(next: Partial<PlayerSnapshot>): void {
    this.state = { ...this.state, ...next };
    this.notify();
  }

  private navState() {
    return {
      length: this.state.queue.length,
      index: this.state.index,
      shuffle: this.state.shuffle,
      repeat: this.state.repeat,
    };
  }

  private onAudioState(s: AudioState): void {
    if (typeof s.position === 'number' || typeof s.duration === 'number') {
      this.patch({
        position: s.position ?? this.state.position,
        duration: (s.duration && s.duration > 0) ? s.duration : this.state.duration,
      });
      void s.status;
    }

    if (s.status && s.status !== this.state.status) {
      this.patch({ status: s.status as PlayStatus });
    }

    if (s.error) {
      this.patch({ status: 'error', error: s.error });
    }

    if (s.ended) {
      const next = nextIndexOnEnded(this.navState());
      if (next === null) this.patch({ status: 'paused', position: this.state.duration });
      else void this.startAt(next);
    }

    if (s.command) {
      const name = s.command.name;
      if (name === 'play') this.resume();
      else if (name === 'pause') this.pause();
      else if (name === 'next') this.next();
      else if (name === 'prev') this.prev();
      else if (name === 'seek' && typeof s.command.value === 'number') this.seekTo(s.command.value);
    }
  }

  async startAt(i: number): Promise<void> {
    const track = this.state.queue[i];
    if (!track) return;
    const token = ++this.playToken;
    this.patch({
      index: i,
      current: track,
      status: 'loading',
      position: 0,
      duration: track.duration_sec || 0,
      error: '',
      availableQualities: track.available_qualities ?? [],
      lyrics: [],
      lyricsError: '',
    });
    void this.loadLyrics(track);

    try {
      let src = await api.playerOpen(track, this.state.quality, false, true);
      if (token !== this.playToken) return;
      if (!src?.url) {
        src = await api.playerOpen(track, this.state.quality, true, true);
      }
      if (token !== this.playToken) return;
      audio.load(src.url, track.title, track.artist, track.cover ?? '', track.duration_sec || 0);
      audio.setVolume(this.state.volume);
      audio.play();
      this.patch({ status: 'playing' });
    } catch (e) {
      if (token !== this.playToken) return;
      this.patch({ status: 'error', error: String(e) });
    }
  }

  async playTrack(track: Track, queue?: Track[]): Promise<void> {
    if (queue && queue.length > 0) {
      const i = queue.findIndex((t) => t.provider === track.provider && t.id === track.id);
      this.patch({ queue: [...queue], index: i >= 0 ? i : 0 });
    } else if (this.state.queue.length === 0) {
      this.patch({ queue: [track], index: 0 });
    } else {
      const i = this.state.queue.findIndex((t) => t.provider === track.provider && t.id === track.id);
      if (i >= 0) this.patch({ index: i });
      else this.patch({ queue: [...this.state.queue, track], index: this.state.queue.length });
    }
    await this.startAt(this.state.index);
  }

  /**
   * 播放已下载到本机的文件（离线播放）。
   * iOS 沙盒内直接用 file:// 交给 AVPlayer，不走后端流代理。
   */
  playLocal(row: DownloadRow): void {
    const track = {
      provider: row.provider || 'local',
      id: row.id,
      title: row.title,
      artist: row.artist,
      album: '',
      cover: '',
      duration_sec: 0,
      availability: 'unknown',
      available_qualities: [],
    } as unknown as Track;

    this.playToken += 1;
    this.patch({
      queue: [track],
      index: 0,
      current: track,
      status: 'loading',
      position: 0,
      duration: 0,
      error: '',
      lyrics: [],
      lyricsError: '',
    });
    audio.loadLocal(row.path, row.title, row.artist);
    audio.setVolume(this.state.volume);
    audio.play();
    this.patch({ status: 'playing' });
  }

  resume(): void {
    if (!this.state.current) return;
    audio.play();
    this.patch({ status: 'playing' });
  }

  pause(): void {
    audio.pause();
    this.patch({ status: 'paused' });
  }

  toggle(): void {
    if (!this.state.current) return;
    if (this.state.status === 'playing') this.pause();
    else this.resume();
  }

  seekTo(seconds: number): void {
    audio.seek(seconds);
    this.patch({ position: seconds });
  }

  next(): void {
    const i = nextIndexManual(this.navState());
    if (i !== null) void this.startAt(i);
  }

  prev(): void {
    const i = prevIndexManual(this.navState());
    if (i !== null) void this.startAt(i);
  }

  /** 拉歌词：详情接口顺带返回，失败不阻塞播放 */
  async loadLyrics(track: Track): Promise<void> {
    this.patch({ lyricsLoading: true, lyricsError: '' });
    try {
      const detail = await api.detail(track.provider, track);
      if (this.state.current?.id !== track.id) return;
      this.patch({ lyrics: detail.lyrics ?? [], lyricsLoading: false });
    } catch (e) {
      if (this.state.current?.id !== track.id) return;
      this.patch({ lyricsLoading: false, lyricsError: String(e) });
    }
  }

  /** 切音质：保留当前进度，重新取流 */
  async setQuality(q: Quality): Promise<void> {
    if (q === this.state.quality) return;
    const track = this.state.current;
    const at = this.state.position;
    const wasPlaying = this.state.status === 'playing';
    this.patch({ quality: q });
    if (!track) return;
    try {
      await api.qualitySet(q);
    } catch {
      /* 设置写入失败不影响本次播放 */
    }
    this.patch({ status: 'loading' });
    try {
      const src = await api.playerOpen(track, q, true, true);
      audio.load(src.url, track.title, track.artist, track.cover ?? '', track.duration_sec || 0);
      audio.setVolume(this.state.volume);
      if (at > 0) audio.seek(at);
      if (wasPlaying) audio.play();
      this.patch({ status: wasPlaying ? 'playing' : 'paused', error: '' });
    } catch (e) {
      this.patch({ status: 'error', error: String(e) });
    }
  }

  setVolume(v: number): void {
    const clamped = Math.max(0, Math.min(1, v));
    audio.setVolume(clamped);
    this.patch({ volume: clamped });
  }

  toggleShuffle(): void {
    this.patch({ shuffle: !this.state.shuffle });
  }

  cycleRepeat(): void {
    const order: RepeatMode[] = ['off', 'all', 'one'];
    const i = order.indexOf(this.state.repeat);
    this.patch({ repeat: order[(i + 1) % order.length] });
  }
}

export const player = new PlayerStore();

/** 组件里用：订阅快照 */
export function usePlayer(): PlayerSnapshot {
  const [snap, setSnap] = useState<PlayerSnapshot>(player.snapshot());
  useEffect(() => {
    'background only';
    return player.subscribe(() => setSnap(player.snapshot()));
  }, []);
  return snap;
}
