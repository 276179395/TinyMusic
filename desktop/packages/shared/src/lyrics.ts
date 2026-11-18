//! 歌词行定位：点句跳播、逐行高亮、自动滚动都靠它。
//!
//! 与桌面一致：取「最后一句 time_ms <= 当前 + 容差」；容差 60ms 是为了
//! 抵消音频进度回调的抖动，不然刚切到下一句时会闪一下。

import type { LyricLine } from './types';

export const LYRIC_LEAD_MS = 60;

/**
 * 当前应该高亮的行下标；还没到第一句时返回 -1。
 */
export function activeLineIndex(lines: LyricLine[], positionMs: number, leadMs = LYRIC_LEAD_MS): number {
  if (lines.length === 0) return -1;
  const target = positionMs + leadMs;
  let lo = 0;
  let hi = lines.length - 1;
  let ans = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (lines[mid].time_ms <= target) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}

/** 点句跳播用：把某一行的时间换算成播放位置（秒） */
export function seekSecondsForLine(line: LyricLine): number {
  return Math.max(0, line.time_ms / 1000);
}
