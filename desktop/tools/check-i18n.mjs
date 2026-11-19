#!/usr/bin/env node
/**
 * 检查桌面端 i18n 覆盖率：
 *   1. 所有 t('中文原文') 是否都有英文译文；
 *   2. 有没有 t() 里混进英文 / 空串。
 *
 * 用法：cd desktop && node tools/check-i18n.mjs
 * 退出码 1 表示有缺翻译。
 */

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const src = join(root, 'src');

/** @param {string} dir */
function walk(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...walk(p));
    else if (/\.(svelte|ts)$/.test(name) && !p.includes('/lib/i18n/messages/') && !p.endsWith('/lib/i18n.svelte.ts'))
      out.push(p);
  }
  return out;
}

const single = /\bt\(\s*'((?:\\.|[^'\\])*)'/g;
const double = /\bt\(\s*"((?:\\.|[^"\\])*)"/g;
const scoped = /\btc\(\s*'([^']*)'\s*,\s*'((?:\\.|[^'\\])*)'/g;

/** @type {Map<string, {file: string, line: number}[]>} */
const used = new Map();
/** @type {Map<string, {file: string, line: number}[]>} */
const scopedUsed = new Map();
for (const file of walk(src)) {
  const text = readFileSync(file, 'utf8');
  for (const re of [single, double]) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(text))) {
      const line = text.slice(0, m.index).split('\n').length;
      const key = m[1].replace(/\\(['"\\])/g, '$1');
      const arr = used.get(key) ?? [];
      arr.push({ file: relative(root, file), line });
      used.set(key, arr);
    }
  }
  scoped.lastIndex = 0;
  let m;
  while ((m = scoped.exec(text))) {
    const line = text.slice(0, m.index).split('\n').length;
    const key = m[1] + '|' + m[2].replace(/\\(['"\\])/g, '$1');
    const arr = scopedUsed.get(key) ?? [];
    arr.push({ file: relative(root, file), line });
    scopedUsed.set(key, arr);
  }
}

const names = ['common', 'shell', 'player', 'browse', 'details'];
/** @type {Record<string, string>} */
const en = {};
for (const name of names) {
  const mod = await import(join(root, 'src/lib/i18n/messages', name + '.ts'));
  const dict = Object.values(mod)[0];
  Object.assign(en, dict);
}

const missingScoped = [...scopedUsed.keys()].filter((k) => !en[k]).sort();
const missing = [...used.keys()].filter((k) => !en[k]).sort();
const bad = [...used.keys()]
  .filter((k) => !/[\u4e00-\u9fff]/.test(k) && !/^[\p{P}\p{S}\s]+$/u.test(k))
  .sort();

for (const key of missing) {
  const at = used.get(key).slice(0, 3).map((u) => u.file + ':' + u.line).join(', ');
  console.log('MISSING  ' + JSON.stringify(key) + '  @ ' + at);
}
for (const key of missingScoped) {
  const at = scopedUsed.get(key).slice(0, 3).map((u) => u.file + ':' + u.line).join(', ');
  console.log('MISSING-SCOPED  ' + JSON.stringify(key) + '  @ ' + at);
}
for (const key of bad) {
  console.log('NOT-CJK  ' + JSON.stringify(key) + '  @ ' + used.get(key)[0].file + ':' + used.get(key)[0].line);
}

console.log('');
console.log(
  'used=' +
    used.size +
    ' translated=' +
    (used.size - missing.length) +
    ' missing=' +
    missing.length +
    ' | scoped=' +
    scopedUsed.size +
    ' missing=' +
    missingScoped.length
);
if (missing.length || missingScoped.length || bad.length) process.exitCode = 1;
