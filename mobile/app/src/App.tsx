import { useEffect, useState } from '@lynx-js/react';

import '@tinymusic/theme/lynx.css';
import './styles/base.css';
import { Home } from './routes/Home.js';
import { ensureTransport, hostProps, transportError, type HostProps } from './platform.js';

/**
 * 壳层：主题、安全区、传输层初始化，然后交给 Home。
 * 页面栈与各路由在 P5/P6 逐步接进来。
 */
export function App() {
  const [props, setProps] = useState<HostProps>({});
  const [ready, setReady] = useState(false);

  useEffect(() => {
    'background only';
    const next = hostProps();
    setProps(next);
    setReady(ensureTransport());
  }, []);

  const light = props.appTheme === 'light';
  const theme = light ? 'tm-light' : 'tm-dark';
  const iconColor = light ? '#161616' : '#fafafa';
  const inkIconColor = light ? '#fafafa' : '#2a2a2a';
  const topInset = typeof props.safeAreaTop === 'number' ? props.safeAreaTop : 0;
  const bottomInset = typeof props.safeAreaBottom === 'number' ? props.safeAreaBottom : 0;

  return (
    <view className={`page ${theme}`}>
      <view style={{ height: `${topInset}px` }} />
      <view className="app-body">
        {ready ? (
          <Home iconColor={iconColor} inkIconColor={inkIconColor} ready={ready} autoPlay={Boolean(props.autoPlay)} />
        ) : (
          <view className="boot">
            <text className="boot-title">TinyMusic</text>
            <text className="boot-hint">
              {transportError || props.backendError || `等待本地后端…（apiBase=${props.apiBase ?? '无'}）`}
            </text>
          </view>
        )}
      </view>
      <view style={{ height: `${bottomInset}px` }} />
    </view>
  );
}
