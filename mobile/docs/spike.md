# P4 Spike 结论（Lynx 4.2.0 在 iOS 上跑通）

日期：2026-11-16 · 设备：iPhone 16 Pro (iOS 18.5) 模拟器 · Xcode 27.2

## 已验证

| 项 | 结果 | 备注 |
|---|---|---|
| Lynx 4.2.0 Pod 安装 | ✅ | 13 个 pod：Lynx/LynxBase/LynxService/LynxServiceAPI/PrimJS 4.2.1/XElement 4.2.0/SDWebImage/ServalSVG… |
| 模拟器编译 | ✅ | Xcode 27.2 + 官方 `post_install` 告警降级 |
| ReactLynx bundle 加载 | ✅ | 105.7 kB，DEBUG 先试 dev server（3s 超时）再回落内置 |
| 页面渲染 | ✅ | 见 `docs/screenshots/p4-first-screen.png`（令牌色、圆角、边框都生效） |
| 设计令牌生效 | ✅ | `@tinymusic/theme/lynx.css` 的 `.tm-dark` 变量在 Lynx 里可用 |
| 构建产物打包 | ✅ | 用 Build Phase 拷贝 bundle（生成工程时文件还不存在，不能写死 file reference） |

## 已踩到并解决的坑

1. **engineVersion 不能写 4.2**：rspeedy 当前的主线程字节码编码器只支持 bundle 版本 1.0–3.9。
   宿主 Lynx 4.2.0 向后兼容，所以不显式设置 `engineVersion`。
2. **bundle 找不到**：`loadTemplate(fromURL: "main")` → 会找 `main.bundle`；正确写法是 `"main.lynx"`（拼出 `main.lynx.bundle`）。
3. **Resources 目录里没有产物**：xcodegen 生成工程时 `app/dist` 还没有 bundle，资源引用会丢；改成编译期脚本拷进 `BUILT_PRODUCTS_DIR`。
4. `color-scheme` 属性 Lynx 模板编码器不认，生成令牌时已剔除。

## 待办（P4 剩余）

- 安全区：首屏标题现在压在状态栏下面，需要用 `safeAreaTop` 做 padding（原生注入 globalProps）。
- `TmBackend`：把 `crates/ffi` 编成 `aarch64-apple-ios-sim` 静态库，Swift 侧 `tm_start` 起后端并把 `apiBase/token` 注入 initData。
- `<svg content>` 图标方案验证（Hugeicons → SVG 字符串）。
- XElement `blur-view` 观感验证（玻璃质感）。
