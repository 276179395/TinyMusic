import { useCallback, useEffect, useState } from '@lynx-js/react';
import { Search01Icon } from '@hugeicons/core-free-icons';
import { api } from '@tinymusic/shared/api';
import type { PlaylistRef, Track } from '@tinymusic/shared/types';

import { Icon } from '../components/Icon.js';
import { player } from '../state/player.js';
import { downloads } from '../state/downloads.js';
import { ensureTransport } from '../platform.js';

interface HomeProps {
  iconColor: string;
  inkIconColor: string;
  ready: boolean;
  /** 自动化冒烟：拿到结果后自动播第一首 */
  autoPlay?: boolean;
  /** 自动化冒烟：拿到结果后下载第一首 */
  autoDownload?: boolean;
  /** 点播放条展开全屏播放页（保留参数，播放条在 App 层） */
  onOpenPlayer?: () => void;
  /** 打开歌单详情 */
  onOpenPlaylist: (p: PlaylistRef) => void;
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
export function Home({ iconColor, inkIconColor, ready, autoPlay, autoDownload, onOpenPlaylist }: HomeProps) {
  const [mode, setMode] = useState<'recommend' | 'search'>('recommend');
  const [recSongs, setRecSongs] = useState<Track[]>([]);
  const [recLists, setRecLists] = useState<PlaylistRef[]>([]);
  const [recLoading, setRecLoading] = useState(false);
  const [recError, setRecError] = useState('');
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

  // 推荐：每日歌曲（需登录态）+ 推荐歌单（不需要），失败各自降级
  useEffect(() => {
    'background only';
    if (!ready) return;
    setRecLoading(true);
    Promise.allSettled([api.recommendSongs('netease', 30), api.recommendPlaylists('netease')])
      .then(([songs, lists]) => {
        if (songs.status === 'fulfilled') setRecSongs(songs.value ?? []);
        else setRecError('推荐歌曲取不到（可能未登录）');
        if (lists.status === 'fulfilled') setRecLists(lists.value ?? []);
      })
      .finally(() => setRecLoading(false));
  }, [ready]);

  useEffect(() => {
    'background only';
    if (ready && mode === 'search') search(kw);
    // 切到搜索时才请求
  }, [ready, mode, search]);

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
    const feed = mode === 'search' ? items : recSongs;
    if (!autoPlay || feed.length === 0) return;

    // 竞态兜底：globalProps / 列表可能比首帧晚到，这里最多试 10 次
    let tries = 0;
    const attempt = () => {
      if (player.snapshot().current || tries >= 10) return;
      tries += 1;
      if (player.snapshot().status === 'loading') return;
      void player.playTrack(feed[0], feed);
      setTimeout(attempt, 1200);
    };
    setTimeout(attempt, 300);
  }, [autoPlay, mode, items, recSongs]);

  // 冒烟钩子：自动下载第一首（验证下载全链路）
  useEffect(() => {
    'background only';
    const feed = mode === 'search' ? items : recSongs;
    if (!autoDownload || feed.length === 0) return;
    let tries = 0;
    const attempt = () => {
      if (tries >= 3) return;
      tries += 1;
      void downloads.start(feed[0], 'super');
    };
    setTimeout(attempt, 500);
  }, [autoDownload, mode, items, recSongs]);

  const onTapTrack = useCallback((track: Track) => {
    'background only';
    void player.playTrack(track, items);
  }, [items]);

  return (
    <view className="home">
      <view className="segment">
        <view
          className={'segment-item' + (mode === 'recommend' ? ' segment-item--on' : '')}
          bindtap={() => setMode('recommend')}
        >
          <text className="segment-text">推荐</text>
        </view>
        <view
          className={'segment-item' + (mode === 'search' ? ' segment-item--on' : '')}
          bindtap={() => setMode('search')}
        >
          <text className="segment-text">搜索</text>
        </view>
      </view>

      {mode === 'recommend' ? (
        <scroll-view className="results" scroll-orientation="vertical">
          {recLoading ? <text className="home-hint">读取推荐…</text> : null}
          {recError ? <text className="home-hint">{recError}</text> : null}
          {recLists.length > 0 ? <text className="section-title">推荐歌单</text> : null}
          {recLists.map((p) => (
            <view className="row" key={'pl:' + p.id} bindtap={() => onOpenPlaylist(p)}>
              {p.cover ? <image className="row-cover" src={p.cover} /> : <view className="row-cover row-cover--ph" />}
              <view className="row-meta">
                <text className="row-title">{p.name}</text>
                <text className="row-sub">{p.creator ?? ''}</text>
              </view>
            </view>
          ))}
          {recSongs.length > 0 ? <text className="section-title">每日推荐</text> : null}
          {recSongs.map((t) => (
            <view className="row" key={'rec:' + t.provider + ':' + t.id} bindtap={() => onTapTrack(t)}>
              {t.cover ? <image className="row-cover" src={t.cover} /> : <view className="row-cover row-cover--ph" />}
              <view className="row-meta">
                <text className="row-title">{t.title}</text>
                <text className="row-sub">{t.artist}</text>
              </view>
              <text className="row-dur">{fmt(t.duration_sec)}</text>
            </view>
          ))}
        </scroll-view>
      ) : null}

      {mode === 'search' ? (
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
        </view>
      ) : null}
    </view>
  );
}
