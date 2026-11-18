import { useCallback, useEffect, useState } from '@lynx-js/react';
import { PageHeader } from '../components/PageHeader.js';
import { useContentHeight } from '../platform/layout.js';
import { api } from '@tinymusic/shared/api';
import type { S3IntegrityReport, S3PlaylistInfo, S3TrackRow, Settings as SettingsModel } from '@tinymusic/shared/types';

interface CloudProps {
  iconColor: string;
  /** 冒烟：自动打开第一个歌单 */
  autoOpen?: boolean;
}

/**
 * 网盘（S3 兼容）：歌单/曲目浏览 + 连通性测试 + 完整性检查。
 * 桶里的目录结构、校验算法都在 Rust（crates/core::s3），这里只展示。
 */
export function Cloud({ iconColor, autoOpen }: CloudProps) {
  const contentH = useContentHeight(112, 64);
  const [enabled, setEnabled] = useState<boolean | null>(null);
  const [playlists, setPlaylists] = useState<S3PlaylistInfo[]>([]);
  const [current, setCurrent] = useState<string | null>(null);
  const [tracks, setTracks] = useState<S3TrackRow[]>([]);
  const [report, setReport] = useState<S3IntegrityReport | null>(null);
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');

  const loadPlaylists = useCallback(() => {
    'background only';
    setBusy('读取歌单…');
    api
      .s3Playlists()
      .then((list) => setPlaylists(list))
      .catch((e: unknown) => setError(String(e)))
      .finally(() => setBusy(''));
  }, []);

  useEffect(() => {
    'background only';
    api
      .settingsGet()
      .then((s: SettingsModel) => {
        setEnabled(s.s3_enabled && !!s.s3_endpoint && !!s.s3_bucket);
        if (s.s3_enabled && s.s3_endpoint && s.s3_bucket) loadPlaylists();
      })
      .catch((e: unknown) => setError(String(e)));
  }, [loadPlaylists]);

  const onOpen = useCallback((name: string, root?: boolean) => {
    'background only';
    setCurrent(name);
    setBusy('读取曲目…');
    api
      .s3PlaylistTracks(name, !!root)
      .then((rows) => setTracks(rows))
      .catch((e: unknown) => setError(String(e)))
      .finally(() => setBusy(''));
  }, []);

  // 冒烟钩子：列表到手后自动进第一个歌单
  useEffect(() => {
    'background only';
    if (!autoOpen || current || playlists.length === 0) return;
    const first = playlists[0];
    setCurrent(first.name);
    api
      .s3PlaylistTracks(first.name, !!first.root)
      .then((rows) => setTracks(rows))
      .catch((e: unknown) => setError(String(e)));
  }, [autoOpen, current, playlists]);

  const onTest = useCallback(() => {
    'background only';
    setBusy('测试连接…');
    setError('');
    api
      .s3Test()
      .then((msg) => setReport({ ok: true, checked: 0, issues: [], message: msg } as unknown as S3IntegrityReport))
      .catch((e: unknown) => setError(String(e)))
      .finally(() => setBusy(''));
  }, []);

  const onFix = useCallback(() => {
    'background only';
    if (!report) return;
    const ids = report.issues.map((i) => i.id).filter(Boolean);
    setBusy('修复中…');
    setError('');
    api
      .s3IntegrityFix(current, ids, (p: { done?: number; total?: number }) => {
        setBusy('修复中 ' + String(p.done ?? 0) + '/' + String(p.total ?? ids.length));
      })
      .then(() => {
        setMessage('修复完成');
        return api.s3IntegrityCheck(current);
      })
      .then((r) => setReport(r))
      .catch((e: unknown) => setError(String(e)))
      .finally(() => setBusy(''));
  }, [current, report]);

  const onIntegrity = useCallback(() => {
    'background only';
    setBusy('检查完整性…');
    setError('');
    api
      .s3IntegrityCheck(current)
      .then((r) => setReport(r))
      .catch((e: unknown) => setError(String(e)))
      .finally(() => setBusy(''));
  }, [current]);

  if (enabled === false) {
    return (
      <view className="page-content">
        <PageHeader title="网盘" />
        <text className="ios-hint">还没配置网盘</text>
        <text className="section-hint">去「设置 → 网盘」填 endpoint / bucket / 密钥，教程和桌面端一致</text>
      </view>
    );
  }

  return (
    <view className="page-content">
      <PageHeader
        title="网盘"
        actions={
          <view className="ios-nav-actions">
            <view className="ios-text-button" bindtap={onTest}>
              <text className="ios-text-button-label">试连</text>
            </view>
            <view className="ios-text-button" bindtap={onIntegrity}>
              <text className="ios-text-button-label">校验</text>
            </view>
          </view>
        }
      />

      {busy ? <text className="home-hint">{busy}</text> : null}
      {error ? <text className="home-error">{error}</text> : null}
      {report ? (
        <view className="failure-head">
          <text className="home-hint">
            {'检查 ' + report.checked + ' 项，问题 ' + report.issues.length + ' 个'}
          </text>
          {report.issues.length > 0 ? (
            <view bindtap={onFix}>
              <text className="link-text">修复</text>
            </view>
          ) : null}
        </view>
      ) : null}
      {report && report.issues.length > 0
        ? report.issues.slice(0, 5).map((i) => (
            <text className="section-hint" key={i.id}>
              {i.title + (i.missing && i.missing.length ? ' · 缺 ' + i.missing.join('/') : '')}
            </text>
          ))
        : null}
      {message ? <text className="home-hint">{message}</text> : null}

      {current ? (
        <view className="page-head-action" bindtap={() => { setCurrent(null); setTracks([]); }}>
          <text className="page-head-action-text">{'← 返回歌单'}</text>
        </view>
      ) : null}

      <scroll-view className="results" style={{ height: contentH + "px" }} scroll-orientation="vertical">
        {!current
          ? playlists.map((p) => (
              <view className="row" key={p.name} bindtap={() => onOpen(p.name, p.root)}>
                <view className="row-meta">
                  <text className="row-title">{p.name}</text>
                  <text className="row-sub">{p.count + ' 首' + (p.root ? ' · 根目录' : '')}</text>
                </view>
              </view>
            ))
          : null}
        {!current && playlists.length === 0 && !busy ? (
          <text className="home-hint">桶里还没有歌单</text>
        ) : null}

        {current
          ? tracks.map((t) => (
              <view className="row" key={t.key}>
                <view className="row-meta">
                  <text className="row-title">{t.track.title}</text>
                  <text className="row-sub">
                    {t.track.artist + (t.missing && t.missing.length ? ' · 缺 ' + t.missing.join('/') : '')}
                  </text>
                </view>
                <text className="row-dur">{t.track.album ? 'FLAC' : ''}</text>
              </view>
            ))
          : null}
        {current && tracks.length === 0 && !busy ? <text className="home-hint">这个歌单是空的</text> : null}
      </scroll-view>
    </view>
  );
}
