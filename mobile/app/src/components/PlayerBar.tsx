import { MusicNote01Icon, PauseIcon, PlayIcon, NextIcon, PreviousIcon } from '@hugeicons/core-free-icons';

import { Icon } from './Icon.js';
import { player } from '../state/player.js';
import { useNativeNowPlaying } from '../state/nativePlayer.js';

interface PlayerBarProps {
  iconColor: string;
  inkIconColor: string;
}

function clip(s: string, n: number): string {
  if (!s) return '';
  return s.length > n ? s.slice(0, n) + '…' : s;
}

function fmt(sec: number): string {
  if (!Number.isFinite(sec) || sec <= 0) return '0:00';
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return m + ':' + String(s).padStart(2, '0');
}

/**
 * 迷你播放器（Apple Music 那种贴在 Tab bar 上方的条）。
 * 状态直接读原生播放器，避免 Lynx 双线程下 store 副本不一致。
 */
export function PlayerBar({ iconColor }: PlayerBarProps) {
  const now = useNativeNowPlaying();

  if (!now.title) {
    return (
      <view className="ios-mini-player">
        <view className="ios-mini-art ios-row-art--round" />
        <view className="ios-mini-text">
          <text className="ios-mini-title">未在播放</text>
          <text className="ios-mini-sub">从「现在就听」里挑一首</text>
        </view>
      </view>
    );
  }

  const ratio = now.duration > 0 ? Math.min(1, now.position / now.duration) : 0;

  return (
    <view className="ios-mini-player">
      {now.cover ? (
        <image className="ios-mini-art" src={now.cover} />
      ) : (
        <view className="ios-mini-art ios-row-art-ph">
          <Icon icon={MusicNote01Icon} size={18} color={iconColor} />
        </view>
      )}

      <view className="ios-mini-text">
        <text className="ios-mini-title">{clip(now.title, 26)}</text>
        <text className="ios-mini-sub">
          {clip(now.artist, 16) + ' · ' + fmt(now.position) + ' / ' + fmt(now.duration)}
        </text>
      </view>

      <view className="ios-mini-controls">
        <view className="ios-mini-btn" bindtap={() => player.prev()}>
          <Icon icon={PreviousIcon} size={22} color={iconColor} />
        </view>
        <view className="ios-mini-btn" bindtap={() => player.toggle()}>
          <Icon icon={now.status === 'playing' ? PauseIcon : PlayIcon} size={24} color={iconColor} />
        </view>
        <view className="ios-mini-btn" bindtap={() => player.next()}>
          <Icon icon={NextIcon} size={22} color={iconColor} />
        </view>
      </view>

      <view className="ios-mini-progress">
        <view className="ios-mini-progress-fill" style={{ width: Math.round(ratio * 100) + '%' }} />
      </view>
    </view>
  );
}
