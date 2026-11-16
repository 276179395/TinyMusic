import { useCallback, useEffect, useState } from '@lynx-js/react';
import { api } from '@tinymusic/shared/api';
import { QUALITY_ORDER } from '@tinymusic/shared/quality';
import type { Quality, Settings as SettingsModel } from '@tinymusic/shared/types';

import { qualityLabel } from '@tinymusic/shared/format';

/**
 * 设置页（mobile）：下载目录、并发、默认音质。
 * 托盘/自动更新/窗口主题这些桌面专属项不做。
 */
export function Settings() {
  const [model, setModel] = useState<SettingsModel | null>(null);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    'background only';
    api
      .settingsGet()
      .then((s) => setModel(s))
      .catch((e: unknown) => setError(String(e)));
  }, []);

  const save = useCallback(
    (next: SettingsModel) => {
      'background only';
      setModel(next);
      setSaved(false);
      api
        .settingsSet(next)
        .then(() => setSaved(true))
        .catch((e: unknown) => setError(String(e)));
    },
    []
  );

  if (!model) {
    return (
      <view className="page-content">
        <text className="home-hint">{error || '读取设置…'}</text>
      </view>
    );
  }

  const onQuality = (q: Quality) => {
    save({ ...model, default_quality: q });
  };

  const onConcurrency = (delta: number) => {
    const next = Math.max(1, Math.min(6, model.concurrency + delta));
    save({ ...model, concurrency: next });
  };

  return (
    <view className="page-content">
      <view className="page-head">
        <text className="page-title">设置</text>
      </view>

      <view className="section">
        <text className="section-title">下载目录</text>
        <text className="section-value">{model.download_dir || '未设置'}</text>
        <text className="section-hint">iOS 上固定为 App 的「文件」目录，可在文件 App 里看到</text>
      </view>

      <view className="section">
        <text className="section-title">默认音质</text>
        <view className="quality-row">
          {QUALITY_ORDER.filter((q) => q === 'standard' || q === 'super' || q === 'lossless').map((q) => (
            <view
              key={q}
              className={'quality-chip' + (model.default_quality === q ? ' quality-chip--on' : '')}
              bindtap={() => onQuality(q)}
            >
              <text className="quality-chip-text">{qualityLabel(q)}</text>
            </view>
          ))}
        </view>
      </view>

      <view className="section">
        <text className="section-title">同时下载数</text>
        <view className="stepper">
          <view className="stepper-btn" bindtap={() => onConcurrency(-1)}>
            <text className="stepper-btn-text">−</text>
          </view>
          <text className="stepper-value">{String(model.concurrency)}</text>
          <view className="stepper-btn" bindtap={() => onConcurrency(1)}>
            <text className="stepper-btn-text">＋</text>
          </view>
        </view>
      </view>

      {saved ? <text className="home-hint">已保存</text> : null}
      {error ? <text className="home-error">{error}</text> : null}

      <view className="section">
        <text className="section-title">关于</text>
        <text className="section-value">TinyMusic mobile 0.7.2</text>
        <text className="section-hint">业务逻辑与桌面共用 Rust 后端（crates/app）</text>
      </view>
    </view>
  );
}
