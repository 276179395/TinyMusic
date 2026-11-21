import { api } from './api';
import type { ResolvedTheme } from './theme.svelte';

export const THEME_PACK_KEY = import.meta.env.DEV ? 'tinymusic.themePack.dev' : 'tinymusic.themePack.installed';
const TOKENS = [
  '--background', '--foreground', '--fg2', '--fg3', '--bg2', '--popover', '--brand', '--line',
  '--bg-tint',
] as const;
type Palette = { colors: Record<string, string>; image?: string; effect?: 'petals' | 'none' };
type ThemePack = {
  id: string; name: string; version: string; author?: string;
  appearance?: ResolvedTheme;
  palettes: Record<'base' | ResolvedTheme, Palette>;
};

export const themePacks = $state({
  items: [] as ThemePack[],
  activeId: '',
  loaded: false,
  error: '',
});

let onSelectionChange: (() => void) | undefined;

function selectedPack() {
  return themePacks.items.find((item) => item.id === themePacks.activeId);
}

export function themePackAppearance(): ResolvedTheme {
  return selectedPack()?.appearance ?? 'dark';
}

export function applyThemePack(resolved: ResolvedTheme, enabled: boolean) {
  const root = document.documentElement;
  for (const token of TOKENS) root.style.removeProperty(token);
  root.style.removeProperty('--theme-pack-image');
  delete root.dataset.themePack;
  delete root.dataset.themeEffect;
  if (!enabled) return;
  const pack = selectedPack();
  if (!pack) return;
  const { base, [resolved]: override } = pack.palettes;
  for (const [token, value] of Object.entries({ ...base.colors, ...override.colors })) {
    root.style.setProperty(token, value);
  }
  const image = override.image ?? base.image;
  const effect = override.effect ?? base.effect;
  if (effect === 'petals') root.dataset.themeEffect = effect;
  if (image) root.style.setProperty('--theme-pack-image', `url("${image}")`);
  root.dataset.themePack = image ? 'image' : 'color';
}

export async function initThemePacks(applySelection: () => void) {
  onSelectionChange = applySelection;
  try {
    // 旧版使用共享的 WebView 缓存。只删除主题数据库和它的选中记录。
    indexedDB.deleteDatabase('tinymusic-theme-packs');
    localStorage.removeItem('tinymusic.themePack');
    const results = await Promise.allSettled((await api.listThemePacks()).map(parseThemePack));
    const byId = new Map<string, ThemePack>();
    for (const result of results) {
      if (result.status === 'fulfilled') byId.set(result.value.id.toLowerCase(), result.value);
    }
    themePacks.items = [...byId.values()];
    const id = localStorage.getItem(THEME_PACK_KEY) ?? '';
    themePacks.activeId = themePacks.items.some((pack) => pack.id === id) ? id : '';
    applySelection();
  } catch (error) {
    themePacks.error = String(error);
  } finally {
    themePacks.loaded = true;
  }
}

export function selectThemePack(id: string) {
  localStorage.setItem(THEME_PACK_KEY, id);
  themePacks.activeId = id;
  onSelectionChange?.();
}

async function parseThemePack(source: Awaited<ReturnType<typeof api.readThemePack>>): Promise<ThemePack> {
  const config = source.config as Partial<ThemePack> & { formatVersion?: number } | null;
  if (config?.formatVersion !== 1 || typeof config.id !== 'string'
    || !/^[a-z0-9][a-z0-9_-]{0,63}$/i.test(config.id)
    || typeof config.name !== 'string' || !config.name.trim() || config.name.length > 80
    || typeof config.version !== 'string' || !config.version.trim() || config.version.length > 32
    || (config.author !== undefined && (typeof config.author !== 'string' || config.author.length > 80))
    || (config.appearance !== undefined && config.appearance !== 'light' && config.appearance !== 'dark')) {
    throw new Error('主题包 config.json 无效或版本不受支持');
  }
  const palettes: ThemePack['palettes'] = {
    base: { colors: {} }, light: { colors: {} }, dark: { colors: {} },
  };
  // Parse only. The imported stylesheet is never attached to the document.
  const stylesheet = new CSSStyleSheet();
  stylesheet.replaceSync(source.css);
  for (const rule of stylesheet.cssRules) {
    if (!(rule instanceof CSSStyleRule)) continue;
    for (const selector of rule.selectorText.split(',').map((value) => value.trim().replaceAll("'", '"'))) {
      const scope = selector === ':root' ? 'base'
        : selector === ':root[data-theme="light"]' ? 'light'
        : selector === ':root[data-theme="dark"]' ? 'dark' : null;
      if (!scope) continue;
      const palette = palettes[scope];
      const effect = rule.style.getPropertyValue('--bg-effect').trim();
      if (effect === 'petals' || effect === 'none') palette.effect = effect;
      for (const token of TOKENS) {
        const value = rule.style.getPropertyValue(token).trim();
        if (value && !/^(?:initial|inherit|unset|revert(?:-layer)?)$/i.test(value)
          && !/\b(?:var|env|attr|url)\s*\(/i.test(value) && CSS.supports('color', value)) {
          palette.colors[token] = value;
        }
      }
      const background = rule.style.getPropertyValue('--bg-image').trim();
      if (background) {
        const match = /^url\(\s*["']?@\/([a-z0-9._/-]+)["']?\s*\)$/i.exec(background);
        const data = match ? source.images[match[1]] : undefined;
        if (!data || !/^data:image\/(?:jpeg|png|webp);base64,[a-z0-9+/]+=*$/i.test(data)) {
          throw new Error('背景图片必须指向主题包内的图片');
        }
        palette.image = data;
      }
    }
  }
  if (!Object.values(palettes).some((palette) => palette.image || Object.keys(palette.colors).length)) {
    throw new Error('主题包没有可用的颜色或背景声明');
  }
  for (const data of new Set(Object.values(palettes).map((palette) => palette.image))) {
    if (!data) continue;
    const image = new Image();
    image.src = data;
    await image.decode();
  }
  return { id: config.id, name: config.name, version: config.version, author: config.author,
    appearance: config.appearance, palettes };
}

export async function importThemePack(path: string) {
  const pack = await parseThemePack(await api.readThemePack(path));
  await api.saveThemePack(path, pack.id);
  themePacks.items = [...themePacks.items.filter((item) => item.id.toLowerCase() !== pack.id.toLowerCase()), pack];
  selectThemePack(pack.id);
}
