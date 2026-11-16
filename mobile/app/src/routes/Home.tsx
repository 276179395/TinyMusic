import { useCallback, useEffect, useState } from '@lynx-js/react';
import { Search01Icon, PlayCircleIcon } from '@hugeicons/core-free-icons';
import { api } from '@tinymusic/shared/api';
import type { PlaylistRef, Track } from '@tinymusic/shared/types';

import { Icon } from '../components/Icon.js';
import { PageHeader } from '../components/PageHeader.js';
import { player } from '../state/player.js';
import { downloads } from '../state/downloads.js';
import { ensureTransport } from '../platform.js';

interface HomeProps {
  iconColor: string;
  inkIconColor: string;
  ready: boolean;
  autoPlay?: boolean;
  autoDownload?: boolean;
  onOpenPlaylist: (p: PlaylistRef) => void;
  initialSearchKind?: string;
  autoOpenPlaylist?: boolean;
}

function clip(s: string, n: number): string {
  if (!s) return '';
  return s.length > n ? s.slice(0, n) + '…' : s;
}

function fmt(sec: number): string {
  if (!sec) return '';
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return String(m) + ':' + String(s).padStart(2, '0');
}

/**
 * 首页 = Apple Music 的「现在就听」：大标题 + 每日推荐 + 推荐歌单。
 * 搜索做成右上角入口，点开才是搜索列表（和 Apple Music 一致）。
 */
