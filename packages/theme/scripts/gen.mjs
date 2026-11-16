#!/usr/bin/env node
/**
 * 设计令牌生成器：desktop/src/app.css → mobile 能用的令牌。
 *
 * 为什么需要它：
 * - 桌面的颜色写在 oklch() 里，还用了 color-mix()，Lynx 两个都不支持；
 * - 桌面还用了 backdrop-filter 做玻璃，Lynx 也没有（用半透明 + 描边模拟）。
 * 所以这里把颜色提前算成 sRGB 的 hex / rgba，并把两套主题输出成 class 切换。
 *
 * 用法：
 *   node scripts/gen.mjs          # 写 dist/lynx-tokens.css + dist/tokens.json
 *   node scripts/gen.mjs --check  # 只比对，不一致就退出 1（CI 用）
 */

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '../../..');
const cssPath = resolve(repo, 'desktop/src/app.css');
const outCss = resolve(here, '../dist/lynx-tokens.css');
const outJson = resolve(here, '../dist/tokens.json');

const css = readFileSync(cssPath, 'utf8');

/** 取出某个选择器块里的声明（只处理顶层块，够用） */
function block(selector, from = 0) {
  const idx = css.indexOf(selector, from);
  if (idx < 0) return { text: '', end: -1 };
  const open = css.indexOf('{', idx);
  if (open < 0) return { text: '', end: -1 };
  let depth = 0;
  for (let i = open; i < css.length; i++) {
    if (css[i] === '{') depth++;
    else if (css[i] === '}') {
      depth--;
      if (depth === 0) return { text: css.slice(open + 1, i), end: i };
    }
  }
  return { text: '', end: -1 };
}

const darkBlock = block(':root {').text;
const lightStart = css.indexOf(":root[data-theme='light'] {");
const lightBlock = lightStart >= 0 ? css.slice(css.indexOf('{', lightStart) + 1, (() => {
  let depth = 0;
  for (let i = css.indexOf('{', lightStart); i < css.length; i++) {
    if (css[i] === '{') depth++;
    else if (css[i] === '}') {
      depth--;
      if (depth === 0) return i;
    }
  }
  return css.length;
})()) : '';

// ---------------- 颜色计算 ----------------

function oklchToRgb(L, C, hDeg, alpha = 1) {
  const h = (hDeg * Math.PI) / 180;
  const a = C * Math.cos(h);
  const b = C * Math.sin(h);

  const l_ = L + 0.3963377774 * a + 0.2158037573 * b;
  const m_ = L - 0.1055613458 * a - 0.0638541728 * b;
  const s_ = L - 0.0894841775 * a - 1.291485548 * b;
  const l = l_ ** 3;
  const m = m_ ** 3;
  const s = s_ ** 3;

  let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
  let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
  let bl = -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s;

  const gamma = (v) => (v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055);
  const to255 = (v) => Math.max(0, Math.min(255, Math.round(gamma(Math.max(0, Math.min(1, v))) * 255)));

  if (alpha >= 1) {
    const hex = (n) => n.toString(16).padStart(2, '0');
    return '#' + hex(to255(r)) + hex(to255(g)) + hex(to255(bl));
  }
  const a255 = Math.round(alpha * 1000) / 1000;
  return `rgba(${to255(r)}, ${to255(g)}, ${to255(bl)}, ${a255})`;
}

