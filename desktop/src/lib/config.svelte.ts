/** 全局生效的应用配置（目前主要是「网盘是否启用」） */
import { api, type Settings } from './api';

export function hasCloud(settings: Settings) {
  return settings.webdav_enabled
    ? !!settings.webdav_endpoint.trim()
    : settings.s3_enabled && !!settings.s3_bucket;
}

export function isCloudProvider(provider?: string) {
  return provider === 's3' || provider === 'webdav';
}

export const appCfg = $state({
  loaded: false,
  s3Enabled: false,
});

export async function refreshAppCfg() {
  try {
    const s = await api.settingsGet();
    appCfg.s3Enabled = hasCloud(s);
    appCfg.loaded = true;
    return s;
  } catch {
    appCfg.s3Enabled = false;
    appCfg.loaded = true;
    return null;
  }
}
