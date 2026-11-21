<script lang="ts">
  import { onMount } from 'svelte';
  import { t } from './lib/i18n.svelte';
  import { HugeiconsIcon } from '@hugeicons/svelte';
  import appLogo from '../src-tauri/icons/128x128.png';
  import { listen } from '@tauri-apps/api/event';
  import { icons, ICON_SIZE } from './lib/icons';
  import { router, go } from './lib/router.svelte';
  import { api } from './lib/api';
  import { updateState, checkUpdatesSilently } from './lib/update.svelte';
  import {
    player,
    bindAudio,
    restoreVolume,
    onEnded,
    toggle,
    loadQualityCapabilities,
    setPreferredQuality,
    refreshTrackQualities,
    fallbackFromLossless,
    next,
    prev,
    syncPlayback,
    persistPlayback,
    consumePendingSeek,
    clearPendingSeek,
    recoverSource,
    maybeCachePlayback,
  } from './lib/player.svelte';
  import PlayerBar from './components/PlayerBar.svelte';
  import EqualizerDialog from './components/EqualizerDialog.svelte';
  import TitleBar from './components/TitleBar.svelte';
  import WindowControls from './components/WindowControls.svelte';
  import DownloadDialog from './components/DownloadDialog.svelte';
  import DownloadFailures from './components/DownloadFailures.svelte';
  import S3IntegrityDialog from './components/S3IntegrityDialog.svelte';
  import ErrorNotice from './components/ErrorNotice.svelte';
  import { addFailures, loadFailures } from './lib/downloadFailures.svelte';
  import type { FailedDownload } from './lib/api';
  import ContextMenu from './components/ContextMenu.svelte';
  import Toast from './components/Toast.svelte';
  import Track from './routes/Track.svelte';
  import Downloads from './routes/Downloads.svelte';
  import Local from './routes/Local.svelte';
  import { createLocalFolder, deleteLocalFolder, initializeLocalFolders, localFolders, renameLocalFolder } from './lib/localFolders.svelte';
  import Library from './routes/Library.svelte';
  import Settings from './routes/Settings.svelte';
  import Cloud from './routes/Cloud.svelte';
  import Lyrics from './routes/Lyrics.svelte';
  import { appCfg, isCloudProvider, refreshAppCfg } from './lib/config.svelte';
  import {
    bindEqualizerAudio,
    equalizer,
    prepareEqualizerForPlay,
    setEqualizerVolume,
  } from './lib/equalizer.svelte';
  import { showToast } from './lib/toast.svelte';

  // 自绘标题栏只出现在 Windows + Tauri（见 main.ts 的 data-chrome）
  const customChrome = document.documentElement.dataset.chrome === 'custom';

  let audio = $state<HTMLAudioElement | null>(null);
  let mainEl = $state<HTMLElement | null>(null);

  // 侧边栏选中背景：位置跟着当前菜单滑动
  let asideEl = $state<HTMLElement | null>(null);
  let indTop = $state(0);
  let indH = $state(0);
  let indShow = $state(false);
  let indReady = $state(false);

  function measureNav() {
    const aside = asideEl;
    if (!aside) return;
    const btn = aside.querySelector<HTMLElement>('button.on');
    if (!btn) {
      indShow = false;
      return;
    }
    const ar = aside.getBoundingClientRect();
    const br = btn.getBoundingClientRect();
    const list = btn.closest('.local-folder-list')?.getBoundingClientRect();
    const top = list ? Math.max(br.top, list.top) : br.top;
    const bottom = list ? Math.min(br.bottom, list.bottom) : br.bottom;
    if (bottom <= top) {
      indShow = false;
      return;
    }
    indTop = top - ar.top;
    indH = bottom - top;
    indShow = true;
  }

  $effect(() => {
    // 依赖当前菜单和「喜欢」是否出现（导航项数量会变）
    activeNav;
    appCfg.s3Enabled;
    localFolders.items.length;
    creatingFolder;
    editingFolder;
    const raf = requestAnimationFrame(() => {
      measureNav();
      if (!indReady) requestAnimationFrame(() => (indReady = true));
    });
    return () => cancelAnimationFrame(raf);
  });

  // 路由变化时把主区域滚回顶部。
  $effect(() => {
    router.route.name;
    mainEl?.scrollTo({ top: 0 });
  });

  let bootErr = $state('');

  /** 播放失败：FLAC 不被 WebView 支持时自动退回 320k，其余错误照实显示 */
  async function handlePlayError(err: unknown) {
    const name = (err as DOMException)?.name;
    if (name === 'NotSupportedError' && (await fallbackFromLossless())) {
      showToast(t('当前系统不支持 FLAC，已切到 320k'));
      player.error = '';
      return;
    }
    // 直链过期也会以 NotSupportedError / 空源的形式冒出来，先换一条新直链试一次
    if (await recoverSource()) {
      player.error = '';
      return;
    }
    player.error = t('播放失败：{err}', { err: String(err) });
    player.status = 'error';
    player.playing = false;
  }

  onMount(() => {
    void initializeLocalFolders().catch((error) => showToast(String(error)));
    restoreVolume();
    void loadQualityCapabilities();
    if (audio) bindEqualizerAudio(audio);
    // 音质以后端设置为准；旧 localStorage 只做一次性迁移（high 实际是 128k）
    import('./lib/api').then(async ({ api: a }) => {
      try {
        const s = await a.settingsGet();
        const legacy = localStorage.getItem('quality');
        if (legacy) {
          const mapped = legacy === 'high' ? 'standard' : legacy;
          try {
            await a.qualitySet(mapped as never);
            setPreferredQuality(mapped);
          } catch {
            setPreferredQuality(s.default_quality);
          }
          localStorage.removeItem('quality');
        } else {
          setPreferredQuality(s.default_quality);
        }
      } catch {
        /* 后端不可用时保持默认 */
      }
    });
    if (player.current) void refreshTrackQualities(player.current);
    refreshAppCfg().then(() => {
      if (appCfg.s3Enabled) api.favoritesPull().catch(() => {});
    });
    // 「页面里已经出现过真实手势」：托盘 / 自动播放不能用来建 AudioContext
    let eqGesture = false;
    bindAudio((action, value) => {
      const el = audio;
      if (!el) return;
      switch (action) {
        case 'load':
          el.src = player.src;
          el.load();
          break;
        case 'play':
          // 均衡器已开启时必须先建链 / 把 AudioContext 拉回 running；
          // 建链要发生在用户手势里，所以播放动作是最后一道保险。
          if (prepareEqualizerForPlay(eqGesture) === 'failed') {
            showToast(t('均衡器在当前系统不可用，已关闭'));
          }
          el.play().catch((e) => void handlePlayError(e));
          break;
        case 'pause':
          el.pause();
          break;
        case 'seek':
          // 恢复的上次记录还没取流时拖动进度：只更新 UI，等 play 时再落到 audio
          if (!el.src) break;
          try {
            el.currentTime = value ?? 0;
          } catch {
            /* metadata 还没就绪时忽略 */
          }
          break;
      }
    });

    // 存档里均衡器是开着的时候，第一次点击 / 按键就建链并解锁 AudioContext。
    // 浏览器只允许在用户手势里恢复音频上下文，不能等到 play 的异步回调。
    let eqUnlocked = false;
    const unlockEq = () => {
      if (eqUnlocked) return;
      eqUnlocked = true;
      eqGesture = true;
      if (prepareEqualizerForPlay() === 'failed') {
        showToast(t('均衡器在当前系统不可用，已关闭'));
      }
      document.removeEventListener('pointerdown', unlockEq, true);
      document.removeEventListener('keydown', unlockEq, true);
    };
    document.addEventListener('pointerdown', unlockEq, true);
    document.addEventListener('keydown', unlockEq, true);

    // 下载任务结束且留下失败项 → 弹窗让用户手动重试
    let unlistenFailures: (() => void) | undefined;
    listen<FailedDownload[]>('download://failed', (e) => addFailures(e.payload))
      .then((fn) => (unlistenFailures = fn))
      .catch(() => {
        /* 非 Tauri 环境（纯浏览器调试）忽略 */
      });
    // 上次没处理完的失败记录：下载页入口用得上
    void loadFailures();

    // 托盘菜单 → 前端动作
    let unlisten: (() => void) | undefined;
    listen<string>('tray://action', (e) => {
      switch (e.payload) {
        case 'toggle':
          toggle();
          break;
        case 'next':
          next();
          break;
        case 'prev':
          prev();
          break;
      }
    })
      .then((fn) => (unlisten = fn))
      .catch(() => {
        /* 非 Tauri 环境（纯浏览器调试）忽略 */
      });

    const saveRecord = () => {
      if (audio) player.progress = audio.currentTime;
      persistPlayback(true);
    };
    const onVisibility = () => {
      if (document.hidden) saveRecord();
    };
    window.addEventListener('pagehide', saveRecord);
    window.addEventListener('beforeunload', saveRecord);
    document.addEventListener('visibilitychange', onVisibility);

    // 静默更新检查：启动后隔一会儿查一次（别和首屏抢网络），之后每 6 小时再看一眼
    const firstCheck = setTimeout(() => void checkUpdatesSilently(), 2500);
    const updateTimer = setInterval(() => void checkUpdatesSilently(), 6 * 60 * 60 * 1000);

    return () => {
      unlisten?.();
      unlistenFailures?.();
      clearTimeout(firstCheck);
      clearInterval(updateTimer);
      document.removeEventListener('pointerdown', unlockEq, true);
      document.removeEventListener('keydown', unlockEq, true);
      window.removeEventListener('pagehide', saveRecord);
      window.removeEventListener('beforeunload', saveRecord);
      document.removeEventListener('visibilitychange', onVisibility);
    };
  });

  // 音量同步：均衡器建链后，音量交给链尾的增益节点，元素自身保持 1，
  // 避免不同 WebView 对 MediaElementAudioSourceNode 的音量处理不一致。
  $effect(() => {
    if (!audio) return;
    const routed = equalizer.graphReady;
    setEqualizerVolume(player.volume);
    audio.volume = routed ? 1 : player.volume;
  });

  // 侧边栏按 Apple Music 的分组方式排：顶部单项、资料库、其他、底部账号
  //
  // 「喜欢」存到网盘，只有网盘启用时才出现
  const navLibrary = $derived([
    ...(appCfg.s3Enabled ? [{ name: 'library', label: t('喜欢'), icon: icons.favorite }] : []),
    { name: 'downloads', label: t('下载'), icon: icons.downloadDir },
  ]);
  const navOther = $derived([{ name: 'settings', label: t('设置'), icon: icons.settings }]);

  let creatingFolder = $state(false);
  let folderName = $state('');
  let folderInput = $state<HTMLInputElement>();

  $effect(() => {
    if (creatingFolder) folderInput?.focus();
  });

  let savingFolder = $state(false);
  let editingFolder = $state<string>();
  let renamedFolder = $state('');
  let renameInput = $state<HTMLInputElement>();

  $effect(() => {
    if (editingFolder && renameInput) {
      renameInput.focus();
      renameInput.select();
    }
  });

  function editFolder(id: string, name: string) {
    if (savingFolder) return;
    renamedFolder = name;
    editingFolder = id;
  }

  async function saveFolderName(event: SubmitEvent, id: string) {
    event.preventDefault();
    const name = renamedFolder.trim();
    if (!name || savingFolder) return;
    savingFolder = true;
    try {
      await renameLocalFolder(id, name);
      editingFolder = undefined;
      if (activeFolder === id) go({ name: 'local', folderId: name });
    } catch (error) {
      showToast(String(error));
    } finally {
      savingFolder = false;
    }
  }

  async function removeFolder(id: string) {
    if (savingFolder) return;
    savingFolder = true;
    try {
      await deleteLocalFolder(id);
      if (editingFolder === id) editingFolder = undefined;
      if (activeFolder === id) go({ name: 'local' });
    } catch (error) {
      showToast(String(error));
    } finally {
      savingFolder = false;
    }
  }

  async function addFolder(event: SubmitEvent) {
    event.preventDefault();
    if (!folderName.trim() || savingFolder) return;
    savingFolder = true;
    try {
      const id = await createLocalFolder(folderName);
      folderName = '';
      creatingFolder = false;
      go({ name: 'local', folderId: id });
    } catch (error) {
      showToast(String(error));
    } finally {
      savingFolder = false;
    }
  }

  const navRoute = $derived(
    router.route.name === 'track'
      ? ([...router.history].reverse().find((route) => route.name === 'local') ??
        { name: router.route.track.provider === 'local' ? 'local' : 'cloud' })
      : router.route
  );
  const activeFolder = $derived(navRoute.name === 'local' && 'folderId' in navRoute ? navRoute.folderId : undefined);
  const activeNav = $derived(activeFolder ?? navRoute.name);
