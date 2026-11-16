import { EQ_MAX_DB, EQ_MIN_DB } from '@tinymusic/shared/eq';

import { EQ_BANDS, EQ_PRESETS, equalizer, useEqualizer } from '../state/equalizer.js';

/**
 * 均衡器页：10 段增益 + 预增益 + 预设。
 * 频段和预设来自 packages/shared/eq（桌面同一份），DSP 在原生 tap。
 */
export function Equalizer({ onBack }: { onBack: () => void }) {
  const eq = useEqualizer();

  return (
    <view className="page-content">
      <view className="page-head">
        <view className="page-head-action" bindtap={onBack}>
          <text className="page-head-action-text">返回</text>
        </view>
        <view className="page-head-action" bindtap={() => equalizer.reset()}>
          <text className="page-head-action-text">重置</text>
        </view>
      </view>

      <view className="switch-row">
        <text className="section-title">启用均衡器</text>
        <view
          className={'switch' + (eq.enabled ? ' switch--on' : '')}
          bindtap={() => equalizer.setEnabled(!eq.enabled)}
        >
          <view className="switch-knob" />
        </view>
      </view>

      <scroll-view className="results" scroll-orientation="vertical">
        <view className="eq-guide">
          {(EQ_BANDS as { label: string; hz: number }[]).map((band, i) => (
            <view className="eq-row" key={band.label}>
              <text className="eq-label">{band.label}</text>
              <view className="eq-bar">
                <view
                  className="eq-fill"
                  style={{
                    width: String(Math.round(((eq.gains[i] - EQ_MIN_DB) / (EQ_MAX_DB - EQ_MIN_DB)) * 100)) + '%',
                  }}
                />
              </view>
              <view className="eq-actions">
                <view
                  className="stepper-btn"
                  bindtap={() => equalizer.setBand(i, eq.gains[i] - 1)}
                >
                  <text className="stepper-btn-text">−</text>
                </view>
                <text className="eq-value">{eq.gains[i] > 0 ? '+' + eq.gains[i] : String(eq.gains[i])}</text>
                <view
                  className="stepper-btn"
                  bindtap={() => equalizer.setBand(i, eq.gains[i] + 1)}
                >
                  <text className="stepper-btn-text">＋</text>
                </view>
              </view>
            </view>
          ))}
        </view>

        <view className="section">
          <text className="section-title">预设</text>
          <view className="quality-row">
            {EQ_PRESETS.map((p) => (
              <view
                key={p.id}
                className={'quality-chip' + (eq.preset === p.id ? ' quality-chip--on' : '')}
                bindtap={() => equalizer.usePreset(p)}
              >
                <text className="quality-chip-text">{p.name}</text>
              </view>
            ))}
          </view>
        </view>

        <text className="section-hint">
          均衡器走原生音频处理（MTAudioProcessingTap），对流媒体和本地文件都生效；当前为内存态，重开 App 回默认
        </text>
      </scroll-view>
    </view>
  );
}
