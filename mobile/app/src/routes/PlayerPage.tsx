import { useCallback, useEffect, useState } from '@lynx-js/react';
import {
  ArrowDown01Icon,
  MusicNote01Icon,
  PauseIcon,
  PlayIcon,
  NextIcon,
  PreviousIcon,
  ShuffleIcon,
  RepeatIcon,
  RepeatOne01Icon,
  FavouriteIcon,
} from '@hugeicons/core-free-icons';
import type { Quality } from '@tinymusic/shared/types';
import { qualityChoices } from '@tinymusic/shared/quality';

import { Icon } from '../components/Icon.js';
import { player, usePlayer } from '../state/player.js';
import { api } from '@tinymusic/shared/api';

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
 * 全屏播放页：封面 + 控制 + 音质 + 歌词。
 * 队列/随机/循环/音质门控全部来自 packages/shared，这里只做展示与手势。
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

  // 切歌时查收藏状态
  useEffect(() => {
    'background only';
    const t = p.current;
    if (!t) return;
    api
      .favoriteCheck(t.provider, t.id)
      .then((v) => setFav(!!v))
      .catch(() => setFav(false));
  }, [p.current?.id]);

  // 当前行变化时把歌词滚到中间
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

  const choices = qualityChoices(
    p.current,
    caps as never,
    p.availableQualities.length
      ? { available: p.availableQualities, has_advanced: !!p.current?.has_advanced, known: true }
      : null,
    p.quality
  );

  const onSeekTap = useCallback(
    (e: { detail?: { x?: number } }) => {
      'background only';
      if (!p.duration || !e.detail?.x) return;
      // 进度条点击：按点击位置估算比例（Lynx 事件里的 x 是相对坐标）
      const ratio = Math.max(0, Math.min(1, e.detail.x / 320));
      player.seekTo(ratio * p.duration);
    },
    [p.duration]
  );

  const ratio = p.duration > 0 ? Math.min(1, p.position / p.duration) : 0;

  return (
    <view className="player-page">
      <view className="player-top">
        <view className="player-collapse" bindtap={onCollapse}>
          <Icon icon={ArrowDown01Icon} size={22} color={iconColor} />
        </view>
        <text className="player-top-label">正在播放</text>
        <view className="player-collapse" />
      </view>

      <view className="player-art">
        {p.current?.cover ? (
          <image className="player-art-img" src={p.current.cover} />
        ) : (
          <view className="player-art-img player-art-ph">
            <Icon icon={MusicNote01Icon} size={48} color={iconColor} />
          </view>
        )}
      </view>

      <view className="player-info">
        <text className="player-info-title">{p.current?.title ?? '未在播放'}</text>
        <text className="player-info-sub">
          {(p.current?.artist ?? '') + (p.current?.album ? ' · ' + p.current.album : '')}
        </text>
      </view>

      <view className="player-seek" bindtap={onSeekTap}>
        <view className="player-seek-track">
          <view className="player-seek-fill" style={{ width: Math.round(ratio * 100) + '%' }} />
        </view>
        <view className="player-seek-times">
          <text className="player-time">{fmt(p.position)}</text>
          <text className="player-time">{fmt(p.duration || p.current?.duration_sec || 0)}</text>
        </view>
      </view>

      <view className="player-controls">
        <view className="player-icon-btn" bindtap={() => player.toggleShuffle()}>
          <Icon icon={ShuffleIcon} size={20} color={p.shuffle ? '#54d2a4' : iconColor} />
        </view>
        <view className="player-icon-btn" bindtap={() => player.prev()}>
          <Icon icon={PreviousIcon} size={26} color={iconColor} />
        </view>
        <view className="player-play-big" bindtap={() => player.toggle()}>
          <Icon
            icon={p.status === 'playing' ? PauseIcon : PlayIcon}
            size={30}
            color={inkIconColor}
          />
        </view>
        <view className="player-icon-btn" bindtap={() => player.next()}>
          <Icon icon={NextIcon} size={26} color={iconColor} />
        </view>
        <view className="player-icon-btn" bindtap={() => player.cycleRepeat()}>
          <Icon
            icon={p.repeat === 'one' ? RepeatOne01Icon : RepeatIcon}
            size={20}
            color={p.repeat === 'off' ? iconColor : '#54d2a4'}
          />
        </view>
      </view>

      <view className="player-links">
        {p.current?.artist_id ? (
          <view
            className="player-link"
            bindtap={() => onOpenArtist?.(String(p.current?.artist_id), p.current?.artist ?? '')}
          >
            <text className="player-link-text">歌手</text>
          </view>
        ) : null}
        {p.current?.album_id ? (
          <view
            className="player-link"
            bindtap={() => onOpenAlbum?.(String(p.current?.album_id), p.current?.album ?? '')}
          >
            <text className="player-link-text">专辑</text>
          </view>
        ) : null}
      </view>

      <view className="player-fav-row">
        <view
          className="player-fav"
          bindtap={() => {
            'background only';
            const t = p.current;
            if (!t) return;
            const next = !fav;
            setFav(next);
            const call = next ? api.favoriteAdd(t) : api.favoriteRemove(t.provider, t.id);
            call.catch(() => setFav(!next));
          }}
        >
          <Icon icon={FavouriteIcon} size={18} color={fav ? '#ff6468' : iconColor} />
          <text className="player-fav-text">{fav ? '已收藏' : '收藏'}</text>
        </view>
      </view>

      <view className="player-quality">
        {choices.map((c) => (
          <view
            key={c.value}
            className={'quality-chip' + (c.current ? ' quality-chip--on' : '') + (c.disabled ? ' quality-chip--off' : '')}
            bindtap={() => {
              'background only';
              if (c.disabled) return;
              void player.setQuality(c.value);
            }}
          >
            <text className="quality-chip-text">{c.label}</text>
          </view>
        ))}
      </view>

      <view className="player-lyrics-wrap">
        {p.lyricsLoading ? <text className="lyrics-hint">歌词加载中…</text> : null}
        {p.lyricsError ? <text className="lyrics-hint">{p.lyricsError}</text> : null}
        {!p.lyricsLoading && !p.lyricsError && p.lyrics.length === 0 ? (
          <text className="lyrics-hint">没有歌词</text>
        ) : null}
        <scroll-view className="lyrics-scroll" scroll-orientation="vertical" scroll-top={scrollTop}>
          {p.lyrics.map((l, i) => {
            const ms = p.position * 1000;
            const active = l.time_ms <= ms + 60 && (i === p.lyrics.length - 1 || p.lyrics[i + 1].time_ms > ms + 60);
            return (
              <view
                className={'lyric-line' + (active ? ' lyric-line--on' : '')}
                key={l.time_ms + '-' + i}
                bindtap={() => {
                  'background only';
                  player.seekTo(l.time_ms / 1000);
                }}
              >
                <text className="lyric-text">{l.text || ' '}</text>
              </view>
            );
          })}
        </scroll-view>
      </view>
    </view>
  );
}
