# SwiftUI 性能审计 · TinyMusic iOS（iOS 18–26, Swift 6）

日期：2026-11-19（r3）· 范围：`tinymusic/ios/Sources`（约 5.8k 行 Swift）· 方法：代码审查 + 本机微基准 + 构建/测试验证

> r3 = 审计结论 + **已落地的修复**。修复前的版本（r2）里对问题的判断仍然成立，
> 但下面「已修复」表取代了 r2 的「下一步」。
> 唯一一条被**主动放弃**的实现见文末，并说明了原因。

## 摘要

问题不是零散的性能小毛病，而是一条固定的放大器链路：

```
播放器 0.25 s tick ─┐
                    ├─→ 一个 @Observable 属性变化 ─→ 整棵子树 body 重算 ─→ 里面还有 I/O 和解析
下载进度 4 Hz 合流 ─┘
```

核心判断：**`@Observable` 的依赖粒度是「属性」，不是字典的 key**。所以
「每一行只关心自己那首歌的进度」这个意图，放在 `[String: Double]` 里根本没有被表达出来。

修复按「先削订阅宽度、再削单点」进行。所有改动都不改变 JSON 契约、不改界面文案、不动桌面端。

## 已修复

| # | 问题 | 改法 | 位置 |
| --- | --- | --- | --- |
| 1 | 播放页整个 body 挂在 0.25 s 的 `position` 上 | 抽出 `PlayerProgressRow`，**并把它里面的 `.onChange(of: player.position)` 一起搬走**——这一步是 r2 漏掉的，漏了就等于没拆 | `NowPlayingView.swift` |
| 2 | `updateNowPlaying()` 每 250 ms 跨进程写一次 | 从定时器里删掉；改为在 play/pause/seek/切歌/中断/拔耳机/远程命令时推一次 | `PlayerEngine.swift` |
| 3 | 下载进度是「整张字典」一个依赖 | 每 key 一个 `CacheProgress` 盒子（`@Observable`），字典本身 `@ObservationIgnored`；聚合进度抽成 `CacheProgressHeader`，不让它把每一行重新挂上去 | `CacheStore.swift`、`TrackRow.swift`、`PlaylistView.swift`、`CacheView.swift`、`FavoritesView.swift` |
| 4 | body 里 `FileManager.fileExists` | `isCached`/`coverURL` 改成纯内存查表；`localURL` 保留 stat（它只在真正播放时调一次，用于「文件被系统清掉就退回流播放」） | `CacheStore.swift` |
| 5 | `isFavorite` 是 O(F) 且每次归一化字符串 | 维护 `favoriteKeyIndex` / `favoriteIDIndex` 两个 `Set`；并在入口读一次 `favorites.count` 以保留 Observation 依赖（否则心形图标不刷新） | `LibraryStore.swift` |
| 6.1 | `updateTotal()` 每次完成都 O(n) 次 stat → 整体 O(n²) | 改为按 entry 增量维护（`entryBytes`），只 stat 这一条自己的歌词/封面 | `CacheStore.swift` |
| 6.2 | `touch()` 每播一首就整表重写索引 | 2 s 防抖落盘，进后台/切场景时 `flushSave()` 补齐 | `CacheStore.swift`、`RootView.swift` |
| 6.3 | `reconcile()` 在 `@MainActor` 的 `init` 里，每条 entry open+read 12 字节 | 拆成两步：`reconcileStatuses()`（纯内存，留在 init）和 `reconcileFiles()`（`Task.detached` 后台校验，回主 actor 应用） | `CacheStore.swift`、`AppModel.swift` |
| 7 | `CoverImage.init` 每趟父 body 都解析一次 URL | `key(for:)` 加 NSCache；`init` 变成两次缓存命中 | `CoverImage.swift` |
| 8 | 取色在主 actor 上新建 `CIContext` + 解整张封面 | `CIContext` 提成共享静态；读文件/解码/求均值搬到 `Task.detached`；先把封面缩到 32 px 再求均值 | `ArtworkPalette.swift` |
| 9 | EQ 拖动每帧 24 次本地化查表 + JSON 编码 + defaults 写 | 预设拆成 `definitions`（不含文案）与 `presets`（界面用）；`detect` / `applyPreset` 走前者；落盘 + 上云通知 300 ms 防抖 | `EQLibrary.swift`、`EQController.swift`、`EqualizerView.swift` |
| 10 | `L()` 在 `.system` 下每次都问 `Locale.preferredLanguages` | 缓存解析结果，只在 `select(_:)` 里失效 | `Localization.swift` |
| 11 | 列表身份用下标 | `PlaybackQueueView` 改 `ForEach(player.queue)`；歌词与 EQ 频段改 `indices`（不再每趟 body 新建数组） | `PlaybackQueueView.swift`、`InlineLyricsView.swift`、`EqualizerView.swift` |
| 12 | `CacheView` 每趟 body 扫 4 遍 `entries` | 合成一次遍历的 `snapshot` | `CacheView.swift` |

