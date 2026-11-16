import { describe, expect, it } from 'vitest';

import { EQ_BANDS, EQ_PRESETS, clampDb, detectPreset, presetById } from '../eq';

describe('均衡器数据', () => {
  it('10 个频段，每个预设都有 10 段增益', () => {
    expect(EQ_BANDS).toHaveLength(10);
    for (const p of EQ_PRESETS) expect(p.gains).toHaveLength(10);
  });

  it('桌面与 mobile 用同一份预设（12 个，id 稳定）', () => {
    expect(EQ_PRESETS.map((p) => p.id)).toEqual([
      'flat', 'pop', 'rock', 'jazz', 'classical', 'electronic',
      'hiphop', 'vocal', 'acoustic', 'bass', 'treble', 'loudness',
    ]);
  });

  it('钳制到 0.5dB 步进与 ±12dB', () => {
    expect(clampDb(3.3)).toBe(3.5);
    expect(clampDb(99)).toBe(12);
    expect(clampDb(-99)).toBe(-12);
    expect(clampDb(Number.NaN)).toBe(0);
  });

  it('能按曲线反查预设', () => {
    const flat = presetById('flat')!;
    expect(detectPreset(flat.gains, flat.preamp)).toBe('flat');
    expect(detectPreset([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0)).toBe(null);
  });
});
