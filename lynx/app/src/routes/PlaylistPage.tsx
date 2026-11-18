import { useCallback, useEffect, useState } from '@lynx-js/react';
import { api } from '@tinymusic/shared/api';
import type { PlaylistDetail, PlaylistRef, Track } from '@tinymusic/shared/types';

import { player } from '../state/player.js';
import { api } from '@tinymusic/shared/api';

interface PlaylistPageProps {
  playlist: PlaylistRef;
  onBack: () => void;
  /** 冒烟：进页面就进多选态并选中前两首 */
  autoBatch?: boolean;
}

/**
 * 歌单详情：曲目列表 + 一键播放全部。
 * 取数与解析在 Rust（crates/app::playlist），这里只渲染和入队。
 */
export function PlaylistPage({ playlist, onBack, autoBatch }: PlaylistPageProps) {
  const [detail, setDetail] = useState<PlaylistDetail | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [importing, setImporting] = useState('');
  const [message, setMessage] = useState('');
  const [selecting, setSelecting] = useState(false);
  const [selected, setSelected] = useState<string[]>([]);

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

  const toggleSelect = useCallback((track: Track) => {
    'background only';
    const id = track.provider + ':' + track.id;
    setSelected((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  }, []);

  /** 批量下载选中曲目（编排在 crates/app，进度从后端推回） */
  const onBatchDownload = useCallback(() => {
    'background only';
    const tracks = (detail?.tracks ?? []).filter((t) => selected.includes(t.provider + ':' + t.id));
    if (!tracks.length) return;
    setMessage('批量下载中…');
    api
      .downloadBatch(tracks, 'super', (p: { done?: number; total?: number }) => {
        setMessage('下载中 ' + String(p.done ?? 0) + '/' + String(p.total ?? tracks.length));
      })
      .then(() => setMessage('已开始下载 ' + tracks.length + ' 首'))
      .catch((e: unknown) => setMessage(String(e)));
  }, [detail, selected]);

  // 冒烟钩子：自动进多选并选中前两首
  useEffect(() => {
    'background only';
    if (!autoBatch || !detail || selecting) return;
    setSelecting(true);
    setSelected(detail.tracks.slice(0, 2).map((t) => t.provider + ':' + t.id));
    // 再等一拍，让选中态先渲染出来，然后真的发起批量下载
    setTimeout(() => {
      const tracks = detail.tracks.slice(0, 2);
      setMessage('批量下载中…');
      api
        .downloadBatch(tracks, 'super', (p: { done?: number; total?: number }) => {
          setMessage('下载中 ' + String(p.done ?? 0) + '/' + String(p.total ?? tracks.length));
        })
        .then(() => setMessage('已开始下载 ' + tracks.length + ' 首'))
        .catch((e: unknown) => setMessage(String(e)));
    }, 800);
  }, [autoBatch, detail, selecting]);

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
          <view className="page-head-action" bindtap={() => { setSelecting((v) => !v); setSelected([]); }}>
            <text className="page-head-action-text">{selecting ? '取消多选' : '多选'}</text>
          </view>
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

      {selecting ? (
        <view className="batch-bar">
          <text className="batch-count">{'已选 ' + selected.length + ' 首'}</text>
          <view className="row-actions">
            <view className="page-head-action" bindtap={onBatchDownload}>
              <text className="page-head-action-text">下载</text>
            </view>
          </view>
        </view>
      ) : null}

      <scroll-view className="results" scroll-orientation="vertical">
        {tracks.map((t, i) => (
          <view
            className={'row' + (selected.includes(t.provider + ':' + t.id) ? ' row--selected' : '')}
            key={t.provider + ':' + t.id}
            bindtap={() => (selecting ? toggleSelect(t) : onTap(t))}
          >
            <text className="row-index">{selecting ? (selected.includes(t.provider + ':' + t.id) ? '✓' : String(i + 1)) : String(i + 1)}</text>
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
