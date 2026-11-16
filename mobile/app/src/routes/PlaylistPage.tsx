import { useCallback, useEffect, useState } from '@lynx-js/react';
import { api } from '@tinymusic/shared/api';
import type { PlaylistDetail, PlaylistRef, Track } from '@tinymusic/shared/types';

import { player } from '../state/player.js';
import { api } from '@tinymusic/shared/api';

interface PlaylistPageProps {
  playlist: PlaylistRef;
  onBack: () => void;
}

/**
 * 歌单详情：曲目列表 + 一键播放全部。
 * 取数与解析在 Rust（crates/app::playlist），这里只渲染和入队。
 */
export function PlaylistPage({ playlist, onBack }: PlaylistPageProps) {
  const [detail, setDetail] = useState<PlaylistDetail | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [importing, setImporting] = useState('');
  const [message, setMessage] = useState('');

  useEffect(() => {
    'background only';
    setLoading(true);
    api
      .playlist(playlist.provider, playlist.id)
      .then((d) => setDetail(d))
      .catch((e: unknown) => setError(String(e)))
      .finally(() => setLoading(false));
  }, [playlist.provider, playlist.id]);

  /** 把当前歌单导入网盘（桶里的目录），进度从后端推回 */
  const onImport = useCallback(() => {
    'background only';
    setImporting('准备中…');
    setMessage('');
    api
      .s3ImportPlaylist('kuwo', playlist.id, playlist.name, (p: { done?: number; total?: number }) => {
        setImporting('导入中 ' + String(p.done ?? 0) + '/' + String(p.total ?? '?'));
      })
      .then((r) => setMessage('导入完成：成功 ' + r.uploaded + ' 首，失败 ' + r.failed + ' 首'))
      .catch((e: unknown) => setMessage(String(e)))
      .finally(() => setImporting(''));
  }, [playlist.id, playlist.name]);

  const playAll = useCallback(() => {
    'background only';
    const tracks = detail?.tracks ?? [];
    if (tracks.length) void player.playTrack(tracks[0], tracks);
  }, [detail]);

  const onTap = useCallback((track: Track) => {
    'background only';
    void player.playTrack(track, detail?.tracks ?? []);
  }, [detail]);

  const tracks = detail?.tracks ?? [];

  return (
    <view className="page-content">
      <view className="page-head">
        <view className="page-head-action" bindtap={onBack}>
          <text className="page-head-action-text">返回</text>
        </view>
        <view className="row-actions">
          <view className="page-head-action" bindtap={onImport}>
            <text className="page-head-action-text">{importing || '导入网盘'}</text>
          </view>
          <view className="page-head-action" bindtap={playAll}>
            <text className="page-head-action-text">播放全部</text>
          </view>
        </view>
      </view>

      <view className="playlist-head">
        {playlist.cover ? <image className="playlist-cover" src={playlist.cover} /> : null}
        <view className="playlist-meta">
          <text className="page-title">{playlist.name}</text>
          <text className="section-hint">
            {playlist.creator ? playlist.creator + ' · ' : ''}
            {(detail ? tracks.length : playlist.track_count) + ' 首'}
          </text>
        </view>
      </view>

      {loading ? <text className="home-hint">读取中…</text> : null}
      {message ? <text className="home-hint">{message}</text> : null}
      {error ? <text className="home-error">{error}</text> : null}

      <scroll-view className="results" scroll-orientation="vertical">
        {tracks.map((t, i) => (
          <view className="row" key={t.provider + ':' + t.id} bindtap={() => onTap(t)}>
            <text className="row-index">{String(i + 1)}</text>
            <view className="row-meta">
              <text className="row-title">{t.title}</text>
              <text className="row-sub">{t.artist}</text>
            </view>
          </view>
        ))}
      </scroll-view>
    </view>
  );
}
