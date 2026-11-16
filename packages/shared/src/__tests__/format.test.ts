import { describe, expect, it } from 'vitest';

import { coverUrl, fmtBytes, fmtCount, fmtDuration, formatLabel, isBlocked, parsePlaylistId, qualityLabel } from '../format';
import type { AudioFormat } from '../types';

describe('fmtDuration', () => {
  it('秒数转 m:ss', () => {
    expect(fmtDuration(0)).toBe('');
    expect(fmtDuration(-1)).toBe('');
    expect(fmtDuration(59)).toBe('0:59');
    expect(fmtDuration(60)).toBe('1:00');
    expect(fmtDuration(223)).toBe('3:43');
    expect(fmtDuration(3600)).toBe('60:00');
  });
});

describe('fmtBytes', () => {
  it('按量级选单位', () => {
    expect(fmtBytes(null)).toBe('');
    expect(fmtBytes(0)).toBe('');
    expect(fmtBytes(512)).toBe('512 B');
    expect(fmtBytes(2048)).toBe('2 KB');
    expect(fmtBytes(3.5 * 1024 * 1024)).toBe('3.5 MB');
  });
});

describe('qualityLabel / formatLabel', () => {
  it('已知档位有中文名，未知原样返回', () => {
    expect(qualityLabel('super')).toBe('高品质 320k');
    expect(qualityLabel('original')).toBe('原文件');
    expect(qualityLabel('weird')).toBe('weird');
  });

  it('无损显示采样率与位深，有损显示码率', () => {
    const flac: AudioFormat = {
      codec: 'flac', bitrate_kbps: null, sample_rate_hz: 44100, bits_per_sample: 16,
      channels: 2, lossless: true, verified: true,
    };
    expect(formatLabel(flac)).toBe('FLAC 44.1kHz 16bit');

    const mp3: AudioFormat = {
      codec: 'mp3', bitrate_kbps: 320, sample_rate_hz: 44100, bits_per_sample: null,
      channels: 2, lossless: false, verified: true,
    };
    expect(formatLabel(mp3)).toBe('MP3 320k');

    expect(formatLabel(null)).toBe('');
  });
});

describe('封面与数量', () => {
  it('酷我封面换尺寸段，网易云升 https', () => {
    expect(coverUrl('https://img1.kuwo.cn/star/albumcover/120/aa/bb.jpg', 500))
      .toBe('https://img1.kuwo.cn/star/albumcover/500/aa/bb.jpg');
    expect(coverUrl('http://p1.music.126.net/x.jpg')).toBe('https://p1.music.126.net/x.jpg');
    expect(coverUrl(null)).toBe('');
  });

  it('播放量简写', () => {
    expect(fmtCount(999)).toBe('999');
    expect(fmtCount(12345)).toBe('1.2万');
    expect(fmtCount(123456789)).toBe('1.2亿');
    expect(fmtCount(0)).toBe('');
  });
});

describe('可用性与歌单 id', () => {
  it('只有 unavailable 才算拦截', () => {
    expect(isBlocked('unavailable')).toBe(true);
    expect(isBlocked('vip_only')).toBe(false);
    expect(isBlocked('available')).toBe(false);
  });

  it('从链接/纯数字/id 参数里抽 pid', () => {
    expect(parsePlaylistId('123456')).toBe('123456');
    expect(parsePlaylistId('https://www.kuwo.cn/playlist_detail/987654321?x=1')).toBe('987654321');
    expect(parsePlaylistId('https://x.com/a?pid=55566677')).toBe('55566677');
    expect(parsePlaylistId('  ')).toBe(null);
  });
});
