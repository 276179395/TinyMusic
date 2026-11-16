import { useCallback, useEffect, useState } from '@lynx-js/react';
import { api } from '@tinymusic/shared/api';
import { QUALITY_ORDER } from '@tinymusic/shared/quality';
import { qualityLabel } from '@tinymusic/shared/format';
import type { Quality, Settings as SettingsModel } from '@tinymusic/shared/types';

interface FieldProps {
  label: string;
  value: string;
  placeholder?: string;
  password?: boolean;
  onChange: (v: string) => void;
}

function Field({ label, value, placeholder, onChange }: FieldProps) {
  return (
    <view className="field">
      <text className="field-label">{label}</text>
      <input
        className="field-input"
        value={value}
        placeholder={placeholder ?? ''}
        bindinput={(e: { detail?: { value?: string } }) => onChange(e.detail?.value ?? '')}
      />
    </view>
  );
}

/**
 * 设置页（mobile）：下载、音质、网盘。
 * 桌面专属项（托盘、自动更新、窗口主题）不出现。
 */
export function Settings() {
  const [model, setModel] = useState<SettingsModel | null>(null);
  const [dirty, setDirty] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    'background only';
    api
      .settingsGet()
      .then((s) => setModel(s))
      .catch((e: unknown) => setError(String(e)));
  }, []);

  const patch = useCallback((next: Partial<SettingsModel>) => {
    'background only';
    setModel((prev) => (prev ? { ...prev, ...next } : prev));
    setDirty(true);
    setMessage('');
  }, []);

  const save = useCallback(() => {
    'background only';
    if (!model) return;
    api
      .settingsSet(model)
      .then(() => {
        setDirty(false);
        setMessage('已保存');
      })
      .catch((e: unknown) => setError(String(e)));
  }, [model]);

  if (!model) {
    return (
      <view className="page-content">
        <text className="home-hint">{error || '读取设置…'}</text>
      </view>
    );
  }

  return (
    <view className="page-content">
      <view className="page-head">
        <text className="page-title">设置</text>
        <view className="page-head-action" bindtap={save}>
          <text className="page-head-action-text">{dirty ? '保存' : '已保存'}</text>
        </view>
      </view>

      <scroll-view className="results" scroll-orientation="vertical">
        <view className="section">
          <text className="section-title">下载目录</text>
          <text className="section-value">{model.download_dir || '未设置'}</text>
          <text className="section-hint">iOS 固定为 App 的「文件」目录，可在文件 App 里看到</text>
        </view>

        <view className="section">
          <text className="section-title">默认音质</text>
          <view className="quality-row">
            {QUALITY_ORDER.filter((q) => q === 'standard' || q === 'super' || q === 'lossless').map((q: Quality) => (
              <view
                key={q}
                className={'quality-chip' + (model.default_quality === q ? ' quality-chip--on' : '')}
                bindtap={() => patch({ default_quality: q })}
              >
                <text className="quality-chip-text">{qualityLabel(q)}</text>
              </view>
            ))}
          </view>
        </view>

        <view className="section">
          <text className="section-title">同时下载数</text>
          <view className="stepper">
            <view className="stepper-btn" bindtap={() => patch({ concurrency: Math.max(1, model.concurrency - 1) })}>
              <text className="stepper-btn-text">−</text>
            </view>
            <text className="stepper-value">{String(model.concurrency)}</text>
            <view className="stepper-btn" bindtap={() => patch({ concurrency: Math.min(6, model.concurrency + 1) })}>
              <text className="stepper-btn-text">＋</text>
            </view>
          </view>
        </view>

        <view className="section">
          <view className="switch-row">
            <text className="section-title">启用网盘（S3 兼容）</text>
            <view
              className={'switch' + (model.s3_enabled ? ' switch--on' : '')}
              bindtap={() => patch({ s3_enabled: !model.s3_enabled })}
            >
              <view className="switch-knob" />
            </view>
          </view>
          <Field label="Endpoint" value={model.s3_endpoint} placeholder="https://s3.example.com" onChange={(v) => patch({ s3_endpoint: v })} />
          <Field label="Region" value={model.s3_region} placeholder="auto" onChange={(v) => patch({ s3_region: v })} />
          <Field label="Bucket" value={model.s3_bucket} placeholder="my-music" onChange={(v) => patch({ s3_bucket: v })} />
          <Field label="Access Key" value={model.s3_access_key} onChange={(v) => patch({ s3_access_key: v })} />
          <Field label="Secret Key" value={model.s3_secret_key} password onChange={(v) => patch({ s3_secret_key: v })} />
          <Field label="前缀目录" value={model.s3_prefix} placeholder="music/" onChange={(v) => patch({ s3_prefix: v })} />
          <view className="switch-row">
            <text className="section-title">Path style 寻址</text>
            <view
              className={'switch' + (model.s3_path_style ? ' switch--on' : '')}
              bindtap={() => patch({ s3_path_style: !model.s3_path_style })}
            >
              <view className="switch-knob" />
            </view>
          </view>
        </view>

        <view className="section">
          <text className="section-title">关于</text>
          <text className="section-value">TinyMusic mobile 0.7.2</text>
          <text className="section-hint">业务逻辑与桌面共用 Rust 后端（crates/app）</text>
        </view>

        {message ? <text className="home-hint">{message}</text> : null}
        {error ? <text className="home-error">{error}</text> : null}
      </scroll-view>
    </view>
  );
}
