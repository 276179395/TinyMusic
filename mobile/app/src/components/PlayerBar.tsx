import { MusicNote01Icon, PauseIcon, PlayIcon, NextIcon, PreviousIcon } from '@hugeicons/core-free-icons';

import { Icon } from './Icon.js';
import { player } from '../state/player.js';
import { useNativeNowPlaying } from '../state/nativePlayer.js';

interface PlayerBarProps {
  /** 图标颜色（跟随主题） */
  iconColor: string;
  /** 主按钮（墨色底）上的图标颜色 */
  inkIconColor: string;
}

function fmt(sec: number): string {
  if (!Number.isFinite(sec) || sec <= 0) return '0:00';
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return m + ':' + String(s).padStart(2, '0');
}

/**
 * 迷你播放条：状态直接来自原生播放器（见 useNativeNowPlaying 的说明），
 * 操作复用 player store（队列/切歌规则仍在 packages/shared）。
 */
export function PlayerBar({ iconColor, inkIconColor }: PlayerBarProps) {
  const now = useNativeNowPlaying();
  const color = iconColor;

  if (!now.title) {
    return (
      <view className="player-bar player-bar--empty">
        <text className="player-empty">在下面搜一首，点一下就能播</text>
      </view>
    );
  }

  const ratio = now.duration > 0 ? Math.min(1, now.position / now.duration) : 0;

  return (
    <view className="player-bar">
      <view className="player-progress">
        <view className="player-progress-fill" style={{ width: `${Math.round(ratio * 100)}%` }} />
      </view>
      <view className="player-row">
        {now.cover ? (
          <image className="player-cover" src={now.cover} />
        ) : (
          <view className="player-cover player-cover--ph">
            <Icon icon={MusicNote01Icon} size={18} color={color} />
          </view>
        )}
        <view className="player-meta">
          <text className="player-title">{now.title}</text>
          <text className="player-sub">
            {now.artist} · {fmt(now.position)} / {fmt(now.duration)}
          </text>
        </view>
        <view className="player-actions">
          <view className="player-btn" bindtap={() => player.prev()}>
            <Icon icon={PreviousIcon} size={20} color={color} />
          </view>
          <view className="player-btn player-btn--main" bindtap={() => player.toggle()}>
            <Icon icon={now.status === 'playing' ? PauseIcon : PlayIcon} size={22} color={inkIconColor} />
          </view>
          <view className="player-btn" bindtap={() => player.next()}>
            <Icon icon={NextIcon} size={20} color={color} />
          </view>
        </view>
      </view>
    </view>
  );
}