export function Home({ iconColor, inkIconColor, ready, autoPlay, autoDownload, onOpenPlaylist, initialSearchKind, autoOpenPlaylist }: HomeProps) {
  const [mode, setMode] = useState<'feed' | 'search'>(initialSearchKind ? 'search' : 'feed');
  const [recSongs, setRecSongs] = useState<Track[]>([]);
  const [recLists, setRecLists] = useState<PlaylistRef[]>([]);
  const [recLoading, setRecLoading] = useState(false);
  const [recError, setRecError] = useState('');
  const [kw, setKw] = useState('周杰伦');
  const [searchKind, setSearchKind] = useState<'song' | 'playlist'>(initialSearchKind === 'playlist' ? 'playlist' : 'song');
  const [playlistHits, setPlaylistHits] = useState<PlaylistRef[]>([]);
  const [items, setItems] = useState<Track[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const search = useCallback((q: string) => {
    'background only';
    const key = q.trim();
    if (!key || !ensureTransport()) return;
    setLoading(true);
    setError('');
    const req =
      searchKind === 'song'
        ? api.search('kuwo', key, 1, 30).then((page) => setItems(page.items ?? []))
        : api.searchPlaylists('kuwo', key, 0, 30).then((page) => setPlaylistHits(page.items ?? []));
    req.catch((e: unknown) => setError(String(e))).finally(() => setLoading(false));
  }, [searchKind]);

  useEffect(() => {
    'background only';
    if (!ready) return;
    setRecLoading(true);
    Promise.allSettled([api.recommendSongs('netease', 30), api.recommendPlaylists('netease')])
      .then(([songs, lists]) => {
        if (songs.status === 'fulfilled') setRecSongs(songs.value ?? []);
        else setRecError('推荐暂时取不到，检查一下网络');
        if (lists.status === 'fulfilled') setRecLists(lists.value ?? []);
      })
      .finally(() => setRecLoading(false));
  }, [ready]);

  useEffect(() => {
    'background only';
    if (ready && mode === 'search') search(kw);
  }, [ready, mode, search]);

  const onInput = useCallback((e: { detail?: { value?: string } }) => {
    'background only';
    setKw(e.detail?.value ?? '');
  }, []);

  const onConfirm = useCallback(() => {
    'background only';
    search(kw);
  }, [kw, search]);

  useEffect(() => {
    'background only';
    const feed = mode === 'search' ? items : recSongs;
    if (!autoPlay || feed.length === 0) return;
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

  useEffect(() => {
    'background only';
    if (!autoOpenPlaylist || playlistHits.length === 0) return;
    onOpenPlaylist(playlistHits[0]);
  }, [autoOpenPlaylist, playlistHits, onOpenPlaylist]);

  const onTapTrack = useCallback((track: Track) => {
    'background only';
    void player.playTrack(track, items.length ? items : recSongs);
  }, [items, recSongs]);

  const searchButton = (
    <view className="ios-icon-button" bindtap={() => setMode(mode === 'search' ? 'feed' : 'search')}>
      <Icon icon={mode === 'search' ? PlayCircleIcon : Search01Icon} size={18} color={iconColor} />
    </view>
  );

  return (
    <view className="ios-page">
      <PageHeader title={mode === 'search' ? '搜索' : '现在就听'} actions={searchButton} />

      {mode === 'feed' ? (
        <scroll-view className="ios-list" scroll-orientation="vertical">
          {recLoading ? <text className="ios-hint">正在加载推荐…</text> : null}
          {recError ? <text className="ios-error">{recError}</text> : null}

          {recSongs.length > 0 ? <text className="ios-section-title">每日推荐</text> : null}
          {recSongs.map((t) => (
            <view className="ios-row" key={'rec:' + t.provider + ':' + t.id} bindtap={() => onTapTrack(t)}>
              {t.cover ? (
                <image className="ios-row-art" src={t.cover} />
              ) : (
                <view className="ios-row-art ios-row-art-ph" />
              )}
              <view className="ios-row-text">
                <text className="ios-row-title">{clip(t.title, 28)}</text>
                <text className="ios-row-sub">{t.artist}</text>
              </view>
              <text className="ios-row-trailing">{fmt(t.duration_sec)}</text>
            </view>
          ))}

          {recLists.length > 0 ? <text className="ios-section-title">推荐歌单</text> : null}
          {recLists.map((p) => (
            <view className="ios-row" key={'pl:' + p.id} bindtap={() => onOpenPlaylist(p)}>
              {p.cover ? (
                <image className="ios-row-art" src={p.cover} />
              ) : (
                <view className="ios-row-art ios-row-art-ph" />
              )}
              <view className="ios-row-text">
                <text className="ios-row-title">{clip(p.name, 28)}</text>
                <text className="ios-row-sub">{(p.creator ?? '') + (p.track_count ? ' · ' + p.track_count + ' 首' : '')}</text>
              </view>
            </view>
          ))}

          {!recLoading && recSongs.length === 0 && recLists.length === 0 ? (
            <view className="ios-empty">
              <text className="ios-empty-title">暂无推荐</text>
              <text className="ios-empty-sub">点右上角的搜索，先找一首想听的</text>
            </view>
          ) : null}
        </scroll-view>
      ) : null}

      {mode === 'search' ? (
        <view className="ios-page">
          <view className="ios-segmented">
            <view
              className={'ios-segmented-item' + (searchKind === 'song' ? ' ios-segmented-item--on' : '')}
              bindtap={() => setSearchKind('song')}
            >
              <text className="ios-segmented-label">歌曲</text>
            </view>
            <view
              className={'ios-segmented-item' + (searchKind === 'playlist' ? ' ios-segmented-item--on' : '')}
              bindtap={() => setSearchKind('playlist')}
            >
              <text className="ios-segmented-label">歌单</text>
            </view>
          </view>

          <view className="ios-search-field">
            <Icon icon={Search01Icon} size={16} color={iconColor} />
            <input
              className="ios-search-input"
              value={kw}
              placeholder={searchKind === 'song' ? '搜索歌曲、歌手' : '搜索歌单'}
              bindinput={onInput}
              bindconfirm={onConfirm}
            />
            <view className="ios-text-button" bindtap={onConfirm}>
              <text className="ios-text-button-label">搜索</text>
            </view>
          </view>

          {error ? <text className="ios-error">{error}</text> : null}
          {loading ? <text className="ios-hint">搜索中…</text> : null}

          <scroll-view className="ios-list" scroll-orientation="vertical">
            {searchKind === 'playlist'
              ? playlistHits.map((p) => (
                  <view className="ios-row" key={'sp:' + p.id} bindtap={() => onOpenPlaylist(p)}>
                    {p.cover ? <image className="ios-row-art" src={p.cover} /> : <view className="ios-row-art ios-row-art-ph" />}
                    <view className="ios-row-text">
                      <text className="ios-row-title">{clip(p.name, 28)}</text>
                      <text className="ios-row-sub">{(p.creator ?? '') + (p.track_count ? ' · ' + p.track_count + ' 首' : '')}</text>
                    </view>
                  </view>
                ))
              : null}
            {searchKind === 'song'
              ? items.map((t) => (
                  <view className="ios-row" key={t.provider + ':' + t.id} bindtap={() => onTapTrack(t)}>
                    {t.cover ? <image className="ios-row-art" src={t.cover} /> : <view className="ios-row-art ios-row-art-ph" />}
                    <view className="ios-row-text">
                      <text className="ios-row-title">{clip(t.title, 28)}</text>
                      <text className="ios-row-sub">{t.artist + (t.album ? ' · ' + t.album : '')}</text>
                    </view>
                    <text className="ios-row-trailing">{fmt(t.duration_sec)}</text>
                  </view>
                ))
              : null}

            {!loading && (searchKind === 'song' ? items.length : playlistHits.length) === 0 ? (
              <view className="ios-empty">
                <text className="ios-empty-title">没有结果</text>
                <text className="ios-empty-sub">换个关键词试试</text>
              </view>
            ) : null}
          </scroll-view>
        </view>
      ) : null}
    </view>
  );
}