import { useCallback, useEffect, useState } from '@lynx-js/react';
import {
  ChevronDownIcon,
  MusicNote01Icon,
  PauseIcon,
  PlayIcon,
  NextIcon,
  PreviousIcon,
  ShuffleIcon,
  RepeatIcon,
  RepeatOne01Icon,
  FavouriteIcon,
  ArrowDown01Icon,
} from '@hugeicons/core-free-icons';
import type { Quality } from '@tinymusic/shared/types';
import { qualityChoices } from '@tinymusic/shared/quality';
import { api } from '@tinymusic/shared/api';

import { Icon } from '../components/Icon.js';
import { player, usePlayer } from '../state/player.js';

interface PlayerPageProps {
  iconColor: string;
  inkIconColor: string;
  onCollapse: () => void;
  onOpenArtist?: (id: string, name: string) => void;
  onOpenAlbum?: (id: string, name: string) => void;
}

function fmt(sec: number): string {
  if (!Number.isFinite(sec) || sec <= 0) return '0:00';
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return m + ':' + String(s).padStart(2, '0');
}

const LINE_HEIGHT = 34;

/**
 * 全屏播放页，按 Apple Music 的排布：封面 → 标题/歌手 → 进度 → 传输控制 → 歌词 → 次要操作。
 */
export function PlayerPage({ iconColor, inkIconColor, onCollapse, onOpenArtist, onOpenAlbum }: PlayerPageProps) {
  const p = usePlayer();
  const [caps, setCaps] = useState<{ value: Quality; label: string; available: boolean }[]>([]);
  const [scrollTop, setScrollTop] = useState(0);
  const [fav, setFav] = useState(false);

  useEffect(() => {
    'background only';
    api
      .qualityCapabilities()
      .then((list) => setCaps(list.map((c) => ({ value: c.value, label: c.label, available: c.available }))))
      .catch(() => setCaps([]));
  }, []);

  useEffect(() => {
    'background only';
    const t = p.current;
    if (!t) return;
    api.favoriteCheck(t.provider, t.id).then((v) => setFav(!!v)).catch(() => setFav(false));
  }, [p.current?.id]);

  useEffect(() => {
    'background only';
    if (!p.lyrics.length || p.duration <= 0) return;
    const ms = p.position * 1000;
    let idx = -1;
    for (let i = 0; i < p.lyrics.length; i++) {
      if (p.lyrics[i].time_ms <= ms + 60) idx = i;
      else break;
    }
    if (idx >= 0) setScrollTop(Math.max(0, idx * LINE_HEIGHT - 2 * LINE_HEIGHT));
  }, [p.position, p.lyrics, p.duration]);

  const ratio = p.duration > 0 ? Math.min(1, p.position / p.duration) : 0;
  const choices = qualityChoices(
    p.current,
    caps as never,
    p.availableQualities.length
      ? { available: p.availableQualities, has_advanced: !!p.current?.has_advanced, known: true }
      : null,
    p.quality
  );

  const onFav = useCallback(() => {
    'background only';
    const t = p.current;
    if (!t) return;
    const next = !fav;
    setFav(next);
    const call = next ? api.favoriteAdd(t) : api.favoriteRemove(t.provider, t.id);
    call.catch(() => setFav(!next));
  }, [fav, p.current]);

  return (
    <view className="ios-player">
      <view className="ios-player-grabber" bindtap={onCollapse} />

      {p.current?.cover ? (
        <image className="ios-player-art" src={p.current.cover} />
      ) : (
        <view className="ios-player-art ios-row-art-ph">
          <Icon icon={MusicNote01Icon} size={56} color={iconColor} />
        </view>
      )}

      <text className="ios-player-title">{p.current?.title ?? '未在播放'}</text>
      <text className="ios-player-artist" bindtap={() => p.current?.artist_id && onOpenArtist?.(String(p.current.artist_id), p.current.artist)}>
        {p.current?.artist ?? ''}
      </text>

      <view className="ios-progress">
        <view className="ios-progress-track">
          <view className="ios-progress-fill" style={{ width: Math.round(ratio * 100) + '%' }} />
        </view>
        <view className="ios-progress-times">
          <text className="ios-time">{fmt(p.position)}</text>
          <text className="ios-time">{'-' + fmt(Math.max(0, (p.duration || 0) - p.position))}</text>
        </view>
      </view>

      <view className="ios-transport">
        <view className="ios-transport-btn" bindtap={() => player.prev()}>
          <Icon icon={PreviousIcon} size={32} color={iconColor} />
        </view>
        <view className="ios-transport-main" bindtap={() => player.toggle()}>
          <Icon icon={p.status === 'playing' ? PauseIcon : PlayIcon} size={44} color={iconColor} />
        </view>
        <view className="ios-transport-btn" bindtap={() => player.next()}>
          <Icon icon={NextIcon} size={32} color={iconColor} />
        </view>
      </view>

      {p.lyrics.length > 0 ? (
        <scroll-view className="ios-lyrics" style={{ height: "150px" }} scroll-orientation="vertical" scroll-top={scrollTop}>
          {p.lyrics.map((l, i) => {
            const ms = p.position * 1000;
            const active = l.time_ms <= ms + 60 && (i === p.lyrics.length - 1 || p.lyrics[i + 1].time_ms > ms + 60);
            return (
              <view
                className={'ios-lyric-line' + (active ? ' ios-lyric-line--on' : '')}
                key={String(l.time_ms) + '-' + i}
                bindtap={() => player.seekTo(l.time_ms / 1000)}
              >
                <text className="ios-lyric-text">{l.text || ' '}</text>
              </view>
            );
          })}
        </scroll-view>
      ) : (
        <view className="ios-empty">
          <text className="ios-empty-sub">{p.lyricsLoading ? '歌词加载中…' : '暂无歌词'}</text>
        </view>
      )}

      <view className="ios-action-row">
        <view className="ios-action-item" bindtap={onFav}>
          <Icon icon={FavouriteIcon} size={22} color={fav ? '#ff375f' : iconColor} />
          <text className="ios-action-label">{fav ? '已收藏' : '收藏'}</text>
        </view>
        <view className="ios-action-item" bindtap={() => player.toggleShuffle()}>
          <Icon icon={ShuffleIcon} size={22} color={p.shuffle ? '#ff375f' : iconColor} />
          <text className="ios-action-label">随机</text>
        </view>
        <view className="ios-action-item" bindtap={() => player.cycleRepeat()}>
          <Icon icon={p.repeat === 'one' ? RepeatOne01Icon : RepeatIcon} size={22} color={p.repeat === 'off' ? iconColor : '#ff375f'} />
          <text className="ios-action-label">循环</text>
        </view>
        {p.current?.album_id ? (
          <view className="ios-action-item" bindtap={() => onOpenAlbum?.(String(p.current?.album_id), p.current?.album ?? '')}>
            <Icon icon={ArrowDown01Icon} size={22} color={iconColor} />
            <text className="ios-action-label">专辑</text>
          </view>
        ) : null}
      </view>
    </view>
  );
}