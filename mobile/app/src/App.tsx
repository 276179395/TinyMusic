import { useEffect, useState } from '@lynx-js/react';
import { useGlobalProps } from '@lynx-js/react';

import '@tinymusic/theme/lynx.css';
import './styles/base.css';
import { Home } from './routes/Home.js';
import { PlayerPage } from './routes/PlayerPage.js';
import { ensureTransport, normalizeHostProps, transportError, type HostProps } from './platform.js';
import { usePlayer } from './state/player.js';

/**
 * 壳层：主题、安全区、传输层初始化，然后决定渲染首页还是全屏播放页。
 */
export function App() {
  // 官方钩子：globalProps 变化会触发重新渲染（不用手动读 lynx.__globalProps）
  const props: HostProps = normalizeHostProps(
    (useGlobalProps() ?? {}) as Record<string, unknown>
  );
  const [ready, setReady] = useState(false);
  const player = usePlayer();
  const [showPlayer, setShowPlayer] = useState(false);

  useEffect(() => {
    'background only';
    setReady(ensureTransport(props));
  }, [props.apiBase, props.apiToken]);

  // 冒烟钩子：TM_OPEN_PLAYER=1 时，播放开始后自动展开全屏播放页
  useEffect(() => {
    'background only';
    if (props.openPlayer && player.current) setShowPlayer(true);
  }, [props.openPlayer, player.current]);

  const light = props.appTheme === 'light';
  const theme = light ? 'tm-light' : 'tm-dark';
  const iconColor = light ? '#161616' : '#fafafa';
  const inkIconColor = light ? '#fafafa' : '#2a2a2a';

  return (
    <view className={'page ' + theme}>
      <view style={{ height: String(props.safeAreaTop ?? 0) + 'px' }} />
      <view className="app-body">
        {!ready ? (
          <view className="boot">
            <text className="boot-title">TinyMusic</text>
            <text className="boot-hint">
              {transportError || props.backendError || '等待本地后端…'}
            </text>
          </view>
        ) : showPlayer && player.current ? (
          <PlayerPage
            iconColor={iconColor}
            inkIconColor={inkIconColor}
            onCollapse={() => setShowPlayer(false)}
          />
        ) : (
          <Home
            iconColor={iconColor}
            inkIconColor={inkIconColor}
            ready={ready}
            autoPlay={props.autoPlay === true}
            onOpenPlayer={() => setShowPlayer(true)}
          />
        )}
      </view>
      <view style={{ height: String(props.safeAreaBottom ?? 0) + 'px' }} />
    </view>
  );
}
