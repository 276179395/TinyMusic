#!/usr/bin/env python3
"""把 app.css 里的 oklch() / color-mix() 令牌换算成 sRGB 兜底值。

macOS 11/12 的系统 WKWebView 跟着系统走，装不了新 Safari；引擎一旦不认
oklch()（Safari 15.4 之前），整页的颜色令牌就全部失效：页面变白、卡片变透明、
发丝线和阴影一起消失。这里把设计令牌逐个换算成等价的 sRGB 字面量，包在
@supports not (color: oklch(...)) 里，现代引擎一条都不会命中。

用法：
    python3 tools/srgb-fallback.py          # 重新生成
    python3 tools/srgb-fallback.py --check   # 校验是否过期（提交前跑）

改了 src/app.css 顶部的令牌（:root / :root[data-theme='light']）之后要跑一遍。
"""

from __future__ import annotations

import math
import re
import sys
from pathlib import Path

# Windows 的默认控制台编码是 cp1252，直接 print 中文会 UnicodeEncodeError。
# 这个脚本要跨平台跑（release 的 Windows job 也会调 --check），先切到 UTF-8。
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    except Exception:  # 老 Python / 被重定向的流：保持原样
        pass

CSS_PATH = Path(__file__).resolve().parent.parent / "src" / "app.css"
START = "/* @generated:srgb-fallback:start */"
END = "/* @generated:srgb-fallback:end */"

OKLCH_RE = re.compile(r"oklch\([^()]*\)")
DECL_RE = re.compile(r"(--[\w-]+)\s*:\s*([^;]*?);", re.S)


# ---------------------------------------------------------------- 颜色换算
def oklch_to_linear(L: float, C: float, H: float) -> list[float]:
    h = math.radians(H)
    a, b = C * math.cos(h), C * math.sin(h)
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_**3, m_**3, s_**3
    return [
        +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    ]


def in_gamut(rgb: list[float]) -> bool:
    return all(-1e-4 <= c <= 1 + 1e-4 for c in rgb)


def oklch_to_srgb(L: float, C: float, H: float) -> list[float]:
    """OKLCH -> sRGB(0..255)。超出 sRGB 色域时按 CSS Color 4 的做法压色度。"""

    def encode(u: float) -> float:
        u = max(0.0, min(1.0, u))
        return 12.92 * u if u <= 0.0031308 else 1.055 * u ** (1 / 2.4) - 0.055

    lin = oklch_to_linear(L, C, H)
    if not in_gamut(lin):
        lo, hi = 0.0, C
        for _ in range(32):
            mid = (lo + hi) / 2
            if in_gamut(oklch_to_linear(L, mid, H)):
                lo = mid
            else:
                hi = mid
        lin = oklch_to_linear(L, lo, H)
    return [encode(c) * 255 for c in lin]


def parse_oklch(text: str) -> tuple[float, float, float, float]:
    body = text[text.index("(") + 1 : text.rindex(")")]
    if "/" in body:
        left, alpha = body.split("/", 1)
        alpha = alpha.strip()
        alpha = float(alpha[:-1]) / 100 if alpha.endswith("%") else float(alpha)
    else:
        left, alpha = body, 1.0
    parts = left.replace(",", " ").split()
    L = float(parts[0][:-1]) / 100 if parts[0].endswith("%") else float(parts[0])
    return L, float(parts[1]), float(parts[2]), alpha


def fmt(rgb: list[float], alpha: float) -> str:
    r, g, b = (int(round(c)) for c in rgb)
    if alpha >= 0.999:
        return "#%02x%02x%02x" % (r, g, b)
    a = ("%.3f" % alpha).rstrip("0").rstrip(".")
    return "rgba(%d, %d, %d, %s)" % (r, g, b, a)


def convert_literals(value: str) -> str:
    def repl(m: re.Match[str]) -> str:
        L, C, H, alpha = parse_oklch(m.group(0))
        return fmt(oklch_to_srgb(L, C, H), alpha)

    return OKLCH_RE.sub(repl, value)


# ---------------------------------------------------------------- 解析令牌
def read_css() -> str:
    return CSS_PATH.read_text(encoding="utf-8")


def block_body(css: str, selector: str) -> str:
    i = css.index(selector)
    j = css.index("{", i)
    depth, k = 0, j
    while k < len(css):
        if css[k] == "{":
            depth += 1
        elif css[k] == "}":
            depth -= 1
            if depth == 0:
                break
        k += 1
    return css[j + 1 : k]