</script>

<svelte:window onresize={measureNav} />

<div class="app">
  {#if customChrome}
    <TitleBar />
  {/if}
  <aside bind:this={asideEl}>
    <span
      class="nav-ind"
      class:show={indShow}
      class:ready={indReady}
      style="top: {indTop}px; height: {indH}px"
    ></span>
    <!-- macOS 使用 Overlay 标题栏：给红绿灯留位置，并让这块区域可以拖动窗口 -->
    <div class="titlebar-drag" data-tauri-drag-region aria-hidden="true"></div>
    <div class="brand">
      <img class="logo" src={appLogo} alt="" width="26" height="26" />
      <span>TinyMusic</span>
    </div>
    <nav class="side-nav">
      <!-- 必须按 name 做 key：features 异步加载后导航项会插队，
           不 key 的话 Svelte 会复用按钮，HugeiconsIcon 的 icon 属性不跟随更新，
           结果「喜欢」显示成下载图标、「下载」和「设置」都显示齿轮。 -->
      {#each navLibrary as n (n.name)}
        <button class:on={activeNav === n.name} onclick={() => go({ name: n.name } as never)}>
          <span class="ico"><HugeiconsIcon icon={n.icon} size={ICON_SIZE.control} /></span>{n.label}
        </button>
      {/each}
      <div class="nav-sep local-sep" aria-hidden="true"></div>
      <button class:on={activeNav === 'cloud'}
        aria-current={activeNav === 'cloud' ? 'page' : undefined}
        onclick={() => go({ name: 'cloud' })}>
        <span class="ico"><HugeiconsIcon icon={icons.cloud} size={ICON_SIZE.control} /></span>{t('网盘')}
      </button>
      <div class="local-nav-row" class:local-active={activeNav === 'local'}>
        <button class="local-nav-link" class:on={activeNav === 'local'}
          aria-current={activeNav === 'local' ? 'page' : undefined}
          onclick={() => go({ name: 'local' })}>
          <span class="ico"><HugeiconsIcon icon={icons.music} size={ICON_SIZE.control} /></span>{t('本地')}
        </button>
        <button class="local-nav-add" type="button" title={t('新建收藏夹')}
          aria-label={t('新建收藏夹')} aria-expanded={creatingFolder}
          onclick={() => (creatingFolder = !creatingFolder)}>
          <HugeiconsIcon icon={icons.plus} size={ICON_SIZE.control} />
        </button>
      </div>
      {#if creatingFolder}
        <form class="local-folder-form" onsubmit={addFolder}>
          <input bind:this={folderInput} bind:value={folderName} maxlength={60}
            placeholder={t('收藏夹名称')} aria-label={t('收藏夹名称')}
            onkeydown={(event) => { if (event.key === 'Escape') creatingFolder = false; }} />
          <button type="submit" aria-label={t('新建收藏夹')} disabled={!folderName.trim() || savingFolder}>
            <HugeiconsIcon icon={icons.plus} size={ICON_SIZE.inline} />
          </button>
        </form>
      {/if}
      {#if localFolders.items.length}
        <div class="local-folder-list" onscroll={measureNav}>
          {#each localFolders.items as folder (folder.id)}
            <div class="local-folder-row">
              {#if editingFolder === folder.id}
                <form class="local-folder-form local-folder-rename" onsubmit={(event) => saveFolderName(event, folder.id)}>
                  <input bind:this={renameInput} bind:value={renamedFolder} maxlength={60}
                    aria-label={t('重命名收藏夹')} disabled={savingFolder}
                    onkeydown={(event) => { if (event.key === 'Escape') editingFolder = undefined; }} />
                </form>
              {:else}
                <button class="local-folder" class:on={activeNav === folder.id} title={folder.name}
                  aria-current={activeNav === folder.id ? 'page' : undefined}
                  onclick={() => go({ name: 'local', folderId: folder.id })}
                  ondblclick={() => editFolder(folder.id, folder.name)}
                  onkeydown={(event) => {
                    if (event.key === 'F2') {
                      event.preventDefault();
                      editFolder(folder.id, folder.name);
                    }
                  }}>
                  <span class="ico"><HugeiconsIcon icon={icons.folder} size={ICON_SIZE.control} /></span>
                  <span class="folder-name">{folder.name}</span>
                </button>
              {/if}
              <button class="folder-delete" type="button" disabled={savingFolder}
                title={t('删除收藏夹 {name}', { name: folder.name })}
                aria-label={t('删除收藏夹 {name}', { name: folder.name })}
                onclick={() => removeFolder(folder.id)}>
                <HugeiconsIcon icon={icons.trash} size={ICON_SIZE.inline} />
              </button>
            </div>
          {/each}
        </div>
      {/if}
    </nav>
    <nav class="side-settings" aria-label={t('设置')}>
      {#each navOther as n (n.name)}
        <button class:on={activeNav === n.name} onclick={() => go({ name: n.name } as never)}>
          <span class="ico"><HugeiconsIcon icon={n.icon} size={ICON_SIZE.control} /></span>{n.label}
          <!-- 静默检查到新版才出现的一颗小红点，不写版本号、不闪 -->
          {#if n.name === 'settings' && updateState.version}
            <span
              class="nav-dot"
              title={t('有新版本 {version}，点进来更新', { version: updateState.version })}
            ></span>
          {/if}
        </button>
      {/each}
    </nav>
  </aside>

  <main bind:this={mainEl} class:no-player={!player.current}>
    {#if bootErr}<ErrorNotice text={bootErr} />{/if}
    {#if router.route.name === 'track'}
      <Track />
    {:else if router.route.name === 'downloads'}
      <Downloads />
    {:else if router.route.name === 'local'}
      <Local folderId={router.route.folderId} />
    {:else if router.route.name === 'library'}
      <Library />
    {:else if router.route.name === 'settings'}
      <Settings />
    {:else if router.route.name === 'cloud'}
      <Cloud />
    {/if}
  </main>

  <footer>
    <PlayerBar />
  </footer>

  {#if player.lyricsOpen && player.current}
    <Lyrics />
  {/if}

  <DownloadDialog />
  <DownloadFailures />
  <S3IntegrityDialog />
  <EqualizerDialog />
  <ContextMenu />
  <Toast />

  <!-- 窗口按钮浮在所有浮层之上：歌词页全屏盖住时也关得掉窗口 -->
  {#if customChrome}
    <WindowControls />
  {/if}

  <!-- 隐藏的音频元素：真正的解码/播放器 -->
  <audio
    bind:this={audio}
    crossorigin="anonymous"
    ontimeupdate={(e) => {
      const a = e.currentTarget as HTMLAudioElement;
      player.progress = a.currentTime;
      maybeCachePlayback(a);
      persistPlayback();
    }}
    onloadedmetadata={(e) => {
      const a = e.currentTarget as HTMLAudioElement;
      const duration = isFinite(a.duration) && a.duration > 0 ? a.duration : 0;
      if (duration > 0) player.duration = duration;

      // 恢复上次进度：等 metadata 就绪后再 seek，然后播放
      const seekTo = consumePendingSeek();
      if (seekTo != null) {
        const target = duration > 0 ? Math.min(seekTo, Math.max(0, duration - 0.5)) : seekTo;
        try {
          a.currentTime = target;
        } catch {
          /* ignore */
        }
        player.progress = target;
        a.play().catch((err) => void handlePlayError(err));
      }
      persistPlayback(true);
    }}
    onended={() => {
      onEnded();
      persistPlayback(true);
    }}
    onerror={() => {
      clearPendingSeek();
      // 挂掉的直链（缓存里的旧地址、代理 token 过期）先自动换一条再续播，
      // 只有重试过了还失败才把错误摆到播放条上。
      void recoverSource().then((retried) => {
        if (retried) return;
        const what =
          player.current?.provider === 'local'
            ? t('本地文件可能已移动或格式不受支持')
            : isCloudProvider(player.current?.provider)
            ? t('网盘文件可能已被删除或直链过期')
            : t('直链可能已过期');
        if (player.src) player.error = t('音频加载失败（{what}）', { what });
        player.status = 'error';
        player.playing = false;
      });
    }}
    onplay={() => syncPlayback('playing')}
    onpause={(e) => {
      player.progress = (e.currentTarget as HTMLAudioElement).currentTime;
      syncPlayback('paused');
      persistPlayback(true);
    }}
  ></audio>
</div>
