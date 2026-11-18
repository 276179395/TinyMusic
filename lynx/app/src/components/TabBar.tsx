import { Home01Icon, Download04Icon, CloudIcon, UserIcon, Settings01Icon } from '@hugeicons/core-free-icons';

import { Icon } from './Icon.js';

export type TabKey = 'home' | 'downloads' | 'cloud' | 'account' | 'settings';

interface TabBarProps {
  current: TabKey;
  /** 未选中颜色（系统 label2 近似值） */
  tintColor: string;
  /** 选中颜色（苹果红） */
  activeColor: string;
  onChange: (tab: TabKey) => void;
  /** 底部安全区，由 App 传入 */
  bottomInset?: number;
}

const TABS: { key: TabKey; label: string; icon: typeof Home01Icon }[] = [
  { key: 'home', label: '现在就听', icon: Home01Icon },
  { key: 'downloads', label: '资料库', icon: Download04Icon },
  { key: 'cloud', label: '网盘', icon: CloudIcon },
  { key: 'account', label: '账号', icon: UserIcon },
  { key: 'settings', label: '设置', icon: Settings01Icon },
];

export function TabBar({ current, tintColor, activeColor, onChange, bottomInset = 0 }: TabBarProps) {
  return (
    <view
      className="ios-tabbar"
      style={{ height: 50 + bottomInset + 'px', paddingBottom: bottomInset + 'px' }}
    >
      {TABS.map((t) => {
        const on = current === t.key;
        return (
          <view className="ios-tab" key={t.key} bindtap={() => onChange(t.key)}>
            <view className="ios-tab-icon">
              <Icon icon={t.icon} size={24} color={on ? activeColor : tintColor} />
            </view>
            <text className={'ios-tab-label' + (on ? ' ios-tab-label--on' : '')}>{t.label}</text>
          </view>
        );
      })}
    </view>
  );
}
