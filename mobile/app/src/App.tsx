import { useEffect, useState } from '@lynx-js/react';
import { useGlobalProps } from '@lynx-js/react';

import '@tinymusic/theme/lynx.css';
import './styles/base.css';
import { Home } from './routes/Home.js';
import { Downloads } from './routes/Downloads.js';
import { Settings } from './routes/Settings.js';
import { Account } from './routes/Account.js';
import { Cloud } from './routes/Cloud.js';
import { PlayerPage } from './routes/PlayerPage.js';
import { TabBar, type TabKey } from './components/TabBar.js';
import { PlayerBar } from './components/PlayerBar.js';
import { player } from './state/player.js';
import { ensureTransport, normalizeHostProps, readGlobalPropsDirect, transportError, type HostProps } from './platform.js';
import { usePlayer } from './state/player.js';

/**
 * 壳层：主题、安全区、传输层初始化，然后决定渲染首页还是全屏播放页。
 */
export function App() {
  // 官方钩子：globalProps 变化会触发重新渲染（不用手动读 lynx.__globalProps）
  // 两个来源合并：useGlobalProps 是响应式的，但首帧可能是空对象；
  // lynx.__globalProps 首帧就绪，但不触发重渲染。两边取并集最稳。
  const reactive: HostProps = normalizeHostProps(
    (useGlobalProps() ?? {}) as Record<string, unknown>
  );
  const direct: HostProps = readGlobalPropsDirect();
  const props: HostProps = { ...direct, ...reactive };
  if (!props.apiBase) props.apiBase = direct.apiBase;
  if (props.autoPlay === undefined) props.autoPlay = direct.autoPlay;
  if (props.openPlayer === undefined) props.openPlayer = direct.openPlayer;
  const [ready, setReady] = useState(false);
  const snapshot = usePlayer();
  const [showPlayer, setShowPlayer] = useState(false);
  const initialTab: TabKey =
    props.initialTab === 'downloads'
      ? 'downloads'
      : props.initialTab === 'cloud'
        ? 'cloud'
        : props.initialTab === 'account'
          ? 'account'
        : props.initialTab === 'settings'
          ? 'settings'
          : 'home';
  const [tab, setTab] = useState<TabKey>(initialTab);

  useEffect(() => {
    'background only';
    setReady(ensureTransport(props));
  }, [props.apiBase, props.apiToken]);

  // 冒烟钩子：TM_OPEN_PLAYER=1 时，播放开始后自动展开全屏播放页
  useEffect(() => {
    'background only';
    if (props.openPlayer && snapshot.current) setShowPlayer(true);
  }, [props.openPlayer, snapshot.current]);

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
        ) : showPlayer && snapshot.current ? (
          <PlayerPage
            iconColor={iconColor}
            inkIconColor={inkIconColor}
            onCollapse={() => setShowPlayer(false)}
          />
        ) : (
          <view className="tab-shell">
            <view className="tab-body">
              {tab === 'home' ? (
                <Home
                  iconColor={iconColor}
                  inkIconColor={inkIconColor}
                  ready={ready}
                  autoPlay={props.autoPlay === true}
                  autoDownload={props.autoDownload === true}
                  onOpenPlayer={() => setShowPlayer(true)}
                />
              ) : null}
              {tab === 'downloads' ? <Downloads iconColor={iconColor} /> : null}
              {tab === 'cloud' ? <Cloud iconColor={iconColor} /> : null}
              {tab === 'account' ? <Account /> : null}
              {tab === 'settings' ? <Settings /> : null}
            </view>
            {/* 全局迷你播放条：切换 tab 也在，点了展开全屏 */}
            <view bindtap={() => snapshot.current && setShowPlayer(true)}>
              <PlayerBar iconColor={iconColor} inkIconColor={inkIconColor} />
            </view>
            <TabBar
              current={tab}
              iconColor={iconColor}
              activeColor={light ? '#171717' : '#fafafa'}
              onChange={(t) => setTab(t)}
            />
          </view>
        )}
      </view>
      <view style={{ height: String(props.safeAreaBottom ?? 0) + 'px' }} />
    </view>
  );
}
