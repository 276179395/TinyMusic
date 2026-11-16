import { useCallback, useEffect, useState } from '@lynx-js/react';
import {
  MusicNote01Icon,
  Search01Icon,
  CloudDownloadIcon,
  UserIcon,
} from '@hugeicons/core-free-icons';

import '@tinymusic/theme/lynx.css';
import './styles/base.css';
import { Icon } from './components/Icon.js';

interface HostProps {
  platform?: string;
  appTheme?: string;
  apiBase?: string;
  apiToken?: string;
  backendError?: string;
  safeAreaTop?: number;
  safeAreaBottom?: number;
}

function hostProps(): HostProps {
  try {
    return ((lynx as unknown as { __globalProps?: HostProps }).__globalProps ?? {}) as HostProps;
  } catch {
    return {};
  }
}

/**
 * P4 验证屏：bundle / 后端 / 安全区 / 图标 / 玻璃材质 五件事一起验证。
 */
export function App() {
  const [props, setProps] = useState<HostProps>({});
  const [health, setHealth] = useState('探测中…');

  const probe = useCallback((next: HostProps) => {
    'background only';
    const base = next.apiBase;
    if (!base) {
      setHealth(next.backendError ? `后端未启动：${next.backendError}` : '等宿主注入 apiBase');
      return;
    }
    fetch(`${base}/api/health`, {
      headers: next.apiToken ? { 'X-Tm-Token': next.apiToken } : {},
    })
      .then((r) => r.json())
      .then((j: { ok?: boolean; version?: string; downloadDir?: string }) => {
        setHealth(j.ok ? `后端 OK · v${j.version ?? '?'}` : '后端返回异常');
      })
      .catch((e: unknown) => setHealth(`连接失败：${String(e)}`));
  }, []);

  useEffect(() => {
    'background only';
    const next = hostProps();
    setProps(next);
    probe(next);
  }, [probe]);

  const onTapProbe = useCallback(() => {
    'background only';
    const next = hostProps();
    setProps(next);
    setHealth('探测中…');
    probe(next);
  }, [probe]);

  const light = props.appTheme === 'light';
  const theme = light ? 'tm-light' : 'tm-dark';
  const iconColor = light ? '#161616' : '#fafafa';
  const topInset = typeof props.safeAreaTop === 'number' ? props.safeAreaTop : 0;
  const bottomInset = typeof props.safeAreaBottom === 'number' ? props.safeAreaBottom : 0;

  return (
    <view className={`page ${theme}`}>
      <view style={{ height: `${topInset}px` }} />
      <view className="content">
        <view className="header">
          <text className="title">TinyMusic</text>
          <text className="subtitle">mobile · Lynx</text>
        </view>

        <view className="icons">
          <Icon icon={MusicNote01Icon} color={iconColor} size={26} />
          <Icon icon={Search01Icon} color={iconColor} size={26} />
          <Icon icon={CloudDownloadIcon} color={iconColor} size={26} />
          <Icon icon={UserIcon} color={iconColor} size={26} />
        </view>

        <view className="card" bindtap={onTapProbe}>
          <text className="card-title">本地后端</text>
          <text className="card-value">{health}</text>
          <text className="card-hint">{props.apiBase ?? '未注入 apiBase'} · 点一下重新探测</text>
        </view>

        <view className="glass-wrap">
          <image
            className="glass-bg"
            src="https://img1.kuwo.cn/star/albumcover/500/s4s0/93/1794217775.jpg"
          />
          <blur-view
            className="glass-panel"
            blur-effect={light ? 'light' : 'dark'}
            blur-radius={18}
          >
            <text className="glass-text">blur-view 玻璃层</text>
          </blur-view>
        </view>

        <view className="footer">
          <text className="footer-text">阶段 P4：后端 / 安全区 / 图标 / 玻璃</text>
        </view>
      </view>
      <view style={{ height: `${bottomInset}px` }} />
    </view>
  );
}
