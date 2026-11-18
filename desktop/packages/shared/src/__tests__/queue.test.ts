import { describe, expect, it } from 'vitest';

import {
  nextIndexManual,
  nextIndexOnEnded,
  prevIndexManual,
  queueAfterRemove,
  queueInsertAfterCurrent,
} from '../player/queue';

const nav = (length: number, index: number, shuffle = false, repeat: 'off' | 'all' | 'one' = 'off') => ({
  length,
  index,
  shuffle,
  repeat,
});

describe('nextIndexOnEnded', () => {
  it('顺序播放到底就停', () => {
    expect(nextIndexOnEnded(nav(3, 0))).toBe(1);
    expect(nextIndexOnEnded(nav(3, 2))).toBe(null);
  });

  it('列表循环到底回第一首', () => {
    expect(nextIndexOnEnded(nav(3, 2, false, 'all'))).toBe(0);
  });

  it('随机不重复当前这首', () => {
    // 前两次随机到当前下标（0），第三次换到 2
    const seq = [0, 0, 0.99];
    let i = 0;
    const random = () => seq[Math.min(i++, seq.length - 1)];
    expect(nextIndexOnEnded(nav(3, 0, true), random)).toBe(2);
  });

  it('只有一首时随机也播它', () => {
    expect(nextIndexOnEnded(nav(1, 0, true))).toBe(0);
  });

  it('空队列返回 null', () => {
    expect(nextIndexOnEnded(nav(0, -1))).toBe(null);
  });
});

describe('手动切歌', () => {
  it('下一首到头回第一首（不受 repeat 影响）', () => {
    expect(nextIndexManual(nav(3, 2))).toBe(0);
    expect(nextIndexManual(nav(3, 1))).toBe(2);
  });

  it('上一首开头回最后一首', () => {
    expect(prevIndexManual(nav(3, 0))).toBe(2);
    expect(prevIndexManual(nav(3, 2))).toBe(1);
  });

  it('随机模式下前后都用随机挑', () => {
    const random = () => 0.9;
    expect(nextIndexManual(nav(5, 0, true), random)).toBe(4);
    expect(prevIndexManual(nav(5, 0, true), random)).toBe(4);
  });
});

describe('queueAfterRemove', () => {
  it('删非当前、在当前之前：当前下标前移', () => {
    const r = queueAfterRemove(['a', 'b', 'c'], 2, 0)!;
    expect(r.queue).toEqual(['b', 'c']);
    expect(r.index).toBe(1);
    expect(r.playTarget).toBe(null);
  });

  it('删当前这首：接着播原位置那首', () => {
    const r = queueAfterRemove(['a', 'b', 'c'], 1, 1)!;
    expect(r.queue).toEqual(['a', 'c']);
    expect(r.index).toBe(1);
    expect(r.playTarget).toBe(1);
  });

  it('删最后剩下的那首当前：没有可播目标', () => {
    const r = queueAfterRemove(['a'], 0, 0)!;
    expect(r.queue).toEqual([]);
    expect(r.playTarget).toBe(null);
  });

  it('下标越界返回 null', () => {
    expect(queueAfterRemove(['a'], 0, 3)).toBe(null);
  });
});

describe('queueInsertAfterCurrent', () => {
  const same = (a: string, b: string) => a === b;

  it('插到当前之后', () => {
    const r = queueInsertAfterCurrent(['a', 'c'], 0, 'b', same);
    expect(r.queue).toEqual(['a', 'b', 'c']);
    expect(r.index).toBe(0);
    expect(r.at).toBe(1);
  });

  it('已在后面的歌先摘掉再插', () => {
    const r = queueInsertAfterCurrent(['a', 'b', 'c'], 0, 'c', same);
    expect(r.queue).toEqual(['a', 'c', 'b']);
    expect(r.at).toBe(1);
  });

  it('摘掉的歌在当前之前，当前下标要前移', () => {
    const r = queueInsertAfterCurrent(['a', 'b', 'c'], 2, 'a', same);
    expect(r.queue).toEqual(['b', 'c', 'a']);
    expect(r.index).toBe(1);
  });
});
