//! 展示层纯函数：时长、字节、音质、格式、封面的格式化。

import type { AudioFormat, Availability } from './types';

export function fmtDuration(sec: number): string {
  if (!sec || sec < 0) return '';
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${String(s).padStart(2, '0')}`;
}

export function fmtBytes(n: number | null | undefined): string {
  if (!n) return '';
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(0)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

/** 音质代码 → 中文，下载记录等处直接展示 */
export const QUALITY_LABEL: Record<string, string> = {
  standard: '标准 128k',
  high: '标准 128k', // 旧记录兼容
  super: '高品质 320k',
  lossless: '无损 FLAC',
  hires: 'Hi-Res',
  atmos: '杜比全景声',
  master: '母带',
  original: '原文件',
};

export function qualityLabel(q: string): string {
  return QUALITY_LABEL[q] ?? q;
}

/** 实际格式 → 界面短标签，例如 `FLAC 44.1kHz/16bit`、`MP3 320k` */
export function formatLabel(f: AudioFormat | null | undefined): string {
  if (!f || f.codec === 'unknown') return '';
  const codec = f.codec.toUpperCase();
  if (f.lossless) {
    const hz = f.sample_rate_hz ? `${(f.sample_rate_hz / 1000).toFixed(1).replace('.0', '')}kHz` : '';
    const bits = f.bits_per_sample ? `${f.bits_per_sample}bit` : '';
    return [codec, hz, bits].filter(Boolean).join(' ');
  }
  return f.bitrate_kbps ? `${codec} ${f.bitrate_kbps}k` : codec;
}

export const AVAILABILITY_LABEL: Record<Availability, string> = {
  unknown: '',
  available: '',
  preview_only: '仅试听',
  vip_only: '会员曲',
  unavailable: '不可用',
};

/** 该曲目是否确定无法播放。
 *
 * 注意：`vip_only`（PAY=16711935）**不再**算作不可播放 ——
 * provider 现在会落到资源管理链路拿到真直链，会员曲可以正常播放，
 * 该标记只作为「这是会员内容」的提示。 */
export function isBlocked(a: Availability): boolean {
  return a === 'unavailable';
}


/** 从酷我歌单链接 / 纯数字 / playlist?id= 中抽出 pid */
export function parsePlaylistId(input: string): string | null {
  const t = input.trim();
  if (!t) return null;
  if (/^\d+$/.test(t)) return t;
  const m =
    t.match(/playlist[_-]?detail\/(\d+)/i) ||
    t.match(/[?&](?:id|pid|playlistid)=(\d+)/i) ||
    t.match(/(\d{6,})/);
  return m ? m[1] : null;
}

/**
 * 酷我封面 URL 自带尺寸段（如 `/star/albumcover/120/...`），
 * 把尺寸段换成更大的值就能拿到同图的高清版（实测 500/800/1000 都可用）。
 * 列表缩略图继续用 120，详情/歌词这种大图再用这个函数换大图。
 */
export function coverUrl(url: string | null | undefined, size = 500): string {
  if (!url) return '';
  // 网易云的 p*.music.126.net 经常给 http，WebView 会把这种图片当混合内容拦掉
  // （每日推荐、我的歌单尤其明显），这里统一升到 https。
  const safe = url.replace(/^http:\/\/([a-z0-9-]+\.music\.126\.net)/i, 'https://$1');
  if (!/kuwo\.cn/i.test(safe)) return safe;
  return safe.replace(/\/(\d{2,4})\//, `/${size}/`);
}

export function fmtCount(n: number): string {
  if (!n) return '';
  if (n >= 100_000_000) return `${(n / 100_000_000).toFixed(1)}亿`;
  if (n >= 10_000) return `${(n / 10_000).toFixed(1)}万`;
  return String(n);
}
