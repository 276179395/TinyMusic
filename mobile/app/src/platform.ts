import { setTransport } from '@tinymusic/shared/transport';
import { createHttpTransport } from '@tinymusic/shared/transport/http';

export interface HostProps {
  platform?: string;
  appTheme?: string;
  apiBase?: string;
  apiToken?: string;
  backendError?: string;
  safeAreaTop?: number;
  safeAreaBottom?: number;
  screenWidth?: number;
  screenHeight?: number;
  autoPlay?: boolean | number;
}

export function hostProps(): HostProps {
  try {
    const raw = ((lynx as unknown as { __globalProps?: Record<string, unknown> }).__globalProps ??
      {}) as Record<string, unknown>;
    // Lynx 会把 globalProps 里的 boolean 变成 1/0，这里统一回 boolean
    const props = raw as HostProps;
    if (props.autoPlay !== undefined) props.autoPlay = Boolean(props.autoPlay);
    return props;
  } catch {
    return {};
  }
}

let inited = false;
/** 初始化失败的原因，界面直接显示，避免"黑屏猜半天" */
export let transportError = '';

/**
 * 把共享库的传输层接到本机后端上。必须在使用 api 之前调用（App 启动时一次）。
 */
export function ensureTransport(): boolean {
  if (inited) return true;
  const props = hostProps();
  if (!props.apiBase) {
    transportError = 'globalProps 里没有 apiBase';
    return false;
  }
  try {
    setTransport(
      createHttpTransport({
        baseUrl: props.apiBase,
        token: props.apiToken ?? '',
      })
    );
    inited = true;
    transportError = '';
    return true;
  } catch (e) {
    transportError = `传输层初始化失败：${String(e)}（typeof fetch=${typeof fetch}）`;
    return false;
  }
}
