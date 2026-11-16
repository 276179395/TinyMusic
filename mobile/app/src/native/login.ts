/**
 * 网页登录（Swift 侧 TmLoginModule）：打开 WKWebView，用户登录完点「完成」，
 * 我们轮询拿 cookie，再交给后端 login(method=cookie)。
 *
 * 和后端交互的部分（校验 cookie、存 session）全在 Rust crates/app，这里只做跳转。
 */
import { api } from '@tinymusic/shared/api';

interface TmLoginModule {
  open(provider: string, url: string): void;
  state(cb: (json: string) => void): void;
  close(): void;
}

interface LoginState {
  running?: boolean;
  done?: boolean;
  cancelled?: boolean;
  cookie?: string;
  uid?: string;
  provider?: string;
}

const LOGIN_URLS: Record<string, string> = {
  kuwo: 'https://www.kuwo.cn/',
  netease: 'https://music.163.com/',
};

function module(): TmLoginModule | null {
  try {
    const g = globalThis as unknown as { NativeModules?: Record<string, TmLoginModule> };
    if (g.NativeModules && g.NativeModules.TmLogin) return g.NativeModules.TmLogin;
  } catch {
    /* 忽略 */
  }
  try {
    const l = lynx as unknown as {
      getNativeApp?: () => { nativeModuleProxy?: Record<string, TmLoginModule> };
    };
    const proxy = l.getNativeApp?.()?.nativeModuleProxy;
    if (proxy && proxy.TmLogin) return proxy.TmLogin;
  } catch {
    /* 忽略 */
  }
  return null;
}

export interface LoginResult {
  ok: boolean;
  cancelled?: boolean;
  uid?: string;
  nickname?: string;
  error?: string;
}

/**
 * 打开登录窗口并等它结束；成功后把 cookie 交给后端校验并存 session。
 */
export function loginWithWebView(provider: string): Promise<LoginResult> {
  return new Promise((resolve) => {
    'background only';
    const m = module();
    if (!m) {
      resolve({ ok: false, error: '登录窗口不可用（原生模块没接上）' });
      return;
    }
    m.open(provider, LOGIN_URLS[provider] ?? LOGIN_URLS.kuwo);

    let tries = 0;
    const timer = setInterval(() => {
      tries += 1;
      if (tries > 240) {
        clearInterval(timer);
        m.close();
        resolve({ ok: false, error: '登录超时' });
        return;
      }
      m.state((json: string) => {
        let s: LoginState;
        try {
          s = JSON.parse(json) as LoginState;
        } catch {
          return;
        }
        if (s.cancelled) {
          clearInterval(timer);
          resolve({ ok: false, cancelled: true });
          return;
        }
        if (!s.done) return;
        clearInterval(timer);
        if (!s.cookie) {
          resolve({ ok: false, error: '没取到登录态，请重试' });
          return;
        }
        api
          .login(provider, 'cookie', null, null, s.cookie)
          .then(() => api.sessionGet(provider))
          .then((session) => {
            resolve({
              ok: !!session,
              uid: session?.user_id,
              nickname: session?.nickname,
              error: session ? undefined : '后端没有确认登录态',
            });
          })
          .catch((e: unknown) => resolve({ ok: false, error: String(e) }));
      });
    }, 500);
  });
}