### 修复依据的实测数据

本机微基准（M 系列，`swift -O` 之外的默认构建，取相对量级）：

| 操作 | 单次耗时 |
| --- | --- |
| `Locale.preferredLanguages.first` | **1677 ns** |
| 字典查找（3 个 key） | 157 ns |
| `String(format: "%d:%02d")` | 1403 ns |
| `lowercased().filter { isLetter \|\| isNumber }`（中英混排歌名） | **2047 ns** |

结论：
- `Locale.preferredLanguages` 比一次字典查找贵一个数量级——第 10 条值得修，不是噪音。
- `favoriteKey` 归一化 2 µs × 收藏数 × 可见行数 × 4 Hz，是第 5 条真正的成本来源。
- 这两项都是**实测**，不是估计。

## 已删除的未使用组件

`DesignSystem/` 下有两个文件全仓库无引用（已 grep 确认，含 Tests），已 `git rm`：

| 文件 | 行数 | 说明 |
| --- | --- | --- |
| `MarqueeText.swift` | 74 | 跑马灯标签。内部是 `TimelineView(.periodic(by: 1.0/30.0))`，接进列表就是每行每秒 30 次 body 求值；而且宽度测量只写在「不溢出」那一支里，列表行复用换标题后滚动距离会算错。 |
| `PlaybackSlider.swift` | 52 | 被 `SeekBar` 取代的旧进度条（`GeometryReader` 版，在 VStack 里会被撑满）。 |

删除而不是优化：它们**不在视图树里，渲染 0 帧**，优化的收益是 0。
之前留着是因为「也许以后要接」，但留着就等于把一个 30 Hz + 测量 bug 的陷阱放在仓库里等人踩。

> 如果以后确实需要跑马灯，按这点重写约 40 行即可：无条件测量容器宽与文本宽、
> `text` 变化时重置相位、滚动动画交给 `phaseAnimator`（而不是 `TimelineView`）。

## 仍然没做

- `LibraryView.swift:18-20`：离线模式下 `playlists` 每次都重算 `cache.cachedPlaylists`
  （全表分组 + 每组一次 `coverURL` + 两次排序）。现在 `coverURL` 已经不打盘了，
  剩下的是纯内存分组，量级小了一个数量级，暂时不值得为它引入缓存失效逻辑。
- `ProgressRing` 的 `.animation(.linear(duration: 0.35), value: progress)` 在 4 Hz 下一直重定向。
  视觉上是平滑的，成本可接受，知道它在跑就行。
- `MainTabView` 的四份 `MiniPlayer` 保持原样：改成外层一份会压到 iOS 26 的悬浮 tab bar
  （代码注释里写明了）。第 4 条把 `entries` 依赖摘掉之后，这四条已经不贵了。

## 复查（同日，自查 diff）

