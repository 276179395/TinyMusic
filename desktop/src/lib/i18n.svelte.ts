/**
 * 界面语言：跟随系统 / 简体中文 / English。
 *
 * 文案的「键」就是中文原文 —— t('设置') 在中文下原样返回，在英文下查表
 * 换成 Settings。这样不用给几百条文案起 key，也不会因为漏翻译把界面变成
 * 空白；没收录的英文条目会先回落到中文原文。
 *
 * 语言偏好和主题一样存在 localStorage：它是本机的显示偏好，不是业务数据。
 */

import { fmtCount } from '@tinymusic/shared/format';
import { common } from './i18n/messages/common';
import { shell } from './i18n/messages/shell';
import { player } from './i18n/messages/player';
import { browse } from './i18n/messages/browse';
import { details } from './i18n/messages/details';

export type LanguageSetting = 'auto' | 'zh' | 'en';
export type Lang = 'zh' | 'en';

/** 中文原文 -> 英文译文；按功能拆文件，避免一个几千行的巨型字典 */
const EN: Record<string, string> = {
  ...common,
  ...shell,
  ...player,
  ...browse,
  ...details
};

const STORAGE_KEY = 'tinymusic.language';

/** 系统语言：中文系优先中文，其余一律英文（英文是国际通用回落） */
function systemLang(): Lang {
  const list =
    navigator.languages && navigator.languages.length
      ? navigator.languages
      : [navigator.language || 'en'];
  for (const raw of list) {
    const l = (raw || '').toLowerCase();
    if (l.startsWith('zh')) return 'zh';
    if (l.startsWith('en')) return 'en';
  }
  return 'en';
}

function storedSetting(): LanguageSetting {
  try {
    const v = localStorage.getItem(STORAGE_KEY);
    if (v === 'auto' || v === 'zh' || v === 'en') return v;
  } catch {
    /* ignore */
  }
  return 'auto';
}

function resolve(setting: LanguageSetting): Lang {
  return setting === 'auto' ? systemLang() : setting;
}

export const i18n = $state<{ setting: LanguageSetting; lang: Lang }>({
  setting: storedSetting(),
  lang: 'zh'
});

/** 给 Intl / Date / 排序用的 BCP 47 标签 */
export function localeTag(): string {
  return i18n.lang === 'zh' ? 'zh-CN' : 'en-US';
}

function apply() {
  i18n.lang = resolve(i18n.setting);
  if (typeof document !== 'undefined') {
    document.documentElement.lang = i18n.lang === 'zh' ? 'zh-CN' : 'en';
    document.documentElement.dataset.lang = i18n.lang;
  }
  // 托盘菜单是 Rust 画的，单独通知一声；浏览器调试时没有这个命令
  if (typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window) {
    import('@tauri-apps/api/core')
      .then(({ invoke }) => invoke('set_ui_language', { lang: i18n.lang }))
      .catch(() => {
        /* 非 Tauri 环境或命令不可用：忽略 */
      });
  }
}

/** 挂载前调用，避免首帧中文闪一下 */
export function initI18n() {
  apply();
  // 系统语言在运行中变化时（auto 模式）跟着切
  window.addEventListener('languagechange', () => {
    if (i18n.setting === 'auto') apply();
  });
}

export function setLanguage(setting: LanguageSetting) {
  i18n.setting = setting;
  try {
    localStorage.setItem(STORAGE_KEY, setting);
  } catch {
    /* ignore */
  }
  apply();
}

const missing = new Set<string>();

function interpolate(text: string, vars?: Record<string, string | number>): string {
  if (!vars) return text;
  let out = text;
  for (const key in vars) {
    out = out.split('{' + key + '}').join(String(vars[key]));
  }
  return out;
}

function warnMissing(key: string) {
  if (import.meta.env.DEV && !missing.has(key)) {
    missing.add(key);
    console.warn('[i18n] missing translation:', key);
  }
}

/**
 * 翻译一条界面文案。
 *
 * 参数用 {name} 占位：t('已检查 {n} 首', { n: 12 })。
 * 中文模式直接返回原文（占位照样替换），所以中文文案与改造前逐字一致。
 */
export function t(source: string, vars?: Record<string, string | number>): string {
  // 读取 lang 让调用方自动获得响应式：语言切换后模板会重渲染
  const lang = i18n.lang;
  let out = source;
  if (lang === 'en') {
    const hit = EN[source];
    if (hit === undefined) {
      warnMissing(source);
      out = source;
    } else {
      out = hit;
    }
  }
  return interpolate(out, vars);
}

/**
 * 同一句中文在不同语境需要不同英文时用它：tc('tab', '歌曲')。
 * 中文仍然原样返回；英文先查「语境|原文」，没有就退回普通词条。
 */
export function tc(
  context: string,
  source: string,
  vars?: Record<string, string | number>
): string {
  const lang = i18n.lang;
  let out = source;
  if (lang === 'en') {
    const scoped = context + '|' + source;
    const hit = EN[scoped] ?? EN[source];
    if (hit === undefined) {
      warnMissing(scoped);
      out = source;
    } else {
      out = hit;
    }
  }
  return interpolate(out, vars);
}

/** 播放量 / 收藏数：中文用「万 / 亿」，英文用 12K / 1.2M */
export function fmtPlayCount(n: number): string {
  if (!n) return '';
  if (i18n.lang === 'en') {
    return new Intl.NumberFormat('en', { notation: 'compact', maximumFractionDigits: 1 }).format(n);
  }
  return fmtCount(n);
}
