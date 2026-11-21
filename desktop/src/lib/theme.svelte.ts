import { api } from './api';
import { applyThemePack, initThemePacks, themePackAppearance, THEME_PACK_KEY } from './themePacks.svelte';

type BaseTheme = 'auto' | 'light' | 'dark';
export type ThemeMode = BaseTheme | 'custom';
export type ResolvedTheme = 'light' | 'dark';
export type ThemeBackground = 'default' | 'color' | 'image';

const STORAGE_KEY = 'tinymusic.theme';
const MODE_KEY = 'tinymusic.theme.mode';
const BACKGROUND_KEY = 'tinymusic.theme.background';
const IMAGE_KEY = 'tinymusic.theme.image';
const DEFAULT_COLOR = '#657d94';

function readBackground() {
  try {
    const saved = JSON.parse(localStorage.getItem(BACKGROUND_KEY) ?? 'null');
    return {
      kind: (saved?.kind === 'color' || saved?.kind === 'image' ? saved.kind : 'default') as ThemeBackground,
      color: validColor(saved?.color) ? saved.color : DEFAULT_COLOR,
    };
  } catch {
    return { kind: 'default' as const, color: DEFAULT_COLOR };
  }
}

function validColor(value: unknown): value is string {
  return typeof value === 'string' && /^#[0-9a-f]{6}$/i.test(value);
}

function readImage() {
  try {
    const saved = JSON.parse(localStorage.getItem(IMAGE_KEY) ?? 'null');
    if (typeof saved?.name === 'string' && typeof saved?.url === 'string'
      && /^data:image\/jpeg;base64,[A-Za-z0-9+/]+=*$/.test(saved.url)) {
      return { name: saved.name as string, url: saved.url as string };
    }
  } catch {
    /* A missing or invalid image falls back to the default background. */
  }
  return null;
}

export const themeBackground = $state({
  ...readBackground(),
  image: readImage(),
});

function applyBackground() {
  const root = document.documentElement;
  const kind = theme.mode === 'custom' ? themeBackground.kind : 'default';
  const image = kind === 'image' ? themeBackground.image : null;
  root.dataset.background = image ? 'image' : kind === 'color' ? 'color' : 'default';
  root.style.setProperty('--custom-theme-color', themeBackground.color);
  if (image) root.style.setProperty('--custom-theme-image', `url("${image.url}")`);
  else root.style.removeProperty('--custom-theme-image');
}

export function setThemeBackground(kind: ThemeBackground, color = themeBackground.color) {
  if (!validColor(color)) return;
  localStorage.setItem(BACKGROUND_KEY, JSON.stringify({ kind, color }));
  themeBackground.kind = kind;
  themeBackground.color = color;
  applyBackground();
}

export async function importThemeImage(file: File) {
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type) || file.size > 20 * 1024 * 1024) {
    throw new Error('请选择不超过 20 MB 的 JPG、PNG 或 WebP 图片');
  }
  const source = URL.createObjectURL(file);
  try {
    const image = new Image();
    image.src = source;
    await image.decode();
    const scale = Math.min(1, 1920 / Math.max(image.naturalWidth, image.naturalHeight));
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
    canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
    const context = canvas.getContext('2d');
    if (!context) throw new Error('无法读取背景图片');
    context.fillStyle = '#ffffff';
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.drawImage(image, 0, 0, canvas.width, canvas.height);

    const imported = { name: file.name, url: canvas.toDataURL('image/jpeg', 0.82) };
    localStorage.setItem(IMAGE_KEY, JSON.stringify(imported));
    themeBackground.image = imported;
    setThemeBackground('image');
  } finally {
    URL.revokeObjectURL(source);
  }
}

function storedBase(): BaseTheme {
  try {
    const v = localStorage.getItem(STORAGE_KEY);
    if (v === 'light' || v === 'dark' || v === 'auto') return v;
  } catch {
    /* ignore */
  }
  return 'auto';
}

const media = window.matchMedia('(prefers-color-scheme: dark)');
let base = storedBase();

function storedMode(): ThemeMode {
  try {
    const saved = localStorage.getItem(MODE_KEY);
    if (saved === 'custom' || saved === base) return saved;
    if (!saved && (localStorage.getItem(THEME_PACK_KEY) || themeBackground.kind !== 'default')) return 'custom';
  } catch {
    /* Use the base theme if storage is unavailable. */
  }
  return base;
}

export const theme = $state<{ mode: ThemeMode; resolved: ResolvedTheme }>({
  mode: storedMode(),
  resolved: media.matches ? 'dark' : 'light'
});

function resolve(): ResolvedTheme {
  if (theme.mode === 'custom') return themePackAppearance();
  if (base === 'auto') return media.matches ? 'dark' : 'light';
  return base;
}

function apply() {
  theme.resolved = resolve();
  document.documentElement.dataset.theme = theme.resolved;
  applyThemePack(theme.resolved, theme.mode === 'custom');
  applyBackground();
  // 窗口标题栏/原生控件跟着一起变（auto 时交还给系统）
  api.setWindowTheme(theme.mode === 'custom' ? theme.resolved : base).catch(() => {});
}

export function setTheme(mode: ThemeMode) {
  theme.mode = mode;
  if (mode !== 'custom') base = mode;
  try {
    localStorage.setItem(STORAGE_KEY, base);
    localStorage.setItem(MODE_KEY, mode);
  } catch {
    /* ignore */
  }
  apply();
}

/** 在挂载前调用，避免首帧闪一下深色 */
export function initTheme() {
  media.addEventListener('change', () => {
    if (theme.mode === 'auto') apply();
  });
  apply();
  void initThemePacks(apply);
}