def tokens(body: str) -> list[tuple[str, str]]:
    return [(m.group(1), m.group(2).strip()) for m in DECL_RE.finditer(body)]


def resolve_vars(value: str, table: dict[str, str], depth: int = 0) -> str:
    if depth > 8:
        return value
    return re.sub(
        r"var\((--[\w-]+)\)",
        lambda m: resolve_vars(table.get(m.group(1), m.group(0)), table, depth + 1),
        value,
    )


MIX_RE = re.compile(
    r"color-mix\(in oklch,\s*(.+?)\s+([\d.]+)%,?\s*transparent\s*\)", re.S
)


def convert_mixes(value: str, table: dict[str, str]) -> str:
    """color-mix(in oklch, X P%, transparent) 等价于 X 取 P% 的透明度。"""

    def repl(m: re.Match[str]) -> str:
        base = resolve_vars(m.group(1).strip(), table)
        if not base.startswith("oklch("):
            raise SystemExit(f"认不出的 color-mix 底色：{m.group(0)}")
        L, C, H, alpha = parse_oklch(base)
        return fmt(oklch_to_srgb(L, C, H), alpha * float(m.group(2)) / 100)

    return MIX_RE.sub(repl, value)


def squash(value: str) -> str:
    """多行渐变折成一行，生成块里每条令牌都只占一行。"""
    return " ".join(value.split())


def declarations(decls: list[tuple[str, str]], table: dict[str, str]) -> tuple[list[str], list[str]]:
    colors: list[str] = []
    mixes: list[str] = []
    for name, value in decls:
        if "color-mix(" in value:
            mixes.append(f"{name}: {squash(convert_literals(convert_mixes(value, table)))};")
        elif "oklch(" in value:
            colors.append(f"{name}: {squash(convert_literals(value))};")
    return colors, mixes


def build(css: str) -> str:
    dark_body = block_body(css, ":root {")
    light_body = block_body(css, ":root[data-theme='light'] {")
    dark = tokens(dark_body)
    light = tokens(light_body)
    dark_table = {k: v for k, v in dark}
    light_table = {**dark_table, **{k: v for k, v in light}}

    def wrap(sel: str, body: list[str], indent: str) -> list[str]:
        if not body:
            return []
        return [f"{indent}{sel} {{"] + [f"{indent}  {line}" for line in body] + [f"{indent}}}"]

    dark_colors, dark_mixes = declarations(dark, dark_table)
    light_colors, light_mixes = declarations(light, light_table)
    # 浅色主题继承 :root 里没有重定义的令牌（比如 --warn-bg），按浅色的 --warn 重算一份
    light_extra: list[str] = []
    light_names = {k for k, _ in light}
    for name, value in dark:
        if name in light_names:
            continue
        if "color-mix(" in value:
            light_extra.append(
                f"{name}: {squash(convert_literals(convert_mixes(value, light_table)))};"
            )
    light_mix_lines = light_mixes + light_extra

    out: list[str] = []
    # 探测值必须写成「数字」形式：oklch(0% 0% 0%) 的色相是百分比，本身就不合法，
    # 会把条件永远判成「不支持」，现代引擎也会吃到这层兜底。
    out.append("@supports not (color: oklch(0 0 0)) {")
    out += wrap(":root", dark_colors, "  ")
    out += wrap(":root[data-theme='light']", light_colors, "  ")
    out.append("}")
    out.append("")
    out.append("@supports not (background-color: color-mix(in oklch, #000 10%, transparent)) {")
    out += wrap(":root", dark_mixes, "  ")
    out += wrap(":root[data-theme='light']", light_mix_lines, "  ")
    out.append("}")
    return "\n".join(out) + "\n"


def main() -> int:
    css = read_css()
    if START not in css or END not in css:
        raise SystemExit(f"app.css 里找不到生成标记：{START} / {END}")
    head, rest = css.split(START, 1)
    _, tail = rest.split(END, 1)
    block = build(css)
    updated = f"{head}{START}\n{block}{END}{tail}"
    if "--check" in sys.argv:
        if updated != css:
            print("srgb 兜底与令牌不一致，请运行：python3 tools/srgb-fallback.py", file=sys.stderr)
            return 1
        print("srgb 兜底是最新的")
        return 0
    CSS_PATH.write_text(updated, encoding="utf-8")
    print(f"已写入 {CSS_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