抓到一处**我自己引入的回归**，已修：

`updateNowPlaying()` 从 0.25 s 定时器里删掉之后，锁屏 / 控制中心拿不到
`MPMediaItemPropertyPlaybackDuration` 了。原因是 `duration` 是**异步就绪**的：
切歌时先推的那一次里 `duration` 还是 0（`load()` 会把它清 0），于是 `nowPlayingInfo` 里没有总时长，
而之后再也没有推送 —— 进度条就只剩一个不能拖的圆点。
原来靠 4 Hz 的定时器在 250 ms 内补上，删掉之后这个补位也没了。

修法：在定时器里判断「时长第一次拿到」（`duration <= 0` → 有值），只在那一下补推一次，每首歌一次。
见 `PlayerEngine.swift:67-79`。

## 验证

| 项 | 结果 |
| --- | --- |
| `./scripts/build.sh`（clean build） | **BUILD SUCCEEDED**，0 error；1 条**既有** warning 在 `CacheManager.swift:175`（`if let cover: String? = try? ...` 多一层 optional），不在本次改动范围内，语义正确故未动（`SWIFT_STRICT_CONCURRENCY=complete` + `-swift-version 6`） |
| `./scripts/test.sh` | **33 tests / 7 suites 全绿**（含 `EQTests`、`LocalizationTests`——正好覆盖第 9、10 条） |
| UI 测试（8 个用例逐个跑） | **全部通过**：启动、歌词页+侧滑返回、队列弹窗、缓存页、播放页、语言即时切换、设置页、均衡器弹窗 |

覆盖到的改动：播放页拆分（`testPlayerShowsTransport`）、歌词 `indices`（`testLyricsSwipeBack`）、
队列身份（`testMiniPlayerOpensQueueSheet`）、缓存页 snapshot（`testCacheTabShowsOfflineCache`）、
EQ 预设（`testEQSheetOpens`）、**语言缓存失效**（`testLanguageSwitchesImmediatelyWithoutRestart`）、
启动路径（`testLaunchWithStubShowsLibrary`）。

> 说明：全量跑整套 UI 时，语言用例失败过一次（`Failed to tap "settings.language" ... no longer
> valid after interruption handling`——XCUITest 经典的元素失效），单独重跑 2/2 通过。
> 判断是整套连跑时上一个用例的 App 重启造成的既有 flaky，与本次改动无关。

## 指标

改动是**按代码推断做的，没有运行期证据**。下面这些必须由你采一次才有数：

| 指标 | 改前 | 改后 | 对应 |
| --- | --- | --- | --- |
| 播放页静止 10 s 的 View Body 次数 | 待测 | 待测 | 1 |
| 播放时 `MPNowPlayingInfoCenter` 相关帧 | 待测 | 应为 0 | 2 |
| 缓存 20 首过程中 View Body 次数 | 待测 | 待测 | 3 |
| 缓存 20 首过程中 `stat` 调用数 | 待测 | 待测 | 4、6.1 |
| 长歌单 fling 滚动掉帧 | 待测 | 待测 | 3、4、5 |
| 切歌瞬间的最长 hang | 待测 | 待测 | 8 |
| 缓存 500 首时的冷启动时间 | 待测 | 待测 | 6.3 |

## 采集单

- **Release 构建，真机**（ProMotion 设备最能暴露第 1、2 条）。
- Instruments 选 **SwiftUI 模板**，同时开 **Time Profiler** 和 **Hangs**。
- 四段独立录制，一段只做一件事：
  1. 播放并**停在播放页**静止 10 秒；
  2. 在 200+ 首的歌单里缓存 20 首，停在歌单页 20 秒；
  3. 长歌单里快速 fling 滚动 10 秒；
  4. 冷启动一次到首帧（先缓够 500 首）。
- 导出 trace（或 SwiftUI 泳道 + Time Profiler 调用树截图），附设备型号 / iOS 版本 / 构建配置。
