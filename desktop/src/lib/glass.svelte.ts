/**
 * 界面材质：玻璃 / 边框。
 *
 * 玻璃（半透明 + backdrop-filter）是设计本身的形态，但它有版本门槛：
 * macOS 的 WKWebView 跟着系统走，系统停在 11 / 12 时引擎就停在能装上的最后一版，
 * 用户没法单独升级。这类机器上 `backdrop-filter` 经常不生效，`oklch()` 甚至整批失效
 * （颜色令牌算不出来时整页会变白，靠 app.css 的 sRGB 兜底救回来）。
 *
 * 所以三种情况会退到「边框材质」（实色 + 1px 边框，结构不变）：
 *
 * 1. 引擎能力不足 —— 不认 backdrop-filter 或 oklch()，开关不可用；
 * 2. 系统版本过低 —— macOS 12 及以前（WKWebView 太旧，模糊也很贵）；
 * 3. 用户手动关掉，或系统要求减少透明。
 *
 * 判定结果写到 `<html data-glass="on|flat">`，具体材质在 app.css 第 20 节。
 * 挂载前会先问一次桌面壳的 `system_info`（sw_vers），拿不到就只按能力判断。
 */

import { invoke } from '@tauri-apps/api/core';

export type GlassMode = 'glass' | 'flat';
/** 为什么是当前这个材质：给设置页说明用 */
export type GlassReason = 'ok' | 'engine' | 'system' | 'reduced' | 'user';

type SystemInfo = { os: string; osVersion: string };

const STORAGE_KEY = 'tinymusic.glass';

/** 低于这个 macOS 大版本就走边框材质：WKWebView 跟着系统走，模糊又贵又不稳 */
const MIN_MACOS_MAJOR = 13;

const hasBackdrop = detectBackdrop();
const hasOklch = detectOklch();
const capable = hasBackdrop && hasOklch;

const reducedTransparency = matchMedia('(prefers-reduced-transparency: reduce)');

export const glass = $state<{
  mode: GlassMode;
  reason: GlassReason;
  /** 引擎根本不支持毛玻璃：开关不可用（不是用户选的） */
  forced: boolean;
  /** 系统版本（macOS 形如 12.7.6），拿不到就是空串 */
  osVersion: string;
}>({
  mode: capable ? 'glass' : 'flat',
  reason: capable ? 'ok' : 'engine',
  forced: !capable,
  osVersion: ''
});

let lastSystem: SystemInfo | null = null;

function detectBackdrop(): boolean {
  try {
    return (
      CSS.supports('-webkit-backdrop-filter', 'blur(1px)') ||
      CSS.supports('backdrop-filter', 'blur(1px)')
    );
  } catch {
    // 老引擎没有 CSS.supports：按不支持处理，宁可边框也不要透明
    return false;
  }
}

function detectOklch(): boolean {
  try {
    return CSS.supports('color', 'oklch(50% 0.1 100)');
  } catch {
    return false;
  }
}

function storedMode(): GlassMode | null {
  try {
    const v = localStorage.getItem(STORAGE_KEY);
    return v === 'on' ? 'glass' : v === 'off' ? 'flat' : null;
  } catch {
    return null;
  }
}

function isOldMac(sys: SystemInfo | null): boolean {
  if (sys?.os !== 'macos' || !sys.osVersion) return false;
  const major = Number.parseInt(sys.osVersion.split('.')[0] ?? '', 10);
  return Number.isInteger(major) && major > 0 && major < MIN_MACOS_MAJOR;
}

function decide(sys: SystemInfo | null): Pick<typeof glass, 'mode' | 'reason' | 'forced'> {
  if (!capable) return { mode: 'flat', reason: 'engine', forced: true };
  const pref = storedMode();
  if (pref) return { mode: pref, reason: 'user', forced: false };
  if (reducedTransparency.matches) return { mode: 'flat', reason: 'reduced', forced: false };
  if (isOldMac(sys)) return { mode: 'flat', reason: 'system', forced: false };
  return { mode: 'glass', reason: 'ok', forced: false };
}

function render(sys: SystemInfo | null) {
  const d = decide(sys);
  glass.mode = d.mode;
  glass.reason = d.reason;
  glass.forced = d.forced;
  if (sys?.osVersion) glass.osVersion = sys.osVersion;
  document.documentElement.dataset.glass = d.mode === 'glass' ? 'on' : 'flat';
}

/** 桌面壳的 system_info；浏览器里调试或命令缺失时返回 null（只按能力判断） */
async function readSystem(): Promise<SystemInfo | null> {
  if (!('__TAURI_INTERNALS__' in window)) return null;
  try {
    // 别让一次异常 IPC 卡住首屏：最多等 600ms
    const info = await Promise.race([
      invoke<SystemInfo>('system_info'),
      new Promise<null>((resolve) => setTimeout(() => resolve(null), 600))
    ]);
    return info ?? null;
  } catch {
    return null;
  }
}

/** 用户手动开关；引擎不支持时不做任何事 */
export function setGlassEnabled(on: boolean) {
  if (glass.forced) return;
  glass.mode = on ? 'glass' : 'flat';
  glass.reason = 'user';
  try {
    localStorage.setItem(STORAGE_KEY, on ? 'on' : 'off');
  } catch {
    /* ignore */
  }
  document.documentElement.dataset.glass = on ? 'on' : 'flat';
}

/**
 * 挂载前调用（main.ts 会等它）：先把能力判出来落属性，再问桌面壳要系统版本。
 * 老机器上首帧就应该是边框材质，不能先闪一下毛玻璃。
 */
export async function initGlass(): Promise<void> {
  render(null);
  if (glass.forced) return;

  lastSystem = await readSystem();
  render(lastSystem);

  // 系统在设置里切了「减少透明」时跟着换材质（WebKit 不认这个媒体查询，
  // 所以只能用事件监听当补充；Chromium / WebView2 才有值）
  try {
    reducedTransparency.addEventListener('change', () => render(lastSystem));
  } catch {
    /* 更老的引擎没有 MediaQueryList.addEventListener：这一段跳过就好 */
  }
}
