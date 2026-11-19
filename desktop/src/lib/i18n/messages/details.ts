/** 详情页、账号、列表与右键菜单的英文译文。 */
export const details: Record<string, string> = {
  // ---- 详情页：曲目 ----
  '返回上一级': 'Back',
  '播放': 'Play',
  '不可播放': 'Not available',
  '会员曲目': 'Members-only track',
  '这条信息来自搜索接口的': 'The search API reports this through the',
  // 键里的空格来自原文换行（浏览器折叠成一个空格），删掉中文就会变
  '字段。本客户端会通过资源管理链路取直链， 未登录也能完整播放；上面的探测器可以直接验证每一档实际能拿到什么格式。':
    'field. The app resolves the direct link through the resource-management route, so the track plays in full even when you are signed out; the probes above show exactly which format each tier returns.',
  '未登录状态下，酷我服务端对会员专享曲目可能只下发约 11 秒的占位片段。':
    "When signed out, the Kuwo server may return only an ~11-second placeholder clip for members-only tracks.",
  '下载这首歌（含歌词与封面）': 'Download this song (with lyrics and cover art)',
  '复制歌曲 ID': 'Copy song ID',
  '已复制歌曲 ID': 'Song ID copied',
  '测 {label}': 'Test {label}',
  '大小未知': 'Size unknown',
  '（已降级）': ' (degraded)',
  '（未校验）': ' (unverified)',
  '资源链路': 'Media route',
  '直连': 'Direct',
  '✘ {quality} 不可用（{err}）': '✘ {quality} unavailable ({err})',
  '加载歌词': 'Loading lyrics',
  '歌词获取失败（详情接口易限流，不影响播放）':
    "Couldn't load lyrics (the detail API is rate-limited; playback is unaffected)",
  '暂无歌词': 'No lyrics',

  // ---- 详情页：专辑 / 艺人 / 歌单 ----
  'tab|歌曲': 'Songs',
  'tab|专辑': 'Albums',
  '{n} 首': '{n} tracks',
  '{n} 首曲目 · {m} 张专辑': '{n} songs · {m} albums',
  '{n} 播放': '{n} plays',
  '{n} 分钟': '{n} min',
  '收起简介': 'Show less',
  '展开简介': 'Show more',
  '这个歌单没有可显示的曲目': 'This playlist has no tracks to show',
  // 同上：第二个空格来自原文换行
  '若提示不可见，可能是私密歌单或已被删除。酷我的账号歌单需要登录后才能列出， 本客户端目前只支持公开歌单。':
    "If it says the playlist isn't visible, it may be private or has been deleted. Kuwo account playlists require signing in to list, so the app only supports public playlists.",

  // ---- 列表行 ----
  '暂停': 'Pause',
  '继续播放': 'Resume',
  '无损': 'Lossless',
  '本曲有无损 FLAC': 'This track is available in lossless FLAC',
  '仅试听': 'Preview only',
  '不可用': 'Unavailable',
  '未知艺人': 'Unknown artist',
  '热度 {n}': 'Popularity {n}',
  '热度未知': 'Popularity unknown',
  '已取消喜欢': 'Removed from Favorites',
  '已收藏到网盘': 'Saved to Favorites',
  '取消喜欢': 'Remove from Favorites',
  '喜欢（收藏到网盘）': 'Favorite (save to cloud)',
  '网盘文件': 'Cloud file',
  '网盘文件已在云端': 'This file is already in cloud storage',
  '正在下载': 'Downloading',
  '下载（含歌词与封面）': 'Download (with lyrics & cover)',

  // ---- 账号 ----
  '酷我音乐': 'Kuwo Music',
  '网易云音乐': 'NetEase Music',
  '查看账号歌单': 'View account playlists',
  '查看每日推荐': 'View daily recommendations',
  '登录': 'Sign in',
  '登出': 'Sign out',
  '正在打开…': 'Opening…',
  '等待登录…': 'Waiting for sign-in…',
  '在应用内打开网易云网页完成登录': 'Open the NetEase page in the app to sign in',
  '已登录网易云：{name}': 'Signed in to NetEase: {name}',
  '已登出网易云': 'Signed out of NetEase',
  '登录超时：窗口已关闭或未完成登录':
    "Sign-in timed out: the window was closed or sign-in wasn't completed",

  // ---- 账号歌单 ----
  '账号歌单': 'Account playlists',
  '还没有登录': 'Not signed in yet',
  '去登录': 'Sign in',
  '登录只用于把平台歌单导入网盘。先到「网盘」页启用网盘配置。':
    'Signing in is only used to import provider playlists to cloud storage. Turn on cloud storage on the Cloud page first.',
  '这个账号还没有歌单': 'This account has no playlists yet',
  '打开歌单': 'Open playlist',
  '一键导入到网盘': 'Import to cloud',
  '复制歌单 ID': 'Copy playlist ID',
  '已复制歌单 ID': 'Playlist ID copied',
  '把歌单 {name} 导入到网盘': 'Import playlist {name} to cloud',
  '导入歌单到网盘': 'Import playlist to cloud',
  '导入到网盘': 'Import to cloud',
  '{name} · {n} 首 · 逐首下载后上传':
    '{name} · {n} tracks · downloaded one by one, then uploaded',
  '网盘歌单（目标目录）': 'Cloud playlist (destination folder)',
  '目标歌单名称': 'Playlist name',
  '文件会存到': 'Files are saved under',
  '前缀/歌单名/': 'prefix/playlist-name/',
  '下，包含内嵌封面的音频、同名 .lrc 与封面图。':
    'with audio that embeds the cover, a matching .lrc file and a cover image.',
  '加入队列后可以直接关掉弹窗，不需要在这里等；进度和结果在页面顶部的「导入队列」里看。':
    'Once it is in the queue you can close this dialog; progress and results show in the import queue at the top of the page.',
  '加入导入队列': 'Add to import queue',
  '已加入导入队列': 'Added to import queue'
};
