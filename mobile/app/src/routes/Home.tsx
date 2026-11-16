import { useCallback, useEffect, useState } from '@lynx-js/react';
import { Search01Icon } from '@hugeicons/core-free-icons';
import { api } from '@tinymusic/shared/api';
import type { Track } from '@tinymusic/shared/types';

import { Icon } from '../components/Icon.js';
import { PlayerBar } from '../components/PlayerBar.js';
import { player } from '../state/player.js';
import { ensureTransport } from '../platform.js';

interface HomeProps {
  iconColor: string;
  inkIconColor: string;
  ready: boolean;
  /** 自动化冒烟：拿到结果后自动播第一首 */
  autoPlay?: boolean;
  /** 点播放条展开全屏播放页 */
  onOpenPlayer: () => void;
}

function fmt(sec: number): string {
  if (!sec) return '';
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${String(s).padStart(2, '0')}`;
}

/**
 * 首页 = 搜索 + 结果列表 + 底部播放条（P3 浏览骨架 + P5 播放的最小闭环）。
 */
export function Home({ iconColor, inkIconColor, ready, autoPlay, onOpenPlayer }: HomeProps) {
  const [kw, setKw] = useState('周杰伦');
  const [items, setItems] = useState<Track[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const search = useCallback((q: string) => {
    'background only';
    const key = q.trim();
    if (!key || !ensureTransport()) return;
    setLoading(true);
    setError('');
    api
      .search('kuwo', key, 1, 30)
      .then((page) => setItems(page.items ?? []))
      .catch((e: unknown) => setError(String(e)))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    'background only';
    if (ready) search(kw);
    // 只在后端可用后跑一次
  }, [ready, search]);

  const onInput = useCallback((e: { detail?: { value?: string } }) => {
    'background only';
    setKw(e.detail?.value ?? '');
  }, []);

  const onConfirm = useCallback(() => {
    'background only';
    search(kw);
  }, [kw, search]);

  // 冒烟钩子：拿到 autoPlay 标记时自动播第一首（TM_AUTOPLAY=1，自动化验证用）
  useEffect(() => {
    'background only';
    if (!autoPlay || items.length === 0) return;
    if (player.snapshot().current) return;
    void player.playTrack(items[0], items);
  }, [autoPlay, items]);

  const onTapTrack = useCallback((track: Track) => {
    'background only';
    void player.playTrack(track, items);
  }, [items]);

  return (
    <view className="home">
      <view className="search">
        <Icon icon={Search01Icon} size={18} color={iconColor} />
        <input
          className="search-input"
          value={kw}
          placeholder="搜索歌曲、歌手"
          bindinput={onInput}
          bindconfirm={onConfirm}
        />
        <view className="search-go" bindtap={onConfirm}>
          <text className="search-go-text">搜索</text>
        </view>
      </view>

      {error ? <text className="home-error">{error}</text> : null}
      {loading ? <text className="home-hint">搜索中…</text> : null}
      {!loading && !error && items.length === 0 ? <text className="home-hint">没有结果</text> : null}

      <scroll-view className="results" scroll-orientation="vertical">
        {items.map((t) => (
          <view className="row" key={`${t.provider}:${t.id}`} bindtap={() => onTapTrack(t)}>
            {t.cover ? <image className="row-cover" src={t.cover} /> : <view className="row-cover row-cover--ph" />}
            <view className="row-meta">
              <text className="row-title">{t.title}</text>
              <text className="row-sub">
                {t.artist}
                {t.album ? ` · ${t.album}` : ''}
              </text>
            </view>
            <text className="row-dur">{fmt(t.duration_sec)}</text>
          </view>
        ))}
      </scroll-view>

      <view bindtap={onOpenPlayer}>
        <PlayerBar iconColor={iconColor} inkIconColor={inkIconColor} />
      </view>
    </view>
  );
}
