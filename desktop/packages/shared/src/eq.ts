//! 均衡器数据：频段、范围、预设曲线。
//!
//! 桌面（Web Audio）与 mobile（原生 AVAudioUnitEQ）共用这一份，
//! 避免"同一个预设两个端听起来不一样"。

export interface EqualizerPreset {
  id: string;
  name: string;
  desc: string;
  gains: number[];
  preamp: number;
}

/** 频段：32 / 64 / 125 / ... / 16k，标签只写数字，单位在面板上说明。 */
export const EQ_BANDS = [
  { hz: 32, label: '32' },
  { hz: 64, label: '64' },
  { hz: 125, label: '125' },
  { hz: 250, label: '250' },
  { hz: 500, label: '500' },
  { hz: 1000, label: '1k' },
  { hz: 2000, label: '2k' },
  { hz: 4000, label: '4k' },
  { hz: 8000, label: '8k' },
  { hz: 16000, label: '16k' }
] as const;

export const EQ_MIN_DB = -12;
export const EQ_MAX_DB = 12;

const FLAT_GAINS = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

/**
 * 预设曲线。数字都按「听感」调过：
 * 低音 / 响度这类大增益的预设会给一个负的前级（留 headroom），
 * 限幅器只在真的有正增益时介入。
 */
export const EQ_PRESETS: EqualizerPreset[] = [
  {
    id: 'flat',
    name: '平直',
    desc: '不染色，所有频段 0 dB',
    preamp: 0,
    gains: FLAT_GAINS
  },
  {
    id: 'pop',
    name: '流行',
    desc: '人声和中高频更靠前，低频收一点',
    preamp: -3,
    gains: [-1, 0, 2, 3.5, 3.5, 2, 0.5, -1, -1.5, -2]
  },
  {
    id: 'rock',
    name: '摇滚',
    desc: '经典微笑曲线：鼓和贝斯更重，吉他更亮',
    preamp: -4,
    gains: [4, 3, 2, 0, -1, -1, 0, 2, 3, 4]
  },
  {
    id: 'jazz',
    name: '爵士',
    desc: '温暖的低频和铜管，中频略退',
    preamp: -3,
    gains: [3, 2, 0, 1, -1, -1, 0, 1, 2, 2.5]
  },
  {
    id: 'classical',
    name: '古典',
    desc: '保留厅堂感，弦乐和空气感更清晰',
    preamp: -3,
    gains: [3.5, 3, 2, 1, 0, 0, -0.5, 0, 2, 3]
  },
  {
    id: 'electronic',
    name: '电子',
    desc: '下潜和 hi-hat 都更突出',
    preamp: -4,
    gains: [5, 4, 1, -1, -2, 0, 1, 3, 4, 5]
  },
  {
    id: 'hiphop',
    name: '嘻哈',
    desc: '808 和底鼓更厚，顶部保留咬字',
    preamp: -5,
    gains: [6, 5, 2, 0, -1, 0, 1, 2, 3, 3]
  },
  {
    id: 'vocal',
    name: '人声',
    desc: '突出中频，压低低频和齿音',
    preamp: -3,
    gains: [-2, -2, -1, 1, 3, 4, 4, 2, 0, -1]
  },
  {
    id: 'acoustic',
    name: '原声',
    desc: '木吉他和人声都自然、靠前',
    preamp: -2,
    gains: [3, 2, 1, 1, 2, 2, 1.5, 1, 1.5, 2]
  },
  {
    id: 'bass',
    name: '低音增强',
    desc: '只抬低频，适合鼓点和小音箱',
    preamp: -7,
    gains: [8, 7, 5, 3, 1, 0, 0, 0, 0, 0]
  },
  {
    id: 'treble',
    name: '高音增强',
    desc: '更亮的高频，适合闷的耳机',
    preamp: -4,
    gains: [0, 0, 0, 0, 0, 0, 1, 3, 5, 6]
  },
  {
    id: 'loudness',
    name: '响度',
    desc: '小音量下补足两端，中频略退',
    preamp: -6,
    gains: [6, 4, 1, -2, -1, 1, 3, 4, 5, 5]
  }
];


/** 预设曲线最多允许的增益（与 slider 的范围一致） */
export const EQ_FLAT_GAINS: number[] = [...FLAT_GAINS];

/** 增益钳制：0.5 dB 步进，非法值归零 */
export function clampDb(v: number): number {
  if (!Number.isFinite(v)) return 0;
  return Math.max(EQ_MIN_DB, Math.min(EQ_MAX_DB, Math.round(v * 2) / 2));
}

/** 按预设 id 取曲线；找不到返回 null */
export function presetById(id: string): EqualizerPreset | null {
  return EQ_PRESETS.find((p) => p.id === id) ?? null;
}

/** 当前增益是否刚好等于某个预设（用于把"自定义"换回预设名） */
export function detectPreset(gains: number[], preamp: number): string | null {
  const hit = EQ_PRESETS.find(
    (p) => p.gains.length === gains.length && p.gains.every((g, i) => Math.abs(g - gains[i]) < 0.01) && Math.abs(p.preamp - preamp) < 0.01
  );
  return hit ? hit.id : null;
}