function parseColor(raw) {
  const s = raw.trim();

  const oklch = s.match(/^oklch\(\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*(?:\/\s*([\d.]+%?)\s*)?\)$/);
  if (oklch) {
    const alpha = oklch[4] ? (oklch[4].endsWith('%') ? parseFloat(oklch[4]) / 100 : parseFloat(oklch[4])) : 1;
    return oklchToRgb(parseFloat(oklch[1]), parseFloat(oklch[2]), parseFloat(oklch[3]), alpha);
  }
  if (/^#[0-9a-f]{3,8}$/i.test(s)) return s;
  if (/^rgba?\(/i.test(s)) return s.replace(/\s+/g, '');
  if (/^hsla?\(/i.test(s)) return s.replace(/\s+/g, '');
  return null;
}

/** color-mix(in oklch, <color> N%, transparent) → 带 alpha 的同色 */
function parseColorMix(raw) {
  const m = raw.match(/^color-mix\(\s*in oklch,\s*(.+?)\s+([\d.]+)%,\s*transparent\s*\)$/);
  if (!m) return null;
  const base = parseColor(m[1]) ?? m[1];
  const pct = parseFloat(m[2]) / 100;
  const rgb = base.match(/^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i);
  if (rgb) {
    return `rgba(${parseInt(rgb[1], 16)}, ${parseInt(rgb[2], 16)}, ${parseInt(rgb[3], 16)}, ${Math.round(pct * 1000) / 1000})`;
  }
  const r = base.match(/^rgba?\((\d+),\s*(\d+),\s*(\d+)/);
  if (r) return `rgba(${r[1]}, ${r[2]}, ${r[3]}, ${Math.round(pct * 1000) / 1000})`;
  return null;
}

function declarations(text) {
  const out = {};
  for (const line of text.split('\n')) {
    const m = line.match(/^\s*(--[\w-]+)\s*:\s*([^;]+);/);
    if (m) out[m[1]] = m[2].trim();
  }
  return out;
}

const dark = declarations(darkBlock);
const lightRaw = declarations(lightBlock);
const light = { ...dark, ...lightRaw };

const NON_COLOR = /(blur|px|rem|em|%|deg|calc\(|inset|solid|none|var\(--(font|side|titlebar|panel-radius|radius|glass-blur))/i;

function resolveTheme(tokens) {
  const cache = new Map();
  function resolveVar(name, seen = new Set()) {
    if (cache.has(name)) return cache.get(name);
    if (seen.has(name)) return undefined;
    seen.add(name);
    const raw = tokens[name];
    if (raw == null) return undefined;
    const out = resolveValue(raw, seen);
    if (out != null) cache.set(name, out);
    return out;
  }
  function resolveValue(raw, seen) {
    let v = raw.trim();
    // 把字符串里的 var(--x) 全部展开（color-mix 里也会出现）
    for (let i = 0; i < 6 && v.includes('var('); i++) {
      v = v.replace(/var\((--[\w-]+)\)/g, (m, name) => resolveVar(name, seen) ?? m);
    }
    if (v.startsWith('var(')) {
      const name = v.slice(4, v.indexOf(')')).trim();
      return resolveVar(name, seen);
    }
    const mixed = parseColorMix(v);
    if (mixed) return mixed;
    const color = parseColor(v);
    if (color) return color;

    // 兜底：把嵌在复合值里的颜色函数（box-shadow 等）也换成 sRGB
    const patched = v
      .replace(/color-mix\(in oklch,[^)]*\)/g, (m) => parseColorMix(m) ?? m)
      .replace(/oklch\([^)]*\)/g, (m) => parseColor(m) ?? m);
    if (patched !== v) return patched;
    return null;
  }
  const resolved = {};
  const unresolved = [];
  for (const name of Object.keys(tokens)) {
    const raw = tokens[name];
    const v = resolveValue(raw, new Set());
    if (v != null) {
      resolved[name] = v;
    } else {
      resolved[name] = raw;
      if (/oklch\(|color-mix\(/.test(raw)) unresolved.push(name);
    }
  }
  if (unresolved.length) console.warn('⚠ 没能换算的颜色（Lynx 会不认）:', unresolved.join(', '));
  return resolved;
}

const themes = { dark: resolveTheme(dark), light: resolveTheme(light) };

function toCss() {
  const lines = [
    '/* 由 packages/theme/scripts/gen.mjs 生成，不要手改。 */',
    '/* 来源：desktop/src/app.css 的 :root 与 :root[data-theme=\'light\'] */',
    '',
  ];
  for (const [name, tokens] of Object.entries(themes)) {
    lines.push(`.tm-${name} {`);
    // Lynx 的模板编码器不认 color-scheme，直接不写
    for (const [k, v] of Object.entries(tokens)) {
      if (typeof v !== 'string') continue;
      if (/backdrop-filter/.test(k)) continue;
      lines.push(`  ${k}: ${v};`);
    }
    lines.push('}');
    lines.push('');
  }
  return lines.join('\n');
}

const cssOut = toCss();
const jsonOut = JSON.stringify({ generatedFrom: 'desktop/src/app.css', themes }, null, 2) + '\n';

if (process.argv.includes('--check')) {
  const cssOk = existsSync(outCss) && readFileSync(outCss, 'utf8') === cssOut;
  const jsonOk = existsSync(outJson) && readFileSync(outJson, 'utf8') === jsonOut;
  if (!cssOk || !jsonOk) {
    console.error('✗ 令牌产物不是最新：请运行 pnpm -F @tinymusic/theme gen');
    process.exit(1);
  }
  console.log('✓ 令牌产物与 desktop/src/app.css 一致');
} else {
  writeFileSync(outCss, cssOut);
  writeFileSync(outJson, jsonOut);
  const count = Object.keys(themes.dark).length;
  console.log(`✓ 生成 ${count} 个令牌（dark/light），输出 dist/lynx-tokens.css 与 dist/tokens.json`);
}
