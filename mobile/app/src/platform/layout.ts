import { useGlobalProps } from '@lynx-js/react';

interface HostSize {
  screenHeight?: number;
}

/**
 * 内容区可用高度（px）。
 *
 * Lynx 的 overflow:hidden 只是部分支持：scroll-view 不给确定高度时，
 * 长页面会把下面的 mini player / tab bar 顶出屏幕。这里统一算好高度，
 * 各页 scroll-view 用内联 style 固定住。
 */
export function useContentHeight(barsH = 112, extra = 0): number {
  const raw = (useGlobalProps() ?? {}) as HostSize;
  const h = Number(raw.screenHeight ?? 0) || 0;
  if (!h) return 0;
  return Math.max(240, h - barsH - extra);
}
