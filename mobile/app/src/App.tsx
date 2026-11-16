import { useCallback, useEffect, useState } from '@lynx-js/react';

import '@tinymusic/theme/lynx.css';
import './styles/base.css';

/**
 * 第一屏：先证明 bundle 能在宿主里跑起来，并把「后端是否连上」显示出来。
 * 真正的页面在 routes/ 里，随阶段推进逐个接进来。
 */
export function App() {
  const [theme, setTheme] = useState<'dark' | 'light'>('dark');
  const [health, setHealth] = useState('未连接');

  useEffect(() => {
    'background only';
    try {
      const props = (lynx as { __globalProps?: { appTheme?: string } }).__globalProps;
      if (props?.appTheme === 'light') setTheme('light');
    } catch {
      // 宿主没给就按深色
    }
  }, []);

  const onTapProbe = useCallback(() => {
    'background only';
    setHealth('正在探测…');
    // P4 会换成 native TmBackend 注入的 baseUrl；先用 initData 里可能存在的地址
    const data = (lynx as { __globalProps?: { apiBase?: string } }).__globalProps;
    const base = data?.apiBase;
    if (!base) {
      setHealth('等宿主注入 apiBase');
      return;
    }
    fetch(`${base}/api/health`)
      .then((r) => r.json())
      .then((j) => setHealth(`后端 OK · ${j.version ?? '?'}`))
      .catch((e: unknown) => setHealth(`连接失败：${String(e)}`));
  }, []);

  return (
    <view className={`page ${theme === 'light' ? 'tm-light' : 'tm-dark'}`}>
      <view className="header">
        <text className="title">TinyMusic</text>
        <text className="subtitle">mobile · Lynx</text>
      </view>

      <view className="card" bindtap={onTapProbe}>
        <text className="card-title">本地后端</text>
        <text className="card-value">{health}</text>
        <text className="card-hint">点一下重新探测</text>
      </view>

      <view className="footer">
        <text className="footer-text">阶段 P4：骨架 + 后端连通</text>
      </view>
    </view>
  );
}
