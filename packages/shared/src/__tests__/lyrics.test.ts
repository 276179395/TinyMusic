import { describe, expect, it } from 'vitest';

import { activeLineIndex, seekSecondsForLine } from '../lyrics';
import type { LyricLine } from '../types';

const lines: LyricLine[] = [
  { time_ms: 0, text: 'a' },
  { time_ms: 1000, text: 'b' },
  { time_ms: 2500, text: 'c' },
];

describe('activeLineIndex', () => {
  it('取最后一句不晚于当前时间（含容差）', () => {
    expect(activeLineIndex(lines, 0)).toBe(0);
    expect(activeLineIndex(lines, 900)).toBe(0);
    expect(activeLineIndex(lines, 950)).toBe(1); // 60ms 容差
    // 2500 - 60 = 2440 起算作第三句
    expect(activeLineIndex(lines, 2439)).toBe(1);
    expect(activeLineIndex(lines, 2440)).toBe(2);
    expect(activeLineIndex(lines, 9999)).toBe(2);
  });

  it('没有歌词时返回 -1', () => {
    expect(activeLineIndex([], 1000)).toBe(-1);
  });

  it('点句跳播换算成秒', () => {
    expect(seekSecondsForLine({ time_ms: 2500, text: '' })).toBe(2.5);
    expect(seekSecondsForLine({ time_ms: -5, text: '' })).toBe(0);
  });
});
