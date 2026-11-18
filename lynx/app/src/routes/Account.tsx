import { useCallback, useEffect, useState } from '@lynx-js/react';
import { PageHeader } from '../components/PageHeader.js';
import { api } from '@tinymusic/shared/api';
import type { PlaylistRef, Session, Track } from '@tinymusic/shared/types';

import { loginWithWebView } from '../native/login.js';
import { player } from '../state/player.js';

const PROVIDERS = [
  { id: 'kuwo', name: '酷我音乐' },
  { id: 'netease', name: '网易云音乐' },
];

/**
 * 账号页：网页登录 / 会话展示 / 退出。
 * 登录态校验和存储都在后端（crates/app），这里只负责唤起登录窗口。
 */
export function Account({ onOpenPlaylist }: { onOpenPlaylist: (p: PlaylistRef) => void }) {
  const [sessions, setSessions] = useState<Record<string, Session | null>>({});
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  const [favorites, setFavorites] = useState<Track[]>([]);
  const [playlists, setPlaylists] = useState<PlaylistRef[]>([]);

  const refresh = useCallback(() => {
    'background only';
    Promise.all(PROVIDERS.map((p) => api.sessionGet(p.id).catch(() => null)))
      .then((list) => {
        const next: Record<string, Session | null> = {};
        PROVIDERS.forEach((p, i) => (next[p.id] = list[i] ?? null));
        setSessions(next);
      })
      .catch((e: unknown) => setError(String(e)));
  }, []);

  useEffect(() => {
    'background only';
    refresh();
    api.favoriteList().then((list) => setFavorites(list ?? [])).catch(() => undefined);
    api.myPlaylists('kuwo').then((list) => setPlaylists(list ?? [])).catch(() => undefined);
  }, [refresh]);

  const playFavorites = useCallback(() => {
    'background only';
    if (favorites.length) void player.playTrack(favorites[0], favorites);
  }, [favorites]);

  const onLogin = useCallback(
    (provider: string) => {
      'background only';
      setBusy(provider);
      setError('');
      void loginWithWebView(provider).then((r) => {
        setBusy('');
        if (!r.ok) {
          if (!r.cancelled) setError(r.error ?? '登录失败');
          return;
        }
        refresh();
      });
    },
    [refresh]
  );

  const onLogout = useCallback(
    (provider: string) => {
      'background only';
      api
        .logout(provider)
        .then(() => refresh())
        .catch((e: unknown) => setError(String(e)));
    },
    [refresh]
  );

  return (
    <view className="page-content">
      <PageHeader title="账号" />

      {PROVIDERS.map((p) => {
        const s = sessions[p.id];
        return (
          <view className="section" key={p.id}>
            <text className="section-title">{p.name}</text>
            {s ? (
              <view className="account-row">
                {s.avatar ? (
                  <image className="account-avatar" src={s.avatar} />
                ) : (
                  <view className="account-avatar" />
                )}
                <view className="account-meta">
                  <text className="section-value">{s.nickname || s.user_id}</text>
                  <text className="section-hint">uid {s.user_id}</text>
                </view>
                <view className="page-head-action" bindtap={() => onLogout(p.id)}>
                  <text className="page-head-action-text">退出</text>
                </view>
              </view>
            ) : (
              <view
                className={'login-btn' + (busy === p.id ? ' login-btn--busy' : '')}
                bindtap={() => onLogin(p.id)}
              >
                <text className="login-btn-text">
                  {busy === p.id ? '请在网页里登录…' : '登录' + p.name}
                </text>
              </view>
            )}
          </view>
        );
      })}

      {error ? <text className="home-error">{error}</text> : null}
      <text className="section-hint">登录只为了拿歌单与每日推荐；不保存密码，登录态只留在本机</text>

      <view className="section">
        <view className="failure-head">
          <text className="section-title">{'收藏（' + favorites.length + '）'}</text>
          {favorites.length ? (
            <view bindtap={playFavorites}>
              <text className="link-text">播放全部</text>
            </view>
          ) : null}
        </view>
        {favorites.length === 0 ? (
          <text className="section-hint">还没有收藏；播放页点♡可以收藏当前歌曲</text>
        ) : null}
        {favorites.slice(0, 20).map((t) => (
          <view className="ios-row" key={t.provider + ':' + t.id} bindtap={() => void player.playTrack(t, favorites)}>
            <view className="ios-row-text">
              <text className="ios-row-title">{t.title}</text>
              <text className="ios-row-sub">{t.artist}</text>
            </view>
          </view>
        ))}
      </view>

      {playlists.length ? (
        <view className="section">
          <text className="section-title">{'我的歌单（' + playlists.length + '）'}</text>
          {playlists.map((p) => (
            <view className="ios-row" key={p.id} bindtap={() => onOpenPlaylist(p)}>
              <view className="row-meta">
                <text className="ios-row-title">{p.name}</text>
                <text className="ios-row-sub">{p.track_count + ' 首'}</text>
              </view>
            </view>
          ))}
        </view>
      ) : null}
    </view>
  );
}
