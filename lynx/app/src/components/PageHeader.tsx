import type { ReactNode } from '@lynx-js/react';

/**
 * 页面大标题（iOS 原生风：34pt bold + 右侧操作）。
 * 用法：<PageHeader title="现在就听" actions={<.../>} />
 */
export function PageHeader({ title, actions }: { title: string; actions?: ReactNode }) {
  return (
    <view className="ios-nav">
      <text className="ios-large-title">{title}</text>
      {actions ? <view className="ios-nav-actions">{actions}</view> : null}
    </view>
  );
}
