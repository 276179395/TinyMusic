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
  openPlayer?: boolean | number;
  initialTab?: string;
}

/**
 * 归一化宿主全局属性：
 * Lynx 会把 boolean 变成 1/0，这里统一回 boolean，界面层只处理干净的类型。
 */
export function normalizeHostProps(raw: Record<string, unknown> | null | undefined): HostProps {
  const src = raw ?? {};
  const props = { ...src } as HostProps;
  props.autoPlay = Boolean(src.autoPlay);
  props.openPlayer = Boolean(src.openPlayer);
  props.safeAreaTop = Number(src.safeAreaTop ?? 0) || 0;
  props.safeAreaBottom = Number(src.safeAreaBottom ?? 0) || 0;
  return props;
}

let inited = false;
/** 初始化失败的原因，界面直接显示，避免"黑屏猜半天" */
export let transportError = '';

/**
 * 把共享库的传输层接到本机后端上。必须在使用 api 之前调用（App 启动时一次）。
 */
export function ensureTransport(props: HostProps): boolean {
  if (inited) return true;
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
    transportError = '传输层初始化失败：' + String(e);
    return false;
  }
}
