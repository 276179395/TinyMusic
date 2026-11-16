import { useEffect, useState } from '@lynx-js/react';
import { useGlobalProps } from '@lynx-js/react';

import '@tinymusic/theme/lynx.css';
import './styles/base.css';
import { Home } from './routes/Home.js';
import { Downloads } from './routes/Downloads.js';
import { Settings } from './routes/Settings.js';
import { Account } from './routes/Account.js';
import { Cloud } from './routes/Cloud.js';
import { PlaylistPage } from './routes/PlaylistPage.js';
import { ArtistPage } from './routes/ArtistPage.js';
import { AlbumPage } from './routes/AlbumPage.js';
import type { PlaylistRef } from '@tinymusic/shared/types';
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
  // 冒烟/宿主标志以「任一来源为真」为准（reactive 首帧可能给 false）
  props.autoPlay = Boolean(props.autoPlay) || Boolean(direct.autoPlay);
  props.autoDownload = Boolean(props.autoDownload) || Boolean(direct.autoDownload);
  props.playLocal = Boolean(props.playLocal) || Boolean(direct.playLocal);
  props.openPlayer = Boolean(props.openPlayer) || Boolean(direct.openPlayer);
  if (!props.initialTab || props.initialTab === 'home') props.initialTab = direct.initialTab ?? props.initialTab;
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
  const [playlist, setPlaylist] = useState<PlaylistRef | null>(null);
  const [artist, setArtist] = useState<{ id: string; name: string } | null>(null);
  const [album, setAlbum] = useState<{ id: string; name: string } | null>(null);

  useEffect(() => {
    'background only';
    setReady(ensureTransport(props));
  }, [props.apiBase, props.apiToken]);

  // 冒烟钩子：TM_OPEN_ARTIST / TM_OPEN_ALBUM=1 时，播放开始后直接进歌手/专辑页
  useEffect(() => {
    'background only';
    const cur = snapshot.current;
    if (!cur) return;
    if (props.openArtist && cur.artist_id) setArtist({ id: String(cur.artist_id), name: cur.artist });
    else if (props.openAlbum && cur.album_id) setAlbum({ id: String(cur.album_id), name: cur.album });
  }, [props.openArtist, props.openAlbum, snapshot.current?.id]);

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
        ) : artist ? (
          <ArtistPage
            provider="kuwo"
            artistId={artist.id}
            name={artist.name}
            onBack={() => setArtist(null)}
          />
        ) : album ? (
          <AlbumPage
            provider="kuwo"
            albumId={album.id}
            name={album.name}
            onBack={() => setAlbum(null)}
          />
        ) : playlist ? (
          <PlaylistPage playlist={playlist} onBack={() => setPlaylist(null)} />
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
                  onOpenPlaylist={(p) => setPlaylist(p)}
                  initialSearchKind={props.searchKind}
                />
              ) : null}
              {tab === 'downloads' ? <Downloads iconColor={iconColor} playLocal={props.playLocal === true} /> : null}
              {tab === 'cloud' ? <Cloud iconColor={iconColor} /> : null}
              {tab === 'account' ? <Account onOpenPlaylist={(p) => setPlaylist(p)} /> : null}
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
