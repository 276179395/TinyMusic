import { useCallback, useEffect } from '@lynx-js/react';
import { PageHeader } from '../components/PageHeader.js';
import { useContentHeight } from '../platform/layout.js';

import { downloads, useDownloads } from '../state/downloads.js';
import { player } from '../state/player.js';

function fmtBytes(n: number): string {
  if (!n || n <= 0) return '';
  if (n >= 1024 * 1024) return (n / 1024 / 1024).toFixed(1) + ' MB';
  if (n >= 1024) return Math.round(n / 1024) + ' KB';
  return n + ' B';
}

/**
 * 下载页：已下载列表 + 失败记录（可重试/忽略）。
 */
export function Downloads({ iconColor, playLocal }: { iconColor: string; playLocal?: boolean }) {
  const contentH = useContentHeight(112, 64);
  const d = useDownloads();

  // 冒烟钩子：TM_PLAY_LOCAL=1 时自动播第一条已下载
  useEffect(() => {
    'background only';
    if (!playLocal || d.rows.length === 0) return;
    if (player.snapshot().current) return;
    player.playLocal(d.rows[0]);
  }, [playLocal, d.rows]);

  const onRetryAll = useCallback(() => {
    'background only';
    const ids = d.failures.map((f) => f.id);
    if (ids.length) void downloads.retry(ids);
  }, [d.failures]);

  const onRefresh = useCallback(() => {
    'background only';
    void downloads.refresh();
  }, []);

  return (
    <view className="page-content">
      <PageHeader
        title="资料库"
        actions={
          <view className="ios-text-button" bindtap={onRefresh}>
            <text className="ios-text-button-label">刷新</text>
          </view>
        }
      />

      {d.error ? <text className="home-error">{d.error}</text> : null}
      {d.busy ? <text className="home-hint">{d.message}</text> : null}

      {d.failures.length > 0 ? (
        <view className="failures">
          <view className="failure-head">
            <text className="section-title">未完成 {d.failures.length}</text>
            <view bindtap={onRetryAll}>
              <text className="link-text">全部重试</text>
            </view>
          </view>
          {d.failures.map((f) => (
            <view className="failure-row" key={f.id}>
              <view className="failure-meta">
                <text className="ios-row-title">{f.track.title}</text>
                <text className="ios-row-sub">
                  {f.track.artist + ' · ' + (f.parts.map((p) => p.part).join('/') || '音频')}
                </text>
              </view>
              <view className="failure-actions">
                <view bindtap={() => void downloads.retry([f.id])}>
                  <text className="link-text">重试</text>
                </view>
                <view bindtap={() => void downloads.dismiss(f.id)}>
                  <text className="link-text link-text--muted">忽略</text>
                </view>
              </view>
            </view>
          ))}
        </view>
      ) : null}

      <scroll-view className="results" style={{ height: contentH + "px" }} scroll-orientation="vertical">
        {d.rows.length === 0 ? <text className="home-hint">还没有下载完成的曲目</text> : null}
        {d.rows.map((r) => (
          <view
            className="row"
            key={r.task_id}
            bindtap={() => {
              'background only';
              player.playLocal(r);
            }}
          >
            <view className="ios-row-text">
              <text className="ios-row-title">{r.title}</text>
              <text className="ios-row-sub">{r.artist}</text>
            </view>
            <text className="ios-row-trailing">{fmtBytes(r.bytes)}</text>
          </view>
        ))}
      </scroll-view>
    </view>
  );
}
