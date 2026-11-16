import { describe, expect, it } from 'vitest';

import { QUALITY_ORDER, qualityChoices } from '../quality';
import type { QualityCapability, Track, TrackQualities } from '../types';

const caps: QualityCapability[] = QUALITY_ORDER.map((value) => ({
  value,
  label: value,
  kbps: null,
  lossless: value === 'lossless',
  available: ['standard', 'super', 'lossless'].includes(value),
  reason: null,
}));

function track(partial: Partial<Track> = {}): Track {
  return {
    provider: 'kuwo', id: '1', title: 't', artist: 'a', artist_id: '1',
    album: '', album_id: '', duration_sec: 200, cover: null,
    availability: 'available', subtitle: null, ...partial,
  };
}

describe('qualityChoices', () => {
  it('高级三档永远禁用', () => {
    const list = qualityChoices(track(), caps, null, 'super');
    for (const q of ['hires', 'atmos', 'master']) {
      expect(list.find((x) => x.value === q)?.disabled).toBe(true);
    }
  });

  it('未知档位时先禁用无损', () => {
    const list = qualityChoices(track(), caps, null, 'super');
    expect(list.find((x) => x.value === 'lossless')?.disabled).toBe(true);
  });

  it('探测结果说明没有无损时保持禁用，有的放开', () => {
    const noLossless: TrackQualities = { available: ['standard', 'super'], has_advanced: true, known: true };
    expect(qualityChoices(track(), caps, noLossless, 'super').find((x) => x.value === 'lossless')?.disabled).toBe(true);

    const withLossless: TrackQualities = { available: ['standard', 'super', 'lossless'], has_advanced: true, known: true };
    expect(qualityChoices(track(), caps, withLossless, 'super').find((x) => x.value === 'lossless')?.disabled).toBe(false);
  });

  it('标出当前档位', () => {
    const list = qualityChoices(track(), caps, null, 'standard');
    expect(list.filter((x) => x.current).map((x) => x.value)).toEqual(['standard']);
  });
});
