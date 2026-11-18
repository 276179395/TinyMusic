//! 播放队列的纯逻辑：下一首/上一首怎么算、删一首之后当前是哪首、插播怎么放。
//!
//! 桌面（Svelte）与 mobile（ReactLynx）都调这里。状态各自持有，**规则只有一份**：
//! 随机不重复当前这首、列表循环到底回开头、单曲循环由调用方自己重开、
//! 手动「下一首」永远有下一首（和自动结束不同）。

export type RepeatMode = 'off' | 'all' | 'one';

export interface NavState {
  length: number;
  index: number;
  shuffle: boolean;
  repeat: RepeatMode;
}

export type RandomFn = () => number;

/**
 * 音频**自然结束**时的下一首；null 表示到此为止（自动停止）。
 */
export function nextIndexOnEnded(state: NavState, random: RandomFn = Math.random): number | null {
  const { length, index, shuffle, repeat } = state;
  if (length <= 0) return null;

  if (shuffle) {
    if (length === 1) return 0;
    let candidate = index;
    // 最多试 20 次：列表大于 1 时不应该随机到自己
    for (let guard = 0; guard < 20 && candidate === index; guard++) {
      candidate = Math.floor(random() * length);
    }
    return candidate;
  }

  const next = index + 1;
  if (next < length) return next;
  return repeat === 'all' ? 0 : null;
}

/**
 * 手动点「下一首」：永远有下一首（到头回到第一首），随机时随机挑。
 */
export function nextIndexManual(state: NavState, random: RandomFn = Math.random): number | null {
  const { length, index, shuffle } = state;
  if (length <= 0) return null;
  if (shuffle) return nextIndexOnEnded({ ...state, repeat: 'off' }, random);
  return (index + 1) % length;
}

/**
 * 手动点「上一首」：到头回到最后一首；随机时和「下一首」一样随机挑。
 */
export function prevIndexManual(state: NavState, random: RandomFn = Math.random): number | null {
  const { length, index, shuffle } = state;
  if (length <= 0) return null;
  if (shuffle) return nextIndexOnEnded({ ...state, repeat: 'off' }, random);
  return (index - 1 + length) % length;
}

export interface RemoveResult<T> {
  queue: T[];
  /** 删除之后当前曲目的下标（可能前移） */
  index: number;
  /** 删的就是当前这首时，应该接着播哪一首；否则为 null */
  playTarget: number | null;
}

/**
 * 删掉队列里第 removeAt 首。
 * 删的是当前曲目时，返回应该接着播的位置（后面没有就退到新的最后一条）。
 */
export function queueAfterRemove<T>(queue: readonly T[], index: number, removeAt: number): RemoveResult<T> | null {
  if (removeAt < 0 || removeAt >= queue.length) return null;

  const next = [...queue];
  next.splice(removeAt, 1);

  const removingCurrent = removeAt === index;
  let nextIndex = index;
  if (removeAt < index) nextIndex = index - 1;

  let playTarget: number | null = null;
  if (removingCurrent) {
    playTarget = next.length === 0 ? null : Math.min(removeAt, next.length - 1);
  }

  return { queue: next, index: nextIndex, playTarget };
}

export interface InsertResult<T> {
  queue: T[];
  /** 插入之后当前曲目的下标 */
  index: number;
  /** 插到第几首（用于 UI 提示） */
  at: number;
}

/**
 * 把一首歌插到当前曲目后面（「下一首播放」）。
 * 已经在队列里的先摘掉再插，避免重复；摘掉的位置在当前之前时下标要前移。
 */
export function queueInsertAfterCurrent<T>(
  queue: readonly T[],
  index: number,
  track: T,
  isSame: (a: T, b: T) => boolean
): InsertResult<T> {
  const next = [...queue];
  let current = index;

  const exist = next.findIndex((t) => isSame(t, track));
  if (exist >= 0) {
    next.splice(exist, 1);
    if (exist < current) current -= 1;
  }

  const at = Math.min(current + 1, next.length);
  next.splice(at, 0, track);
  return { queue: next, index: current, at };
}
