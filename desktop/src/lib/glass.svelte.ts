/**
 * 玻璃材质开关。
 *
 * macOS 的 WKWebView 跟着系统走：系统停在 11 / 12，引擎就停在能装上的最后一版，
 * 用户没法单独升级。这类机器上两件事都可能不成立：
 *
 * - `backdrop-filter` 不生效：模糊没了，半透明卡片就只剩白底上一层更白；
 * - `oklch()` 不生效：整批颜色令牌在计算值阶段失效，页面直接变白（app.css 第 20.1 节兜底）。
 *
 * 所以启动时探一次能力：不支持毛玻璃就把 <html> 标成 data-glass="off"，
 * app.css 第 20 节会把玻璃整站换成实色。用户也可以在「设置 → 外观」里手动关掉，
 * 低端机、外接屏、远程桌面都能少算一层合成。选择存在 localStorage。
 */

const STORAGE_KEY = 'tinymusic.glass';

/** 引擎认不认 backdrop-filter（-webkit- 前缀也算） */
const supported = detectBackdrop();

/**
 * 引擎认不认 oklch()（Safari 15.4 之前不认）。
 * 不认时颜色由 CSS 的 sRGB 兜底接管，这里只负责把状态说给用户看。
 */
export const oklchSupported = detectOklch();

export const glass = $state<{ solid: boolean; forced: boolean }>({
  solid: !supported || storedSolid(),
  /** 引擎不支持毛玻璃，开关不可用（不是用户选的） */
  forced: !supported
});

function detectBackdrop(): boolean {
  try {
    return (
      CSS.supports('-webkit-backdrop-filter', 'blur(1px)') ||
      CSS.supports('backdrop-filter', 'blur(1px)')
    );
  } catch {
    // 老引擎没有 CSS.supports：按不支持处理，宁可实色也不要透明
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

function storedSolid(): boolean {
  try {
    return localStorage.getItem(STORAGE_KEY) === 'solid';
  } catch {
    return false;
  }
}

function apply() {
  document.documentElement.dataset.glass = glass.solid ? 'off' : 'on';
}

/** 手动开关；引擎不支持时不做任何事 */
export function setGlassSolid(solid: boolean) {
  if (glass.forced) return;
  glass.solid = solid;
  try {
    localStorage.setItem(STORAGE_KEY, solid ? 'solid' : 'glass');
  } catch {
    /* ignore */
  }
  apply();
}

/** 在挂载前调用：先把 data-glass 落下去，避免首帧闪一下毛玻璃 */
export function initGlass() {
  apply();
}
