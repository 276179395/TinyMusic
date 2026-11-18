import { useCallback, useEffect, useState } from '@lynx-js/react';
import { api } from '@tinymusic/shared/api';
import type { ArtistPage as ArtistData, Track } from '@tinymusic/shared/types';

import { player } from '../state/player.js';

interface Props {
  provider: string;
  artistId: string;
  name: string;
  onBack: () => void;
}

/**
 * 歌手页：简介 + 热门歌曲 + 专辑列表（接口已由 crates/app 提供，这里只渲染）。
 */
export function ArtistPage({ provider, artistId, name, onBack }: Props) {
  const [data, setData] = useState<ArtistData | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    'background only';
    setLoading(true);
    api
      .artist(provider, artistId, name)
      .then((d) => setData(d))
      .catch((e: unknown) => setError(String(e)))
      .finally(() => setLoading(false));
  }, [provider, artistId, name]);

  const playAll = useCallback(() => {
    'background only';
    const tracks = data?.tracks ?? [];
    if (tracks.length) void player.playTrack(tracks[0], tracks);
  }, [data]);

  const onTap = useCallback((t: Track) => {
    'background only';
    void player.playTrack(t, data?.tracks ?? []);
  }, [data]);

  return (
    <view className="page-content">
      <view className="page-head">
        <view className="page-head-action" bindtap={onBack}>
          <text className="page-head-action-text">返回</text>
        </view>
        <view className="page-head-action" bindtap={playAll}>
          <text className="page-head-action-text">播放全部</text>
        </view>
      </view>

      <text className="page-title">{data?.name || name}</text>
      {loading ? <text className="home-hint">读取中…</text> : null}
      {error ? <text className="home-error">{error}</text> : null}

      <scroll-view className="results" scroll-orientation="vertical">
        {(data?.tracks ?? []).map((t, i) => (
          <view className="row" key={t.provider + ':' + t.id} bindtap={() => onTap(t)}>
            <text className="row-index">{String(i + 1)}</text>
            <view className="row-meta">
              <text className="row-title">{t.title}</text>
              <text className="row-sub">{t.album || t.artist}</text>
            </view>
          </view>
        ))}
      </scroll-view>
    </view>
  );
}
