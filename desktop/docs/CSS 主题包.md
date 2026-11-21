# TinyMusic CSS 主题包

把 [主题包模板](主题包模板/) 里的 `config.json`、`index.css` 和 `imgs/` 一起压缩为 `.zip`，让两个入口文件位于压缩包根目录。在「设置 → 外观」将主题切到「自定义」，再导入和选择主题包。

- `config.json` 填写 `formatVersion: 1`、唯一的 `id`、显示名称 `name`、版本 `version` 和可选的 `author`。可通过 `appearance` 选择 `light` 或 `dark`，省略时使用深色。相同 ID 再次导入会替换旧版。
- `index.css` 用 `:root` 写通用值。与主题包 `appearance` 对应的 `:root[data-theme='light']` 或 `:root[data-theme='dark']` 可以覆盖通用值。
- 颜色变量支持 `--background`、`--foreground`、`--fg2`、`--fg3`、`--bg2`、`--popover`、`--brand` 和 `--line`。背景用 `--bg-image: url("@/imgs/dusk.png")`，支持包内 PNG、JPG 和 WebP。可用 `--bg-tint` 指定背景图片的遮罩颜色。资源路径用字母、数字、连字符、下划线和点。
- 主题包只应用名单里的颜色和背景声明。组件选择器、脚本、iframe、外链资源和 `@import` 不参与渲染。每包最多 8 MiB 解压内容，最多 64 个条目。
- `--bg-effect: petals` 可开启内置的落樱动画。开启系统的减少动态效果后，只显示静态背景。
- 切换到内置主题后，再回到「自定义」即可恢复原来的主题包和背景。选择「应用外观」可使用自定义背景。主题包和选中状态仅保存在本机。

安装版默认把原始 ZIP 保存在软件旁边的 `theme/`；macOS 使用应用包所在文件夹。软件目录无法写入时使用应用配置目录下的 `theme/`，Windows 上通常为 `%APPDATA%\com.tinymusic.app\theme`。启动时会把原配置目录里的 ZIP 复制到可写的软件目录，保留原包。连接前端开发服务器的构建使用独立的配置目录 `dev/theme/`，开发版和安装版各自保存选中记录。

[星夜](主题包示例/night-star/)使用静态背景，[樱花](主题包示例/sakura/)使用静态底图和落樱动画。两个示例可按页首的目录规则打包导入。

安装包、两个示例和 MusicFree 静态主题合集见 [GitHub Releases](https://github.com/276179395/TinyMusic/releases/latest)。合集包含 27 套图片背景、6 套纯色和 2 套渐变。先解压合集，再在 TinyMusic 里逐个导入内层 ZIP。包内保留原作者与来源链接，完整名单见合集中的 `catalog.md`。
