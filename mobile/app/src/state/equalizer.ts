import { useEffect, useState } from '@lynx-js/react';

import { EQ_BANDS, EQ_FLAT_GAINS, EQ_PRESETS, clampDb, type EqualizerPreset } from '@tinymusic/shared/eq';

import { audio } from '../native/audio.js';

export interface EqState {
  enabled: boolean;
  gains: number[];
  preamp: number;
  preset: string;
}

const INITIAL: EqState = {
  enabled: false,
  gains: [...EQ_FLAT_GAINS],
  preamp: 0,
  preset: 'flat',
};

type Listener = () => void;

/**
 * 均衡器状态（mobile）。
 *
 * 频段/预设与桌面共用 packages/shared/eq；DSP 在原生（MTAudioProcessingTap）。
 * 目前是内存态：重开 App 回到默认，后续可以写进 settings。
 */
class EqualizerStore {
  private state: EqState = { ...INITIAL, gains: [...INITIAL.gains] };
  private listeners = new Set<Listener>();

  snapshot(): EqState {
    return { ...this.state, gains: [...this.state.gains] };
  }

  subscribe(fn: Listener): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  private apply(next: EqState): void {
    this.state = next;
    audio.setEQ(next.enabled, next.gains, next.preamp);
    for (const fn of this.listeners) fn();
  }

  setEnabled(enabled: boolean): void {
    this.apply({ ...this.state, enabled });
  }

  setBand(index: number, db: number): void {
    const gains = [...this.state.gains];
    gains[index] = clampDb(Math.round(db * 2) / 2);
    this.apply({ ...this.state, gains, preset: 'custom' });
  }

  setPreamp(db: number): void {
    this.apply({ ...this.state, preamp: clampDb(db) });
  }

  usePreset(preset: EqualizerPreset): void {
    this.apply({
      ...this.state,
      gains: [...preset.gains],
      preamp: preset.preamp ?? 0,
      preset: preset.id,
      enabled: true,
    });
  }

  reset(): void {
    this.apply({ ...INITIAL, gains: [...INITIAL.gains] });
  }
}

export const equalizer = new EqualizerStore();

export function useEqualizer(): EqState {
  const [snap, setSnap] = useState<EqState>(equalizer.snapshot());
  useEffect(() => {
    'background only';
    setSnap(equalizer.snapshot());
    return equalizer.subscribe(() => setSnap(equalizer.snapshot()));
  }, []);
  return snap;
}

export { EQ_BANDS, EQ_PRESETS };
