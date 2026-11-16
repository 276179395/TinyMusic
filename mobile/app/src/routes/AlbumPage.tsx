import { useCallback, useEffect, useState } from '@lynx-js/react';
import { api } from '@tinymusic/shared/api';
import type { AlbumPage as AlbumData, Track } from '@tinymusic/shared/types';

import { player } from '../state/player.js';

interface Props {
  provider: string;
  albumId: string;
  name: string;
  onBack: () => void;
}

/**
 * 专辑页：曲目列表 + 播放全部（接口由 crates/app 提供）。
 */
export function AlbumPage({ provider, albumId, name, onBack }: Props) {
  const [data, setData] = useState<ArtistData | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    'background only';
    setLoading(true);
    api.album(provider, albumId, name)
      .then((d) => setData(d))
      .catch((e: unknown) => setError(String(e)))
      .finally(() => setLoading(false));
  }, [provider, albumId, name]);

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
