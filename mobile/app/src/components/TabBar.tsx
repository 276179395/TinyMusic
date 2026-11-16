import { Home01Icon, Download04Icon, Settings01Icon, UserIcon, CloudIcon } from '@hugeicons/core-free-icons';

import { Icon } from './Icon.js';

export type TabKey = 'home' | 'downloads' | 'cloud' | 'account' | 'settings';

interface TabBarProps {
  current: TabKey;
  iconColor: string;
  activeColor: string;
  onChange: (tab: TabKey) => void;
}

const TABS: { key: TabKey; label: string; icon: typeof Home01Icon }[] = [
  { key: 'home', label: '首页', icon: Home01Icon },
  { key: 'downloads', label: '下载', icon: Download04Icon },
  { key: 'cloud', label: '网盘', icon: CloudIcon },
  { key: 'account', label: '账号', icon: UserIcon },
  { key: 'settings', label: '设置', icon: Settings01Icon },
];

export function TabBar({ current, iconColor, activeColor, onChange }: TabBarProps) {
  return (
    <view className="tabbar">
      {TABS.map((t) => (
        <view className="tabbar-item" key={t.key} bindtap={() => onChange(t.key)}>
          <Icon icon={t.icon} size={22} color={current === t.key ? activeColor : iconColor} />
          <text className={'tabbar-label' + (current === t.key ? ' tabbar-label--on' : '')}>
            {t.label}
          </text>
        </view>
      ))}
    </view>
  );
}
