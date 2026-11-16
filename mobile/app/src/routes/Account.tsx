import { useCallback, useEffect, useState } from '@lynx-js/react';
import { api } from '@tinymusic/shared/api';
import type { Session } from '@tinymusic/shared/types';

import { loginWithWebView } from '../native/login.js';

const PROVIDERS = [
  { id: 'kuwo', name: '酷我音乐' },
  { id: 'netease', name: '网易云音乐' },
];

/**
 * 账号页：网页登录 / 会话展示 / 退出。
 * 登录态校验和存储都在后端（crates/app），这里只负责唤起登录窗口。
 */
export function Account() {
  const [sessions, setSessions] = useState<Record<string, Session | null>>({});
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');

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
  }, [refresh]);

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
      <view className="page-head">
        <text className="page-title">账号</text>
      </view>

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
    </view>
  );
}
