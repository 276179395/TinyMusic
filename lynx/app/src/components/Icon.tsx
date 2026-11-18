import type { IconNode } from '@hugeicons/core-free-icons';

interface IconProps {
  icon: IconNode;
  size?: number;
  color?: string;
  strokeWidth?: number;
}

const ATTR_MAP: Record<string, string> = {
  strokeWidth: 'stroke-width',
  strokeLinecap: 'stroke-linecap',
  strokeLinejoin: 'stroke-linejoin',
  fillRule: 'fill-rule',
  clipRule: 'clip-rule',
};

function attrsToString(attrs: Record<string, unknown>): string {
  return Object.entries(attrs)
    .filter(([, v]) => v !== undefined && v !== null && v !== false)
    .map(([k, v]) => {
      const name = ATTR_MAP[k] ?? k;
      if (v === true) return name;
      return `${name}="${String(v)}"`;
    })
    .join(' ');
}

/**
 * Lynx 的 <svg> 元素吃的是 SVG 字符串（content 属性），不能像 web 那样写子节点。
 * 所以把 Hugeicons 的 IconNode 序列化成字符串——图标数据与桌面是同一套。
 */
export function iconSvg(icon: IconNode, size = 24, color = '#fafafa', strokeWidth = 1.6): string {
  const body = icon
    .map(([tag, attrs]) => {
      const merged = { ...(attrs as Record<string, unknown>), stroke: (attrs as Record<string, unknown>).stroke ?? color };
      return `<${tag} ${attrsToString(merged)} />`;
    })
    .join('');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="${strokeWidth}" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;
}

export function Icon({ icon, size = 24, color = '#fafafa', strokeWidth = 1.6 }: IconProps) {
  return <svg content={iconSvg(icon, size, color, strokeWidth)} style={{ width: `${size}px`, height: `${size}px` }} />;
}
