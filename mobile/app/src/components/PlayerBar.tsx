import { MusicNote01Icon, PauseIcon, PlayIcon, NextIcon, PreviousIcon } from '@hugeicons/core-free-icons';

import { usePlayer, player } from '../state/player.js';


interface PlayerBarProps {
  /** 图标颜色（跟随主题） */
  iconColor: string;
  /** 主按钮（墨色底）上的图标颜色 */
  inkIconColor: string;
}

export function PlayerBar({ iconColor, inkIconColor }: PlayerBarProps) {
  const p = usePlayer();
  const color = iconColor;

  if (!p.current) {
    return (
      <view className="player-bar player-bar--empty">
        <text className="player-empty">在下面搜一首，点一下就能播</text>
      </view>
    );
  }

  const ratio = p.duration > 0 ? Math.min(1, p.position / p.duration) : 0;

  return (
    <view className="player-bar">
      <view className="player-progress">
        <view className="player-progress-fill" style={{ width: `${Math.round(ratio * 100)}%` }} />
      </view>
      <view className="player-row">
        {p.current.cover ? (
          <image className="player-cover" src={p.current.cover} />
        ) : (
          <view className="player-cover player-cover--ph">
            <Icon icon={MusicNote01Icon} size={18} color={color} />
          </view>
        )}
        <view className="player-meta">
          <text className="player-title">{p.current.title}</text>
          <text className="player-sub">
            {p.current.artist} · {fmt(p.position)} / {fmt(p.duration || p.current.duration_sec)}
          </text>
        </view>
        <view className="player-actions">
          <view className="player-btn" bindtap={() => player.prev()}>
            <Icon icon={PreviousIcon} size={20} color={color} />
          </view>
          <view className="player-btn player-btn--main" bindtap={() => player.toggle()}>
            <Icon icon={p.status === 'playing' ? PauseIcon : PlayIcon} size={22} color={inkIconColor} />
          </view>
          <view className="player-btn" bindtap={() => player.next()}>
            <Icon icon={NextIcon} size={20} color={color} />
          </view>
        </view>
      </view>
    </view>
  );
}
